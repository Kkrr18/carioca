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
const ModelProp = preload("res://scripts/world/model_prop.gd")
const Pedestrians = preload("res://scripts/world/pedestrians.gd")
const FaceTexture = preload("res://scripts/player/face_texture.gd")

const WALK_SPEED := 4.2
const RUN_SPEED := 8.5
const ACCEL := 26.0
const AIR_ACCEL := 7.0
const JUMP_SPEED := 6.0
const GRAVITY := 18.0
const TURN_SPEED := 12.0
const EYE_HEIGHT := 1.5

# --- Modelo do protagonista (B-63) -------------------------------------------
## O mesmo corpo CC0 da Quaternius que ja roda nos pedestres: e o unico com as
## animacoes DENTRO do arquivo (idle, walk, run, jump), entao nao depende de
## retarget nenhum. Pintado por vertice: homem BRANCO, de CABELO PRETO, 1,80 m,
## camiseta laranja e calca jeans (a identidade do boneco antigo).
const AVATAR_PATH := "res://assets/models/ped-walk.glb"
const AVATAR_HEIGHT := 1.80
const SKIN_COL := Color(0.96, 0.84, 0.75)
const SHIRT_COL := Color(0.92, 0.45, 0.25)
const PANTS_COL := Color(0.19, 0.27, 0.46)
const HAIR_COL := Color(0.09, 0.08, 0.08)

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
var contact_shadow: MeshInstance3D
var _using_model := false
var _ap: AnimationPlayer
var _model_holder: Node3D
var _face: MeshInstance3D      # rosto (B-76); null se o modelo nao carregou
var _idle_static := false      # clipe de parado sem movimento (pose parada)
var _sway := 0.0
var _walk_anim := ""
var _idle_anim := ""
var _run_anim := ""
var _jump_anim := ""


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
	if not _build_model_avatar():
		_build_block_avatar()
	_build_contact_shadow()


## Avatar de MODELO (B-63). Devolve false se o arquivo nao carregar ou nao der
## para pintar, e ai o jogador continua com o boneco de caixas: o jogo nunca fica
## sem personagem.
func _build_model_avatar() -> bool:
	var scene := Pedestrians.load_scene(AVATAR_PATH)
	if scene == null:
		return false
	# O avatar gira em Y pelo codigo de movimento (atan2(hv.x, hv.y)) e o modelo
	# olha para -Z: um filho com PI deixa a frente no +Z do avatar, que e o que o
	# resto do codigo ja esperava do boneco antigo (nariz em +Z). Sem esse PI o
	# protagonista anda de costas (o mesmo erro que a B-62 corrigiu nos pedestres).
	var holder := Node3D.new()
	holder.rotation.y = PI
	avatar.add_child(holder)
	_model_holder = holder
	var inst: Node3D = scene.instantiate()
	holder.add_child(inst)
	var painted := 0
	for node in ModelProp.collect_meshes(inst):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if Pedestrians.paint_body(mi, SKIN_COL, SHIRT_COL, PANTS_COL, HAIR_COL):
			painted += 1
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = false
		mat.roughness = 0.92
		mat.metallic_specular = 0.1
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if painted == 0:
		holder.queue_free()
		return false
	# Animacoes: o walker traz idle/walk/run/jump no proprio arquivo.
	_ap = Pedestrians._find_anim(inst)
	var clips := {}
	if _ap != null:
		for nm in _ap.get_animation_list():
			var a := _ap.get_animation(String(nm))
			if a != null:
				clips[String(nm)] = a
	_walk_anim = Pedestrians.pick_clip(clips, "walk")
	_idle_anim = Pedestrians.pick_clip(clips, "idle")
	_run_anim = Pedestrians.pick_clip(clips, "run")
	_jump_anim = Pedestrians.pick_clip(clips, "jump")
	for nm in [_walk_anim, _idle_anim, _run_anim]:
		if nm != "" and clips.has(nm):
			(clips[nm] as Animation).loop_mode = Animation.LOOP_LINEAR
	# O clipe de parado da Quaternius pode ser uma pose ESTATICA: nesse caso o
	# protagonista fica plantado como estátua (era o que se via no jogo), e a
	# solucao e um balanco minimo por codigo (ESTILO.md: nada fica imovel).
	_idle_static = _idle_anim == "" or Pedestrians.clip_motion(clips[_idle_anim]) < 0.02
	if _idle_anim != "":
		_ap.play(StringName(_idle_anim))
	# Escala: posa um clipe, mede a altura do esqueleto POSADO (o AABB da malha e
	# o do bind pose e mente), normaliza para 1,80 m e apoia o pe no chao.
	var box := ModelProp.mesh_aabb(inst)
	var sk := Pedestrians._find_skel(inst)
	var posed := Pedestrians.posed_height(sk)
	var h := posed / Pedestrians.BONE_EXTENT if posed > 0.3 else maxf(0.5, box.size.y)
	var k := AVATAR_HEIGHT / maxf(0.5, h)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * k
	_using_model = _ap != null
	# Rosto (B-76): o corpo CC0 tem cabeca lisa. O quad do rosto entra DEPOIS da
	# escala, como filho do `avatar` (que ja gira com o personagem e tem +Z como
	# frente), entao ele acompanha o corpo e o tamanho do protagonista.
	_build_face()
	return true


## Rosto do protagonista: quad com olhos/sobrancelha/boca desenhados em codigo
## (FaceTexture), do tamanho da cabeca do personagem (fracao de AVATAR_HEIGHT).
## Fica no espaco do `avatar`: +Z e a frente, sem rotacao nenhuma — a frente do
## QuadMesh ja aponta para +Z.
func _build_face() -> void:
	if avatar == null:
		return
	var lay := FaceTexture.layout(AVATAR_HEIGHT)
	var quad := QuadMesh.new()
	quad.size = lay["size"]
	var mi := MeshInstance3D.new()
	mi.name = "Rosto"
	mi.mesh = quad
	mi.material_override = FaceTexture.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var center: Vector3 = lay["center"]
	mi.position = center
	avatar.add_child(mi)
	_face = mi


## Boneco de caixas: a reserva de sempre, usada so se o modelo nao carregar.
func _build_block_avatar() -> void:
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


## Sombra de contato (nao existe Decal no renderer Compatibility): disco
## escuro sob os pes, ancorado no chao analitico.
func _build_contact_shadow() -> void:
	contact_shadow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35, 1.35)
	quad.orientation = PlaneMesh.FACE_Y
	# Mancha REDONDA e macia (gradiente radial). Sem textura o quad virava um
	# retangulo cinza duro embaixo do personagem (B-60).
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.50),
			Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.98, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.42)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	contact_shadow.mesh = quad
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_shadow.top_level = true
	add_child(contact_shadow)


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

	var ground_y := Cfg.surface_at(next.x, next.z)
	if contact_shadow != null:
		contact_shadow.global_position = Vector3(next.x, ground_y + 0.07, next.z)
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

	# --- Orientacao e animacao.
	if hv.length() > 0.4:
		var want_angle := atan2(hv.x, hv.y)
		avatar.rotation.y = lerp_angle(avatar.rotation.y, want_angle, clampf(TURN_SPEED * delta, 0.0, 1.0))
	_bob += delta * maxf(1.0, hv.length())
	_update_anim(hv, delta)

	_update_camera(delta)


## Animacao: clipes do MODELO quando ele existe (parado / andando / correndo /
## pulando) e, no boneco de caixas, o balanco antigo de bracos e pernas.
func _update_anim(hv: Vector2, delta: float) -> void:
	if _using_model and _ap != null:
		var sp := hv.length()
		if not _grounded and _jump_anim != "":
			_play_anim(_jump_anim, 1.0)
			_idle_hold()
		elif sp > 2.2 and _run_anim != "":
			# O clipe de corrida cobre ~4,6 m/s no compasso 1.
			_play_anim(_run_anim, clampf(sp / 4.6, 0.55, 2.0))
			_idle_hold()
		elif sp > 0.35 and _walk_anim != "":
			_play_anim(_walk_anim, clampf(sp / 1.5, 0.60, 1.70))
			_idle_hold()
		else:
			_play_anim(_idle_anim, 1.0)
			_idle_sway(delta)
		return
	if hv.length() > 0.4:
		var swing := sin(_bob) * clampf(hv.length() / RUN_SPEED, 0.0, 1.0) * 0.7
		if _legs.size() == 2:
			_legs[0].rotation.x = swing
			_legs[1].rotation.x = -swing
		if _arms.size() == 2:
			_arms[0].rotation.x = -swing * 0.8
			_arms[1].rotation.x = swing * 0.8
	else:
		for l in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, 0.2)
		for a in _arms:
			a.rotation.x = lerpf(a.rotation.x, 0.0, 0.2)


func _play_anim(nm: String, spd: float) -> void:
	if _ap == null or nm == "":
		return
	# `is_playing()` falso = o clipe acabou (pulo, por exemplo): recomeca, senao o
	# personagem fica congelado no ultimo quadro daquele clipe para sempre.
	if _ap.current_animation != StringName(nm) or not _ap.is_playing():
		_ap.play(StringName(nm))
	_ap.speed_scale = spd


## Parado: o corpo SEMPRE ganha um balanco minimo (giro de ~1,7 grau e 1 cm de
## sobe e desce). O clipe de parado da Quaternius mexe pouco (0,118 rad no osso
## que mais gira) e a 250 px de tela ele parece congelado — o autor viu o
## protagonista "parado numa pose" (B-63). Com o clipe animando, o balanco e
## menor (so para nao parecer estatua); sem movimento no clipe, ele e maior.
func _idle_sway(delta: float) -> void:
	if _model_holder == null:
		return
	_sway += delta
	var amp := 0.030 if _idle_static else 0.016
	_model_holder.rotation.y = PI + sin(_sway * 1.1) * amp
	_model_holder.position.y = sin(_sway * 2.0) * 0.010


func _idle_hold() -> void:
	if _model_holder == null:
		return
	_model_holder.rotation.y = PI
	_model_holder.position.y = 0.0


## Estado do avatar na telemetria: e por esta linha que se sabe, no aparelho, se
## o modelo carregou e se a animacao esta mesmo tocando (nao ha console no Safari).
func describe() -> String:
	if not _using_model:
		return "avatar: boneco de caixas (modelo nao carregou)"
	var playing := "parada"
	if _ap != null and _ap.is_playing():
		playing = "tocando"
	return "avatar: modelo 1,80 m (%s; idle=%s walk=%s run=%s jump=%s; parado=%s; rosto=%s)" % [
		playing, _idle_anim, _walk_anim, _run_anim, _jump_anim,
		"estatico+balanco" if _idle_static else "animado",
		"sim" if _face != null else "nao"]


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
	position = Vector3(pos.x, Cfg.surface_at(pos.x, pos.z) + 0.05, pos.z)
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
