extends Node
## DayNight: relogio do mundo, sol/lua, ceu, nevoa e clima (Fase 1: simples).
##
## 1 hora de jogo = HOUR_SECONDS segundos reais (padrao 60 s => dia de 24 min,
## pensado para sessao curta no celular; ver docs/ROADMAP.md para o ajuste).
## O ceu e procedural (ProceduralSkyMaterial), nao ha cubemap noturno ainda.

const Cfg = preload("res://scripts/core/cfg.gd")

const HOUR_SECONDS := 60.0

var hour := 9.5
var paused := false
var weather := "claro"   # claro | nublado | chuva

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var _weather_timer := 180.0


func setup(sun_light: DirectionalLight3D, moon_light: DirectionalLight3D, environment: Environment) -> void:
	sun = sun_light
	moon = moon_light
	env = environment
	if env != null:
		sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	apply()


## Chamado pelo Main todo frame: avanca o relogio e troca o clima.
## (Nao usa _process para o Main ser a unica fonte de tempo do jogo.)
func process_frame(delta: float) -> void:
	if paused:
		return
	advance(delta / HOUR_SECONDS)
	_weather_timer -= delta
	if _weather_timer <= 0.0:
		_weather_timer = 240.0
		cycle_weather()


## Avanca o relogio em `hours` horas e reaplica iluminacao/ceu.
func advance(hours: float) -> void:
	hour = fposmod(hour + hours, 24.0)
	apply()


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	apply()


func cycle_weather() -> void:
	var order := ["claro", "claro", "nublado", "chuva"]
	var i := order.find(weather)
	weather = order[(i + 1) % order.size()]
	apply()


func apply() -> void:
	var angle := (hour - 6.0) / 12.0 * PI          # 6h leste, 18h oeste
	var sin_e := sin(angle)
	var daylight := smoothstep(-0.18, 0.22, sin_e)
	var dusk := clampf(1.0 - absf(sin_e) * 3.4, 0.0, 1.0)

	var sky_top := Color(0.055, 0.09, 0.17).lerp(Color(0.20, 0.40, 0.72), daylight)
	var horizon := Color(0.10, 0.13, 0.20).lerp(Color(0.68, 0.79, 0.88), daylight)
	horizon = horizon.lerp(Color(0.92, 0.55, 0.33), dusk * 0.55)
	var fog_col := Color(0.12, 0.15, 0.22).lerp(Color(0.70, 0.79, 0.87), daylight)
	fog_col = fog_col.lerp(Color(0.88, 0.58, 0.40), dusk * 0.4)

	if sky_mat != null:
		sky_mat.sky_top_color = sky_top
		sky_mat.sky_horizon_color = horizon
		sky_mat.ground_horizon_color = horizon
		sky_mat.ground_bottom_color = sky_top.darkened(0.5)
		sky_mat.sun_angle_max = 22.0
		sky_mat.sun_curve = 0.12
		sky_mat.energy_multiplier = 1.0
		sky_mat.sky_energy_multiplier = 1.0

	if env != null:
		var fog_base := 0.0011
		if weather == "nublado":
			fog_base = 0.0022
		elif weather == "chuva":
			fog_base = 0.0040
		env.fog_light_color = fog_col
		env.fog_density = fog_base * lerpf(1.5, 1.0, daylight)
		env.ambient_light_color = Color(0.30, 0.36, 0.48).lerp(Color(0.72, 0.78, 0.84), daylight)
		env.ambient_light_energy = lerpf(0.35, 1.0, daylight)
		env.background_energy_multiplier = lerpf(0.55, 1.0, daylight)

	if sun != null:
		if sin_e > -0.08:
			sun.visible = true
			sun.rotation = Vector3(lerpf(-0.06, -1.45, maxf(sin_e, 0.0)), -PI * 0.25, 0.0)
			sun.light_color = Color(1.0, 0.86, 0.68).lerp(Color(1.0, 0.97, 0.92), clampf(daylight * 1.6, 0.0, 1.0))
			var dim := 1.0
			if weather == "nublado":
				dim = 0.55
			elif weather == "chuva":
				dim = 0.35
			sun.light_energy = lerpf(0.0, 1.15, daylight) * dim
			sun.shadow_enabled = daylight > 0.35 and weather == "claro"
		else:
			sun.visible = false

	if moon != null:
		moon.visible = sin_e < 0.05
		moon.rotation = Vector3(-1.0, PI * 0.75, 0.0)
		moon.light_energy = lerpf(0.16, 0.0, daylight)


func state() -> Dictionary:
	return {"hour": hour, "weather": weather}


func restore(data: Dictionary) -> void:
	hour = float(data.get("hour", 9.5))
	weather = String(data.get("weather", "claro"))
	apply()
