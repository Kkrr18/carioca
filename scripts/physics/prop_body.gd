extends RefCounted
## PropBody: um objeto MOVEL do mundo (caixa, cadeira, lixeira, cone, destroco).
##
## Por que nao RigidBody3D: este mundo nao tem malha de colisao no chao (o chao e
## analitico: Cfg.height_at/surface_at) e criar corpo fisico para 9 setores de
## 512 m nao cabe no iPhone 12. Entao cada objeto e um estado PURO (dicionario)
## integrado por estas funcoes: gravidade, contato com o chao analitico,
## restituicao (quica), atrito/deslizamento por superficie, giro ao ser jogado,
## empurrao por impulso e SONO automatico quando para. E a mesma fisica de
## verdade, com as mesmas grandezas (massa, impulso, atrito, restituicao), so
## que resolvida em 30 linhas em vez de um solver generico.
##
## Estado (Dictionary, mutado no lugar por performance):
##   kind, mat, mass, size, mesh, color, pos, vel, yaw, spin, hp, max_hp,
##   state, rest, sleep_t, life, alive, radius, hit_cool, lod_acc
##
## Tudo puro: sem no, sem cena, sem aleatoriedade. Testado no CI.

const Cfg = preload("res://scripts/core/cfg.gd")
const Damage = preload("res://scripts/physics/damage.gd")

const GRAVITY := 9.81
const MAX_SPEED := 40.0
## Abaixo disso (m/s) e no chao, o objeto esta "parado" e comeca a contar o sono.
const SLEEP_SPEED := 0.12
const SLEEP_TIME := 0.45
## Velocidade vertical minima para valer como quique (senao ele "morre" no chao).
const BOUNCE_MIN := 0.9
## Arrasto do ar: leve, so para nada deslizar eternamente.
const AIR_DAMP := 0.30

## Tipos que existem hoje na rua. `mesh` = qual MultiMesh desenha (3 no total).
const KINDS := {
	"caixa": {"mass": 14.0, "size": Vector3(0.60, 0.50, 0.60), "mat": "wood",
			"mesh": "box", "color": Color(0.62, 0.47, 0.30)},
	"cadeira": {"mass": 6.0, "size": Vector3(0.50, 0.90, 0.50), "mat": "wood",
			"mesh": "box", "color": Color(0.45, 0.33, 0.22)},
	"lixeira": {"mass": 22.0, "size": Vector3(0.55, 1.00, 0.55), "mat": "metal",
			"mesh": "cyl", "color": Color(0.22, 0.34, 0.27)},
	"cone": {"mass": 3.0, "size": Vector3(0.40, 0.60, 0.40), "mat": "plastic",
			"mesh": "cone", "color": Color(0.92, 0.42, 0.16)},
	"destroco": {"mass": 2.0, "size": Vector3(0.26, 0.18, 0.26), "mat": "wood",
			"mesh": "box", "color": Color(0.48, 0.40, 0.30)},
}


static func kinds() -> Array:
	return KINDS.keys()


static func kit(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["caixa"])


static func half_height(kind: String) -> float:
	var size: Vector3 = kit(kind)["size"]
	return size.y * 0.5


## Cria o estado de um objeto do tipo pedido, apoiado em `pos` (posicao do
## CENTRO do objeto, ja com meia altura, quem chama que ponha no chao).
static func make(kind: String, pos: Vector3, yaw: float) -> Dictionary:
	var k := kit(kind)
	var mat := String(k["mat"])
	var hp := Damage.resistance(mat)
	var size: Vector3 = k["size"]
	return {
		"kind": kind, "mat": mat, "mass": float(k["mass"]), "size": size,
		"mesh": String(k["mesh"]), "color": k["color"],
		"pos": pos, "vel": Vector3.ZERO, "yaw": yaw, "spin": 0.0,
		"hp": hp, "max_hp": hp, "state": Damage.INTACT,
		"rest": false, "sleep_t": 0.0, "life": -1.0, "alive": true,
		"radius": Vector2(size.x, size.z).length() * 0.5,
		"hit_cool": 0.0, "lod_acc": 0.0,
	}


## Coloca o objeto apoiado no chao (y do centro = chao + meia altura).
static func place_on_ground(b: Dictionary, ground: float) -> void:
	var pos: Vector3 = b["pos"]
	pos.y = ground + half_height(String(b["kind"]))
	b["pos"] = pos
	b["vel"] = Vector3.ZERO


## Um passo de fisica. `ground` = altura do chao analitico embaixo dele e
## `mu`/`bounce` vem do SurfaceDB daquele ponto.
static func step(b: Dictionary, dt: float, ground: float, mu: float, bounce: float) -> void:
	if dt <= 0.0 or not bool(b["alive"]):
		return
	if bool(b["rest"]):
		return
	var kind := String(b["kind"])
	var half := half_height(kind)
	var pos: Vector3 = b["pos"]
	var vel: Vector3 = b["vel"]

	# Gravidade (a mesma do resto do jogo) e arrasto do ar.
	vel.y -= GRAVITY * dt
	var damp := clampf(1.0 - AIR_DAMP * dt, 0.0, 1.0)
	vel.x *= damp
	vel.z *= damp
	pos += vel * dt

	# Chao analitico: quando o fundo do objeto encosta, ele para, quica ou desliza.
	if pos.y - half < ground:
		pos.y = ground + half
		if absf(vel.y) > BOUNCE_MIN:
			vel.y = -vel.y * bounce
		else:
			vel.y = 0.0
		# Atrito do piso: come velocidade horizontal a mu*g por segundo.
		var flat := Vector2(vel.x, vel.z)
		var sp := flat.length()
		if sp > 0.0:
			var after := maxf(0.0, sp - mu * GRAVITY * dt)
			flat = flat * (after / sp)
			vel.x = flat.x
			vel.z = flat.y
		# O giro tambem morre no chao.
		b["spin"] = float(b["spin"]) * clampf(1.0 - (0.6 + mu) * dt, 0.0, 1.0)

	vel = vel.limit_length(MAX_SPEED)
	b["vel"] = vel
	b["pos"] = pos
	if absf(float(b["spin"])) > 0.01:
		b["yaw"] = wrapf(float(b["yaw"]) + float(b["spin"]) * dt, -PI, PI)

	# SONO: parado no chao por SLEEP_TIME, congela (economia no iPhone). Acorda
	# no primeiro impulso (impulse()) ou se o chao sumir debaixo dele (wake()).
	var on_ground := pos.y - half < ground + 0.03
	if on_ground and vel.length() < SLEEP_SPEED:
		b["sleep_t"] = float(b["sleep_t"]) + dt
		if float(b["sleep_t"]) >= SLEEP_TIME:
			b["rest"] = true
			b["vel"] = Vector3.ZERO
			b["spin"] = 0.0
	else:
		b["sleep_t"] = 0.0


## Acorda o objeto (o chao mudou ou alguem encostou).
static func wake(b: Dictionary) -> void:
	b["rest"] = false
	b["sleep_t"] = 0.0


## Impulso (N.s) no centro do objeto. `power` dividido pela massa vira a
## variacao de velocidade — e o que faz uma caixa leve voar e uma lixeira pesada
## so andar um pouco com o mesmo empurrao.
static func impulse(b: Dictionary, dir: Vector3, power: float) -> void:
	if not bool(b["alive"]) or power <= 0.0:
		return
	var mass := maxf(1.0, float(b["mass"]))
	var dv := dir.normalized() * (power / mass)
	var vel: Vector3 = b["vel"]
	vel += dv
	# Um objeto atingido de lado sobe um pouco (senao ele "desliza" no chao).
	vel.y = maxf(vel.y, minf(2.6, dv.length() * 0.35))
	b["vel"] = vel
	wake(b)
	# Tomba no sentido do empurrao.
	var side := signf(dir.x) if absf(dir.x) > 0.2 else signf(dir.z)
	b["spin"] = clampf(float(b["spin"]) + dv.length() * 1.2 * side, -12.0, 12.0)


## Aplica dano de um impacto. Devolve o estado novo (Damage.INTACT/DAMAGED/...).
## Quem chama cuida de virar destrocos quando o estado e DESTROYED.
static func apply_damage(b: Dictionary, power: float) -> int:
	var pair := Damage.hit(float(b["hp"]), float(b["max_hp"]), power)
	b["hp"] = float(pair[0])
	b["state"] = int(pair[1])
	if int(b["state"]) == Damage.DESTROYED:
		b["alive"] = false
	return int(b["state"])
