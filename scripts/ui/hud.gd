extends CanvasLayer
## HUD: interface de jogo (Fase 1).
##
## - Canto superior esquerdo: estado do mundo e telemetria (FPS, frame time,
##   p95, draw calls, primitivas, memoria, setores, carro e modelo externo).
## - Faixa superior direita: SALVAR, CARREGAR, PERF, MEDIR, +1h, LIMITAR 30.
## - Aviso curto ("toast") para confirmar acoes. O botao ENTRAR/SAIR do veiculo
##   fica no TouchControls, junto dos botoes de toque (B-38).
##
## Toda a interface e criada por codigo: menos arquivos .tscn para manter e
## nada de imagem/textura nesta fase.
##
## ESCALA (B-35): o jogo e desenhado num viewport logico de 1280x720 esticado
## para a tela do iPhone; em retrato a altura logica chega a ~2770 px e um
## texto de 12 px aparecia com ~6 px reais. Fontes, botoes e deslocamentos sao
## multiplicados por _ui (calculado uma vez em _ready).

signal action(name: String)
signal perf_toggled(on: bool)

const Cfg = preload("res://scripts/core/cfg.gd")

## Duracao da medicao de FPS do botao MEDIR (B-09).
const BENCH_SECONDS := 15.0

var player = null
var streamer = null
var day_night = null
var car = null

var _stats: Label
var _title: Label
var _toast: Label
var _toast_t := 0.0
var _refresh := 0.0
var _perf_on := true
var _cap30 := true
var _model_note := ""

var _ui := 1.0
var _btn_w := 96.0
var _btn_h := 46.0

var _bench_t := -1.0
var _bench_dt: Array[float] = []
var _bench_result := ""

var _frame_times: Array[float] = []
var _frame_i := 0


func setup(p: Node, s: Node, dn: Node) -> void:
	player = p
	streamer = s
	day_night = dn


func _ready() -> void:
	layer = 2
	# Escala da interface (B-35): derivada da altura logica do viewport, que no
	# iPhone esticado pode chegar a ~2770 px em retrato.
	var vs := get_viewport().get_visible_rect().size
	_ui = clampf(vs.y / 640.0, 1.15, 2.2)
	_btn_w = 96.0 * _ui
	_btn_h = 46.0 * _ui
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var labels := ["SALVAR", "CARREGAR", "PERF", "MEDIR", "+1h", "LIMITAR 30"]
	var cbs: Array[Callable] = [_on_save, _on_load, _on_perf, _on_bench, _on_plus_hour, _on_cap]
	var gap := 6.0 * _ui
	# Duas fileiras de tres. Com os seis botoes numa linha so, a barra ficava
	# mais larga que a tela em retrato e os primeiros saiam pela borda esquerda
	# (visto no iPhone: "CARREGAR" cortado).
	var cols := VBoxContainer.new()
	cols.add_theme_constant_override("separation", int(gap))
	root.add_child(cols)
	var rows: Array[HBoxContainer] = []
	for r in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(gap))
		cols.add_child(row)
		rows.append(row)
	for i in labels.size():
		var row: HBoxContainer = rows[0] if i < 3 else rows[1]
		_bar_button(row, String(labels[i]), cbs[i])
	cols.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cols.offset_left = -3.0 * (_btn_w + gap) - 12.0 * _ui
	cols.offset_right = -12.0 * _ui
	cols.offset_top = 8.0 * _ui
	cols.offset_bottom = 8.0 * _ui + 2.0 * _btn_h + gap
	var bar_bottom := 8.0 * _ui + 2.0 * _btn_h + gap

	# O botao ENTRAR/SAIR do carro NAO fica aqui: no iPhone o toque em Button do
	# Godot nao chegava ao jogo (B-38), enquanto o toque tratado pelo
	# TouchControls (PULAR/CORRER) sempre funcionou. Ver
	# scripts/ui/touch_controls.gd: _car_pos / take_car_press().

	_title = Label.new()
	_title.text = "CARIOCA  v%s" % Cfg.APP_VERSION
	_title.position = Vector2(12.0 * _ui, 8.0 * _ui)
	_title.add_theme_font_size_override("font_size", int(16.0 * _ui))
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_title.add_theme_constant_override("outline_size", 3)
	root.add_child(_title)

	_stats = Label.new()
	# Abaixo da barra de botoes: em retrato a barra ocupa o topo, e a telemetria
	# por baixo dela nao se sobrepoe (era o que acontecia no iPhone).
	_stats.position = Vector2(12.0 * _ui, bar_bottom + 10.0 * _ui)
	_stats.size = Vector2(vs.x - 24.0 * _ui, 0.0)
	_stats.clip_text = true
	_stats.add_theme_font_size_override("font_size", int(13.0 * _ui))
	_stats.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.95))
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_stats.add_theme_constant_override("outline_size", 3)
	root.add_child(_stats)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var half := minf(330.0 * _ui, vs.x * 0.44)
	_toast.offset_left = -half
	_toast.offset_right = half
	_toast.offset_top = -400.0 * _ui
	_toast.offset_bottom = -332.0 * _ui
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", int(19.0 * _ui))
	_toast.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 4)
	root.add_child(_toast)

	Engine.max_fps = 30


func _bar_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(_btn_w, _btn_h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(15.0 * _ui))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func toast(msg: String) -> void:
	_toast.text = msg
	_toast_t = 2.5


## Carro para a linha de diagnostico da telemetria (pode ser null).
func set_car(c: Node) -> void:
	car = c


## Linha livre sobre o modelo externo (piloto de asset, B-21).
func set_model_note(t: String) -> void:
	_model_note = t


func _process(delta: float) -> void:
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_bench_tick(delta)
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
	if car != null:
		# Diagnostico do carro (Fase 4): se "entrar e nao andar" voltar, esta
		# linha diz se o carro esta ocupado e o que ele recebe de acelerador e
		# de volante — sem precisar do console do Safari.
		lines.append("carro %s   dist %.0f m   %.0f km/h   acel %.0f%%   volante %.0f%%" % [
			"dirigindo" if car.occupied else "livre",
			player.position.distance_to(car.global_position),
			absf(float(car.speed)) * 3.6,
			float(car.input_throttle) * 100.0,
			float(car.input_steer) * 100.0])
		# Marcha e giro (B-67): e por esta linha que se ve, no aparelho, se o
		# cambio esta subindo e se o motor nao morre na areia.
		lines.append("marcha %d   %d rpm   aderencia %.0f%%%s" % [
			int(car.gear), int(round(float(car.rpm))),
			(1.0 - float(car.slip)) * 100.0,
			"   ESP" if bool(car.esp_on) else ""])
		# Avaria (B-69): fase do dano e quanto o motor ainda entrega.
		lines.append("avaria %.0f%% (%s)" % [
			float(car.damage) * 100.0, String(car.damage_label())])
	if not _model_note.is_empty():
		lines.append(_model_note)
	if not _bench_result.is_empty():
		lines.append(_bench_result)
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


## Medicao de FPS (B-09): com o limite de 30 ligado o numero mede o LIMITE, nao
## o aparelho. Aqui o limite sai durante 15 s e o resultado fica na telemetria:
## media, p95 do frame e o pior frame (e o pior que engasga no dedo).
func _on_bench() -> void:
	if _bench_t >= 0.0:
		_finish_bench(false)
		return
	_bench_dt.clear()
	_bench_t = BENCH_SECONDS
	_bench_result = ""
	_perf_on = true
	Engine.max_fps = 0
	toast("Medindo %.0f s SEM limite: ande ou dirija agora." % BENCH_SECONDS)


func _bench_tick(delta: float) -> void:
	if _bench_t < 0.0:
		return
	_bench_dt.append(delta)
	_bench_t -= delta
	if _bench_t <= 0.0:
		_finish_bench(true)


func _finish_bench(complete: bool) -> void:
	_bench_t = -1.0
	Engine.max_fps = 30 if _cap30 else 0
	var n := _bench_dt.size()
	if n < 10:
		_bench_dt.clear()
		toast("Medicao cancelada (poucos quadros).")
		return
	var total := 0.0
	var worst := 0.0
	for d in _bench_dt:
		total += d
		worst = maxf(worst, d)
	var sorted_dt := _bench_dt.duplicate()
	sorted_dt.sort()
	var p95: float = sorted_dt[clampi(int(float(n) * 0.95), 0, n - 1)]
	var avg := float(n) / maxf(0.0001, total)
	_bench_result = "MEDICAO %.0f s: media %.0f fps (%.1f ms)   p95 %.1f ms   pior %.1f ms" % [
		BENCH_SECONDS, avg, 1000.0 / maxf(0.001, avg), p95 * 1000.0, worst * 1000.0]
	_bench_dt.clear()
	if complete:
		toast(_bench_result)


func _on_plus_hour() -> void:
	if day_night != null:
		day_night.advance(1.0)
		toast("Relogio: %s" % Cfg.clock_label(day_night.hour))


func _on_cap() -> void:
	_cap30 = not _cap30
	Engine.max_fps = 30 if _cap30 else 0
	toast("Limite de FPS: %s" % ("30" if _cap30 else "livre"))
