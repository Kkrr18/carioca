extends Node3D
## Main: composicao da cena da Fase 1 (montada por codigo; o .tscn so aponta
## para este script). Ordem de boot:
##   1. ambiente (ceu procedural, nevoa, sol/lua)
##   2. streamer de setores (com o seed do World)
##   3. jogador na praia, olhando o mar
##   4. interface de toque e HUD
##   5. salvamento/carregamento versionado (SaveManager)

const Cfg = preload("res://scripts/core/cfg.gd")
const Car = preload("res://scripts/vehicles/car.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const SectorStreamer = preload("res://scripts/world/sector_streamer.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const Player = preload("res://scripts/player/player.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")
const PerfLog = preload("res://scripts/core/perf_log.gd")

const SPAWN := Vector3(1600.0, 1.2, 100.0)

var world_seed: int = 20260922
var environment: Environment
var sea: MeshInstance3D
var streamer = null
var player = null
var car = null
var day_night = null
var hud = null
var perf_log = null
var touch = null
var model_prop = null

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _camera: Camera3D
var _loading := true
var _loading_label: Label
var _play_time := 0.0
var _boot_log: Label


## Marca a etapa atual do boot na tela. O console do WebGL no Safari nao e
## visivel para o jogador; se _ready abortar em algum erro, o ULTIMO texto
## aqui mostrado indica exatamente onde o jogo parou (B-20/B-23 passaram
## despercebidos por isso).
func _boot_step(m: String) -> void:
	if _boot_log != null:
		_boot_log.text = "BOOT: " + m


func _ready() -> void:
	world_seed = World.world_seed
	randomize()

	# Log de boot visivel na tela.
	var boot_layer := CanvasLayer.new()
	boot_layer.name = "BootLogLayer"
	boot_layer.layer = 10
	add_child(boot_layer)
	_boot_log = Label.new()
	_boot_log.text = "BOOT: iniciando"
	_boot_log.position = Vector2(12.0, 70.0)
	_boot_log.add_theme_font_size_override("font_size", 14)
	_boot_log.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_boot_log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_boot_log.add_theme_constant_override("outline_size", 3)
	boot_layer.add_child(_boot_log)

	_boot_step("ambiente")
	_build_environment()
	_boot_step("mar")
	_build_sea()

	_boot_step("streamer")
	streamer = SectorStreamer.new()
	streamer.name = "SectorStreamer"
	streamer.world_seed = world_seed
	streamer.full_ring = 1
	streamer.far_ring = 2
	if OS.has_feature("web"):
		# Build web (Safari / GitHub Pages) sem threads: WorkerThreadPool nao
		# existe nessa variante do export, entao a geracao roda na thread
		# principal e o raio de streaming e menor.
		streamer.use_threads = false
		streamer.full_ring = 0
		streamer.far_ring = 1
	add_child(streamer)

	_boot_step("relogio")
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(_sun, _moon, environment)
	day_night.set_hour(9.5)

	# HUD antes do player: se o player abortar, a interface e o log de boot
	# continuam visiveis (e o diagnostics fica na tela).
	_boot_step("interface")
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(player, streamer, day_night)
	hud.action.connect(_on_hud_action)

	_boot_step("player")
	player = Player.new()
	player.name = "Player"
	player.streamer = streamer
	player.spawn_position = SPAWN
	add_child(player)
	hud.setup(player, streamer, day_night)

	# Fase 4 (incremento minimo): um carro dirigivel na areia, a poucos metros do
	# ponto de nascimento. Antes ele ficava a 14 m e o botao so aparecia a 3,5 m:
	# no iPhone o jogador nao o encontrava (B-36). Agora ele nasce no campo de
	# visao e tem um marcador flutuante.
	_boot_step("carro")
	car = Car.new()
	car.name = "Car"
	car.player = player
	car.streamer = streamer
	car.position = Vector3(1604.0, Cfg.height_at(1604.0, 96.0), 96.0)
	car.rotation.y = PI * 0.5
	add_child(car)
	hud.set_car(car)

	# Piloto de assets (B-21): UM modelo .glb CC0 externo no mundo procedural.
	# Serve para medir no aparelho o custo real (bytes e FPS) de sair do
	# procedural; se o arquivo nao carregar, o no fica vazio e o jogo segue.
	_boot_step("modelo")
	model_prop = ModelProp.new()
	model_prop.name = "ModelPropTruck"
	model_prop.model_path = "res://assets/models/vehicle-truck-red.glb"
	model_prop.target_length = 5.4
	model_prop.position = Vector3(1594.0, Cfg.height_at(1594.0, 90.0), 90.0)
	model_prop.rotation.y = PI * 0.5
	add_child(model_prop)
	hud.set_model_note(model_prop.describe())

	_boot_step("toque")
	var touch_layer := CanvasLayer.new()
	touch_layer.name = "TouchLayer"
	touch_layer.layer = 1
	add_child(touch_layer)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch_layer.add_child(touch)

	_boot_step("telemetria")
	perf_log = PerfLog.new()
	perf_log.name = "PerfLog"
	add_child(perf_log)
	perf_log.setup(player, streamer, day_night)

	_loading_label = Label.new()
	_loading_label.text = "Gerando o mundo..."
	_loading_label.add_theme_font_size_override("font_size", 20)
	_loading_label.position = Vector2(24.0, 200.0)
	hud.add_child(_loading_label)

	_boot_step("pronto")
	_boot_log.text = ""
	hud.toast("Joystick anda, arraste na direita para olhar. O carro esta a sua frente.")


func _build_environment() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.20, 0.40, 0.72)
	sm.sky_horizon_color = Color(0.68, 0.79, 0.88)
	sm.ground_bottom_color = Color(0.08, 0.12, 0.16)
	sm.ground_horizon_color = Color(0.68, 0.79, 0.88)
	sm.sun_angle_max = 22.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.75
	environment.ambient_light_energy = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.70, 0.79, 0.87)
	environment.fog_density = 0.0011
	environment.fog_sky_affect = 0.6
	# Pos-processamento barato (suportado no renderer Compatibility):
	# tonemap ACES + glow dao o "haze" de cidade litoranea.
	# O enum do Godot 4 e Environment.ToneMapper com o prefixo TONE_MAPPER_:
	# "TONEMAPPER_ACES" nao existe e quebrava a compilacao deste arquivo (B-28).
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.1

	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation = Vector3(-0.9, -PI * 0.25, 0.0)
	_sun.light_energy = 1.15
	_sun.light_color = Color(1.0, 0.97, 0.92)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 110.0
	_sun.directional_shadow_blend_splits = true
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.rotation = Vector3(-1.0, PI * 0.75, 0.0)
	_moon.light_energy = 0.15
	_moon.light_color = Color(0.62, 0.72, 1.0)
	_moon.shadow_enabled = false
	add_child(_moon)

	_camera = Camera3D.new()
	_camera.name = "BootCamera"
	_camera.fov = 65.0
	_camera.far = 3200.0
	_camera.position = Vector3(1600.0, 40.0, -120.0)
	_camera.rotation = Vector3(-0.15, 0.0, 0.0)
	add_child(_camera)
	_camera.make_current()


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000.0, 60000.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	sea = MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = plane
	# Material PBR padrao (sem shader custom): um ShaderMaterial sobre este
	# plano congelou o render no Safari/WebGL (B-25), entao o brilho do mar
	# vem de roughness baixa + specular com o sol do dia/noite.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.26, 0.38)
	m.roughness = 0.12
	m.metallic = 0.0
	m.metallic_specular = 0.7
	m.disable_receive_shadows = true
	sea.material_override = m
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _process(delta: float) -> void:
	_play_time += delta
	if day_night != null:
		day_night.process_frame(delta)
		if streamer != null:
			streamer.set_window_glow(day_night.night_amount)
	# Foco do mundo: o personagem a pe ou o carro, quando estiver dirigindo.
	# Sem isso o streaming e o mar ficariam parados onde o personagem desceu do
	# carro, e a cidade nao carregaria na frente do veiculo (Fase 4).
	var focus := Vector3.ZERO
	if player != null:
		focus = player.position
	if car != null and car.occupied:
		focus = car.global_position
	if streamer != null and player != null:
		streamer.update_stream(focus, delta)
		if _loading and streamer.has_ready_at(focus):
			_loading = false
			if _loading_label != null:
				_loading_label.visible = false
		if _loading_label != null:
			_loading_label.visible = _loading
	if sea != null and player != null:
		# Mar "infinito": acompanha o foco no plano XZ.
		sea.global_position = Vector3(focus.x, Cfg.SEA_LEVEL, focus.z)
	# Carro: avisa o toque para trocar PULAR/CORRER por ACEL/FREIO e mostra o
	# botao de contexto (ENTRAR perto do carro, SAIR dirigindo).
	if car != null and touch != null and touch.is_driving() != car.occupied:
		touch.set_driving(car.occupied)
	if hud != null and car != null and player != null:
		var prompt := ""
		if car.occupied:
			prompt = "SAIR DO CARRO"
		elif player.position.distance_to(car.global_position) < Car.PROXIMITY:
			prompt = "ENTRAR NO CARRO"
		hud.set_car_prompt(prompt)
	perf_log.sample(delta)


func _on_hud_action(which: String) -> void:
	match which:
		"save":
			save_game()
		"load":
			load_game()
		"car":
			if car == null or player == null:
				return
			if car.occupied:
				car.toggle_occupant()
				hud.toast("Voce saiu do carro.")
			else:
				# Rede de seguranca: o botao de contexto so aparece dentro de
				# Car.PROXIMITY, mas a distancia pode mudar entre o desenho do
				# botao e o toque. Se estiver longe, o jogador vai para o lado do
				# carro antes de entrar (B-36).
				if player.position.distance_to(car.global_position) > Car.PROXIMITY:
					var side := Vector3(cos(car.rotation.y), 0.0, -sin(car.rotation.y))
					player.teleport(car.global_position + side * 2.4)
				car.toggle_occupant()
				hud.toast("Volante no joystick, ACEL acelera, FREIO freia/da re (ou W A S D).")


func collect_state() -> Dictionary:
	var state := {
		"world_seed": world_seed,
		"player": player.state(),
		"clock": day_night.state(),
		"play_time": _play_time,
	}
	return state


func save_game() -> void:
	var ok: bool = SaveManager.save_state(collect_state())
	if ok:
		hud.toast("Jogo salvo (%s)" % SaveManager.save_path())
	else:
		hud.toast("Falha ao salvar: %s" % SaveManager.last_error)


func load_game() -> void:
	var state: Dictionary = SaveManager.load_state()
	if state.is_empty():
		hud.toast("Falha ao carregar: %s" % SaveManager.last_error)
		return
	var p: Dictionary = state.get("player", {})
	player.restore(p)
	var clock: Dictionary = state.get("clock", {})
	day_night.restore(clock)
	_play_time = float(state.get("play_time", 0.0))
	hud.toast("Jogo carregado (schema %d)" % int(state.get("schema", 0)))


## Teletransporte (usado por testes manuais e pela Fase 6).
func teleport(pos: Vector3) -> void:
	player.teleport(pos)


func dump_perf_log() -> String:
	return perf_log.dump_csv()
