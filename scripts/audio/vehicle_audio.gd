extends Node
## Som do carro e da cidade (Fase 4): motor sintetizado em codigo + um impacto
## CC0 baixado.
##
## Por que sintetizar em vez de baixar: nao existe loop de motor CC0 em .wav ou
## .mp3 com URL direta (pesquisa de 2026-11); os loops livres que existem sao
## .ogg, que o Safari do iPhone nao decodifica. E um arquivo fixo nao acompanha a
## velocidade — aqui o tom sobe com o giro, que e o que faz o carro parecer vivo.
## O unico arquivo baixado e a batida (thud2.wav, CC0, BMacZero, OpenGameArt).
##
## O Safari so libera audio depois do primeiro toque na tela; o Godot retoma o
## AudioContext nesse momento, entao o som "acorda" no primeiro comando.
##
## Custo: a tabela do motor e preenchida uma vez; por amostra so ha uma leitura
## de tabela e um filtro de ruido, porque chamar sin() 700 vezes por quadro no
## iPhone custaria mais que o desenho da cidade.

const MIX_RATE := 22050.0
const TABLE_SIZE := 512
const IDLE_HZ := 26.0
const MAX_HZ := 96.0
const MAX_SPEED := 22.0      # igual a car.gd (m/s)
const IMPACT_PATH := "res://assets/sounds/impact.wav"

var car = null               # car.gd: velocidade e acelerador vem daqui
var enabled := true

var _stream: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _table := PackedFloat32Array()
var _phase := 0.0
var _noise := 0.0
var _rng := RandomNumberGenerator.new()
var _started := false
var _tries := 0
var _retry := 0.0


func _ready() -> void:
	_rng.seed = 20260922
	_table = engine_table()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	_stream = AudioStreamPlayer.new()
	_stream.name = "Engine"
	_stream.stream = gen
	_stream.volume_db = -8.0
	add_child(_stream)
	_impact = AudioStreamPlayer.new()
	_impact.name = "Impact"
	_impact.stream = load_impact()
	_impact.volume_db = -4.0
	add_child(_impact)
	if _impact.stream == null:
		push_warning("VehicleAudio: %s nao carregou" % IMPACT_PATH)
	# NAO chamar play() aqui: no build web o AudioContext ainda esta suspenso (o
	# Safari exige um toque), e o Godot imprime "is trying to play a sample from
	# a stream that cannot be sampled" e o motor fica mudo (B-42). O som comeca
	# no primeiro toque, em _input.


# --- Nucleo puro (testado em tests/runner.gd) --------------------------------

## Frequencia do motor (Hz) para uma fracao de velocidade 0..1. Marcha lenta
## grave e subida linear ate o giro alto.
static func engine_hz(ratio: float) -> float:
	return lerpf(IDLE_HZ, MAX_HZ, clampf(ratio, 0.0, 1.0))


## Tabela do motor: fundamental + harmonicos, normalizada em 1.0. Ler a tabela
## (em vez de chamar sin() por amostra) e o que deixa a sintese barata.
static func engine_table() -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE_SIZE)
	var peak := 0.0
	for i in TABLE_SIZE:
		var x := float(i) / float(TABLE_SIZE)
		var v := 0.0
		v += sin(TAU * x) * 0.60
		v += sin(TAU * x * 2.0) * 0.30
		v += sin(TAU * x * 3.0) * 0.16
		v += sin(TAU * x * 5.0) * 0.08
		t[i] = v
		peak = maxf(peak, absf(v))
	peak = maxf(peak, 0.001)
	for i in TABLE_SIZE:
		t[i] = t[i] / peak
	return t


## Pitch do impacto: batida forte soa mais grave e mais alta.
static func impact_pitch(strength: float) -> float:
	return lerpf(1.25, 0.85, clampf(strength, 0.0, 1.0))


static func load_impact() -> AudioStream:
	if not ResourceLoader.exists(IMPACT_PATH):
		return null
	var res: Resource = load(IMPACT_PATH)
	if res is AudioStream:
		return res as AudioStream
	return null


# --- Cena --------------------------------------------------------------------

func start() -> void:
	_start_stream()


## Estado do som para a telemetria: sem isso, "nao tem som" e um mistério.
func describe() -> String:
	if _playback != null:
		return "som: motor sintetizado ligado"
	if _started:
		return "som: sem audio neste navegador (%d tentativas)" % _tries
	return "som: toque na tela para ligar"


## O Safari so libera audio depois de um gesto. Cada toque/tecla tenta ligar o
## motor de novo, ate conseguir (ou ate desistir, para nao gastar quadro).
func _input(event: InputEvent) -> void:
	if _playback != null:
		return
	var press := false
	if event is InputEventScreenTouch:
		press = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		press = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		press = (event as InputEventKey).pressed
	if press:
		_start_stream()


func _start_stream() -> void:
	if _stream == null or _tries >= 8:
		return
	_started = true
	_tries += 1
	if _stream.playing:
		_stream.stop()
	_stream.play()
	_playback = _stream.get_stream_playback() as AudioStreamGeneratorPlayback


## Batida (ligada ao signal crashed do carro).
func crash(strength: float) -> void:
	if _impact == null or _impact.stream == null:
		return
	_impact.pitch_scale = impact_pitch(strength)
	_impact.volume_db = lerpf(-10.0, -2.0, clampf(strength, 0.0, 1.0))
	_impact.play()


func _process(_delta: float) -> void:
	if not enabled:
		return
	if _playback == null:
		# Sem toque ainda, ou o navegador recusou: tenta de novo a cada 0,5 s,
		# algumas vezes, em vez de insistir a cada quadro.
		_retry -= _delta
		if _started and _tries < 8 and _retry <= 0.0:
			_retry = 0.5
			_start_stream()
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var ratio := 0.0
	var gas := 0.0
	var driving := false
	if car != null:
		driving = bool(car.occupied)
		ratio = clampf(absf(float(car.speed)) / MAX_SPEED, 0.0, 1.0)
		gas = clampf(absf(float(car.input_throttle)), 0.0, 1.0)
	var inc := engine_hz(ratio) / MIX_RATE
	var amp := (0.10 + 0.20 * ratio + 0.08 * gas) if driving else 0.0
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		_phase = fmod(_phase + inc, 1.0)
		var sample := 0.0
		if amp > 0.0:
			sample += _table[int(_phase * float(TABLE_SIZE)) & (TABLE_SIZE - 1)] * amp
		# Ruido filtrado: cidade e vento atras do motor.
		_noise = lerpf(_noise, _rng.randf_range(-1.0, 1.0), 0.03)
		sample += _noise * 0.06
		sample = clampf(sample, -0.9, 0.9)
		buf[i] = Vector2(sample, sample)
	_playback.push_buffer(buf)
