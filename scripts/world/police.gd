extends Node3D
## Police: nivel de procurado e perseguicao policial (o "wanted" do GTA).
##
## - O calor (heat) e as estrelas vem de wanted.gd, que e puro. Aqui ficam as
##   VIATURAS: quantas, onde nascem, como perseguem, quando atiram, quando
##   prendem.
## - As viaturas andam sobre o MESMO chao analitico do jogador (Cfg.surface_at)
##   e desviam de predio pelo push_out do streamer: nao existe corpo de fisica
##   no mundo. Uma viatura e um no com 3 desenhos (carroceria assada + duas
##   lentes), entao cinco viaturas custam 15 chamadas de desenho.
## - Nada de caminho pre-calculado: o cerco e "busca direta" com limite de giro
##   e de velocidade. Em rua reta isso e o suficiente e custa quase nada no
##   iPhone; o que da a sensacao de perseguicao e a luz, o som do impacto e a
##   velocidade limite crescer com as estrelas.

signal shot_fired(from: Vector3)
signal busted()
signal cop_down()
signal heat_changed(heat: float, stars: int)

const Cfg = preload("res://scripts/core/cfg.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const Wanted = preload("res://scripts/game/wanted.gd")

const SPAWN_MIN := 90.0
const SPAWN_MAX := 155.0
const DESPAWN_NEAR := 150.0
const RAM_RADIUS := 3.4
const SHOOT_RANGE := 30.0
const LOST_SIGHT := 72.0

## Carroceria da viatura (assada numa malha so, cor por vertice).
const BODY_DARK := Color(0.10, 0.11, 0.13)
const BODY_WHITE := Color(0.86, 0.87, 0.88)
const BODY_GLASS := Color(0.22, 0.30, 0.38)
const TYRE := Color(0.07, 0.07, 0.08)
const BAR := Color(0.09, 0.09, 0.10)
const RED := Color(1.00, 0.16, 0.12)
const BLUE := Color(0.20, 0.42, 1.00)

var player = null
var streamer = null
var car = null

var heat := 0.0
var stars := 0
var cops: Array = []            # {node, yaw, speed, health, alive, shoot_t, ...}
var enabled := true

var _mesh: ArrayMesh
var _mat_body: StandardMaterial3D
var _mat_red: StandardMaterial3D
var _mat_blue: StandardMaterial3D
var _spawn_cool := 0.0
var _bust_t := 0.0
var _clock := 0.0
var _seen := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 90210
	_mesh = cop_mesh()
	_mat_body = StandardMaterial3D.new()
	_mat_body.vertex_color_use_as_albedo = true
	_mat_body.vertex_color_is_srgb = false
	_mat_body.roughness = 0.55
	_mat_body.metallic_specular = 0.45
	_mat_red = _light_material(RED)
	_mat_blue = _light_material(BLUE)


func _light_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.35
	return m


# --- Malha da viatura (pura; o CI pode medir) --------------------------------

## Malha da viatura: carroceria escura com porta branca, cabine de vidro, rodas
## e a base da barra de luz. Tudo em cor de vertice, uma superficie, um desenho.
static func cop_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	# Carroceria (frente em -Z, como todos os veiculos do jogo).
	_append_box(v, n, c, Vector3(0.0, 0.62, 0.0), Vector3(1.88, 0.72, 4.40), BODY_DARK)
	# Portas brancas: duas faixas nas laterais.
	for side in [-1.0, 1.0]:
		_append_box(v, n, c, Vector3(0.95 * side, 0.62, 0.0), Vector3(0.06, 0.58, 1.70), BODY_WHITE)
	# Cabine.
	_append_box(v, n, c, Vector3(0.0, 1.22, -0.15), Vector3(1.66, 0.52, 2.10), BODY_GLASS)
	# Capo e teto brancos (a viatura brasileira e branca com faixa escura).
	_append_box(v, n, c, Vector3(0.0, 1.50, -0.15), Vector3(1.70, 0.10, 2.14), BODY_WHITE)
	# Para-choques.
	_append_box(v, n, c, Vector3(0.0, 0.42, -2.26), Vector3(1.90, 0.30, 0.16), BAR)
	_append_box(v, n, c, Vector3(0.0, 0.42, 2.26), Vector3(1.90, 0.30, 0.16), BAR)
	# Base da barra de luz.
	_append_box(v, n, c, Vector3(0.0, 1.56, -0.15), Vector3(0.90, 0.10, 0.34), BAR)
	# Rodas (caixas: a 30 m de distancia leem como roda e custam nada).
	for pos in [
		Vector3(-0.92, 0.34, -1.42), Vector3(0.92, 0.34, -1.42),
		Vector3(-0.92, 0.34, 1.42), Vector3(0.92, 0.34, 1.42),
	]:
		_append_box(v, n, c, pos, Vector3(0.24, 0.66, 0.66), TYRE)
	return _mesh_from(v, n, c)


static func _append_box(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	for f in CityGen.CUBE_FACES:
		var fc: Vector3 = f[0]
		var ya: Vector3 = f[1]
		var za: Vector3 = f[2]
		var cc := center + Vector3(fc.x * h.x, fc.y * h.y, fc.z * h.z)
		var yv := Vector3(ya.x * h.x, ya.y * h.y, ya.z * h.z)
		var zv := Vector3(za.x * h.x, za.y * h.y, za.z * h.z)
		var a: Vector3 = cc - yv - zv
		var b: Vector3 = cc + yv - zv
		var d: Vector3 = cc + yv + zv
		var e: Vector3 = cc - yv + zv
		for p in [a, b, d, a, d, e]:
			v.append(p)
			n.append(fc)
			c.append(col)


static func _mesh_from(v: PackedVector3Array, n: PackedVector3Array,
		c: PackedColorArray) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- API de jogo ---------------------------------------------------------------

## Registra um crime: sobe o calor e, com ele, o numero de estrelas.
func report_crime(crime: String) -> void:
	var before := stars
	heat = Wanted.add(heat, crime)
	stars = Wanted.stars(heat)
	if stars != before:
		heat_changed.emit(heat, stars)


## Sobe o calor em um valor cru (usado pelo roteiro das missoes: "ao chegar
## aqui, a policia entra em cena com duas estrelas").
func raise_heat(amount: float) -> void:
	if amount <= 0.0:
		return
	var before := stars
	heat = clampf(maxf(heat, 0.0) + amount, 0.0, float(Wanted.MAX_STARS))
	stars = Wanted.stars(heat)
	if stars != before:
		heat_changed.emit(heat, stars)
## Zera o procurado e manda as viaturas embora (preso, morto ou missao).
func clear() -> void:
	heat = 0.0
	stars = 0
	_bust_t = 0.0
	for i in range(cops.size() - 1, -1, -1):
		_remove_cop(i)
	heat_changed.emit(0.0, 0)


func active_cops() -> int:
	var n := 0
	for c in cops:
		if bool(c["alive"]):
			n += 1
	return n


func nearest_distance(pos: Vector3) -> float:
	var best := 1.0e30
	for c in cops:
		if not bool(c["alive"]):
			continue
		var node := c["node"] as Node3D
		if node == null:
			continue
		best = minf(best, Vector2(node.global_position.x - pos.x,
				node.global_position.z - pos.z).length())
	return best


## Acha a viatura dentro do cone de tiro e aplica dano. Devolve {} (nada),
## {"hit": true, "killed": bool, "pos": Vector3}.
func damage_nearest(from: Vector3, dir: Vector3, reach: float, cone: float,
		dmg: float) -> Dictionary:
	var best := -1
	var best_d := reach
	var aim := dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	for i in cops.size():
		var c: Dictionary = cops[i]
		if not bool(c["alive"]):
			continue
		var node := c["node"] as Node3D
		if node == null:
			continue
		var d: Vector3 = node.global_position - from
		var dist := d.length()
		if dist < 0.05 or dist > best_d:
			continue
		if aim != Vector3.ZERO and d.normalized().dot(aim) < cos(cone):
			continue
		best_d = dist
		best = i
	if best < 0:
		return {}
	var cop: Dictionary = cops[best]
	cop["health"] = float(cop["health"]) - dmg
	var pos: Vector3 = (cop["node"] as Node3D).global_position
	if float(cop["health"]) <= 0.0:
		_kill(best)
		return {"hit": true, "killed": true, "pos": pos}
	return {"hit": true, "killed": false, "pos": pos}


# --- Ciclo ---------------------------------------------------------------------

func update(delta: float, focus: Vector3) -> void:
	if not enabled:
		return
	_clock += delta
	_spawn_cool = maxf(0.0, _spawn_cool - delta)
	_seen = nearest_distance(focus) <= LOST_SIGHT
	var before := stars
	heat = Wanted.decay(heat, delta, _seen)
	stars = Wanted.stars(heat)
	if stars != before:
		heat_changed.emit(heat, stars)
	_update_lights()
	_manage_cops(focus, delta)
	_step_cops(focus, delta)
	_check_bust(focus, delta)


func _update_lights() -> void:
	# Pisca-pisca: vermelho e azul alternados, so com procurado ativo.
	var phase := fmod(_clock, 0.46) < 0.23
	var red := 0.0
	var blue := 0.0
	if stars > 0:
		if phase:
			red = 3.2
		else:
			blue = 3.2
	if _mat_red != null:
		_mat_red.emission_energy_multiplier = red
	if _mat_blue != null:
		_mat_blue.emission_energy_multiplier = blue


func _manage_cops(focus: Vector3, delta: float) -> void:
	for i in range(cops.size() - 1, -1, -1):
		var c: Dictionary = cops[i]
		if not bool(c["alive"]):
			c["remove_t"] = float(c["remove_t"]) - delta
			if float(c["remove_t"]) <= 0.0:
				_remove_cop(i)
			continue
		var node := c["node"] as Node3D
		if node == null:
			_remove_cop(i)
			continue
		# Sem procurado, a viatura vai embora quando o jogador se afasta.
		if stars == 0:
			var away := Vector2(node.global_position.x - focus.x,
					node.global_position.z - focus.z).length()
			if away > DESPAWN_NEAR:
				_remove_cop(i)
	var want := Wanted.cop_count(stars)
	if cops.size() < want and _spawn_cool <= 0.0:
		if _spawn(focus):
			_spawn_cool = 3.5


func _spawn(focus: Vector3) -> bool:
	for _attempt in 8:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := Vector2(focus.x + cos(ang) * dist, focus.z + sin(ang) * dist)
		p.x = clampf(p.x, Cfg.WORLD_MIN.x + 40.0, Cfg.WORLD_MAX.x - 40.0)
		p.y = clampf(p.y, Cfg.WORLD_MIN.y + 40.0, Cfg.WORLD_MAX.y - 40.0)
		if Cfg.height_at(p.x, p.y) < Cfg.MIN_WADE_DEPTH:
			continue
		if streamer != null:
			var pushed: Vector2 = streamer.push_out(p.x, p.y, 2.2)
			p = pushed
		if Cfg.height_at(p.x, p.y) < Cfg.MIN_WADE_DEPTH:
			continue
		var node := Node3D.new()
		node.name = "Cop%d" % cops.size()
		var body := MeshInstance3D.new()
		body.mesh = _mesh
		body.material_override = _mat_body
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(body)
		var lamp_r := MeshInstance3D.new()
		var box_r := BoxMesh.new()
		box_r.size = Vector3(0.34, 0.12, 0.26)
		lamp_r.mesh = box_r
		lamp_r.material_override = _mat_red
		lamp_r.position = Vector3(-0.26, 1.62, -0.15)
		lamp_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lamp_r)
		var lamp_b := MeshInstance3D.new()
		var box_b := BoxMesh.new()
		box_b.size = Vector3(0.34, 0.12, 0.26)
		lamp_b.mesh = box_b
		lamp_b.material_override = _mat_blue
		lamp_b.position = Vector3(0.26, 1.62, -0.15)
		lamp_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lamp_b)
		node.global_position = Vector3(p.x, Cfg.surface_at(p.x, p.y), p.y)
		var yaw := atan2(-(focus.x - p.x), -(focus.z - p.y))
		node.rotation.y = yaw
		add_child(node)
		cops.append({
			"node": node,
			"yaw": yaw,
			"speed": 0.0,
			"health": Wanted.cop_health(stars),
			"alive": true,
			"shoot_t": _rng.randf_range(0.3, 1.2),
			"ram_t": 0.0,
			"remove_t": 0.0,
		})
		return true
	return false


func _remove_cop(i: int) -> void:
	if i < 0 or i >= cops.size():
		return
	var c: Dictionary = cops[i]
	var node := c["node"] as Node3D
	if node != null and is_instance_valid(node):
		node.queue_free()
	cops.remove_at(i)


func _kill(i: int) -> void:
	if i < 0 or i >= cops.size():
		return
	var c: Dictionary = cops[i]
	c["alive"] = false
	c["remove_t"] = 9.0
	var node := c["node"] as Node3D
	if node != null:
		node.rotation.z = PI * 0.42
	cop_down.emit()


func _step_cops(focus: Vector3, delta: float) -> void:
	var max_v := Wanted.cop_speed(maxi(1, stars))
	for c in cops:
		if not bool(c["alive"]):
			continue
		var node := c["node"] as Node3D
		if node == null:
			continue
		var pos := node.global_position
		var to := Vector2(focus.x - pos.x, focus.z - pos.z)
		var dist := to.length()
		var desired := atan2(-to.x, -to.y)
		var yaw := float(c["yaw"])
		yaw = lerp_angle(yaw, desired, clampf(2.9 * delta, 0.0, 1.0))
		c["yaw"] = yaw
		var want_v := max_v
		if dist < 14.0:
			want_v = maxf(0.0, (dist - 4.2) * 2.2)
		var diff := absf(wrapf(desired - yaw, -PI, PI))
		if diff > 0.75:
			want_v *= 0.55
		var v := move_toward(float(c["speed"]), want_v, 10.0 * delta)
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var next := pos + fwd * v * delta
		next.x = clampf(next.x, Cfg.WORLD_MIN.x, Cfg.WORLD_MAX.x)
		next.z = clampf(next.z, Cfg.WORLD_MIN.y, Cfg.WORLD_MAX.y)
		if streamer != null:
			var pushed: Vector2 = streamer.push_out(next.x, next.z, 1.3)
			if pushed.x != next.x or pushed.y != next.z:
				next.x = pushed.x
				next.z = pushed.y
				v *= 0.45
		next.y = Cfg.surface_at(next.x, next.z)
		node.global_position = next
		node.rotation.y = yaw
		c["speed"] = v

		# Encostao: machuca o carro do jogador ou o proprio jogador a pe.
		if dist < RAM_RADIUS + 1.4:
			c["ram_t"] = float(c["ram_t"]) - delta
			if float(c["ram_t"]) <= 0.0:
				c["ram_t"] = 0.9
				if player != null and player.enabled:
					player.add_damage(7.0)
					if player.has_method("push"):
						player.push(Vector3(to.x, 0.0, to.y).normalized())
				elif car != null and car.occupied:
					car.add_damage(0.045)

		# Tiro só a partir de duas estrelas, e só com o jogador a pe (dentro do
		# carro quem apanha é o carro, na batida).
		if player != null and player.enabled and stars >= 2 and dist < SHOOT_RANGE:
			c["shoot_t"] = float(c["shoot_t"]) - delta
			if float(c["shoot_t"]) <= 0.0:
				c["shoot_t"] = maxf(0.7, 1.5 - 0.14 * float(stars))
				shot_fired.emit(pos + Vector3(0.0, 1.2, 0.0))
				player.add_damage(Wanted.cop_damage(stars))


## Preso: a pe, com viatura perto por tempo suficiente.
func _check_bust(focus: Vector3, delta: float) -> void:
	if player == null or not player.enabled or stars <= 0:
		_bust_t = 0.0
		return
	if nearest_distance(focus) <= Wanted.arrest_radius():
		_bust_t += delta
		if _bust_t >= Wanted.arrest_seconds():
			clear()
			busted.emit()
	else:
		_bust_t = maxf(0.0, _bust_t - delta * 1.5)


func describe() -> String:
	return "policia: %d estrelas, %d viaturas (calor %.2f%s)" % [
		stars, active_cops(), heat, ", visto" if _seen else ""]
