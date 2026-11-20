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

# Texturas CC0 (Poly Haven, 1K) das superficies do chao. Se faltar o arquivo, a
# superficie sai com a cor de reserva — o jogo nao quebra por causa de textura.
const TEX_ROAD := "res://assets/textures/asphalt.jpg"
const TEX_WALK := "res://assets/textures/pavement.jpg"
const TEX_SAND := "res://assets/textures/sand.jpg"
const TEX_CALCADA := "res://assets/textures/calcada.jpg"
const TEX_FACADE := "res://assets/textures/facade.jpg"

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
var _win_mat: StandardMaterial3D
var _mat_road: StandardMaterial3D
var _mat_walk: StandardMaterial3D
var _mat_sand: StandardMaterial3D
var _mat_calcadao: StandardMaterial3D
var _mat_facade: StandardMaterial3D
var _requests_this_frame := 0

var generated_total: int = 0
var last_generate_ms: float = 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = false
	_material.roughness = 1.0
	_material.metallic_specular = 0.1
	# Material das janelas (surface 1 de cada setor): acende a noite.
	_win_mat = StandardMaterial3D.new()
	_win_mat.vertex_color_use_as_albedo = true
	_win_mat.vertex_color_is_srgb = false
	_win_mat.roughness = 0.4
	_win_mat.emission_enabled = true
	_win_mat.emission = Color(1.0, 0.85, 0.55)
	_win_mat.emission_energy_multiplier = 0.0
	# Superficies texturadas do chao (asfalto, calcada, areia). UV em escala de
	# mundo ja vem pronto do city_gen; aqui so entra a textura e o material.
	_mat_road = _tex_material(TEX_ROAD, Color(0.21, 0.22, 0.24))
	_mat_walk = _tex_material(TEX_WALK, Color(0.63, 0.62, 0.59))
	_mat_sand = _tex_material(TEX_SAND, Color(0.86, 0.79, 0.64))
	# Calcadao: pedra portuguesa de verdade (textura CC0 do OpenGameArt). O
	# padrao de ondas gerado antes ficou ruim na tela e foi trocado por pedra.
	_mat_calcadao = _tex_material(TEX_CALCADA, Color(0.72, 0.70, 0.66))
	# Fachada dos predios: parede + janela e mapa de emissao, gerados em codigo.
	_mat_facade = _facade_material()


## Material de superficie texturada. Sem a textura, cai na cor de reserva.
func _tex_material(path: String, fallback: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = fallback
	m.roughness = 0.95
	m.metallic_specular = 0.05
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			m.albedo_texture = res as Texture2D
			# A textura ja traz a cor: albedo branco nao tinge.
			m.albedo_color = Color.WHITE
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Fachada em coordenadas de textura: devolve Vector2(tom da parede, brilho da
## janela). Parede clara, janela escura e acesa; a junta do andar fica mais
## escura. Puro (sem GPU), para o teste conferir o padrao sem placa de video.
static func facade_value(u: float, v: float) -> Vector2:
	var win := u > 0.20 and u < 0.80 and v > 0.32 and v < 0.84
	if win:
		return Vector2(0.30, 1.0)
	var shade := 0.94
	if v < 0.06 or v > 0.97:
		shade = 0.72
	return Vector2(shade, 0.0)


## Material da fachada dos predios. Com a textura fotografada (Keith333, CC-BY
## 3.0) usa a foto; sem ela, cai no padrao gerado (parede + janela), que tambem
## tem mapa de emissao alinhado. A cor de vertice do predio tinge a textura.
func _facade_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.emission_enabled = true
	m.emission_energy_multiplier = 0.0
	if ResourceLoader.exists(TEX_FACADE):
		var res: Resource = load(TEX_FACADE)
		if res is Texture2D:
			m.albedo_texture = res as Texture2D
			# A noite a propria foto vira mapa de emissao, com energia baixa: a
			# fachada ganha luz de cidade em vez de virar um bloco preto.
			m.emission_texture = res as Texture2D
			m.emission = Color(0.60, 0.52, 0.40)
			return m
	var size := 128
	var albedo := Image.create(size, size, true, Image.FORMAT_RGB8)
	var emit := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var f := facade_value(float(x) / float(size), float(y) / float(size))
			var shade := f.x
			albedo.set_pixel(x, y, Color(shade, shade, shade))
			emit.set_pixel(x, y, Color.WHITE if f.y > 0.5 else Color.BLACK)
	albedo.generate_mipmaps()
	emit.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(albedo)
	m.emission_texture = ImageTexture.create_from_image(emit)
	m.emission = Color(1.0, 0.85, 0.55)
	return m


## Acrescenta uma surface texturada e devolve o proximo indice livre.
func _tex_surface(mesh: ArrayMesh, si: int, v: PackedVector3Array, n: PackedVector3Array,
		uv: PackedVector2Array, mat: Material,
		cols: PackedColorArray = PackedColorArray()) -> int:
	if v.is_empty() or uv.size() != v.size() or n.size() != v.size():
		return si
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	if cols.size() == v.size():
		arr[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(si, mat)
	return si + 1


## Intensidade da iluminacao das janelas (0 = dia, 1 = noite).
func set_window_glow(f: float) -> void:
	# 0,55 e nao 1,4 (B-52): o mapa de emissao da fachada e a FOTO inteira, entao
	# energia alta fazia a PAREDE acender junto com a janela, e a cidade de noite
	# virava um borrao brilhante.
	var e := clampf(f, 0.0, 1.0) * 0.55
	if _win_mat != null:
		_win_mat.emission_energy_multiplier = e
	# As janelas que acendem agora sao as da textura de fachada.
	if _mat_facade != null:
		_mat_facade.emission_energy_multiplier = e


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
	# O tempo de geracao vem como ULTIMO elemento (a worker anexa depois das
	# superficies): le pelo tipo, nao por indice fixo.
	var last: Variant = res[res.size() - 1]
	if last is float:
		last_generate_ms = float(last)
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
	var si := 1
	# Fachadas de vidro em surface propria, com emissao controlada por
	# set_window_glow() conforme o ciclo dia/noite.
	var win_v: PackedVector3Array = res[5]
	if win_v.size() > 0:
		var warrays := []
		warrays.resize(Mesh.ARRAY_MAX)
		warrays[Mesh.ARRAY_VERTEX] = win_v
		warrays[Mesh.ARRAY_NORMAL] = res[6]
		warrays[Mesh.ARRAY_COLOR] = res[7]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warrays)
		mesh.surface_set_material(si, _win_mat)
		si += 1
	# Superficies texturadas: asfalto, calcada, areia e o calcadao de Copacabana.
	if res.size() >= 17:
		si = _tex_surface(mesh, si, res[8], res[9], res[10], _mat_road)
		si = _tex_surface(mesh, si, res[11], res[12], res[13], _mat_walk)
		si = _tex_surface(mesh, si, res[14], res[15], res[16], _mat_sand)
	if res.size() >= 20:
		si = _tex_surface(mesh, si, res[17], res[18], res[19], _mat_calcadao)
	# Fachada dos predios (com cor por vertice: a paleta tinge a textura).
	if res.size() >= 24:
		si = _tex_surface(mesh, si, res[20], res[21], res[22], _mat_facade, res[23])

	var node := Node3D.new()
	node.name = "S%d_%d" % [sec.x, sec.y]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# Distancia de visibilidade: o setor detalhado some antes do grosso (corta
	# draw calls). O enum do Godot 4 e VisibilityRangeFadeMode e as constantes
	# tem o prefixo VISIBILITY_RANGE_FADE_ — "SELF_DITHER" nao existe (B-29).
	# E o fade so funciona no Forward+: no Compatibility ele faz o mesmo que
	# DISABLED, entao aqui o corte e seco e honesto.
	mi.visibility_range_end = 1500.0 if lod == CityGen.LOD_FULL else 2400.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
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
		c += Vector3(
			float(d.get("dx", 0.0)),
			float(d.get("dy", 0.0)),
			float(d.get("dz", 0.0)))
		var kind := String(d.get("kind", "tree"))
		var hue := float(d.get("hue", 0.5))
		var h := float(d.get("h", 6.0))
		var shape := PropFactory.shape_for(kind, h)
		var basis := Basis.from_scale(shape[1])
		# Giro em Y (B-52): copa de arvore e arbusto girados leem como volume,
		# nao como caixa alinhada a grade da cidade.
		var rot := float(d.get("rot", 0.0))
		if rot != 0.0:
			basis = Basis(Vector3.UP, rot) * basis
		mm.set_instance_transform(i, Transform3D(basis, c + Vector3(0.0, float(shape[0]), 0.0)))
		mm.set_instance_color(i, PropFactory.color_for(kind, hue))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = false
	mat.roughness = 1.0
	mmi.material_override = mat
	mmi.visibility_range_end = 700.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
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
