extends Node3D
## PropField: fisica ambiental do mundo aberto (B-69).
##
## O que faz: caixas, cadeiras, lixeiras e cones espalhados pela rua com MASSA,
## impulso, atrito (por piso, via SurfaceDB), quique, giro ao serem jogados,
## dano em 3 estados e destrocos limitados. O carro atropela e os objetos voam;
## andando a pe voce empurra. Tudo sobre o MESMO chao analitico do carro e do
## personagem (Cfg.surface_at) e com a colisao de predio que ja existe
## (SectorStreamer.push_out).
##
## Por que nao RigidBody3D/StaticBody3D: este mundo nao tem malha de colisao (de
## proposito, ver docs/ARQUITETURA.md) e dar corpo fisico aos 9 setores de 512 m
## nao cabe no iPhone 12. A integracao fica em scripts/physics/prop_body.gd
## (pura) e aqui so mora o que precisa de cena: desenho, LOD, pooling e dano.
##
## Custo no iPhone: 3 desenhos (um MultiMesh por FORMA, cor por instancia),
## no maximo 20 objetos + 30 destrocos, sono automatico e LOD em 3 faixas:
##   < 35 m  -> fisica a 60 Hz
##   35..100 -> fisica a 20 Hz com o tempo real acumulado (mesma trajetoria)
##   > 100 m -> nao integra, mas GUARDA o estado (retoma identico ao voltar)
## Nada e congelado "no meio do voo" perdendo o estado: o dicionario do objeto
## continua com posicao, velocidade e giro.

signal bumped(strength: float, surface: String)

const Cfg = preload("res://scripts/core/cfg.gd")
const PropBody = preload("res://scripts/physics/prop_body.gd")
const Damage = preload("res://scripts/physics/damage.gd")
const SurfaceDB = preload("res://scripts/core/surface_db.gd")

const PROP_KINDS := ["caixa", "cadeira", "lixeira", "cone"]
const MAX_PROPS := 20
const MAX_DEBRIS := 30
const SPAWN_MIN := 7.0
const SPAWN_MAX := 32.0
## Faixas de LOD (m) a partir do foco (jogador a pe ou o carro).
const LOD_FULL := 35.0
const LOD_REDUCED := 100.0
## Acumulado minimo do LOD 1 antes de integrar (s).
const LOD_STEP := 0.05
const DRAW_RANGE := 120.0
const RECYCLE_RANGE := 150.0
## Quanto do embalo do carro passa para o objeto (ele sai na frente do para-choque).
const CAR_PUSH := 1.15
## Distancia do centro do carro ao objeto para valer como atropelamento (m).
const CAR_REACH := 2.4
## Massa considerada do carro no calculo de dano (kg).
const CAR_MASS := 1450.0

var bodies: Array = []
var debris: Array = []
var streamer = null
var car = null
var rng := RandomNumberGenerator.new()

var _mm_data := {}
var _last_focus := Vector3.ZERO
var _have_focus := false
var _bump_cool := 0.0


# --- Montagem ---------------------------------------------------------------

## `origin` = onde o jogador nasceu: os primeiros objetos nascem em volta dele.
func setup(seed_value: int, streamer_ref, origin: Vector3) -> void:
	rng.seed = seed_value
	streamer = streamer_ref
	_build_meshes()
	for i in MAX_PROPS:
		_spawn_near(origin)


func _build_meshes() -> void:
	# Cubo unitario: caixa, cadeira e destroco (escala por instancia).
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_add_mm("box", box, MAX_PROPS + MAX_DEBRIS)
	# Cilindro unitario (raio 0,5): lixeira.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	_add_mm("cyl", cyl, MAX_PROPS)
	# Cone unitario: cone de transito.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	_add_mm("cone", cone, MAX_PROPS)


func _add_mm(mesh_kind: String, mesh: Mesh, capacity: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Cor por instancia: o tipo e a avaria (escurece) vao na cor, sem material
	# novo e sem desenho novo por objeto.
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + mesh_kind
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	_mm_data[mesh_kind] = mm


# --- Quadro -----------------------------------------------------------------

func update(delta: float, focus: Vector3) -> void:
	if delta <= 0.0:
		return
	_bump_cool = maxf(0.0, _bump_cool - delta)
	# Empurroes primeiro: o impulso entra na integracao do MESMO quadro.
	_player_push(delta, focus)
	_car_push()
	_step_list(bodies, delta, focus)
	_step_list(debris, delta, focus)
	_compact()
	_age_debris(delta)
	_recycle(focus)
	_draw(focus)


# --- Interacao com o jogador e o carro --------------------------------------

## Andando a pe o personagem empurra o que estiver na frente. A velocidade vem
## da variacao de posicao do foco (nao depende de detalhe interno do player).
func _player_push(delta: float, focus: Vector3) -> void:
	if car != null and bool(car.occupied):
		_have_focus = false
		return
	if not _have_focus:
		_last_focus = focus
		_have_focus = true
		return
	var vel := (focus - _last_focus) / delta
	_last_focus = focus
	var speed := Vector2(vel.x, vel.z).length()
	if speed < 0.4:
		return
	var dir := Vector3(vel.x, 0.0, vel.z).normalized()
	# Potencia de um corpo de ~80 kg andando: da para empurrar caixa e derrubar
	# cone, nao para arremessar uma lixeira de 22 kg.
	_push_near(bodies, focus, 1.2, dir, speed * 5.0, 0.0)


## O carro atropela: impulso proporcional ao embalo e dano pelo impulso dele
## contra a resistencia do material (Damage.hit_power).
func _car_push() -> void:
	if car == null or not bool(car.occupied):
		return
	var signed_speed := float(car.speed)
	var speed := absf(signed_speed)
	if speed < 1.0:
		return
	var fwd := Vector3(-sin(float(car.rotation.y)), 0.0, -cos(float(car.rotation.y)))
	var dir := fwd if signed_speed >= 0.0 else -fwd
	var at: Vector3 = car.global_position
	var push := clampf(speed * CAR_PUSH, 0.0, 20.0)
	_car_hit_list(bodies, at, dir, push, speed)
	_car_hit_list(debris, at, dir, push, speed)


func _car_hit_list(list: Array, at: Vector3, dir: Vector3, push: float, speed: float) -> void:
	for b in list:
		if not bool(b["alive"]) or float(b["hit_cool"]) > 0.0:
			continue
		var pos: Vector3 = b["pos"]
		if absf(pos.y - at.y) > 2.2:
			continue
		var flat := Vector2(pos.x - at.x, pos.z - at.z).length()
		if flat > CAR_REACH + float(b["radius"]):
			continue
		# O objeto sai a ~1,15x a velocidade do carro e o carro leva um
		# arranhao proporcional ao peso do que ele acertou.
		PropBody.impulse(b, dir, push * float(b["mass"]))
		b["hit_cool"] = 0.5
		car.add_damage(clampf(float(b["mass"]) * 0.0015, 0.0, 0.03))
		var state := PropBody.apply_damage(b, Damage.hit_power(CAR_MASS, speed))
		_bump(clampf(speed / 20.0, 0.25, 1.0), pos)
		if state == Damage.DESTROYED:
			_break(b)


func _push_near(list: Array, at: Vector3, radius: float, dir: Vector3, power: float,
		hurt: float) -> void:
	for b in list:
		if not bool(b["alive"]):
			continue
		var pos: Vector3 = b["pos"]
		if absf(pos.y - at.y) > 2.2:
			continue
		if Vector2(pos.x - at.x, pos.z - at.z).length() > radius + float(b["radius"]):
			continue
		PropBody.impulse(b, dir, power)
		if hurt > 0.0:
			var state := PropBody.apply_damage(b, hurt)
			_bump(0.3, pos)
			if state == Damage.DESTROYED:
				_break(b)


# --- Simulacao --------------------------------------------------------------

func _step_list(list: Array, delta: float, focus: Vector3) -> void:
	for b in list:
		if not bool(b["alive"]):
			continue
		b["hit_cool"] = maxf(0.0, float(b["hit_cool"]) - delta)
		var pos: Vector3 = b["pos"]
		var far := Vector2(pos.x - focus.x, pos.z - focus.z).length()
		if far > LOD_REDUCED:
			continue                      # LOD 2: estado guardado, sem integrar
		var dt := delta
		if far > LOD_FULL:
			# LOD 1: mesma fisica, chamada a 20 Hz com o tempo real acumulado.
			b["lod_acc"] = float(b["lod_acc"]) + delta
			if float(b["lod_acc"]) < LOD_STEP:
				continue
			dt = float(b["lod_acc"])
			b["lod_acc"] = 0.0
		var kind := SurfaceDB.kind_at(pos.x, pos.z)
		var ground := Cfg.surface_at(pos.x, pos.z)
		# Se o chao mudou debaixo de um objeto dormindo (meio-fio, rampa), acorda.
		if bool(b["rest"]):
			var half := PropBody.half_height(String(b["kind"]))
			if absf(pos.y - half - ground) > 0.05:
				PropBody.wake(b)
		PropBody.step(b, dt, ground, SurfaceDB.slide(kind), SurfaceDB.bounce(kind))
		_wall(b)


## Parede de predio: usa o MESMO push_out do carro e do personagem.
func _wall(b: Dictionary) -> void:
	if streamer == null:
		return
	var pos: Vector3 = b["pos"]
	var pushed: Vector2 = streamer.push_out(pos.x, pos.z, float(b["radius"]))
	if pushed.distance_to(Vector2(pos.x, pos.z)) < 0.001:
		return
	b["pos"] = Vector3(pushed.x, pos.y, pushed.y)
	var vel: Vector3 = b["vel"]
	# Bateu e volta com 35% da velocidade horizontal (o vertical continua).
	b["vel"] = Vector3(-vel.x * 0.35, vel.y, -vel.z * 0.35)


# --- Destruicao -------------------------------------------------------------

## Vira destrocos: alguns fragmentos pequenos, com teto global, e o objeto sai.
func _break(b: Dictionary) -> void:
	var pos: Vector3 = b["pos"]
	var base: Color = b["color"]
	var room := MAX_DEBRIS - debris.size()
	var count := mini(Damage.debris_count(String(b["mat"])), maxi(0, room))
	for i in count:
		var at := pos + Vector3(rng.randf_range(-0.25, 0.25),
				rng.randf_range(-0.1, 0.35), rng.randf_range(-0.25, 0.25))
		var piece := PropBody.make("destroco", at, rng.randf_range(-PI, PI))
		# O destroco herda o MATERIAL (som) e a cor escurecida do que quebrou.
		piece["mat"] = String(b["mat"])
		piece["color"] = base.darkened(0.35)
		piece["life"] = rng.randf_range(8.0, 13.0)
		piece["vel"] = Vector3(rng.randf_range(-3.5, 3.5),
				rng.randf_range(1.2, 3.8), rng.randf_range(-3.5, 3.5))
		debris.append(piece)
	b["alive"] = false


func _age_debris(delta: float) -> void:
	var i := debris.size() - 1
	while i >= 0:
		var b: Dictionary = debris[i]
		var life := float(b["life"]) - delta
		b["life"] = life
		if not bool(b["alive"]) or life <= 0.0:
			debris.remove_at(i)
		i -= 1
	while debris.size() > MAX_DEBRIS:
		debris.remove_at(0)


## Remove o que foi destruido e repoe com outro objeto perto do jogador: a rua
## nunca fica vazia nem acumula lixo de fisica.
func _compact() -> void:
	var i := bodies.size() - 1
	while i >= 0:
		if not bool(bodies[i]["alive"]):
			bodies.remove_at(i)
		i -= 1
	while bodies.size() < MAX_PROPS and _have_focus:
		_spawn_near(_last_focus)


func _spawn_near(origin: Vector3) -> void:
	var kind := String(PROP_KINDS[rng.randi_range(0, PROP_KINDS.size() - 1)])
	var spot := _land_spot(origin)
	var body := PropBody.make(kind, spot, rng.randf_range(-PI, PI))
	PropBody.place_on_ground(body, Cfg.surface_at(spot.x, spot.z))
	bodies.append(body)


## Ponto livre no chao perto de `origin` (fora da agua e fora de predio).
func _land_spot(origin: Vector3) -> Vector3:
	for i in 10:
		var ang := rng.randf_range(-PI, PI)
		var rad := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var x := clampf(origin.x + cos(ang) * rad, Cfg.WORLD_MIN.x + 2.0, Cfg.WORLD_MAX.x - 2.0)
		var z := clampf(origin.z + sin(ang) * rad, 2.0, Cfg.WORLD_MAX.y - 2.0)
		if Cfg.height_at(x, z) < Cfg.MIN_WADE_DEPTH:
			continue                       # agua
		if streamer != null:
			var free_at: Vector2 = streamer.push_out(x, z, 0.8)
			if free_at.distance_to(Vector2(x, z)) > 0.01:
				continue                   # dentro de predio
		return Vector3(x, Cfg.surface_at(x, z), z)
	return Vector3(origin.x, Cfg.surface_at(origin.x, origin.z), origin.z)


## Objeto muito longe: volta para perto do jogador (reciclagem, nao acumula).
func _recycle(focus: Vector3) -> void:
	for b in bodies:
		var pos: Vector3 = b["pos"]
		if Vector2(pos.x - focus.x, pos.z - focus.z).length() < RECYCLE_RANGE:
			continue
		var spot := _land_spot(focus)
		b["pos"] = spot
		b["yaw"] = rng.randf_range(-PI, PI)
		b["hp"] = float(b["max_hp"])
		b["state"] = Damage.INTACT
		b["hit_cool"] = 0.0
		PropBody.place_on_ground(b, Cfg.surface_at(spot.x, spot.z))


# --- Desenho ----------------------------------------------------------------

## Junta os objetos por FORMA (3 MultiMesh no total), escreve transform e cor e
## esconde o resto: nenhuma chamada de desenho por objeto.
func _draw(focus: Vector3) -> void:
	var groups := {"box": [], "cyl": [], "cone": []}
	for b in bodies:
		_collect(groups, b, focus)
	for b in debris:
		_collect(groups, b, focus)
	for mesh_kind in groups:
		var mm: MultiMesh = _mm_data.get(mesh_kind)
		if mm == null:
			continue
		var list: Array = groups[mesh_kind]
		var n := mini(list.size(), mm.instance_count)
		for i in n:
			var b: Dictionary = list[i]
			var size: Vector3 = b["size"]
			var at: Vector3 = b["pos"]
			var basis := Basis(Vector3.UP, float(b["yaw"])).scaled(size)
			mm.set_instance_transform(i, Transform3D(basis, at))
			mm.set_instance_color(i, _color_of(b))
		mm.visible_instance_count = n


func _collect(groups: Dictionary, b: Dictionary, focus: Vector3) -> void:
	if not bool(b["alive"]):
		return
	var pos: Vector3 = b["pos"]
	if Vector2(pos.x - focus.x, pos.z - focus.z).length() > DRAW_RANGE:
		return
	var mesh_kind := String(b["mesh"])
	if not groups.has(mesh_kind):
		return
	# Array e por referencia: anexar aqui escreve no grupo guardado.
	var arr: Array = groups[mesh_kind]
	arr.append(b)


## Cor da instancia: tipo + avaria (danificado/destruido escurece).
func _color_of(b: Dictionary) -> Color:
	var c: Color = b["color"]
	var state := int(b["state"])
	if state == Damage.DAMAGED:
		return c.darkened(0.22)
	if state == Damage.DESTROYED:
		return c.darkened(0.45)
	return c


func _bump(strength: float, at: Vector3) -> void:
	if _bump_cool > 0.0:
		return
	_bump_cool = 0.12
	bumped.emit(clampf(strength, 0.0, 1.0), SurfaceDB.sound(SurfaceDB.kind_at(at.x, at.z)))


# --- Telemetria -------------------------------------------------------------

func describe() -> String:
	var awake := 0
	for b in bodies:
		if not bool(b["rest"]):
			awake += 1
	return "props %d (%d acordados) + %d destrocos   LOD %.0f/%.0f m" % [
		bodies.size(), awake, debris.size(), LOD_FULL, LOD_REDUCED]
