extends Node3D
## Main: composicao da cena da Fase 1 (montada por codigo; o .tscn so aponta
## para este script). Ordem de boot:
##   1. ambiente (ceu procedural, nevoa, sol/lua)
##   2. streamer de setores (com o seed do World)
##   3. jogador na praia, olhando o mar
##   4. interface de toque e HUD
##   5. salvamento/carregamento versionado (SaveManager)

const Cfg = preload("res://scripts/core/cfg.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const SectorStreamer = preload("res://scripts/world/sector_streamer.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const Player = preload("res://scripts/player/player.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PerfLog = preload("res://scripts/core/perf_log.gd")

const SPAWN := Vector3(1600.0, 1.2, 100.0)

var world_seed: int = 20260922
var environment: Environment
var sea: MeshInstance3D
var streamer = null
var player = null
var day_night = null
var hud = null
var perf_log = null

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _camera: Camera3D
var _loading := true
var _loading_label: Label
var _play_time := 0.0


func _ready() -> void:
	world_seed = World.world_seed
	randomize()

	_build_environment()
	_build_sea()

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

	player = Player.new()
	player.name = "Player"
	player.streamer = streamer
	player.spawn_position = SPAWN
	add_child(player)

	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(_sun, _moon, environment)
	day_night.set_hour(9.5)

	var touch_layer := CanvasLayer.new()
	touch_layer.name = "TouchLayer"
	touch_layer.layer = 1
	add_child(touch_layer)
	var touch := TouchControls.new()
	touch.name = "TouchControls"
	touch_layer.add_child(touch)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(player, streamer, day_night)
	hud.action.connect(_on_hud_action)

	perf_log = PerfLog.new()
	perf_log.name = "PerfLog"
	add_child(perf_log)
	perf_log.setup(player, streamer, day_night)

	_loading_label = Label.new()
	_loading_label.text = "Gerando o mundo..."
	_loading_label.add_theme_font_size_override("font_size", 20)
	_loading_label.position = Vector2(24.0, 200.0)
	hud.add_child(_loading_label)

	hud.toast("Toque na esquerda para andar. Arraste na direita para olhar.")


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
	environment.tonemap_mode = Environment.TONEMAPPER_ACES
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
	var smat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SEA_SHADER
	smat.shader = sh
	sea.material_override = smat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


## Agua procedural: ondas pequenas pela posicao de mundo + tempo, fresnel
## misturando para a cor do ceu. Sem reflexo de tela (nao existe no
## renderer Compatibility) e opaco (transparencia custa fill rate).
const SEA_SHADER := "
shader_type spatial;
render_mode cull_back;
uniform vec3 deep_color : source_color = vec3(0.09, 0.23, 0.34);
uniform vec3 sky_color : source_color = vec3(0.68, 0.79, 0.88);
uniform float wave_scale = 0.045;
uniform float wave_speed = 0.8;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float t = TIME * wave_speed;
	float wx = wpos.x * wave_scale;
	float wz = wpos.z * wave_scale;
	float dwx = 0.02 * cos(wx + t) + 0.012 * cos(wz * 1.7 - t * 1.3);
	float dwz = 0.02 * cos(wz + t * 0.8) + 0.012 * cos(wx * 1.9 + t);
	vec3 n_world = normalize(vec3(-dwx, 1.0, -dwz));
	vec3 n_view = normalize((INV_VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	NORMAL = n_view;
	float fres = pow(1.0 - clamp(dot(n_view, normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, sky_color, fres * 0.55);
	ROUGHNESS = mix(0.85, 0.2, fres);
	SPECULAR = 0.55;
}
"


func _process(delta: float) -> void:
	_play_time += delta
	if day_night != null:
		day_night.process_frame(delta)
		if streamer != null:
			streamer.set_window_glow(day_night.night_amount)
	if streamer != null and player != null:
		streamer.update_stream(player.position, delta)
		if _loading and streamer.has_ready_at(player.position):
			_loading = false
			if _loading_label != null:
				_loading_label.visible = false
		if _loading_label != null:
			_loading_label.visible = _loading
	if sea != null and player != null:
		# Mar "infinito": acompanha o jogador no plano XZ.
		sea.global_position = Vector3(player.position.x, Cfg.SEA_LEVEL, player.position.z)
	perf_log.sample(delta)


func _on_hud_action(which: String) -> void:
	match which:
		"save":
			save_game()
		"load":
			load_game()


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
