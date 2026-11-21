extends Node3D
## Car: veiculo dirigivel do jogador — fisica automotiva (B-67).
##
## - FISICA DE VERDADE sobre o chao ANALITICO: `vehicle_physics.gd` (puro) cuida
##   de massa, motor com curva de torque, cambio automatico de 5 marchas, freio
##   com ABS, tracao limitada (TCS), arrasto aerodinamico, resistencia de
##   rolamento, gravidade no declive e aderencia por piso (asfalto/areia/pedra).
## - Nada de RigidBody3D: este mundo NAO tem corpos de fisica (o chao e
##   Cfg.height_at/surface_at e os predios sao retangulos consultados por
##   push_out). RigidBody3D com raios nas rodas cairia no vazio, e criar colisao
##   para os setores de 512 m estouraria o iPhone. Ver docs/ARQUITETURA.md.
## - Guinada pelo modelo "bicycle", mas LIMITADA pela aderencia lateral
##   (mu*g): pedir curva demais em alta velocidade faz o carro SUBESTERAR em vez
##   de girar no proprio eixo.
## - Carroceria inclina com o relevo E com a transferencia de peso: mergulha ao
##   frear, levanta ao acelerar e rola para fora na curva.
## - Entrar/sair: botao CARRO do HUD quando perto do veiculo (ou tecla E no
##   desktop). Ao entrar, a fisica do jogador desliga e a camera do carro
##   assume; ao sair, o jogador volta do lado direito do carro.
## - Animacao: rodas giram com a velocidade, as dianteiras estercam com o
##   volante, farois e lanternas emissivos (acendem a noite junto do ciclo).
## - O trafego (traffic.gd) continua CINEMATICO de proposito: 12 carros com
##   fisica completa nao cabem no iPhone. A fisica e do carro do jogador.

## Emitido quando o carro bate em outro veiculo (o main liga ao som e ao HUD).
signal crashed(strength: float)

const Cfg = preload("res://scripts/core/cfg.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")
const VehiclePhysics = preload("res://scripts/vehicles/vehicle_physics.gd")
const MODEL_LENGTH := 4.3      # comprimento do sedan CC0 (m); frente em -Z

# Motor, freio, cambio e aderencia saíram daqui para vehicle_physics.gd (B-67).
# MAX_SPEED fica porque normaliza a forca da batida no HUD e no som.
const MAX_SPEED := 22.0        # ~80 km/h: referencia de "batida forte"
const WHEELBASE := 2.6         # distancia entre eixos (m), igual ao preset sedan
const STEER_MAX := 0.75        # rad de esterco maximo, parado (~43 graus)
const STEER_SPEED := 4.5       # resposta do volante (rad/s)
const STEER_DROP := 0.40       # quanto o esterco maximo cai com a velocidade
## A roda DESENHADA nao passa daqui (34 graus): acima disso ela entra no para-lama.
## O volante da fisica vira mais que isso, o desenho nao precisa.
const VISUAL_STEER := 0.60
const WHEEL_RADIUS := 0.34
# Distancia (m) para o prompt ENTRAR aparecer. Era 3,5 m: no iPhone o jogador
# nao achava o carro e nao conseguia entrar (B-36).
const PROXIMITY := 12.0
const COLLIDE_RADIUS := 1.5    # raio do carro para colisao com o transito (m)

var speed := 0.0               # m/s assinada (+ frente, - re)
var steer := 0.0               # rad assinado
var occupied := false
## Configuracao do veiculo (vehicle_physics.gd). Vazio = sedan.
var vehicle_spec: Dictionary = {}
var gear := 1
var rpm := 800.0
## Rotacao normalizada (0 = marcha lenta, 1 = corte): e o que o som do motor usa
## para a troca de marcha ser AUDIVEL (B-67).
var engine_ratio := 0.0
## 0 = pneu agarrado, 1 = derrapando (a curva pedida passou de mu*g).
var slip := 0.0
var accel_long := 0.0
var accel_lat := 0.0
# Estado interno da fisica longitudinal (velocidade, marcha e espera de troca).
var _st: Dictionary = {"speed": 0.0, "gear": 1, "shift_cool": 0.0}
# Entrada do ultimo quadro, somente para a telemetria do HUD: e por ela que se
# ve, no aparelho, se o carro nao anda por falta de toque ou por outra coisa.
var input_throttle := 0.0
var input_steer := 0.0
var player = null              # main conecta; usado para entrar/sair
var streamer = null
var traffic = null             # main conecta; colisao com os carros de transito
var hit_flash := 0.0           # tempo desde a ultima batida (HUD/som)
var _crash_cool := 0.0         # evita som/tremor repetido enquanto encostado

## Modelo CC0 do carro (sedan). Vazio = so a caixa de codigo.
var model_path := ""
var model_loaded := false
# {node: PIVO proprio da roda, front: bool, radius: float}. O giro acontece no
# pivo (no centro da roda), nao no no do .glb (B-39).
var _model_wheels: Array = []
var _spin_radius := WHEEL_RADIUS

var camera: Camera3D
var _camera_rig: Node3D
var _marker: Node3D
var _wheels: Array[Node3D] = []
var _front_pivots: Array[Node3D] = []
var _spin := 0.0
var _e_latch := false


# --- Nucleo puro (sem cena; testado em tests/runner.gd) ----------------------

## Configuracao efetiva do veiculo (sedan quando nada foi definido).
func spec() -> Dictionary:
	if vehicle_spec.is_empty():
		return VehiclePhysics.sedan()
	return vehicle_spec


## Esterco maximo util: em alta velocidade o volante fica mais curto, senao o
## carro gira no proprio eixo a 80 km/h. Abaixo de ~10 m/s quem manda e este
## limite; acima disso quem limita e a aderencia (mu*g), entao o curso maior do
## volante aparece nas manobras (vira, estaciona, sai da areia) sem deixar o
## carro nervoso na avenida.
static func steer_limit(speed: float) -> float:
	return STEER_MAX / (1.0 + STEER_DROP * absf(speed) / 10.0)


## Modelo bicycle: taxa de guinada = v / L * tan(esterco). Em re (v < 0) o
## giro inverte, como num carro de verdade.
static func yaw_rate(speed: float, steer: float) -> float:
	return speed / WHEELBASE * tan(steer)


# --- Cena ---------------------------------------------------------------------

func _ready() -> void:
	# O main posiciona o carro antes do add_child; aqui ele encosta no chao
	# analitico para nao nascer flutuando nem enterrado.
	position.y = Cfg.surface_at(position.x, position.z)
	# Modelo CC0 quando carrega; a caixa de codigo e a reserva se nao carregar.
	if not model_path.is_empty():
		_build_model()
	if not model_loaded:
		_build_body()
		_build_wheels()
	_build_camera()
	_build_marker()
	set_physics_process(true)


func _build_body() -> void:
	# Mesma paleta dos carros estacionados (PropFactory); a Fase 4 sorteara
	# cores deterministicas quando houver varios veiculos.
	var hue := 0.5
	var body := StandardMaterial3D.new()
	body.albedo_color = PropFactory.color_for("carro", hue)
	body.roughness = 0.55
	body.metallic_specular = 0.4
	var glass := StandardMaterial3D.new()
	glass.albedo_color = PropFactory.color_for("carro_top", hue)
	glass.roughness = 0.2
	glass.metallic_specular = 0.6

	var chassis := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.1, 4.2)
	chassis.mesh = box
	chassis.material_override = body
	chassis.position = Vector3(0.0, WHEEL_RADIUS + 0.55, 0.0)
	add_child(chassis)

	var cabin := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(1.6, 0.62, 2.1)
	cabin.mesh = cbox
	cabin.material_override = glass
	cabin.position = Vector3(0.0, WHEEL_RADIUS + 1.41, -0.2)
	add_child(cabin)

	# Farois e lanternas emissivos (barato: sem SpotLight3D nesta fase).
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.9, 0.88, 0.7)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.93, 0.72)
	lamp.emission_energy_multiplier = 1.6
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.6, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(0.9, 0.1, 0.08)
	tail.emission_energy_multiplier = 1.2
	for side in [-1.0, 1.0]:
		var head := MeshInstance3D.new()
		var hbox := BoxMesh.new()
		hbox.size = Vector3(0.3, 0.16, 0.1)
		head.mesh = hbox
		head.material_override = lamp
		head.position = Vector3(0.55 * side, WHEEL_RADIUS + 0.6, -2.12)
		add_child(head)
		var tl := MeshInstance3D.new()
		var tbox := BoxMesh.new()
		tbox.size = Vector3(0.3, 0.12, 0.1)
		tl.mesh = tbox
		tl.material_override = tail
		tl.position = Vector3(0.55 * side, WHEEL_RADIUS + 0.6, 2.12)
		add_child(tl)


func _build_wheels() -> void:
	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color(0.08, 0.08, 0.09)
	tyre.roughness = 0.9
	var mesh := CylinderMesh.new()
	mesh.height = 0.26
	mesh.top_radius = WHEEL_RADIUS
	mesh.bottom_radius = WHEEL_RADIUS
	mesh.radial_segments = 12
	for pos in [
		Vector3(-0.82, WHEEL_RADIUS, -1.3),
		Vector3(0.82, WHEEL_RADIUS, -1.3),
		Vector3(-0.82, WHEEL_RADIUS, 1.3),
		Vector3(0.82, WHEEL_RADIUS, 1.3),
	]:
		var pivot := Node3D.new()
		pivot.position = pos
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = tyre
		# O cilindro nasce com o eixo em Y; girando o mesh em Z o eixo fica em X.
		# No pivote (ordem YXZ): rotation.y = esterco, rotation.x = giro da roda.
		mi.rotation.z = PI * 0.5
		pivot.add_child(mi)
		add_child(pivot)
		_wheels.append(pivot)
		if pos.z < 0.0:
			_front_pivots.append(pivot)


## Carrega o .glb do carro e guarda as rodas. Se nao carregar, o no volta
## a vazio e a caixa de codigo assume.
func _build_model() -> void:
	var mp := ModelProp.new()
	mp.model_path = model_path
	mp.target_length = MODEL_LENGTH
	add_child(mp)
	mp.load_model()
	if not mp.loaded:
		remove_child(mp)
		mp.free()
		return
	model_loaded = true
	_model_wheels.clear()
	var radii: Array[float] = []
	for w in mp.wheel_info:
		var node := w["node"] as Node3D
		if node == null:
			continue
		# Posicao e tamanho da roda no espaco do CARRO. Isto tem que ser lido
		# ANTES de mexer na arvore: o modelo vem escalado e girado pelo
		# ModelProp.
		var in_car: Transform3D = ModelProp.rel_xf(node, self)
		var box: AABB = ModelProp.mesh_aabb(node)
		var center: Vector3 = in_car * box.get_center()
		var sc: float = in_car.basis.get_scale().y
		var radius: float = maxf(0.05, 0.5 * maxf(box.size.y, box.size.z) * sc)
		# Pivo novo NO CENTRO DA RODA. No .glb (obj2gltf) o no da roda tem a
		# origem no centro do modelo, entao girar o no faz a roda ORBITAR o
		# carro em vez de rodar em torno do proprio eixo (B-39).
		var pivot := Node3D.new()
		pivot.name = "WheelPivot"
		pivot.position = center
		add_child(pivot)
		var parent := node.get_parent()
		if parent != null:
			# Sem soltar o owner, o Godot avisa "owner ... inconsistent" a cada
			# roda movida, e esse aviso aparece no painel de console do iPhone.
			node.owner = null
			parent.remove_child(node)
		pivot.add_child(node)
		node.transform = wheel_in_pivot(in_car, center)
		_model_wheels.append({
			"node": pivot,
			"front": bool(w["front"]),
			"radius": radius,
		})
		radii.append(radius)
	if not radii.is_empty():
		var sum := 0.0
		for r in radii:
			sum += r
		# Raio do proprio modelo: a velocidade angular tem que bater com a roda
		# desenhada, senao ela "derrapa" visualmente.
		_spin_radius = sum / float(radii.size())


## Transform da roda em relacao ao seu pivo proprio (centro da roda): a roda
## fica exatamente onde estava no carro, mas passa a girar em torno do proprio
## eixo. Puro e testado no CI, porque transformacao errada aqui = roda orbitando.
static func wheel_in_pivot(in_car: Transform3D, center: Vector3) -> Transform3D:
	return Transform3D(Basis(), center).affine_inverse() * in_car


func _build_camera() -> void:
	# Rig em top_level: a camera segue a posicao do carro SEM herdar rotacao —
	# mesmo arranjo da camera do personagem.
	_camera_rig = Node3D.new()
	_camera_rig.name = "CarCameraRig"
	_camera_rig.top_level = true
	add_child(_camera_rig)
	camera = Camera3D.new()
	camera.name = "CarCamera"
	camera.fov = 68.0
	camera.near = 0.25
	camera.far = 3200.0
	_camera_rig.add_child(camera)


## Marcador flutuante sobre o carro: um poste fino e uma esfera emissiva. O
## carro e baixo e cinza no meio da areia; no iPhone o jogador nao o achava
## (B-36). O marcador fica em pe (top_level: nao herda a inclinacao do carro) e
## some ao dirigir.
func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "CarMarker"
	_marker.top_level = true
	add_child(_marker)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.25)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = 2.6
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.radial_segments = 6
	pole.mesh = cyl
	pole.material_override = mat
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position = Vector3(0.0, 1.3, 0.0)
	_marker.add_child(pole)
	var bulb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.26
	sph.height = 0.52
	sph.radial_segments = 10
	sph.rings = 5
	bulb.mesh = sph
	bulb.material_override = mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = Vector3(0.0, 2.7, 0.0)
	_marker.add_child(bulb)
	_update_marker()


func _update_marker() -> void:
	if _marker == null:
		return
	_marker.global_position = global_position
	_marker.visible = not occupied


# --- Direcao ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta)
	_crash_cool = maxf(0.0, _crash_cool - delta)
	if occupied:
		_drive(delta)
		_inclinar(delta)
		_update_camera(delta)
	_update_wheels(delta)
	_maybe_toggle()
	_update_marker()


func _drive(delta: float) -> void:
	# Entrada: joystick (cima = acelerar, baixo = frear/re, lados = volante)
	# e teclado no desktop. O mesmo padrao de entrada do player.gd.
	var throttle := 0.0
	var steer_in := 0.0
	if TouchControls.is_active():
		var s := TouchControls.stick()
		# O joystick continua servindo de acelerador (arrastar para cima), mas
		# so pela metade: dirigindo ele fica com o volante, e quem acelera de
		# verdade sao os pedais ACEL/FREIO (touch_controls.set_driving).
		throttle = clampf(-s.y, -1.0, 1.0) * 0.5
		steer_in = clampf(s.x, -1.0, 1.0)
	if TouchControls.pedal_gas():
		throttle = 1.0
	if TouchControls.pedal_brake():
		throttle = -1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		throttle = 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		throttle = -1.0
	if Input.is_key_pressed(KEY_A):
		steer_in = -1.0
	if Input.is_key_pressed(KEY_D):
		steer_in = 1.0
	# Diagnostico para o HUD: se o carro nao andar, esta linha diz se ele
	# recebe acelerador e volante (B-36).
	input_throttle = throttle
	input_steer = steer_in
	# Dirigindo, o arrasto de olhar nao move nada: descarta o acumulado, senao a
	# camera do personagem da um salto ao sair do carro.
	TouchControls.consume_look()

	# --- Motor, cambio e forcas (B-67): massa, torque, marchas, ABS/TCS, arrasto
	# e peso. O declive entra no sentido do movimento (sobe freia, desce acelera).
	var sp := spec()
	var fwd2 := Vector2(-sin(rotation.y), -cos(rotation.y))
	var h_front := Cfg.surface_at(position.x + fwd2.x * 1.6, position.z + fwd2.y * 1.6)
	var h_back := Cfg.surface_at(position.x - fwd2.x * 1.6, position.z - fwd2.y * 1.6)
	var slope := atan2(h_front - h_back, 3.2)
	var mu := VehiclePhysics.surface_mu(position.x, position.z)
	_st["speed"] = speed
	_st["gear"] = gear
	_st = VehiclePhysics.step(sp, _st, throttle, slope, mu, delta)
	speed = float(_st["speed"])
	gear = int(_st["gear"])
	rpm = float(_st["rpm"])
	accel_long = float(_st["accel"])
	var redline := maxf(1.0, float(sp["redline"]))
	engine_ratio = clampf((rpm - float(sp["idle"])) / maxf(1.0, redline - float(sp["idle"])),
			0.0, 1.0)
	# Esterco e guinada: o volante pede uma curva, a ADERENCIA diz quanta cabe.
	steer = move_toward(steer, -steer_in * steer_limit(speed), STEER_SPEED * delta)
	var radius := WHEELBASE / maxf(0.02, tan(absf(steer)))
	var lat_req := speed * speed / maxf(1.0, radius)
	var lat_max := VehiclePhysics.lateral_limit(sp, mu)
	var grip := clampf(lat_max / maxf(0.1, lat_req), 0.0, 1.0)
	slip = 1.0 - grip
	var turn := yaw_rate(speed, steer) * grip
	accel_lat = speed * turn
	rotation.y = wrapf(rotation.y + turn * delta, -PI, PI)

	var forward := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var next := position + forward * speed * delta
	# Agua funda: desliza na borda e perde o impulso (mesmo padrao do player).
	if Cfg.height_at(next.x, next.z) < Cfg.MIN_WADE_DEPTH:
		var try_x := Vector3(next.x, 0.0, position.z)
		var try_z := Vector3(position.x, 0.0, next.z)
		if Cfg.height_at(try_x.x, try_x.z) >= Cfg.MIN_WADE_DEPTH:
			next = try_x
		elif Cfg.height_at(try_z.x, try_z.z) >= Cfg.MIN_WADE_DEPTH:
			next = try_z
		else:
			next = Vector3(position.x, 0.0, position.z)
		speed = 0.0
	next.x = clampf(next.x, Cfg.WORLD_MIN.x, Cfg.WORLD_MAX.x)
	next.z = clampf(next.z, Cfg.WORLD_MIN.y, Cfg.WORLD_MAX.y)
	if streamer != null:
		var pushed: Vector2 = streamer.push_out(next.x, next.z, 1.1)
		if pushed != Vector2(next.x, next.z):
			next.x = pushed.x
			next.z = pushed.y
			# Bateu num predio: mata a velocidade para frente (a re continua).
			if speed > 0.0:
				speed = 0.0
	# Colisao com o transito: o carro nao atravessa outro carro. Empurra para
	# fora e mata o embalo, com um pequeno recuo que da a sensacao de batida.
	if traffic != null:
		var hit: Dictionary = traffic.hit_test(next, COLLIDE_RADIUS)
		if not hit.is_empty():
			var pushed: Vector3 = hit["pushed"]
			next.x = pushed.x
			next.z = pushed.z
			var impact := clampf(absf(speed) / MAX_SPEED, 0.2, 1.0)
			speed = -1.6 if speed > 0.0 else 0.0
			# Encostado no outro carro, isto roda a cada quadro: o som e o
			# tremor so valem a cada 0,35 s, senao vira metralhadora.
			if _crash_cool <= 0.0:
				hit_flash = 0.8
				_crash_cool = 0.35
				crashed.emit(impact)
	position = next
	position.y = Cfg.surface_at(next.x, next.z)


## Carroceria acompanha o relevo: pitch (nariz sobe na subida) e roll (lado
## direito sobe quando o terreno do lado direito e mais alto), suavizados.
func _inclinar(delta: float) -> void:
	var f := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var r := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var s := 1.6
	var hf := Cfg.surface_at(position.x + f.x * s, position.z + f.z * s)
	var hb := Cfg.surface_at(position.x - f.x * s, position.z - f.z * s)
	var hr := Cfg.surface_at(position.x + r.x * s, position.z + r.z * s)
	var hl := Cfg.surface_at(position.x - r.x * s, position.z - r.z * s)
	var pitch := atan2(hf - hb, 2.0 * s)
	var roll := atan2(hr - hl, 2.0 * s)
	# Transferencia de peso VISIVEL (B-67): acelerar levanta o nariz, frear
	# mergulha, e na curva a carroceria rola para fora.
	pitch += clampf(accel_long * 0.010, -0.06, 0.06)
	roll -= clampf(accel_lat * 0.008, -0.07, 0.07)
	var k := clampf(6.0 * delta, 0.0, 1.0)
	rotation.x = lerp_angle(rotation.x, pitch, k)
	rotation.z = lerp_angle(rotation.z, roll, k)


func _update_wheels(delta: float) -> void:
	# wrapf mantem o angulo pequeno: sem isso o acumulo perde precisao float
	# depois de alguns minutos dirigindo.
	_spin = wrapf(_spin + (speed / maxf(0.05, _spin_radius)) * delta, -TAU, TAU)
	# A roda desenhada para no para-lama (VISUAL_STEER); o volante da fisica vira
	# mais que isso nas manobras.
	var wheel_steer := clampf(steer, -VISUAL_STEER, VISUAL_STEER)
	if model_loaded:
		for wi in _model_wheels:
			var pivot := wi["node"] as Node3D
			if pivot == null:
				continue
			# Giro no eixo LATERAL do carro (X local), nao no eixo do no do .glb:
			# num .glb o "eixo da roda" pode nao existir como eixo do no, e o no
			# "BackWheels" carrega as duas rodas de tras. Sinal negativo: com o
			# carro andando para -Z, o topo da roda vai para -Z (B-39).
			pivot.rotation.x = -_spin
			pivot.rotation.y = wheel_steer if bool(wi["front"]) else 0.0
		return
	for w in _wheels:
		w.rotation.x = -_spin
	for p in _front_pivots:
		p.rotation.y = wheel_steer


func _update_camera(delta: float) -> void:
	if camera == null or _camera_rig == null:
		return
	var back := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var forward := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var target := global_position + back * 7.5 + Vector3(0.0, 3.0, 0.0)
	var ground := Cfg.height_at(target.x, target.z) + 1.2
	target.y = maxf(target.y, ground)
	# delta <= 0 = encaixe instantaneo (ao entrar no carro).
	var k := 1.0 if delta <= 0.0 else clampf(6.0 * delta, 0.0, 1.0)
	_camera_rig.global_position = _camera_rig.global_position.lerp(target, k)
	camera.look_at(global_position + forward * 3.0 + Vector3(0.0, 1.3, 0.0), Vector3.UP)


# --- Entrar / sair --------------------------------------------------------------

func _maybe_toggle() -> void:
	var e := Input.is_key_pressed(KEY_E)
	if e and not _e_latch:
		_e_latch = true
		if occupied or _near_player():
			toggle_occupant()
	elif not e:
		_e_latch = false


func _near_player() -> bool:
	return player != null and player.position.distance_to(position) < PROXIMITY


func toggle_occupant() -> void:
	if occupied:
		_exit()
	else:
		_enter()


func _enter() -> void:
	if occupied or player == null:
		return
	occupied = true
	speed = 0.0
	steer = 0.0
	if _marker != null:
		_marker.visible = false
	player.enabled = false
	player.visible = false
	if camera != null:
		camera.current = true
	_update_camera(0.0)


func _exit() -> void:
	if not occupied or player == null:
		return
	# Desembarca do lado direito; se cair na agua, tenta o esquerdo.
	var side := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var out := global_position + side * 2.4
	if Cfg.height_at(out.x, out.z) < Cfg.MIN_WADE_DEPTH:
		out = global_position - side * 2.4
	out.x = clampf(out.x, Cfg.WORLD_MIN.x, Cfg.WORLD_MAX.x)
	out.z = clampf(out.z, Cfg.WORLD_MIN.y, Cfg.WORLD_MAX.y)
	if streamer != null:
		var pushed: Vector2 = streamer.push_out(out.x, out.z, 0.5)
		out.x = pushed.x
		out.z = pushed.y
	player.teleport(out)
	player.visible = true
	player.enabled = true
	if player.camera != null:
		player.camera.current = true
	occupied = false
	speed = 0.0
	steer = 0.0
