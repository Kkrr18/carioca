extends RefCounted
## CityGen: geracao PROCEDURAL e DETERMINISTICA de um setor do mundo.
##
## Sem estado global e sem aleatoriedade do motor: o mesmo (seed, setor, LOD)
## gera sempre os mesmos vertices. Roda em WorkerThreadPool (so arrays, sem nos).
##
## Retorno de generate(): 17 arrays, nesta ordem:
##   0..2  vertices/normais/cores da cidade (predios, props, pintura) — cor por vertice
##   3     colisores (Array de Rect2)
##   4     defs (Array de Dictionary com props)
##   5..7  fachadas de vidro (vertices/normais/cores) — surface com emissao
##   8..10 asfalto texturado (vertices/normais/UV)
##   11..13 calcada texturada (vertices/normais/UV)
##   14..16 areia texturada (vertices/normais/UV)
## As tres ultimas superficies existem porque textura e material sao por
## superficie: a rua, a calcada e a areia tem textura CC0 propria (Fase 4,
## premissa de realismo), o resto da cidade continua com cor por vertice.
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
const PLAZA_LIFT := Cfg.CURB_HEIGHT + 0.02
const MARK_LIFT := 0.06              # pintura da rua: acima do asfalto
const MARK_WHITE := Color(0.88, 0.88, 0.85)
const MARK_YELLOW := Color(0.86, 0.72, 0.22)
# Calcada levantada no meio-fio: a superficie fica CURB_LIFT acima do terreno e
# uma face vertical fecha a diferenca no encontro com a rua.
const CURB_LIFT := Cfg.CURB_HEIGHT
const CURB_COL := Color(0.73, 0.72, 0.69)

# Repeticao das texturas (1 unidade de UV = `tile` metros). O asfalto do Poly
# Haven cobre 3 m; a areia aerea cobre 30 m, entao 10 m deixa o grao visivel
# sem repetir demais na tela.
const ROAD_TILE := 3.0
const WALK_TILE := 3.0
const SAND_TILE := 10.0
const CALCADAO_TILE := 6.0   # onda da calcada de Copacabana: 1 padrao a cada 6 m
# Fachada: uma janela por andar. O pe-direito e 3 m, entao a textura de fachada
# repete a cada 3 m na vertical E na horizontal (uma janela por modulo).
const FACADE_TILE := 3.0
## Canto liso da textura de fachada: usado nas faces de topo e base, para o
## telhado nao ganhar janela.
const FLAT_UV := Vector2(0.02, 0.02)

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
const GLASS := Color(0.55, 0.68, 0.78)   # fachada de janelas (surface proprio)

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
	var win := GBuf.new()
	# Superficies texturadas (asfalto, calcada, areia).
	var road := TBuf.new(ROAD_TILE)
	var walk := TBuf.new(WALK_TILE)
	var sand := TBuf.new(SAND_TILE)
	var calcadao := TBuf.new(CALCADAO_TILE)
	var bld := TBuf.new(FACADE_TILE)
	var defs: Array = []
	var colliders: Array = []
	var ox := float(sx) * Cfg.SECTOR_SIZE
	var oz := float(sz) * Cfg.SECTOR_SIZE
	var s := Cfg.SECTOR_SIZE

	_ground(gb, sand, ox, oz)
	if sz == 0:
		_beach(walk, road, calcadao, defs, ox, lod)

	var i0 := int(ceil(maxf(ox, 0.0) / BLOCK))
	var i1 := int(ceil((ox + s) / BLOCK)) - 1
	var j0 := int(ceil((oz - Cfg.CITY_MIN_Z) / BLOCK))
	var j1 := int(ceil((oz + s - Cfg.CITY_MIN_Z) / BLOCK)) - 1
	for j in range(j0, j1 + 1):
		var z_axis := Cfg.CITY_MIN_Z + float(j) * BLOCK
		if z_axis < Cfg.CITY_MIN_Z or z_axis > Cfg.CITY_MAX_Z:
			continue
		for i in range(i0, i1 + 1):
			_block(gb, win, walk, road, calcadao, bld, defs, colliders, float(i) * BLOCK, z_axis,
					world_seed, i, j, lod)

	return [gb.v, gb.n, gb.c, colliders, defs, win.v, win.n, win.c,
			road.v, road.n, road.uv, walk.v, walk.n, walk.uv, sand.v, sand.n, sand.uv,
			calcadao.v, calcadao.n, calcadao.uv,
			bld.v, bld.n, bld.uv, bld.c]


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


static func _ground(gb: GBuf, sand: TBuf, ox: float, oz: float) -> void:
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
			var zmid := z0 + Cfg.CELL_SIZE * 0.5
			if zmid >= 0.0 and zmid < Cfg.BEACH_EDGE_Z:
				# Praia: textura de areia (e o chao que o jogador ve de perto).
				sand.quad(a, b, c, d, Vector3.UP)
			else:
				# Mar, cidade e morros: cor por vertice (SEABED, GRASS, FOREST).
				_add_quad(gb, a, b, c, d, ground_color(x0 + 16.0, z0 + 16.0))


# --- Orla --------------------------------------------------------------------

static func _beach(walk: TBuf, road: TBuf, calcadao: TBuf, defs: Array, ox: float, lod: int) -> void:
	# Calcadao da Av. Atlantica: faixa clara entre z = 112 e z = 126.
	var z0 := 112.0
	var z1 := 126.0
	var end := ox + Cfg.SECTOR_SIZE
	# Piso de asfalto da avenida, entre a areia e o calçadão.
	_add_flat_tx(road, ox, 97.0, end, 110.0)
	var x := ox
	while x < end - 0.01:
		var x1 := minf(x + 64.0, end)
		var a := Vector3(x, Cfg.height_at(x, z0) + FLAT_LIFT, z0)
		var b := Vector3(x1, Cfg.height_at(x1, z0) + FLAT_LIFT, z0)
		var c := Vector3(x1, Cfg.height_at(x1, z1) + FLAT_LIFT, z1)
		var d := Vector3(x, Cfg.height_at(x, z1) + FLAT_LIFT, z1)
		# O calcadao tem material proprio: o padrao de ondas da calcada
		# portuguesa, gerado em codigo (nao existe CC0 com URL direta).
		calcadao.quad(a, b, c, d, Vector3.UP)
		x = x1
	if lod == LOD_FAR:
		return
	var rng := Rng.new(mix3(101, int(ox), 0))
	var px := ox + 8.0
	while px < end - 4.0:
		defs.append({"c": Vector3(px, Cfg.height_at(px, 88.0), 88.0), "kind": "palm", "h": 7.0})
		px += 32.0
	# Mobiliario do calçadão: bancos e lixeiras a cada 32 m.
	var bx := ox + 16.0
	while bx < end - 4.0:
		defs.append({"c": Vector3(bx, Cfg.height_at(bx, 118.0), 118.0), "kind": "banco", "h": 0.6})
		defs.append({"c": Vector3(bx + 8.0, Cfg.height_at(bx + 8.0, 118.0), 118.0), "kind": "lixeira", "h": 1.0})
		bx += 32.0
	# Carros estacionados na avenida, com cor variada e deterministicos.
	var cx := ox + 9.0
	while cx < end - 4.0:
		if rng.chance(0.65):
			var car_z := rng.range_f(100.5, 104.5)
			var hue := rng.unit()
			var car_y := Cfg.height_at(cx, car_z)
			defs.append({"c": Vector3(cx, car_y, car_z), "kind": "carro", "hue": hue})
			defs.append({"c": Vector3(cx, car_y, car_z), "kind": "carro_top", "hue": hue})
		cx += 17.0
	for k in 3:
		if not rng.chance(0.75):
			continue
		var kx := ox + rng.range_f(20.0, Cfg.SECTOR_SIZE - 20.0)
		var kz := rng.range_f(28.0, 84.0)
		var kind := "kiosk" if rng.chance(0.5) else "umbrella"
		defs.append({"c": Vector3(kx, Cfg.height_at(kx, kz), kz), "kind": kind, "hue": rng.unit()})


# --- Quadras -----------------------------------------------------------------

static func _block(gb: GBuf, win: GBuf, walk: TBuf, road: TBuf, calcadao: TBuf, bld: TBuf,
		defs: Array, colliders: Array,
		ax: float, az: float, world_seed: int, bi: int, bj: int, lod: int) -> void:
	# Semente propria da quadra: o conteudo nao depende do setor que a desenha.
	var rng := Rng.new(mix3(world_seed, bi * 4096 + 1, bj * 4096 + 7))
	var edge := ROAD * 0.5
	# Ruas: a quadra desenha a meia-rua de sua borda oeste e sul.
	_add_roads(gb, road, ax, az, lod)
	# Calcada: miolo da quadra, LEVANTADA no meio-fio que a separa da rua.
	# O chao de quem anda tambem sobe (Cfg.surface_at), senao o personagem
	# afundaria 15 cm ao subir na calcada.
	_add_flat_tx(walk, ax + edge, az + edge, ax + BLOCK - edge, az + BLOCK - edge, CURB_LIFT)
	if lod == LOD_FULL:
		_add_curbs(gb, ax, az, edge)

	# Postes com luminaria nos cantos da calçada (em qualquer tipo de quadra).
	if lod == LOD_FULL:
		for p2 in [
			Vector2(ax + 6.0, az + 6.0),
			Vector2(ax + BLOCK - 6.0, az + 6.0),
			Vector2(ax + 6.0, az + BLOCK - 6.0),
			Vector2(ax + BLOCK - 6.0, az + BLOCK - 6.0),
		]:
			# O poste fica EM PE na calcada, nao enterrado nela.
			var py := Cfg.surface_at(p2.x, p2.y)
			defs.append({"c": Vector3(p2.x, py, p2.y), "kind": "poste", "h": 5.5})
			defs.append({"c": Vector3(p2.x, py, p2.y), "kind": "lampadaria", "h": 5.5})

	if rng.chance(0.07):
		_add_flat(gb, ax + 14.0, az + 14.0, ax + BLOCK - 14.0, az + BLOCK - 14.0, PLAZA, PLAZA_LIFT)
		if lod == LOD_FULL:
			var tx := ax + BLOCK * 0.42
			var tz := az + BLOCK * 0.55
			defs.append({"c": Vector3(tx, Cfg.surface_at(tx, tz), tz), "kind": "tree", "h": rng.range_f(7.0, 11.0)})
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
			_lot(gb, win, bld, defs, colliders, rng, lx, lz, lot_w, lot_d, lod)


## Um lote. Sorteia SEMPRE todos os valores (mesmo em LOD far), para o layout
## nao mudar entre os dois LODs.
static func _lot(gb: GBuf, win: GBuf, bld: TBuf, defs: Array, colliders: Array, rng: Rng,
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
	# Nivel do passeio (calcada levantada): o toldo, o arbusto e a arvore ficam
	# nesta altura, nao enterrados no meio-fio.
	var ground_y := Cfg.surface_at(lx, lz)

	if empty:
		if lod == LOD_FULL and shrub:
			defs.append({"c": Vector3(lx, ground_y, lz), "kind": "bush", "h": shrub_h})
		return

	var h := float(floors) * 3.0
	var total := h + 2.5                       # 2,5 m de embasamento enterrado
	var base_y := minf(Cfg.height_at(lx - w * 0.5, lz - d * 0.5),
			Cfg.height_at(lx + w * 0.5, lz + d * 0.5)) - 2.5
	# Corpo do predio com TEXTURA de fachada (parede + janela), na surface
	# propria: a cor da paleta tinge a textura, entao cada predio mantem a sua
	# cor e ganha janelas. O brilho das janelas a noite vem do mapa de emissao.
	_add_box_tx(bld, Vector3(lx, base_y + total * 0.5, lz), Vector3(w, total, d), col)
	if lod == LOD_FULL:
		_add_box(gb, Vector3(lx, base_y + total + 1.3, lz), Vector3(w * 0.42, 2.6, d * 0.42), ROOF)
		if awning and h < 40.0:
			_add_box(gb, Vector3(lx, ground_y + 3.4, lz + d * 0.5 + 1.1), Vector3(w * 0.85, 0.25, 2.2), ROOF)
	colliders.append(Rect2(lx - w * 0.5, lz - d * 0.5, w, d))


## Ruas da quadra (borda oeste e sul) com a sinalizacao pintada.
##
## A rua vertical sobe 5 mm em relacao a horizontal: as duas se cruzam na
## esquina e, no MESMO nivel, o asfalto piscava (z-fighting) em todo cruzamento.
## A pintura (eixo amarelo, faixa de pedestres, linha de retencao) e so do LOD
## full: e detalhe de perto e custa vertices que o anel distante nao precisa.
static func _add_roads(gb: GBuf, road: TBuf, ax: float, az: float, lod: int) -> void:
	var h := ROAD * 0.5
	_add_flat_tx(road, ax, az - h, ax + BLOCK, az + h)
	_add_flat_tx(road, ax - h, az, ax + h, az + BLOCK, FLAT_LIFT + 0.005)
	if lod != LOD_FULL:
		return
	# Eixo amarelo tracejado nas duas ruas (4 m de tinta, 8 m de vazio).
	_add_dashes_x(gb, ax + h + 1.5, ax + BLOCK - 1.5, az, 0.16, 4.0, 8.0, MARK_YELLOW)
	_add_dashes_z(gb, az + h + 1.5, az + BLOCK - 1.5, ax, 0.16, 4.0, 8.0, MARK_YELLOW)
	# Faixa de pedestres do lado de dentro da esquina e linha de retencao antes
	# dela, na faixa da direita de cada sentido.
	_add_crosswalk_x(gb, ax - h - 3.2, ax - h - 0.4, az - h + 0.4, az + h - 0.4, MARK_WHITE)
	_add_crosswalk_z(gb, az - h - 3.2, az - h - 0.4, ax - h + 0.4, ax + h - 0.4, MARK_WHITE)
	_add_flat(gb, ax - h - 4.2, az, ax - h - 3.8, az + h - 0.4, MARK_WHITE, MARK_LIFT)
	_add_flat(gb, ax, az - h - 4.2, ax + h - 0.4, az - h - 3.8, MARK_WHITE, MARK_LIFT)


## Tracejado ao longo de X (eixo de uma rua leste-oeste).
static func _add_dashes_x(gb: GBuf, x0: float, x1: float, z: float, w: float,
		dash: float, gap: float, col: Color) -> void:
	var x := x0
	while x + dash <= x1:
		_add_flat(gb, x, z - w * 0.5, x + dash, z + w * 0.5, col, MARK_LIFT)
		x += dash + gap


## Tracejado ao longo de Z (eixo de uma rua norte-sul).
static func _add_dashes_z(gb: GBuf, z0: float, z1: float, x: float, w: float,
		dash: float, gap: float, col: Color) -> void:
	var z := z0
	while z + dash <= z1:
		_add_flat(gb, x - w * 0.5, z, x + w * 0.5, z + dash, col, MARK_LIFT)
		z += dash + gap


## Faixa de pedestres atravessando a rua que corre em X (listras ao longo de X).
static func _add_crosswalk_x(gb: GBuf, x0: float, x1: float, z0: float, z1: float, col: Color) -> void:
	var z := z0
	while z + 0.6 <= z1:
		_add_flat(gb, x0, z, x1, z + 0.6, col, MARK_LIFT)
		z += 1.5


## Faixa de pedestres atravessando a rua que corre em Z (listras ao longo de Z).
static func _add_crosswalk_z(gb: GBuf, z0: float, z1: float, x0: float, x1: float, col: Color) -> void:
	var x := x0
	while x + 0.6 <= x1:
		_add_flat(gb, x, z0, x + 0.6, z1, col, MARK_LIFT)
		x += 1.5


## As quatro faces verticais do meio-fio em volta da calçada da quadra.
static func _add_curbs(gb: GBuf, ax: float, az: float, edge: float) -> void:
	var x0 := ax + edge
	var x1 := ax + BLOCK - edge
	var z0 := az + edge
	var z1 := az + BLOCK - edge
	_add_curb_x(gb, x0, z0, z1, -1.0)
	_add_curb_x(gb, x1, z0, z1, 1.0)
	_add_curb_z(gb, z0, x0, x1, -1.0)
	_add_curb_z(gb, z1, x0, x1, 1.0)


## Face do meio-fio correndo em Z (normal em X, `face` = +1 ou -1). O sentido
## dos vertices segue a regra do arquivo: horario visto de fora.
static func _add_curb_x(gb: GBuf, x: float, z0: float, z1: float, face: float) -> void:
	var hb0 := Cfg.height_at(x, z0) + FLAT_LIFT
	var hb1 := Cfg.height_at(x, z1) + FLAT_LIFT
	var b0 := Vector3(x, hb0, z0)
	var b1 := Vector3(x, hb1, z1)
	var t0 := Vector3(x, hb0 + CURB_LIFT - FLAT_LIFT, z0)
	var t1 := Vector3(x, hb1 + CURB_LIFT - FLAT_LIFT, z1)
	gb.normal(Vector3(face, 0.0, 0.0))
	if face > 0.0:
		_add_quad(gb, b0, b1, t1, t0, CURB_COL)
	else:
		_add_quad(gb, b1, b0, t0, t1, CURB_COL)


## Face do meio-fio correndo em X (normal em Z, `face` = +1 ou -1).
static func _add_curb_z(gb: GBuf, z: float, x0: float, x1: float, face: float) -> void:
	var hb0 := Cfg.height_at(x0, z) + FLAT_LIFT
	var hb1 := Cfg.height_at(x1, z) + FLAT_LIFT
	var b0 := Vector3(x0, hb0, z)
	var b1 := Vector3(x1, hb1, z)
	var t0 := Vector3(x0, hb0 + CURB_LIFT - FLAT_LIFT, z)
	var t1 := Vector3(x1, hb1 + CURB_LIFT - FLAT_LIFT, z)
	gb.normal(Vector3(0.0, 0.0, face))
	if face > 0.0:
		_add_quad(gb, b1, b0, t0, t1, CURB_COL)
	else:
		_add_quad(gb, b0, b1, t1, t0, CURB_COL)


## Superficie plana entre (x0, z0) e (x1, z1), acompanhando o terreno nos cantos.
static func _add_flat(gb: GBuf, x0: float, z0: float, x1: float, z1: float, col: Color,
		lift: float = FLAT_LIFT) -> void:
	var a := Vector3(x0, Cfg.height_at(x0, z0) + lift, z0)
	var b := Vector3(x1, Cfg.height_at(x1, z0) + lift, z0)
	var c := Vector3(x1, Cfg.height_at(x1, z1) + lift, z1)
	var d := Vector3(x0, Cfg.height_at(x0, z1) + lift, z1)
	gb.normal(Vector3.UP)
	_add_quad(gb, a, b, c, d, col)


## Superficie plana TEXTURADA: mesma geometria de _add_flat, mas com UV em
## escala de mundo (a textura repete a cada `tb.tile` metros).
static func _add_flat_tx(tb: TBuf, x0: float, z0: float, x1: float, z1: float,
		lift: float = FLAT_LIFT) -> void:
	var a := Vector3(x0, Cfg.height_at(x0, z0) + lift, z0)
	var b := Vector3(x1, Cfg.height_at(x1, z0) + lift, z0)
	var c := Vector3(x1, Cfg.height_at(x1, z1) + lift, z1)
	var d := Vector3(x0, Cfg.height_at(x0, z1) + lift, z1)
	tb.quad(a, b, c, d, Vector3.UP)


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


## Caixa com UV de FACHADA: cada face repete a textura a cada `tb.tile` metros,
## isto e, uma janela por andar de 3 m. Topo e base usam o canto liso, para o
## telhado nao ganhar janela. A cor vai por vertice e tinge a textura.
static func _add_box_tx(tb: TBuf, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	for f in CUBE_FACES:
		var fc: Vector3 = f[0]
		var ya: Vector3 = f[1]
		var za: Vector3 = f[2]
		var c := center + Vector3(fc.x * h.x, fc.y * h.y, fc.z * h.z)
		var yv := Vector3(ya.x * h.x, ya.y * h.y, ya.z * h.z)
		var zv := Vector3(za.x * h.x, za.y * h.y, za.z * h.z)
		var p0 := c - yv - zv
		var p1 := c + yv - zv
		var p2 := c + yv + zv
		var p3 := c - yv + zv
		if absf(fc.y) > 0.5:
			tb.quad_uv(p0, p1, p2, p3, fc, FLAT_UV, FLAT_UV, FLAT_UV, FLAT_UV, color)
		else:
			var uu := (yv * 2.0).length() / tb.tile
			var vv := (zv * 2.0).length() / tb.tile
			tb.quad_uv(p0, p1, p2, p3, fc,
					Vector2(0.0, 0.0), Vector2(uu, 0.0), Vector2(uu, vv), Vector2(0.0, vv), color)


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


## Buffer de superficie TEXTURADA: vertices, normais e UV em escala de mundo
## (1 unidade de UV = `tile` metros), para a textura repetir sem esticar.
class TBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	## Cor por vertice: so a fachada usa (a textura dela e cinza, tingida pela
	## paleta). Chao e asfalto ficam sem cor propria e usam a cor da textura.
	var col := PackedColorArray()
	var tile := 3.0

	func _init(tile_m: float) -> void:
		tile = maxf(0.5, tile_m)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
		for p in [a, b, c, a, c, d]:
			v.append(p)
			n.append(normal)
			uv.append(Vector2(p.x, p.z) / tile)

	## Quad com UV explicito (usado pelas faces da fachada).
	func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, color: Color) -> void:
		var pts := [a, b, c, a, c, d]
		var uvs := [ua, ub, uc, ua, uc, ud]
		for i in 6:
			v.append(pts[i])
			n.append(normal)
			uv.append(uvs[i])
			col.append(color)


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
