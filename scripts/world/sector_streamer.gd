extends Node3D
## SectorStreamer: streaming do mundo por setores de 512 m.
##
## - Anel interno (full_ring) com LOD cheio; anel externo com LOD reduzido.
## - Geracao em WorkerThreadPool: a thread so calcula arrays; a malha e criada
##   na thread principal (rendering thread) no ritmo de 1 setor por frame.
## - Colisao de predios e por retangulos no plano XZ, consultados aqui mesmo;
##   nao existe corpo de fisica estatico no mundo.
## - Fora do raio de streaming: nada. O horizonte e o fog + o plano do mar.

const Cfg = preload("res://scripts/core/cfg.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")

var world_seed: int = 20260922
var full_ring: int = 1
var far_ring: int = 2
var use_threads: bool = true
var max_requests_per_frame: int = 2

var _loaded: Dictionary = {}     # Vector2i -> Node3D
var _levels: Dictionary = {}     # Vector2i -> LOD gravado no disco de trabalho
var _inflight: Dictionary = {}   # Vector2i -> true
var _waiting: Array = []         # setores queridos, em ordem de prioridade
var _done: Array = []            # resultados prontos das threads
var _busy: Dictionary = {}       # Vector2i -> id da tarefa no WorkerThreadPool
var _mutex := Mutex.new()
var _focus := Vector2i(-999, -999)
var _material: StandardMaterial3D
var _requests_this_frame := 0

var generated_total: int = 0
var last_generate_ms: float = 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = false
	_material.roughness = 1.0
	_material.metallic_specular = 0.1


func update_stream(focus: Vector3, delta: float) -> void:
	_requests_this_frame = 0
	_install_done(2)
	var s := Cfg.sector_of(focus.x, focus.z)
	if s != _focus:
		_focus = s
		_recompute_wanted()

	var budget := mini(max_requests_per_frame, 4) - _requests_this_frame
	for sec in _waiting:
		if budget <= 0:
			break
		if _inflight.has(sec):
			continue
		var lod := _lod_for(sec)
		if _loaded.has(sec):
			if int(_levels.get(sec, -1)) == lod:
				continue
			# Regera so quando o setor carregado ficou mais grosso que o desejado
			# (LOD far -> full). Nunca degrada um setor ja detalhado.
			if lod != CityGen.LOD_FULL:
				continue
		_start(sec, lod)
		budget -= 1
		_requests_this_frame += 1


func _recompute_wanted() -> void:
	_waiting.clear()
	var r := far_ring
	# Percorre de dentro para fora: os setores mais proximos entram primeiro na
	# fila, que e consumida em ordem.
	for d in range(0, r + 1):
		for dz in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dz)) != d:
					continue
				var sec := _focus + Vector2i(dx, dz)
				if Cfg.sector_in_bounds(sec):
					_waiting.append(sec)
	# Descarrega o que saiu do anel externo (itera sobre uma copia das chaves).
	for sec in _loaded.keys():
		if absi(sec.x - _focus.x) > far_ring + 1 or absi(sec.y - _focus.y) > far_ring + 1:
			_unload(sec)


func _lod_for(sec: Vector2i) -> int:
	var d := maxi(absi(sec.x - _focus.x), absi(sec.y - _focus.y))
	return CityGen.LOD_FULL if d <= full_ring else CityGen.LOD_FAR


func _start(sec: Vector2i, lod: int) -> void:
	_inflight[sec] = true
	_levels[sec] = lod
	if use_threads:
		var id := WorkerThreadPool.add_task(_task.bind(sec, lod), false, "carioca_sector")
		_busy[sec] = id
	else:
		var res := CityGen.generate(sec.x, sec.y, world_seed, lod)
		_install(sec, lod, res)


## Roda numa worker thread: apenas arrays, nada de cena/rendering.
func _task(sec: Vector2i, lod: int) -> void:
	var t0 := Time.get_ticks_usec()
	var res := CityGen.generate(sec.x, sec.y, world_seed, lod)
	res.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	_mutex.lock()
	_done.append([sec, lod, res])
	_mutex.unlock()


func _install_done(limit: int) -> void:
	var n := 0
	while n < limit:
		_mutex.lock()
		if _done.is_empty():
			_mutex.unlock()
			break
		var item: Array = _done.pop_front()
		_mutex.unlock()
		_install(item[0], item[1], item[2])
		n += 1


func _install(sec: Vector2i, lod: int, res: Array) -> void:
	_inflight.erase(sec)
	_busy.erase(sec)
	var verts: PackedVector3Array = res[0]
	var norms: PackedVector3Array = res[1]
	var cols: PackedColorArray = res[2]
	var colliders: Array = res[3]
	var defs: Array = res[4]
	if res.size() > 5:
		last_generate_ms = float(res[5])
	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)

	var node := Node3D.new()
	node.name = "S%d_%d" % [sec.x, sec.y]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	node.add_child(mi)
	if not defs.is_empty():
		node.add_child(_prop_multimesh(defs))

	node.set_meta("colliders", colliders)
	node.set_meta("verts", verts.size())
	if _loaded.has(sec):
		var old: Node3D = _loaded[sec]
		old.queue_free()
	_loaded[sec] = node
	add_child(node)
	generated_total += 1


## Props instanciados (palmeiras, arvores, quiosques): 1 MultiMesh por setor.
func _prop_multimesh(defs: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = CityGen.unit_cube_mesh()
	mm.instance_count = defs.size()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var c: Vector3 = d["c"]
		var kind := String(d.get("kind", "tree"))
		var hue := float(d.get("hue", 0.5))
		var h := float(d.get("h", 6.0))
		var shape := PropFactory.shape_for(kind, h)
		var basis := Basis.from_scale(shape[1])
		mm.set_instance_transform(i, Transform3D(basis, c + Vector3(0.0, float(shape[0]), 0.0)))
		mm.set_instance_color(i, PropFactory.color_for(kind, hue))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = false
	mat.roughness = 1.0
	mmi.material_override = mat
	return mmi


func _unload(sec: Vector2i) -> void:
	if _loaded.has(sec):
		var n: Node3D = _loaded[sec]
		n.queue_free()
		_loaded.erase(sec)
	_levels.erase(sec)


## Colisao: empurra (x, z) para fora dos predios num raio de 2 setores.
func push_out(x: float, z: float, radius: float) -> Vector2:
	var p := Vector2(x, z)
	var sec := Cfg.sector_of(p.x, p.y)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := sec + Vector2i(dx, dz)
			if not _loaded.has(key):
				continue
			var node: Node3D = _loaded[key]
			if not node.has_meta("colliders"):
				continue
			var rects: Array = node.get_meta("colliders")
			for r in rects:
				var rect: Rect2 = r
				var qx := clampf(p.x, rect.position.x, rect.position.x + rect.size.x)
				var qz := clampf(p.y, rect.position.y, rect.position.y + rect.size.y)
				var d := Vector2(p.x - qx, p.y - qz)
				if d.length() >= radius:
					continue
				if d.length() < 0.0001:
					# Centro dentro do retangulo: sai pelo lado mais proximo.
					var left := p.x - rect.position.x
					var right := rect.position.x + rect.size.x - p.x
					var down := p.y - rect.position.y
					var up := rect.position.y + rect.size.y - p.y
					var m := minf(minf(left, right), minf(down, up))
					if m == left:
						p.x = rect.position.x - radius
					elif m == right:
						p.x = rect.position.x + rect.size.x + radius
					elif m == down:
						p.y = rect.position.y - radius
					else:
						p.y = rect.position.y + rect.size.y + radius
				else:
					p += d.normalized() * (radius - d.length())
	return p


func has_ready_at(pos: Vector3) -> bool:
	var sec := Cfg.sector_of(pos.x, pos.z)
	return _loaded.has(sec) and int(_levels.get(sec, -1)) == CityGen.LOD_FULL


func stats(with_render: bool = false) -> Dictionary:
	var d := {
		"loaded": _loaded.size(),
		"inflight": _inflight.size(),
		"generated": generated_total,
		"gen_ms": last_generate_ms,
	}
	if with_render:
		d["draw"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		d["prim"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	return d


func shutdown() -> void:
	if use_threads:
		for sec in _busy.keys():
			var id := int(_busy[sec])
			if id >= 0:
				WorkerThreadPool.wait_for_task_completion(id)
		_busy.clear()
	_mutex.lock()
	_done.clear()
	_mutex.unlock()
	_inflight.clear()
	for sec in _loaded.keys():
		_unload(sec)
