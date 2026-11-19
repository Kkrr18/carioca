extends Node
## PerfLog: amostragem de desempenho para VALIDAR (nao prometer) a meta de 30 FPS.
##
## Coleta a cada ~0,5 s: fps, frame time, draw calls, primitivas, nos, setores e
## posicao. dump_csv() grava user://perf/carioca_perf_<data>.csv. No iPhone, o
## arquivo sai pelo app Arquivos em "No Meu iPhone/CARIOCA" quando o export usa
## user_data/accessible_from_files_app=true (ver export_presets.cfg).

const Cfg = preload("res://scripts/core/cfg.gd")

const MAX_SAMPLES := 3000

var player = null
var streamer = null
var day_night = null

var rows: Array = []
var _acc := 0.0
var _interval := 0.5
var _frames := 0
var _frame_acc := 0.0
var _t := 0.0


func setup(p: Node, s: Node, dn: Node) -> void:
	player = p
	streamer = s
	day_night = dn


func sample(delta: float) -> void:
	_t += delta
	_acc += delta
	_frames += 1
	_frame_acc += delta
	if _acc < _interval:
		return
	if rows.size() >= MAX_SAMPLES:
		rows.pop_front()
	var st: Dictionary = streamer.stats(true) if streamer != null else {}
	var p: Vector3 = player.position if player != null else Vector3.ZERO
	var speed: float = player.speed() if player != null else 0.0
	rows.append({
		"t": snappedf(_t, 0.1),
		"fps": snappedf(float(_frames) / maxf(0.001, _frame_acc), 0.1),
		"ms": snappedf(1000.0 * _frame_acc / float(maxi(1, _frames)), 0.01),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prim": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"sec_loaded": int(st.get("loaded", 0)),
		"sec_inflight": int(st.get("inflight", 0)),
		"gen_ms": snappedf(float(st.get("gen_ms", 0.0)), 0.1),
		"x": snappedf(p.x, 1.0),
		"z": snappedf(p.z, 1.0),
		"speed": snappedf(speed, 0.1),
		"hour": snappedf(float(day_night.hour) if day_night != null else 0.0, 0.01),
	})
	_frames = 0.0
	_frame_acc = 0.0
	_acc = 0.0


func dump_csv() -> String:
	if rows.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute("user://perf")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://perf/carioca_perf_%s.csv" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_line("# CARIOCA v%s | %s | engine %s | renderer %s" % [
		Cfg.APP_VERSION,
		String(OS.get_model_name()),
		str(Engine.get_version_info().get("string", "?")),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
	])
	var keys: Array = rows[0].keys()
	f.store_line(",".join(keys))
	for r in rows:
		var vals := PackedStringArray()
		for k in keys:
			vals.append(str(r[k]))
		f.store_line(",".join(vals))
	f.close()
	return path
