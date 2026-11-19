extends CharacterBody3D
## Player: personagem em terceira pessoa (Fase 3 provisoria, jogavel).
##
## - Chao analitico (Cfg.height_at) + empurrao contra retangulos de predio
##   (SectorStreamer.push_out). Sem CharacterBody3D de chao fisico: previsivel
##   e barato no iPhone, e o mesmo resultado em qualquer frame rate.
## - Camera em orbita atras do personagem; toque na direita gira, joystick
##   na esquerda anda. Teclado WASD/setas funciona no desktop.
## - O personagem nao entra em agua mais funda que MIN_WADE_DEPTH.

const Cfg = preload("res://scripts/core/cfg.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")

const WALK_SPEED := 4.2
const RUN_SPEED := 8.5
const ACCEL := 26.0
const AIR_ACCEL := 7.0
const JUMP_SPEED := 6.0
const GRAVITY := 18.0
const TURN_SPEED := 12.0
const EYE_HEIGHT := 1.5

var streamer = null
var camera_rig: Node3D
var camera: Camera3D
var avatar: Node3D

var cam_yaw := 0.0
var cam_pitch := -0.28
var cam_distance := 6.5
var look_sensitivity := 0.008
var invert_look_y := false

var spawn_position := Vector3(1600.0, 0.0, 100.0)
var enabled := true

var _vy := 0.0
var _grounded := false
var _bob := 0.0
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	_build_avatar()
	_build_camera()
	teleport(spawn_position)
	set_process_input(true)
	set_physics_process(true)


func _build_avatar() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	# Materiais compartilhados por cor.
	var skin := _mat(Color(0.80, 0.63, 0.48))
	var shirt := _mat(Color(0.92, 0.45, 0.25))
	var shorts := _mat(Color(0.18, 0.26, 0.44))
	var hair := _mat(Color(0.16, 0.12, 0.10))

	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.height = 1.2
	cap.radius = 0.28
	torso.mesh = cap
	torso.material_override = shirt
	torso.position = Vector3(0, 1.05, 0)
	avatar.add_child(torso)

	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.height = 0.34
	sph.radius = 0.17
	head.mesh = sph
	head.material_override = skin
	head.position = Vector3(0, 1.82, 0)
	avatar.add_child(head)

	var hair_mi := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.height = 0.2
	hair_mesh.radius = 0.175
	hair_mi.mesh = hair_mesh
	hair_mi.material_override = hair
	hair_mi.position = Vector3(0, 1.88, -0.01)
	avatar.add_child(hair_mi)

	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.05, 0.06)
	nose.mesh = box
	nose.material_override = skin
	nose.position = Vector3(0, 1.8, 0.17)
	avatar.add_child(nose)

	for side in [-1.0, 1.0]:
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(0.34 * side, 1.52, 0.0)
		var arm := MeshInstance3D.new()
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(0.13, 0.62, 0.13)
		arm.mesh = arm_box
		arm.material_override = skin
		arm.position = Vector3(0, -0.3, 0)
		arm_pivot.add_child(arm)
		avatar.add_child(arm_pivot)
		_arms.append(arm_pivot)

		var leg_pivot := Node3D.new()
		leg_pivot.position = Vector3(0.14 * side, 0.72, 0.0)
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.16, 0.72, 0.16)
		leg.mesh = leg_box
		leg.material_override = shorts
		leg.position = Vector3(0, -0.36, 0)
		leg_pivot.add_child(leg)
		avatar.add_child(leg_pivot)
		_legs.append(leg_pivot)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	return m


func _build_camera() -> void:
	# Uma caixa tecnica (rig) segue a posicao do personagem SEM herdar a rotacao
	# do corpo: a camera e filha dela, e nenhuma conta de yaw e aplicada duas
	# vezes.
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.top_level = true
	add_child(camera_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 72.0
	camera.near = 0.25
	camera.far = 3200.0
	camera_rig.add_child(camera)
	camera.current = true


func _input(event: InputEvent) -> void:
	# Desktop: botao direito arrastado gira a camera. No iPhone o look vem de
	# TouchControls (arrasto no lado direito da tela).
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		cam_yaw = wrapf(cam_yaw - mm.relative.x * look_sensitivity * 0.5, -PI, PI)
		cam_pitch = clampf(cam_pitch - mm.relative.y * look_sensitivity * 0.5, deg_to_rad(-70.0), deg_to_rad(20.0))


func _physics_process(delta: float) -> void:
	if not enabled:
		return

	# --- Camera: arrasto do toque na direita + setas no desktop.
	var look := TouchControls.consume_look()
	var yaw_in := look.x * look_sensitivity
	var pitch_in := look.y * look_sensitivity
	if Input.is_key_pressed(KEY_LEFT):
		yaw_in -= 1.8 * delta
	if Input.is_key_pressed(KEY_RIGHT):
		yaw_in += 1.8 * delta
	if Input.is_key_pressed(KEY_UP):
		pitch_in -= 1.2 * delta
	if Input.is_key_pressed(KEY_DOWN):
		pitch_in += 1.2 * delta
	cam_yaw = wrapf(cam_yaw - yaw_in, -PI, PI)
	var dy := pitch_in if invert_look_y else -pitch_in
	cam_pitch = clampf(cam_pitch + dy, deg_to_rad(-70.0), deg_to_rad(20.0))

	# --- Entrada de movimento.
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var input := Vector2.ZERO
	if TouchControls.is_active():
		input = TouchControls.stick()
	else:
		if Input.is_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			input.x += 1.0
		if Input.is_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			input.y += 1.0
		if input.length() > 1.0:
			input = input.normalized()

	var wish := right * input.x + forward * -input.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	var want_sprint := TouchControls.sprint_held() or Input.is_key_pressed(KEY_SHIFT)
	var target_speed := RUN_SPEED if want_sprint else WALK_SPEED
	var target := wish * target_speed
	var accel := ACCEL if _grounded else AIR_ACCEL
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), accel * delta)

	# --- Pulo / voo (botao PULAR; segurar mantem no ar como "asas" de debug).
	if TouchControls.jump_pressed() or Input.is_key_pressed(KEY_SPACE):
		if _grounded:
			_vy = JUMP_SPEED
			_grounded = false
		elif _vy > -1.0 and (TouchControls.jump_held() or Input.is_key_pressed(KEY_SPACE)):
			_vy = maxf(_vy, 2.5)

	_vy -= GRAVITY * delta
	var next := position + Vector3(hv.x, 0.0, hv.y) * delta
	# Agua profunda: desliza na superficie em vez de entrar.
	var ground_next := Cfg.height_at(next.x, next.z)
	if ground_next < Cfg.MIN_WADE_DEPTH:
		var try_x := Vector3(next.x, 0.0, position.z)
		var try_z := Vector3(position.x, 0.0, next.z)
		if Cfg.height_at(try_x.x, try_x.z) >= Cfg.MIN_WADE_DEPTH:
			next = try_x
		elif Cfg.height_at(try_z.x, try_z.z) >= Cfg.MIN_WADE_DEPTH:
			next = try_z
		else:
			next = Vector3(position.x, 0.0, position.z)
	next.x = clampf(next.x, Cfg.WORLD_MIN.x, Cfg.WORLD_MAX.x)
	next.z = clampf(next.z, Cfg.WORLD_MIN.y, Cfg.WORLD_MAX.y)
	if streamer != null:
		var pushed: Vector2 = streamer.push_out(next.x, next.z, 0.5)
		next.x = pushed.x
		next.z = pushed.y
	next.y = position.y

	var ground_y := Cfg.height_at(next.x, next.z)
	var y := position.y + _vy * delta
	if y <= ground_y:
		y = ground_y
		_vy = 0.0
		_grounded = true
	else:
		_grounded = false
	next.y = y

	velocity = (next - position) / delta
	move_and_slide()
	position = next

	# --- Orientacao e animacao de caminhada.
	if hv.length() > 0.4:
		var want_angle := atan2(hv.x, hv.y)
		avatar.rotation.y = lerp_angle(avatar.rotation.y, want_angle, clampf(TURN_SPEED * delta, 0.0, 1.0))
		_bob += delta * hv.length() * 2.2
		var swing := sin(_bob) * clampf(hv.length() / RUN_SPEED, 0.0, 1.0) * 0.7
		if _legs.size() == 2:
			_legs[0].rotation.x = swing
			_legs[1].rotation.x = -swing
		if _arms.size() == 2:
			_arms[0].rotation.x = -swing * 0.8
			_arms[1].rotation.x = swing * 0.8
	else:
		_bob += delta
		for l in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, 0.2)
		for a in _arms:
			a.rotation.x = lerpf(a.rotation.x, 0.0, 0.2)

	_update_camera(delta)


func _update_camera(delta: float) -> void:
	if camera == null or camera_rig == null:
		return
	var head := global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	camera_rig.global_position = head
	var back := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var dist := cam_distance
	var desired := head + back * dist
	if streamer != null:
		# Encurta a camera se um predio ficaria entre ela e a cabeca.
		var flat := Vector2(desired.x, desired.z)
		var pushed: Vector2 = streamer.push_out(flat.x, flat.y, 0.6)
		var margin := (pushed - flat).length()
		if margin > 0.01:
			dist = maxf(1.6, dist - margin - 0.4)
			desired = head + back * dist
	var ground := Cfg.height_at(desired.x, desired.z) + 0.8
	camera.global_position = Vector3(desired.x, maxf(desired.y, ground), desired.z)
	camera.look_at(head + Vector3(0, 0.15, 0), Vector3.UP)


func teleport(pos: Vector3) -> void:
	position = Vector3(pos.x, Cfg.height_at(pos.x, pos.z) + 0.05, pos.z)
	_vy = 0.0
	_grounded = true
	velocity = Vector3.ZERO
	_update_camera(0.0)


## Estado para o save (schema 1).
func state() -> Dictionary:
	return {
		"pos": [position.x, position.y, position.z],
		"yaw": avatar.rotation.y,
		"cam_yaw": cam_yaw,
		"cam_pitch": cam_pitch,
	}


func restore(data: Dictionary) -> void:
	var p: Array = data.get("pos", [position.x, position.y, position.z])
	teleport(Vector3(float(p[0]), float(p[1]), float(p[2])))
	avatar.rotation.y = float(data.get("yaw", 0.0))
	cam_yaw = float(data.get("cam_yaw", 0.0))
	cam_pitch = float(data.get("cam_pitch", -0.28))
	_update_camera(0.0)


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
