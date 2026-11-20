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
## - Ainda NAO: semaforos, colisao com o jogador, rodas girando, distancia
##   entre carros. Cada um e um passo proprio da Fase 4.
## - A logica (advance, choose_heading, pose) e pura e testada no CI sem cena.

const Cfg = preload("res://scripts/core/cfg.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")

const LANE := 2.5                       # m do eixo da rua ate o centro da faixa
const BLOCK := Cfg.BLOCK_SIZE           # 64 m entre cruzamentos
const ORIGIN := Vector2(1280.0, 128.0)  # no (0, 0): x = 1280, z = CITY_MIN_Z
const GRID := Vector2i(10, 6)           # nos em x e em z: 9 x 5 quadras
const SPEED_MIN := 5.0                  # m/s (~18 km/h)
const SPEED_MAX := 9.0                  # m/s (~32 km/h)
const LAT_RATE := 4.0                   # m/s com que a faixa se ajusta numa curva

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


# --- Nucleo puro (sem cena; testado em tests/runner.gd) ----------------------

static func node_pos(n: Vector2i) -> Vector2:
	return ORIGIN + Vector2(n) * BLOCK


static func valid(n: Vector2i) -> bool:
	return n.x >= 0 and n.x < GRID.x and n.y >= 0 and n.y < GRID.y


## Faixa da direita do sentido h (mao direita). Para h = (1, 0) (leste) da (0, 1).
static func right_of(h: Vector2i) -> Vector2i:
	return Vector2i(-h.y, h.x)


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
static func advance(car: Dictionary, dt: float) -> void:
	var s: float = float(car["s"]) + float(car["speed"]) * dt
	var n: Vector2i = car["node"]
	var h: Vector2i = car["h"]
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
	var y := Cfg.height_at(p.x, p.y) + 0.05
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
func setup(base_seed: int) -> void:
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
		cars.append(spawn_car(base_seed + k * 7919, k, k % meshes.size()))

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
	update(0.0)


## Um passo do transito: anda os carros e reescreve as transformacoes.
func update(delta: float) -> void:
	var used := PackedInt32Array()
	used.resize(_mats_mm.size())
	for c in cars:
		if delta > 0.0:
			advance(c, delta)
		var m: int = c["model"]
		var mm: MultiMesh = _mats_mm[m].multimesh
		mm.set_instance_transform(used[m], pose(c))
		used[m] += 1


func describe() -> String:
	if models_loaded == 0:
		return "transito: nenhum modelo carregou (rodar --import?)"
	return "transito: %d carros, %d modelos (%d desenhos por quadro)" % [
		cars.size(), models_loaded, _mats_mm.size()]
