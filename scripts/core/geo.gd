extends RefCounted
## Geo: calculos geograficos puros sobre pontos [lon, lat] em graus.
## A projecao e equiretangular local, a mesma de tools/geo/polygon_area.py.

const R_EARTH := 6371008.8


## Area (m2) de um poligono [[lon, lat], ...] (anel aberto ou fechado).
static func polygon_area_m2(points: Array) -> float:
	var n := points.size()
	if n < 3:
		return 0.0
	var lat0 := 0.0
	for p in points:
		lat0 += float(p[1])
	lat0 /= float(n)
	var k := cos(deg_to_rad(lat0))
	var lon0: float = points[0][0]
	var sum := 0.0
	for i in n:
		var a: Array = points[i]
		var b: Array = points[(i + 1) % n]
		var ax := (float(a[0]) - lon0) * k
		var bx := (float(b[0]) - lon0) * k
		sum += ax * float(b[1]) - bx * float(a[1])
	var m_per_deg := R_EARTH * PI / 180.0
	return absf(sum) * 0.5 * m_per_deg * m_per_deg


static func polygon_area_km2(points: Array) -> float:
	return polygon_area_m2(points) / 1_000_000.0


## Ponto (lon, lat) dentro do poligono? (ray casting)
static func point_in_polygon(lon: float, lat: float, points: Array) -> bool:
	var inside := false
	var n := points.size()
	var j := n - 1
	for i in n:
		var xi := float(points[i][0])
		var yi := float(points[i][1])
		var xj := float(points[j][0])
		var yj := float(points[j][1])
		if (yi > lat) != (yj > lat):
			var x_cross := (xj - xi) * (lat - yi) / (yj - yi) + xi
			if lon < x_cross:
				inside = not inside
		j = i
	return inside


## Distancia em metros (haversine).
static func distance_m(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := p2 - p1
	var dl := deg_to_rad(lon2 - lon1)
	var s1 := sin(dp * 0.5)
	var s2 := sin(dl * 0.5)
	var a := s1 * s1 + cos(p1) * cos(p2) * s2 * s2
	return 2.0 * R_EARTH * asin(minf(1.0, sqrt(a)))


## Comprimento (m) de uma linha [[lon, lat], ...].
static func path_length_m(points: Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += distance_m(
			float(points[i - 1][0]), float(points[i - 1][1]),
			float(points[i][0]), float(points[i][1]))
	return total


static func _orient(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


## Poligono simples (sem auto-intersecao propria)?
static func is_simple(points: Array) -> bool:
	var n := points.size()
	if n < 3:
		return false
	var v: Array[Vector2] = []
	for p in points:
		v.append(Vector2(float(p[0]), float(p[1])))
	for i in n:
		var a := v[i]
		var b := v[(i + 1) % n]
		for j in range(i + 1, n):
			if j == i + 1 or (i == 0 and j == n - 1):
				continue
			var c := v[j]
			var d := v[(j + 1) % n]
			if _orient(a, b, c) * _orient(a, b, d) < 0.0 and _orient(c, d, a) * _orient(c, d, b) < 0.0:
				return false
	return true
