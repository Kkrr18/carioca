extends Node3D
## ModelProp: um modelo .glb externo (CC0) dentro do mundo.
##
## Piloto de assets externos (Fase 1.5, B-21): prova o caminho completo —
## arquivo .glb no repositorio, import no CI, export Web e custo medido no
## aparelho. Se o modelo nao carregar, este no fica vazio, o motivo vai para o
## HUD e o resto do jogo nao muda.
##
## Por que normalizar por codigo: os pacotes CC0 vem em escala, eixo e pivo
## arbitrarios e nao ha como abrir o .glb no iPhone para conferir (B-21).
## Entao o modelo e medido pelo AABB e ajustado:
##   1. escala para `target_length` metros no maior eixo horizontal;
##   2. se o maior eixo for X, gira 90 graus — o comprimento fica em Z, que e
##      o eixo para onde carro/caminhao "apontam" neste jogo;
##   3. se as rodas "front" estiverem do lado de tras, gira mais 180 graus
##      (a frente do carro passa a ser -Z, como no carro dirigivel);
##   4. o ponto mais baixo vai para y = 0 e o centro X/Z para a origem, para o
##      modelo encostar no chao analitico (Cfg.height_at) sem flutuar.
## A funcao pura normalize_for() faz a conta (1 e 2) e e testada no CI.

const Cfg = preload("res://scripts/core/cfg.gd")

var model_path := ""
var target_length := 4.0

var loaded := false
var mesh_count := 0
var tris := 0
var load_ms := 0.0
var size_m := Vector3.ZERO
var stats_text := ""
## Rodas do modelo (nome com "wheel" ou "roda"): lista de
## {"node": Node3D, "rest": Transform3D, "front": bool}. O carro dirigivel gira
## e esterca estes nos; lista vazia = modelo sem rodas separadas.
var wheel_info: Array = []
var _built := false


func _ready() -> void:
	load_model()


func describe() -> String:
	return stats_text


## Conta pura do piloto (sem cena, testada em tests/runner.gd).
## Retorna [escala, yaw] para um AABB de `size` virar `target` metros de
## comprimento com o eixo longo em Z.
static func normalize_for(size: Vector3, target: float) -> Array:
	var span: float = maxf(maxf(size.x, size.z), 0.001)
	var s: float = target / span
	var yaw: float = 0.0 if size.z >= size.x else PI * 0.5
	return [s, yaw]


## Escala e giro finais: normalize_for() mais meia volta quando a frente do
## modelo aponta para o lado errado. [escala, yaw].
static func placement(root: Node3D, box: AABB, target: float) -> Array:
	var norm := normalize_for(box.size, target)
	var yaw: float = float(norm[1])
	if facing_flip(root, box):
		yaw += PI
	return [float(norm[0]), yaw]


## Centros das rodas no espaco de `root`: [{"node", "center", "front"}].
## Usa o centro do AABB da MALHA, nao a origem do no: num .glb exportado por
## obj2gltf a origem do no da roda fica no centro do modelo e a geometria vive
## nos vertices — a transform do no nao diz onde a roda esta (B-39/B-40).
static func wheel_centers(root: Node3D) -> Array:
	var out: Array = []
	for w in wheel_nodes(root):
		var n3 := w as Node3D
		if n3 == null:
			continue
		var xf := rel_xf(n3, root)
		var c: Vector3 = xf * mesh_aabb(n3).get_center()
		out.append({
			"node": n3,
			"center": c,
			"front": String(n3.name).to_lower().contains("front"),
		})
	return out


## True se as rodas "front" estiverem atras das "back"/"rear" no eixo longo.
## Sem nomes de frente e tras, ou sem separacao entre elas, devolve false.
static func facing_flip(root: Node3D, box: AABB) -> bool:
	var along_z := box.size.z >= box.size.x
	var fsum := 0.0
	var fn := 0
	var bsum := 0.0
	var bn := 0
	for w in wheel_centers(root):
		var c: Vector3 = w["center"]
		var v := c.z if along_z else c.x
		if bool(w["front"]):
			fsum += v
			fn += 1
		else:
			bsum += v
			bn += 1
	if fn == 0 or bn == 0:
		return false
	var f := fsum / float(fn)
	var b := bsum / float(bn)
	if absf(f - b) < 0.05:
		return false
	# Com o eixo longo em Z, a frente deve ficar em -Z: flip se estiver em +Z.
	# Com o eixo longo em X, o giro de 90 graus leva +X para -Z: flip se a
	# frente estiver em -X.
	if along_z:
		return f > b
	return f < b


## AABB de todas as MeshInstance3D abaixo de `root`, no espaco de `root`.
## Usa as transforms LOCAIS: funciona com o no fora da arvore (testes).
static func mesh_aabb(root: Node3D) -> AABB:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	var out := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.mesh.get_aabb()
		var xf := _rel_transform(mi, root)
		for i in 8:
			var p: Vector3 = xf * box.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


## Triangulos somados de todas as superficies do modelo.
static func count_tris(root: Node3D) -> int:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	var n := 0
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			if arr.size() <= Mesh.ARRAY_VERTEX:
				continue
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				n += int(floor(float((idx as PackedInt32Array).size()) / 3.0))
			else:
				var verts: Variant = arr[Mesh.ARRAY_VERTEX]
				if verts is PackedVector3Array:
					n += int(floor(float((verts as PackedVector3Array).size()) / 3.0))
	return n


## Nos do modelo cujo nome indica roda (ex.: Quaternius "NormalCar1_FrontLeftWheel").
## Serve para girar/estercar as rodas do carro dirigivel e para o teste avisar
## quando um modelo novo vier com a malha toda soldada numa peca so.
static func wheel_nodes(root: Node) -> Array:
	var out: Array = []
	_collect_wheels(root, out)
	return out


## Todas as MeshInstance3D abaixo de `root` (uso publico, para a malha unica).
static func collect_meshes(root: Node) -> Array:
	var out: Array = []
	_collect_meshes(root, out)
	return out


## Transform de `node` relativa a `root` (uso publico).
static func rel_xf(node: Node3D, root: Node3D) -> Transform3D:
	return _rel_transform(node, root)


static func _collect_wheels(n: Node, out: Array) -> void:
	var low := String(n.name).to_lower()
	if low.contains("wheel") or low.contains("roda"):
		out.append(n)
		return
	for c in n.get_children():
		_collect_wheels(c, out)


static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


## Transform de `node` relativa a `root`, pelas transforms locais (sem
## depender de global_transform, que pode estar desatualizado fora da arvore).
static func _rel_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Carrega o modelo uma vez. Pode ser chamado de fora (o carro faz isso quando
## o _ready do no ainda nao rodou); a guarda impede carregar duas vezes.
func load_model() -> void:
	if _built:
		return
	_built = true
	if model_path.is_empty():
		stats_text = "modelo: caminho vazio"
		push_warning("ModelProp sem model_path")
		return

	var t0 := Time.get_ticks_usec()
	var scene: PackedScene = null
	if ResourceLoader.exists(model_path):
		var res: Resource = load(model_path)
		if res is PackedScene:
			scene = res as PackedScene
	load_ms = float(Time.get_ticks_usec() - t0) / 1000.0

	if scene == null:
		stats_text = "modelo %s: NAO carregou" % model_path.get_file()
		push_warning("ModelProp: %s nao carregou (rodar --import?)" % model_path)
		return

	var inst := scene.instantiate() as Node3D
	if inst == null:
		stats_text = "modelo %s: raiz nao e Node3D" % model_path.get_file()
		return

	size_m = mesh_aabb(inst).size
	tris = count_tris(inst)
	var found: Array = []
	_collect_meshes(inst, found)
	mesh_count = found.size()
	if mesh_count == 0:
		inst.free()
		stats_text = "modelo %s: sem malha" % model_path.get_file()
		return

	var box := mesh_aabb(inst)
	var pl := placement(inst, box, target_length)
	var center := box.get_center()

	# Pivo proprio: escala e giro ficam nele; o modelo e centrado e apoiado no
	# chao dentro dele. Assim a rotacao em Y nao desfaz o apoio no chao.
	var pivot := Node3D.new()
	pivot.name = "Normalized"
	pivot.scale = Vector3.ONE * float(pl[0])
	pivot.rotation.y = float(pl[1])
	inst.position = Vector3(-center.x, -box.position.y, -center.z)
	pivot.add_child(inst)
	add_child(pivot)

	wheel_info.clear()
	for w in wheel_nodes(inst):
		var n3 := w as Node3D
		if n3 == null:
			continue
		wheel_info.append({
			"node": n3,
			"rest": n3.transform,
			"front": String(n3.name).to_lower().contains("front"),
		})

	loaded = true
	stats_text = "modelo %s: %d malhas, %d tris, %.1f m, %.1f ms" % [
		model_path.get_file(), mesh_count, tris, target_length, load_ms]
