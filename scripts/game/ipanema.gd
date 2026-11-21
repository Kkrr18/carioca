extends RefCounted
## Ipanema: ruas, bairros e pontos do bairro em coordenadas do mundo.
##
## O mundo do jogo e uma grade idealizada de 64 m (Cfg.BLOCK_SIZE), com a praia
## em z < 128 e a cidade crescendo para +Z. Aqui os nomes REAIS do bairro sao
## pregados nessa grade: rua que corre para o continente vira uma coluna em
## x = multiplo de 64; rua paralela a praia vira uma linha em z = 128 + j * 64.
## Nenhuma arte nova: e a MESMA malha de ruas do city_gen.
##
## Tudo e puro (sem no, sem GPU) para o HUD e os testes lerem sem cena.

const Cfg = preload("res://scripts/core/cfg.gd")

const BLOCK := 64.0
const BEACH_Z := 128.0
## Ate esta distancia (m) de uma linha de rua o HUD mostra o nome dela.
const LINE_TOL := 18.0

## Ruas PERPENDICULARES a praia (correm no eixo Z), do Arpoador para o Leblon.
const X_STREETS := [
	"Rua Francisco Otaviano",
	"Rua Joana Angelica",
	"Rua Jangadeiros",
	"Rua Teixeira de Melo",
	"Rua Farme de Amoedo",
	"Rua Garcia d'Avila",
	"Rua Anibal de Mendonca",
	"Rua Nascimento Silva",
	"Rua Paul Redfern",
	"Rua Demetrio Ribeiro",
	"Rua Cupertino Durao",
	"Rua Barao de Jaguaribe",
]

## Ruas PARALELAS a praia (correm no eixo X), do mar para o continente.
const Z_STREETS := [
	"Avenida Vieira Souto",
	"Rua Prudente de Morais",
	"Rua Visconde de Piraja",
	"Rua Rita Ludolf",
	"Rua Aristides Espinola",
	"Rua Barao da Torre",
]

## Pontos do bairro. "at" e Vector2(x, z) em metros; a altura do chao vem de
## Cfg.surface_at na hora de usar (o terreno muda e nao vale congelar o y).
const PLACES := {
	"posto9": {"name": "Posto 9", "at": Vector2(1632.0, 96.0)},
	"farme": {"name": "Farme de Amoedo", "at": Vector2(1728.0, 288.0)},
	"galeria": {"name": "Galeria de Ipanema", "at": Vector2(1984.0, 640.0)},
	"osorio": {"name": "Praca General Osorio", "at": Vector2(1856.0, 512.0)},
	"arpoador": {"name": "Arpoador", "at": Vector2(2560.0, 224.0)},
	"lagoa": {"name": "Lagoa Rodrigo de Freitas", "at": Vector2(2112.0, 1472.0)},
	"delegacia": {"name": "Delegacia de Ipanema", "at": Vector2(1472.0, 448.0)},
	"hospital": {"name": "Hospital de Ipanema", "at": Vector2(1632.0, 832.0)},
	"garagem": {"name": "Garagem", "at": Vector2(1600.0, 96.0)},
}


## Nome do bairro em (x, z). E o texto que aparece ao cruzar uma fronteira.
static func district_at(x: float, z: float) -> String:
	if z < BEACH_Z:
		return "Praia de Ipanema"
	if x >= 2432.0 and z < 520.0:
		return "Arpoador"
	if z >= 1216.0:
		return "Lagoa Rodrigo de Freitas"
	if z >= 832.0:
		return "Ipanema - Jardim de Alah"
	return "Ipanema"


## Nome da rua mais proxima de (x, z), ou "" no meio da quadra. A escolha e
## pela linha MAIS PROXIMA, como o GTA faz: o HUD nunca fica sem referencia.
static func street_at(x: float, z: float) -> String:
	var best := ""
	var best_d := LINE_TOL
	var ix := int(round(x / BLOCK))
	var dx := absf(x - float(ix) * BLOCK)
	if dx < best_d:
		best_d = dx
		best = String(X_STREETS[posmod(ix, X_STREETS.size())])
	var iz := int(round((z - BEACH_Z) / BLOCK))
	var dz := absf(z - (BEACH_Z + float(iz) * BLOCK))
	if dz < best_d:
		best = String(Z_STREETS[posmod(iz, Z_STREETS.size())])
	return best


## Texto de localizacao do HUD: "Ipanema / Rua Farme de Amoedo". Duas linhas
## num texto so para o HUD nao ter de decidir nada.
static func location_line(x: float, z: float) -> String:
	var street := street_at(x, z)
	if street.is_empty():
		return district_at(x, z)
	return "%s\n%s" % [district_at(x, z), street]


## Posicao no mundo de um ponto do bairro (y no chao analitico). Chave
## desconhecida devolve Vector3.ZERO.
static func place(key: String) -> Vector3:
	if not PLACES.has(key):
		return Vector3.ZERO
	var at: Vector2 = PLACES[key]["at"]
	return Vector3(at.x, Cfg.surface_at(at.x, at.y), at.y)


static func place_name(key: String) -> String:
	if not PLACES.has(key):
		return key
	return String(PLACES[key]["name"])


## Chave do ponto mais proximo de uma posicao (para o HUD saber "voce chegou").
static func nearest_place(pos: Vector3) -> String:
	var best := ""
	var best_d := 1.0e30
	for key in PLACES.keys():
		var at: Vector2 = PLACES[key]["at"]
		var d := Vector2(pos.x - at.x, pos.z - at.y).length()
		if d < best_d:
			best_d = d
			best = String(key)
	return best
