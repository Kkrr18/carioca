extends Node3D
## Pedestrians: gente com vida propria nas calcadas e na praia (B-53).
##
## Cada pedestre tem DESTINO, PRESSA e ROTINA — nao e enfeite que desliza:
##   - anda pela calcada em volta das quadras, canto a canto, no sentido que
##     sorteou (horario ou anti-horario);
##   - ao chegar num canto decide: segue a volta (65%), atravessa a rua (35%) ou
##     PARA (12%) para olhar o celular / esperar alguem;
##   - para atravessar ele ESPERA o sinal: so entra na via quando a rua que ele
##     vai cruzar esta no vermelho para os carros (a mesma fase dos semaforos do
##     transito). Se demorar demais, desiste e segue pela calcada;
##   - na praia caminha pela areia e pelo calcadao, indo e voltando, as vezes
##     parado olhando o mar;
##   - sai da frente do jogador quando ele chega perto e CORRE se um carro
##     aparece em cima dele no meio da travessia;
##   - muda de altura, tom de pele e roupa (semente propria por pessoa: mesma
##     pessoa, mesma roupa, sempre);
##   - de madrugada sobram poucas pessoas na rua; de dia a calcada enche.
##
## Custo: 3 MultiMesh (corpo, cabeca+bracos, pernas) para TODOS os pedestres,
## entao a cidade inteira de gente custa 3 chamadas de desenho. As pernas
## balancam de verdade porque cada perna e uma instancia propria girada no
## quadril — e nao existe esqueleto nem animacao importada.
## A logica e PURA (funcoes estaticas) e testada no CI sem cena.

const Cfg = preload("res://scripts/core/cfg.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const Traffic = preload("res://scripts/world/traffic.gd")

const BLOCK := Cfg.BLOCK_SIZE
## Meio da calcada: 5 m de meia-rua + 1,5 m dentro da calcada de 3 m.
const RING := 6.5
## No do transito na esquina sudoeste da quadra (0, 0): 1280 / 64.
const NODE_ORIGIN_X := 20

# Estado do pedestre.
const KIND_WALK := 0     # indo para o proximo canto (ou ponto da praia)
const KIND_WAIT := 1     # parado no canto esperando o sinal abrir
const KIND_CROSS := 2    # atravessando a rua
const KIND_IDLE := 3     # parado (celular, conversa, olhando o mar)

const MODE_BLOCK := 0    # calcada em volta da quadra
const MODE_BEACH := 1    # areia e calcadao

# Limites de quadra da cidade desenhada (city_gen): x 0..6144, z 128..2304.
const BMIM := Vector2i(0, 0)
const BMAX := Vector2i(95, 34)

const WALK_MIN := 1.05          # m/s (passo de calcada)
const WALK_MAX := 1.55
const JOG_SPEED := 2.70         # quem esta correndo na orla
const JOG_CHANCE := 0.12
const RUN_PANIC := 2.30         # multiplicador ao ver carro em cima
const RESPAWN_NEAR := 32.0      # ao voltar para perto do jogador: de 32 a...
const RESPAWN_FAR := 125.0      # ...125 m (fora do susto, dentro do mundo)
const CROSS_CHANCE := 0.35
const IDLE_CHANCE := 0.12
const GIVE_UP := 18.0           # s esperando o sinal antes de desistir
const DODGE_RADIUS := 1.5       # m do jogador: sai da frente
const CAR_PANIC := 9.0          # carro a menos disso durante a travessia: corre

# Paleta das pessoas. Pele e roupa variam, como na rua de verdade.
const SKINS := [
	Color(0.94, 0.79, 0.67), Color(0.86, 0.69, 0.54), Color(0.74, 0.56, 0.41),
	Color(0.58, 0.41, 0.29), Color(0.44, 0.31, 0.22), Color(0.32, 0.22, 0.17),
]
const SHIRTS := [
	Color(0.90, 0.20, 0.18), Color(0.16, 0.42, 0.72), Color(0.95, 0.93, 0.88),
	Color(0.95, 0.78, 0.18), Color(0.20, 0.55, 0.32), Color(0.72, 0.24, 0.60),
	Color(0.35, 0.36, 0.40), Color(0.98, 0.55, 0.20),
]
const PANTS := [
	Color(0.18, 0.22, 0.34), Color(0.12, 0.12, 0.13), Color(0.55, 0.52, 0.44),
	Color(0.30, 0.36, 0.44), Color(0.42, 0.42, 0.45),
]

## Altura do quadril (onde a perna gira) e da cabeca, em metros.
const HIP_Y := 0.84
const HEAD_Y := 1.62

var peds_total := 28
var peds: Array = []
var _clock := 0.0
var _follow_t := 0.0
var _visible := 0
var _mat: StandardMaterial3D
var _mm_body: MultiMeshInstance3D
var _mm_skin: MultiMeshInstance3D
var _mm_legs: MultiMeshInstance3D


# --- Nucleo puro (sem cena; testado em tests/runner.gd) ----------------------

## Canto sudoeste da quadra `b` no plano XZ (metros).
static func block_origin(b: Vector2i) -> Vector2:
	return Vector2(float(b.x) * BLOCK, Cfg.CITY_MIN_Z + float(b.y) * BLOCK)


static func valid_block(b: Vector2i) -> bool:
	return b.x >= BMIM.x and b.x <= BMAX.x and b.y >= BMIM.y and b.y <= BMAX.y


## Os quatro cantos da calcada da quadra, em ordem de caminhada:
## 0 = sudoeste, 1 = sudeste, 2 = nordeste, 3 = noroeste.
static func corner(b: Vector2i, k: int) -> Vector2:
	var o := block_origin(b)
	var lo := RING
	var hi := BLOCK - RING
	match k:
		0:
			return o + Vector2(lo, lo)
		1:
			return o + Vector2(hi, lo)
		2:
			return o + Vector2(hi, hi)
		_:
			return o + Vector2(lo, hi)


static func next_corner(k: int, clockwise: bool) -> int:
	return (k + 1) % 4 if clockwise else (k + 3) % 4


## Cruzamento que governa a travessia feita do canto `k`: e o semaforo da
## esquina daquele canto (a mesma grade do transito).
static func corner_node(b: Vector2i, k: int) -> Vector2i:
	var dx := 1 if (k == 1 or k == 2) else 0
	var dz := 1 if k >= 2 else 0
	return Vector2i(b.x - NODE_ORIGIN_X + dx, b.y + dz)


## Pode atravessar? `along_x` = atravessar a rua que corre em Z (norte-sul), que
## e a que tem os carros quando a fase `.x` esta verde. Pedestre so entra quando
## os carros daquela via estao parados.
static func can_cross(b: Vector2i, k: int, along_x: bool, t: float) -> bool:
	var st := Traffic.light_states(corner_node(b, k), t)
	return st.x != 2 if along_x else st.y != 2


## Travessia a partir do canto `k` da quadra `b`. Devolve
## [quadra nova, canto novo, destino no plano]. O destino fica sempre a 13 m
## (10 de rua + 1,5 de cada calcada), atravessando a via pela menor distancia.
static func cross_target(b: Vector2i, k: int, along_x: bool) -> Array:
	var nb: Vector2i
	var nc: int
	match k:
		0:
			nb = Vector2i(b.x - 1, b.y) if along_x else Vector2i(b.x, b.y - 1)
			nc = 1 if along_x else 3
		1:
			nb = Vector2i(b.x + 1, b.y) if along_x else Vector2i(b.x, b.y - 1)
			nc = 0 if along_x else 2
		2:
			nb = Vector2i(b.x + 1, b.y) if along_x else Vector2i(b.x, b.y + 1)
			nc = 3 if along_x else 1
		_:
			nb = Vector2i(b.x - 1, b.y) if along_x else Vector2i(b.x, b.y + 1)
			nc = 2 if along_x else 0
	return [nb, nc, corner(nb, nc)]


## Quanta gente ha na rua a essa hora (1.0 = calcada cheia).
static func life_fraction(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 5.5 or h >= 23.0:
		return 0.35
	if h < 7.0:
		return 0.70
	if h < 21.0:
		return 1.0
	return 0.60


## Pedestre novo, deterministico a partir da semente (mesma pessoa, mesma roupa).
static func spawn_ped(seed_value: int, index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var jogging := rng.randf() < JOG_CHANCE
	return {
		"rng": rng,
		"index": index,
		"pos": Vector2.ZERO,
		"target": Vector2.ZERO,
		"block": Vector2i.ZERO,
		"corner": 0,
		"pending_block": Vector2i.ZERO,
		"pending_corner": 0,
		"cross_to": Vector2.ZERO,
		"cross_x": true,
		"mode": MODE_BLOCK,
		"kind": KIND_WALK,
		"clockwise": rng.randf() < 0.5,
		"speed": JOG_SPEED if jogging else rng.randf_range(WALK_MIN, WALK_MAX),
		"phase": rng.randf() * TAU,
		"yaw": 0.0,
		"wait": 0.0,
		"waited": 0.0,
		"scale": rng.randf_range(0.93, 1.07),
		"skin": SKINS[rng.randi_range(0, SKINS.size() - 1)],
		"shirt": SHIRTS[rng.randi_range(0, SHIRTS.size() - 1)],
		"pants": PANTS[rng.randi_range(0, PANTS.size() - 1)],
	}


## Proximo ponto da caminhada na praia: vai e volta pela areia e pelo calcadao.
static func beach_goal(p: Dictionary) -> Vector2:
	var rng: RandomNumberGenerator = p["rng"]
	var pos: Vector2 = p["pos"]
	var dx := rng.randf_range(18.0, 60.0)
	if rng.randf() < 0.5:
		dx = -dx
	var z := pos.y + rng.randf_range(-14.0, 14.0)
	return Vector2(clampf(pos.x + dx, 12.0, Cfg.WORLD_MAX.x - 12.0),
			clampf(z, 46.0, 124.0))


## Poe o pedestre perto de `focus`: na calcada de uma quadra (modo normal) ou na
## areia/calcadao quando o ponto sorteado cai na praia.
static func place_ped(p: Dictionary, focus: Vector3, near_m: float, far_m: float) -> bool:
	var rng: RandomNumberGenerator = p["rng"]
	var f := Vector2(focus.x, focus.z)
	for attempt in 16:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(near_m, far_m)
		var q := f + Vector2(cos(ang), sin(ang)) * d
		if q.y < Cfg.BEACH_EDGE_Z:
			p["mode"] = MODE_BEACH
			p["pos"] = Vector2(clampf(q.x, 12.0, Cfg.WORLD_MAX.x - 12.0),
					clampf(q.y, 46.0, 124.0))
			p["kind"] = KIND_WALK
			p["wait"] = 0.0
			p["target"] = beach_goal(p)
			return true
		var b := Vector2i(int(floor(q.x / BLOCK)),
				int(floor((q.y - Cfg.CITY_MIN_Z) / BLOCK)))
		if not valid_block(b):
			continue
		p["mode"] = MODE_BLOCK
		p["block"] = b
		p["corner"] = rng.randi_range(0, 3)
		p["pos"] = corner(b, int(p["corner"]))
		p["kind"] = KIND_WALK
		p["wait"] = 0.0
		p["target"] = corner(b, next_corner(int(p["corner"]), bool(p["clockwise"])))
		return true
	return false


# --- Malhas ------------------------------------------------------------------

## Corpo (pe no y = 0): torax e quadril. Cor de vertice neutra — quem da a cor
## final e a cor de instancia (a roupa da pessoa).
static func body_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	_append_box(v, n, c, Vector3(0.0, 1.15, 0.0), Vector3(0.38, 0.62, 0.24), Color.WHITE)
	_append_box(v, n, c, Vector3(0.0, 0.92, 0.0), Vector3(0.34, 0.18, 0.22), Color(0.55, 0.55, 0.60))
	return _mesh_from(v, n, c)


## Cabeca, cabelo e bracos (a pele, que a cor de instancia define). Mesma origem
## do corpo, entao usa exatamente a mesma transformacao.
static func skin_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	_append_box(v, n, c, Vector3(0.0, HEAD_Y, 0.0), Vector3(0.21, 0.24, 0.21), Color.WHITE)
	# Cabelo: metade do tom da pele, entao escurece junto (sem textura).
	_append_box(v, n, c, Vector3(0.0, HEAD_Y + 0.09, 0.0), Vector3(0.23, 0.10, 0.23),
			Color(0.55, 0.52, 0.50))
	_append_box(v, n, c, Vector3(-0.245, 1.12, 0.0), Vector3(0.10, 0.46, 0.12), Color.WHITE)
	_append_box(v, n, c, Vector3(0.245, 1.12, 0.0), Vector3(0.10, 0.46, 0.12), Color.WHITE)
	return _mesh_from(v, n, c)


## Perna: do quadril (y = 0) para baixo. O giro no quadril vem da instancia.
static func leg_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	_append_box(v, n, c, Vector3(0.0, -HIP_Y * 0.5, 0.0), Vector3(0.15, HIP_Y, 0.16), Color.WHITE)
	_append_box(v, n, c, Vector3(0.0, -HIP_Y + 0.03, 0.02), Vector3(0.16, 0.07, 0.24),
			Color(0.25, 0.25, 0.27))
	return _mesh_from(v, n, c)


static func _append_box(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	for f in CityGen.CUBE_FACES:
		var fc: Vector3 = f[0]
		var ya: Vector3 = f[1]
		var za: Vector3 = f[2]
		var cc := center + Vector3(fc.x * h.x, fc.y * h.y, fc.z * h.z)
		var yv := Vector3(ya.x * h.x, ya.y * h.y, ya.z * h.z)
		var zv := Vector3(za.x * h.x, za.y * h.y, za.z * h.z)
		var a: Vector3 = cc - yv - zv
		var b: Vector3 = cc + yv - zv
		var d: Vector3 = cc + yv + zv
		var e: Vector3 = cc - yv + zv
		for p in [a, b, d, a, d, e]:
			v.append(p)
			n.append(fc)
			c.append(col)


static func _mesh_from(v: PackedVector3Array, n: PackedVector3Array,
		c: PackedColorArray) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- Cena --------------------------------------------------------------------

func setup(base_seed: int, focus: Vector3 = Vector3.ZERO) -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = false
	_mat.roughness = 0.92
	_mat.metallic_specular = 0.1

	peds.clear()
	for k in peds_total:
		peds.append(spawn_ped(base_seed + k * 6151, k))

	_mm_body = _make_mm("PedBodies", body_mesh(), peds_total)
	_mm_skin = _make_mm("PedSkin", skin_mesh(), peds_total)
	_mm_legs = _make_mm("PedLegs", leg_mesh(), peds_total * 2)

	for i in peds.size():
		var p: Dictionary = peds[i]
		_mm_body.multimesh.set_instance_color(i, p["shirt"])
		_mm_skin.multimesh.set_instance_color(i, p["skin"])
		for side in 2:
			_mm_legs.multimesh.set_instance_color(i * 2 + side, p["pants"])
		place_ped(p, focus, RESPAWN_NEAR, RESPAWN_FAR)

	update(0.0, focus, focus, Vector3.ZERO, 0.0, 12.0)


func _make_mm(nm: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = _mat
	add_child(mmi)
	return mmi


## Um passo: mantem a vizinhanca povoada, anda cada pedestre e reescreve as
## transformacoes. `car_speed` > 0 liga o panico de atravessia.
func update(delta: float, focus: Vector3 = Vector3.ZERO, player_pos: Vector3 = Vector3.ZERO,
		car_pos: Vector3 = Vector3.ZERO, car_speed: float = 0.0, hour: float = 12.0) -> void:
	_clock += delta
	if focus != Vector3.ZERO:
		_follow(focus, delta)
	for p in peds:
		_step(p, delta, player_pos, car_pos, car_speed)
	# De madrugada a rua esvazia (os primeiros `n` continuam em cena).
	_visible = maxi(4, int(round(float(peds_total) * life_fraction(hour))))
	_write_instances()


## Quem ficou longe demais volta para perto (a cidade nao pode ficar vazia
## quando o jogador atravessa a cidade de carro).
func _follow(focus: Vector3, delta: float) -> void:
	_follow_t -= delta
	if _follow_t > 0.0:
		return
	_follow_t = 0.7
	for p in peds:
		var pos: Vector2 = p["pos"]
		if Vector2(pos.x - focus.x, pos.y - focus.z).length() > RESPAWN_FAR:
			place_ped(p, focus, RESPAWN_NEAR, RESPAWN_FAR)


func _step(p: Dictionary, dt: float, player_pos: Vector3, car_pos: Vector3,
		car_speed: float) -> void:
	var kind: int = p["kind"]
	if kind == KIND_WAIT:
		_dodge(p, player_pos)
		_step_wait(p, dt)
		return
	if kind == KIND_IDLE:
		_dodge(p, player_pos)
		var left: float = float(p["wait"]) - dt
		p["wait"] = left
		if left <= 0.0:
			_next_target(p)
		return

	var pos: Vector2 = p["pos"]
	var target: Vector2 = p["target"]
	var to := target - pos
	var dist := to.length()
	if dist < 0.12:
		_arrive(p)
		return
	var dir := to / dist
	var speed: float = p["speed"]
	if kind == KIND_CROSS and car_speed > 1.5:
		# Carro em cima: corre. Atravessar correndo e o esporte local.
		if Vector2(car_pos.x - pos.x, car_pos.z - pos.y).length() < CAR_PANIC:
			speed *= RUN_PANIC
	var step := minf(speed * dt, dist)
	pos += dir * step
	p["pos"] = pos
	p["phase"] = float(p["phase"]) + speed * dt * 4.2
	p["yaw"] = lerp_angle(float(p["yaw"]), atan2(-dir.x, -dir.y), minf(1.0, 8.0 * dt))
	_dodge(p, player_pos)


## Sai da frente do jogador em vez de deixar ele atravessar a pessoa.
func _dodge(p: Dictionary, player_pos: Vector3) -> void:
	if player_pos == Vector3.ZERO:
		return
	var pos: Vector2 = p["pos"]
	var away := Vector2(pos.x - player_pos.x, pos.y - player_pos.z)
	var away_len := away.length()
	if away_len < DODGE_RADIUS and away_len > 0.01:
		p["pos"] = pos + away / away_len * (DODGE_RADIUS - away_len) * 0.5


## Parado no canto esperando o sinal. Quando a via abre, atravessa; se demorar
## demais, desiste e segue pela calcada (ninguem fica plantado para sempre).
func _step_wait(p: Dictionary, dt: float) -> void:
	var left: float = float(p["wait"]) - dt
	p["wait"] = left
	p["waited"] = float(p["waited"]) + dt
	if left > 0.0:
		return
	if can_cross(p["block"], int(p["corner"]), bool(p["cross_x"]), _clock):
		p["kind"] = KIND_CROSS
		p["target"] = p["cross_to"]
		return
	if float(p["waited"]) > GIVE_UP:
		_next_target(p)


func _arrive(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	if int(p["kind"]) == KIND_CROSS:
		# Do outro lado da rua: a quadra e o canto mudam.
		p["block"] = p["pending_block"]
		p["corner"] = p["pending_corner"]
		_next_target(p)
		return
	if int(p["mode"]) == MODE_BEACH:
		# Na praia: caminha e as vezes para para olhar o mar.
		if rng.randf() < 0.18:
			p["kind"] = KIND_IDLE
			p["wait"] = rng.randf_range(3.0, 9.0)
		else:
			_next_target(p)
		return
	if rng.randf() < IDLE_CHANCE:
		p["kind"] = KIND_IDLE
		p["wait"] = rng.randf_range(2.5, 7.0)
		return
	if rng.randf() < CROSS_CHANCE:
		var along_x := rng.randf() < 0.5
		var ct := cross_target(p["block"], int(p["corner"]), along_x)
		var nb: Vector2i = ct[0]
		if valid_block(nb):
			p["cross_x"] = along_x
			p["cross_to"] = ct[2]
			p["pending_block"] = nb
			p["pending_corner"] = int(ct[1])
			p["kind"] = KIND_WAIT
			p["wait"] = rng.randf_range(0.8, 2.6)
			p["waited"] = 0.0
			return
	_next_target(p)


func _next_target(p: Dictionary) -> void:
	p["kind"] = KIND_WALK
	if int(p["mode"]) == MODE_BEACH:
		p["target"] = beach_goal(p)
		return
	var k := next_corner(int(p["corner"]), bool(p["clockwise"]))
	p["corner"] = k
	p["target"] = corner(p["block"], k)


## Escreve as instancias: corpo e cabeca usam a MESMA transformacao (mesma
## origem, pe no chao); cada perna e uma instancia girada no quadril.
func _write_instances() -> void:
	if _mm_body == null:
		return
	var n := mini(_visible, peds.size())
	_mm_body.multimesh.visible_instance_count = n
	_mm_skin.multimesh.visible_instance_count = n
	_mm_legs.multimesh.visible_instance_count = n * 2
	# Escreve TODOS (inclusive os que estao fora de cena hoje): assim a caixa de
	# visibilidade do MultiMesh fica do tamanho certo e nao sobra instancia
	# parada na origem do mundo.
	for i in peds.size():
		var p: Dictionary = peds[i]
		var pos: Vector2 = p["pos"]
		var y := Cfg.surface_at(pos.x, pos.y)
		var sc: float = p["scale"]
		var kind: int = p["kind"]
		var moving := kind == KIND_WALK or kind == KIND_CROSS
		var ph: float = p["phase"]
		var swing := sin(ph) * 0.55 if moving else 0.0
		var bob := absf(sin(ph * 2.0)) * 0.035 * sc if moving else 0.0
		var basis := Basis(Vector3.UP, float(p["yaw"])).scaled(Vector3.ONE * sc)
		var root := Vector3(pos.x, y + bob, pos.y)
		var xf := Transform3D(basis, root)
		_mm_body.multimesh.set_instance_transform(i, xf)
		_mm_skin.multimesh.set_instance_transform(i, xf)
		for side in 2:
			var s := 0.0
			if moving:
				s = swing if side == 0 else -swing
			var hip_x := -0.11 if side == 0 else 0.11
			var leg_xf := Transform3D(basis * Basis(Vector3.RIGHT, s),
					root + basis * Vector3(hip_x, HIP_Y, 0.0))
			_mm_legs.multimesh.set_instance_transform(i * 2 + side, leg_xf)


func describe() -> String:
	return "pedestres: %d pessoas na rua (3 desenhos por quadro)" % _visible
