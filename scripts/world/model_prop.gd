extends Node3D
## ModelProp: um modelo .glb externo (CC0) dentro do mundo procedural.
##
## Piloto de assets externos (Fase 1.5, B-21): prova o caminho completo —
## arquivo .glb no repositorio, import no CI, export Web e custo medido no
## aparelho — com UM arquivo e risco zero: se o modelo nao carregar, este no
## fica vazio, o motivo vai para o HUD e o resto do jogo nao muda.
##
## Por que normalizar por codigo: os pacotes CC0 vem em escala, eixo e pivo
## arbitrarios e nao ha como abrir o .glb no iPhone para conferir (B-21).
## Entao o modelo e medido pelo AABB e ajustado:
##   1. escala para `target_length` metros no maior eixo horizontal;
##   2. se o maior eixo for X, gira 90 graus — o comprimento fica em Z, que e
##      o eixo para onde carro/caminhao "apontam" neste jogo;
##   3. o ponto mais baixo vai para y = 0 e o centro X/Z para a origem, para o
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


func _ready() -> void:
	_load_model()


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


func _load_model() -> void:
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
	mesh_count = 0
	var found: Array = []
	_collect_meshes(inst, found)
	mesh_count = found.size()
	if mesh_count == 0:
		inst.free()
		stats_text = "modelo %s: sem malha" % model_path.get_file()
		return

	var box := mesh_aabb(inst)
	var norm := normalize_for(box.size, target_length)
	var center := box.get_center()

	# Pivo proprio: escala e giro ficam nele; o modelo e centrado e apoiado no
	# chao dentro dele. Assim a rotacao em Y nao desfaz o apoio no chao.
	var pivot := Node3D.new()
	pivot.name = "Normalized"
	pivot.scale = Vector3.ONE * float(norm[0])
	pivot.rotation.y = float(norm[1])
	inst.position = Vector3(-center.x, -box.position.y, -center.z)
	pivot.add_child(inst)
	add_child(pivot)

	loaded = true
	stats_text = "modelo %s: %d malhas, %d tris, %.1f m, %.1f ms" % [
		model_path.get_file(), mesh_count, tris, target_length, load_ms]
