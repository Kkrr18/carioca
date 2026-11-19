#!/usr/bin/env python3
"""Mede a area do poligono do mundo e confere pontos de referencia.

Sem dependencias (so biblioteca padrao). Usa a mesma projecao equiretangular
local do jogo (scripts/core/geo.gd e scripts/core/cfg.gd), portanto a area
calculada aqui deve bater com a do runner do Godot.

Uso:
    python3 tools/geo/polygon_area.py
    python3 tools/geo/polygon_area.py --json data/geo/world_polygon.json
    python3 tools/geo/polygon_area.py --inside -43.2048 -22.98706
    python3 tools/geo/polygon_area.py --geojson /tmp/mundo.geojson

Licenca dos dados: ver data/ATTRIBUTION.md (ODbL para dados do OpenStreetMap).
"""

import argparse
import json
import math
import sys

R_EARTH = 6371008.8


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def ring(data):
    """Concatena os vertices dos grupos 'zones' em um anel unico."""
    pts = []
    for zone in data.get("zones", []):
        for node in zone.get("nodes", []):
            pts.append((float(node[0]), float(node[1])))
    return pts


def to_local(pts, origin_lon, origin_lat):
    lat0 = sum(p[1] for p in pts) / len(pts)
    k = math.cos(math.radians(lat0))
    m_lat = R_EARTH * math.pi / 180.0
    m_lon = m_lat * k
    return [((p[0] - origin_lon) * m_lon, (p[1] - origin_lat) * m_lat) for p in pts]


def area_km2(pts, origin_lon, origin_lat):
    loc = to_local(pts, origin_lon, origin_lat)
    s = 0.0
    n = len(loc)
    for i in range(n):
        x1, y1 = loc[i]
        x2, y2 = loc[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return abs(s) * 0.5 / 1e6


def point_in_polygon(lon, lat, pts):
    inside = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > lat) != (yj > lat):
            x_cross = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lon < x_cross:
                inside = not inside
        j = i
    return inside


def orient(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def is_simple(pts):
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            c, d = pts[j], pts[(j + 1) % n]
            if orient(a, b, c) * orient(a, b, d) < 0 and orient(c, d, a) * orient(c, d, b) < 0:
                return False, (i, j)
    return True, None


def haversine_m(a, b):
    lon1, lat1 = a
    lon2, lat2 = b
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2.0 * R_EARTH * math.asin(min(1.0, math.sqrt(h)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", default="data/geo/world_polygon.json")
    ap.add_argument("--inside", nargs=2, type=float, metavar=("LON", "LAT"))
    ap.add_argument("--geojson", help="grava o anel como GeoJSON")
    args = ap.parse_args()

    data = load(args.json)
    pts = ring(data)
    if len(pts) < 3:
        print("poligono com menos de 3 vertices", file=sys.stderr)
        return 2

    target = float(data.get("target_km2", 83.0))
    lo, hi = data.get("target_range_km2", [target * 0.9, target * 1.1])
    origin = data.get("origin", {})
    olon = float(origin.get("lon", pts[0][0]))
    olat = float(origin.get("lat", pts[0][1]))

    simple, pair = is_simple(pts)
    area = area_km2(pts, olon, olat)

    print("arquivo      : %s" % args.json)
    print("vertices     : %d" % len(pts))
    print("simples      : %s%s" % (simple, "" if simple else " (cruzam entre si: %s)" % (pair,)))
    print("area         : %.2f km2" % area)
    print("alvo         : %.1f km2 (faixa %.1f - %.1f)" % (target, lo, hi))
    if lo <= area <= hi:
        print("situacao     : DENTRO da faixa")
    else:
        print("situacao     : FORA da faixa (%.2f km2 de diferenca)" % (area - target))

    way = data.get("bridge_centerline", [])
    if len(way) > 1:
        total = sum(haversine_m(way[i - 1], way[i]) for i in range(1, len(way)))
        print("ponte        : %.2f km no eixo simplificado (oficial 13,29 km)" % (total / 1000.0))

    if args.inside:
        lon, lat = args.inside
        print("ponto        : (%.5f, %.5f) -> %s" % (
            lon, lat, "DENTRO" if point_in_polygon(lon, lat, pts) else "FORA"))

    if args.geojson:
        gj = {
            "type": "FeatureCollection",
            "features": [{
                "type": "Feature",
                "properties": {"name": data.get("name", "carioca"), "version": data.get("version", 1)},
                "geometry": {"type": "Polygon", "coordinates": [[[p[0], p[1]] for p in pts] + [[pts[0][0], pts[0][1]]]]},
            }],
        }
        with open(args.geojson, "w", encoding="utf-8") as f:
            json.dump(gj, f, indent=2)
        print("geojson      : %s" % args.geojson)

    return 0 if simple else 1


if __name__ == "__main__":
    sys.exit(main())
