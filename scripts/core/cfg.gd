extends RefCounted
## Cfg: constantes e funcoes PURAS do mundo (sem Node, sem autoload).
## Pode ser usado por threads, por testes headless e por ferramentas.
##
## Convencao de coordenadas (v0.1):
##   1 unidade = 1 metro. +X = leste, +Z = norte, +Y = cima.
##   z < 0 e mar; a praia vai de z = 0 a BEACH_EDGE_Z; a cidade comeca em
##   CITY_MIN_Z (Avenida Atlantica) e segue para o interior (+Z).
##   Origem (0, 0) = ORIGIN_LON / ORIGIN_LAT (frente de Copacabana).
##   O litoral e IDEALIZADO como uma reta; o mapa real vem de data/geo na Fase 2.

const APP_NAME := "CARIOCA"
const APP_VERSION := "0.1.0-dev"
const SAVE_SCHEMA := 1

# --- Georreferencia ---------------------------------------------------------
const ORIGIN_LAT := -22.97430
const ORIGIN_LON := -43.18280
const METERS_PER_DEG_LAT := 110540.0
const METERS_PER_DEG_LON := 102450.0   # em ~22.97 S

# --- Setores (streaming) ----------------------------------------------------
const SECTOR_SIZE := 512.0
const CELL_SIZE := 32.0                # resolucao do terreno
const SECTOR_MIN := Vector2i(0, -1)    # setores jogaveis nesta fase (inclusive)
const SECTOR_MAX := Vector2i(11, 4)
const WORLD_MIN := Vector2(0.0, -512.0)
const WORLD_MAX := Vector2(6144.0, 2560.0)

# --- Cidade ------------------------------------------------------------------
# CITY_MIN_Z e BEACH_EDGE_Z sao multiplos de 64 (BLOCK_SIZE) para que a grade de
# quadras nao cruze a fronteira dos setores de 512 m (512 = 8 x 64).
const BEACH_EDGE_Z := 128.0            # fim da areia / inicio da Av. Atlantica
const CITY_MIN_Z := 128.0
const CITY_MAX_Z := 2304.0
const BLOCK_SIZE := 64.0
const ROAD_WIDTH := 10.0
const SIDEWALK_WIDTH := 3.0
const HILL_START_Z := 2000.0

# --- Orcamento de render -----------------------------------------------------
## Distancia (m) das sombras do sol. B-72: com 120 m o "shadow pass" puxava
## metade da cidade quando o sol baixava (draw calls 145 -> 263 e primitivas
## 76k -> 176k sem o jogador sair do lugar) e o FPS caia de 29 para 9 no build
## Web. 80 m mantem sombra onde o jogador ve e corta o custo.
const SUN_SHADOW_DISTANCE := 80.0

# --- Agua --------------------------------------------------------------------
const SEA_LEVEL := 0.0
const MIN_WADE_DEPTH := -0.6           # terreno mais fundo que isso: intransponivel

# --- Calcada -----------------------------------------------------------------
# O miolo da quadra (calcada + lotes) fica CURB_HEIGHT acima do terreno: e o
# meio-fio. A rua, a praia e o resto da cidade ficam no nivel do terreno.
const CURB_HEIGHT := 0.15


## Altura extra da calcada em (x, z): CURB_HEIGHT no miolo da quadra, 0 na rua,
## na praia e fora da cidade. A grade e a mesma do city_gen (BLOCK_SIZE).
static func curb_at(x: float, z: float) -> float:
	if z < CITY_MIN_Z or z > CITY_MAX_Z or x < 0.0:
		return 0.0
	var edge := ROAD_WIDTH * 0.5
	var bx := fposmod(x, BLOCK_SIZE)
	var bz := fposmod(z - CITY_MIN_Z, BLOCK_SIZE)
	if bx > edge and bx < BLOCK_SIZE - edge and bz > edge and bz < BLOCK_SIZE - edge:
		return CURB_HEIGHT
	return 0.0


## Chao em que o personagem e os veiculos andam: terreno + calcada.
static func surface_at(x: float, z: float) -> float:
	return height_at(x, z) + curb_at(x, z)



## Altura do terreno (m) em (x, z). Analitica e deterministica.
## Fase 2 troca por DEM real (Copernicus GLO-30 / SRTM) amostrado em disco.
static func height_at(x: float, z: float) -> float:
	if z < 0.0:
		return maxf(-12.0, -0.4 + z * 0.03)
	if z < BEACH_EDGE_Z:
		return lerpf(-0.4, 1.2, z / BEACH_EDGE_Z)
	var base := 1.2 + minf(z - BEACH_EDGE_Z, CITY_MAX_Z) * 0.0045
	var hill := smoothstep(HILL_START_Z, 4200.0, z)
	var n := sin(x * 0.00035) * cos(z * 0.00042) + 0.5 * sin(x * 0.0011 + z * 0.0009)
	return base + hill * (35.0 + 20.0 * n)


static func sector_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / SECTOR_SIZE)), int(floor(z / SECTOR_SIZE)))


static func sector_in_bounds(s: Vector2i) -> bool:
	return s.x >= SECTOR_MIN.x and s.x <= SECTOR_MAX.x and s.y >= SECTOR_MIN.y and s.y <= SECTOR_MAX.y


## (x, z) local em metros -> Vector2(lon, lat).
static func local_to_lonlat(x: float, z: float) -> Vector2:
	return Vector2(ORIGIN_LON + x / METERS_PER_DEG_LON, ORIGIN_LAT + z / METERS_PER_DEG_LAT)


## (lon, lat) -> Vector2(x, z) local em metros.
static func lonlat_to_local(lon: float, lat: float) -> Vector2:
	return Vector2((lon - ORIGIN_LON) * METERS_PER_DEG_LON, (lat - ORIGIN_LAT) * METERS_PER_DEG_LAT)


static func clock_label(hour: float) -> String:
	var h := int(floor(fposmod(hour, 24.0)))
	var m := int(floor(fposmod(hour, 1.0) * 60.0))
	return "%02d:%02d" % [h, m]
