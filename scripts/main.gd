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
const VehiclePhysics = preload("res://scripts/vehicles/vehicle_physics.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const SectorStreamer = preload("res://scripts/world/sector_streamer.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const Player = preload("res://scripts/player/player.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")
const Traffic = preload("res://scripts/world/traffic.gd")
const Pedestrians = preload("res://scripts/world/pedestrians.gd")
const PropField = preload("res://scripts/physics/prop_field.gd")
const VehicleAudio = preload("res://scripts/audio/vehicle_audio.gd")
const PerfLog = preload("res://scripts/core/perf_log.gd")
const Police = preload("res://scripts/world/police.gd")
const MissionRunner = preload("res://scripts/game/mission_runner.gd")
const GtaHud = preload("res://scripts/ui/gta_hud.gd")
const Ipanema = preload("res://scripts/game/ipanema.gd")
const Wanted = preload("res://scripts/game/wanted.gd")

const SPAWN := Vector3(1600.0, 1.2, 100.0)

var world_seed: int = 20260922
var environment: Environment
var sea: MeshInstance3D
## Faixa de espuma da arrebentacao (B-81), logo acima do nivel do mar.
var surf: MeshInstance3D
## Material do mar: o offset de UV das ondas e animado em _process.
var _sea_mat: StandardMaterial3D
var _surf_mat: StandardMaterial3D
var _wave_t := 0.0
var streamer = null
var player = null
var car = null
var day_night = null
var hud = null
var perf_log = null
var touch = null
var model_prop = null
var traffic = null
var pedestrians = null
var props = null
var audio = null
var _audio_note := ""
## Nome da loja em que o jogador esta (vazio = na rua). B-66.
var _shop_here := ""

# --- O "jogo" (policia, missoes e HUD do GTA) --------------------------------
var police = null
var missions = null
var gta = null
## Posicao do foco do mundo (o carro quando dirigindo, senao o personagem).
var _focus := Vector3.ZERO
## Tempo restante da tela de WASTED/BUSTED (0 = jogando).
var _respawn_t := 0.0
var _pending := ""

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
	# B-67: a ficha do veiculo vem de vehicle_physics.gd. Trocar esta linha por
	# VehiclePhysics.compact() ou suv() muda massa, motor, cambio e pneus de uma
	# vez — e o HUD passa a mostrar esses numeros.
	car.vehicle_spec = VehiclePhysics.sedan()
	car.model_path = "res://assets/models/quaternius-car.glb"
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
	# Transito basico (Fase 4): carros de passeio na grade de ruas, em volta do
	# jogador. Cada modelo vira uma malha unica (um desenho por modelo).
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(world_seed, player.position)
	car.traffic = traffic
	# Pedestres (B-53): gente que anda na calcada, espera o sinal, atravessa,
	# desvia de voce e corre de carro. Tres MultiMesh para todo mundo.
	pedestrians = Pedestrians.new()
	pedestrians.name = "Pedestrians"
	# O streamer e quem sabe onde estao as lojas (balconistas, B-66).
	pedestrians.streamer = streamer
	add_child(pedestrians)
	pedestrians.setup(world_seed, player.position)

	# Fisica ambiental (B-69): caixas, cadeiras, lixeiras e cones com massa,
	# impulso, atrito por piso, dano em 3 estados e destrocos — sobre o MESMO
	# chao analitico do carro (sem RigidBody3D). O carro atropela, e andando a pe
	# o personagem empurra. Ver docs/FISICA.md.
	props = PropField.new()
	props.name = "Props"
	add_child(props)
	props.setup(world_seed, streamer, player.position)
	props.car = car

	hud.set_model_note(model_prop.describe() + "\n" + traffic.describe()
			+ "\n" + pedestrians.describe() + "\n" + props.describe()
			+ "\n" + player.describe())

	# --- Policia (estrelas), missoes e o HUD do jogo --------------------------
	# A ordem importa: o HUD le player, police e missions; o roteiro das missoes
	# le a policia (para acender estrelas no meio do servico).
	_boot_step("policia")
	police = Police.new()
	police.name = "Police"
	police.player = player
	police.streamer = streamer
	police.car = car
	add_child(police)

	_boot_step("missoes")
	missions = MissionRunner.new()
	missions.name = "Missions"
	missions.player = player
	missions.police = police
	add_child(missions)

	_boot_step("hud do jogo")
	var gta_layer := CanvasLayer.new()
	gta_layer.name = "GtaLayer"
	gta_layer.layer = 3
	add_child(gta_layer)
	gta = GtaHud.new()
	gta.name = "GtaHud"
	gta_layer.add_child(gta)
	gta.setup(player, police, missions)
	missions.hud = gta
	gta.debug_toggled.connect(_on_debug_toggled)
	# A telemetria comeca escondida: a tela e a do jogo. Volta no botao DEV.
	hud.set_debug_visible(false)

	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	police.shot_fired.connect(_on_cop_shot)
	police.busted.connect(_on_busted)
	police.heat_changed.connect(_on_heat_changed)
	police.cop_down.connect(_on_cop_down)
	missions.started.connect(_on_mission_started)
	missions.finished.connect(_on_mission_finished)

	# Som (Fase 4): motor sintetizado que sobe de tom com o giro + impacto CC0.
	_boot_step("som")
	audio = VehicleAudio.new()
	audio.name = "VehicleAudio"
	audio.car = car
	add_child(audio)
	car.crashed.connect(_on_car_crashed)
	# Impacto nos objetos fisicos usa o MESMO som de batida (impact.wav, CC0).
	props.bumped.connect(_on_prop_bumped)

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
	if gta != null:
		gta.banner("CARIOCA\nIPANEMA", 3.2)
	_notify("Ipanema. O marcador amarelo e a proxima missao.")


func _build_environment() -> void:
	# B-75: no iPhone em retrato o "viewport + expand" desenha 1280x2770 (~3,5 MP)
	# para uma tela de ~0,3 MP de CSS. O print do aparelho mostrou o jogo
	# limitado por PIXEL: 19 FPS na praia com 147 draw calls, contra 30 FPS na
	# cidade com 327. No modo viewport o `content_scale_factor` divide a
	# resolucao de render (ver Cfg.render_scale), e o layout nao muda.
	get_tree().root.content_scale_factor = Cfg.render_scale(get_window().size)
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
	# Glow (B-52): o buffer de glow e meia resolucao, entao glow alto e bloom
	# jogam um granulado grosso em volta de TUDO que e claro. Threshold 1,35
	# deixa so o que realmente brilha (sol, lampada, janela) pegar halo.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.02
	# Ajuste de cor (B-81): um tico de contraste e de saturacao tira o "cinza de
	# motor" das fachadas e da areia. E o mesmo passe de tonemap, sem custo de
	# geometria.
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.14
	environment.adjustment_brightness = 1.0
	environment.glow_enabled = true
	# Menos halo e limiar mais alto: o buffer do glow e de meia resolucao e,
	# com a camera em movimento, o halo tremia em volta de tudo que e claro
	# (o granulado em movimento que o autor viu). So o que brilha de verdade
	# (sol, lampada, janela acesa) pega halo agora.
	environment.glow_intensity = 0.12
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.55

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
	# As emendas entre os splits apareciam como uma faixa reta, mais clara,
	# cortando o calcadao em diagonal (B-59). Com os splits longe da camera a
	# emenda sai do primeiro plano e a resolucao perto do jogador continua alta.
	_sun.directional_shadow_split_1 = 0.45
	_sun.directional_shadow_split_2 = 0.75
	_sun.directional_shadow_max_distance = Cfg.SUN_SHADOW_DISTANCE
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
	# vem de roughness + specular com o sol do dia/noite.
	# Roughness MUITO baixa (0,12) em 60 km de plano virava brilho de sol ponto a
	# ponto, que na tela parece granulado piscando: 0,30 espalha o brilho (B-52).
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.26, 0.38)
	m.roughness = 0.30
	m.metallic = 0.0
	m.metallic_specular = 0.45
	m.disable_receive_shadows = true
	# Ondas (B-80): mapa de normais gerado em codigo — shader custom no mar
	# congelou o render no Safari/WebGL (B-25), entao a ondulacao vem de um
	# normal map num StandardMaterial3D. Sem ele o mar era um espelho perfeito e
	# o horizonte parecia uma chapa de metal azul.
	m.normal_enabled = true
	m.normal_texture = _wave_normal_texture(96)
	m.normal_scale = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_scale = Vector3(1600.0, 1600.0, 1.0)
	m.uv1_offset = Vector3.ZERO
	_sea_mat = m
	sea.material_override = m
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# Espuma da arrebentacao (B-81): uma faixa fina na linha da agua, com
	# textura de espuma gerada em codigo e offset de UV animado. Sem ela a praia
	# termina numa emenda reta entre areia e mar.
	var foam := PlaneMesh.new()
	foam.size = Vector2(30000.0, 18.0)
	foam.subdivide_width = 1
	foam.subdivide_depth = 1
	surf = MeshInstance3D.new()
	surf.name = "Surf"
	surf.mesh = foam
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_texture = _foam_texture(128, 64)
	fm.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	fm.uv1_scale = Vector3(300.0, 1.0, 1.0)
	fm.disable_receive_shadows = true
	_surf_mat = fm
	surf.material_override = fm
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surf)
	surf.global_position = Vector3(SPAWN.x, Cfg.SEA_LEVEL + 0.05, 30.0)


## Textura de espuma do mar (B-81), gerada em codigo: duas faixas que se
## quebram em bolhas, com alfa que some nas duas bordas da faixa. Repete sem
## emenda (as senoides tem periodo inteiro na textura).
static func _foam_texture(size: int, h: int) -> ImageTexture:
	var img := Image.create(size, h, true, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / float(maxi(1, h - 1))
		# A espuma vive no meio da faixa: nas bordas o alfa morre, senao a
		# emenda aparece como uma linha branca reta no mar.
		var edge := smoothstep(0.0, 0.30, v) * (1.0 - smoothstep(0.62, 1.0, v))
		for x in size:
			var u := float(x) / float(size)
			var band := sin((u * 3.0 + v * 1.0) * TAU) * 0.5 + 0.5
			var streaks := sin((u * 11.0 - v * 2.0) * TAU) * 0.5 + 0.5
			var a := edge * (0.30 + 0.70 * band * streaks)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Mapa de normais das ondas, gerado em codigo: tres senoides em alturas e a
## diferenca entre vizinhos virada em normal (escala de cinza -> RGB). Repete
## sem emenda porque as senoides tem periodo inteiro na textura.
static func _wave_normal_texture(size: int) -> ImageTexture:
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var u := float(x) / float(size)
			var v := float(y) / float(size)
			var hh := sin((u * 2.0 + v * 1.0) * TAU) * 0.55
			hh += sin((u * 5.0 - v * 4.0) * TAU) * 0.28
			hh += sin((u * 11.0 + v * 9.0) * TAU) * 0.12
			heights[y * size + x] = hh
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var strength := 2.6
	for y in size:
		for x in size:
			var hl := heights[y * size + posmod(x - 1, size)]
			var hr := heights[y * size + posmod(x + 1, size)]
			var hd := heights[posmod(y - 1, size) * size + x]
			var hu := heights[posmod(y + 1, size) * size + x]
			var nx := (hl - hr) * strength
			var ny := (hd - hu) * strength
			var nz := 1.0
			var inv := 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
			img.set_pixel(x, y, Color(nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5,
					nz * inv * 0.5 + 0.5, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_play_time += delta
	# WASTED/BUSTED: a tela manda, o controle volta no fim da contagem.
	if _respawn_t > 0.0:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_finish_respawn()
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
	_focus = focus
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
		# Ondas andando devagar (B-80): 1 tile a cada ~4 min. Nao e correnteza,
		# e o minimo para o mar nao parecer uma foto.
		if _sea_mat != null:
			_wave_t += delta
			_sea_mat.uv1_offset = Vector3(_wave_t * 0.004, _wave_t * 0.0025, 0.0)
		# Espuma: acompanha o jogador no eixo X (a praia corre de leste a oeste)
		# e sobe/desce na faixa, como a agua lavando a areia.
		if surf != null:
			surf.global_position = Vector3(focus.x, Cfg.SEA_LEVEL + 0.05, 30.0)
			if _surf_mat != null:
				_surf_mat.uv1_offset = Vector3(-_wave_t * 0.012,
						sin(_wave_t * 0.35) * 0.18, 0.0)
	# Loja (B-66): ao entrar no vao, o HUD diz o nome do comercio. A comparacao
	# evita repetir o aviso a cada quadro; sair da loja so zera o estado.
	if streamer != null and player != null and hud != null:
		var here := ""
		var best := 6.0
		for s in streamer.shops_near(player.position, 6.0):
			var d: Dictionary = s
			var f: Vector3 = d["front"]
			var dist := Vector2(f.x - player.position.x, f.z - player.position.z).length()
			if dist < best:
				best = dist
				here = String(d.get("name", ""))
		if here != _shop_here:
			_shop_here = here
			if here != "":
				_notify(here)
	# Carro: o TouchControls desenha e trata o botao ENTRAR/SAIR (B-38: no iPhone
	# o toque em Button do Godot nao chegava ao jogo) e, dirigindo, troca
	# PULAR/CORRER por ACEL/FREIO.
	if car != null and touch != null and player != null:
		if touch.is_driving() != car.occupied:
			touch.set_driving(car.occupied)
		var near: bool = player.position.distance_to(car.global_position) < Car.PROXIMITY
		# Roubo de carro: o botao ENTRAR tambem aparece perto de carro de rua.
		if not near and not car.occupied and traffic != null:
			near = not traffic.car_near(player.position, 7.0).is_empty()
		touch.set_car_state(near or car.occupied, car.occupied)
		if touch.take_car_press():
			_on_hud_action("car")
		# Combate a pe: TROCAR troca a arma, BATER/ATIRAR ataca na direcao da
		# camera. Segurar o botao mantem o fogo no ritmo da arma (cooldown nela).
		touch.set_armed(player.armed())
		if touch.take_weapon_press():
			player.swap_weapon()
			_notify("Arma: %s" % player.weapon_label())
		var want_fire: bool = touch.take_fire_press() or TouchControls.fire_held()
		if want_fire and not car.occupied:
			_player_fire()
	if traffic != null:
		traffic.update(delta, focus)
	if pedestrians != null and player != null:
		# Posicao/velocidade do carro alimentam o panico dos pedestres na
		# travessia; a hora do dia decide quanta gente esta na rua.
		var car_pos := Vector3.ZERO
		var car_speed := 0.0
		if car != null:
			car_pos = car.global_position
			car_speed = absf(car.speed) if car.occupied else 0.0
		pedestrians.update(delta, focus, player.position, car_pos, car_speed,
				day_night.hour if day_night != null else 12.0)
	# Objetos fisicos (B-69): integracao, LOD 35/100 m, sono, atropelamento,
	# destrocos e desenho (3 MultiMesh para tudo).
	if props != null:
		props.update(delta, focus)
	# Policia, missoes e HUD do jogo: o procurado esfria longe dos olhos, as
	# viaturas perseguem, o roteiro avanca e o radar aponta o alvo.
	if police != null:
		police.update(delta, focus)
	if missions != null:
		missions.update(delta, focus)
	if gta != null and player != null:
		var view_yaw: float = player.cam_yaw
		if car != null and car.occupied:
			view_yaw = car.rotation.y
		gta.update_focus(focus, view_yaw)
	# Estado do som na telemetria: e por esta linha que se sabe, no aparelho, se
	# o Safari liberou o audio (B-42).
	if audio != null and hud != null:
		var note: String = audio.describe()
		if note != _audio_note:
			_audio_note = note
			var all := ""
			if model_prop != null:
				all = model_prop.describe()
			if traffic != null:
				all += "\n" + traffic.describe()
			if pedestrians != null:
				all += "\n" + pedestrians.describe()
			if props != null:
				all += "\n" + props.describe()
			if player != null:
				all += "\n" + player.describe()
			hud.set_model_note(all + "\n" + note)
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
				_notify("Voce saiu do carro.")
				return
			# Roubo de carro: se um carro de RUA esta mais perto que o seu, e ele
			# que voce leva (o "carjack" do GTA). A cidade nao fica com buraco:
			# o carro tomado volta a circular longe, 30 s depois.
			var own_d: float = player.position.distance_to(car.global_position)
			if traffic != null:
				var stolen: Dictionary = traffic.car_near(player.position, 7.0)
				if not stolen.is_empty():
					var sd: float = player.position.distance_to(stolen["pos"])
					if sd < own_d:
						_steal_car(stolen)
						return
			# Rede de seguranca: o botao de contexto so aparece dentro de
			# Car.PROXIMITY, mas a distancia pode mudar entre o desenho do
			# botao e o toque. Se estiver longe, o jogador vai para o lado do
			# carro antes de entrar (B-36).
			if own_d > Car.PROXIMITY:
				var side := Vector3(cos(car.rotation.y), 0.0, -sin(car.rotation.y))
				player.teleport(car.global_position + side * 2.4)
			car.toggle_occupant()
			_notify("Volante no joystick, ACEL acelera, FREIO freia/da re.")


func _on_car_crashed(strength: float) -> void:
	if audio != null:
		audio.crash(strength)


## Bateu em caixa/lixeira/cone (B-69): som de impacto mais leve que o de carro.
## `surface` ja vem com a etiqueta do material do piso (asfalto/areia/pedra...) e
## fica pronta para quando houver amostras por material.
func _on_prop_bumped(strength: float, _surface: String) -> void:
	if audio != null:
		audio.crash(clampf(strength, 0.1, 1.0) * 0.7)


# --- Jogo: policia, missoes, combate e WASTED/BUSTED --------------------------

## Aviso curto na tela do jogo (o toast da telemetria fica escondido).
func _notify(msg: String) -> void:
	if gta != null:
		gta.toast(msg)
	elif hud != null:
		hud.toast(msg)


## BATER/ATIRAR na direcao da camera. O alvo e a policia: e ela que persegue o
## jogador, e acertar viatura e o que aperta o cerco.
func _player_fire() -> void:
	if player == null or police == null or not player.alive():
		return
	if car != null and car.occupied:
		return
	if not player.can_fire():
		return
	var data: Dictionary = player.weapon_data()
	var from: Vector3 = player.global_position + Vector3(0.0, 1.25, 0.0)
	var dir: Vector3 = player.aim_dir()
	player.consume_fire()
	var hit: Dictionary = police.damage_nearest(from, dir, float(data["range"]),
			float(data["cone"]), float(data["damage"]))
	if hit.is_empty():
		return
	police.report_crime("tiro" if player.armed() else "agressao")


## Toma o carro de rua: o carro do jogador passa a ser aquele (modelo, ficha e
## posicao), como no GTA.
func _steal_car(info: Dictionary) -> void:
	if car == null or traffic == null or player == null:
		return
	var taken: Dictionary = traffic.take_car(int(info.get("index", -1)))
	if taken.is_empty():
		return
	var mi := clampi(int(taken.get("model", 0)), 0, Traffic.MODEL_PATHS.size() - 1)
	var spec: Dictionary = taken.get("spec", {})
	var length := float(taken.get("length", 4.2))
	var pos: Vector3 = taken["pos"]
	var yaw := float(taken.get("yaw", 0.0))
	car.global_position = Vector3(pos.x, Cfg.surface_at(pos.x, pos.z), pos.z)
	car.rotation = Vector3(0.0, yaw, 0.0)
	car.set_vehicle(String(Traffic.MODEL_PATHS[mi]), spec, length)
	if police != null:
		police.report_crime("carro_tomado")
	car.toggle_occupant()
	_notify("Carro tomado: %s" % String(spec.get("name", "carro")))


func _on_player_damaged(amount: float) -> void:
	if gta != null:
		gta.flinch(amount * 0.02)


func _on_cop_shot(_from: Vector3) -> void:
	if gta != null:
		gta.flinch(0.12)


func _on_player_died() -> void:
	if _respawn_t > 0.0:
		return
	_pending = "wasted"
	_respawn_t = 2.8
	if car != null and car.occupied:
		car.toggle_occupant()
	if player != null:
		player.enabled = false
	if gta != null:
		gta.show_state("WASTED", 2.8)


func _on_busted() -> void:
	if _respawn_t > 0.0:
		return
	_pending = "busted"
	_respawn_t = 2.8
	if car != null and car.occupied:
		car.toggle_occupant()
	if player != null:
		player.enabled = false
	if gta != null:
		gta.show_state("BUSTED", 2.8)


## Fim da contagem: volta na delegacia (preso) ou no hospital (morto), com
## multa proporcional ao dinheiro. A cidade esquece o crime.
func _finish_respawn() -> void:
	var busted := _pending == "busted"
	_pending = ""
	if police != null:
		police.clear()
	if missions != null:
		missions.abort()
	if player == null:
		return
	var loss := 0
	if busted:
		loss = Wanted.busted_fine(player.money)
		player.revive(60.0)
	else:
		loss = int(float(player.money) * 0.15)
		player.revive(100.0)
	player.add_money(-loss)
	player.enabled = true
	player.visible = true
	var where := "delegacia" if busted else "hospital"
	player.teleport(Ipanema.place(where) + Vector3(6.0, 0.0, 6.0))
	if player.camera != null:
		player.camera.current = true
	if gta != null:
		if loss > 0:
			gta.toast("Voce perdeu R$ %d" % loss)
		else:
			gta.toast("De volta a rua.")


func _on_heat_changed(_heat: float, stars: int) -> void:
	if gta == null or stars <= 0:
		return
	gta.banner(Wanted.wanted_line(stars), 1.8)


func _on_cop_down() -> void:
	if police != null:
		police.report_crime("policial_morto")
	if gta != null:
		gta.toast("Viatura fora de combate.")


func _on_mission_started(title: String) -> void:
	if gta != null:
		gta.banner("MISSAO\n" + title, 2.4)


func _on_mission_finished(title: String, reward: int) -> void:
	if player != null:
		player.add_money(reward)
	if gta != null:
		gta.banner("%s CUMPRIDA\n+ R$ %d" % [title, reward], 3.0)


func _on_debug_toggled(on: bool) -> void:
	if hud != null:
		hud.set_debug_visible(on)


func collect_state() -> Dictionary:
	var state := {
		"world_seed": world_seed,
		"player": player.state(),
		"clock": day_night.state(),
		"play_time": _play_time,
		"missions": {"index": missions.mission_index} if missions != null else {},
		"wanted": {"heat": police.heat} if police != null else {},
	}
	return state


func save_game() -> void:
	var ok: bool = SaveManager.save_state(collect_state())
	if ok:
		_notify("Jogo salvo.")
	else:
		_notify("Falha ao salvar: %s" % SaveManager.last_error)


func load_game() -> void:
	var state: Dictionary = SaveManager.load_state()
	if state.is_empty():
		_notify("Falha ao carregar: %s" % SaveManager.last_error)
		return
	var p: Dictionary = state.get("player", {})
	player.restore(p)
	var clock: Dictionary = state.get("clock", {})
	day_night.restore(clock)
	_play_time = float(state.get("play_time", 0.0))
	if missions != null:
		var m: Dictionary = state.get("missions", {})
		missions.mission_index = maxi(0, int(m.get("index", 0)))
		missions.abort()
	if police != null:
		police.clear()
	_notify("Jogo carregado (schema %d)" % int(state.get("schema", 0)))


## Teletransporte (usado por testes manuais e pela Fase 6).
func teleport(pos: Vector3) -> void:
	player.teleport(pos)


func dump_perf_log() -> String:
	return perf_log.dump_csv()
