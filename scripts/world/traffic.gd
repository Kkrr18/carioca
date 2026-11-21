extends Node3D
## Traffic: carros de passeio andando pela grade de ruas (Fase 4, transito basico).
##
## - Malha de ruas: a mesma grade do city_gen (ruas a cada BLOCK metros, em
##   x = multiplo de 64 e z = CITY_MIN_Z + j * 64). Um carro anda de no em no;
##   em cada cruzamento escolhe seguir reto (60%) ou virar (20% cada lado),
##   sem dar meia-volta. Mao direita: a faixa fica do lado direito do sentido.
## - Visual barato: um MultiMesh por modelo. Cada modelo (carros CC0 da
##   Quaternius) e assado numa malha unica com cor de vertice (bake), entao o
##   transito inteiro custa uma chamada de desenho por modelo.
## - O transito ACOMPANHA o jogador: carro que ficou longe demais volta para
##   perto, fora do campo de visao (senao a cidade fica vazia quando ele acelera
##   para longe do nascimento). Ha distancia minima entre carros e colisao com o
##   carro do jogador (hit_test).
## - Semaforos: quatro postes por cruzamento (um por canto), desenhados em dois
##   MultiMesh (poste+carcaca e lentes), entao a cidade inteira de semaforos
##   custa 2 chamadas de desenho. O ciclo verde/amarelo/vermelho e defasado por
##   cruzamento. O carro para na linha de retencao no vermelho e atravessa no
##   verde; quem ja entrou no cruzamento termina de passar.
## - Ainda NAO: rodas girando, pedestres, faixa exclusiva de onibus.
## - A logica (advance, choose_heading, pose, place_near, hit_test) e pura e
##   testada no CI sem cena.

const Cfg = preload("res://scripts/core/cfg.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")
const SurfaceDB = preload("res://scripts/core/surface_db.gd")
const VehiclePhysics = preload("res://scripts/vehicles/vehicle_physics.gd")

const LANE := 2.5                       # m do eixo da rua ate o centro da faixa
const BLOCK := Cfg.BLOCK_SIZE           # 64 m entre cruzamentos
const ORIGIN := Vector2(1280.0, 128.0)  # no (0, 0): x = 1280, z = CITY_MIN_Z
const GRID := Vector2i(10, 6)           # janela de nascimento (perto do spawn)
const SPEED_MIN := 5.0                  # m/s (~18 km/h)
const SPEED_MAX := 9.0                  # m/s (~32 km/h)
const LAT_RATE := 4.0                   # m/s com que a faixa se ajusta numa curva

# --- Ficha por modelo (B-70): o SUV nao anda como um hatch -------------------
# A ordem segue MODEL_PATHS: sedan, SUV, esportivo, taxi.
const MODEL_SPECS := ["sedan", "suv", "sport", "sedan"]
## Raio (m) da curva de 90 graus na esquina e a distancia em que o carro ja
## alivia o acelerador para fazer a curva (m).
const TURN_RADIUS := 7.0
const CORNER_ZONE := 16.0

# Grade inteira da cidade desenhada (CITY_MIN_Z ate CITY_MAX_Z, x de 0 a 6144):
# os carros podem circular por toda ela, nao so pela janela do nascimento.
const CITY_MIN := Vector2i(-20, 0)
const CITY_MAX := Vector2i(76, 34)

const CAR_RADIUS := 1.45                # raio de colisao do carro de transito (m)
const GAP_LOOK := 14.0                  # distancia em que o carro de tras alivia
const GAP_MIN := 4.5                    # distancia em que ele para de vez
const GAP_LATERAL := 2.4                # so freia se estiver na mesma faixa
const RESPAWN_NEAR := 150.0             # ao voltar para perto: de 150 a...
const RESPAWN_FAR := 260.0              # ...260 m do jogador (fora do susto)

# --- Semaforos ---------------------------------------------------------------
const STOP_BEFORE := 5.0        # linha de retencao: m antes do centro do cruzamento
const LIGHT_RADIUS := 190.0     # raio (m) em volta do jogador em que aparecem
const LIGHT_OFF := 6.4          # do centro do cruzamento ate o poste (na calcada)
const LIGHT_CYCLE := 26.0       # um ciclo completo das duas vias (s)
const LIGHT_GREEN := 10.0
const LIGHT_YELLOW := 2.0
const LIGHT_ALL_RED := 1.0      # seguranca entre as fases
const LENS_RED := Color(0.95, 0.16, 0.10)
const LENS_YELLOW := Color(1.00, 0.80, 0.15)
const LENS_GREEN := Color(0.10, 0.90, 0.35)

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const MODEL_PATHS := [
	"res://assets/models/quaternius-car.glb",
	"res://assets/models/quaternius-suv.glb",
	"res://assets/models/quaternius-sports-car.glb",
	"res://assets/models/quaternius-taxi.glb",
]
const MODEL_LENGTHS := [4.3, 4.2, 3.9, 4.2]

var cars_total := 12
var models_loaded := 0
var cars: Array = []
var _mats_mm: Array = []      # MultiMeshInstance3D, um por modelo carregado
var _material: StandardMaterial3D
var _follow_t := 0.0          # relogio do "acompanhar o jogador"
var _clock := 0.0             # relogio do transito (fases do semaforo)
var _light_body: MultiMeshInstance3D
var _light_lens: MultiMeshInstance3D
var _light_items: Array = []  # {n, sx, sz} de cada semaforo em cena
var _light_node := Vector2i(999999, 999999)   # no do jogador no ultimo rebuild
var _light_t := 0.0           # throttle da cor das lentes


# --- Nucleo puro (sem cena; testado em tests/runner.gd) ----------------------

static func node_pos(n: Vector2i) -> Vector2:
	return ORIGIN + Vector2(n) * BLOCK


static func valid(n: Vector2i) -> bool:
	return n.x >= CITY_MIN.x and n.x <= CITY_MAX.x and n.y >= CITY_MIN.y and n.y <= CITY_MAX.y


## No da grade mais proximo de uma posicao do mundo (metros).
static func nearest_node(p: Vector2) -> Vector2i:
	return Vector2i(
		int(round((p.x - ORIGIN.x) / BLOCK)),
		int(round((p.y - ORIGIN.y) / BLOCK)))


## Poe o carro perto de `focus`, a uma distancia entre near_m e far_m, numa rua
## valida. Usado ao nascer e para trazer de volta quem ficou longe. Devolve
## false se nao achou posicao (grade pequena, por exemplo).
static func place_near(car: Dictionary, focus: Vector3, near_m: float, far_m: float) -> bool:
	var rng: RandomNumberGenerator = car["rng"]
	for attempt in 12:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(near_m, far_m)
		var p := Vector2(focus.x, focus.z) + Vector2(cos(ang), sin(ang)) * d
		var n := nearest_node(p)
		if not valid(n):
			continue
		var h: Vector2i = DIRS[rng.randi_range(0, DIRS.size() - 1)]
		if not valid(n + h):
			continue
		car["node"] = n
		car["h"] = h
		car["s"] = rng.randf() * BLOCK
		car["lat"] = Vector2(right_of(h)) * LANE
		car["speed"] = rng.randf_range(SPEED_MIN, SPEED_MAX)
		car["pace"] = 1.0
		# Carro com ficha (B-70): volta na velocidade de cruzeiro DELE e ja em
		# movimento (nao nasce acelerando do zero depois de um respawn).
		if car.has("spec"):
			car["speed"] = cruise_speed(car["spec"], rng.randf())
		if car.has("v"):
			car["v"] = float(car["speed"])
		return true
	return false


## Faixa da direita do sentido h (mao direita). Para h = (1, 0) (leste) da (0, 1).
static func right_of(h: Vector2i) -> Vector2i:
	return Vector2i(-h.y, h.x)


# --- Fichas dos veiculos (B-70) ---------------------------------------------

## Ficha do veiculo pelo indice do modelo carregado. Desconhecido = sedan.
static func spec_for_model(model: int) -> Dictionary:
	var key := "sedan"
	if model >= 0 and model < MODEL_SPECS.size():
		key = String(MODEL_SPECS[model])
	match key:
		"suv":
			return VehiclePhysics.suv()
		"sport":
			return VehiclePhysics.sport()
		"compact":
			return VehiclePhysics.compact()
		_:
			return VehiclePhysics.sedan()


## Velocidade de cruzeiro pela ficha: carro com mais forca por peso anda mais na
## mesma avenida (o esportivo puxa na frente, o SUV fica no ritmo de passeio).
static func cruise_speed(spec: Dictionary, r: float) -> float:
	var score := clampf(VehiclePhysics.power_to_weight(spec) / 5.9, 0.80, 1.15)
	return lerpf(SPEED_MIN, SPEED_MAX, clampf(r, 0.0, 1.0)) * score


## Aceleracao (m/s2) e freio (m/s2) que a ficha aguenta. O freio e o que mais
## separa os modelos: o SUV de 2200 kg precisa de mais distancia para parar.
static func accel_of(spec: Dictionary) -> float:
	if spec.is_empty():
		return 2.6
	return clampf(VehiclePhysics.power_to_weight(spec) * 0.45, 1.6, 3.8)


static func brake_of(spec: Dictionary) -> float:
	if spec.is_empty():
		return 5.3
	return clampf(float(spec["brake"]) / maxf(1.0, float(spec["mass"])) * 0.7, 3.5, 7.5)


## Limite na curva de 90 graus: v = sqrt(mu*g*R). Centro de gravidade alto
## derruba o limite — o SUV faz a esquina mais devagar que o esportivo.
static func corner_speed(spec: Dictionary) -> float:
	if spec.is_empty():
		return 8.3
	var com := maxf(0.35, float(spec.get("com_height", 0.55)))
	var base := sqrt(SurfaceDB.MU_ASPHALT * VehiclePhysics.GRAVITY * TURN_RADIUS)
	return clampf(base * (0.55 / com), 4.0, 20.0)


## Poe a ficha no carro: modelo -> massa/freio/CG, ritmo de cruzeiro e limite de
## curva. `v` e a velocidade REAL (sobe e desce pela ficha, ver advance()).
static func apply_spec(car: Dictionary) -> void:
	var spec := spec_for_model(int(car.get("model", 0)))
	car["spec"] = spec
	car["corner"] = corner_speed(spec)
	var r := clampf(float(car.get("speed", SPEED_MAX)) / SPEED_MAX, 0.0, 1.0)
	car["speed"] = cruise_speed(spec, r)
	car["v"] = float(car["speed"])
	car["pace"] = 1.0


## Deslocamento de fase do cruzamento: assim os semaforos da cidade nao trocam
## todos no mesmo instante (e o transito flui em ondas).
static func light_offset(n: Vector2i) -> float:
	return float(absi(n.x * 7 + n.y * 11) % 13)


## Estado das duas vias no cruzamento `n` no instante `t`:
## Vector2i(norte-sul, leste-oeste) com 2 = verde, 1 = amarelo, 0 = vermelho.
static func light_states(n: Vector2i, t: float) -> Vector2i:
	var tt := fposmod(t + light_offset(n), LIGHT_CYCLE)
	if tt < LIGHT_GREEN:
		return Vector2i(2, 0)
	tt -= LIGHT_GREEN
	if tt < LIGHT_YELLOW:
		return Vector2i(1, 0)
	tt -= LIGHT_YELLOW
	if tt < LIGHT_ALL_RED:
		return Vector2i(0, 0)
	tt -= LIGHT_ALL_RED
	if tt < LIGHT_GREEN:
		return Vector2i(0, 2)
	tt -= LIGHT_GREEN
	if tt < LIGHT_YELLOW:
		return Vector2i(0, 1)
	return Vector2i(0, 0)


static func lens_color(state: int) -> Color:
	if state == 2:
		return LENS_GREEN
	if state == 1:
		return LENS_YELLOW
	return LENS_RED


## O carro que vem no sentido h, a `s` metros do no anterior, tem que parar?
## Quem ja passou da linha de retencao NAO para: termina de atravessar.
static func must_stop(n: Vector2i, h: Vector2i, s: float, t: float) -> bool:
	if s > BLOCK - STOP_BEFORE + 0.01:
		return false
	var st := light_states(n + h, t)
	var verde := st.x == 2 if h.x == 0 else st.y == 2
	return not verde


## Malha do poste + carcaca do semaforo (duas caixas): base em y = 0, frente
## em -Z. Cores de vertice, para um material so.
static func light_body_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	_append_box(v, n, c, Vector3(0.0, 1.70, 0.0), Vector3(0.12, 3.40, 0.12), Color(0.17, 0.18, 0.20))
	_append_box(v, n, c, Vector3(0.0, 3.10, -0.06), Vector3(0.34, 0.90, 0.22), Color(0.09, 0.09, 0.10))
	return _mesh_from(v, n, c)


## Malha da lente: caixinha branca na frente da carcaca. A cor (vermelho,
## amarelo, verde) vem da cor de instancia do MultiMesh.
static func lens_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	_append_box(v, n, c, Vector3(0.0, 3.10, -0.19), Vector3(0.24, 0.24, 0.06), Color.WHITE)
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


static func _mesh_from(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Proximo sentido num cruzamento. r em [0, 1). Reto 60%, cada curva 20%.
## Nunca sai da grade; so volta atras se nao houver nenhuma outra saida.
static func choose_heading(n: Vector2i, h: Vector2i, r: float) -> Vector2i:
	var cands := [[h, 0.6], [Vector2i(-h.y, h.x), 0.2], [Vector2i(h.y, -h.x), 0.2]]
	var ok: Array = []
	var total := 0.0
	for c in cands:
		var d: Vector2i = c[0]
		if valid(n + d):
			ok.append(c)
			total += float(c[1])
	if ok.is_empty():
		return -h
	var pick := r * total
	for c in ok:
		pick -= float(c[1])
		if pick < 0.0:
			var chosen: Vector2i = c[0]
			return chosen
	var last: Vector2i = ok[ok.size() - 1][0]
	return last


## Carro novo num no e sentido validos. `rng_seed` define todo o comportamento
## dele (deterministico: mesmo seed, mesma rota).
static func spawn_car(rng_seed: int, index: int, model: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var n := Vector2i(rng.randi_range(0, GRID.x - 1), rng.randi_range(0, GRID.y - 1))
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var h: Vector2i = dirs[rng.randi_range(0, 3)]
	if not valid(n + h):
		h = -h
	return {
		"node": n,
		"h": h,
		"s": rng.randf() * BLOCK,
		"lat": Vector2(right_of(h)) * LANE,
		"speed": rng.randf_range(SPEED_MIN, SPEED_MAX),
		"rng": rng,
		"model": model,
		"index": index,
	}


## Avanca o carro dt segundos. Ao passar de um no, escolhe a proxima rua.
## A faixa ('lat') desliza ate a faixa certa do novo sentido, sem salto.
## `t` e o relogio do mundo: e ele que diz se o semaforo esta aberto.
static func advance(car: Dictionary, dt: float, t: float = 0.0) -> void:
	# 'pace' vem do espacamento (0 = parado atras de outro carro).
	var pace: float = clampf(float(car.get("pace", 1.0)), 0.0, 1.0)
	var s: float = float(car["s"])
	var n: Vector2i = car["node"]
	var h: Vector2i = car["h"]
	var step: float = float(car["speed"]) * pace * dt
	# B-70: carro COM ficha ("v") tem velocidade real, que sobe e desce pela
	# aceleracao/freio do modelo, freia no semaforo e reduz antes da esquina. Sem
	# "v" (dicionario montado a mao em teste) vale o modelo antigo.
	if car.has("v"):
		var want_speed := float(car["speed"]) * pace
		# Semaforo fechado: FREIA ate a linha, em vez de so travar a posicao.
		if must_stop(n, h, s, t):
			want_speed = 0.0
		var corner := float(car.get("corner", 0.0))
		if want_speed > 0.0 and corner > 0.0 and s > BLOCK - CORNER_ZONE:
			want_speed = minf(want_speed, corner)
		var spec: Dictionary = car.get("spec", {})
		var v := float(car["v"])
		var rate := accel_of(spec) if want_speed > v else brake_of(spec)
		v = move_toward(v, want_speed, rate * dt)
		car["v"] = v
		step = v * dt
	# Semaforo fechado: para na linha de retencao.
	if must_stop(n, h, s, t):
		s = minf(s + step, BLOCK - STOP_BEFORE)
	else:
		s += step
	var rng: RandomNumberGenerator = car["rng"]
	while s >= BLOCK:
		s -= BLOCK
		n = n + h
		h = choose_heading(n, h, rng.randf())
	car["s"] = s
	car["node"] = n
	car["h"] = h
	var lat: Vector2 = car["lat"]
	var target := Vector2(right_of(h)) * LANE
	car["lat"] = lat.move_toward(target, LAT_RATE * dt)


## Transform do carro no mundo: posicao no chao analitico e rumo do sentido.
## O modelo tem a frente em -Z (ver ModelProp), como o carro dirigivel.
static func pose(car: Dictionary) -> Transform3D:
	var n: Vector2i = car["node"]
	var h: Vector2i = car["h"]
	var lat: Vector2 = car["lat"]
	var p := node_pos(n) + Vector2(h) * float(car["s"]) + lat
	var y := Cfg.surface_at(p.x, p.y) + 0.05
	var theta := atan2(-float(h.x), -float(h.y))
	return Transform3D(Basis(Vector3.UP, theta), Vector3(p.x, y, p.y))


## Assa um modelo carregado numa malha unica: vertices no espaco do modelo
## normalizado, cor de vertice = cor do material da peca. Um ArrayMesh, uma
## superficie por peca original.
static func bake(mp: Node3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for mi in ModelProp.collect_meshes(mp):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var xf := ModelProp.rel_xf(m, mp)
		var nb := xf.basis
		for si in m.mesh.get_surface_count():
			var src: Array = m.mesh.surface_get_arrays(si)
			if src.size() <= Mesh.ARRAY_VERTEX or not (src[Mesh.ARRAY_VERTEX] is PackedVector3Array):
				continue
			var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
			var out_v := PackedVector3Array()
			out_v.resize(verts.size())
			for i in verts.size():
				out_v[i] = xf * verts[i]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = out_v
			if src.size() > Mesh.ARRAY_NORMAL and src[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				var ns: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
				var out_n := PackedVector3Array()
				out_n.resize(ns.size())
				for i in ns.size():
					out_n[i] = (nb * ns[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = out_n
			var cols := PackedColorArray()
			cols.resize(verts.size())
			cols.fill(_albedo(m.mesh.surface_get_material(si)))
			arr[Mesh.ARRAY_COLOR] = cols
			if src.size() > Mesh.ARRAY_INDEX and src[Mesh.ARRAY_INDEX] is PackedInt32Array:
				arr[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


static func _albedo(mat: Material) -> Color:
	var bm := mat as BaseMaterial3D
	if bm == null:
		return Color(0.7, 0.7, 0.7)
	return bm.albedo_color


# --- Cena ---------------------------------------------------------------------

## Carrega os modelos, assa cada um e cria os carros. Modelos que nao carregam
## sao pulados; se nenhum carregar, o transito fica vazio e describe() diz por que.
## `focus` (posicao do jogador) faz os carros nascerem em volta dele.
func setup(base_seed: int, focus: Vector3 = Vector3.ZERO) -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = false
	_material.roughness = 0.6
	_material.metallic_specular = 0.4

	var meshes: Array = []
	for i in MODEL_PATHS.size():
		var mp := ModelProp.new()
		mp.model_path = MODEL_PATHS[i]
		mp.target_length = MODEL_LENGTHS[i]
		mp.load_model()
		if mp.loaded:
			meshes.append(bake(mp))
		mp.free()
	models_loaded = meshes.size()
	if meshes.is_empty():
		return

	cars.clear()
	for k in cars_total:
		var c := spawn_car(base_seed + k * 7919, k, k % meshes.size())
		if focus != Vector3.ZERO:
			place_near(c, focus, 30.0, 130.0)
		# Ficha por modelo (B-70): o SUV da rua freia antes e faz a curva mais
		# devagar que o hatch; o esportivo anda mais.
		apply_spec(c)
		cars.append(c)

	for m in meshes.size():
		var n := 0
		for c in cars:
			if int(c["model"]) == m:
				n += 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[m]
		mm.instance_count = n
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "TrafficModel%d" % m
		mmi.multimesh = mm
		mmi.material_override = _material
		add_child(mmi)
		_mats_mm.append(mmi)
	_build_lights()
	if focus != Vector3.ZERO:
		_light_node = nearest_node(Vector2(focus.x, focus.z))
		_rebuild_lights(focus)
	update(0.0)


## Um passo do transito: mantem os carros perto do jogador, aplica a distancia
## entre eles, anda e reescreve as transformacoes.
func update(delta: float, focus: Vector3 = Vector3.ZERO) -> void:
	_clock += delta
	if focus != Vector3.ZERO:
		_follow(focus, delta)
		# Semaforos: so os de perto ficam em cena (nao adianta desenhar os de
		# 3 km). Reconstroi quando o jogador muda de no.
		var fc := nearest_node(Vector2(focus.x, focus.z))
		if fc != _light_node:
			_light_node = fc
			_rebuild_lights(focus)
	_apply_spacing()
	for c in cars:
		if delta > 0.0:
			advance(c, delta, _clock)
	_write_instances()
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.1
		_update_lenses()


## Carro que ficou longe demais volta para perto (fora do campo de visao), para
## a cidade nao ficar vazia quando o jogador acelera para longe do nascimento.
func _follow(focus: Vector3, delta: float) -> void:
	_follow_t -= delta
	if _follow_t > 0.0:
		return
	_follow_t = 0.5
	for c in cars:
		var o: Vector3 = pose(c).origin
		if Vector2(o.x - focus.x, o.z - focus.z).length() > RESPAWN_FAR:
			place_near(c, focus, RESPAWN_NEAR, RESPAWN_FAR)


## Distancia entre carros: quem vem atras alivia o acelerador e para se preciso.
## Sem isso dois carros ficam um dentro do outro num cruzamento.
func _apply_spacing() -> void:
	var poses: Array = []
	for c in cars:
		poses.append(pose(c).origin)
	for i in cars.size():
		var a: Dictionary = cars[i]
		var pa: Vector3 = poses[i]
		var h: Vector2i = a["h"]
		var fwd := Vector3(float(h.x), 0.0, float(h.y))
		var pace := 1.0
		for j in cars.size():
			if i == j:
				continue
			var d: Vector3 = poses[j] - pa
			var along := d.dot(fwd)
			if along <= 0.5 or along >= GAP_LOOK:
				continue
			if (d - fwd * along).length() > GAP_LATERAL:
				continue
			pace = minf(pace, clampf((along - GAP_MIN) / (GAP_LOOK - GAP_MIN), 0.0, 1.0))
		a["pace"] = pace


func _write_instances() -> void:
	var used := PackedInt32Array()
	used.resize(_mats_mm.size())
	for c in cars:
		var m: int = c["model"]
		var mm: MultiMesh = _mats_mm[m].multimesh
		mm.set_instance_transform(used[m], pose(c))
		used[m] += 1


## Colisao do carro do jogador com o transito (circulos no plano XZ).
## Devolve {} se estiver livre, ou {"pushed": Vector3, "normal": Vector3} com a
## posicao corrigida para fora do outro carro.
func hit_test(pos: Vector3, radius: float) -> Dictionary:
	var min_d := radius + CAR_RADIUS
	for c in cars:
		var o: Vector3 = pose(c).origin
		var d := Vector2(pos.x - o.x, pos.z - o.z)
		var dist := d.length()
		if dist >= min_d:
			continue
		var nrm := d / dist if dist > 0.001 else Vector2(1.0, 0.0)
		return {
			"pushed": Vector3(o.x + nrm.x * min_d, pos.y, o.z + nrm.y * min_d),
			"normal": Vector3(nrm.x, 0.0, nrm.y),
		}
	return {}


## Dois MultiMesh para todos os semaforos: poste+carcaca (estatico) e lentes
## (a cor muda com a fase). Dois desenhos por quadro, independente da cidade.
func _build_lights() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.vertex_color_use_as_albedo = true
	body_mat.vertex_color_is_srgb = false
	body_mat.roughness = 0.7
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.mesh = light_body_mesh()
	bmm.instance_count = 0
	_light_body = MultiMeshInstance3D.new()
	_light_body.name = "TrafficLights"
	_light_body.multimesh = bmm
	_light_body.material_override = body_mat
	add_child(_light_body)

	# Lente: sem sombreamento, para ler como luz acesa de dia e de noite.
	var lens_mat := StandardMaterial3D.new()
	lens_mat.vertex_color_use_as_albedo = true
	lens_mat.vertex_color_is_srgb = false
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.use_colors = true
	lmm.mesh = lens_mesh()
	lmm.instance_count = 0
	_light_lens = MultiMeshInstance3D.new()
	_light_lens.name = "TrafficLightLenses"
	_light_lens.multimesh = lmm
	_light_lens.material_override = lens_mat
	add_child(_light_lens)


## Poe um semaforo em cada canto dos cruzamentos dentro do raio do jogador.
## O poste fica na calcada, e cada um olha para o carro que ele governa: quem
## vem do leste/oeste ve o poste do canto, na direita do sentido (mao direita).
func _rebuild_lights(focus: Vector3) -> void:
	if _light_body == null:
		return
	var c := nearest_node(Vector2(focus.x, focus.z))
	var reach := int(ceil(LIGHT_RADIUS / BLOCK))
	var items: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var n := c + Vector2i(dx, dz)
			if not valid(n):
				continue
			var np := node_pos(n)
			if Vector2(np.x - focus.x, np.y - focus.z).length() > LIGHT_RADIUS:
				continue
			for k in 4:
				var sx := 1.0 if (k & 1) == 0 else -1.0
				var sz := 1.0 if (k & 2) == 0 else -1.0
				items.append({"n": n, "sx": sx, "sz": sz})
	_light_items = items
	_light_body.multimesh.instance_count = items.size()
	_light_lens.multimesh.instance_count = items.size()
	for i in items.size():
		var it: Dictionary = items[i]
		var nn: Vector2i = it["n"]
		var np := node_pos(nn)
		var sx: float = it["sx"]
		var sz: float = it["sz"]
		var p := np + Vector2(sx * LIGHT_OFF, sz * LIGHT_OFF)
		var y := Cfg.surface_at(p.x, p.y)
		# Canto (+,+) e (-,-) servem quem anda em X; (-,+) e (+,-) quem anda em
		# Z. O poste olha contra o sentido do carro que ele governa.
		var dir := Vector2(-sx, 0.0) if sx * sz > 0.0 else Vector2(0.0, -sz)
		var theta := atan2(-dir.x, -dir.y)
		var xf := Transform3D(Basis(Vector3.UP, theta), Vector3(p.x, y, p.y))
		_light_body.multimesh.set_instance_transform(i, xf)
		_light_lens.multimesh.set_instance_transform(i, xf)
	_update_lenses()


## Cor de cada lente conforme a fase do cruzamento naquele instante.
func _update_lenses() -> void:
	if _light_lens == null or _light_items.is_empty():
		return
	for i in _light_items.size():
		var it: Dictionary = _light_items[i]
		var nn: Vector2i = it["n"]
		var st := light_states(nn, _clock)
		var ew := float(it["sx"]) * float(it["sz"]) > 0.0
		_light_lens.multimesh.set_instance_color(i, lens_color(st.y if ew else st.x))


func describe() -> String:
	if models_loaded == 0:
		return "transito: nenhum modelo carregou (rodar --import?)"
	return "transito: %d carros, %d modelos, %d cruzamentos com semaforo (%d desenhos por quadro)" % [
		cars.size(), models_loaded, _light_items.size() / 4, _mats_mm.size() + 2]
