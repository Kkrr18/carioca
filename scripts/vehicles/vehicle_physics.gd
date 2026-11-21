extends RefCounted
## VehiclePhysics: modelo AUTOMOTIVO do carro do jogador (B-67).
##
## Por que nao RigidBody3D + RayCast3D (o caminho classico em Godot):
## este mundo NAO tem corpos de fisica. O chao e ANALITICO (Cfg.height_at,
## Cfg.surface_at) e os predios sao retangulos checados por push_out — nao existe
## malha de colisao em setor nenhum (docs/ARQUITETURA.md). Um RigidBody3D com
## raios nas rodas cairia para sempre, e criar colisao para os 9 setores
## carregados a 512 m cada estouraria a memoria e a CPU do iPhone. Entao a mesma
## fisica e integrada sobre o chao analitico: o que muda em relacao ao
## "bicycle" antigo e o que importa para o jogador — massa, motor com curva de
## torque, cambio com marchas, transferencia de peso, limite de aderencia,
## arrasto aerodinamico e resistencia de rolamento.
##
## Tudo aqui e PURO (sem no, sem cena, sem aleatoriedade) e testado no CI:
## `step()` e o mesmo codigo que o carro roda no jogo.

const SurfaceDB = preload("res://scripts/core/surface_db.gd")

const GRAVITY := 9.81
const AIR_DENSITY := 1.225
## Trocas de marcha: acima disso sobe, abaixo desce (com histerese e espera).
const SHIFT_UP_RPM := 5900.0
const SHIFT_DOWN_RPM := 1700.0
## A aderencia por piso mora em scripts/core/surface_db.gd (B-69): o carro, os
## objetos moveis e o som leem a MESMA tabela. Aqui so se pergunta por um ponto.
## Teto de seguranca (m/s) para nenhum passo maluco jogar o carro para o infinito.
const MAX_FORWARD := 90.0
## Marcha a re: |velocidade| maxima (m/s). O pedal do freio e o mesmo da re.
const REVERSE_MAX := 7.0


# --- Veiculos ----------------------------------------------------------------

static func sedan() -> Dictionary:
	return {
		"name": "Sedan",
		"mass": 1450.0, "drive": "fwd",
		"torque": 210.0, "redline": 6500.0, "idle": 800.0,
		"gears": [3.55, 2.05, 1.40, 1.03, 0.80], "final": 3.9,
		"wheel_radius": 0.34, "wheelbase": 2.60, "track": 1.64,
		"com_height": 0.55, "spring": 35000.0, "damp": 4500.0,
		"brake": 11000.0, "rolling": 0.014,
		"cd": 0.32, "area": 2.20,
	}


static func compact() -> Dictionary:
	return {
		"name": "Compacto",
		"mass": 1100.0, "drive": "fwd",
		"torque": 155.0, "redline": 6400.0, "idle": 800.0,
		"gears": [3.60, 2.10, 1.42, 1.05, 0.82], "final": 4.1,
		"wheel_radius": 0.31, "wheelbase": 2.45, "track": 1.50,
		"com_height": 0.48, "spring": 28000.0, "damp": 3600.0,
		"brake": 9000.0, "rolling": 0.013,
		"cd": 0.31, "area": 2.00,
	}


static func suv() -> Dictionary:
	return {
		"name": "SUV",
		"mass": 2200.0, "drive": "awd",
		"torque": 350.0, "redline": 6000.0, "idle": 750.0,
		"gears": [3.80, 2.20, 1.50, 1.10, 0.85], "final": 3.7,
		"wheel_radius": 0.38, "wheelbase": 2.85, "track": 1.72,
		"com_height": 0.72, "spring": 42000.0, "damp": 5200.0,
		"brake": 13000.0, "rolling": 0.016,
		"cd": 0.38, "area": 2.75,
	}


static func specs() -> Array:
	return [compact(), sedan(), suv()]


# --- Motor -------------------------------------------------------------------

## Curva de torque: sobe do marcha lenta ate o pico (~4000 rpm) e cai ate o corte.
## Nao e uma curva de dinamometro, mas e a mesma FORMA — e a forma e o que o
## jogador sente (puxa no meio, morre no fim).
static func engine_torque(spec: Dictionary, rpm: float) -> float:
	var peak_rpm := 4000.0
	var top := maxf(1.0, float(spec["redline"]))
	var r := clampf(rpm, 0.0, top)
	if r <= peak_rpm:
		return float(spec["torque"]) * lerpf(0.55, 1.0, r / peak_rpm)
	return float(spec["torque"]) * lerpf(1.0, 0.72, (r - peak_rpm) / (top - peak_rpm))


## Rotacao do motor para uma velocidade e marcha (m/s, 1..N).
static func rpm_for(spec: Dictionary, speed: float, gear: int) -> float:
	var gears: Array = spec["gears"]
	var g := float(gears[clampi(gear - 1, 0, gears.size() - 1)])
	var wheel_rpm := absf(speed) / maxf(0.05, float(spec["wheel_radius"])) * 60.0 / TAU
	var rpm := wheel_rpm * g * float(spec["final"])
	return clampf(rpm, float(spec["idle"]), float(spec["redline"]))


## Forca nas rodas (N) para uma marcha, acelerador (0..1), rotacao e a potencia
## que o motor ainda entrega (1 = novo; cai com a avaria, ver Damage.power_scale).
static func drive_force(spec: Dictionary, gear: int, throttle: float, rpm: float,
		power: float = 1.0) -> float:
	var gears: Array = spec["gears"]
	var g := float(gears[clampi(gear - 1, 0, gears.size() - 1)])
	var torque := engine_torque(spec, rpm)
	return torque * g * float(spec["final"]) / maxf(0.05, float(spec["wheel_radius"])) \
			* clampf(throttle, 0.0, 1.0) * clampf(power, 0.0, 1.5)


## Arrasto aerodinamico (N): 1/2 rho Cd A v^2.
static func drag_force(spec: Dictionary, speed: float) -> float:
	return 0.5 * AIR_DENSITY * float(spec["cd"]) * float(spec["area"]) * speed * speed


## Aderencia do piso naquele ponto (asfalto, areia, pedra do calcadao...).
## A tabela e uma so para o jogo inteiro: scripts/core/surface_db.gd (B-69).
static func surface_mu(x: float, z: float) -> float:
	return SurfaceDB.mu_at(x, z)


# --- Carga nos pneus e aderencia ---------------------------------------------

## Carga normal em cada roda [FL, FR, RL, RR], em N, COM transferencia de peso:
## frear joga peso na frente, acelerar joga atras, curva joga no lado de fora.
## `long_accel` em m/s2 (+ acelera) e `lat_accel` (+ curva para a esquerda).
static func normal_loads(spec: Dictionary, long_accel: float, lat_accel: float) -> Array:
	var m := float(spec["mass"])
	var total := m * GRAVITY
	var dh := float(spec["com_height"])
	# Transferencia longitudinal: dF = m * a * h / entre-eixos. Acelerar joga o
	# peso para TRAS; frear (a < 0), para a FRENTE — por isso o sinal trocado.
	var d_long := clampf(m * long_accel * dh / maxf(0.5, float(spec["wheelbase"])),
			-total * 0.40, total * 0.40)
	var front := total * 0.52 - d_long
	var rear := total * 0.48 + d_long
	# Transferencia lateral: dF = m * a * h / bitola. Curva para a ESQUERDA
	# (a > 0) carrega as rodas da DIREITA: o corpo joga para o lado de fora.
	var d_lat := clampf(m * lat_accel * dh / maxf(0.5, float(spec["track"])),
			-total * 0.35, total * 0.35)
	var left := -d_lat * 0.5
	var right := d_lat * 0.5
	return [maxf(0.0, front * 0.5 + left), maxf(0.0, front * 0.5 + right),
			maxf(0.0, rear * 0.5 + left), maxf(0.0, rear * 0.5 + right)]


## Forca de um pneu limitada pelo CIRCULO DE ADERENCIA: o pneu so transmite
## mu * carga normal, somando tracao e lateral. E o que gera, de graca, o
## comportamento de ABS (freio limitado) e TCS (tracao limitada).
static func tire_force(long_want: float, lat_slip_vel: float, load: float,
		mu: float, stiffness: float) -> Vector2:
	var want := Vector2(long_want, -lat_slip_vel * stiffness)
	var cap := maxf(0.0, load) * mu
	if cap <= 0.0:
		return Vector2.ZERO
	if want.length() > cap:
		want = want.normalized() * cap
	return want


## Aderencia lateral disponivel (m/s2) para um dado piso. O limite fisico e mu*g:
## o carro nao consegue fazer curva mais fechada do que isso.
static func lateral_limit(spec: Dictionary, mu: float) -> float:
	return mu * GRAVITY


# --- Integracao longitudinal --------------------------------------------------

## Um passo de simulacao (puro). Recebe o estado e devolve o novo estado:
## {speed, gear, shift_cool, rpm, accel, slip}. `slope` em radianos (+ subida).
## Faz: motor com cambio automatico, freio com ABS, re, arrasto, rolamento,
## gravidade no declive e limite de aderencia (TCS/ABS).
static func step(spec: Dictionary, state: Dictionary, throttle: float, slope: float,
		mu: float, dt: float, power: float = 1.0) -> Dictionary:
	var speed := float(state.get("speed", 0.0))
	var gear := int(state.get("gear", 1))
	var cool := maxf(0.0, float(state.get("shift_cool", 0.0)) - dt)
	var mass := float(spec["mass"])
	var rpm := rpm_for(spec, speed, gear)
	var gears: Array = spec["gears"]
	var grip := mass * GRAVITY * mu

	var force := 0.0
	var braking := false
	if throttle > 0.0:
		if speed < 0.0:
			# Rodando de re com o pedal de frente: freia ate parar, nao inverte de
			# uma vez. A forca tem de ser POSITIVA — a velocidade e negativa, e o
			# que freia e a forca no sentido contrario ao movimento.
			braking = true
			force = minf(float(spec["brake"]) * throttle * 0.6, grip * 0.95)
		else:
			force = drive_force(spec, gear, throttle, rpm, power)
			force = minf(force, grip * 0.95)          # TCS
	elif throttle < 0.0:
		if speed > 0.0:
			braking = true
			# ABS: o freio nunca passa do que o pneu aguenta.
			force = -minf(float(spec["brake"]) * absf(throttle), grip * 0.95)
		else:
			# Re: marcha 1 com metade do acelerador. O mesmo pedal faz as duas
			# coisas (como no GTA): parado, ele engata a re.
			var rev := drive_force(spec, 1, absf(throttle) * 0.5, rpm, power) * 0.55
			force = -minf(rev, grip * 0.85)

	# Resistencias, sempre contra o movimento.
	var roll := 0.0
	if absf(speed) > 0.05:
		roll = float(spec["rolling"]) * mass * GRAVITY * signf(speed)
	var drag := drag_force(spec, speed) * signf(speed)
	# Gravidade no sentido do movimento: descida acelera, subida freia.
	var gravity_along := -mass * GRAVITY * sin(slope)

	var net := force - roll - drag + gravity_along
	var accel := net / mass
	var new_speed := speed + accel * dt
	# Freando, o carro PARA exatamente em zero (nao passa para re sozinho).
	if braking and signf(new_speed) != signf(speed):
		new_speed = 0.0
	# Rolamento e arrasto nao empurram o carro para tras sozinhos.
	if absf(speed) > 0.05 and absf(new_speed) < 0.35 and throttle == 0.0:
		new_speed = 0.0
	new_speed = clampf(new_speed, -REVERSE_MAX, MAX_FORWARD)

	# Cambio automatico: sobe perto do corte, desce se o motor cair demais.
	var now_rpm := rpm_for(spec, new_speed, gear)
	if cool <= 0.0 and throttle != 0.0:
		if now_rpm > SHIFT_UP_RPM and gear < gears.size():
			gear += 1
			cool = 0.55
		elif now_rpm < SHIFT_DOWN_RPM and gear > 1:
			gear -= 1
			cool = 0.40
	return {
		"speed": new_speed,
		"gear": gear,
		"shift_cool": cool,
		"rpm": rpm_for(spec, new_speed, gear),
		"accel": accel,
		"braking": braking,
	}
