extends CharacterBody3D
## Player: personagem em terceira pessoa (Fase 3 provisoria, jogavel).
##
## - Chao analitico (Cfg.height_at) + empurrao contra retangulos de predio
##   (SectorStreamer.push_out). Sem CharacterBody3D de chao fisico: previsivel
##   e barato no iPhone, e o mesmo resultado em qualquer frame rate.
## - Camera em orbita atras do personagem; toque na direita gira, joystick
##   na esquerda anda. Teclado WASD/setas funciona no desktop.
## - O personagem nao entra em agua mais funda que MIN_WADE_DEPTH.

const Cfg = preload("res://scripts/core/cfg.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")
const Pedestrians = preload("res://scripts/world/pedestrians.gd")

const WALK_SPEED := 4.2
const RUN_SPEED := 8.5
const ACCEL := 26.0
const AIR_ACCEL := 7.0
const JUMP_SPEED := 6.0
const GRAVITY := 18.0
const TURN_SPEED := 12.0
const EYE_HEIGHT := 1.5

# --- Modelo do protagonista (B-63) -------------------------------------------
## O mesmo corpo CC0 da Quaternius que ja roda nos pedestres: e o unico com as
## animacoes DENTRO do arquivo (idle, walk, run, jump), entao nao depende de
## retarget nenhum. Pintado por vertice: homem BRANCO, de CABELO PRETO, 1,80 m,
## camiseta laranja e calca jeans (a identidade do boneco antigo).
const AVATAR_PATH := "res://assets/models/ped-walk.glb"
## Modelo do autor. Entra ANTES do corpo CC0; se nao trouxer animacao de
## andar de verdade, o corpo CC0 segue valendo (ver _build_avatar).
const PROTAGONISTA_PATH := "res://assets/models/PROTAGONISTA.fbx"
const AVATAR_HEIGHT := 1.80
const SKIN_COL := Color(0.96, 0.84, 0.75)
const SHIRT_COL := Color(0.92, 0.45, 0.25)
const PANTS_COL := Color(0.19, 0.27, 0.46)
const HAIR_COL := Color(0.09, 0.08, 0.08)

# --- Combate, vida e dinheiro (o "jogo" do GTA) ------------------------------
const MAX_HEALTH := 100.0
const MAX_ARMOR := 100.0
const START_MONEY := 350

## Ficha das armas. `range` em metros, `cone` em radianos (abertura do tiro),
## `cool` em segundos entre golpes.
const WEAPONS := {
	"punho": {"label": "PUNHO", "range": 2.6, "cone": 1.0, "damage": 34.0,
		"ammo": false, "cool": 0.42},
	"pistola": {"label": "PISTOLA", "range": 46.0, "cone": 0.17, "damage": 100.0,
		"ammo": true, "cool": 0.24},
}

# --- Cabeca 3D (B-77) ---------------------------------------------------------
## Cabeca de verdade no lugar da cabeca lisa do corpo CC0. O modelo e a cabeca
## escaneada de Lee Perry-Smith (CC-BY 3.0, ver data/ATTRIBUTION.md), baixada do
## repositorio do three.js: e o unico modelo de cabeca humano com ARQUIVO DIRETO
## (os low-poly CC0 do poly.pizza nao tem link de arquivo e os pacotes da Kenney
## e da Quaternius vem em .zip, que aqui nao da para abrir).
##
## Tudo em FRACAO da altura do corpo, entao a cabeca acompanha o protagonista:
##   HEAD_HEIGHT_FRAC  altura do modelo (tem pescoco) / altura do corpo
##   HEAD_TOP_FRAC     topo do cranio / altura do corpo
const HEAD_PATH := "res://assets/models/head.glb"
const HEAD_HEIGHT_FRAC := 0.24
## Um tico acima da altura do corpo (1,01): o topo do cranio novo tem de cobrir o
## topo da cabeca lisa do corpo, senao ela aparece por cima.
const HEAD_TOP_FRAC := 1.01
## Se a cabeca aparecer de costas no jogo, trocar para PI (o glb olha para +Z).
const HEAD_YAW := 0.0

var streamer = null
var camera_rig: Node3D
var camera: Camera3D
var avatar: Node3D

var cam_yaw := 0.0
var cam_pitch := -0.28
var cam_distance := 6.5
var look_sensitivity := 0.008
var invert_look_y := false

var spawn_position := Vector3(1600.0, 0.0, 100.0)
var enabled := true

## Vida e colete: o colete absorve 75% do dano ate acabar (como no GTA).
signal damaged(amount: float)
signal died()

var health := MAX_HEALTH
var max_health := MAX_HEALTH
var armor := 0.0
var money := START_MONEY
var weapon := "punho"
var ammo := 0

var _cool := 0.0
var _push := Vector3.ZERO
var _muzzle: MeshInstance3D
var _muzzle_t := 0.0

var _vy := 0.0
var _grounded := false
var _bob := 0.0
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var contact_shadow: MeshInstance3D
var _using_model := false
var _ap: AnimationPlayer
var _model_holder: Node3D
var _head: Node3D             # cabeca 3D (B-77); null se o modelo nao carregar
var _head_tris := 0           # custo da cabeca na telemetria
var _idle_static := false      # clipe de parado sem movimento (pose parada)
var _sway := 0.0
var _walk_anim := ""
var _idle_anim := ""
var _run_anim := ""
var _jump_anim := ""


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	_build_avatar()
	_build_camera()
	teleport(spawn_position)
	set_process_input(true)
	set_physics_process(true)


func _build_avatar() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	# Fila de avatares: primeiro o modelo do autor (PROTAGONISTA.fbx), depois o
	# corpo CC0 que sempre traz as animacoes, e no fim o boneco de caixas — o
	# jogo nunca fica sem personagem.
	# A frente de cada modelo define a rotacao do filho: o avatar olha para +Z
	# (nariz em +Z, convencao do boneco antigo). O corpo CC0 olha para -Z no
	# arquivo e entra com PI; o .fbx do autor veio olhando para +Z e entra com 0
	# — com PI ele andava de costas (moonwalk, visto no playtest).
	if not _build_model_avatar(PROTAGONISTA_PATH, 0.0):
		if not _build_model_avatar(AVATAR_PATH, PI):
			_build_block_avatar()
	_build_contact_shadow()


## Avatar de MODELO (B-63). Devolve false se o arquivo nao carregar ou nao der
## para usar, e ai o jogador passa para o modelo seguinte da fila (e, no fim,
## para o boneco de caixas): o jogo nunca fica sem personagem.
func _build_model_avatar(path: String, model_yaw: float) -> bool:
	var scene := Pedestrians.load_scene(path)
	if scene == null:
		return false
	# A rotacao do filho e a FRENTE do modelo (comentario em _build_avatar).
	var holder := Node3D.new()
	holder.rotation.y = model_yaw
	avatar.add_child(holder)
	_model_holder = holder
	var inst: Node3D = scene.instantiate()
	holder.add_child(inst)
	var painted := 0
	for node in ModelProp.collect_meshes(inst):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if Pedestrians.paint_body(mi, SKIN_COL, SHIRT_COL, PANTS_COL, HAIR_COL):
			painted += 1
			# Pintura por vertice: o material le a cor gravada na malha.
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = false
			mat.roughness = 0.92
			mat.metallic_specular = 0.1
			mi.material_override = mat
		elif mi.material == null and mi.material_override == null:
			# Sem pintura e sem material proprio (o caso de um .fbx sem
			# textura): um chapado neutro, nunca o branco do material padrao.
			var plain := StandardMaterial3D.new()
			plain.albedo_color = SHIRT_COL
			plain.roughness = 0.92
			plain.metallic_specular = 0.1
			mi.material_override = plain
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# O corpo CC0 se pinta por vertice: sem pintura nenhuma, o arquivo nao e o
	# esperado. O .fbx do autor pode vir sem cores de vertice e e aceito assim.
	if painted == 0 and path == AVATAR_PATH:
		holder.queue_free()
		_model_holder = null
		_ap = null
		return false
	# Animacoes: clipe de andar e OBRIGATORIO para um modelo entrar. Sem ele o
	# personagem desliza em T-pose, e o corpo seguinte (que sempre traz as
	# animacoes) segue valendo.
	_ap = Pedestrians._find_anim(inst)
	var clips := {}
	if _ap != null:
		for nm in _ap.get_animation_list():
			var a := _ap.get_animation(String(nm))
			if a != null:
				clips[String(nm)] = a
	_walk_anim = Pedestrians.pick_clip(clips, "walk")
	if path != AVATAR_PATH and _walk_anim == "":
		holder.queue_free()
		_model_holder = null
		_ap = null
		return false
	_idle_anim = Pedestrians.pick_clip(clips, "idle")
	_run_anim = Pedestrians.pick_clip(clips, "run")
	_jump_anim = Pedestrians.pick_clip(clips, "jump")
	for nm in [_walk_anim, _idle_anim, _run_anim]:
		if nm != "" and clips.has(nm):
			(clips[nm] as Animation).loop_mode = Animation.LOOP_LINEAR
	# O clipe de parado da Quaternius pode ser uma pose ESTATICA: nesse caso o
	# protagonista fica plantado como estátua (era o que se via no jogo), e a
	# solucao e um balanco minimo por codigo (ESTILO.md: nada fica imovel).
	_idle_static = _idle_anim == "" or Pedestrians.clip_motion(clips[_idle_anim]) < 0.02
	if _idle_anim != "":
		_ap.play(StringName(_idle_anim))
	# Escala: posa um clipe, mede a altura do esqueleto POSADO (o AABB da malha e
	# o do bind pose e mente), normaliza para 1,80 m e apoia o pe no chao.
	var box := ModelProp.mesh_aabb(inst)
	var sk := Pedestrians._find_skel(inst)
	var posed := Pedestrians.posed_height(sk)
	var h := posed / Pedestrians.BONE_EXTENT if posed > 0.3 else maxf(0.5, box.size.y)
	var k := AVATAR_HEIGHT / maxf(0.5, h)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * k
	_using_model = _ap != null
	# Cabeca 3D (B-77): so para o corpo CC0, que vem de cabeca lisa. O
	# PROTAGONISTA.fbx traz o rosto dele — uma cabeca por cima seria a segunda.
	if path == AVATAR_PATH:
		_build_head()
	return true


## Escala do modelo de cabeca para um corpo de `body_height` metros.
static func head_scale(model_height: float, body_height: float) -> float:
	return (HEAD_HEIGHT_FRAC * maxf(1.0, body_height)) / maxf(0.01, model_height)


## Cabeca 3D do protagonista (B-77). O modelo e escalado para
## HEAD_HEIGHT_FRAC x altura do corpo com o TOPO em HEAD_TOP_FRAC x altura, entao
## muda de tamanho junto com o personagem. Fica no espaco do `avatar` (+Z e a
## frente, como o corpo), nao no osso: nao depende do rig nem do eixo dos ossos.
func _build_head() -> void:
	if avatar == null:
		return
	var scene := Pedestrians.load_scene(HEAD_PATH)
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	avatar.add_child(inst)
	var box := ModelProp.mesh_aabb(inst)
	var k := head_scale(box.size.y, AVATAR_HEIGHT)
	inst.scale = Vector3.ONE * k
	# Centraliza em X/Z e apoia o TOPO do cranio na altura do corpo.
	var c := box.get_center()
	inst.position = Vector3(-c.x * k, HEAD_TOP_FRAC * AVATAR_HEIGHT - box.end.y * k, -c.z * k)
	inst.rotation.y = HEAD_YAW
	# O .glb nao traz material (as texturas sao arquivos separados no repo de
	# origem), entao o tom vem de um material chapado de pele.
	var skin := _mat(SKIN_COL)
	for node in ModelProp.collect_meshes(inst):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.material_override = skin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_head = inst
	# Custo na telemetria: a cabeca e um escaneamento denso; se pescar o FPS no
	# aparelho, este numero diz se ele e o culpado.
	_head_tris = ModelProp.count_tris(inst)
	_build_hair(box.size.x * k)


## Medidas do cabelo (B-78) a partir da largura da cabeca, em metros. Tudo e
## fracao da largura, entao acompanha o TAMANHO do personagem.
## B-78a: na primeira versao a calota era MAIS LARGA que o cranio (1,08) e alta
## demais; no print do autor ela virou uma ABA DE CHAPEU preta. Agora ela e um
## tico mais estreita que a cabeca (0,96) e mais alta que meia (0,62), para
## assentar no cranio, e leva uma inclinacao para a frente (tilt) que deixa a
## linha da testa mais alta que a da nuca — cabelo, nao capacete.
static func hair_layout(head_width: float, crown_y: float) -> Dictionary:
	var w := maxf(0.05, head_width)
	return {
		"scale": Vector3(w * 0.96, w * 0.62, w * 1.00),
		"top": crown_y + w * 0.02,
		"z": -w * 0.02,
		"tilt": -0.10,
	}


## Cabelo do protagonista (B-78). A cabeca escaneada e CARECA, e o personagem
## pedido na B-63 e homem de CABELO PRETO: uma calota escura por cima do cranio
## devolve o cabelo (e cobre o topo da cabeca lisa do corpo). Um desenho so, ~200
## triangulos.
func _build_hair(head_width: float) -> void:
	if avatar == null or head_width <= 0.0:
		return
	var lay := hair_layout(head_width, HEAD_TOP_FRAC * AVATAR_HEIGHT)
	var dome := SphereMesh.new()
	dome.is_hemisphere = true
	dome.radius = 0.5
	dome.height = 0.5
	dome.radial_segments = 16
	dome.rings = 6
	var mi := MeshInstance3D.new()
	mi.name = "Cabelo"
	mi.mesh = dome
	mi.material_override = _mat(HAIR_COL)
	var s: Vector3 = lay["scale"]
	mi.scale = s
	mi.rotation.x = float(lay["tilt"])
	# O AABB da calota resolve a convencao de origem do SphereMesh: o TOPO dela
	# tem de ficar no topo calculado do cranio.
	var ha := dome.get_aabb()
	mi.position = Vector3(0.0, float(lay["top"]) - ha.end.y * s.y, float(lay["z"]))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	avatar.add_child(mi)


## Boneco de caixas: a reserva de sempre, usada so se o modelo nao carregar.
func _build_block_avatar() -> void:
	# Materiais compartilhados por cor.
	var skin := _mat(Color(0.80, 0.63, 0.48))
	var shirt := _mat(Color(0.92, 0.45, 0.25))
	var shorts := _mat(Color(0.18, 0.26, 0.44))
	var hair := _mat(Color(0.16, 0.12, 0.10))

	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.height = 1.2
	cap.radius = 0.28
	torso.mesh = cap
	torso.material_override = shirt
	torso.position = Vector3(0, 1.05, 0)
	avatar.add_child(torso)

	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.height = 0.34
	sph.radius = 0.17
	head.mesh = sph
	head.material_override = skin
	head.position = Vector3(0, 1.82, 0)
	avatar.add_child(head)

	var hair_mi := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.height = 0.2
	hair_mesh.radius = 0.175
	hair_mi.mesh = hair_mesh
	hair_mi.material_override = hair
	hair_mi.position = Vector3(0, 1.88, -0.01)
	avatar.add_child(hair_mi)

	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.05, 0.06)
	nose.mesh = box
	nose.material_override = skin
	nose.position = Vector3(0, 1.8, 0.17)
	avatar.add_child(nose)

	for side in [-1.0, 1.0]:
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(0.34 * side, 1.52, 0.0)
		var arm := MeshInstance3D.new()
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(0.13, 0.62, 0.13)
		arm.mesh = arm_box
		arm.material_override = skin
		arm.position = Vector3(0, -0.3, 0)
		arm_pivot.add_child(arm)
		avatar.add_child(arm_pivot)
		_arms.append(arm_pivot)

		var leg_pivot := Node3D.new()
		leg_pivot.position = Vector3(0.14 * side, 0.72, 0.0)
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.16, 0.72, 0.16)
		leg.mesh = leg_box
		leg.material_override = shorts
		leg.position = Vector3(0, -0.36, 0)
		leg_pivot.add_child(leg)
		avatar.add_child(leg_pivot)
		_legs.append(leg_pivot)


## Sombra de contato (nao existe Decal no renderer Compatibility): disco
## escuro sob os pes, ancorado no chao analitico.
func _build_contact_shadow() -> void:
	contact_shadow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35, 1.35)
	quad.orientation = PlaneMesh.FACE_Y
	# Mancha REDONDA e macia (gradiente radial). Sem textura o quad virava um
	# retangulo cinza duro embaixo do personagem (B-60).
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.50),
			Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.98, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.42)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	contact_shadow.mesh = quad
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_shadow.top_level = true
	add_child(contact_shadow)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	return m


func _build_camera() -> void:
	# Uma caixa tecnica (rig) segue a posicao do personagem SEM herdar a rotacao
	# do corpo: a camera e filha dela, e nenhuma conta de yaw e aplicada duas
	# vezes.
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.top_level = true
	add_child(camera_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 72.0
	camera.near = 0.25
	camera.far = 3200.0
	camera_rig.add_child(camera)
	camera.current = true


func _input(event: InputEvent) -> void:
	# Desktop: botao direito arrastado gira a camera. No iPhone o look vem de
	# TouchControls (arrasto no lado direito da tela).
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		cam_yaw = wrapf(cam_yaw - mm.relative.x * look_sensitivity * 0.5, -PI, PI)
		cam_pitch = clampf(cam_pitch - mm.relative.y * look_sensitivity * 0.5, deg_to_rad(-70.0), deg_to_rad(20.0))


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_cool = maxf(0.0, _cool - delta)
	if _muzzle_t > 0.0:
		_muzzle_t -= delta
		if _muzzle_t <= 0.0 and _muzzle != null:
			_muzzle.visible = false

	# --- Camera: arrasto do toque na direita + setas no desktop.
	var look := TouchControls.consume_look()
	var yaw_in := look.x * look_sensitivity
	var pitch_in := look.y * look_sensitivity
	if Input.is_key_pressed(KEY_LEFT):
		yaw_in -= 1.8 * delta
	if Input.is_key_pressed(KEY_RIGHT):
		yaw_in += 1.8 * delta
	if Input.is_key_pressed(KEY_UP):
		pitch_in -= 1.2 * delta
	if Input.is_key_pressed(KEY_DOWN):
		pitch_in += 1.2 * delta
	cam_yaw = wrapf(cam_yaw - yaw_in, -PI, PI)
	var dy := pitch_in if invert_look_y else -pitch_in
	cam_pitch = clampf(cam_pitch + dy, deg_to_rad(-70.0), deg_to_rad(20.0))

	# --- Entrada de movimento.
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var input := Vector2.ZERO
	if TouchControls.is_active():
		input = TouchControls.stick()
	else:
		if Input.is_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			input.x += 1.0
		if Input.is_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			input.y += 1.0
		if input.length() > 1.0:
			input = input.normalized()

	var wish := right * input.x + forward * -input.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	var want_sprint := TouchControls.sprint_held() or Input.is_key_pressed(KEY_SHIFT)
	var target_speed := RUN_SPEED if want_sprint else WALK_SPEED
	var target := wish * target_speed
	var accel := ACCEL if _grounded else AIR_ACCEL
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), accel * delta)
	# Empurrao externo (viatura encostando no jogador a pe): some sozinho.
	hv += Vector2(_push.x, _push.z)
	_push = _push.move_toward(Vector3.ZERO, 14.0 * delta)

	# --- Pulo / voo (botao PULAR; segurar mantem no ar como "asas" de debug).
	if TouchControls.jump_pressed() or Input.is_key_pressed(KEY_SPACE):
		if _grounded:
			_vy = JUMP_SPEED
			_grounded = false
		elif _vy > -1.0 and (TouchControls.jump_held() or Input.is_key_pressed(KEY_SPACE)):
			_vy = maxf(_vy, 2.5)

	_vy -= GRAVITY * delta
	var next := position + Vector3(hv.x, 0.0, hv.y) * delta
	# Agua profunda: desliza na superficie em vez de entrar.
	var ground_next := Cfg.height_at(next.x, next.z)
	if ground_next < Cfg.MIN_WADE_DEPTH:
		var try_x := Vector3(next.x, 0.0, position.z)
		var try_z := Vector3(position.x, 0.0, next.z)
		if Cfg.height_at(try_x.x, try_x.z) >= Cfg.MIN_WADE_DEPTH:
			next = try_x
		elif Cfg.height_at(try_z.x, try_z.z) >= Cfg.MIN_WADE_DEPTH:
			next = try_z
		else:
			next = Vector3(position.x, 0.0, position.z)
	next.x = clampf(next.x, Cfg.WORLD_MIN.x, Cfg.WORLD_MAX.x)
	next.z = clampf(next.z, Cfg.WORLD_MIN.y, Cfg.WORLD_MAX.y)
	if streamer != null:
		var pushed: Vector2 = streamer.push_out(next.x, next.z, 0.5)
		next.x = pushed.x
		next.z = pushed.y
	next.y = position.y

	var ground_y := Cfg.surface_at(next.x, next.z)
	if contact_shadow != null:
		contact_shadow.global_position = Vector3(next.x, ground_y + 0.07, next.z)
	var y := position.y + _vy * delta
	if y <= ground_y:
		y = ground_y
		_vy = 0.0
		_grounded = true
	else:
		_grounded = false
	next.y = y

	velocity = (next - position) / delta
	move_and_slide()
	position = next

	# --- Orientacao e animacao.
	if hv.length() > 0.4:
		var want_angle := atan2(hv.x, hv.y)
		avatar.rotation.y = lerp_angle(avatar.rotation.y, want_angle, clampf(TURN_SPEED * delta, 0.0, 1.0))
	_bob += delta * maxf(1.0, hv.length())
	_update_anim(hv, delta)

	_update_camera(delta)


## Animacao: clipes do MODELO quando ele existe (parado / andando / correndo /
## pulando) e, no boneco de caixas, o balanco antigo de bracos e pernas.
func _update_anim(hv: Vector2, delta: float) -> void:
	if _using_model and _ap != null:
		var sp := hv.length()
		if not _grounded and _jump_anim != "":
			_play_anim(_jump_anim, 1.0)
			_idle_hold()
		elif sp > 2.2 and _run_anim != "":
			# O clipe de corrida cobre ~4,6 m/s no compasso 1.
			_play_anim(_run_anim, clampf(sp / 4.6, 0.55, 2.0))
			_idle_hold()
		elif sp > 0.35 and _walk_anim != "":
			_play_anim(_walk_anim, clampf(sp / 1.5, 0.60, 1.70))
			_idle_hold()
		else:
			_play_anim(_idle_anim, 1.0)
			_idle_sway(delta)
		return
	if hv.length() > 0.4:
		var swing := sin(_bob) * clampf(hv.length() / RUN_SPEED, 0.0, 1.0) * 0.7
		if _legs.size() == 2:
			_legs[0].rotation.x = swing
			_legs[1].rotation.x = -swing
		if _arms.size() == 2:
			_arms[0].rotation.x = -swing * 0.8
			_arms[1].rotation.x = swing * 0.8
	else:
		for l in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, 0.2)
		for a in _arms:
			a.rotation.x = lerpf(a.rotation.x, 0.0, 0.2)


func _play_anim(nm: String, spd: float) -> void:
	if _ap == null or nm == "":
		return
	# `is_playing()` falso = o clipe acabou (pulo, por exemplo): recomeca, senao o
	# personagem fica congelado no ultimo quadro daquele clipe para sempre.
	if _ap.current_animation != StringName(nm) or not _ap.is_playing():
		_ap.play(StringName(nm))
	_ap.speed_scale = spd


## Parado: o corpo SEMPRE ganha um balanco minimo (giro de ~1,7 grau e 1 cm de
## sobe e desce). O clipe de parado da Quaternius mexe pouco (0,118 rad no osso
## que mais gira) e a 250 px de tela ele parece congelado — o autor viu o
## protagonista "parado numa pose" (B-63). Com o clipe animando, o balanco e
## menor (so para nao parecer estatua); sem movimento no clipe, ele e maior.
func _idle_sway(delta: float) -> void:
	if _model_holder == null:
		return
	_sway += delta
	var amp := 0.030 if _idle_static else 0.016
	_model_holder.rotation.y = PI + sin(_sway * 1.1) * amp
	_model_holder.position.y = sin(_sway * 2.0) * 0.010


func _idle_hold() -> void:
	if _model_holder == null:
		return
	_model_holder.rotation.y = PI
	_model_holder.position.y = 0.0


## Estado do avatar na telemetria: e por esta linha que se sabe, no aparelho, se
## o modelo carregou e se a animacao esta mesmo tocando (nao ha console no Safari).
func describe() -> String:
	if not _using_model:
		return "avatar: boneco de caixas (modelo nao carregou)"
	var playing := "parada"
	if _ap != null and _ap.is_playing():
		playing = "tocando"
	return "avatar: modelo 1,80 m (%s; idle=%s walk=%s run=%s jump=%s; parado=%s; cabeca=%s %d tris)" % [
		playing, _idle_anim, _walk_anim, _run_anim, _jump_anim,
		"estatico+balanco" if _idle_static else "animado",
		"sim" if _head != null else "nao", _head_tris]


func _update_camera(delta: float) -> void:
	if camera == null or camera_rig == null:
		return
	var head := global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	camera_rig.global_position = head
	var back := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var dist := cam_distance
	var desired := head + back * dist
	if streamer != null:
		# Encurta a camera se um predio ficaria entre ela e a cabeca.
		var flat := Vector2(desired.x, desired.z)
		var pushed: Vector2 = streamer.push_out(flat.x, flat.y, 0.6)
		var margin := (pushed - flat).length()
		if margin > 0.01:
			dist = maxf(1.6, dist - margin - 0.4)
			desired = head + back * dist
	var ground := Cfg.height_at(desired.x, desired.z) + 0.8
	camera.global_position = Vector3(desired.x, maxf(desired.y, ground), desired.z)
	camera.look_at(head + Vector3(0, 0.15, 0), Vector3.UP)


# --- Combate, vida e dinheiro -------------------------------------------------

func alive() -> bool:
	return health > 0.0


## Dano recebido. O colete absorve 75% ate acabar; o resto vai na vida. O sinal
## `damaged` faz a tela piscar vermelho; `died` dispara o WASTED no main.
func add_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	var left := amount
	if armor > 0.0:
		var absorbed := minf(armor, left * 0.75)
		armor = maxf(0.0, armor - absorbed)
		left -= absorbed
	health = maxf(0.0, health - left)
	damaged.emit(amount)
	if health <= 0.0:
		died.emit()


func revive(hp: float = MAX_HEALTH) -> void:
	health = clampf(hp, 1.0, MAX_HEALTH)
	armor = 0.0
	_cool = 0.0
	_push = Vector3.ZERO


func heal(amount: float) -> void:
	health = clampf(health + maxf(0.0, amount), 0.0, MAX_HEALTH)


func add_armor(amount: float) -> void:
	armor = clampf(armor + maxf(0.0, amount), 0.0, MAX_ARMOR)


func add_money(amount: int) -> void:
	money = maxi(0, money + amount)


## Dados da arma equipada. Nunca vazio: cai no punho.
func weapon_data() -> Dictionary:
	if weapon == "pistola":
		return WEAPONS["pistola"]
	return WEAPONS["punho"]


func weapon_label() -> String:
	return String(weapon_data()["label"])


func armed() -> bool:
	return weapon == "pistola"


## Troca punho <-> pistola (botao TROCAR). A pistola entra com um carregador
## cheio (12 balas) quando a municao estava zerada.
func swap_weapon() -> void:
	if weapon == "pistola":
		weapon = "punho"
	else:
		weapon = "pistola"
		if ammo <= 0:
			ammo = 12


func can_fire() -> bool:
	if _cool > 0.0:
		return false
	if armed() and ammo <= 0:
		return false
	return true


## Direcao da mira: a da CAMERA no plano XZ, nao a do corpo. No celular o
## jogador mira com a camera; o corpo acompanha no disparo.
func aim_dir() -> Vector3:
	return Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))


func face_dir(d: Vector3) -> void:
	if d.length() > 0.01 and avatar != null:
		avatar.rotation.y = atan2(d.x, d.z)


## Gasta o golpe: cooldown, municao, giro do corpo e clarao da boca do cano.
func consume_fire() -> void:
	_cool = maxf(0.08, float(weapon_data()["cool"]))
	if armed():
		ammo = maxi(0, ammo - 1)
	face_dir(aim_dir())
	flash_muzzle()


func flash_muzzle() -> void:
	if _muzzle == null:
		_muzzle = MeshInstance3D.new()
		_muzzle.name = "Muzzle"
		var sph := SphereMesh.new()
		sph.radius = 0.15
		sph.height = 0.30
		sph.radial_segments = 8
		sph.rings = 4
		_muzzle.mesh = sph
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.86, 0.40)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.80, 0.30)
		m.emission_energy_multiplier = 4.0
		_muzzle.material_override = m
		_muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle.top_level = true
		add_child(_muzzle)
	_muzzle.visible = true
	_muzzle.global_position = global_position + Vector3(0.0, 1.25, 0.0) + aim_dir() * 0.8
	_muzzle_t = 0.07


## Empurrao externo (a viatura encostou). Curto de proposito: tira o jogador
## do lugar sem jogar ele longe.
func push(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	_push += Vector3(dir.x, 0.0, dir.z).normalized() * 4.5


func teleport(pos: Vector3) -> void:
	position = Vector3(pos.x, Cfg.surface_at(pos.x, pos.z) + 0.05, pos.z)
	_vy = 0.0
	_grounded = true
	velocity = Vector3.ZERO
	_update_camera(0.0)


## Estado para o save (schema 1). Os campos novos sao opcionais na leitura, para
## um save antigo continuar valendo.
func state() -> Dictionary:
	return {
		"pos": [position.x, position.y, position.z],
		"yaw": avatar.rotation.y,
		"cam_yaw": cam_yaw,
		"cam_pitch": cam_pitch,
		"health": health,
		"armor": armor,
		"money": money,
		"weapon": weapon,
		"ammo": ammo,
	}


func restore(data: Dictionary) -> void:
	var p: Array = data.get("pos", [position.x, position.y, position.z])
	teleport(Vector3(float(p[0]), float(p[1]), float(p[2])))
	avatar.rotation.y = float(data.get("yaw", 0.0))
	cam_yaw = float(data.get("cam_yaw", 0.0))
	cam_pitch = float(data.get("cam_pitch", -0.28))
	health = clampf(float(data.get("health", MAX_HEALTH)), 1.0, MAX_HEALTH)
	armor = clampf(float(data.get("armor", 0.0)), 0.0, MAX_ARMOR)
	money = maxi(0, int(data.get("money", START_MONEY)))
	weapon = String(data.get("weapon", "punho"))
	ammo = maxi(0, int(data.get("ammo", 0)))
	_update_camera(0.0)


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
