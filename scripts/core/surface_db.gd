extends RefCounted
## SurfaceDB: banco UNICO de superficies do mundo (B-69).
##
## Antes, o piso do carro era um `match` dentro de vehicle_physics.gd e os props
## nao tinham piso nenhum. Agora existe UMA tabela: o carro, os objetos moveis e
## (nas proximas rodadas) o som e as particulas leem daqui. Duas colunas de
## atrito de proposito, porque sao coisas diferentes:
##   * `mu`    = aderencia do PNEU (o carro). Areia murcha: 0,55.
##   * `slide` = atrito de um OBJETO deslizando (caixa arrastada). Areia agarra
##     mais que asfalto: 0,85.
## `hardness` (N.s) e a resistencia da superficie a ser atingida; `dust` e a cor
## do pufo/particula e `sound` a etiqueta para o audio de impacto (o audio atual
## usa o mesmo `impact.wav` para tudo; a etiqueta permite trocar por material
## quando houver mais amostras CC0).
##
## Tudo aqui e PURO: sem no, sem cena, sem aleatoriedade. Testado no CI.

const Cfg = preload("res://scripts/core/cfg.gd")

# --- Aderencia dos pneus (o carro) -------------------------------------------
const MU_ASPHALT := 1.0
const MU_CONCRETE := 0.95
const MU_STONE := 0.85
const MU_SAND := 0.55
const MU_DIRT := 0.70
const MU_GRASS := 0.75
const MU_MUD := 0.40
const MU_WOOD := 0.65
const MU_METAL := 0.55
const MU_GLASS := 0.50
const MU_WATER := 0.20

## Etiqueta do calcadao de pedra portuguesa: fica entre a praia (sand) e a
## cidade (asphalt), com o z que o city_gen usa (111..127).
const STONE_Z0 := 111.0
const STONE_Z1 := 127.0

const DATA := {
	"asphalt": {"mu": MU_ASPHALT, "slide": 0.62, "bounce": 0.10, "hardness": 1800.0,
			"dust": Color(0.30, 0.30, 0.31), "sound": "asfalto"},
	"concrete": {"mu": MU_CONCRETE, "slide": 0.70, "bounce": 0.08, "hardness": 2000.0,
			"dust": Color(0.64, 0.63, 0.60), "sound": "concreto"},
	"stone": {"mu": MU_STONE, "slide": 0.60, "bounce": 0.12, "hardness": 1500.0,
			"dust": Color(0.55, 0.53, 0.50), "sound": "pedra"},
	"sand": {"mu": MU_SAND, "slide": 0.85, "bounce": 0.02, "hardness": 300.0,
			"dust": Color(0.82, 0.74, 0.55), "sound": "areia"},
	"dirt": {"mu": MU_DIRT, "slide": 0.75, "bounce": 0.03, "hardness": 420.0,
			"dust": Color(0.45, 0.35, 0.24), "sound": "terra"},
	"grass": {"mu": MU_GRASS, "slide": 0.68, "bounce": 0.03, "hardness": 350.0,
			"dust": Color(0.30, 0.45, 0.24), "sound": "grama"},
	"mud": {"mu": MU_MUD, "slide": 0.55, "bounce": 0.01, "hardness": 200.0,
			"dust": Color(0.32, 0.24, 0.16), "sound": "lama"},
	"wood": {"mu": MU_WOOD, "slide": 0.55, "bounce": 0.22, "hardness": 500.0,
			"dust": Color(0.50, 0.38, 0.24), "sound": "madeira"},
	"metal": {"mu": MU_METAL, "slide": 0.40, "bounce": 0.30, "hardness": 1200.0,
			"dust": Color(0.60, 0.62, 0.65), "sound": "metal"},
	"glass": {"mu": MU_GLASS, "slide": 0.35, "bounce": 0.35, "hardness": 120.0,
			"dust": Color(0.75, 0.85, 0.88), "sound": "vidro"},
	"water": {"mu": MU_WATER, "slide": 0.90, "bounce": 0.0, "hardness": 60.0,
			"dust": Color(0.55, 0.70, 0.78), "sound": "agua"},
}


## Piso em (x, z), na MESMA divisao que o city_gen desenha:
##   mar (z < 0), praia (areia) com o calcadao de pedra entre 111 e 127 m,
##   cidade com a rua no asfalto e o miolo da quadra na calcada (CurbAt).
static func kind_at(x: float, z: float) -> String:
	if z < Cfg.SEA_LEVEL:
		return "water"
	if z < Cfg.CITY_MIN_Z:
		if z > STONE_Z0 and z < STONE_Z1:
			return "stone"
		return "sand"
	if Cfg.curb_at(x, z) > 0.0:
		return "concrete"
	return "asphalt"


static func has(kind: String) -> bool:
	return DATA.has(kind)


static func _row(kind: String) -> Dictionary:
	return DATA.get(kind, DATA["asphalt"])


static func mu(kind: String) -> float:
	return float(_row(kind)["mu"])


static func slide(kind: String) -> float:
	return float(_row(kind)["slide"])


static func bounce(kind: String) -> float:
	return float(_row(kind)["bounce"])


static func hardness(kind: String) -> float:
	return float(_row(kind)["hardness"])


static func dust(kind: String) -> Color:
	return _row(kind)["dust"]


static func sound(kind: String) -> String:
	return String(_row(kind)["sound"])


# --- Consultas no mundo ------------------------------------------------------

static func mu_at(x: float, z: float) -> float:
	return mu(kind_at(x, z))


static func slide_at(x: float, z: float) -> float:
	return slide(kind_at(x, z))


static func bounce_at(x: float, z: float) -> float:
	return bounce(kind_at(x, z))


## Todas as superficies declaradas (para testes e ferramentas).
static func kinds() -> Array:
	return DATA.keys()
