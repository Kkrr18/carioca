extends RefCounted
## CityGen: geracao PROCEDURAL e DETERMINISTICA de um setor do mundo.
##
## Sem estado global e sem aleatoriedade do motor: o mesmo (seed, setor, LOD)
## gera sempre os mesmos vertices. Roda em WorkerThreadPool (so arrays, sem nos).
##
## Retorno de generate(): 34 arrays, nesta ordem (os indices sao contrato com o
## SectorStreamer e com tests/runner.gd — acrescente SEMPRE no fim):
##   0..2  vertices/normais/cores da cidade (chao, pintura, meio-fio, toldos)
##   3     colisores (Array de Rect2)
##   4     defs (Array de Dictionary com props)
##   5..7  fachadas de vidro (sempre vazias desde a B-48)
##   8..10 asfalto texturado (vertices/normais/UV)
##   11..13 calcada texturada (vertices/normais/UV)
##   14..16 areia texturada (vertices/normais/UV)
##   17..19 calcadao texturado (vertices/normais/UV)
##   20..23 fachada dos predios (vertices/normais/UV/cores) — surface com emissao
##   24    lojas do setor (balconista, entrada e nome)
##   25..27 props com geometria de verdade (vertices/normais/cores) — B-80
##   28..30 props que acendem a noite (luminarias de rua)
##   31..33 areia molhada da faixa do mar (vertices/normais/UV)
## As superficies texturadas existem porque textura e material sao por
## superficie: rua, calcada, areia e calcadao tem textura CC0 propria (Fase 4,
## premissa de realismo), o resto da cidade continua com cor por vertice.
## Convencao de frente: triangulo horario visto de fora (Godot). A normal de
## frente e -(b-a)x(d-a), que coincide com a normal salva.

const Cfg = preload("res://scripts/core/cfg.gd")
const PropMesh = preload("res://scripts/world/prop_mesh.gd")

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
const MARK_LIFT := 0.10              # pintura da rua: 6 cm acima do asfalto
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
# Fachada: a textura fotografada (Keith333, CC-BY 3.0) cobre 22,9 m de largura
# com 8 janelas e 12 m de altura com 4 andares. O UV usa essas duas medidas, e
# nao um "tile" unico, senao a janela estica.
const FACADE_W := 22.9
const FACADE_H := 12.0
## Canto liso da textura de fachada: usado nas faces de topo e base, para o
## telhado nao ganhar janela.
const FLAT_UV := Vector2(0.02, 0.02)

## Platibanda (B-80): a faixa de concreto que coroa a laje. Sem ela o predio
## termina num corte seco de papelao e o ceu parece entrar por cima do bloco.
const PARAPET := 0.45
const PARAPET_W := 0.22
## Areia que o mar lava (B-80): vai para um material proprio, mais escuro e com
## brilho de areia molhada. Na praia idealizada a altura zero cai em z = 32,
## entao a faixa molhada e a celula de terreno de 32 a 64 m.
const WET_Z0 := 32.0
const WET_Z1 := 64.0

const SAND := Color(0.86, 0.79, 0.64)
const SAND_WET := Color(0.70, 0.65, 0.55)
const SEABED := Color(0.20, 0.31, 0.30)
const ASPHALT := Color(0.21, 0.22, 0.24)
const WALK_COL := Color(0.63, 0.62, 0.59)
const PLAZA := Color(0.42, 0.52, 0.36)
## Telhado/laje: e a cor por vertice do teto do prisma, que multiplica o canto
## liso da textura de fachada (FLAT_UV). Cinza de laje, nao preto.
const ROOF := Color(0.50, 0.49, 0.45)
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

# --- Loja (B-65) -------------------------------------------------------------
## Predio baixo ganha uma LOJA no terreo, aberta para a calcada: o vao entra
## SHOP_DEPTH para dentro do predio e o jogador entra andando (os colisores do
## vao ficam abertos). Predios altos nao tem loja: sao torres com garagem.
const SHOP_CHANCE := 0.22
const SHOP_H := 3.0              # pe direito da loja (m)
const SHOP_BAY_MAX := 5.5        # largura maxima da frente
const SHOP_DEPTH_MAX := 4.5      # profundidade maxima do vao
const SHOP_FLOOR := Color(0.42, 0.35, 0.28)     # piso (ceramica/madeira)
const SHOP_WALL := Color(0.88, 0.86, 0.80)      # parede interna clara
const SHOP_COUNTER := Color(0.52, 0.40, 0.28)   # balcao e prateleira
## Tipos de loja: [nome, cor da placa]. A cor e o que se ve de longe na rua.
const SHOP_TYPES := [
	["Padaria", Color(0.92, 0.74, 0.24)],
	["Farmacia", Color(0.18, 0.56, 0.34)],
	["Bar", Color(0.76, 0.18, 0.16)],
	["Loja", Color(0.24, 0.44, 0.72)],
	["Mercado", Color(0.96, 0.54, 0.14)],
]
## Lado (oeste/leste/sul/norte) -> aresta da planta que fica naquele lado.
## A planta de _plan_rect vai em anti-horario: 0 = sul, 1 = leste, 2 = norte,
## 3 = oeste.
const SHOP_EDGE := [3, 1, 0, 2]

## Lonas de toldo: o comercio de rua tem toldo COLORIDO. Antes o toldo saia na
## cor de telhado (cinza) e parecia uma laje solta na fachada.
const AWNINGS := [
	Color(0.72, 0.16, 0.14), Color(0.16, 0.42, 0.60), Color(0.90, 0.86, 0.74),
	Color(0.20, 0.46, 0.30), Color(0.86, 0.62, 0.16),
]

## Embasamento (B-81): faixa de pedra no pe do predio, do nivel da rua para
## cima. E o que assenta o bloco no chao — sem ela o predio nasce direto do
## asfalto, como um cubo apoiado.
const PLINTH := Color(0.42, 0.41, 0.38)
const PLINTH_H := 1.05

## Varandas (B-81): laje + guarda-corpo na fachada que olha para a rua. E o
## detalhe que faz o predio de Ipanema parecer de Ipanema: sem ele, so sobra
## um retangulo de janelas.
const BALCONY_SLAB := Color(0.84, 0.83, 0.79)
const BALCONY_RAIL := Color(0.26, 0.28, 0.30)
const BALCONY_CHANCE := 0.55
const BALCONY_REACH := 1.05

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
	var wet := TBuf.new(SAND_TILE)
	var calcadao := TBuf.new(CALCADAO_TILE)
	var bld := TBuf.new(FACADE_W, FACADE_H)
	# Props com geometria de verdade (B-80): o solido e o que acende a noite.
	var props := PropMesh.MBuf.new()
	var glow := PropMesh.MBuf.new()
	var prop_cache: Dictionary = {}
	var defs: Array = []
	var colliders: Array = []
	var shops: Array = []     # lojas do setor (balconista + nome na tela), B-66
	var ox := float(sx) * Cfg.SECTOR_SIZE
	var oz := float(sz) * Cfg.SECTOR_SIZE
	var s := Cfg.SECTOR_SIZE

	_ground(gb, sand, wet, ox, oz)
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
			_block(gb, win, walk, road, calcadao, bld, defs, colliders, shops, float(i) * BLOCK,
					z_axis, world_seed, i, j, lod)

	# Props: os defs (que continuam sendo os DADOS do que existe no setor) viram
	# geometria aqui, ainda na worker thread — a malha de cada tipo e construida
	# uma vez e instanciada por transformacao (ver PropMesh).
	_props_geometry(props, glow, prop_cache, defs)

	return [gb.v, gb.n, gb.c, colliders, defs, win.v, win.n, win.c,
			road.v, road.n, road.uv, walk.v, walk.n, walk.uv, sand.v, sand.n, sand.uv,
			calcadao.v, calcadao.n, calcadao.uv,
			bld.v, bld.n, bld.uv, bld.col, shops,
			props.v, props.n, props.c, glow.v, glow.n, glow.c,
			wet.v, wet.n, wet.uv]


# --- Props (defs -> geometria) -----------------------------------------------

## Transforma os defs do setor na geometria dos props. Puro e deterministico:
## a mesma lista de defs gera sempre os mesmos vertices.
##
## A malha de cada tipo e construida UMA vez por (tipo, altura, tom) e cacheada
## no proprio setor — 256 postes iguais custam uma construcao e 256 copias com
## transformacao, que e o que faz isto caber na thread.
static func _props_geometry(props, glow, cache: Dictionary, defs: Array) -> void:
	for d in defs:
		var dd: Dictionary = d
		var kind := String(dd.get("kind", "tree"))
		var h := float(dd.get("h", 6.0))
		var hue := float(dd.get("hue", 0.5))
		var key := "%s|%.1f|%d" % [kind, h, int(hue * 4.0)]
		var tpl: Dictionary = cache.get(key, {})
		if tpl.is_empty():
			tpl = PropMesh.build(kind, h, hue)
			if tpl.is_empty():
				# Tipo sem malha (ex.: "carro_top", que virou parte do carro):
				# guarda o vazio para nao tentar construir de novo.
				cache[key] = {"solid": null, "glow": null}
				continue
			cache[key] = tpl
		var solid = tpl.get("solid")
		if solid == null:
			continue
		var c: Vector3 = dd["c"]
		var rot := float(dd.get("rot", 0.0))
		var xf := Transform3D(Basis(Vector3.UP, rot), c)
		props.add(solid, xf)
		var lit = tpl.get("glow")
		if lit != null and not lit.is_empty():
			glow.add(lit, xf)


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


static func _ground(gb: GBuf, sand: TBuf, wet: TBuf, ox: float, oz: float) -> void:
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
				# A celula que o mar lava vai para a areia MOLHADA, com material
				# proprio (mais escura e com brilho): e a faixa que separa a
				# praia do mar na tela, e sem ela tudo virava um areial so.
				if z0 >= WET_Z0 - 0.01 and z1 <= WET_Z1 + 0.01:
					wet.quad(a, b, c, d, Vector3.UP)
				else:
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
		var py := Cfg.height_at(px, 88.0)
		# Palmeira = TRONCO + COPA, duas instancias do mesmo tipo (B-52), e agora
		# com malha de verdade (B-80/B-81): tronco que afina e inclina, nove folhas
		# em tres trechos e cacho de cocos. O tronco e a copa se encontram porque
		# PropMesh.palm_top() e funcao SO da altura — por isso o def da copa nao
		# tem `rot`, e as duas instancias usam a MESMA altura `ph`.
		var phue := rng.unit()
		var ph := rng.range_f(6.4, 9.4)
		defs.append({"c": Vector3(px, py, 88.0), "kind": "palm", "h": ph, "hue": phue})
		defs.append({"c": Vector3(px, py, 88.0), "kind": "palm_crown", "h": ph, "hue": phue})
		px += 24.0
	# Mobiliario do calçadão: bancos e lixeiras a cada 32 m.
	var bx := ox + 16.0
	while bx < end - 4.0:
		defs.append({"c": Vector3(bx, Cfg.height_at(bx, 118.0), 118.0), "kind": "banco", "h": 0.6})
		defs.append({"c": Vector3(bx + 8.0, Cfg.height_at(bx + 8.0, 118.0), 118.0), "kind": "lixeira", "h": 1.0})
		bx += 32.0
	# Carros estacionados na avenida, com cor variada e deterministicos. O carro
	# agora e UMA malha (carroceria, capo, cabine, vidros, farois e rodas): ver
	# PropMesh._carro.
	var cx := ox + 9.0
	while cx < end - 4.0:
		if rng.chance(0.55):
			var car_z := rng.range_f(100.5, 104.5)
			var hue := rng.unit()
			var car_y := Cfg.height_at(cx, car_z)
			defs.append({"c": Vector3(cx, car_y, car_z), "kind": "carro", "hue": hue})
		cx += 17.0
	for k in 3:
		if not rng.chance(0.75):
			continue
		var kx := ox + rng.range_f(20.0, Cfg.SECTOR_SIZE - 20.0)
		var kz := rng.range_f(28.0, 84.0)
		var kind := "kiosk" if rng.chance(0.5) else "umbrella"
		var k_y := Cfg.height_at(kx, kz)
		defs.append({"c": Vector3(kx, k_y, kz), "kind": kind, "hue": rng.unit(),
				"rot": rng.range_f(0.0, TAU)})
		if kind == "umbrella":
			# Cadeira de praia na sombra do guarda-sol (B-81): a praia cheia de
			# gente nao tem so guarda-sol, tem onde sentar.
			for j in 2:
				var ang := rng.range_f(0.0, TAU)
				var cx2 := kx + cos(ang) * rng.range_f(1.7, 2.7)
				var cz2 := kz + sin(ang) * rng.range_f(1.7, 2.7)
				defs.append({"c": Vector3(cx2, Cfg.height_at(cx2, cz2), cz2),
						"kind": "cadeira", "hue": rng.unit(),
						"rot": rng.range_f(0.0, TAU)})
	# Pedras da arrebentacao (B-81): onde o mar quebra, a areia nao termina numa
	# linha reta — ela quebra em pedra.
	var rx := ox + 6.0
	while rx < end - 4.0:
		if rng.chance(0.55):
			var rz := rng.range_f(24.0, 42.0)
			defs.append({"c": Vector3(rx, Cfg.height_at(rx, rz), rz), "kind": "pedra",
					"h": rng.range_f(0.8, 1.7), "hue": rng.unit(),
					"rot": rng.range_f(0.0, TAU)})
		rx += 26.0


# --- Quadras -----------------------------------------------------------------

static func _block(gb: GBuf, win: GBuf, walk: TBuf, road: TBuf, calcadao: TBuf, bld: TBuf,
		defs: Array, colliders: Array, shops: Array,
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

	# Arvores de calcada (B-80): uma no meio de cada calcada que a quadra
	# desenha (oeste e sul). Rua arborizada e o que faz Ipanema parecer Ipanema;
	# antes a rua era um corredor de concreto sem uma sombra de arvore.
	# O sorteio acontece nos DOIS LODs (o layout nao pode mudar de um para outro).
	var tree_h := [rng.range_f(6.0, 9.0), rng.range_f(6.0, 9.5)]
	var tree_hue := [rng.unit(), rng.unit()]

	# Mobiliario novo de calcada (B-81): canteiro, hidrante e placa de rua. Os
	# SORTEIOS acontecem nos dois LODs (senao o layout do LOD far mudaria de
	# valor e o predio pularia quando o setor troca de nivel); a geometria so
	# entra no LOD full.
	var planter_n := rng.range_i(1, 2)
	var planter_hue := rng.unit()
	var hydrant := rng.chance(0.30)
	var hydrant_hue := rng.unit()
	var sign_side := rng.chance(0.5)
	var sign_hue := rng.unit()

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
		var spots := [
			Vector2(ax + edge + 1.1, az + BLOCK * 0.5),
			Vector2(ax + BLOCK * 0.5, az + edge + 1.1),
		]
		for k in spots.size():
			var sp: Vector2 = spots[k]
			var ty := Cfg.surface_at(sp.x, sp.y)
			var th: float = tree_h[k]
			var thue: float = tree_hue[k]
			defs.append({"c": Vector3(sp.x, ty, sp.y), "kind": "tree", "h": th})
			defs.append({"c": Vector3(sp.x, ty, sp.y), "kind": "tree_crown", "h": th,
					"hue": thue})
		# Canteiros na calcada oeste, hidrante e a placa de nome de rua na
		# esquina (B-81). Sao os tres objetos que fazem uma rua parecer
		# habitada em vez de um corredor de asfalto.
		for k in planter_n:
			var pz := az + 14.0 + float(k) * 30.0
			defs.append({"c": Vector3(ax + 6.4, Cfg.surface_at(ax + 6.4, pz), pz),
					"kind": "planta", "h": 1.2, "hue": planter_hue + float(k) * 0.25})
		if hydrant:
			var hz := az + BLOCK * 0.62
			defs.append({"c": Vector3(ax + 5.7, Cfg.surface_at(ax + 5.7, hz), hz),
					"kind": "hidrante", "h": 1.0, "hue": hydrant_hue})
		if sign_side:
			var sx := ax + 5.7
			var sz := az + 11.0
			defs.append({"c": Vector3(sx, Cfg.surface_at(sx, sz), sz), "kind": "placa",
					"h": 3.0, "hue": sign_hue})

	if rng.chance(0.07):
		_add_flat(gb, ax + 14.0, az + 14.0, ax + BLOCK - 14.0, az + BLOCK - 14.0, PLAZA, PLAZA_LIFT)
		if lod == LOD_FULL:
			var tx := ax + BLOCK * 0.42
			var tz := az + BLOCK * 0.55
			var th := rng.range_f(7.0, 11.0)
			var ty := Cfg.surface_at(tx, tz)
			# Arvore = tronco + copa, duas instancias do mesmo MultiMesh (B-52).
			defs.append({"c": Vector3(tx, ty, tz), "kind": "tree", "h": th})
			defs.append({"c": Vector3(tx, ty, tz), "kind": "tree_crown", "h": th,
					"hue": rng.unit(), "rot": rng.range_f(0.0, PI)})
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
			_lot(gb, win, bld, defs, colliders, shops, rng, lx, lz, lot_w, lot_d, lod, ax, az)


## Um lote. Sorteia SEMPRE todos os valores (mesmo em LOD far), para o layout
## nao mudar entre os dois LODs.
##
## O volume do predio NAO e sempre a mesma caixa (B-50). Cada lote sorteia:
##   - planta com largura e profundidade INDEPENDENTES (de esbelta a larga),
##   - posicao dentro do lote (o predio nao encosta na divisa),
##   - e um de tres volumes: caixa reta, caixa com topo recuado (setback) ou
##     embasamento de dois/tres andares com torre recuada (as vezes chanfrada).
## O embasamento e a caixa reta ficam com a planta INTEIRA, entao o colisor
## retangular continua exato: todo recuo e chanfro acontece acima da rua.
static func _lot(gb: GBuf, win: GBuf, bld: TBuf, defs: Array, colliders: Array, shops: Array,
		rng: Rng, lx: float, lz: float, lot_w: float, lot_d: float, lod: int,
		ax: float, az: float) -> void:
	var empty := not rng.chance(0.92)
	var floors := rng.range_i(1, 7)
	if rng.chance(0.18):
		floors = rng.range_i(9, 20)
	# Planta: as duas medidas sao independentes. Antes eram "lote menos 1 a 3 m"
	# nas DUAS (~20 x 20 m em todo lote) — era essa uniformidade que fazia a
	# cidade parecer feita de cubos iguais.
	var fit_w := lot_w - 1.2
	var fit_d := lot_d - 1.2
	var w := fit_w * rng.range_f(0.50, 1.0)
	var d := fit_d * rng.range_f(0.50, 1.0)
	var off_x := rng.range_f(-1.0, 1.0) * (fit_w - w) * 0.5
	var off_z := rng.range_f(-1.0, 1.0) * (fit_d - d) * 0.5
	var col: Color = PALETTE[rng.range_i(0, PALETTE.size() - 1)]
	# Embasamento mais escuro (pedra/concreto): separa a loja do corpo do predio.
	var base_col := col.darkened(0.32)
	var awning := rng.chance(0.35)
	var awning_col: Color = AWNINGS[rng.range_i(0, AWNINGS.size() - 1)]
	var shrub := rng.chance(0.55)
	var shrub_h := rng.range_f(2.5, 4.0)
	# Volume: 0 = caixa, 1 = topo recuado, 2 = embasamento + torre recuada.
	var style := 0
	if floors >= 3:
		style = 1 if rng.chance(0.4) else 2
	var tower_f := rng.range_f(0.58, 0.80)
	var tower_f2 := rng.range_f(0.58, 0.80)
	var tower_sx := rng.range_f(-1.0, 1.0)
	var tower_sz := rng.range_f(-1.0, 1.0)
	var step_floors := float(rng.range_i(1, 2))
	var chamfered := rng.chance(0.45)
	var chamfer_corner := rng.range_i(0, 3)
	var chamfer_cut := rng.range_f(2.2, 3.8)
	# Detalhe de cobertura (casa de maquinas / caixa d'agua / antena).
	var roof_kind := rng.range_i(0, 2)
	var roof_hue := rng.unit()
	var roof_ox := rng.range_f(-1.0, 1.0)
	var roof_oz := rng.range_f(-1.0, 1.0)
	# Ar-condicionado de split na fachada (B-80): e o detalhe que mais faz uma
	# fachada carioca parecer carioca. Sorteado SEMPRE, usado so no LOD full.
	var ac_n := rng.range_i(0, 2)
	var ac_pick := rng.unit()
	var ac_off := rng.range_f(-0.6, 0.6)
	var ac_hue := rng.unit()
	# Varandas (B-81): sorteado SEMPRE (o layout nao pode mudar de LOD), usado
	# so no LOD full e so em predio residencial de quatro andares ou mais.
	var balcony := rng.chance(BALCONY_CHANCE)
	# Nivel do passeio (calcada levantada): o toldo, o arbusto e a arvore ficam
	# nesta altura, nao enterrados no meio-fio.
	var ground_y := Cfg.surface_at(lx, lz)
	# Loja (B-65): predio baixo, virado para a calcada, com vao aberto no terreo.
	# O sorteio e identico nos dois LODs (o layout nao muda), mas o vao so e
	# ABERTO no LOD full: de longe o predio fica fechado (economia de geometria).
	var side := street_side(lx, lz, ax, az)
	var shop := floors >= 2 and floors <= 3 and w >= 8.0 and d >= 8.0 and rng.chance(SHOP_CHANCE)
	var shop_kind := 0
	if shop:
		shop_kind = rng.range_i(0, SHOP_TYPES.size() - 1)
	var shop_open := shop and lod == LOD_FULL
	# Planta do vao: frente de ate SHOP_BAY_MAX e ate SHOP_DEPTH_MAX para dentro.
	var bw := minf(w * 0.62, SHOP_BAY_MAX)
	var bd := minf(d * 0.45, SHOP_DEPTH_MAX)
	# `SHOP_EDGE` e um Array sem tipo: sem o `: int` o GDScript nao consegue
	# inferir o tipo do ternario e o arquivo inteiro deixa de compilar (o CI
	# pegou isso antes do jogador).
	var skip_edge: int = SHOP_EDGE[side] if shop_open else -1
	var ground_top := 0.0
	var ground_col := col

	if empty:
		if lod == LOD_FULL and shrub:
			defs.append({"c": Vector3(lx, ground_y, lz), "kind": "bush", "h": shrub_h, "rot": 0.6})
		return

	var bx := lx + off_x
	var bz := lz + off_z
	var roof_y := ground_y + float(floors) * 3.0
	# Platibanda so no LOD full (e detalhe de perto): no anel distante o predio
	# continua sendo o prisma liso, que e o que se ve a 2 km.
	var par := PARAPET if lod == LOD_FULL else 0.0
	# Fundo enterrado: o predio atravessa o relevo (a cidade e suave aqui).
	var base_y := minf(Cfg.height_at(bx - w * 0.5, bz - d * 0.5),
			Cfg.height_at(bx + w * 0.5, bz + d * 0.5)) - 2.5
	# Planta retangular cheia: a do nivel da rua e a do colisor.
	var full := _plan_rect(bx, bz, w, d, -1, 0.0)
	var roof_cx := bx
	var roof_cz := bz
	var roof_w := w
	var roof_d := d

	if style == 2 and floors >= 4:
		# Embasamento de dois/tres andares (loja, garagem) com a planta inteira e
		# a torre recuada por cima: a silhueta deixa de ser um bloco so.
		var pod_top := ground_y + (6.3 if floors >= 8 else 4.2)
		_add_prism_tx(bld, full, base_y, pod_top, base_col, ROOF, skip_edge, par)
		ground_top = pod_top
		ground_col = base_col
		roof_w = maxf(6.5, w * tower_f)
		roof_d = maxf(6.5, d * tower_f2)
		roof_cx = bx + tower_sx * (w - roof_w) * 0.5
		roof_cz = bz + tower_sz * (d - roof_d) * 0.5
		var tplan := _plan_rect(roof_cx, roof_cz, roof_w, roof_d,
				chamfer_corner if chamfered else -1, chamfer_cut)
		_add_prism_tx(bld, tplan, pod_top, roof_y, col, ROOF, -1, par)
	elif style == 1 and floors >= 3:
		# Topo recuado (setback): o ultimo andar (ou dois) entra para dentro.
		var low_top := maxf(ground_y + 3.0, roof_y - step_floors * 3.0)
		_add_prism_tx(bld, full, base_y, low_top, col, ROOF, skip_edge, par)
		ground_top = low_top
		roof_w = maxf(6.0, w * tower_f)
		roof_d = maxf(6.0, d * tower_f2)
		roof_cx = bx + tower_sx * (w - roof_w) * 0.5
		roof_cz = bz + tower_sz * (d - roof_d) * 0.5
		_add_prism_tx(bld, _plan_rect(roof_cx, roof_cz, roof_w, roof_d, -1, 0.0), low_top, roof_y,
				col, ROOF, -1, par)
	else:
		_add_prism_tx(bld, full, base_y, roof_y, col, ROOF, skip_edge, par)
		ground_top = roof_y

	if shop_open:
		# A frente do predio, agora com o VAO da loja: os dois lados e a verga por
		# cima, com o modulo da fachada continuo (a janela nao escorrega).
		var fa: Vector2 = full[skip_edge]
		var fb: Vector2 = full[(skip_edge + 1) % 4]
		var seg := (fb - fa).length()
		var off := (seg - bw) * 0.5
		_wall_with_hole(bld, fa, fb, base_y, ground_top, off, bw, ground_y,
				ground_y + SHOP_H, ground_col)
		_add_shop(gb, bx, bz, w, d, side, bw, bd, ground_y, shop_kind)
		# Publica a loja: onde o balconista fica em pe, onde o jogador entra (e o
		# que o HUD mostra) e para onde o balconista olha.
		shops.append(_shop_spot(bx, bz, w, d, side, bw, bd, ground_y, shop_kind))
	elif lod == LOD_FULL and floors >= 3:
		# Porta de entrada (B-80): sem loja, todo predio era um bloco sem porta.
		_add_entrance(gb, bx, bz, w, d, side, ground_y)

	if lod == LOD_FULL:
		# Cobertura: casa de maquinas, caixa d'agua ou antena. Vai como def para
		# o PropMesh (geometria de verdade, nao mais um cubo), que e o que da a
		# silhueta la em cima.
		_roof_props(defs, roof_kind, roof_hue, roof_cx, roof_cz, roof_w, roof_d, roof_y,
				roof_ox, roof_oz)
		# Ar-condicionado: preso na fachada que olha para a rua, acima do terreo
		# e abaixo do topo do volume (nunca flutuando na frente de um recuo).
		if ac_n > 0:
			_place_acs(defs, bx, bz, w, d, side, ground_y, ground_top, ac_n, ac_pick,
					ac_off, ac_hue)
		# Com loja, a placa colorida ja marca a fachada: o toldo sairia em cima
		# dela (os dois a ~3,4 m).
		if awning and floors >= 2 and floors <= 8 and not shop_open:
			_add_awning(gb, lx, lz, bx, bz, w, d, ground_y, ax, az, awning_col)
		# Varandas na fachada da rua (B-81): so em predio residencial alto o
		# bastante para ter andar sobrando, e nunca sobre a loja aberta.
		if balcony and floors >= 4 and floors <= 9 and not shop_open and w >= 8.5 and d >= 8.5:
			_add_balconies(gb, bx, bz, w, d, side, ground_y, floors, ground_top)
		# Embasamento de pedra (B-81): assenta o predio no passeio. Com a loja
		# aberta a faixa atravessaria o vao, entao ela so entra na fachada
		# fechada.
		if not shop_open:
			_add_base_band(gb, full, ground_y)
	# Colisores: com o vao aberto viram corpo do predio + duas laterais do vao;
	# sem loja (ou no LOD far, onde a frente fica fechada) continua um retangulo.
	if shop_open:
		colliders.append_array(shop_colliders(bx, bz, w, d, side, bw, bd))
	else:
		colliders.append(Rect2(bx - w * 0.5, bz - d * 0.5, w, d))


## Detalhe de cobertura na laje (caixa d'agua, casa de maquinas ou antena).
static func _roof_props(defs: Array, kind: int, hue: float, cx: float, cz: float,
		w: float, d: float, y: float, ox: float, oz: float) -> void:
	var k := "caixa_dagua"
	if kind == 1:
		k = "casa_maquinas"
	elif kind == 2:
		k = "antena"
	# O prop fica DENTRO da laje: o deslocamento e limitado pela sobra de area
	# (1,8 m cobre o maior deles, a casa de maquinas de 3,2 m de lado).
	var px := cx + ox * maxf(0.0, w * 0.5 - 1.8)
	var pz := cz + oz * maxf(0.0, d * 0.5 - 1.8)
	defs.append({"c": Vector3(px, y, pz), "kind": k, "h": 3.0, "hue": hue})


## Ar-condicionado de split preso na fachada que olha para a rua. O def traz a
## rotacao em `rot` porque a malha do aparelho sai da parede no +X: girar o +X
## para a normal de fora e o que faz o aparelho ficar de frente para a rua.
## Nunca acima de `top_y` (o topo do volume daquele predio), senao ele flutuaria
## na frente de um recuo.
static func _place_acs(defs: Array, bx: float, bz: float, w: float, d: float, side: int,
		ground_y: float, top_y: float, count: int, pick: float, off: float, hue: float) -> void:
	var room := top_y - ground_y - 3.2
	if room < 2.4:
		return
	var levels := int(room / 3.0)
	var span := w if side < 2 else d
	var face := Vector2.ZERO
	var nrm := Vector3.ZERO
	var tan := Vector3.ZERO
	match side:
		0:
			face = Vector2(bx - w * 0.5, bz)
			nrm = Vector3(-1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
		1:
			face = Vector2(bx + w * 0.5, bz)
			nrm = Vector3(1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
		2:
			face = Vector2(bx, bz - d * 0.5)
			nrm = Vector3(0.0, 0.0, -1.0)
			tan = Vector3(1.0, 0.0, 0.0)
		_:
			face = Vector2(bx, bz + d * 0.5)
			nrm = Vector3(0.0, 0.0, 1.0)
			tan = Vector3(1.0, 0.0, 0.0)
	# Gira +X para a normal de fora (rotacao em Y: +X -> (cos, 0, -sin)).
	var rot := atan2(-nrm.z, nrm.x)
	var first := 1 + int(clampf(pick, 0.0, 0.999) * float(maxi(1, levels)))
	for i in count:
		var level := first + i
		if level > levels:
			break
		var y := ground_y + float(level) * 3.0 + 1.35
		var lateral := off * span * 0.32
		if count > 1:
			lateral += (float(i) - 0.5) * 2.2
		var base := Vector3(face.x, 0.0, face.y) + tan * lateral
		defs.append({"c": Vector3(base.x, y, base.z), "kind": "ar_condicionado",
				"h": 0.62, "hue": hue, "rot": rot})


## Lado da quadra mais proximo da calcada: 0 = oeste, 1 = leste, 2 = sul,
## 3 = norte. E para la que a loja e o toldo olham.
static func street_side(lx: float, lz: float, ax: float, az: float) -> int:
	var side := 0
	var best := lx - ax
	if ax + BLOCK - lx < best:
		side = 1
		best = ax + BLOCK - lx
	if lz - az < best:
		side = 2
		best = lz - az
	if az + BLOCK - lz < best:
		side = 3
	return side


## Colisores de um predio COM loja: o vao fica ABERTO para a rua e as paredes
## viram retangulos (corpo do predio + duas laterais do vao). Puro e testado:
## e o que garante que da para entrar andando e que parede nao se atravessa.
static func shop_colliders(bx: float, bz: float, w: float, d: float, side: int,
		bw: float, bd: float) -> Array:
	var x0 := bx - w * 0.5
	var x1 := bx + w * 0.5
	var z0 := bz - d * 0.5
	var z1 := bz + d * 0.5
	var half_z := (z1 - z0) * 0.5 - bw * 0.5
	var half_x := (x1 - x0) * 0.5 - bw * 0.5
	var out: Array = []
	match side:
		0:
			out.append(Rect2(x0 + bd, z0, w - bd, d))
			out.append(Rect2(x0, z0, bd, half_z))
			out.append(Rect2(x0, bz + bw * 0.5, bd, z1 - (bz + bw * 0.5)))
		1:
			out.append(Rect2(x0, z0, w - bd, d))
			out.append(Rect2(x1 - bd, z0, bd, half_z))
			out.append(Rect2(x1 - bd, bz + bw * 0.5, bd, z1 - (bz + bw * 0.5)))
		2:
			out.append(Rect2(x0, z0 + bd, w, d - bd))
			out.append(Rect2(x0, z0, half_x, bd))
			out.append(Rect2(bx + bw * 0.5, z0, x1 - (bx + bw * 0.5), bd))
		_:
			out.append(Rect2(x0, z0, w, d - bd))
			out.append(Rect2(x0, z1 - bd, half_x, bd))
			out.append(Rect2(bx + bw * 0.5, z1 - bd, x1 - (bx + bw * 0.5), bd))
	return out


## Quad vertical (parede) com normal `nrm`: a ordem dos pontos e corrigida
## sozinha se o winding sair ao contrario (a convencao do arquivo e front =
## -(b-a) x (d-a)). Assim nenhuma parede da loja some por engano.
static func _wall_quad(gb: GBuf, a: Vector2, b: Vector2, y0: float, y1: float,
		nrm: Vector3, col: Color) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.y - a.y)
	if (-(d.cross(Vector3.UP))).dot(nrm) < 0.0:
		var tmp := a
		a = b
		b = tmp
	gb.normal(nrm)
	_add_quad(gb, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y),
			Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), col)


## Parede da fachada com um VAO retangular (a frente da loja): desenha os dois
## lados e a verga por cima do vao, com UV de fachada continuo — o modulo da
## janela nao escorrega. Abaixo do vao nao se desenha nada: fica enterrado.
static func _wall_with_hole(tb: TBuf, a: Vector2, b: Vector2, y0: float, y1: float,
		off: float, ow: float, hole_y0: float, hole_y1: float, col: Color) -> void:
	var dir := b - a
	var seg := dir.length()
	if seg < 0.2:
		return
	var u := dir / seg
	var nrm := Vector3(u.y, 0.0, -u.x)
	_wall_piece(tb, a, u, nrm, 0.0, off, y0, y1, y0, col)
	_wall_piece(tb, a, u, nrm, off + ow, seg, y0, y1, y0, col)
	_wall_piece(tb, a, u, nrm, off, off + ow, hole_y1, y1, y0, col)


## Pedaco de parede entre t0..t1 (ao longo da face) e yb..yt, com UV de modulo.
static func _wall_piece(tb: TBuf, a: Vector2, u: Vector2, nrm: Vector3,
		t0: float, t1: float, yb: float, yt: float, y_base: float, col: Color) -> void:
	if t1 - t0 < 0.02 or yt - yb < 0.02:
		return
	var p0 := a + u * t0
	var p1 := a + u * t1
	tb.quad_uv(
			Vector3(p0.x, yb, p0.y), Vector3(p1.x, yb, p1.y),
			Vector3(p1.x, yt, p1.y), Vector3(p0.x, yt, p0.y), nrm,
			Vector2(t0 / tb.tile, (yb - y_base) / tb.tile_v),
			Vector2(t1 / tb.tile, (yb - y_base) / tb.tile_v),
			Vector2(t1 / tb.tile, (yt - y_base) / tb.tile_v),
			Vector2(t0 / tb.tile, (yt - y_base) / tb.tile_v), col)


## Onde fica a loja, em dados: o ponto do BALCONISTA (atras do balcao), o centro
## do vao (onde o jogador entra e o HUD avisa o nome), para onde olhar e o nome.
## Puro: o teste confere posicao, lado e nome sem GPU.
static func _shop_spot(bx: float, bz: float, w: float, d: float, side: int,
		bw: float, bd: float, ground_y: float, kind: int) -> Dictionary:
	var face := Vector2.ZERO
	var inward := Vector2.ZERO
	match side:
		0:
			face = Vector2(bx - w * 0.5, bz)
			inward = Vector2(1.0, 0.0)
		1:
			face = Vector2(bx + w * 0.5, bz)
			inward = Vector2(-1.0, 0.0)
		2:
			face = Vector2(bx, bz - d * 0.5)
			inward = Vector2(0.0, 1.0)
		_:
			face = Vector2(bx, bz + d * 0.5)
			inward = Vector2(0.0, -1.0)
	# Balconista atras do balcao (o balcao fica a 62% da profundidade).
	var stand := face + inward * minf(bd * 0.62 + 0.9, bd - 0.5)
	var front := face + inward * minf(bd * 0.35, 2.0)
	return {
		"stand": Vector3(stand.x, ground_y, stand.y),
		"front": Vector3(front.x, ground_y, front.y),
		"facing": -inward,
		"name": String(SHOP_TYPES[kind][0]),
		"kind": kind,
	}


## Loja aberta para a calcada (B-65): interior com piso, forro, paredes de fundo
## e laterais (quads simples, so a face de dentro), balcao, prateleira, dois
## produtos e a PLACA colorida na fachada. Tudo no buffer de cor por vertice:
## nenhum desenho novo por setor.
static func _add_shop(gb: GBuf, bx: float, bz: float, w: float, d: float, side: int,
		bw: float, bd: float, ground_y: float, kind: int) -> void:
	var face := Vector2.ZERO
	var inward := Vector2.ZERO
	match side:
		0:
			face = Vector2(bx - w * 0.5, bz)
			inward = Vector2(1.0, 0.0)
		1:
			face = Vector2(bx + w * 0.5, bz)
			inward = Vector2(-1.0, 0.0)
		2:
			face = Vector2(bx, bz - d * 0.5)
			inward = Vector2(0.0, 1.0)
		_:
			face = Vector2(bx, bz + d * 0.5)
			inward = Vector2(0.0, -1.0)
	var across := Vector2(-inward.y, inward.x)
	var nrm_in := Vector3(-inward.x, 0.0, -inward.y)     # normal para DENTRO
	var half := bw * 0.5
	var deep := bd
	var y0 := ground_y + 0.02
	# Forro 3 cm abaixo do pe direito: com predio de 1 andar o teto da loja
	# encostaria na laje e os dois brigariam por profundidade na tela.
	var roof := ground_y + SHOP_H - 0.03
	# Piso e forro: U (para dentro) x V (ao longo da frente) = -cima, entao a
	# ordem abaixo da a normal para cima (piso) e a invertida da para baixo.
	var u3 := Vector3(inward.x, 0.0, inward.y)
	var v3 := Vector3(across.x, 0.0, across.y)
	var base := face + inward * 0.05 - across * half
	var p00 := Vector3(base.x, y0, base.y)
	var p10 := p00 + u3 * (deep - 0.1)
	var p11 := p10 + v3 * bw
	var p01 := p00 + v3 * bw
	gb.normal(Vector3.UP)
	_add_quad(gb, p00, p10, p11, p01, SHOP_FLOOR)
	gb.normal(Vector3.DOWN)
	_add_quad(gb, Vector3(p01.x, roof, p01.z), Vector3(p11.x, roof, p11.z),
			Vector3(p10.x, roof, p10.z), Vector3(p00.x, roof, p00.z), SHOP_WALL)
	# Paredes: fundo e as duas laterais (so a face de dentro).
	var back_a := face + inward * deep + across * half
	var back_b := face + inward * deep - across * half
	_wall_quad(gb, back_a, back_b, y0, roof, nrm_in, SHOP_WALL)
	var l0 := face + inward * 0.05 + across * half
	var l1 := face + inward * deep + across * half
	_wall_quad(gb, l0, l1, y0, roof, -Vector3(across.x, 0.0, across.y), SHOP_WALL)
	var r0 := face + inward * 0.05 - across * half
	var r1 := face + inward * deep - across * half
	_wall_quad(gb, r0, r1, y0, roof, Vector3(across.x, 0.0, across.y), SHOP_WALL)
	# Balcao perto do fundo, prateleira na parede do fundo, dois produtos.
	var col: Color = SHOP_TYPES[kind][1]
	var counter := face + inward * (deep * 0.62)
	var sx := 0.6 if absf(inward.x) > 0.5 else minf(bw * 0.72, 2.4)
	var sz := minf(bw * 0.72, 2.4) if absf(inward.x) > 0.5 else 0.6
	_add_box(gb, Vector3(counter.x, ground_y + 0.50, counter.y), Vector3(sx, 1.0, sz), SHOP_COUNTER)
	var shelf := face + inward * (deep - 0.25)
	var shx := 0.35 if absf(inward.x) > 0.5 else bw * 0.7
	var shz := bw * 0.7 if absf(inward.x) > 0.5 else 0.35
	_add_box(gb, Vector3(shelf.x, ground_y + 1.05, shelf.y), Vector3(shx, 1.7, shz), SHOP_COUNTER)
	for k in 2:
		var o := face + inward * (deep - 0.35) + across * (half * 0.45 * (1.0 if k == 0 else -1.0))
		_add_box(gb, Vector3(o.x, ground_y + 1.05, o.y),
				Vector3(0.3, 0.35, 0.3), col.lerp(Color.WHITE, 0.35))
	# Placa da loja, acima do vao, na cor do tipo (padaria, farmacia, bar...).
	# A frente escura por fora da a leitura de "placa" em vez de "faixa".
	var sign := face + inward * 0.06
	var pgx := 0.14 if absf(inward.x) > 0.5 else bw * 1.02
	var pgz := bw * 1.02 if absf(inward.x) > 0.5 else 0.14
	_add_box(gb, Vector3(sign.x, roof + 0.42, sign.y), Vector3(pgx, 0.72, pgz), col)



## Quad com normal CORRIGIDA pelo winding: o chamador diz para onde a face deve
## olhar (`want`) e a ordem dos vertices e ajustada sozinha. E o que permite
## desenhar toldo inclinado, porta e platibanda sem errar o sentido da face.
static func _quad_out(gb: GBuf, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, want: Vector3) -> void:
	var nrm := -(b - a).cross(d - a)
	if nrm.length_squared() < 1e-10:
		return
	if nrm.dot(want) < 0.0:
		var tmp := b
		b = d
		d = tmp
		nrm = -nrm
	gb.normal(nrm.normalized())
	_add_quad(gb, a, b, c, d, col)


## Painel plano encostado numa fachada: retangulo de `hw` de meia-largura ao
## longo de `tan`, de y0 a y1, virado para `nrm`. Usado pela porta de entrada.
static func _facade_panel(gb: GBuf, center: Vector3, tan: Vector3, nrm: Vector3,
		hw: float, y0: float, y1: float, col: Color) -> void:
	var a := center - tan * hw
	var b := center + tan * hw
	_quad_out(gb, a + Vector3(0.0, y0, 0.0), b + Vector3(0.0, y0, 0.0),
			b + Vector3(0.0, y1, 0.0), a + Vector3(0.0, y1, 0.0), col, nrm)


## Porta de entrada do predio (B-80): moldura clara e o vidro escuro da portaria.
## Antes todo predio era um bloco fechado, sem porta nenhuma na rua.
static func _add_entrance(gb: GBuf, bx: float, bz: float, w: float, d: float, side: int,
		ground_y: float) -> void:
	var face := Vector2.ZERO
	var nrm := Vector3.ZERO
	var tan := Vector3.ZERO
	match side:
		0:
			face = Vector2(bx - w * 0.5, bz)
			nrm = Vector3(-1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
		1:
			face = Vector2(bx + w * 0.5, bz)
			nrm = Vector3(1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
		2:
			face = Vector2(bx, bz - d * 0.5)
			nrm = Vector3(0.0, 0.0, -1.0)
			tan = Vector3(1.0, 0.0, 0.0)
		_:
			face = Vector2(bx, bz + d * 0.5)
			nrm = Vector3(0.0, 0.0, 1.0)
			tan = Vector3(1.0, 0.0, 0.0)
	var half := (w if side < 2 else d) * 0.5
	var hw := clampf(half * 0.34, 0.7, 1.5)
	var centre := Vector3(face.x, 0.0, face.y)
	var y0 := ground_y + 0.02
	_facade_panel(gb, centre + nrm * 0.05, tan, nrm, hw + 0.22, y0, y0 + 3.05,
			Color(0.80, 0.79, 0.74))
	_facade_panel(gb, centre + nrm * 0.09, tan, nrm, hw, y0, y0 + 2.85,
			Color(0.14, 0.20, 0.22))


## Toldo do comercio: LONA INCLINADA que sai da parede e cai sobre a calcada,
## com a saia na frente. Antes era um caixote de 25 cm de espessura colado na
## fachada, que na tela lia como uma laje solta (B-80).
static func _add_awning(gb: GBuf, lx: float, lz: float, bx: float, bz: float,
		w: float, d: float, ground_y: float, ax: float, az: float, col: Color) -> void:
	# Qual face do lote esta mais perto da calcada.
	var south := lz - az
	var north := az + BLOCK - lz
	var west := lx - ax
	var east := ax + BLOCK - lx
	var side := 0
	var best := west
	if east < best:
		side = 1
		best = east
	if south < best:
		side = 2
		best = south
	if north < best:
		side = 3
	# Normal de fora, tangente ao longo da fachada e meia-largura disponivel.
	var nrm := Vector3.ZERO
	var tan := Vector3.ZERO
	var face := Vector2.ZERO
	match side:
		0:
			nrm = Vector3(-1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
			face = Vector2(bx - w * 0.5, bz)
		1:
			nrm = Vector3(1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
			face = Vector2(bx + w * 0.5, bz)
		2:
			nrm = Vector3(0.0, 0.0, -1.0)
			tan = Vector3(1.0, 0.0, 0.0)
			face = Vector2(bx, bz - d * 0.5)
		_:
			nrm = Vector3(0.0, 0.0, 1.0)
			tan = Vector3(1.0, 0.0, 0.0)
			face = Vector2(bx, bz + d * 0.5)
	var span := (w if side < 2 else d) * 0.82
	var reach := 1.9
	var y_high := ground_y + 3.45      # na parede
	var y_low := ground_y + 3.05       # na ponta, sobre a calcada
	var inner := Vector3(face.x, 0.0, face.y)
	var outer := inner + nrm * reach
	# Lona: duas faces (de cima e de baixo), porque o jogador passa por baixo.
	_quad_out(gb, inner - tan * span * 0.5 + Vector3(0.0, y_high, 0.0),
			inner + tan * span * 0.5 + Vector3(0.0, y_high, 0.0),
			outer + tan * span * 0.5 + Vector3(0.0, y_low, 0.0),
			outer - tan * span * 0.5 + Vector3(0.0, y_low, 0.0), col,
			(nrm + Vector3.UP).normalized())
	_quad_out(gb, inner - tan * span * 0.5 + Vector3(0.0, y_high - 0.04, 0.0),
			inner + tan * span * 0.5 + Vector3(0.0, y_high - 0.04, 0.0),
			outer + tan * span * 0.5 + Vector3(0.0, y_low - 0.04, 0.0),
			outer - tan * span * 0.5 + Vector3(0.0, y_low - 0.04, 0.0),
			col.darkened(0.28), (-nrm + Vector3.DOWN).normalized())
	# Saia do toldo na ponta (a faixa onde o comercio escreve o nome).
	_quad_out(gb, outer - tan * span * 0.5 + Vector3(0.0, y_low, 0.0),
			outer + tan * span * 0.5 + Vector3(0.0, y_low, 0.0),
			outer + tan * span * 0.5 + Vector3(0.0, y_low - 0.32, 0.0),
			outer - tan * span * 0.5 + Vector3(0.0, y_low - 0.32, 0.0),
			col.darkened(0.12), nrm)


## Varandas na fachada que olha para a rua (B-81). Uma laje a cada dois andares
## a partir do segundo, com guarda-corpo na frente e nos lados. Custa 1 caixa e
## 3 quads por varanda: entra no buffer de cor por vertice, sem desenho novo.
##
## `floors` e o numero de andares do VOLUME; a varanda pula o primeiro (loja),
## o ultimo (onde fica a platibanda) e qualquer andar acima de `max_y` — em
## predio com torre recuada o volume de baixo e mais largo, e uma varanda presa
## na fachada de baixo ficaria flutuando no vazio depois do recuo.
static func _add_balconies(gb: GBuf, bx: float, bz: float, w: float, d: float,
		side: int, ground_y: float, floors: int, max_y: float) -> void:
	# Normal de fora, tangente ao longo da fachada e o ponto dela no chao.
	var face := Vector3.ZERO
	var nrm := Vector3.ZERO
	var tan := Vector3.ZERO
	match side:
		0:
			face = Vector3(bx - w * 0.5, 0.0, bz)
			nrm = Vector3(-1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
		1:
			face = Vector3(bx + w * 0.5, 0.0, bz)
			nrm = Vector3(1.0, 0.0, 0.0)
			tan = Vector3(0.0, 0.0, 1.0)
		2:
			face = Vector3(bx, 0.0, bz - d * 0.5)
			nrm = Vector3(0.0, 0.0, -1.0)
			tan = Vector3(1.0, 0.0, 0.0)
		_:
			face = Vector3(bx, 0.0, bz + d * 0.5)
			nrm = Vector3(0.0, 0.0, 1.0)
			tan = Vector3(1.0, 0.0, 0.0)
	var span := (d if side < 2 else w) * 0.62
	if span < 3.0:
		return
	var reach := BALCONY_REACH
	for f in floors:
		if f < 2 or f % 2 == 1 or f >= floors - 1:
			continue
		var y := ground_y + float(f) * 3.0
		if y + 1.10 > max_y:
			continue
		# Laje: a caixa e montada nos eixos da face (nunca em diagonal, porque
		# os predios do city_gen sao retangulares). O fundo entra 12 cm DENTRO
		# da parede para a face da laje nao ficar coplanar com a fachada (duas
		# superficies no mesmo plano brigam por profundidade — regra do B-52).
		var mid := face + nrm * ((reach - 0.12) * 0.5) + Vector3(0.0, y + 0.07, 0.0)
		var thick := reach + 0.12
		_add_box(gb, mid, Vector3(absf(nrm.x) * thick + absf(tan.x) * span, 0.14,
				absf(nrm.z) * thick + absf(tan.z) * span), BALCONY_SLAB)
		var a := face + nrm * reach - tan * (span * 0.5)
		var b := face + nrm * reach + tan * (span * 0.5)
		# Guarda-corpo da frente (um quad so: a face de dentro nao existe).
		_quad_out(gb, a + Vector3(0.0, y + 0.14, 0.0), b + Vector3(0.0, y + 0.14, 0.0),
				b + Vector3(0.0, y + 1.00, 0.0), a + Vector3(0.0, y + 1.00, 0.0),
				BALCONY_RAIL, nrm)
		for s in [-1.0, 1.0]:
			var e := face + tan * (span * 0.5 * float(s))
			var eo := e + nrm * reach
			_quad_out(gb, e + Vector3(0.0, y + 0.14, 0.0), eo + Vector3(0.0, y + 0.14, 0.0),
					eo + Vector3(0.0, y + 1.00, 0.0), e + Vector3(0.0, y + 1.00, 0.0),
					BALCONY_RAIL, tan * float(s))


## Faixa de embasamento (B-81): pedra do nivel da rua ate PLINTH_H, 6 cm para
## fora da parede. Assenta o predio no chao e separa a loja do corpo do predio.
static func _add_base_band(gb: GBuf, plan: PackedVector2Array, ground_y: float) -> void:
	var n := plan.size()
	for i in n:
		var a := plan[i]
		var b := plan[(i + 1) % n]
		var dx := b.x - a.x
		var dz := b.y - a.y
		var seg := sqrt(dx * dx + dz * dz)
		if seg < 0.05:
			continue
		var nrm := Vector3(dz / seg, 0.0, -dx / seg)
		var o := nrm * 0.06
		_quad_out(gb, Vector3(a.x, ground_y, a.y) + o,
				Vector3(b.x, ground_y, b.y) + o,
				Vector3(b.x, ground_y + PLINTH_H, b.y) + o,
				Vector3(a.x, ground_y + PLINTH_H, a.y) + o, PLINTH, nrm)


## Ruas da quadra (borda oeste e sul) com a sinalizacao pintada.
##
## As duas ruas NAO se sobrepoem mais (B-52). Antes a vertical era desenhada
## inteira e a horizontal subia 5 mm para ganhar a disputa no cruzamento — mas
## 5 mm nao resolvem nada a partir de ~150 m: o cruzamento piscava (z-fighting)
## e na tela isso parece granulado na rua. Agora a vertical e desenhada so no
## trecho que nenhuma horizontal cobre (de az + h a az + BLOCK - h): as duas
## faixas de 10 m dos cruzamentos ficam por conta das horizontais, que ja
## passam ali. A horizontal so cobre x >= ax, entao a faixa a oeste continua
## vindo da horizontal da quadra vizinha, como antes.
## A pintura (eixo amarelo, faixa de pedestres, linha de retencao) e so do LOD
## full: e detalhe de perto e custa vertices que o anel distante nao precisa.
static func _add_roads(gb: GBuf, road: TBuf, ax: float, az: float, lod: int) -> void:
	var h := ROAD * 0.5
	_add_flat_tx(road, ax, az - h, ax + BLOCK, az + h)
	_add_flat_tx(road, ax - h, az + h, ax + h, az + BLOCK - h)
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


## Planta retangular no plano XZ com UM canto chanfrado opcional, em ordem
## ANTI-HORARIA (a que `_add_prism_tx` espera). `corner`: 0 = (+x, +z),
## 1 = (-x, +z), 2 = (-x, -z), 3 = (+x, -z). `corner` negativo ou `cut` ~0
## devolve o retangulo reto (4 pontos).
static func _plan_rect(cx: float, cz: float, w: float, d: float, corner: int,
		cut: float) -> PackedVector2Array:
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	# O chanfro nunca come metade do lado, senao o canto desaparece.
	var c := clampf(cut, 0.0, minf(w, d) * 0.42)
	var pts := PackedVector2Array()
	# Canto (-x, -z): vem de -z, sai para +x.
	if corner == 2 and c > 0.01:
		pts.append(Vector2(x0, z0 + c))
		pts.append(Vector2(x0 + c, z0))
	else:
		pts.append(Vector2(x0, z0))
	# Canto (+x, -z): vem de +x, sai para +z.
	if corner == 3 and c > 0.01:
		pts.append(Vector2(x1 - c, z0))
		pts.append(Vector2(x1, z0 + c))
	else:
		pts.append(Vector2(x1, z0))
	# Canto (+x, +z): vem de +z, sai para -x.
	if corner == 0 and c > 0.01:
		pts.append(Vector2(x1, z1 - c))
		pts.append(Vector2(x1 - c, z1))
	else:
		pts.append(Vector2(x1, z1))
	# Canto (-x, +z): vem de -x, sai para -z.
	if corner == 1 and c > 0.01:
		pts.append(Vector2(x0 + c, z1))
		pts.append(Vector2(x0, z1 - c))
	else:
		pts.append(Vector2(x0, z1))
	return pts


## Area (m2) de uma planta convexa no plano XZ.
static func plan_area(pts: PackedVector2Array) -> float:
	var sum := 0.0
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


## Prisma de FACHADA a partir de uma planta convexa em XZ (anti-horaria).
##
## Paredes com UV de modulo de fachada (repete a cada `tb.tile` x `tb.tile_v`
## metros) e teto em leque com o canto liso da textura, na cor de telhado. A
## face de baixo nao existe (o predio esta enterrado) — e o que faz este prisma
## custar menos vertices que a caixa de 6 faces de antes.
static func _add_prism_tx(tb: TBuf, plan: PackedVector2Array, y0: float, y1: float,
		wall_col: Color, roof_col: Color, skip_edge: int = -1,
		parapet: float = 0.0) -> void:
	var n := plan.size()
	if n < 3 or y1 - y0 < 0.05:
		return
	var vv := (y1 - y0) / tb.tile_v
	for i in n:
		if i == skip_edge:
			continue
		var a := plan[i]
		var b := plan[(i + 1) % n]
		var dx := b.x - a.x
		var dz := b.y - a.y
		var seg := sqrt(dx * dx + dz * dz)
		if seg < 0.05:
			continue
		# Normal para fora: o sentido de percurso anti-horario em (x, z) deixa o
		# exterior a direita, isto e (dz, -dx).
		var nrm := Vector3(dz / seg, 0.0, -dx / seg)
		var uu := seg / tb.tile
		var a0 := Vector3(a.x, y0, a.y)
		var b0 := Vector3(b.x, y0, b.y)
		var b1 := Vector3(b.x, y1, b.y)
		var a1 := Vector3(a.x, y1, a.y)
		# Ordem (a0, b0, b1, a1): -(b-a) x (d-a) = normal, a convencao do arquivo.
		tb.quad_uv(a0, b0, b1, a1, nrm,
				Vector2(0.0, 0.0), Vector2(uu, 0.0), Vector2(uu, vv), Vector2(0.0, vv), wall_col)
	# Teto: leque a partir do centroide (a planta e convexa).
	var c := Vector2.ZERO
	for p in plan:
		c += p
	c /= float(n)
	var cc := Vector3(c.x, y1, c.y)
	for k in n:
		var pa := plan[k]
		var pb := plan[(k + 1) % n]
		var qx := pb.x - pa.x
		var qz := pb.y - pa.y
		if qx * qx + qz * qz < 0.0025:
			continue
		tb.tri_uv(cc, Vector3(pa.x, y1, pa.y), Vector3(pb.x, y1, pb.y), Vector3.UP,
				FLAT_UV, FLAT_UV, FLAT_UV, roof_col)
	# Platibanda (B-80): a faixa de concreto em volta da laje, com o topo de
	# PARAPET_W de largura. Custa 2 quads por aresta e muda a leitura do predio:
	# sem ela o volume termina num corte seco e a laje parece papelao. As faces
	# usam o canto LISO da textura (FLAT_UV): platibanda nao tem janela.
	if parapet > 0.02:
		var ph := parapet
		var band := roof_col.darkened(0.10)
		var cap := roof_col.lightened(0.05)
		for i in n:
			var a := plan[i]
			var b := plan[(i + 1) % n]
			var dx := b.x - a.x
			var dz := b.y - a.y
			var seg := sqrt(dx * dx + dz * dz)
			if seg < 0.05:
				continue
			var nrm := Vector3(dz / seg, 0.0, -dx / seg)
			tb.quad_uv(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y),
					Vector3(b.x, y1 + ph, b.y), Vector3(a.x, y1 + ph, a.y), nrm,
					FLAT_UV, FLAT_UV, FLAT_UV, FLAT_UV, band)
			var ix := nrm.x * PARAPET_W
			var iz := nrm.z * PARAPET_W
			tb.quad_uv(Vector3(a.x, y1 + ph, a.y), Vector3(b.x, y1 + ph, b.y),
					Vector3(b.x - ix, y1 + ph, b.y - iz),
					Vector3(a.x - ix, y1 + ph, a.y - iz), Vector3.UP,
					FLAT_UV, FLAT_UV, FLAT_UV, FLAT_UV, cap)


# --- Utilitarios -------------------------------------------------------------

## Mistura deterministica de tres inteiros em 31 bits (sempre positivo).
static func mix3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


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
	## Repeticao vertical (quando difere da horizontal, como na fachada).
	var tile_v := 3.0

	func _init(tile_m: float, tile_v_m: float = -1.0) -> void:
		tile = maxf(0.5, tile_m)
		tile_v = tile if tile_v_m < 0.0 else maxf(0.5, tile_v_m)

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

	## Triangulo com UV explicito (leque do teto do prisma dos predios).
	## Mesma convencao de winding do resto do arquivo: a frente e -(b-a)x(c-a).
	func tri_uv(a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2, color: Color) -> void:
		v.append(a)
		v.append(b)
		v.append(c)
		n.append(normal)
		n.append(normal)
		n.append(normal)
		uv.append(ua)
		uv.append(ub)
		uv.append(uc)
		col.append(color)
		col.append(color)
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
