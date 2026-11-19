extends CanvasLayer
## HUD: interface de jogo (Fase 1).
##
## - Canto superior esquerdo: estado do mundo e telemetria (FPS, frame time,
##   draw calls, triangulos, memoria, setores).
## - Faixa superior: botoes SALVAR, CARREGAR, PERF, +1h, LIMITAR 30.
## - Aviso curto ("toast") para confirmar acoes.
##
## Toda a interface e criada por codigo: menos arquivos .tscn para manter e
## nada de imagem/textura nesta fase.

signal action(name: String)
signal perf_toggled(on: bool)

const Cfg = preload("res://scripts/core/cfg.gd")

var player = null
var streamer = null
var day_night = null

var _stats: Label
var _title: Label
var _toast: Label
var _toast_t := 0.0
var _refresh := 0.0
var _perf_on := true
var _cap30 := true
var _car_btn: Button
var _car_label := ""

var _frame_times: Array[float] = []
var _frame_i := 0


func setup(p: Node, s: Node, dn: Node) -> void:
	player = p
	streamer = s
	day_night = dn


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-440.0, 10.0)
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	_bar_button(bar, "SALVAR", _on_save)
	_bar_button(bar, "CARREGAR", _on_load)
	_bar_button(bar, "PERF", _on_perf)
	_bar_button(bar, "+1h", _on_plus_hour)
	_bar_button(bar, "LIMITAR 30", _on_cap)

	# Botao de contexto do veiculo (Fase 4): so aparece quando o jogador
	# esta perto do carro (ou dirigindo). O main manda o texto via
	# set_car_prompt() e o clique volta pelo signal action("car").
	_car_btn = Button.new()
	_car_btn.text = "ENTRAR NO CARRO"
	_car_btn.custom_minimum_size = Vector2(200.0, 54.0)
	_car_btn.focus_mode = Control.FOCUS_NONE
	_car_btn.add_theme_font_size_override("font_size", 14)
	_car_btn.visible = false
	_car_btn.pressed.connect(_on_car)
	root.add_child(_car_btn)

	_title = Label.new()
	_title.text = "CARIOCA  v%s  -  Fase 1 (fundacao jogavel)" % Cfg.APP_VERSION
	_title.position = Vector2(12.0, 8.0)
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_title.add_theme_constant_override("outline_size", 3)
	root.add_child(_title)

	_stats = Label.new()
	_stats.position = Vector2(12.0, 28.0)
	_stats.add_theme_font_size_override("font_size", 12)
	_stats.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.95))
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_stats.add_theme_constant_override("outline_size", 3)
	root.add_child(_stats)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-260.0, -120.0)
	_toast.size = Vector2(520.0, 28.0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 4)
	root.add_child(_toast)

	Engine.max_fps = 30


func _bar_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(84.0, 40.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func toast(msg: String) -> void:
	_toast.text = msg
	_toast_t = 2.5


## Texto do botao de contexto do veiculo. String vazia esconde o botao.
func set_car_prompt(label: String) -> void:
	if label == _car_label:
		return
	_car_label = label
	_car_btn.text = label if label != "" else "ENTRAR NO CARRO"
	_car_btn.visible = label != ""


func _on_car() -> void:
	action.emit("car")


func _process(delta: float) -> void:
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _car_btn != null and _car_btn.visible:
		# Ancorado a mao: o canto inferior direito fica com os botoes de toque
		# (PULAR/CORRER ficam abaixo; sem sobreposicao).
		var vs := get_viewport_rect().size
		_car_btn.position = Vector2(vs.x - 216.0, vs.y - 254.0)
	_frame_times.resize(240)
	_frame_times[_frame_i % 240] = delta * 1000.0
	_frame_i += 1
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_refresh_stats()


func _refresh_stats() -> void:
	if player == null:
		return
	_stats.visible = _perf_on
	if not _perf_on:
		return
	var p: Vector3 = player.position
	var st: Dictionary = streamer.stats() if streamer != null else {}
	# O enum Performance.Monitor do Godot 4 nao tem monitor de triangulos:
	# RENDER_TOTAL_TRIANGLES nao existe (B-32). Primitivas por frame sao o
	# numero equivalente (inclui prepass/sombras) e servem de proxy.
	var tri := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) if _metric_ok() else 0
	var lines: Array[String] = []
	lines.append("FPS %d   frame %.1f ms   p95 %.1f ms" % [
		int(Engine.get_frames_per_second()),
		1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		_percentile(95)])
	if _metric_ok():
		lines.append("draw calls %d   primitivas %d   objetos %d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
		lines.append("mem %.0f MB   nos %d" % [
			float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	lines.append("pos %.0f, %.0f, %.0f   vel %.1f m/s" % [p.x, p.y, p.z, player.speed()])
	lines.append("relogio %s   clima %s   cap %s" % [
		Cfg.clock_label(day_night.hour if day_night != null else 0.0),
		String(day_night.weather) if day_night != null else "-",
		"30" if _cap30 else "livre"])
	if not st.is_empty():
		lines.append("setores %d   na fila %d   gerados %d   ger %.0f ms   prim %d" % [
			int(st.get("loaded", 0)), int(st.get("inflight", 0)), int(st.get("generated", 0)),
			float(st.get("gen_ms", 0.0)), tri])
	_stats.text = "\n".join(lines)


func _percentile(p: int) -> float:
	var n := mini(_frame_i, 240)
	if n == 0:
		return 0.0
	var arr := _frame_times.slice(0, n)
	arr.sort()
	var idx := clampi(int(round(float(p) / 100.0 * float(n - 1))), 0, n - 1)
	return arr[idx]


func _metric_ok() -> bool:
	# Em headless o monitor de rendering nao existe.
	return not DisplayServer.get_name().contains("headless")


# --- Botoes -------------------------------------------------------------------

func _on_save() -> void:
	action.emit("save")


func _on_load() -> void:
	action.emit("load")


func _on_perf() -> void:
	_perf_on = not _perf_on
	perf_toggled.emit(_perf_on)


func _on_plus_hour() -> void:
	if day_night != null:
		day_night.advance(1.0)
		toast("Relogio: %s" % Cfg.clock_label(day_night.hour))


func _on_cap() -> void:
	_cap30 = not _cap30
	Engine.max_fps = 30 if _cap30 else 0
	toast("Limite de FPS: %s" % ("30" if _cap30 else "livre"))
