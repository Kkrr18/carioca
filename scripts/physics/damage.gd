extends RefCounted
## Damage: estados de dano e resistencia dos materiais (B-69), puro e testado.
##
## Tres estados, como pede a especificacao: INTACTO -> DANIFICADO -> DESTRUIDO.
## A "vida" de um objeto e um numero de resistencia em N.s: cada impacto tira um
## tanto e o estado sai da fracao que sobrou. A resistencia vem do MATERIAL, nao
## do tipo do objeto — uma lixeira de metal aguenta o que uma caixa de madeira
## nao aguenta, e um vidro quebra com um encostao.
##
## Por que nao simular fragmentos de verdade em tudo: 9 setores de cidade com
## fisica de detrito estoura o iPhone 12. Aqui o objeto passa por 3 estados e o
## destroidor vira um numero LIMITADO de fragmentos (DebrisManager/pooling no
## prop_field). Predio nao entra: estrutura grande teria de ser outro sistema
## (dano estrutural por seccao, ver docs/FISICA.md).

const INTACT := 0
const DAMAGED := 1
const DESTROYED := 2

## Resistencia (N.s absorvidos) por material. Calibracao: um carro de 1450 kg a
## 10 m/s gera hit_power() ~ 9.000, entao a 10 m/s ele quebra madeira/plastico/
## vidro, AMASSA metal e nao move pedra/concreto.
const RESIST := {
	"glass": 400.0,
	"plastic": 900.0,
	"wood": 2200.0,
	"metal": 9000.0,
	"stone": 22000.0,
	"concrete": 45000.0,
}

## Fragmentos por material ao ser destruido (o prop_field corta pelo teto).
const DEBRIS := {
	"glass": 6,
	"plastic": 4,
	"wood": 3,
	"metal": 3,
	"stone": 2,
	"concrete": 2,
}

## Avaria do carro: fracao 0..1 (0 = novo, 1 = destruido).
const CAR_DAMAGED := 0.35
const CAR_WRECKED := 0.75


static func resistance(material: String) -> float:
	return float(RESIST.get(material, 2200.0))


static func state_for(hp: float, max_hp: float) -> int:
	var f := hp / maxf(1.0, max_hp)
	if f <= 0.0:
		return DESTROYED
	if f < 0.5:
		return DAMAGED
	return INTACT


## Estado a partir da fracao de dano recebida (0 = intacto, 1 = destruido).
static func state_from_damage(damage: float) -> int:
	if damage >= CAR_WRECKED:
		return DESTROYED
	if damage >= CAR_DAMAGED:
		return DAMAGED
	return INTACT


## Impulso efetivo (N.s) de um corpo de `mass` kg a `speed` m/s contra um objeto.
## O 0,62 e calibracao das resistencias acima; nao e o impulso exato de uma
## colisao elastica (que precisaria da massa do alvo e do coeficiente).
static func hit_power(mass: float, speed: float) -> float:
	return mass * absf(speed) * 0.62


## Aplica um impacto na vida do objeto e devolve o novo estado.
## `hp` e mutavel por referencia no dicionario do objeto (prop_body.gd).
static func hit(hp: float, max_hp: float, power: float) -> Array:
	var new_hp := maxf(0.0, hp - maxf(0.0, power))
	return [new_hp, state_for(new_hp, max_hp)]


static func debris_count(material: String) -> int:
	return int(DEBRIS.get(material, 2))


## Potencia que sobra no motor do carro com a avaria atual (1.0 = zero de dano).
## Avaria tambem puxa o volante para um lado (car.gd), como roda torta de verdade.
static func power_scale(damage: float) -> float:
	return 1.0 - 0.45 * clampf(damage, 0.0, 1.0)


## Quanto a carroceria escurece/amassa por dano (0 = cor original).
static func dent(damage: float) -> float:
	return clampf(damage * 0.55, 0.0, 0.55)


static func label(state: int) -> String:
	match state:
		DAMAGED:
			return "danificado"
		DESTROYED:
			return "destruido"
		_:
			return "intacto"
