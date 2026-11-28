extends RefCounted
## bone_anim.gd — B-82: animacoes PROCEDURAIS de atividade (NPC e protagonista).
##
## Por que existe: os arquivos do repositorio trazem SO parado/andar/correr. Nao
## existe clipe de celular, de conversa, de olhar o mar, de atender o balcao, de
## soco nem de dano — e o que se via na tela era o NPC parado numa pose fixa (ou
## o corpo inteiro tombando como uma tabua, quando atropelado). Em vez de baixar
## mais um pacote de animacao (o .zip nao abre no iPhone, B-21) as atividades
## sao construidas em codigo, osso por osso.
##
## Como isso funciona em QUALQUER esqueleto (e por que nao e chute):
##
## 1. `role_of()` reconhece o PAPEL do osso pelo NOME (coxa, antebraco, cabeca),
##    cobrindo os dois rigs que o jogo usa (Quaternius "UpperArm.L" e Mixamo
##    "mixamorig:LeftArm"). Osso sem papel fica no repouso.
##
## 2. A rotacao autoral e dada no ESPACO DO ESQUELETO, que e legivel: X = direita
##    (girar em X leva o membro para a frente, -Z), Y = cima (girar em Y torce o
##    tronco/cabeca) e Z = tras (girar em Z levanta o braco para o lado).
##
## 3. A conversao para a POSE LOCAL do osso vem da propria composicao do Godot
##    (scene/3d/skeleton_3d.cpp, 4.4: `global_pose = global_pose(pai) * pose`,
##    e a pose de cada osso e o repouso ate alguem animar). Para o osso girar r
##    no espaco do esqueleto:
##        pose = Bp^-1 * r * Bb
##    onde Bp e Bb sao as rotacoes de repouso GLOBAIS do osso pai e do osso.
##    Com r = identidade isso devolve exatamente o repouso (pose local = rest),
##    que e a prova de que a conta esta certa.
##
## 4. O "braco caido" nao e numero magico: a direcao de repouso de cada braco e
##    MEDIDA (posicao do osso filho), e a correcao e o arco dessa direcao para
##    baixo. Rig em T-pose, em A-pose ou torto: o braco cai igual.
##
## Custo: um clipe por atividade e por corpo (cacheado em `pedestrians.gd`), com
## poucas chaves por trilha. Nada de textura, nada de arquivo novo.

## Papeis que o jogo sabe animar. Os que nao existirem no corpo sao ignorados.
const ROLES := ["hips", "spine", "chest", "neck", "head",
	"shoulder_l", "shoulder_r", "upperarm_l", "upperarm_r",
	"forearm_l", "forearm_r", "hand_l", "hand_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]

## Atividades que os NPCs fazem quando parados.
const NPC_ACTIVITIES := ["phone", "talk", "sea", "work", "wait", "sit", "wave"]
## Atividades do protagonista (entram no meio do andar/parar, nao no lugar dele).
const PLAYER_ACTIVITIES := ["punch", "aim", "jump", "hurt"]

const LENGTHS := {
	"phone": 2.6, "talk": 3.2, "sea": 4.6, "work": 2.2, "wait": 1.8,
	"sit": 6.0, "wave": 1.4, "punch": 0.45, "aim": 1.4, "jump": 0.7, "hurt": 0.35,
}
## Clipes que tocam UMA vez e voltam para o repouso (o resto cicla).
const ONCE := ["punch", "hurt"]

## Amostras por trilha nos ossos animados. Uma curva de seno cabe em poucas.
const SAMPLES := 10

## Reconhecimento do papel pelo nome do osso, na ordem em que se testa.
## A ordem importa: "lowerleg"/"upleg" antes de "leg", "forearm" antes de "arm".
const _BASES := [
	["forearm", ["forearm", "lowerarm"]],
	["upperarm", ["upperarm", "uparm"]],
	["hand", ["hand", "wrist"]],
	["shoulder", ["shoulder", "clavicle"]],
	["thigh", ["upleg", "upperleg", "thigh"]],
	["shin", ["lowerleg", "shin", "calf", "leg"]],
	["foot", ["foot", "ankle"]],
	["head", ["head"]],
	["neck", ["neck"]],
	["hips", ["hip", "pelvis"]],
	["spine", ["spine", "chest", "torso"]],
	["arm", ["arm"]],
]

## Ossos centrais nao precisam de lado (Left/Right).
const _CENTRAL := ["hips", "spine", "chest", "neck", "head"]


# --- Leitura do esqueleto ----------------------------------------------------

## Lado do osso: "l", "r" ou "" (central). Entende "LeftArm", "left_arm",
## "Arm.L", "Arm_R" e o "mixamorig:LeftArm" que o importador deixa "mixamorig_LeftArm".
static func side_of(name: String) -> String:
	var low := name.to_lower()
	if low.contains("left"):
		return "l"
	if low.contains("right"):
		return "r"
	var parts := low.replace(".", " ").replace("_", " ").replace("-", " ") \
			.replace(":", " ").split(" ")
	for p in parts:
		if p == "l":
			return "l"
		if p == "r":
			return "r"
	return ""


## Papel do osso ("thigh_l", "upperarm_r", "head"...). "" = nao reconhecido.
static func role_of(name: String) -> String:
	var low := name.to_lower()
	var base := ""
	for pair in _BASES:
		var keys: Array = pair[1]
		for key in keys:
			if low.contains(String(key)):
				base = String(pair[0])
				break
		if base != "":
			break
	if base == "":
		return ""
	if base == "arm":
		base = "upperarm"
	var side := side_of(name)
	if side == "":
		return base if _CENTRAL.has(base) else ""
	return base + "_" + side


## Transform de repouso global (espaco do esqueleto) do osso `bone`.
## Calculado pela cadeia de rests: global(b) = global(pai) * rest(b).
static func global_rest(sk: Skeleton3D, bone: int, cache: Dictionary) -> Transform3D:
	if bone < 0 or sk == null or bone >= sk.get_bone_count():
		return Transform3D.IDENTITY
	if cache.has(bone):
		return cache[bone] as Transform3D
	var parent := sk.get_bone_parent(bone)
	var xf := sk.get_bone_rest(bone)
	if parent >= 0:
		xf = global_rest(sk, parent, cache) * xf
	cache[bone] = xf
	return xf


## Tudo o que as animacoes precisam saber deste esqueleto:
##   bone: papel -> indice do osso
##   name: papel -> nome do osso
##   bp:   papel -> rotacao de repouso global do PAI
##   bb:   papel -> rotacao de repouso global do osso
##   dir:  papel -> direcao do osso no repouso (para o primeiro filho)
## Quando ha mais de um osso da familia "spine", o primeiro vira "spine" e o
## seguinte "chest" — e assim que o tronco dobra em dois lugares.
static func rig(sk: Skeleton3D) -> Dictionary:
	var out := {"bone": {}, "name": {}, "bp": {}, "bb": {}, "dir": {}}
	if sk == null:
		return out
	var glob := {}
	for i in sk.get_bone_count():
		global_rest(sk, i, glob)
	for i in sk.get_bone_count():
		var nm := String(sk.get_bone_name(i))
		var role := role_of(nm)
		if role == "":
			continue
		if role == "spine" and out["bone"].has("spine"):
			if out["bone"].has("chest"):
				continue
			role = "chest"
		if out["bone"].has(role):
			continue
		var parent := sk.get_bone_parent(i)
		var gp := Transform3D.IDENTITY
		if parent >= 0:
			gp = glob[parent] as Transform3D
		out["bone"][role] = i
		out["name"][role] = nm
		out["bb"][role] = (glob[i] as Transform3D).basis.get_rotation_quaternion().normalized()
		out["bp"][role] = gp.basis.get_rotation_quaternion().normalized()
		# Direcao do osso = do osso para o primeiro filho dele (o "para onde o
		# membro aponta" no repouso). Braco sem antebraco nao tem direcao.
		var kids := sk.get_bone_children(i)
		if kids.size() > 0:
			var d: Vector3 = (glob[kids[0]] as Transform3D).origin \
					- (glob[i] as Transform3D).origin
			if d.length() > 0.001:
				out["dir"][role] = d.normalized()
	return out


## Correcao de repouso do papel: leva o braco para baixo. Para todo o resto e
## identidade. E medida no esqueleto, nunca chutada.
static func stand(rg: Dictionary, role: String) -> Quaternion:
	if role != "upperarm_l" and role != "upperarm_r":
		return Quaternion.IDENTITY
	var dirs: Dictionary = rg.get("dir", {})
	if not dirs.has(role):
		return Quaternion.IDENTITY
	var d: Vector3 = dirs[role]
	if d.length() < 0.1 or d.dot(Vector3.DOWN) < -0.94:
		return Quaternion.IDENTITY
	return Quaternion(d, Vector3.DOWN)


# --- As atividades -----------------------------------------------------------

static func length_of(kind: String) -> float:
	return float(LENGTHS.get(kind, 2.0))


static func cycles(kind: String) -> bool:
	return not ONCE.has(kind)


## Rotacao de um eixo do espaco do esqueleto, em GRAUS.
static func _q(axis: Vector3, deg: float) -> Quaternion:
	return Quaternion(axis, deg_to_rad(deg))


## A pose da atividade no instante `u` em [0, 1] — papel do osso -> rotacao no
## espaco do esqueleto, JA em cima do "braco caido". Puro: o CI confere que
## todo clipe de ciclo fecha em u = 0 e u = 1.
static func pose(kind: String, u: float) -> Dictionary:
	var out := {}
	var w := sin(TAU * u)              # um ciclo
	var w2 := sin(TAU * u * 2.0)       # dois ciclos
	var a := sin(PI * clampf(u, 0.0, 1.0))   # sobe e volta (clipe de uma vez)
	var x := Vector3.RIGHT
	var y := Vector3.UP
	var z := Vector3(0.0, 0.0, 1.0)
	match kind:
		"phone":
			# Cabeca baixa no aparelho, antebraco dobrado na altura do peito.
			out["head"] = _q(x, 22.0 + 3.0 * w)
			out["spine"] = _q(x, 6.0)
			out["upperarm_r"] = _q(x, 45.0 + 3.0 * w)
			out["forearm_r"] = _q(x, 80.0)
			out["upperarm_l"] = _q(x, 8.0)
			out["forearm_l"] = _q(x, 20.0)
		"talk":
			# Gesticula com as duas maos e vira a cabeca para o interlocutor.
			out["spine"] = _q(y, 7.0 * w)
			out["head"] = _q(y, 14.0 * w) * _q(x, 4.0)
			out["upperarm_r"] = _q(x, 30.0 + 12.0 * w2)
			out["forearm_r"] = _q(x, 62.0 + 16.0 * w2)
			out["upperarm_l"] = _q(x, 24.0 - 12.0 * w2)
			out["forearm_l"] = _q(x, 54.0 - 16.0 * w2)
		"sea":
			# Mao na testa, olhando o horizonte: o gesto classico de quem procura
			# alguem na areia.
			out["head"] = _q(x, -6.0 + 3.0 * w)
			out["spine"] = _q(x, -2.0 + 1.5 * w)
			out["upperarm_r"] = _q(y, 22.0) * _q(x, 96.0)
			out["forearm_r"] = _q(x, 98.0)
			out["upperarm_l"] = _q(x, -6.0)
			out["forearm_l"] = _q(x, 10.0)
		"work":
			# Balconista: debrucado no balcao, as duas maos trabalhando.
			out["spine"] = _q(x, 12.0)
			out["head"] = _q(x, 14.0 + 4.0 * w2)
			out["upperarm_r"] = _q(x, 34.0 + 12.0 * w)
			out["forearm_r"] = _q(x, 76.0 + 20.0 * w)
			out["upperarm_l"] = _q(x, 34.0 - 12.0 * w)
			out["forearm_l"] = _q(x, 76.0 - 20.0 * w)
		"wait":
			# Esperando o sinal: olha para os lados e bate o pe no chao.
			var tap := maxf(0.0, sin(TAU * u * 3.0))
			out["hips"] = _q(y, 3.0 * w)
			out["head"] = _q(y, 20.0 * w)
			out["upperarm_r"] = _q(x, 12.0 + 4.0 * w)
			out["forearm_r"] = _q(x, 24.0)
			out["upperarm_l"] = _q(x, 12.0 - 4.0 * w)
			out["forearm_l"] = _q(x, 24.0)
			out["thigh_r"] = _q(x, 5.0)
			out["shin_r"] = _q(x, -(8.0 + 20.0 * tap))
		"sit":
			# Sentado na areia com os joelhos dobrados: coxa para a frente, canela
			# para baixo, maos descansando nas pernas.
			out["hips"] = _q(x, -6.0)
			out["spine"] = _q(x, -4.0 + 1.5 * w)
			out["head"] = _q(y, 10.0 * w)
			out["thigh_l"] = _q(x, 95.0)
			out["thigh_r"] = _q(x, 95.0)
			out["shin_l"] = _q(x, -100.0)
			out["shin_r"] = _q(x, -100.0)
			out["upperarm_l"] = _q(x, 42.0)
			out["upperarm_r"] = _q(x, 42.0)
			out["forearm_l"] = _q(x, 46.0)
			out["forearm_r"] = _q(x, 46.0)
		"wave":
			# Braco levantado para o lado, antebraco acenando.
			out["head"] = _q(x, -3.0)
			out["spine"] = _q(y, 4.0)
			out["upperarm_r"] = _q(z, 75.0) * _q(x, 15.0)
			out["forearm_r"] = _q(z, 35.0 + 25.0 * w)
		"punch":
			# Soco de direita com giro de tronco; a esquerda protege o rosto.
			out["spine"] = _q(y, -10.0 * a)
			out["head"] = _q(y, -6.0 * a)
			out["upperarm_r"] = _q(x, 70.0 * a) * _q(y, 12.0 * a)
			out["forearm_r"] = _q(x, 18.0 - 14.0 * a)
			out["upperarm_l"] = _q(x, 34.0 * a)
			out["forearm_l"] = _q(x, 70.0 * a)
		"aim":
			# Pistola nas duas maos, apontada para onde a camera olha.
			out["spine"] = _q(y, -6.0)
			out["head"] = _q(x, 2.0 + 1.0 * w)
			out["upperarm_r"] = _q(x, 78.0) * _q(y, 10.0)
			out["forearm_r"] = _q(x, 8.0)
			out["upperarm_l"] = _q(x, 66.0) * _q(y, -12.0)
			out["forearm_l"] = _q(x, 30.0)
		"jump":
			# No ar: pernas recolhidas, bracos para tras.
			out["spine"] = _q(x, 5.0)
			out["thigh_l"] = _q(x, 28.0 + 8.0 * w)
			out["thigh_r"] = _q(x, 28.0 - 8.0 * w)
			out["shin_l"] = _q(x, -50.0)
			out["shin_r"] = _q(x, -50.0)
			out["upperarm_l"] = _q(x, -22.0)
			out["upperarm_r"] = _q(x, -22.0)
			out["forearm_l"] = _q(x, 30.0)
			out["forearm_r"] = _q(x, 30.0)
		"hurt":
			# Levou o golpe: tronco para tras e bracos abrindo.
			out["spine"] = _q(x, -14.0 * a)
			out["head"] = _q(x, -10.0 * a)
			out["upperarm_l"] = _q(z, -18.0 * a)
			out["upperarm_r"] = _q(z, 18.0 * a)
			out["forearm_l"] = _q(x, 30.0 * a)
			out["forearm_r"] = _q(x, 30.0 * a)
	return out


## Pose LOCAL do osso (a que vai na trilha da animacao) para o papel `role`:
## pose = Bp^-1 * (atividade * braco_caido) * Bb. `pose_now` e o dicionario que
## `pose()` devolveu para o instante desejado.
##
## `model_faces_z` gira a pose autoral 180 graus em Y: o PROTAGONISTA.fbx olha
## para +Z e o corpo CC0 para -Z (e o mesmo motivo do moonwalk, B-62). Sem isso o
## soco dele sairia para tras. O "braco caido" NAO gira: ele vem de uma direcao
## medida (para baixo e para baixo em qualquer modelo).
static func bone_pose(rg: Dictionary, role: String, pose_now: Dictionary,
		model_faces_z: bool = false) -> Quaternion:
	var act: Quaternion = pose_now.get(role, Quaternion.IDENTITY) as Quaternion
	if model_faces_z:
		var m := Quaternion(Vector3.UP, PI)
		act = m * act * m
	var r: Quaternion = act * stand(rg, role)
	var bp: Quaternion = Quaternion.IDENTITY
	var bb: Quaternion = Quaternion.IDENTITY
	var bpd: Dictionary = rg["bp"]
	var bbd: Dictionary = rg["bb"]
	if bpd.has(role):
		bp = bpd[role] as Quaternion
	if bbd.has(role):
		bb = bbd[role] as Quaternion
	return (bp.inverse() * r * bb).normalized()


## Monta o clipe de uma atividade para ESTE esqueleto. Devolve null se o corpo
## nao tem osso reconhecivel (o jogo segue sem a atividade, nunca quebra).
##
## Os ossos que a atividade nao usa tambem entram nas trilhas, presos no
## repouso: o AnimationPlayer nao zera o que o clipe nao anima, entao sem isso o
## pedestre sairia da caminhada com pedaco do passo grudado no corpo.
static func build(kind: String, sk: Skeleton3D, skel_path: String,
		model_faces_z: bool = false) -> Animation:
	var rg := rig(sk)
	var bones: Dictionary = rg["bone"]
	if bones.is_empty() or skel_path == "":
		return null
	var length := length_of(kind)
	var out := Animation.new()
	out.length = length
	out.loop_mode = Animation.LOOP_LINEAR if cycles(kind) else Animation.LOOP_NONE
	var poses: Array = []
	for k in SAMPLES:
		poses.append(pose(kind, float(k) / float(SAMPLES - 1)))
	var role_of_bone := {}
	for role in bones.keys():
		role_of_bone[int(bones[role])] = String(role)
	for i in sk.get_bone_count():
		var nm := String(sk.get_bone_name(i))
		if nm == "" or nm.contains(":"):
			continue
		var role := String(role_of_bone.get(i, ""))
		var animated := role != ""
		var n := SAMPLES if animated else 2
		var rest := sk.get_bone_rest(i)
		var rot := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rot, NodePath(skel_path + ":" + nm))
		var pos := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pos, NodePath(skel_path + ":" + nm))
		for k in n:
			var t := length * float(k) / float(n - 1)
			var q := rest.basis.get_rotation_quaternion()
			if animated:
				q = bone_pose(rg, role, poses[k] as Dictionary, model_faces_z)
			out.track_insert_key(rot, t, q)
			# A posicao do osso nao muda na atividade: DUAS chaves bastam para
			# prender o osso no repouso (contra a sobra do clipe anterior) sem
			# pagar uma chave de posicao por amostra em cada osso do corpo.
			if k == 0 or k == n - 1:
				out.track_insert_key(pos, t, rest.origin)
	return out


## Instala um clipe num AnimationPlayer. Godot 4 tirou o `add_animation(nome,
## clipe)` do Godot 3: a animacao entra numa BIBLIOTECA, e a biblioteca padrao
## chama-se "" (StringName vazio). Chamar o metodo antigo aborta a funcao em
## tempo de execucao — foi o que deixava os pedestres sem atividade e devolvia o
## protagonista para o corpo de reserva, sem nenhuma mensagem no Safari.
## Devolve true se o clipe ficou disponivel no player.
static func add_clip(ap: AnimationPlayer, name: String, anim: Animation) -> bool:
	if ap == null or anim == null or name == "":
		return false
	var nm := StringName(name)
	if ap.has_animation(nm):
		return true
	var lib_name := StringName("")
	var lib := ap.get_animation_library(lib_name)
	if lib == null:
		lib = AnimationLibrary.new()
		if ap.add_animation_library(lib_name, lib) != OK:
			return false
	lib.add_animation(nm, anim)
	return ap.has_animation(nm)


## Quantos ossos deste esqueleto tem papel (telemetria e testes).
static func covered(sk: Skeleton3D) -> int:
	return (rig(sk)["bone"] as Dictionary).size()


## Resumo legivel para o HUD/telemetria.
static func describe(kind: String) -> String:
	return "%s %.1fs%s" % [kind, length_of(kind), "" if cycles(kind) else " (uma vez)"]
