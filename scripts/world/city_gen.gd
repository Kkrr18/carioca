extends RefCounted
## CityGen: geracao PROCEDURAL e DETERMINISTICA de um setor do mundo.
##
## Sem estado global e sem aleatoriedade do motor: o mesmo (seed, setor, LOD)
## gera sempre os mesmos vertices. Roda em WorkerThreadPool (so arrays, sem nos).
##
## Retorno de generate(): [vertices, normais, cores, colisores, defs]
##   vertices/normais/cores: PackedVector3Array / PackedVector3Array / PackedColorArray,
##     3 vertices por triangulo, sem indices.
##   colisores: Array de Rect2 (XZ) dos predios.
##   defs: Array de Dictionary com props (palmeira, arvore, quiosque, guarda-sol).
## Convencao de frente: triangulo horario visto de fora (Godot). A normal de
## frente e -(b-a)x(d-a), que coincide com a normal salva.

const Cfg = preload("res://scripts/core/cfg.gd")

const LOD_FULL := 0
const LOD_FAR := 1

const BLOCK := Cfg.BLOCK_SIZE        # 64 m; grade alinhada a x=0 e z=CITY_MIN_Z
const ROAD := Cfg.ROAD_WIDTH         # 10 m, centrada na linha da quadra
const WALK := Cfg.SIDEWALK_WIDTH     # 3 m de calcada alem da meia-rua
const ALLEY := 2.0                   # vao entre lotes
const LOT_COLS := 2
const LOT_ROWS := 2
const FLAT_LIFT := 0.04              # superficies planas 4 cm acima do terreno
const PLAZA_LIFT := 0.08

const SAND := Color(0.86, 0.79, 0.64)
const SAND_WET := Color(0.70, 0.65, 0.55)
const SEABED := Color(0.20, 0.31, 0.30)
const ASPHALT := Color(0.21, 0.22, 0.24)
const WALK_COL := Color(0.63, 0.62, 0.59)
const PLAZA := Color(0.42, 0.52, 0.36)
const ROOF := Color(0.36, 0.34, 0.32)
const TRUNK := Color(0.34, 0.27, 0.18)
const LEAF := Color(0.22, 0.42, 0.24)
const GRASS := Color(0.33, 0.45, 0.27)
const FOREST := Color(0.20, 0.31, 0.18)

const PALETTE := [
	Color(0.90, 0.88, 0.82), Color(0.82, 0.80, 0.74), Color(0.94, 0.92, 0.86),
	Color(0.86, 0.80, 0.66), Color(0.72, 0.78, 0.76), Color(0.80, 0.70, 0.62),
	Color(0.68, 0.72, 0.78),
]

# Faces do cubo: [normal para fora, tangente ya, tangente za], com za x ya = normal.
const CUBE_FACES := [
	[Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
	[Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
]


# --- Geracao -----------------------------------------------------------------

## Gera o setor (sx, sz). Quadras pertencem ao setor que contem a sua origem:
## como a grade e alinhada a 64 m e os setores a 512 m, nenhuma quadra cruza
## a fronteira de setor (ver CITY_MIN_Z = 128 = 2 x 64).
static func generate(sx: int, sz: int, world_seed: int, lod: int) -> Array:
	var gb := GBuf.new()
	var defs: Array = []
	var colliders: Array = []
	var ox := float(sx) * Cfg.SECTOR_SIZE
	var oz := float(sz) * Cfg.SECTOR_SIZE
	var s := Cfg.SECTOR_SIZE

	_ground(gb, ox, oz)
	if sz == 0:
		_beach(gb, defs, ox, lod)

	var i0 := int(ceil(maxf(ox, 0.0) / BLOCK))
	var i1 := int(ceil((ox + s) / BLOCK)) - 1
	var j0 := int(ceil((oz - Cfg.CITY_MIN_Z) / BLOCK))
	var j1 := int(ceil((oz + s - Cfg.CITY_MIN_Z) / BLOCK)) - 1
	for j in range(j0, j1 + 1):
		var z_axis := Cfg.CITY_MIN_Z + float(j) * BLOCK
		if z_axis < Cfg.CITY_MIN_Z or z_axis > Cfg.CITY_MAX_Z:
			continue
		for i in range(i0, i1 + 1):
			_block(gb, defs, colliders, float(i) * BLOCK, z_axis, world_seed, i, j, lod)

	return [gb.v, gb.n, gb.c, colliders, defs]


# --- Terreno -----------------------------------------------------------------

static func ground_color(x: float, z: float) -> Color:
	if z < 0.0:
		return SEABED
	if z < Cfg.BEACH_EDGE_Z:
		var top := -0.6 + 1.8 * clampf(z / Cfg.BEACH_EDGE_Z, 0.0, 1.0)
		return SAND_WET if top < 0.2 else SAND
	if z > Cfg.CITY_MAX_Z:
		return FOREST if Cfg.height_at(x, z) > 25.0 else GRASS
	return WALK_COL


static func _ground(gb: GBuf, ox: float, oz: float) -> void:
	var cells := int(Cfg.SECTOR_SIZE / Cfg.CELL_SIZE)
	for cx in cells:
		for cz in cells:
			var x0 := ox + float(cx) * Cfg.CELL_SIZE
			var x1 := x0 + Cfg.CELL_SIZE
			var z0 := oz + float(cz) * Cfg.CELL_SIZE
			var z1 := z0 + Cfg.CELL_SIZE
			var a := Vector3(x0, Cfg.height_at(x0, z0), z0)
			var b := Vector3(x1, Cfg.height_at(x1, z0), z0)
			var c := Vector3(x1, Cfg.height_at(x1, z1), z1)
			var d := Vector3(x0, Cfg.height_at(x0, z1), z1)
			gb.normal(Vector3.UP)
			_add_quad(gb, a, b, c, d, ground_color(x0 + 16.0, z0 + 16.0))


# --- Orla --------------------------------------------------------------------

static func _beach(gb: GBuf, defs: Array, ox: float, lod: int) -> void:
	# Calcadao da Av. Atlantica: faixa clara entre z = 112 e z = 126.
	var z0 := 112.0
	var z1 := 126.0
	var end := ox + Cfg.SECTOR_SIZE
	var x := ox
	while x < end - 0.01:
		var x1 := minf(x + 64.0, end)
		var a := Vector3(x, Cfg.height_at(x, z0) + FLAT_LIFT, z0)
		var b := Vector3(x1, Cfg.height_at(x1, z0) + FLAT_LIFT, z0)
		var c := Vector3(x1, Cfg.height_at(x1, z1) + FLAT_LIFT, z1)
		var d := Vector3(x, Cfg.height_at(x, z1) + FLAT_LIFT, z1)
		gb.normal(Vector3.UP)
		_add_quad(gb, a, b, c, d, WALK_COL)
		x = x1
	if lod == LOD_FAR:
		return
	var rng := Rng.new(mix3(101, int(ox), 0))
	var px := ox + 8.0
	while px < end - 4.0:
		defs.append({"c": Vector3(px, Cfg.height_at(px, 88.0), 88.0), "kind": "palm", "h": 7.0})
		px += 32.0
	for k in 3:
		if not rng.chance(0.75):
			continue
		var kx := ox + rng.range_f(20.0, Cfg.SECTOR_SIZE - 20.0)
		var kz := rng.range_f(28.0, 84.0)
		var kind := "kiosk" if rng.chance(0.5) else "umbrella"
		defs.append({"c": Vector3(kx, Cfg.height_at(kx, kz), kz), "kind": kind, "hue": rng.unit()})


# --- Quadras -----------------------------------------------------------------

static func _block(gb: GBuf, defs: Array, colliders: Array, ax: float, az: float,
		world_seed: int, bi: int, bj: int, lod: int) -> void:
	# Semente propria da quadra: o conteudo nao depende do setor que a desenha.
	var rng := Rng.new(mix3(world_seed, bi * 4096 + 1, bj * 4096 + 7))
	var edge := ROAD * 0.5
	# Ruas: a quadra desenha a meia-rua de sua borda oeste e sul.
	_add_roads(gb, ax, az)
	# Calcada: miolo da quadra, entre as meias-ruas (sem sobreposicao com a rua).
	_add_flat(gb, ax + edge, az + edge, ax + BLOCK - edge, az + BLOCK - edge, WALK_COL)

	if rng.chance(0.07):
		_add_flat(gb, ax + 14.0, az + 14.0, ax + BLOCK - 14.0, az + BLOCK - 14.0, PLAZA, PLAZA_LIFT)
		if lod == LOD_FULL:
			var tx := ax + BLOCK * 0.42
			var tz := az + BLOCK * 0.55
			defs.append({"c": Vector3(tx, Cfg.height_at(tx, tz), tz), "kind": "tree", "h": rng.range_f(7.0, 11.0)})
		return

	# Area de lotes: miolo da calcada, menos a faixa de calcada.
	var x0 := ax + edge + WALK
	var z0 := az + edge + WALK
	var span := BLOCK - 2.0 * (edge + WALK)   # 48 m
	var lot_w := (span - ALLEY * float(LOT_COLS - 1)) / float(LOT_COLS)
	var lot_d := (span - ALLEY * float(LOT_ROWS - 1)) / float(LOT_ROWS)
	for a in LOT_COLS:
		for b in LOT_ROWS:
			var lx := x0 + lot_w * 0.5 + float(a) * (lot_w + ALLEY)
			var lz := z0 + lot_d * 0.5 + float(b) * (lot_d + ALLEY)
			_lot(gb, defs, colliders, rng, lx, lz, lot_w, lot_d, lod)


## Um lote. Sorteia SEMPRE todos os valores (mesmo em LOD far), para o layout
## nao mudar entre os dois LODs.
static func _lot(gb: GBuf, defs: Array, colliders: Array, rng: Rng,
		lx: float, lz: float, lot_w: float, lot_d: float, lod: int) -> void:
	var empty := not rng.chance(0.92)
	var floors := rng.range_i(1, 7)
	if rng.chance(0.18):
		floors = rng.range_i(9, 20)
	var w := lot_w - rng.range_f(1.0, 3.0)
	var d := lot_d - rng.range_f(1.0, 3.0)
	var col: Color = PALETTE[rng.range_i(0, PALETTE.size() - 1)]
	var awning := rng.chance(0.35)
	var shrub := rng.chance(0.55)
	var shrub_h := rng.range_f(2.5, 4.0)
	var ground_y := Cfg.height_at(lx, lz)

	if empty:
		if lod == LOD_FULL and shrub:
			defs.append({"c": Vector3(lx, ground_y, lz), "kind": "bush", "h": shrub_h})
		return

	var h := float(floors) * 3.0
	var total := h + 2.5                       # 2,5 m de embasamento enterrado
	var base_y := minf(Cfg.height_at(lx - w * 0.5, lz - d * 0.5),
			Cfg.height_at(lx + w * 0.5, lz + d * 0.5)) - 2.5
	_add_box(gb, Vector3(lx, base_y + total * 0.5, lz), Vector3(w, total, d), col)
	if lod == LOD_FULL:
		_add_box(gb, Vector3(lx, base_y + total + 1.3, lz), Vector3(w * 0.42, 2.6, d * 0.42), ROOF)
		if awning and h < 40.0:
			_add_box(gb, Vector3(lx, ground_y + 3.4, lz + d * 0.5 + 1.1), Vector3(w * 0.85, 0.25, 2.2), ROOF)
	colliders.append(Rect2(lx - w * 0.5, lz - d * 0.5, w, d))


static func _add_roads(gb: GBuf, ax: float, az: float) -> void:
	var h := ROAD * 0.5
	_add_flat(gb, ax, az - h, ax + BLOCK, az + h, ASPHALT)
	_add_flat(gb, ax - h, az, ax + h, az + BLOCK, ASPHALT)


## Superficie plana entre (x0, z0) e (x1, z1), acompanhando o terreno nos cantos.
static func _add_flat(gb: GBuf, x0: float, z0: float, x1: float, z1: float, col: Color,
		lift: float = FLAT_LIFT) -> void:
	var a := Vector3(x0, Cfg.height_at(x0, z0) + lift, z0)
	var b := Vector3(x1, Cfg.height_at(x1, z0) + lift, z0)
	var c := Vector3(x1, Cfg.height_at(x1, z1) + lift, z1)
	var d := Vector3(x0, Cfg.height_at(x0, z1) + lift, z1)
	gb.normal(Vector3.UP)
	_add_quad(gb, a, b, c, d, col)


# --- Geometria ---------------------------------------------------------------

## Quad (a, b, c, d) em sentido horario visto de fora; normal = gb.normal_vec.
static func _add_quad(gb: GBuf, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		gb.v.append(v)
		gb.n.append(gb.normal_vec)
		gb.c.append(col)


## Caixa alinhada aos eixos; center e o centro geometrico.
static func _add_box(gb: GBuf, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	for f in CUBE_FACES:
		var fc: Vector3 = f[0]
		var ya: Vector3 = f[1]
		var za: Vector3 = f[2]
		var c := center + Vector3(fc.x * h.x, fc.y * h.y, fc.z * h.z)
		var yv := Vector3(ya.x * h.x, ya.y * h.y, ya.z * h.z)
		var zv := Vector3(za.x * h.x, za.y * h.y, za.z * h.z)
		gb.normal(fc)
		_add_quad(gb, c - yv - zv, c + yv - zv, c + yv + zv, c - yv + zv, col)


# --- Utilitarios -------------------------------------------------------------

## Mistura deterministica de tres inteiros em 31 bits (sempre positivo).
static func mix3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


## Cubo unitario (centrado, lado 1) para o MultiMesh dos props.
static func unit_cube_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in CUBE_FACES:
		var fc: Vector3 = f[0]
		var ya: Vector3 = f[1]
		var za: Vector3 = f[2]
		var c: Vector3 = fc * 0.5
		var yv: Vector3 = ya * 0.5
		var zv: Vector3 = za * 0.5
		var quad: Array[Vector3] = [c - yv - zv, c + yv - zv, c + yv + zv, c - yv + zv]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(fc)
			st.set_color(Color.WHITE)
			st.add_vertex(quad[idx])
	return st.commit()


# --- Buffers e PRNG ----------------------------------------------------------

## Acumulador de malha (mais rapido que SurfaceTool para milhares de quads).
class GBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var normal_vec := Vector3.UP

	func normal(v3: Vector3) -> void:
		normal_vec = v3


## PRNG xorshift32: deterministico e independente da versao do motor.
class Rng:
	var _s: int

	func _init(seed_value: int) -> void:
		_s = seed_value & 0xFFFFFFFF
		if _s == 0:
			_s = 0x9E3779B9

	func next() -> int:
		var x := _s
		x ^= (x << 13) & 0xFFFFFFFF
		x ^= x >> 17
		x ^= (x << 5) & 0xFFFFFFFF
		_s = x & 0xFFFFFFFF
		return _s

	func unit() -> float:
		return float(next()) / 4294967296.0

	func range_f(a: float, b: float) -> float:
		return a + unit() * (b - a)

	func range_i(a: int, b: int) -> int:
		return a + int(unit() * float(b - a + 1))

	func chance(p: float) -> bool:
		return unit() < p
