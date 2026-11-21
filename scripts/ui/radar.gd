extends Control
## Radar: minimapa circular estilo GTA, desenhado por codigo (sem textura).
##
## - O mapa gira com a camera: a frente do jogador e sempre para cima.
## - Mar, areia da praia e ruas vem da MESMA grade do city_gen (64 m), entao o
##   radar e o chao contam a mesma cidade.
## - Blips: marcador de missao (amarelo), viaturas (azul piscando) e o jogador
##   (seta branca no centro). Marcador fora do alcance fica na borda do circulo,
##   como no GTA.
## - A geometria (rotacao, recorte do circulo e da faixa de areia/mar) e PURA e
##   testada no CI: `project`, `clip_segment` e `disc_below`.

const Ipanema = preload("res://scripts/game/ipanema.gd")

const MAP_METERS := 165.0        # raio de mundo mostrado (m)
const RING := 0.96               # fracao do raio usada pelo mapa
const SEA_COL := Color(0.08, 0.21, 0.33)
const SAND_COL := Color(0.52, 0.48, 0.37)
const CITY_COL := Color(0.13, 0.14, 0.15)
const ROAD_COL := Color(0.36, 0.37, 0.39)
const MISSION_COL := Color(1.00, 0.82, 0.16)
const COP_COL := Color(0.36, 0.62, 1.00)
const PLAYER_COL := Color(0.96, 0.97, 1.00)
const RING_COL := Color(0.88, 0.90, 0.94, 0.75)

var player = null
var police = null
var runner = null
## Foco do mapa: o carro (dirigindo) ou o personagem (a pe). O main manda.
var focus_pos := Vector3.ZERO
var focus_yaw := 0.0
var has_focus := false

var _ui := 1.0
var _radius := 90.0
var _center := Vector2.ZERO
var _pulse := 0.0
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_layout()


func _layout() -> void:
	var vs := get_viewport_rect().size
	_ui = clampf(vs.y * get_tree().root.content_scale_factor / 640.0, 1.15, 2.2)
	_radius = 92.0 * _ui
	_center = Vector2(_radius + 20.0 * _ui, vs.y - _radius - 26.0 * _ui)


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


# --- Geometria pura (testada no CI) ------------------------------------------

## Mundo -> radar. `delta` e a diferenca em metros (x, z) entre o alvo e o
## jogador; a rotacao usa o mesmo yaw da camera (frente = -Z do mundo).
static func project(delta: Vector2, yaw: float, scale: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(delta.x * c - delta.y * s, delta.x * s + delta.y * c) * scale


## Trecho do segmento a-b que cai dentro do circulo de raio r centrado na
## origem. Vazio quando o segmento nao toca o circulo (assim as ruas nunca
## vazam para fora do radar).
static func clip_segment(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := b - a
	var qa := d.dot(d)
	if qa < 1e-9:
		return out
	var qb := 2.0 * a.dot(d)
	var qc := a.dot(a) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return out
	var sq := sqrt(disc)
	var t1 := (-qb - sq) / (2.0 * qa)
	var t2 := (-qb + sq) / (2.0 * qa)
	if t2 < 0.0 or t1 > 1.0:
		return out
	out.append(a + d * maxf(t1, 0.0))
	out.append(a + d * minf(t2, 1.0))
	return out


## Poligono (em metros, relativo ao jogador) da parte do circulo de raio r que
## fica em z <= t. Usado para pintar o mar e a areia sem vazar do radar: a
## regiao e estrelada em relacao ao centro, entao basta ordenar por angulo.
static func disc_below(t: float, r: float, segments: int = 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	if t <= -r:
		return out
	if t >= r:
		for i in segments:
			var ang := TAU * float(i) / float(segments)
			out.append(Vector2(cos(ang), sin(ang)) * r)
		return out
	for i in segments:
		var ang := TAU * float(i) / float(segments)
		var p := Vector2(cos(ang), sin(ang)) * r
		if p.y <= t:
			out.append(p)
	var half := sqrt(maxf(0.0, r * r - t * t))
	out.append(Vector2(-half, t))
	out.append(Vector2(half, t))
	# Ordena por angulo em volta da origem: a regiao e estrelada, entao a
	# ordem angular e a ordem do contorno.
	var ordered := PackedVector2Array()
	var keys: Array = []
	for p in out:
		keys.append([atan2(p.y, p.x), p])
	keys.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	for k in keys:
		ordered.append(k[1])
	return ordered


# --- Desenho ------------------------------------------------------------------

func _draw() -> void:
	draw_circle(_center, _radius, CITY_COL)
	if player == null:
		_draw_frame()
		return
	var p: Vector3 = focus_pos if has_focus else player.position
	var yaw := focus_yaw if has_focus else float(player.cam_yaw)
	var r := _radius * RING
	var sc := r / MAP_METERS
	# Areia (z de 0 a BEACH_Z) e mar (z < 0): duas faixas recortadas no circulo.
	# O mar e pintado DEPOIS da areia e cobre a parte de tras dela.
	_disc(Ipanema.BEACH_Z - p.z, r, yaw, sc, SAND_COL)
	_disc(-p.z, r, yaw, sc, SEA_COL)
	_draw_roads(p, yaw, r, sc)
	_draw_blips(p, yaw, sc, r)
	_draw_player_arrow(r)
	_draw_north(yaw, r)
	_draw_frame()


## Pinta a parte do radar com z do mundo <= `z_limit`, limitada ao circulo.
func _disc(z_limit_rel: float, r: float, yaw: float, sc: float, col: Color) -> void:
	var pts := disc_below(z_limit_rel, MAP_METERS)
	if pts.size() < 3:
		return
	var mapped := PackedVector2Array()
	for v in pts:
		mapped.append(_center + project(v, yaw, sc))
	draw_colored_polygon(mapped, col)


## Ruas da grade (as mesmas do city_gen) recortadas no circulo.
func _draw_roads(p: Vector3, yaw: float, r: float, sc: float) -> void:
	var block := Ipanema.BLOCK
	var k0 := int(floor((p.x - MAP_METERS) / block))
	var k1 := int(ceil((p.x + MAP_METERS) / block))
	for k in range(k0, k1 + 1):
		var x := float(k) * block - p.x
		var seg := clip_segment(Vector2(x, -MAP_METERS), Vector2(x, MAP_METERS), MAP_METERS)
		if seg.size() == 2:
			draw_line(_center + project(seg[0], yaw, sc), _center + project(seg[1], yaw, sc),
					ROAD_COL, maxf(1.0, 2.0 * _ui))
	var j0 := int(floor((p.z - MAP_METERS - Ipanema.BEACH_Z) / block))
	var j1 := int(ceil((p.z + MAP_METERS - Ipanema.BEACH_Z) / block))
	for j in range(j0, j1 + 1):
		var z := Ipanema.BEACH_Z + float(j) * block - p.z
		var seg := clip_segment(Vector2(-MAP_METERS, z), Vector2(MAP_METERS, z), MAP_METERS)
		if seg.size() == 2:
			draw_line(_center + project(seg[0], yaw, sc), _center + project(seg[1], yaw, sc),
					ROAD_COL, maxf(1.0, 2.0 * _ui))


func _draw_blips(p: Vector3, yaw: float, sc: float, r: float) -> void:
	if runner != null and bool(runner.get("has_target")):
		var t: Vector3 = runner.get("target_pos")
		_blip(Vector2(t.x - p.x, t.z - p.z), yaw, sc, r, MISSION_COL, 5.0 * _ui, true)
	if police != null:
		for c in police.cops:
			var d: Dictionary = c
			if not bool(d.get("alive", true)):
				continue
			var node := d.get("node") as Node3D
			if node == null:
				continue
			var o: Vector3 = node.global_position
			var blink := 0.55 + 0.45 * sin(_pulse * 8.0)
			var col := COP_COL
			col.a = blink
			_blip(Vector2(o.x - p.x, o.z - p.z), yaw, sc, r, col, 4.5 * _ui, false)


## Marcador: losango no lugar certo ou preso na borda quando esta longe.
func _blip(delta: Vector2, yaw: float, sc: float, r: float, col: Color,
		sz: float, diamond: bool) -> void:
	if delta.length() < 0.01:
		return
	var m := project(delta, yaw, sc)
	if m.length() > r * 0.94:
		m = m.normalized() * r * 0.94
	var c := _center + m
	if diamond:
		var pts := PackedVector2Array([
			c + Vector2(0.0, -sz), c + Vector2(sz * 0.7, 0.0),
			c + Vector2(0.0, sz), c + Vector2(-sz * 0.7, 0.0)])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.1, 0.08, 0.0, 0.8), maxf(1.0, 1.2 * _ui))
	else:
		draw_circle(c, sz, col)


func _draw_player_arrow(r: float) -> void:
	var s := 7.0 * _ui
	var pts := PackedVector2Array([
		_center + Vector2(0.0, -s * 1.25),
		_center + Vector2(s * 0.85, s),
		_center + Vector2(0.0, s * 0.4),
		_center + Vector2(-s * 0.85, s)])
	draw_colored_polygon(pts, PLAYER_COL)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(0.05, 0.05, 0.06, 0.9), maxf(1.0, 1.0 * _ui))


## Letra N na direcao do norte do mundo (+Z), girando junto com o mapa.
func _draw_north(yaw: float, r: float) -> void:
	if _font == null:
		return
	var dir := project(Vector2(0.0, 1.0), yaw, 1.0)
	var at := _center + dir.normalized() * (r * 0.80)
	var size := int(13.0 * _ui)
	var w := _font.get_string_size("N", HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(_font, at + Vector2(-w * 0.5, size * 0.36), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.85))


func _draw_frame() -> void:
	draw_arc(_center, _radius, 0.0, TAU, 64, Color(0.05, 0.05, 0.06, 0.85), 5.0 * _ui)
	draw_arc(_center, _radius - 2.0 * _ui, 0.0, TAU, 64, RING_COL, maxf(1.0, 1.6 * _ui))
