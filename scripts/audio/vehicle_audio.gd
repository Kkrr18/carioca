extends Node
## Som do carro e da cidade (Fase 4): motor em loop gerado em codigo + impacto
## CC0 baixado.
##
## B-74: o motor usava `AudioStreamGenerator` (buffer preenchido a cada quadro).
## No iPhone de verdade o console mostrava, ao entrar no carro:
##   WARNING: /root/Main/VehicleAudio/Engine is trying to play a sample from a
##   stream that cannot be sampled. at: play_basic (audio_stream_player_internal)
## e o motor ficava mudo. Era o mesmo sintoma do B-42/B-61, que eu tinha
## "consertado" enchendo o buffer antes do play: a causa nao era buffer vazio —
## no build Web o gerador nao e amostravel. Agora o motor e um `AudioStreamWAV`
## de 1,5 s GERADO UMA VEZ no _ready, em loop, e o giro vira `pitch_scale`.
## Ganhos: sem aviso no console, sem sintese por amostra no Web/iPhone (so uma
## escrita de propriedade por quadro) e o tom acompanha o giro igual.
##
## Por que sintetizar em vez de baixar: nao existe loop de motor CC0 em .wav ou
## .mp3 com URL direta (pesquisa de 2026-11); os loops livres que existem sao
## .ogg, que o Safari do iPhone nao decodifica.
##
## O Safari so libera audio depois do primeiro toque na tela; o Godot retoma o
## AudioContext nesse momento, entao o som "acorda" no primeiro comando.

const MIX_RATE := 22050.0
const TABLE_SIZE := 512
const IDLE_HZ := 26.0
const MAX_HZ := 96.0
const MAX_SPEED := 22.0      # igual a car.gd (m/s)
const IMPACT_PATH := "res://assets/sounds/impact.wav"

## Loop do motor: 1,5 s. O comprimento tem um numero INTEIRO de ciclos da
## frequencia base, senao a emenda estala.
const LOOP_SECONDS := 1.5
const LOOP_HZ := 60.0
## Giro -> pitch do loop: 60 Hz x 0,42 = 25 Hz na lenta; 60 x 1,60 = 96 Hz no
## corte (a mesma faixa de engine_hz).
const PITCH_IDLE := 0.42
const PITCH_MAX := 1.60

var car = null               # car.gd: giro e acelerador vem daqui
var enabled := true

var _stream: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _started := false
var _tries := 0
var _retry := 0.0


func _ready() -> void:
	_stream = AudioStreamPlayer.new()
	_stream.name = "Engine"
	_stream.stream = engine_loop(LOOP_SECONDS, MIX_RATE)
	_stream.volume_db = -40.0        # mudo ate estar dirigindo
	add_child(_stream)
	_impact = AudioStreamPlayer.new()
	_impact.name = "Impact"
	_impact.stream = load_impact()
	_impact.volume_db = -4.0
	add_child(_impact)
	if _impact.stream == null:
		push_warning("VehicleAudio: %s nao carregou" % IMPACT_PATH)
	# NAO chamar play() aqui: no build web o AudioContext ainda esta suspenso (o
	# Safari exige um toque). O som comeca no primeiro gesto, em _input.


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


## Gera o loop do motor como AudioStreamWAV 16 bits mono (B-74). PURO e
## deterministico: o CI confere tamanho, loop e pico sem placa de audio.
## O "ruido de cidade" e feito de harmonicos INTEIROS no mesmo loop (ruido
## aleatorio repetido faria "tick" a cada volta do loop).
static func engine_loop(seconds: float, mix_rate: float) -> AudioStreamWAV:
	var rate := maxf(1000.0, mix_rate)
	var cycles := maxf(1.0, round(LOOP_HZ * maxf(0.1, seconds)))
	var frames := int(round(cycles / LOOP_HZ * rate))
	var table := engine_table()
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var x := fmod(float(i) * LOOP_HZ / rate, 1.0)
		var v := table[int(x * float(TABLE_SIZE)) & (TABLE_SIZE - 1)]
		var u := float(i) / float(frames)
		v += (sin(TAU * u * 37.0) + sin(TAU * u * 61.0) * 0.7
				+ sin(TAU * u * 89.0) * 0.5) * 0.035
		v = clampf(v, -0.95, 0.95)
		data.encode_s16(i * 2, int(round(v * 32000.0)))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = int(round(rate))
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = frames
	return st


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
	if _stream == null or _tries >= 8:
		return
	_started = true
	_tries += 1
	if not _stream.playing:
		_stream.play()


## Estado do som para a telemetria: sem isso, "nao tem som" e um mistério.
func describe() -> String:
	if _stream != null and _stream.playing:
		return "som: motor sintetizado ligado"
	if _started:
		return "som: sem audio neste navegador (%d tentativas)" % _tries
	return "som: toque na tela para ligar"


## O Safari so libera audio depois de um gesto. Cada toque/tecla tenta ligar o
## motor de novo, ate conseguir (ou ate desistir, para nao gastar quadro).
func _input(event: InputEvent) -> void:
	if _stream != null and _stream.playing:
		return
	var press := false
	if event is InputEventScreenTouch:
		press = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		press = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		press = (event as InputEventKey).pressed
	if press:
		start()


## Batida (ligada ao signal crashed do carro).
func crash(strength: float) -> void:
	if _impact == null or _impact.stream == null:
		return
	_impact.pitch_scale = impact_pitch(strength)
	_impact.volume_db = lerpf(-10.0, -2.0, clampf(strength, 0.0, 1.0))
	_impact.play()


## O giro vira pitch do loop: uma escrita de propriedade por quadro, sem
## sintese de amostra (era o custo do gerador em B-42/B-61).
func _process(delta: float) -> void:
	if not enabled or _stream == null or not _started:
		return
	if not _stream.playing:
		# O navegador aceitou o toque mas ainda nao tocou: tenta de novo algumas
		# vezes, sem insistir a cada quadro.
		_retry -= delta
		if _tries < 8 and _retry <= 0.0:
			_retry = 0.5
			start()
		return
	var ratio := 0.0
	var gas := 0.0
	var driving := false
	if car != null:
		driving = bool(car.occupied)
		gas = clampf(absf(float(car.input_throttle)), 0.0, 1.0)
		var er: Variant = car.get("engine_ratio")
		if er != null:
			ratio = clampf(float(er), 0.0, 1.0)
		else:
			ratio = clampf(absf(float(car.speed)) / MAX_SPEED, 0.0, 1.0)
	_stream.pitch_scale = lerpf(PITCH_IDLE, PITCH_MAX, ratio)
	_stream.volume_db = (lerpf(-18.0, -8.0, ratio) + gas * 2.0) if driving else -40.0
