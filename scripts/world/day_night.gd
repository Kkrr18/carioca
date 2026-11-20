extends Node
## DayNight: relogio do mundo, sol/lua, ceu e nevoa com a LUZ DO RIO (B-51).
##
## 1 hora de jogo = HOUR_SECONDS segundos reais (dia de 24 min, sessao curta no
## celular; ver docs/ROADMAP.md). O ceu e procedural (ProceduralSkyMaterial),
## sem cubemap e sem shader custom.
##
## A luz nao e um "dia/noite" generico: segue os momentos que fazem o Rio ser
## reconhecivel na tela (paleta em docs/ESTILO.md).
##   - Sol tropical alto (72 graus) e branco-quente, sombra curta e dura;
##   - HORA DOURADA: sol ambar baixo e comprido, horizonte coral e o zenite
##     AINDA azul (e essa separacao de cor que e o por do sol carioca);
##   - HORA AZUL, depois de o sol cair: zenite indigo e horizonte rosa-ambar;
##   - NOITE com brilho de cidade no horizonte: o ceu do Rio nao fica preto;
##   - nevoa maritima com a COR DO HORIZONTE (senao a emenda aparece) e mais
##     densa de madrugada, que e quando a umidade do mar fecha o tempo.
## O sol NASCE NO MAR (e-sudeste) e SE POE SOBRE O CONTINENTE (oeste-noroeste):
## por isso a posicao e um arco de azimute, nao so de altura. Antes ele subia e
## descia sempre no mesmo lugar do ceu, e por isso nao existia por do sol.

const HOUR_SECONDS := 60.0

## Arco do sol no Rio (latitude -23): nasce a 112 graus (leste-sudeste, sobre o
## mar, que fica em z negativo) e se poe a -68 (= 292, oeste-noroeste, sobre o
## continente). O azimute cai de forma continua de 112 a -68, entao ao meio-dia
## ele passa pelo norte, como acontece no hemisferio sul. Azimute medido do
## norte (+Z) para o leste (+X).
const SUN_AZIMUTH_RISE := 112.0
const SUN_AZIMUTH_SET := -68.0
## Altura maxima do sol no verao carioca, em graus (quase em cima da cabeca).
const SUN_MAX_ELEVATION := 72.0
const SUN_ENERGY := 1.30
const MOON_COL := Color(0.62, 0.72, 1.00)

# --- Paleta dos momentos de luz ----------------------------------------------
# Zenite (alto) e horizonte (nevoa) tem paletas SEPARADAS de proposito: um
# gradiente unico de azul para branco e o que fazia o ceu parecer plastico.
const ZENITH_DAY := Color(0.09, 0.31, 0.74)        # azul tropical fundo
const ZENITH_GOLD := Color(0.15, 0.33, 0.66)       # o azul que resiste no alto
const ZENITH_BLUE := Color(0.09, 0.15, 0.42)       # hora azul
const ZENITH_NIGHT := Color(0.020, 0.031, 0.074)
const HORIZON_DAY := Color(0.74, 0.85, 0.93)       # nevoa marinha umida
const HORIZON_GOLD := Color(0.99, 0.60, 0.36)      # coral/ambar
const HORIZON_BLUE := Color(0.84, 0.44, 0.42)      # rosa-ambar da hora azul
const HORIZON_NIGHT := Color(0.125, 0.104, 0.104)  # brilho de cidade no horizonte
const SUN_DAY := Color(1.00, 0.96, 0.89)
const SUN_GOLD := Color(1.00, 0.64, 0.32)
const AMBIENT_DAY := Color(0.72, 0.79, 0.86)
const AMBIENT_GOLD := Color(0.88, 0.68, 0.52)
const AMBIENT_NIGHT := Color(0.15, 0.17, 0.28)

## Quanto vale 1 passo da hora quantizada do ceu (1/50 h = 1,2 s reais).
const SKY_STEPS := 50.0

var hour := 9.5
var paused := false
var weather := "claro"   # claro | nublado | chuva
var night_amount := 0.0  # 0 = dia pleno, 1 = noite fechada (janelas)

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var _weather_timer := 180.0
## Assinatura do ultimo ceu aplicado (hora quantizada). O ceu e a nevoa NAO sao
## reescritos todo quadro: cada mudanca no material do ceu manda o Godot refazer
## o mapa de radiancia do ambiente, e isso pesa no iPhone.
var _last_key := -1


func setup(sun_light: DirectionalLight3D, moon_light: DirectionalLight3D, environment: Environment) -> void:
	sun = sun_light
	moon = moon_light
	env = environment
	if env != null and env.sky != null:
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
	_last_key = -1   # forca o ceu a ser reescrito (a hora pode cair no mesmo passo)
	apply()


func cycle_weather() -> void:
	var order := ["claro", "claro", "nublado", "chuva"]
	var i := order.find(weather)
	weather = order[(i + 1) % order.size()]
	apply()


func apply() -> void:
	var l := look(hour, weather)
	# Sol e lua seguem o relogio SEM escalonar: e o movimento que o jogador ve.
	_aim_lights(l)
	# Ceu, nevoa e pos-processamento: um passo de 1/50 h basta e nao aparece.
	var key := int(floor(hour * SKY_STEPS))
	if key == _last_key:
		return
	_last_key = key
	night_amount = float(l["night"])
	_apply_sky(l)
	_apply_env(l)


# --- Modelo de luz (puro: testado no CI sem GPU) -----------------------------

## Direcao PARA o sol (unitaria) na hora `h`: azimute do arco carioca e altura
## senoidal (0 no nascer, 72 graus ao meio-dia, 0 no por do sol; negativa a
## noite, e ai o sol esta abaixo do horizonte).
static func sun_direction(h: float) -> Vector3:
	var t := clampf((h - 6.0) / 12.0, 0.0, 1.0)
	var elev := deg_to_rad(SUN_MAX_ELEVATION) * sin((h - 6.0) / 12.0 * PI)
	var az := deg_to_rad(lerpf(SUN_AZIMUTH_RISE, SUN_AZIMUTH_SET, t))
	var ce := cos(elev)
	return Vector3(ce * sin(az), sin(elev), ce * cos(az))


## "Look" do ceu e da luz na hora `h`: cores e energias prontas para aplicar.
## Fracoes devolvidas: daylight (0 noite, 1 meio-dia), gold (hora dourada),
## blue (hora azul) e night (0 dia, 1 noite fechada).
static func look(h: float, sky_weather: String) -> Dictionary:
	var to_sun := sun_direction(h)
	var sin_e := to_sun.y
	var daylight := smoothstep(-0.10, 0.30, sin_e)
	var gold := smoothstep(-0.02, 0.10, sin_e) * (1.0 - smoothstep(0.12, 0.45, sin_e))
	var blue := smoothstep(-0.20, -0.05, sin_e) * (1.0 - smoothstep(-0.05, 0.03, sin_e))
	var night := 1.0 - smoothstep(-0.16, 0.05, sin_e)

	var top := ZENITH_NIGHT.lerp(ZENITH_DAY, daylight)
	top = top.lerp(ZENITH_GOLD, gold * 0.85)
	top = top.lerp(ZENITH_BLUE, blue * 0.80)
	var horizon := HORIZON_NIGHT.lerp(HORIZON_DAY, daylight)
	horizon = horizon.lerp(HORIZON_GOLD, gold)
	horizon = horizon.lerp(HORIZON_BLUE, blue * 0.85)

	var ambient := AMBIENT_NIGHT.lerp(AMBIENT_DAY, daylight)
	ambient = ambient.lerp(AMBIENT_GOLD, gold * 0.75)

	# Nevoa: um tico mais clara que o horizonte (ar umido em suspensao) e mais
	# densa de madrugada, quando a umidade do mar fecha o tempo.
	var fog := horizon.lerp(Color(0.94, 0.96, 0.98), 0.10 + 0.10 * daylight)
	var maritime := 1.0 - smoothstep(0.10, 0.65, sin_e)
	var fog_density := lerpf(0.0009, 0.0016, maritime)

	# Ceu mais "fechado" no nublado e na chuva: menos sol, mais nevoa e cor
	# puxada para o cinza-azulado da frente fria.
	var dim := 1.0
	if sky_weather == "nublado":
		dim = 0.58
		fog_density *= 2.0
		fog = fog.lerp(Color(0.62, 0.65, 0.70), 0.45)
		horizon = horizon.lerp(Color(0.62, 0.65, 0.70), 0.35)
	elif sky_weather == "chuva":
		dim = 0.34
		fog_density *= 3.4
		fog = fog.lerp(Color(0.44, 0.47, 0.52), 0.60)
		horizon = horizon.lerp(Color(0.44, 0.47, 0.52), 0.50)

	# Gradiente do ceu: curto de dia (ceu limpo) e bem longo na hora dourada.
	var sky_curve := lerpf(0.18, 0.11, daylight)
	sky_curve = lerpf(sky_curve, 0.05, maxf(gold, blue))

	return {
		"to_sun": to_sun,
		"moon_dir": sun_direction(fposmod(h + 12.6, 24.0)),
		"top": top,
		"horizon": horizon,
		"fog": fog,
		"fog_density": fog_density,
		"ambient": ambient,
		"ambient_energy": lerpf(0.65, 1.05, daylight),
		"sky_contribution": lerpf(0.30, 0.80, daylight),
		"sun_color": SUN_GOLD.lerp(SUN_DAY, smoothstep(0.04, 0.45, sin_e)),
		"sun_energy": SUN_ENERGY * smoothstep(-0.03, 0.18, sin_e) * dim,
		"moon_energy": lerpf(0.22, 0.0, daylight),
		"exposure": lerpf(1.30, 1.02, daylight),
		"glow": lerpf(0.70, 0.34, daylight),
		"bloom": lerpf(0.20, 0.04, daylight),
		"sky_curve": sky_curve,
		"sun_angle": lerpf(20.0, 13.0, daylight),
		"daylight": daylight,
		"gold": gold,
		"blue": blue,
		"night": night,
	}


## Base de um no de luz para o astro em `to_dir`: em Godot a luz viaja no -Z do
## no, entao o +Z aponta para o astro. Serve para o sol e para a lua.
static func aim_basis(to_dir: Vector3) -> Basis:
	if to_dir.length() < 0.0001:
		return Basis()
	var z_axis := to_dir.normalized()
	var x_axis := Vector3.UP.cross(z_axis)
	if x_axis.length() < 0.0001:
		x_axis = Vector3.RIGHT   # astro exatamente no zenite: eixo X de reserva
	x_axis = x_axis.normalized()
	var y_axis := z_axis.cross(x_axis)
	return Basis(x_axis, y_axis, z_axis)


static func aim_light(light: DirectionalLight3D, to_dir: Vector3) -> void:
	light.basis = aim_basis(to_dir)


# --- Aplicacao na cena -------------------------------------------------------

func _aim_lights(l: Dictionary) -> void:
	if sun != null:
		var to_sun: Vector3 = l["to_sun"]
		sun.visible = to_sun.y > -0.06
		if sun.visible:
			aim_light(sun, to_sun)
			_write(sun, "light_color", l["sun_color"])
			_write(sun, "light_energy", l["sun_energy"])
		# Sombra sempre que o sol ilumina de verdade: a sombra comprida da hora
		# dourada e metade da beleza do por do sol. Na chuva, fora (custo).
		sun.shadow_enabled = float(l["daylight"]) > 0.12 and weather != "chuva"
	if moon != null:
		var to_moon: Vector3 = l["moon_dir"]
		moon.visible = to_moon.y > 0.04
		if moon.visible:
			aim_light(moon, to_moon)
			_write(moon, "light_color", MOON_COL)
			_write(moon, "light_energy", l["moon_energy"])


func _apply_sky(l: Dictionary) -> void:
	if sky_mat == null:
		return
	var top: Color = l["top"]
	var horizon: Color = l["horizon"]
	_write(sky_mat, "sky_top_color", top)
	_write(sky_mat, "sky_horizon_color", horizon)
	_write(sky_mat, "ground_horizon_color", horizon)
	_write(sky_mat, "ground_bottom_color", top.darkened(0.55))
	_write(sky_mat, "sky_curve", l["sky_curve"])
	_write(sky_mat, "ground_curve", 0.02)
	_write(sky_mat, "sun_angle_max", l["sun_angle"])
	_write(sky_mat, "sun_curve", 0.11)
	_write(sky_mat, "energy_multiplier", 1.0)
	_write(sky_mat, "sky_energy_multiplier", 1.0)


func _apply_env(l: Dictionary) -> void:
	if env == null:
		return
	_write(env, "fog_light_color", l["fog"])
	_write(env, "fog_density", l["fog_density"])
	_write(env, "fog_sky_affect", 0.65)
	_write(env, "ambient_light_color", l["ambient"])
	_write(env, "ambient_light_energy", l["ambient_energy"])
	# De dia a luz do ambiente vem do ceu; a noite, boa parte e a cor da cidade
	# (o ceu ja esta escuro, e sem isso a rua some).
	_write(env, "ambient_light_sky_contribution", l["sky_contribution"])
	_write(env, "background_energy_multiplier", lerpf(0.75, 1.0, float(l["daylight"])))
	_write(env, "tonemap_exposure", l["exposure"])
	_write(env, "glow_intensity", l["glow"])
	_write(env, "glow_bloom", l["bloom"])


## Atribui uma propriedade so quando ela muda de verdade (ver _last_key).
static func _write(obj: Object, prop: String, value: Variant) -> void:
	var cur: Variant = obj.get(prop)
	if cur is Color and value is Color:
		if (cur as Color).is_equal_approx(value as Color):
			return
	elif cur is float and value is float:
		if absf(float(cur) - float(value)) < 0.0005:
			return
	elif cur == value:
		return
	obj.set(prop, value)


func state() -> Dictionary:
	return {"hour": hour, "weather": weather}


func restore(data: Dictionary) -> void:
	hour = float(data.get("hour", 9.5))
	weather = String(data.get("weather", "claro"))
	_last_key = -1
	apply()
