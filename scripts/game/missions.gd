extends RefCounted
## Missions: roteiro das missoes de Ipanema — dados e regras PURAS.
##
## Uma missao e uma lista de passos. Cada passo e um dicionario:
##   kind    "goto" | "say" | "wait" | "survive"
##   to      chave de Ipanema.PLACES (so em "goto")
##   text    frase do objetivo, mostrada no HUD
##   who     quem fala (so em "say")
##   secs    duracao em segundos ("say", "wait", "survive")
##   radius  raio de chegada em metros ("goto")
##   stars   calor a acender quando o passo COMECA (polícia entra em cena)
##
## A cena (mission_runner.gd) so executa o roteiro; nenhuma regra mora la.
## Tudo aqui e deterministico e testado no CI sem abrir janela.

const Cfg = preload("res://scripts/core/cfg.gd")
const Ipanema = preload("res://scripts/game/ipanema.gd")

const DEFAULT_RADIUS := 18.0
const DEFAULT_SECS := 3.0

const LIST := [
	{
		"id": "orla04",
		"title": "ORLA 04",
		"giver": "Betinho",
		"start": "posto9",
		"brief": "Levar o carro ate o Arpoador.",
		"steps": [
			{"kind": "say", "who": "Betinho", "secs": 4.0,
				"text": "Pega o carro e leva pro Arpoador. Sem freiada brusca."},
			{"kind": "goto", "to": "arpoador", "radius": 22.0,
				"text": "Leve o carro ate o Arpoador"},
			{"kind": "say", "who": "Betinho", "secs": 3.5,
				"text": "Boa. O dinheiro cai na conta."},
		],
		"reward": 500,
	},
	{
		"id": "encomenda",
		"title": "A ENCOMENDA",
		"giver": "Dona Zilda",
		"start": "farme",
		"brief": "Buscar a caixa e entregar no Osorio.",
		"steps": [
			{"kind": "say", "who": "Dona Zilda", "secs": 4.0,
				"text": "Pega a caixa na Garcia d'Avila. E nao abre."},
			{"kind": "goto", "to": "galeria", "radius": 16.0,
				"text": "Pegue a caixa na galeria"},
			{"kind": "say", "who": "Aviso", "secs": 3.5, "stars": 1.0,
				"text": "A policia viu a caixa. Corre pro Osorio!"},
			{"kind": "goto", "to": "osorio", "radius": 20.0,
				"text": "Entregue a caixa no General Osorio"},
		],
		"reward": 900,
	},
	{
		"id": "lagoa",
		"title": "FUGA NA LAGOA",
		"giver": "Betinho",
		"start": "garagem",
		"brief": "Despistar a policia e voltar para a orla.",
		"steps": [
			{"kind": "say", "who": "Betinho", "secs": 3.5,
				"text": "A encomenda era falsa. Ja tinha viatura na minha porta."},
			{"kind": "goto", "to": "lagoa", "radius": 26.0, "stars": 2.0,
				"text": "Va para a Lagoa e despiste a policia"},
			{"kind": "survive", "secs": 22.0,
				"text": "Sobreviva ate a policia perder voce"},
			{"kind": "goto", "to": "posto9", "radius": 22.0,
				"text": "Volte para o Posto 9"},
		],
		"reward": 1500,
	},
	{
		"id": "carga",
		"title": "O CARGA",
		"giver": "Dona Zilda",
		"start": "arpoador",
		"brief": "Abrir caminho ate a galeria e sair limpo.",
		"steps": [
			{"kind": "say", "who": "Dona Zilda", "secs": 4.0,
				"text": "Tomaram a galeria. Vai la, mas nao vai sozinho."},
			{"kind": "goto", "to": "galeria", "radius": 20.0, "stars": 2.0,
				"text": "Chegue na galeria da Garcia d'Avila"},
			{"kind": "survive", "secs": 30.0,
				"text": "Aguente o cerco ate eles cansarem"},
			{"kind": "goto", "to": "delegacia", "radius": 20.0,
				"text": "Termine o servico na delegacia"},
		],
		"reward": 2500,
	},
]


static func count() -> int:
	return LIST.size()


## Missao pelo indice, com volta ao comeco (o jogo nao acaba: a rua continua).
static func mission_at(index: int) -> Dictionary:
	if LIST.is_empty():
		return {}
	return LIST[posmod(index, count())]


static func step_count(mission: Dictionary) -> int:
	var steps: Array = mission.get("steps", [])
	return steps.size()


static func step_at(mission: Dictionary, index: int) -> Dictionary:
	var steps: Array = mission.get("steps", [])
	if index < 0 or index >= steps.size():
		return {}
	return steps[index]


static func step_kind(step: Dictionary) -> String:
	return String(step.get("kind", "goto"))


static func step_text(step: Dictionary) -> String:
	return String(step.get("text", ""))


static func step_seconds(step: Dictionary) -> float:
	return maxf(0.1, float(step.get("secs", DEFAULT_SECS)))


static func step_radius(step: Dictionary) -> float:
	return maxf(2.0, float(step.get("radius", DEFAULT_RADIUS)))


static func step_heat(step: Dictionary) -> float:
	return maxf(0.0, float(step.get("stars", 0.0)))


## Tem ponto no mundo este passo? ("goto" tem; "say"/"wait" nao)
static func has_target(step: Dictionary) -> bool:
	return step_kind(step) == "goto" and step.has("to")


static func step_pos(step: Dictionary) -> Vector3:
	return Ipanema.place(String(step.get("to", "")))


## Onde fica o marcador que INICIA a missao (a "letra" no mapa).
static func giver_pos(mission: Dictionary) -> Vector3:
	return Ipanema.place(String(mission.get("start", "")))


static func reward_of(mission: Dictionary) -> int:
	return int(mission.get("reward", 0))


static func title_of(mission: Dictionary) -> String:
	return String(mission.get("title", ""))


static func giver_of(mission: Dictionary) -> String:
	return String(mission.get("giver", ""))


## Texto do objetivo no HUD. Passo sem texto herda o titulo da missao.
static func objective_text(mission: Dictionary, index: int) -> String:
	var step := step_at(mission, index)
	var t := step_text(step)
	if t.is_empty():
		return title_of(mission)
	return t
