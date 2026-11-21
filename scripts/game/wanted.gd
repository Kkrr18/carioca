extends RefCounted
## Wanted: nivel de procurado (as "estrelas") — logica PURA, sem cena.
##
## O calor e continuo e medido em ESTRELAS: `stars()` arredonda para cima, entao
## o primeiro crime (calor 1,0) ja acende uma estrela e 2,4 acende tres. Com a
## policia fora de vista o calor cai; quando chega a zero, a cidade esquece.
##
## Nada aqui toca a arvore de cena nem a GPU: e a parte do sistema que o jogador
## sente como "justa" ou nao, e por isso ela e testada no CI.

const MAX_STARS := 5
const MAX_COPS := 5

## Calor de cada crime. A chave e o nome usado por police.report_crime().
const CRIMES := {
	"agressao": 0.8,
	"carro_tomado": 1.0,
	"atropelamento": 1.2,
	"tiro": 1.4,
	"policial_ferido": 2.2,
	"policial_morto": 1.6,
}

## Quanto de calor sai por segundo: com uma estrela a cidade esfria rapido
## (~12 s); com cinco, devagar (~33 s por estrela) — o cerco aperta.
const DECAY_FAST := 0.085
const DECAY_SLOW := 0.030


static func crime_heat(name: String) -> float:
	return float(CRIMES.get(name, 1.0))


## Estrelas acesas para um calor. Sempre para CIMA: 0,1 de calor ja e uma
## estrela (senao o crime "nao aparece" e o jogador nao entende o porque).
static func stars(heat: float) -> int:
	return clampi(int(ceil(maxf(0.0, heat))), 0, MAX_STARS)


static func add(heat: float, crime: String) -> float:
	return clampf(maxf(0.0, heat) + crime_heat(crime), 0.0, float(MAX_STARS))


## Velocidade de esfriamento (calor por segundo) para o nivel atual.
static func decay_rate(star_count: int) -> float:
	var k := float(clampi(star_count, 1, MAX_STARS) - 1) / float(MAX_STARS - 1)
	return lerpf(DECAY_FAST, DECAY_SLOW, k)


## Um passo do resfriamento. `seen` = a policia esta vendo o jogador: nesse
## caso o calor NAO cai (e o que faz a fuga valer a pena).
static func decay(heat: float, dt: float, seen: bool) -> float:
	if seen or heat <= 0.0:
		return maxf(0.0, heat)
	return maxf(0.0, heat - decay_rate(stars(heat)) * dt)


static func cop_count(star_count: int) -> int:
	return clampi(star_count, 0, MAX_COPS)


## Velocidade de perseguicao (m/s). Com uma estrela a viatura acompanha; com
## cinco ela e mais rapida que o carro do jogador e a fuga vira manobra.
static func cop_speed(star_count: int) -> float:
	var k := float(clampi(star_count, 1, MAX_STARS) - 1) / float(MAX_STARS - 1)
	return lerpf(19.0, 31.0, k)


static func cop_damage(star_count: int) -> float:
	return 3.5 + 1.3 * float(clampi(star_count, 1, MAX_STARS))


static func cop_health(_star_count: int) -> float:
	return 100.0


static func arrest_radius() -> float:
	return 9.0


static func arrest_seconds() -> float:
	return 2.5


## Multa ao ser preso: 20% do dinheiro. Nunca negativa.
static func busted_fine(money: int) -> int:
	return maxi(0, int(float(money) * 0.20))


static func wanted_line(star_count: int) -> String:
	if star_count <= 0:
		return ""
	if star_count >= MAX_STARS:
		return "PROCURADO EM TODO O RIO"
	return "PROCURADO: %d %s" % [star_count, "estrela" if star_count == 1 else "estrelas"]
