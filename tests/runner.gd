extends SceneTree
## runner.gd: testes headless, sem abrir janela:
##   godot --headless --path . -s tests/runner.gd
## Sai com codigo 0 se tudo passar; 1 se qualquer teste falhar.
##
## Cobre o que NAO depende de GPU: area/geometria do poligono, conversao
## geo<->metros, determinismo da geracao, orcamento de vertices, normais,
## salvamento versionado e rejeicao de save corrompido. Desempenho de render
## NAO e testado aqui: precisa do aparelho (docs/OTIMIZACAO.md).

const Cfg = preload("res://scripts/core/cfg.gd")
const Geo = preload("res://scripts/core/geo.gd")
const CityGen = preload("res://scripts/world/city_gen.gd")
const SaveManager = preload("res://scripts/autoload/save_manager.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")
const PropMesh = preload("res://scripts/world/prop_mesh.gd")
const Car = preload("res://scripts/vehicles/car.gd")
const VehiclePhysics = preload("res://scripts/vehicles/vehicle_physics.gd")
const Surf = preload("res://scripts/core/surface_db.gd")
const PropBody = preload("res://scripts/physics/prop_body.gd")
const Damage = preload("res://scripts/physics/damage.gd")
const PropField = preload("res://scripts/physics/prop_field.gd")
const ModelProp = preload("res://scripts/world/model_prop.gd")
const Player = preload("res://scripts/player/player.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const VehicleAudio = preload("res://scripts/audio/vehicle_audio.gd")
const SectorStreamer = preload("res://scripts/world/sector_streamer.gd")
const Traffic = preload("res://scripts/world/traffic.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const Pedestrians = preload("res://scripts/world/pedestrians.gd")
const BoneAnim = preload("res://scripts/world/bone_anim.gd")
const Wanted = preload("res://scripts/game/wanted.gd")
const Ipanema = preload("res://scripts/game/ipanema.gd")
const Missions = preload("res://scripts/game/missions.gd")
const Police = preload("res://scripts/world/police.gd")
const Radar = preload("res://scripts/ui/radar.gd")
const GtaHud = preload("res://scripts/ui/gta_hud.gd")

var _pass := 0
var _fail := 0
var _known := 0
var _msgs: PackedStringArray = []
var _fails: PackedStringArray = []   # repetidas no fim: o log do CI chega truncado
var _json: Dictionary = {}
var _poly: Array = []


func _initialize() -> void:
	print("== CARIOCA testes %s ==" % Cfg.APP_VERSION)
	_load()
	_test_polygon_file()
	_test_polygon_area()
	_test_geo_roundtrip()
	_test_bridge_length()
	_test_landmarks()
	_test_determinism()
	_test_vertex_budget()
	_test_road_markings()
	_test_road_no_overlap()
	_test_ground_textures()
	_test_facade()
	_test_normals()
	_test_heights()
	_test_props()
	_test_prop_mesh()
	_test_prop_sector_budget()
	_test_facade_details()
	_test_car_physics()
	_test_surfaces()
	_test_prop_physics()
	_test_car_scene_enter_exit()
	_test_car_model_wheels_in_place()
	_test_model_prop()
	_test_model_asset()
	_test_car_models()
	_test_facing_and_roll()
	_test_curb()
	_test_traffic_pure()
	_test_traffic_specs()
	_test_traffic_lights()
	_test_traffic_models()
	_test_traffic_collision()
	_test_traffic_spacing_and_follow()
	_test_audio_pure()
	_test_sky()
	_test_render_budget()
	_test_pedestrians()
	_test_pedestrian_model()
	_test_pedestrian_life()
	_test_bone_activities()
	_test_wanted()
	_test_ipanema()
	_test_missions()
	_test_police_pure()
	_test_radar()
	_test_gta_hud_pure()
	_test_player_combat()
	_test_player_model()
	_test_protagonista_fbx()
	_test_head_model()
	_test_shops()
	_test_windows()
	_test_building_shapes()
	_test_scripts_compile()
	_test_save_roundtrip()
	_test_save_rejects()
	_test_sectors()
	print("")
	# Log curto de proposito: imprimir so o que deu errado (e os desvios
	# conhecidos). O log do CI chega truncado pelo fim, e com centenas de linhas
	# de "ok" o erro de runtime do Godot ficava fora da parte visivel.
	for m in _msgs:
		if m.begins_with("  FALHA") or m.begins_with("  DESVIO"):
			print(m)
	print("")
	# O log de um job que falha chega truncado no fim: repetir as falhas aqui e
	# o que garante que elas apareçam sem precisar abrir o log inteiro.
	if not _fails.is_empty():
		print("FALHAS:")
		for f in _fails:
			print("  - " + f)
		print("")
	print("RESULTADO: %d passaram, %d falharam, %d desvios conhecidos" % [_pass, _fail, _known])
	quit(0 if _fail == 0 else 1)


func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		_msgs.append("  ok    " + what)
	else:
		_fail += 1
		_msgs.append("  FALHA " + what)
		_fails.append(what)


func known(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		_msgs.append("  ok    " + what)
	else:
		_known += 1
		_msgs.append("  DESVIO " + what)


## Quanto uma animacao MEXE o esqueleto: a maior diferenca angular entre a
## primeira chave de uma trilha de rotacao e qualquer outra. `clip_motion` olha
## so o meio e o fim, e as atividades respiram em seno (a volta passa pelo zero):
## com ele, o clipe do celular mediria zero.
## Cuidado que ja custou um CI vermelho: a chave tem de ser comparada com as
## OUTRAS, entao o que interessa e a MENOR semelhanca (|dot|), nao a maior — a
## maior e sempre 1.0, porque toda chave e identica a si mesma.
func _anim_span(anim: Animation) -> float:
	var least := 1.0
	if anim == null:
		return 0.0
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var n := anim.track_get_key_count(ti)
		if n < 2:
			continue
		var a: Quaternion = anim.track_get_key_value(ti, 0)
		for k in n:
			var b: Quaternion = anim.track_get_key_value(ti, k)
			least = minf(least, absf(a.dot(b)))
	return 2.0 * acos(clampf(least, -1.0, 1.0))


## Quanto a POSE de uma atividade sai do repouso (o maior giro entre os ossos).
## Prova que a atividade posa o corpo: sem isso o NPC "faria" o gesto reto.
func _pose_top(kind: String, u: float) -> float:
	var top := 0.0
	var p: Dictionary = BoneAnim.pose(kind, u)
	for role in p.keys():
		top = maxf(top, (p[role] as Quaternion).get_angle())
	return top


func _load() -> void:
	var f := FileAccess.open("res://data/geo/world_polygon.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_json = parsed
	for z in _json.get("zones", []):
		for node in z.get("nodes", []):
			_poly.append([float(node[0]), float(node[1])])


# --- Poligono do mundo -------------------------------------------------------

func _test_polygon_file() -> void:
	check(not _json.is_empty(), "world_polygon.json carregado")
	check(_poly.size() >= 24, "poligono com %d vertices" % _poly.size())
	# B-14: o rascunho atual tem arestas que se cruzam. E dado, nao codigo do
	# jogo, e sera refeito a partir do OSM na Fase 2 — por isso DESVIO (known)
	# em vez de FALHA: CI vermelho para sempre esconde regressao de verdade.
	known(Geo.is_simple(_poly), "poligono simples (sem auto-intersecao)")
	check(_json.has("bridge_centerline"), "eixo da ponte presente")


func _test_polygon_area() -> void:
	if _poly.is_empty():
		check(false, "poligono vazio")
		return
	var km2 := Geo.polygon_area_km2(_poly)
	var target := float(_json.get("target_km2", 83.0))
	print("  info: area do poligono = %.2f km2 (alvo %.1f)" % [km2, target])
	known(absf(km2 - target) <= 6.0, "area dentro de +-6 km2 do alvo (%.1f vs %.1f)" % [km2, target])


func _test_geo_roundtrip() -> void:
	var p := Cfg.local_to_lonlat(1234.5, 678.9)
	var q := Cfg.lonlat_to_local(p.x, p.y)
	# Vector2 e float32: a ida e volta erra ~0,06 m por precisao, nao por bug.
	# Tolerancia de 0,2 m (era 0,01 e o CI acusava falha — B-31).
	check(absf(q.x - 1234.5) < 0.2 and absf(q.y - 678.9) < 0.2,
		"ida e volta lon/lat <-> metros (erro %.4f m)" % maxf(absf(q.x - 1234.5), absf(q.y - 678.9)))
	var d := Geo.distance_m(-43.1828, -22.9743, -43.1828, -22.9843)
	check(absf(d - 1111.9) < 2.0, "0,01 grau de latitude = %.1f m na esfera (esperado ~1111,9)" % d)


func _test_bridge_length() -> void:
	var way: Array = _json.get("bridge_centerline", [])
	var length_m := Geo.path_length_m(way)
	print("  info: eixo da ponte (simplificado) = %.2f km; oficial = 13,29 km" % (length_m / 1000.0))
	check(length_m > 10000.0 and length_m < 14000.0,
		"eixo da ponte com %.2f km" % (length_m / 1000.0))


func _test_landmarks() -> void:
	if _poly.is_empty():
		return
	var inside := [
		["Ipanema", -43.20480, -22.98706],
		["Copacabana", -43.18100, -22.97569],
		["Leblon", -43.22137, -22.98789],
		["Botafogo", -43.17992, -22.94540],
		["Flamengo", -43.16965, -22.92800],
		["Caju (inicio da ponte)", -43.21671, -22.88464],
		["Icaraí (Niteroi)", -43.11386, -22.90888],
	]
	# B-14: Ipanema, Copacabana, Leblon, Botafogo e Caju caem fora do anel do
	# rascunho. Volta a ser FALHA quando o poligono real (OSM, Fase 2) entrar.
	for item in inside:
		known(Geo.point_in_polygon(float(item[1]), float(item[2]), _poly),
			"%s dentro do mundo" % String(item[0]))
	var outside := [
		["Itacoatiara (Niteroi)", -43.03439, -22.97487],
		["Itaipu (Niteroi)", -43.04657, -22.97070],
	]
	for item in outside:
		check(not Geo.point_in_polygon(float(item[1]), float(item[2]), _poly),
			"%s fora do mundo (excluido nesta fase)" % String(item[0]))


# --- Geracao -----------------------------------------------------------------

func _verts(res: Array) -> PackedVector3Array:
	return res[0]


func _test_determinism() -> void:
	var a := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var b := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var c := CityGen.generate(3, 0, 99999, CityGen.LOD_FULL)
	check(_verts(a) == _verts(b), "mesmo seed => mesmos vertices (%d)" % _verts(a).size())
	check(_verts(a) != _verts(c), "seed diferente => mundo diferente")


func _test_vertex_budget() -> void:
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	var sea := CityGen.generate(3, -1, 20260922, CityGen.LOD_FULL)
	var vf := _verts(full).size()
	var vr := _verts(far).size()
	var vs := _verts(sea).size()
	var colliders: Array = full[3]
	var defs: Array = full[4]
	print("  info: setor full %d verts, far %d verts, mar %d verts, %d predios, %d props" % [
		vf, vr, vs, colliders.size(), defs.size()])
	check(vf > 3000, "setor cheio tem geometria (%d vertices)" % vf)
	check(vf < 40000, "setor full abaixo de 40k vertices (%d)" % vf)
	check(vr < vf, "LOD far mais leve que LOD full (%d < %d)" % [vr, vf])
	check(vs < 6000, "setor de mar so tem terreno (%d)" % vs)
	check(colliders.size() > 20, "setor cheio tem colisores (%d)" % colliders.size())
	check(defs.size() > 10, "setor da orla tem props (%d)" % defs.size())


func _test_road_markings() -> void:
	# Sinalizacao pintada (premissa de realismo): eixo amarelo, faixa de
	# pedestres e linha de retencao no LOD full; nada no LOD far, que e detalhe
	# de longe.
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	var yellow := 0
	var white := 0
	for c in (full[2] as PackedColorArray):
		if c.is_equal_approx(CityGen.MARK_YELLOW):
			yellow += 1
		elif c.is_equal_approx(CityGen.MARK_WHITE):
			white += 1
	check(yellow > 0, "sinalizacao: %d vertices de eixo amarelo" % yellow)
	check(white > 0, "sinalizacao: %d vertices de faixa branca" % white)
	var far_marks := 0
	for c in (far[2] as PackedColorArray):
		if c.is_equal_approx(CityGen.MARK_YELLOW) or c.is_equal_approx(CityGen.MARK_WHITE):
			far_marks += 1
	check(far_marks == 0, "sinalizacao so no LOD full (far: %d vertices)" % far_marks)


func _test_road_no_overlap() -> void:
	# B-52: duas superficies de asfalto na MESMA altura brigam por profundidade e
	# piscam a partir de ~150 m — na tela isso parece granulado na rua. O certo e
	# elas encostarem pela borda. Este teste garante que nenhum par de quads de
	# asfalto do setor tem AREA em comum.
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var v: PackedVector3Array = full[8]
	var quads: Array = []
	var i := 0
	while i + 5 < v.size():
		var a := v[i]
		var c := v[i + 2]
		quads.append(Rect2(minf(a.x, c.x), minf(a.z, c.z),
				absf(c.x - a.x), absf(c.z - a.z)))
		i += 6
	check(quads.size() > 30, "asfalto em %d quads por setor" % quads.size())
	var bad := 0
	for p in quads.size():
		var r: Rect2 = quads[p]
		for q in range(p + 1, quads.size()):
			var s: Rect2 = quads[q]
			var w: float = minf(r.position.x + r.size.x, s.position.x + s.size.x)
			w -= maxf(r.position.x, s.position.x)
			var dd: float = minf(r.position.y + r.size.y, s.position.y + s.size.y)
			dd -= maxf(r.position.y, s.position.y)
			if w > 0.01 and dd > 0.01:
				bad += 1
	check(bad == 0, "nenhum par de ruas sobreposto (%d pares)" % bad)


func _test_ground_textures() -> void:
	# Superficies texturadas (Fase 4, premissa de realismo): asfalto, calcada e
	# areia vem em buffers proprios, com UV em escala de mundo (a textura repete
	# por metro, sem esticar).
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	check(full.size() >= 20, "setor traz as superficies texturadas (%d arrays)" % full.size())
	if full.size() < 20:
		return
	var road_v: PackedVector3Array = full[8]
	var road_uv: PackedVector2Array = full[10]
	check(road_v.size() > 0, "asfalto texturado: %d vertices" % road_v.size())
	check(road_uv.size() == road_v.size(), "asfalto com 1 UV por vertice")
	check((full[11] as PackedVector3Array).size() > 0,
		"calcada texturada: %d vertices" % (full[11] as PackedVector3Array).size())
	check((full[14] as PackedVector3Array).size() > 0,
		"areia texturada: %d vertices" % (full[14] as PackedVector3Array).size())
	check((full[17] as PackedVector3Array).size() > 0,
		"calcadao texturado: %d vertices" % (full[17] as PackedVector3Array).size())
	var span := 0.0
	for uv in road_uv:
		span = maxf(span, maxf(absf(uv.x), absf(uv.y)))
	check(span > 2.0, "UV do asfalto em escala de mundo (max %.1f)" % span)
	# O mar continua com cor por vertice: nao recebe textura de areia.
	var sea := CityGen.generate(3, -1, 20260922, CityGen.LOD_FULL)
	check((sea[14] as PackedVector3Array).is_empty(), "mar sem textura de areia")
	check((sea[0] as PackedVector3Array).size() > 0, "mar com geometria de cor por vertice")


func _test_facade() -> void:
	# Padrao da fachada dos predios: parede clara, janela escura E acesa (o
	# mapa de emissao e o que faz a janela brilhar a noite).
	var wall := SectorStreamer.facade_value(0.05, 0.5)
	var win := SectorStreamer.facade_value(0.5, 0.5)
	check(wall.x > 0.8 and wall.y < 0.01, "parede clara e sem brilho (%.2f)" % wall.x)
	check(win.x < 0.5 and win.y > 0.9, "janela escura e acesa (%.2f)" % win.x)
	var lit := 0
	for i in 64:
		for j in 64:
			if SectorStreamer.facade_value(float(i) / 64.0, float(j) / 64.0).y > 0.5:
				lit += 1
	check(lit > 400 and lit < 1600,
		"janelas ocupam a faixa esperada do modulo (%d de 4096 pontos)" % lit)


func _test_normals() -> void:
	var res := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var v: PackedVector3Array = res[0]
	var n: PackedVector3Array = res[1]
	check(v.size() == n.size(), "vertices e normais com o mesmo tamanho")
	check(v.size() % 3 == 0, "vertices em multiplos de 3")
	# Godot 4: frente de face = sentido horario visto de fora => a normal de
	# frente e -(b-a) x (d-a). Ela deve coincidir com a normal salva.
	var bad := 0
	var tested := 0
	var i := 0
	while i + 2 < v.size() and tested < 500:
		var a := v[i]
		var b := v[i + 1]
		var d := v[i + 2]
		var front := -(b - a).cross(d - a)
		if front.length() > 0.0001:
			tested += 1
			if front.normalized().dot(n[i]) < 0.9:
				bad += 1
		i += 3
	check(tested > 100 and bad == 0, "winding coerente com as normais (%d/%d)" % [tested - bad, tested])


func _test_heights() -> void:
	var h0 := Cfg.height_at(100.0, -50.0)
	var h1 := Cfg.height_at(100.0, 120.0)
	var h2 := Cfg.height_at(100.0, 400.0)
	var h3 := Cfg.height_at(100.0, 2300.0)
	check(h0 < 0.0, "mar abaixo do nivel (%.2f m)" % h0)
	check(h1 > 0.0 and h1 < 1.5, "praia acima do nivel (%.2f m)" % h1)
	check(h2 > h1, "cidade acima da praia (%.2f m > %.2f m)" % [h2, h1])
	check(h3 > 3.0, "interior sobe (%.2f m a 2,3 km)" % h3)


func _test_props() -> void:
	var ok := true
	for s in ["palm", "tree", "bush", "kiosk", "umbrella", "caixa_dagua", "casa_maquinas", "antena", "palm_crown", "tree_crown"]:
		var sh := PropFactory.shape_for(s, 6.0)
		if sh.size() != 2:
			ok = false
			continue
		var size: Vector3 = sh[1]
		if size.length() < 0.4 or size.length() > 20.0:
			ok = false
	check(ok, "props com forma plausivel (10 tipos)")
	# B-52: vegetacao virou tronco + copa. A coluna verde unica era a coisa mais
	# feia da cidade; agora o tronco e marrom e a copa e verde, no alto.
	var trunk := PropFactory.color_for("palm", 0.5)
	var crown := PropFactory.color_for("palm_crown", 0.5)
	check(trunk.r > trunk.g and crown.g > crown.r,
		"palmeira: tronco marrom e copa verde (r %.2f / g %.2f)" % [trunk.r, crown.g])
	check(float(PropFactory.shape_for("palm_crown", 7.0)[0]) >= 7.0,
		"copa da palmeira fica no alto do tronco")
	check(float(PropFactory.shape_for("tree_crown", 9.0)[0]) > 5.0,
		"copa da arvore fica acima do meio do tronco")


## B-80: os props deixaram de ser CUBOS e passaram a ter malha de verdade
## (PropMesh). Este teste cobre o que da para conferir sem GPU: cada tipo tem
## geometria, a base fica no chao, a normal de cada face aponta para fora
## (winding coerente), a luminaria tem buffer emissivo e o orcamento de
## triangulos do setor inteiro continua cabendo num telefone.
func _test_prop_mesh() -> void:
	var kinds := [
		["palm", 7.0], ["palm_crown", 7.0], ["tree", 8.0], ["tree_crown", 8.0],
		["bush", 3.0], ["poste", 5.5], ["lampadaria", 5.5], ["banco", 0.6],
		["lixeira", 1.0], ["kiosk", 3.2], ["umbrella", 2.2], ["caixa_dagua", 1.5],
		["casa_maquinas", 2.5], ["antena", 4.8], ["carro", 1.3],
		["ar_condicionado", 0.62], ["planta", 1.2], ["pedra", 1.2],
		["placa", 3.0], ["hidrante", 1.0], ["cadeira", 0.8],
	]
	var empty: Array = []
	var bad_vert: Array = []
	var bad_norm: PackedStringArray = PackedStringArray()
	var sunk: Array = []
	for entry in kinds:
		var kind := String(entry[0])
		var h := float(entry[1])
		var m: Dictionary = PropMesh.build(kind, h, 0.5)
		if m.is_empty():
			empty.append(kind)
			continue
		var solid = m["solid"]
		var v: PackedVector3Array = solid.v
		var n: PackedVector3Array = solid.n
		var c: PackedColorArray = solid.c
		if v.is_empty() or v.size() % 3 != 0 or n.size() != v.size() or c.size() != v.size():
			bad_vert.append(kind)
			continue
		# Base no chao: nada abaixo de y = 0 (o def traz a altura do chao).
		var lowest := 1e9
		var i := 0
		while i + 2 < v.size():
			var a := v[i]
			var b := v[i + 1]
			var d := v[i + 2]
			lowest = minf(lowest, minf(a.y, minf(b.y, d.y)))
			var front := -(b - a).cross(d - a)
			if front.length() > 0.0001 and front.normalized().dot(n[i]) < 0.9:
				if not bad_norm.has(kind):
					bad_norm.append(kind)
			i += 3
		if lowest < -0.02:
			sunk.append(kind)
	check(empty.is_empty(), "todos os tipos de prop tem malha%s" % (
		"" if empty.is_empty() else " - sem malha: " + ",".join(empty)))
	check(bad_vert.is_empty(), "props com vertices/normais/cores coerentes%s" % (
		"" if bad_vert.is_empty() else " - errados: " + ",".join(bad_vert)))
	check(bad_norm.is_empty(), "props com winding coerente (normal para fora)%s" % (
		"" if bad_norm.is_empty() else " - invertidos: " + ",".join(bad_norm)))
	check(sunk.is_empty(), "props apoiados no chao%s" % (
		"" if sunk.is_empty() else " - enterrados: " + ",".join(sunk)))
	# A luminaria e a UNICA coisa no buffer emissivo (o que acende a noite).
	var lamp: Dictionary = PropMesh.build("lampadaria", 5.5, 0.5)
	var glow = lamp["glow"]
	check((glow.v as PackedVector3Array).size() > 0, "luminaria com disco de luz (emissivo)")
	var post: Dictionary = PropMesh.build("poste", 5.5, 0.5)
	check((post["glow"].v as PackedVector3Array).is_empty(),
		"poste nao acende (so a luminaria no buffer emissivo)")
	var car_solid: PackedVector3Array = PropMesh.build("carro", 1.3, 0.5)["solid"].v
	check(car_solid.size() > 0, "carro parado tem malha propria")
	# A copa da palmeira tem de cair no TOPO do tronco: e a mesma conta usada
	# pelos dois defs ("palm" e "palm_crown").
	var top := PropMesh.palm_top(7.0)
	check(absf(top.y - 7.0) < 0.001 and top.x > 0.4,
		"copa da palmeira no topo do tronco inclinado (%.2f, %.2f)" % [top.x, top.y])
	# Tipo desconhecido nao pode estourar: devolve vazio e o setor nao desenha.
	check(PropMesh.build("tipo_que_nao_existe", 1.0, 0.5).is_empty(),
		"tipo de prop desconhecido devolve malha vazia")
	# AO por vertice (B-81): a cor escurece perto do chao. Teste puro no helper,
	# com uma caixa de cor 1.0: o topo tem de ficar 1.0 e a base, bem escura.
	var buf := PropMesh.MBuf.new()
	PropMesh.box(buf, Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0))
	PropMesh.ao_shade(buf, 1.0, 0.50)
	var lo := 2.0
	var hi := 0.0
	for i in buf.v.size():
		if buf.v[i].y < 0.1:
			lo = minf(lo, buf.c[i].r)
		elif buf.v[i].y > 0.9:
			hi = maxf(hi, buf.c[i].r)
	check(lo < 0.55 and hi > 0.95,
		"AO por vertice: base escurece e topo fica inteiro (%.2f / %.2f)" % [lo, hi])


## B-80: o setor entrega os props como GEOMETRIA (nao mais como lista de cubos),
## e o orcamento do setor inteiro tem de continuar de pe. Este teste e a rede de
## seguranca do que roda no iPhone: 9 setores em cena ao mesmo tempo.
func _test_prop_sector_budget() -> void:
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	check(full.size() >= 34, "setor traz props e areia molhada (%d arrays)" % full.size())
	if full.size() < 34:
		return
	var pv: PackedVector3Array = full[25]
	var pn: PackedVector3Array = full[26]
	var pc: PackedColorArray = full[27]
	var gv: PackedVector3Array = full[28]
	print("  info: props do setor = %d vertices (%d tris), %d de luz, %d defs" % [
		pv.size(), int(pv.size() / 3), gv.size(), (full[4] as Array).size()])
	check(pv.size() > 6000, "setor tem geometria de props (%d vertices)" % pv.size())
	# Teto de triangulos: ~130k vertices = 43k tris por setor. Com 4 setores em
	# cena isso e o que separa "cidade detalhada" de "jogo que trava".
	check(pv.size() < 130000, "props do setor abaixo do teto (%d vertices)" % pv.size())
	check(pn.size() == pv.size() and pc.size() == pv.size(),
		"props com 1 normal e 1 cor por vertice")
	check(gv.size() > 0, "setor tem luminarias emissivas (%d vertices)" % gv.size())
	# LOD far nao tem props: e detalhe de perto e custa vertices que o anel
	# distante nao precisa (o mesmo criterio de postes e arvores de calcada).
	check((far[25] as PackedVector3Array).is_empty(), "LOD far sem geometria de props")
	# Areia molhada: existe na praia e nao no mar.
	check((full[31] as PackedVector3Array).size() > 0,
		"areia molhada na faixa do mar (%d vertices)" % (full[31] as PackedVector3Array).size())
	var sea := CityGen.generate(3, -1, 20260922, CityGen.LOD_FULL)
	check((sea[31] as PackedVector3Array).is_empty(), "mar sem areia molhada")


## B-81: a fachada deixou de ser so o prisma com a textura. Varanda (laje +
## guarda-corpo) e embasamento de pedra entram no buffer de cor por vertice, so
## no LOD full — de longe o predio continua o bloco liso. Este teste confere que
## as duas cores chegam ao setor e que NAO vazam para o LOD far.
func _test_facade_details() -> void:
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	var slab := 0
	var plinth := 0
	for c in (full[2] as PackedColorArray):
		if c.is_equal_approx(CityGen.BALCONY_SLAB):
			slab += 1
		elif c.is_equal_approx(CityGen.PLINTH):
			plinth += 1
	check(slab > 0, "fachada com varanda na cor da laje (%d vertices)" % slab)
	check(plinth > 0, "predio assentado em embasamento (%d vertices)" % plinth)
	var far_detail := 0
	for c in (far[2] as PackedColorArray):
		if c.is_equal_approx(CityGen.BALCONY_SLAB) or c.is_equal_approx(CityGen.PLINTH):
			far_detail += 1
	check(far_detail == 0, "varanda e embasamento so no LOD full (far: %d)" % far_detail)


## Quadros a 60 Hz ate o carro parar freando, para comparar pisos (B-67).
func _brake_frames(sp: Dictionary, speed: float, mu: float) -> int:
	var st := {"speed": speed, "gear": 3, "shift_cool": 0.0}
	var dt := 1.0 / 60.0
	for i in 900:
		st = VehiclePhysics.step(sp, st, -1.0, 0.0, mu, dt)
		if float(st["speed"]) == 0.0:
			return i + 1
	return 0


func _test_car_physics() -> void:
	# Nucleos PUROS (sem cena, sem GPU): vehicle_physics.gd (B-67) e o que sobrou
	# de puro em car.gd. E o MESMO step() que roda no jogo com o dedo no pedal,
	# entao um numero errado aqui e um carro errado na mao do jogador.
	var sp := VehiclePhysics.sedan()
	var mass := float(sp["mass"])
	check(mass >= 1400.0 and mass <= 1500.0, "sedan de 1450 kg")
	check(absf(float(sp["wheelbase"]) - Car.WHEELBASE) < 0.01,
		"entre-eixos da fisica casa com o desenho do carro")
	check(absf(float(sp["wheel_radius"]) - Car.WHEEL_RADIUS) < 0.01,
		"raio da fisica casa com a roda que gira")
	# Motor: pico no meio do giro, fraco na lenta e no corte.
	var t_idle := VehiclePhysics.engine_torque(sp, 800.0)
	var t_peak := VehiclePhysics.engine_torque(sp, 4000.0)
	var t_red := VehiclePhysics.engine_torque(sp, 6500.0)
	check(t_peak > t_idle and t_peak > t_red,
		"curva de torque tem pico no meio (%.0f/%.0f/%.0f Nm)" % [t_idle, t_peak, t_red])
	# Cambio: a mesma velocidade gira mais alto na 1a que na 4a, e a 1a puxa mais.
	check(VehiclePhysics.rpm_for(sp, 10.0, 1) > VehiclePhysics.rpm_for(sp, 10.0, 4),
		"1a marcha gira mais alto que a 4a na mesma velocidade")
	var f1 := VehiclePhysics.drive_force(sp, 1, 1.0, 3000.0)
	var f4 := VehiclePhysics.drive_force(sp, 4, 1.0, 3000.0)
	check(f1 > f4 * 2.5, "1a marcha tem mais forca que a 4a (%.0f x %.0f N)" % [f1, f4])
	# Arrasto cresce com o quadrado da velocidade.
	var d10 := VehiclePhysics.drag_force(sp, 10.0)
	var d20 := VehiclePhysics.drag_force(sp, 20.0)
	check(absf(d20 - d10 * 4.0) < 0.01,
		"arrasto quadruplica ao dobrar a velocidade (%.0f N a 72 km/h)" % d20)
	# Peso: as 4 cargas somam m*g; frear carrega a frente; curva carrega o lado
	# de fora (curva para a esquerda joga o peso nas rodas da direita).
	var still: Array = VehiclePhysics.normal_loads(sp, 0.0, 0.0)
	var total_load := 0.0
	for l in still:
		total_load += float(l)
	check(absf(total_load - mass * VehiclePhysics.GRAVITY) < 1.0,
		"soma das cargas nas rodas = peso (%.0f N)" % total_load)
	var brake_loads: Array = VehiclePhysics.normal_loads(sp, -8.0, 0.0)
	check(float(brake_loads[0]) > float(still[0]) and float(brake_loads[2]) < float(still[2]),
		"frear joga peso para a frente")
	var curve_loads: Array = VehiclePhysics.normal_loads(sp, 0.0, 8.0)
	var front_outer := float(curve_loads[1]) > float(curve_loads[0])
	var rear_outer := float(curve_loads[3]) > float(curve_loads[2])
	check(front_outer and rear_outer, "curva carrega as rodas de fora")
	# Circulo de aderencia: o pneu nunca passa de mu*carga (ABS/TCS de graca).
	var tf := VehiclePhysics.tire_force(30000.0, 0.0, 5000.0, Surf.MU_ASPHALT, 8.0)
	check(absf(tf.length() - 5000.0) < 0.5, "pedido acima do limite e cortado em mu*carga")
	var tf2 := VehiclePhysics.tire_force(1000.0, 0.0, 5000.0, Surf.MU_ASPHALT, 8.0)
	check(absf(tf2.x - 1000.0) < 0.5, "pedido abaixo do limite e atendido inteiro")
	# 0-100 km/h com o step() do jogo: asfalto, plano, pedal em baixo.
	var dt := 1.0 / 60.0
	var run := {"speed": 0.0, "gear": 1, "shift_cool": 0.0}
	var t100 := -1.0
	for i in 2400:
		run = VehiclePhysics.step(sp, run, 1.0, 0.0, Surf.MU_ASPHALT, dt)
		if t100 < 0.0 and float(run["speed"]) >= 100.0 / 3.6:
			t100 = (i + 1) * dt
	check(t100 > 4.0 and t100 < 16.0, "0-100 km/h em %.1f s" % t100)
	check(int(run["gear"]) >= 3,
		"cambio automatico subiu de marcha (marcha %d)" % int(run["gear"]))
	var top := float(run["speed"]) * 3.6
	check(top > 108.0, "passa de 108 km/h em 40 s (%.0f km/h)" % [top])
	# Pisos: areia freia mais longe que asfalto (mu menor, ABS corta antes).
	var brake_asp := _brake_frames(sp, 20.0, Surf.MU_ASPHALT)
	var brake_sand := _brake_frames(sp, 20.0, Surf.MU_SAND)
	check(brake_asp > 0 and brake_sand > brake_asp + 20,
		"areia freia mais longe que asfalto (%d x %d quadros)" % [brake_sand, brake_asp])
	# O freio leva a velocidade a EXATAMENTE zero (nao engata a re sozinho).
	var stop := {"speed": 5.0, "gear": 2, "shift_cool": 0.0}
	var frames := 0
	while frames < 300 and float(stop["speed"]) > 0.0:
		stop = VehiclePhysics.step(sp, stop, -1.0, 0.0, Surf.MU_ASPHALT, dt)
		frames += 1
	check(float(stop["speed"]) == 0.0 and frames > 1,
		"freio para exatamente em zero (em %d quadros)" % frames)
	# Acelerador solto perde velocidade (arrasto + rolamento).
	var coast := {"speed": 10.0, "gear": 3, "shift_cool": 0.0}
	for i in 60:
		coast = VehiclePhysics.step(sp, coast, 0.0, 0.0, Surf.MU_ASPHALT, dt)
	check(float(coast["speed"]) < 9.9,
		"acelerador solto perde velocidade (%.2f m/s em 1 s)" % float(coast["speed"]))
	# Marcha a re satura em REVERSE_MAX.
	var rev := {"speed": 0.0, "gear": 1, "shift_cool": 0.0}
	for i in 1200:
		rev = VehiclePhysics.step(sp, rev, -1.0, 0.0, Surf.MU_ASPHALT, dt)
	check(absf(float(rev["speed"]) + VehiclePhysics.REVERSE_MAX) < 0.05,
		"marcha a re satura em REVERSE_MAX (%.2f m/s)" % float(rev["speed"]))
	# Subida freia mais que o plano (gravidade no sentido do movimento).
	var flat := {"speed": 12.0, "gear": 2, "shift_cool": 0.0}
	var up := {"speed": 12.0, "gear": 2, "shift_cool": 0.0}
	for i in 60:
		flat = VehiclePhysics.step(sp, flat, 1.0, 0.0, Surf.MU_ASPHALT, dt)
		up = VehiclePhysics.step(sp, up, 1.0, 0.08, Surf.MU_ASPHALT, dt)
	var up_speed := float(up["speed"])
	var flat_speed := float(flat["speed"])
	var slope_note := "subida de 8 por cento freia mais que o plano (%.1f x %.1f m/s)" % [up_speed, flat_speed]
	check(up_speed < flat_speed - 0.3, slope_note)
	# Guinada (modelo bicycle) continua em car.gd e inverte na re.
	check(Car.yaw_rate(10.0, 0.3) > 0.0 and Car.yaw_rate(-10.0, 0.3) < 0.0,
		"taxa de guinada inverte na marcha a re (modelo bicycle)")
	check(Car.steer_limit(20.0) < Car.steer_limit(0.0) * 0.7,
		"esterco maximo cai com a velocidade")
	# B-68: o autor pediu "deixa o volante virar um pouco mais, ta muito
	# limitado". Parado o volante passa de 40 graus e a 18 km/h o carro ainda
	# fecha uma curva de menos de 4 m de raio.
	check(Car.steer_limit(0.0) >= 0.70,
		"volante vira 40+ graus parado (%.2f rad)" % Car.steer_limit(0.0))
	var turn_radius := Car.WHEELBASE / tan(Car.steer_limit(5.0))
	check(turn_radius < 4.0,
		"raio de curva abaixo de 4 m a 18 km/h (%.1f m)" % turn_radius)
	# ESP (B-70): no limite lateral corta o acelerador; freando, nao faz nada.
	check(VehiclePhysics.esp_throttle(0.0, 1.0) == 1.0,
		"com pneu agarrado o ESP nao mexe no acelerador")
	check(VehiclePhysics.esp_throttle(0.9, 1.0) < 0.5,
		"no limite lateral o ESP corta o acelerador (%.2f)" % VehiclePhysics.esp_throttle(0.9, 1.0))
	check(VehiclePhysics.esp_throttle(0.9, -1.0) == -1.0,
		"freando o ESP nao corta nada")
	var on := VehiclePhysics.esp_active(0.8, 1.0)
	var off := VehiclePhysics.esp_active(0.1, 1.0)
	check(on and not off, "ESP so aparece no HUD quando age")
	# Impacto em parede por ANGULO (B-70): de frente para, raspando desliza.
	var head := VehiclePhysics.wall_hit(Vector2(0.0, -10.0), Vector2(0.0, 1.0), 22.0)
	var graze := VehiclePhysics.wall_hit(Vector2(-9.4, -3.4), Vector2(0.0, 1.0), 22.0)
	var head_left: Vector2 = head[0]
	var graze_left: Vector2 = graze[0]
	check(head_left.length() < 1.5,
		"batida de frente mata o embalo (%.1f m/s)" % head_left.length())
	check(graze_left.length() > head_left.length() * 4.0,
		"raspando a parede o carro desliza (%.1f x %.1f m/s)" % [
			graze_left.length(), head_left.length()])
	check(float(graze[1]) < float(head[1]),
		"de frente machuca mais que de raspao (%.3f x %.3f)" % [
			float(head[1]), float(graze[1])])
	# Esportivo (B-70): mais leve e mais forte que o sedan.
	var sport := VehiclePhysics.sport()
	var sedan := VehiclePhysics.sedan()
	check(float(sport["mass"]) < 1300.0,
		"esportivo e mais leve que o sedan (%.0f kg)" % float(sport["mass"]))
	check(VehiclePhysics.power_to_weight(sport) > VehiclePhysics.power_to_weight(sedan) * 1.25,
		"esportivo puxa mais que o sedan (%.1f x %.1f m/s2)" % [
			VehiclePhysics.power_to_weight(sport), VehiclePhysics.power_to_weight(sedan)])


func _test_surfaces() -> void:
	# B-69: UMA tabela de superficies para o jogo inteiro (carro, objetos, som).
	check(Surf.kinds().size() >= 10, "%d superficies no banco" % Surf.kinds().size())
	check(Surf.kind_at(1600.0, -5.0) == "water", "mar e agua")
	check(Surf.kind_at(1600.0, 96.0) == "sand", "praia e areia")
	check(Surf.kind_at(1600.0, 120.0) == "stone", "calcadao e pedra portuguesa")
	check(Surf.kind_at(1600.0, 140.0) == "asphalt", "rua e asfalto")
	check(Surf.kind_at(1608.0, 140.0) == "concrete", "calcada e concreto")
	check(Surf.mu_at(1600.0, 96.0) < Surf.mu_at(1600.0, 140.0),
		"areia agarra menos o PNEU que o asfalto (%.2f x %.2f)" % [
			Surf.mu_at(1600.0, 96.0), Surf.mu_at(1600.0, 140.0)])
	check(Surf.slide("sand") > Surf.slide("asphalt"),
		"areia agarra mais uma CAIXA arrastada que o asfalto")
	check(Surf.bounce("metal") > Surf.bounce("sand"), "metal quica mais que areia")
	# O carro passou a ler ESTA tabela: uma fonte so, nenhum numero duplicado.
	check(absf(VehiclePhysics.surface_mu(1600.0, 96.0) - Surf.mu_at(1600.0, 96.0)) < 0.0001,
		"aderencia do carro vem do SurfaceDB")
	var all_ok := true
	for k in Surf.kinds():
		var kind := String(k)
		if Surf.mu(kind) <= 0.0 or Surf.slide(kind) <= 0.0 or Surf.hardness(kind) <= 0.0:
			all_ok = false
	check(all_ok, "toda superficie tem atrito e resistencia positivos")


## Quadros ate a caixa parar deslizando, para comparar pisos (B-69).
func _slide_time(mu: float) -> int:
	var ground := Cfg.surface_at(1600.0, 140.0)
	var b := PropBody.make("caixa",
			Vector3(1600.0, ground + PropBody.half_height("caixa"), 140.0), 0.0)
	b["vel"] = Vector3(6.0, 0.0, 0.0)
	PropBody.wake(b)
	for i in 900:
		PropBody.step(b, 1.0 / 60.0, ground, mu, 0.1)
		if bool(b["rest"]):
			return i + 1
	return 0


func _test_prop_physics() -> void:
	# B-69: objeto movel com massa, impulso, atrito, quique, sono e 3 estados de
	# dano. E o MESMO codigo que o prop_field.gd roda no jogo.
	var ground := Cfg.surface_at(100.0, 500.0)
	var box := PropBody.make("caixa", Vector3(100.0, ground + 4.0, 500.0), 0.0)
	for i in 300:
		PropBody.step(box, 1.0 / 60.0, ground, Surf.slide("asphalt"), Surf.bounce("asphalt"))
	var half := PropBody.half_height("caixa")
	check(absf(float(box["pos"].y) - (ground + half)) < 0.02,
		"caixa cai e pousa no chao analitico (y %.2f, esperado %.2f)" % [
			float(box["pos"].y), ground + half])
	check(bool(box["rest"]), "caixa parada DORME (fisica congelada no iPhone)")
	# Impulso acorda o objeto e vira velocidade.
	PropBody.impulse(box, Vector3(1.0, 0.0, 0.0), 140.0)
	check(not bool(box["rest"]) and float(box["vel"].x) > 1.0,
		"impulso acorda e empurra (%.1f m/s)" % float(box["vel"].x))
	# Mesma forca, massas diferentes: a caixa leve sai mais que a lixeira pesada.
	var bin := PropBody.make("lixeira", Vector3(100.0, ground, 500.0), 0.0)
	PropBody.impulse(bin, Vector3(1.0, 0.0, 0.0), 140.0)
	check(float(box["vel"].x) > float(bin["vel"].x) * 1.2,
		"a mesma forca move mais a caixa (%.1f) que a lixeira (%.1f)" % [
			float(box["vel"].x), float(bin["vel"].x)])
	# Atrito por piso nos objetos (slide, nao o mu do pneu).
	var on_asphalt := _slide_time(Surf.slide("asphalt"))
	var on_sand := _slide_time(Surf.slide("sand"))
	check(on_asphalt > 0 and on_sand > 0 and on_sand < on_asphalt,
		"areia para a caixa antes do asfalto (%d x %d quadros)" % [on_sand, on_asphalt])
	# Dano: 3 estados por material, e o que cada impacto quebra.
	check(Damage.state_for(100.0, 100.0) == Damage.INTACT, "vida cheia = intacto")
	check(Damage.state_for(30.0, 100.0) == Damage.DAMAGED, "menos da metade = danificado")
	check(Damage.state_for(0.0, 100.0) == Damage.DESTROYED, "vida zero = destruido")
	check(Damage.hit_power(1450.0, 10.0) > Damage.resistance("wood"),
		"carro a 36 km/h quebra caixa de madeira")
	check(Damage.hit_power(1450.0, 2.0) < Damage.resistance("metal"),
		"carro a 7 km/h nao quebra lixeira de metal")
	check(Damage.hit_power(80.0, 3.0) < Damage.resistance("glass"),
		"pedestre andando nao quebra vidro")
	check(Damage.debris_count("glass") > Damage.debris_count("stone"),
		"vidro faz mais destrocos que pedra")
	check(Damage.power_scale(0.0) == 1.0 and Damage.power_scale(1.0) < 0.6,
		"avaria total tira mais da metade do motor")
	var s0 := Damage.state_from_damage(0.2)
	var s1 := Damage.state_from_damage(0.5)
	var s2 := Damage.state_from_damage(0.9)
	check(s0 == Damage.INTACT and s1 == Damage.DAMAGED and s2 == Damage.DESTROYED,
		"avaria do carro em 3 estados")
	var hit := PropBody.make("caixa", Vector3.ZERO, 0.0)
	var st := PropBody.apply_damage(hit, Damage.hit_power(1450.0, 15.0))
	check(st == Damage.DESTROYED and not bool(hit["alive"]),
		"caixa atropelada a 54 km/h vira destroco")
	var safe := PropBody.make("caixa", Vector3.ZERO, 0.0)
	PropBody.apply_damage(safe, Damage.hit_power(80.0, 3.0))
	check(bool(safe["alive"]) and int(safe["state"]) == Damage.INTACT,
		"empurrao de pedestre nao destroi a caixa")
	# B-71: objeto posicionado no chao nasce DORMINDO e, dormindo, nao integra
	# (era o "props 20 (20 acordados)" que aparecia no build Web parado).
	var snoozing := PropBody.make("caixa", Vector3(100.0, 0.0, 500.0), 0.0)
	PropBody.place_on_ground(snoozing, ground)
	check(bool(snoozing["rest"]), "objeto posto no chao nasce dormindo")
	for i in 120:
		PropBody.step(snoozing, 1.0 / 60.0, ground, 0.62, 0.1)
	check(absf(float(snoozing["pos"].y) - (ground + half)) < 0.001,
		"e dormindo nao afunda nem treme (y %.2f)" % float(snoozing["pos"].y))
	# Avaria do carro: o `power` que o car.gd passa ao step tira aceleracao.
	var sp := VehiclePhysics.sedan()
	var fresh := {"speed": 0.0, "gear": 1, "shift_cool": 0.0}
	var wrecked := {"speed": 0.0, "gear": 1, "shift_cool": 0.0}
	for i in 60:
		fresh = VehiclePhysics.step(sp, fresh, 1.0, 0.0, Surf.MU_ASPHALT, 1.0 / 60.0)
		wrecked = VehiclePhysics.step(sp, wrecked, 1.0, 0.0, Surf.MU_ASPHALT,
				1.0 / 60.0, Damage.power_scale(1.0))
	check(float(wrecked["speed"]) < float(fresh["speed"]) * 0.75,
		"carro destruido acelera bem menos (%.1f x %.1f m/s)" % [
			float(wrecked["speed"]), float(fresh["speed"])])


func _test_car_scene_enter_exit() -> void:
	# B-38: separa "a logica de entrar e andar funciona" de "o toque chegou".
	# Monta uma cena minima (personagem + carro) no root do SceneTree e faz o
	# MESMO caminho do botao ENTRAR: ocupa, acelera pelo pedal ACEL, sai.
	# Sem GPU e sem dedo: se isto passa, o que falta e so a entrada de toque.
	if root == null:
		known(false, "cena do carro (SceneTree.root indisponivel)")
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var player := Player.new()
	player.streamer = null
	holder.add_child(player)
	var car := Car.new()
	car.player = player
	car.streamer = null
	car.position = Vector3(1600.0, Cfg.height_at(1600.0, 96.0), 96.0)
	car.rotation.y = PI * 0.5
	holder.add_child(car)
	# Em `-s` (headless) o motor so propaga o _ready dos nos adicionados em
	# _initialize no primeiro quadro, que aqui nunca chega (quit() no fim).
	# Chamar o _ready na mao reproduz o mesmo caminho do jogo; nao duplica
	# nada porque nao ha quadro seguinte.
	if player.camera == null:
		player._ready()
	if car.camera == null:
		car._ready()

	check(car.camera != null and player.camera != null, "cena do carro montou (cameras)")
	if car.camera == null or player.camera == null:
		holder.free()
		return

	check(not car.occupied, "carro comeca livre")
	car.toggle_occupant()
	check(car.occupied, "ENTRAR ocupa o carro")
	check(not player.enabled, "entrar desliga o personagem")
	check(not player.visible, "entrar esconde o personagem")
	check(car.camera.current, "camera do carro assume ao entrar")

	# 1 s de pedal ACEL, a 30 Hz: a mesma entrada que o TouchControls entrega.
	var start: Vector3 = car.position
	TouchControls.pedal_gas_s = true
	for i in 30:
		car._drive(1.0 / 30.0)
	TouchControls.pedal_gas_s = false
	check(car.input_throttle > 0.99, "pedal ACEL chega ao carro (throttle %.2f)" % car.input_throttle)
	check(car.speed > 1.0, "carro ganha velocidade (%.1f m/s)" % car.speed)
	var moved: float = car.position.distance_to(start)
	check(moved > 1.0, "carro anda de verdade (%.1f m em 1 s)" % moved)

	car.toggle_occupant()
	check(not car.occupied, "SAIR libera o carro")
	check(player.enabled and player.visible, "sair devolve o personagem")
	check(player.camera.current, "camera do personagem volta ao sair")
	holder.free()


func _test_car_model_wheels_in_place() -> void:
	# B-39 no carro de verdade: monta o carro COM o modelo CC0 e confere que
	# girar a roda nao move o centro dela. Antes, o giro era aplicado no no do
	# .glb (cuja origem fica no centro do modelo) e a roda orbitava o carro.
	var holder := Node3D.new()
	root.add_child(holder)
	var car := Car.new()
	car.model_path = "res://assets/models/quaternius-car.glb"
	holder.add_child(car)
	if car.camera == null:
		car._ready()   # em -s o _ready nao roda antes do quit (ver teste acima)
	check(car.model_loaded, "carro carregou o modelo CC0 do sedan")
	check(car._model_wheels.size() >= 3, "carro com %d rodas do modelo" % car._model_wheels.size())
	var ok := true
	var detail := ""
	for wi in car._model_wheels:
		var pivot := wi["node"] as Node3D
		if pivot == null or pivot.get_child_count() == 0:
			ok = false
			detail = "roda sem pivo"
			continue
		var wheel := pivot.get_child(0) as Node3D
		if wheel == null:
			ok = false
			detail = "roda nao e Node3D"
			continue
		var before: Vector3 = ModelProp.rel_xf(wheel, car) * ModelProp.mesh_aabb(wheel).get_center()
		pivot.rotation.x = 0.7
		var after: Vector3 = ModelProp.rel_xf(wheel, car) * ModelProp.mesh_aabb(wheel).get_center()
		var drift := before.distance_to(after)
		if drift > 0.002:
			ok = false
			detail = "centro andou %.3f m" % drift
	check(ok, "girar a roda nao move o centro dela (nao orbita o carro) %s" % detail)
	holder.free()


func _test_model_prop() -> void:
	# Piloto de asset (B-21): a normalizacao e pura e garante que um modelo de
	# qualquer escala/eixo vire `alvo` metros no eixo Z — o eixo em que carro e
	# caminhao "apontam" neste jogo.
	var a: Array = ModelProp.normalize_for(Vector3(2.0, 1.0, 4.0), 6.0)
	check(absf(float(a[0]) - 1.5) < 0.001 and absf(float(a[1])) < 0.001,
		"modelo de 4 m em Z escala para 6 m sem girar")
	var b: Array = ModelProp.normalize_for(Vector3(4.0, 1.0, 2.0), 6.0)
	check(absf(float(b[0]) - 1.5) < 0.001 and absf(float(b[1]) - PI * 0.5) < 0.001,
		"modelo de 4 m em X gira 90 graus e escala para 6 m")
	var c: Array = ModelProp.normalize_for(Vector3(1.0, 1.0, 1.0), 5.0)
	check(absf(float(c[0]) - 5.0) < 0.001, "modelo cubico escala pelo maior eixo (%.2f)" % float(c[0]))


func _test_model_asset() -> void:
	# B-21: o primeiro asset externo do jogo. O CI roda `--import` antes deste
	# teste, entao aqui se valida o caminho completo ate o Godot: arquivo no
	# repositorio -> PackedScene importada -> AABB -> normalizacao.
	var path := "res://assets/models/vehicle-truck-red.glb"
	check(FileAccess.file_exists(path), "asset .glb no repositorio")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := 0
	if f != null:
		bytes = int(f.get_length())
		f.close()
	check(bytes > 50000, "asset .glb com %d bytes (nao truncado)" % bytes)
	if not ResourceLoader.exists(path):
		known(false, "asset .glb importado pelo Godot (rodar --import antes)")
		return
	var res: Resource = load(path)
	check(res is PackedScene, "asset .glb importado como PackedScene")
	if not (res is PackedScene):
		return
	var inst := (res as PackedScene).instantiate() as Node3D
	check(inst != null, "raiz do modelo e Node3D")
	if inst == null:
		return
	var box: AABB = ModelProp.mesh_aabb(inst)
	check(box.size.x > 0.01 and box.size.y > 0.01 and box.size.z > 0.01,
		"modelo com volume (%.2f x %.2f x %.2f m)" % [box.size.x, box.size.y, box.size.z])
	var norm: Array = ModelProp.normalize_for(box.size, 5.4)
	var scaled: Vector3 = box.size * float(norm[0])
	var along: float = scaled.x if absf(float(norm[1])) > 0.1 else scaled.z
	check(absf(along - 5.4) < 0.05, "normalizado para 5,4 m de comprimento (%.2f)" % along)
	var tris: int = ModelProp.count_tris(inst)
	check(tris > 0, "modelo com %d triangulos" % tris)
	inst.free()


func _test_car_models() -> void:
	# Modelos CC0 da Quaternius (pack "Cars"), trazidos para a frota da Fase 4.
	# O CI prova o caminho todo: arquivo -> import -> PackedScene -> AABB,
	# triangulos e nos de roda. E este teste que vai avisar se um modelo novo
	# vier pesado, com dimensao estranha ou com as rodas soldadas na carroceria.
	var models := [
		["res://assets/models/quaternius-car.glb", "sedan"],
		["res://assets/models/quaternius-suv.glb", "suv"],
		["res://assets/models/quaternius-sports-car.glb", "esportivo"],
		["res://assets/models/quaternius-taxi.glb", "taxi"],
	]
	for m in models:
		var path := String(m[0])
		var label := String(m[1])
		check(FileAccess.file_exists(path), "modelo %s no repositorio" % label)
		if not FileAccess.file_exists(path):
			continue
		if not ResourceLoader.exists(path):
			known(false, "modelo %s importado (rodar --import antes)" % label)
			continue
		var res: Resource = load(path)
		check(res is PackedScene, "modelo %s importado como PackedScene" % label)
		if not (res is PackedScene):
			continue
		var inst := (res as PackedScene).instantiate() as Node3D
		if inst == null:
			check(false, "modelo %s com raiz Node3D" % label)
			continue
		var box: AABB = ModelProp.mesh_aabb(inst)
		var tris: int = ModelProp.count_tris(inst)
		var wheels: int = ModelProp.wheel_nodes(inst).size()
		print("  info: %s = %d tris, %.2f x %.2f x %.2f m, %d nos de roda" % [
			label, tris, box.size.x, box.size.y, box.size.z, wheels])
		check(tris > 500 and tris < 12000, "modelo %s com %d triangulos" % [label, tris])
		check(box.size.z > 3.0 and box.size.z < 6.0,
			"modelo %s com %.2f m de comprimento (eixo Z)" % [label, box.size.z])
		check(box.size.y < 2.5, "modelo %s com %.2f m de altura" % [label, box.size.y])
		check(wheels >= 2, "modelo %s com %d nos de roda separados" % [label, wheels])
		# B-40: o teste antigo lia a ORIGEM do no da roda, que no .glb fica no
		# centro do modelo — tudo dava zero e a deteccao de frente nunca funcionou.
		# Agora o centro vem do AABB da malha, entao tem que haver separacao real.
		var zmin := 9999.0
		var zmax := -9999.0
		for w in ModelProp.wheel_centers(inst):
			var c: Vector3 = w["center"]
			zmin = minf(zmin, c.z)
			zmax = maxf(zmax, c.z)
		check(zmax - zmin > 1.0,
			"modelo %s com eixos dianteiro e traseiro separados (%.2f m)" % [label, zmax - zmin])
		inst.free()


func _wheel_rig(front_z: float) -> Node3D:
	# Raiz com duas rodas (nomes como os da Quaternius): a dianteira em front_z.
	# Cada roda e uma MeshInstance3D COM malha: o centro e lido do AABB da malha,
	# nao da origem do no (B-40).
	var root := Node3D.new()
	var wheel := BoxMesh.new()
	wheel.size = Vector3(0.25, 0.7, 0.7)
	for spec in [["FrontLeftWheel", front_z], ["BackLeftWheel", -front_z]]:
		var mi := MeshInstance3D.new()
		mi.name = String(spec[0])
		mi.mesh = wheel
		mi.position = Vector3(0.8, 0.3, float(spec[1]))
		root.add_child(mi)
	return root


func _test_facing_and_roll() -> void:
	# Frente do modelo em -Z (como o carro dirigivel). Rodas "front" no lado +Z
	# pedem meia volta; no lado -Z, nao.
	var box := AABB(Vector3(-1.0, 0.0, -2.0), Vector3(2.0, 1.0, 4.0))
	var ok_root := _wheel_rig(-1.4)
	var bad_root := _wheel_rig(1.4)
	check(not ModelProp.facing_flip(ok_root, box), "frente das rodas em -Z: modelo nao gira")
	check(ModelProp.facing_flip(bad_root, box), "frente das rodas em +Z: modelo gira meia volta")
	var p_ok: Array = ModelProp.placement(ok_root, box, 4.0)
	var p_bad: Array = ModelProp.placement(bad_root, box, 4.0)
	check(absf(float(p_ok[1])) < 0.001 and absf(float(p_bad[1]) - PI) < 0.001,
		"placement soma meia volta so quando a frente esta errada")
	ok_root.free()
	bad_root.free()
	# Pivo proprio da roda (B-39): girar o no do .glb fazia a roda ORBITAR o
	# carro (a origem do no fica no centro do modelo) e o "eixo" saia errado
	# quando o no continha as duas rodas de um mesmo eixo.
	var in_car := Transform3D(Basis(Vector3.UP, 0.6), Vector3(2.0, 0.6, 3.0))
	var center := Vector3(2.0, 0.32, 3.0)
	var pivot_xf := Transform3D(Basis(), center)
	var local := Car.wheel_in_pivot(in_car, center)
	check((pivot_xf * local).is_equal_approx(in_car),
		"pivo da roda mantem a roda exatamente onde ela estava")
	check(local.origin.is_equal_approx(in_car.origin - center),
		"pivo da roda fica no centro dela, nao na origem do modelo")
	var top := center + Vector3(0.0, 0.35, 0.0)
	var rolled := center + Basis(Vector3.RIGHT, -0.2) * (top - center)
	check(rolled.z < center.z, "rodar para frente leva o topo da roda para -Z")


func _test_traffic_pure() -> void:
	# Transito basico (Fase 4): nucleo puro de scripts/world/traffic.gd.
	check(fmod(Traffic.ORIGIN.x, Cfg.BLOCK_SIZE) == 0.0 and Traffic.ORIGIN.y == Cfg.CITY_MIN_Z,
		"grade do transito cai nas linhas de rua do city_gen")
	check(Traffic.LANE < Cfg.ROAD_WIDTH * 0.5,
		"faixa do carro cabe dentro da rua (%.1f m)" % Traffic.LANE)
	check(Traffic.right_of(Vector2i(1, 0)) == Vector2i(0, 1),
		"mao direita: indo para leste, a faixa fica a +Z")

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var escolha_ok := true
	for i in 4000:
		var n := Vector2i(rng.randi_range(0, Traffic.GRID.x - 1), rng.randi_range(0, Traffic.GRID.y - 1))
		var h: Vector2i = dirs[rng.randi_range(0, 3)]
		var nh := Traffic.choose_heading(n, h, rng.randf())
		if not Traffic.valid(n + nh):
			escolha_ok = false
	check(escolha_ok, "cruzamento nunca escolhe rua fora da grade")

	var a := Traffic.spawn_car(5, 0, 0)
	var b := Traffic.spawn_car(5, 0, 0)
	check(a["node"] == b["node"] and a["h"] == b["h"], "mesmo seed, mesmo carro de transito")

	var sim: Array = []
	for k in 12:
		sim.append(Traffic.spawn_car(1000 + k * 7919, k, 0))
	for step in 6000:
		for c in sim:
			Traffic.advance(c, 1.0 / 30.0, float(step) / 30.0)
	var sim_ok := true
	for c in sim:
		if not Traffic.valid(c["node"]):
			sim_ok = false
	check(sim_ok, "12 carros por 3 min de jogo continuam dentro da grade")

	# Sem teleporte: o passo de um quadro nunca passa de velocidade + deslize
	# lateral. Cobre as curvas, onde o no muda de sentido.
	var one := Traffic.spawn_car(42, 0, 0)
	var prev := Traffic.pose(one).origin
	var worst := 0.0
	for i in 3000:
		Traffic.advance(one, 1.0 / 30.0, float(i) / 30.0)
		var cur := Traffic.pose(one).origin
		worst = maxf(worst, Vector2(cur.x - prev.x, cur.z - prev.z).length())
		prev = cur
	var bound := (Traffic.SPEED_MAX + Traffic.LAT_RATE) / 30.0 + 0.001
	check(worst <= bound, "carro nao teleporta nas curvas (passo maximo %.3f m, limite %.3f)" % [worst, bound])

	# O modelo olha para o sentido da rua (frente = -Z local).
	for h in dirs:
		var c := {"node": Vector2i(3, 2), "h": h, "s": 0.0, "lat": Vector2.ZERO,
			"speed": 0.0, "rng": rng, "model": 0, "index": 0}
		var fwd: Vector3 = -Traffic.pose(c).basis.z
		check(absf(fwd.x - float(h.x)) < 0.001 and absf(fwd.z - float(h.y)) < 0.001,
			"modelo aponta para o sentido %s" % str(h))


func _test_curb() -> void:
	# Calcada com meio-fio: a superficie do miolo da quadra sobe CURB_HEIGHT e o
	# chao de quem anda acompanha (Cfg.surface_at). Se nao acompanhasse, o
	# personagem afundaria 15 cm ao subir na calcada.
	check(absf(Cfg.curb_at(0.0, 200.0)) < 0.001, "rua sem meio-fio")
	check(absf(Cfg.curb_at(6.5, 200.0) - Cfg.CURB_HEIGHT) < 0.001,
		"calcada levantada %.2f m" % Cfg.curb_at(6.5, 200.0))
	check(absf(Cfg.curb_at(6.5, 131.0)) < 0.001, "avenida (z = 131) sem meio-fio")
	check(absf(Cfg.curb_at(6.5, 40.0)) < 0.001, "praia sem meio-fio")
	check(absf(Cfg.curb_at(6.5, 2400.0)) < 0.001, "fora da cidade sem meio-fio")
	check(absf(Cfg.curb_at(-6.5, 200.0)) < 0.001, "x negativo sem meio-fio")
	check(absf(Cfg.surface_at(6.5, 200.0) - Cfg.height_at(6.5, 200.0) - Cfg.CURB_HEIGHT) < 0.001,
		"surface_at soma o meio-fio na calcada")
	check(absf(Cfg.surface_at(0.0, 200.0) - Cfg.height_at(0.0, 200.0)) < 0.001,
		"surface_at = terreno na rua")
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	print("  info: setor com meio-fio = %d vertices (LOD far %d)" % [
		(_verts(full) as PackedVector3Array).size(), (_verts(far) as PackedVector3Array).size()])
	check((_verts(full) as PackedVector3Array).size() < 40000, "setor com meio-fio ainda abaixo de 40k vertices")


## B-70: cada modelo da rua tem ficha propria (massa, freio, centro de gravidade).
func _test_traffic_specs() -> void:
	var sedan := Traffic.spec_for_model(0)
	var suv := Traffic.spec_for_model(1)
	var sport := Traffic.spec_for_model(2)
	check(float(suv["mass"]) > float(sedan["mass"]) * 1.3,
		"SUV da rua e mais pesado que o sedan (%.0f x %.0f kg)" % [
			float(suv["mass"]), float(sedan["mass"])])
	var suv_corner := Traffic.corner_speed(suv)
	var sedan_corner := Traffic.corner_speed(sedan)
	var sport_corner := Traffic.corner_speed(sport)
	check(suv_corner < sedan_corner and sport_corner > sedan_corner,
		"esquina: SUV mais devagar que sedan e esportivo (%.1f/%.1f/%.1f m/s)" % [
			suv_corner, sedan_corner, sport_corner])
	check(Traffic.brake_of(suv) < Traffic.brake_of(sedan),
		"SUV freia mais devagar que o sedan (%.1f x %.1f m/s2)" % [
			Traffic.brake_of(suv), Traffic.brake_of(sedan)])
	check(Traffic.cruise_speed(sport, 1.0) > Traffic.cruise_speed(suv, 1.0),
		"esportivo anda mais que o SUV na mesma avenida (%.1f x %.1f m/s)" % [
			Traffic.cruise_speed(sport, 1.0), Traffic.cruise_speed(suv, 1.0)])
	# Carro com ficha nao salta para o cruzeiro num quadro: acelera pela ficha.
	var car := Traffic.spawn_car(7, 0, 1)          # modelo 1 = SUV
	Traffic.apply_spec(car)
	car["v"] = 0.0
	var cruise := float(car["speed"])
	# Instante com o semaforo aberto no sentido dele (fechado, o carro freia).
	var open_t := 0.0
	for i in 60:
		var cand := float(i) * 0.5
		if not Traffic.must_stop(car["node"], car["h"], 0.0, cand):
			open_t = cand
			break
	Traffic.advance(car, 0.2, open_t)
	var after_one := float(car["v"])
	Traffic.advance(car, 2.0, open_t)
	check(after_one > 0.0 and after_one < cruise * 0.6,
		"carro nao salta para o cruzeiro num quadro (%.2f m/s)" % after_one)
	check(float(car["v"]) > after_one,
		"e vai ganhando velocidade (%.1f m/s)" % float(car["v"]))
	# Sem ficha (dicionario montado a mao) o modelo antigo continua valendo.
	var old := Traffic.spawn_car(9, 1, 0)
	Traffic.advance(old, 0.5, 0.0)
	check(not old.has("v"),
		"carro sem ficha nao ganha velocidade real (modelo antigo intacto)")


func _test_traffic_lights() -> void:
	# Semaforos: ciclo puro, parada na linha de retencao e travessia no verde.
	var ns_green := false
	var ns_yellow := false
	var ew_green := false
	var ew_yellow := false
	var both_green := false
	var t := 0.0
	while t < Traffic.LIGHT_CYCLE:
		var st := Traffic.light_states(Vector2i(0, 0), t)
		ns_green = ns_green or st.x == 2
		ns_yellow = ns_yellow or st.x == 1
		ew_green = ew_green or st.y == 2
		ew_yellow = ew_yellow or st.y == 1
		if st.x == 2 and st.y == 2:
			both_green = true
		t += 0.25
	check(ns_green and ns_yellow and ew_green and ew_yellow,
		"ciclo do semaforo tem verde e amarelo nas duas vias")
	check(not both_green, "as duas vias nunca ficam verdes ao mesmo tempo")
	check(Traffic.light_offset(Vector2i(0, 0)) != Traffic.light_offset(Vector2i(1, 0)),
		"cruzamentos vizinhos com fases diferentes")
	check(Traffic.lens_color(2) == Traffic.LENS_GREEN and Traffic.lens_color(0) == Traffic.LENS_RED,
		"cor da lente segue o estado")

	# Um instante de vermelho e um de verde para a via leste-oeste.
	var node := Vector2i(0, 0)
	var ahead := node + Vector2i(1, 0)
	var t_red := -1.0
	var t_green := -1.0
	var k := 0.0
	while k < Traffic.LIGHT_CYCLE:
		var st := Traffic.light_states(ahead, k)
		if st.y != 2 and t_red < 0.0:
			t_red = k
		if st.y == 2 and t_green < 0.0:
			t_green = k
		k += 0.25
	check(t_red >= 0.0 and t_green >= 0.0, "existe instante de vermelho e de verde")
	check(Traffic.must_stop(node, Vector2i(1, 0), 10.0, t_red), "carro a 10 m para no vermelho")
	check(not Traffic.must_stop(node, Vector2i(1, 0), 10.0, t_green), "carro a 10 m passa no verde")
	check(not Traffic.must_stop(node, Vector2i(1, 0), Traffic.BLOCK - 1.0, t_red),
		"carro ja dentro do cruzamento termina de passar")

	# No vermelho o carro para na linha e nao atravessa. A velocidade e fixada
	# aqui: com a velocidade sorteada (~5 m/s) 10 s de simulacao nao chegavam
	# aos 59 m da linha de retencao e o teste acusava falha no codigo certo.
	var red_car := Traffic.spawn_car(11, 0, 0)
	red_car["node"] = node
	red_car["h"] = Vector2i(1, 0)
	red_car["s"] = 0.0
	red_car["speed"] = 9.0
	for i in 600:
		Traffic.advance(red_car, 1.0 / 30.0, t_red)
	check(red_car["node"] == node, "no vermelho o carro nao atravessa o cruzamento")
	var limite := Traffic.BLOCK - Traffic.STOP_BEFORE
	check(absf(float(red_car["s"]) - limite) < 0.2,
		"no vermelho o carro para na linha (s = %.2f m, limite %.2f)" % [float(red_car["s"]), limite])

	# No verde ele atravessa.
	var green_car := Traffic.spawn_car(12, 0, 0)
	green_car["node"] = node
	green_car["h"] = Vector2i(1, 0)
	green_car["s"] = 0.0
	green_car["speed"] = 9.0
	for i in 600:
		Traffic.advance(green_car, 1.0 / 30.0, t_green)
	check(green_car["node"] != node, "no verde o carro atravessa o cruzamento")

	# Geometria: poste + carcaca (2 caixas) e a lente.
	var body := Traffic.light_body_mesh()
	var bv: PackedVector3Array = body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(body.get_surface_count() == 1 and bv.size() == 72,
		"malha do semaforo com 2 caixas (%d vertices)" % bv.size())
	var lens := Traffic.lens_mesh()
	var lv: PackedVector3Array = lens.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(lens.get_surface_count() == 1 and lv.size() == 36,
		"malha da lente pronta (%d vertices)" % lv.size())


func _test_traffic_models() -> void:
	# Os 4 modelos de transito: importam, sao assados numa malha unica sem
	# perder triangulos e a frente deles aponta para -Z.
	for i in Traffic.MODEL_PATHS.size():
		var path: String = Traffic.MODEL_PATHS[i]
		var label := path.get_file()
		if not ResourceLoader.exists(path):
			known(false, "modelo de transito %s importado (rodar --import antes)" % label)
			continue
		var mp := ModelProp.new()
		mp.model_path = path
		mp.target_length = float(Traffic.MODEL_LENGTHS[i])
		mp.load_model()
		check(mp.loaded, "modelo de transito %s carrega" % label)
		if not mp.loaded:
			mp.free()
			continue
		var mesh := Traffic.bake(mp)
		var baked := 0
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				baked += (idx as PackedInt32Array).size() / 3
			else:
				baked += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var original := ModelProp.count_tris(mp)
		check(mesh.get_surface_count() > 0 and baked == original,
			"malha unica de %s mantem os %d triangulos (%d)" % [label, original, baked])
		var fz := 0.0
		var fn := 0
		var bz := 0.0
		var bn := 0
		for w in ModelProp.wheel_centers(mp):
			var c: Vector3 = w["center"]
			if bool(w["front"]):
				fz += c.z
				fn += 1
			else:
				bz += c.z
				bn += 1
		if fn > 0 and bn > 0:
			check(fz / float(fn) < bz / float(bn), "%s: rodas da frente ficam em -Z" % label)
		mp.free()


func _test_traffic_collision() -> void:
	# Fase 4: o carro do jogador nao atravessa um carro de transito.
	var t := Traffic.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	t.cars = [{"node": Vector2i(2, 2), "h": Vector2i(1, 0), "s": 10.0, "lat": Vector2.ZERO,
		"speed": 6.0, "rng": rng, "model": 0, "index": 0, "pace": 1.0}]
	var o: Vector3 = Traffic.pose(t.cars[0]).origin
	check(t.hit_test(o + Vector3(0.0, 0.0, 30.0), 1.5).is_empty(), "carro a 30 m nao colide")
	var hit: Dictionary = t.hit_test(o + Vector3(0.4, 0.0, 0.3), 1.5)
	check(not hit.is_empty(), "carro em cima do outro colide")
	if not hit.is_empty():
		var pushed: Vector3 = hit["pushed"]
		var d := Vector2(pushed.x - o.x, pushed.z - o.z).length()
		check(d >= 1.5 + Traffic.CAR_RADIUS - 0.01,
			"empurrao tira o carro de dentro do outro (%.2f m)" % d)
	t.free()


func _test_traffic_spacing_and_follow() -> void:
	# Distancia entre carros: quem vem atras alivia e para se preciso.
	var t := Traffic.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var a := {"node": Vector2i(3, 3), "h": Vector2i(1, 0), "s": 0.0, "lat": Vector2.ZERO,
		"speed": 6.0, "rng": rng, "model": 0, "index": 0, "pace": 1.0}
	var b := {"node": Vector2i(3, 3), "h": Vector2i(1, 0), "s": 6.0, "lat": Vector2.ZERO,
		"speed": 6.0, "rng": rng, "model": 0, "index": 1, "pace": 1.0}
	t.cars = [a, b]
	t._apply_spacing()
	check(float(a["pace"]) < 1.0,
		"quem vem atras alivia com carro na frente (pace %.2f)" % float(a["pace"]))
	check(absf(float(b["pace"]) - 1.0) < 0.01, "quem vem na frente segue solto")
	b["s"] = 60.0
	t._apply_spacing()
	check(absf(float(a["pace"]) - 1.0) < 0.01, "longe da frente, volta ao ritmo normal")
	# O transito acompanha o jogador: carro longe volta para perto, em rua valida.
	var c := {"node": Vector2i(0, 0), "h": Vector2i(1, 0), "s": 0.0, "lat": Vector2.ZERO,
		"speed": 6.0, "rng": rng, "model": 0, "index": 2, "pace": 1.0}
	var focus := Vector3(1600.0, 1.0, 200.0)
	check(Traffic.place_near(c, focus, 150.0, 260.0), "carro reposicionado em volta do jogador")
	check(Traffic.valid(c["node"]), "posicao nova esta na grade da cidade")
	var o: Vector3 = Traffic.pose(c).origin
	var dist := Vector2(o.x - focus.x, o.z - focus.z).length()
	check(dist >= 60.0 and dist <= 340.0, "carro volta a uma distancia util (%.0f m)" % dist)
	t.free()


func _test_audio_pure() -> void:
	# Som sintetizado: a conta e pura, entao o CI pode conferir sem placa de audio.
	check(absf(VehicleAudio.engine_hz(0.0) - VehicleAudio.IDLE_HZ) < 0.01,
		"motor em marcha lenta a %.0f Hz" % VehicleAudio.engine_hz(0.0))
	check(absf(VehicleAudio.engine_hz(1.0) - VehicleAudio.MAX_HZ) < 0.01,
		"motor a pleno giro a %.0f Hz" % VehicleAudio.engine_hz(1.0))
	check(VehicleAudio.engine_hz(0.5) > VehicleAudio.engine_hz(0.2),
		"o tom sobe com a velocidade")
	var table: PackedFloat32Array = VehicleAudio.engine_table()
	var peak := 0.0
	for v in table:
		peak = maxf(peak, absf(v))
	check(table.size() == VehicleAudio.TABLE_SIZE, "tabela do motor com %d amostras" % table.size())
	check(peak > 0.95 and peak <= 1.001, "tabela do motor normalizada (pico %.2f)" % peak)
	check(absf(table[0]) < 0.01, "tabela do motor comeca em zero (sem clique no loop)")
	check(VehicleAudio.impact_pitch(0.0) > VehicleAudio.impact_pitch(1.0),
		"batida forte soa mais grave")
	# B-74: com o pe solto o cambio TEM de reduzir (antes ficava em 4a a 10 km/h
	# com o giro preso na lenta; foi assim que o HUD apareceu no print do iPhone).
	var sp := VehiclePhysics.sedan()
	var coast_up := {"speed": 2.78, "gear": 4, "shift_cool": 0.0}
	for i in 120:
		coast_up = VehiclePhysics.step(sp, coast_up, 0.0, 0.0, Surf.MU_ASPHALT, 1.0 / 60.0)
	check(int(coast_up["gear"]) == 1,
		"com o pe solto o cambio reduz ate a 1a (marcha %d)" % int(coast_up["gear"]))
	check(float(coast_up["rpm"]) > 900.0,
		"e o giro sai da marcha lenta andando (%.0f rpm)" % float(coast_up["rpm"]))
	check(VehicleAudio.load_impact() != null, "som de batida CC0 carregou")
	# B-74: o motor e um LOOP de AudioStreamWAV gerado em codigo. O
	# AudioStreamGenerator imprimia "cannot be sampled" no iPhone e ficava mudo.
	var loop := VehicleAudio.engine_loop(VehicleAudio.LOOP_SECONDS, VehicleAudio.MIX_RATE)
	var loop_bytes := loop.data.size() if loop != null else 0
	check(loop != null and loop_bytes > 1000, "loop do motor gerado (%d bytes)" % loop_bytes)
	if loop != null:
		check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loop do motor em repeticao")
		var frames := loop_bytes / 2
		check(absi(loop.loop_end - frames) <= 1,
			"loop cobre o buffer inteiro (%d de %d quadros)" % [loop.loop_end, frames])
		var wav_peak := 0
		for i in mini(frames, 4000):
			wav_peak = maxi(wav_peak, absi(loop.data.decode_s16(i * 2)))
		check(wav_peak > 8000 and wav_peak < 32767,
			"loop audivel e sem estouro (pico %d)" % wav_peak)
	# B-42: o som nao pode comecar antes de um toque (o Safari recusa e o motor
	# fica mudo). Antes do primeiro toque, o estado tem que dizer isso.
	var av := VehicleAudio.new()
	root.add_child(av)
	if av._stream == null:
		av._ready()
	check(av.describe().contains("toque"), "som espera o primeiro toque: %s" % av.describe())
	av.free()


func _test_sky() -> void:
	# B-51: ceu e luz do Rio. O sol NASCE NO MAR (e-sudeste), culmina alto ao
	# meio-dia e se poe sobre o continente (oeste-noroeste). Antes ele subia e
	# descia sempre no mesmo lugar do ceu, entao nao existia por do sol.
	var rise := DayNight.sun_direction(6.0)
	check(absf(rise.y) < 0.06, "sol no horizonte as 6h (altura %.3f)" % rise.y)
	check(rise.x > 0.7, "sol nasce a leste (x %.2f)" % rise.x)
	check(rise.z < -0.2, "sol nasce do lado do MAR (z %.2f)" % rise.z)
	check(DayNight.sun_direction(12.0).y > 0.9, "sol de meio-dia alto como no Rio (%.2f)" % DayNight.sun_direction(12.0).y)
	var set_ := DayNight.sun_direction(18.0)
	check(set_.x < -0.7, "sol se poe a oeste (x %.2f)" % set_.x)
	check(set_.z > 0.2, "sol se poe sobre o CONTINENTE (z %.2f)" % set_.z)
	check(DayNight.sun_direction(0.0).y < -0.5, "sol abaixo do horizonte a meia-noite")

	var noon := DayNight.look(12.0, "claro")
	var gold := DayNight.look(17.6, "claro")
	var night := DayNight.look(23.0, "claro")
	var noon_top: Color = noon["top"]
	var noon_hor: Color = noon["horizon"]
	check(noon_hor.get_luminance() > noon_top.get_luminance() * 1.5,
		"meio-dia: horizonte muito mais claro que o zenite (nevoa marinha)")
	check(noon_hor.b > noon_hor.r, "meio-dia: horizonte azulado (b %.2f > r %.2f)" % [noon_hor.b, noon_hor.r])
	check(noon_top.b > 0.5 and noon_top.r < 0.2, "meio-dia: zenite azul tropical fundo")
	# B-59: a nevoa tingia o ceu inteiro (0,65) e o azul do zenite virava um
	# branco lavado as 9h45 na tela do autor.
	check(float(noon["sky_affect"]) <= 0.25,
		"a nevoa nao lava o ceu de dia (afeto %.2f)" % float(noon["sky_affect"]))
	check(float(noon["sun_energy"]) <= 1.15 and float(noon["ambient_energy"]) <= 0.90,
		"meio-dia sem estourar a areia (sol %.2f, ambiente %.2f)" % [
			float(noon["sun_energy"]), float(noon["ambient_energy"])])
	var gold_hor: Color = gold["horizon"]
	var gold_top: Color = gold["top"]
	check(float(gold["gold"]) > 0.5, "hora dourada detectada (%.2f)" % float(gold["gold"]))
	check(gold_hor.r > gold_hor.b + 0.3,
		"hora dourada: horizonte coral (r %.2f, b %.2f)" % [gold_hor.r, gold_hor.b])
	check(gold_top.b > gold_top.r + 0.2,
		"hora dourada: zenite AINDA azul (b %.2f, r %.2f)" % [gold_top.b, gold_top.r])
	var night_top: Color = night["top"]
	var night_hor: Color = night["horizon"]
	check(night_top.get_luminance() < 0.12, "noite: zenite escuro (%.3f)" % night_top.get_luminance())
	check(night_hor.r >= night_hor.b and night_hor.get_luminance() > night_top.get_luminance(),
		"noite: brilho de cidade no horizonte (o ceu do Rio nao e preto)")
	check(float(noon["night"]) < 0.01 and float(night["night"]) > 0.9,
		"janelas: 0 de dia, 1 de noite (%.2f / %.2f)" % [float(noon["night"]), float(night["night"])])
	check(float(night["fog_density"]) > float(noon["fog_density"]) * 1.3,
		"nevoa maritima fecha o tempo a noite (%.4f > %.4f)" % [
			float(night["fog_density"]), float(noon["fog_density"])])
	check(float(noon["sun_energy"]) > float(gold["sun_energy"]),
		"sol mais fraco e mais ambar na hora dourada")
	check((noon["sun_color"] as Color).g > (gold["sun_color"] as Color).g,
		"cor do sol esfria do ambar para o branco ao subir")
	# A luz viaja no -Z do no: o +Z da base tem que apontar para o astro.
	var to_dir := Vector3(0.0, 0.8, 0.6).normalized()
	check(DayNight.aim_basis(to_dir).z.is_equal_approx(to_dir),
		"aim_basis aponta o +Z da luz para o sol (luz viaja no -Z)")
	check(absf(DayNight.aim_basis(to_dir).determinant() - 1.0) < 0.01,
		"aim_basis e uma base valida (determinante 1, sem espelho)")
	check(DayNight.aim_basis(Vector3.UP).z.is_equal_approx(Vector3.UP),
		"aim_basis aguenta o sol exatamente no zenite")


## B-72: orcamento de sombra e de ceu travado por constante. O teste que rodei
## no build Web viu draw calls 145 -> 263 e primitivas 76k -> 176k (FPS 29 -> 9)
## com o sol baixo e o jogador PARADO; estas checagens impedem o orcamento
## voltar a subir sem alguem perceber.
func _test_render_budget() -> void:
	var size := int(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/size", 0))
	check(size > 0 and size <= 1024, "sombra do sol em %d px (teto 1024)" % size)
	check(Cfg.SUN_SHADOW_DISTANCE <= 80.0,
		"distancia de sombra em %.0f m (teto 80)" % Cfg.SUN_SHADOW_DISTANCE)
	check(DayNight.AIM_EPSILON >= 0.002,
		"sol nao e re-apontado a cada quadro (%.3f rad)" % DayNight.AIM_EPSILON)
	# B-75: em retrato a resolucao de render tem de cair (o iPhone desenhava
	# 1280x2770 para uma tela de ~0,3 MP e ficava limitado por pixel).
	var portrait_scale := Cfg.render_scale(Vector2i(1170, 2532))
	var landscape_scale := Cfg.render_scale(Vector2i(2532, 1170))
	check(portrait_scale > 1.2,
		"retrato divide a resolucao por %.2f" % portrait_scale)
	check(landscape_scale == 1.0,
		"paisagem mantem a resolucao cheia (%.2f)" % landscape_scale)
	var ratio := 1.0 / (portrait_scale * portrait_scale)
	check(ratio < 0.55,
		"retrato corta mais de 45%% dos pixels (fica %.0f%%)" % (ratio * 100.0))


func _test_pedestrians() -> void:
	# B-53: pedestres com rotina. Sem GPU da para provar o que importa: a
	# geometria da calcada, a travessia (13 m, sempre para o canto em frente), a
	# espera do sinal (a mesma fase dos semaforos do transito), a vida por hora
	# do dia e a pessoa deterministica (mesma semente, mesma roupa e pressa).
	var b := Vector2i(3, 2)
	var c0 := Pedestrians.corner(b, 0)
	var c1 := Pedestrians.corner(b, 1)
	check(absf((c1 - c0).length() - 51.0) < 0.01,
		"lado da volta na calcada = 51 m (%.1f)" % (c1 - c0).length())
	var o := Pedestrians.block_origin(b)
	check(absf(c0.x - o.x - 6.5) < 0.01,
		"pedestre anda no meio da calcada (%.1f m da quadra)" % (c0.x - o.x))
	var k := 0
	for i in 4:
		k = Pedestrians.next_corner(k, true)
	check(k == 0, "quatro cantos fecham a volta na quadra")
	check(Pedestrians.next_corner(0, false) == 3, "sentido anti-horario vai ao canto 3")
	# B-62: o pedestre tem que OLHAR para onde anda. Com um giro extra de PI ele
	# atravessava a rua de costas (o "moonwalk" que o autor viu) e nenhum teste
	# olhava a DIRECAO — o clipe tocava, a perna mexia, e o corpo ia de re.
	var dirs: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			Vector2(-1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.7, -0.7)]
	var facing_ok := true
	var worst := 0.0
	for d in dirs:
		var yaw := Pedestrians.facing_yaw(d)
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var err := fwd.distance_to(Vector3(d.x, 0.0, d.y).normalized())
		worst = maxf(worst, err)
		if err > 0.01:
			facing_ok = false
	check(facing_ok, "pedestre olha para onde anda (erro max %.3f)" % worst)
	var sides_ok := true
	var near_ok := true
	for kk in 4:
		for along_x in [true, false]:
			var ct := Pedestrians.cross_target(b, kk, along_x)
			var from := Pedestrians.corner(b, kk)
			var to: Vector2 = ct[2]
			var nb: Vector2i = ct[0]
			if not Pedestrians.valid_block(nb):
				sides_ok = false
			if absf((to - from).length() - 13.0) > 0.01:
				near_ok = false
			if to != Pedestrians.corner(nb, int(ct[1])):
				sides_ok = false
	check(sides_ok, "travessia sempre para o canto em frente, de quadra valida")
	check(near_ok, "travessia de 13 m (10 de rua + 2 x 1,5 de calcada)")
	# Sinal: com a fase norte-sul verde (carros passando), atravessar em X esta
	# FECHADO para o pedestre.
	var n := Pedestrians.corner_node(b, 0)
	var t := 0.0
	while Traffic.light_states(n, t).x != 2 and t < 60.0:
		t += 0.5
	check(t < 60.0, "achou a fase norte-sul verde (t = %.1f s)" % t)
	check(not Pedestrians.can_cross(b, 0, true, t),
		"pedestre espera quando os carros da via estao passando")
	check(Pedestrians.can_cross(b, 0, false, t),
		"pedestre atravessa a outra via, que esta parada")
	check(Pedestrians.life_fraction(12.0) > Pedestrians.life_fraction(3.0),
		"de madrugada sobra menos gente (%.2f < %.2f)" % [
			Pedestrians.life_fraction(3.0), Pedestrians.life_fraction(12.0)])
	check(Pedestrians.life_fraction(12.0) >= 1.0, "meio-dia: calcada cheia")
	var p1 := Pedestrians.spawn_ped(777, 0)
	var p2 := Pedestrians.spawn_ped(777, 0)
	check(p1["shirt"] == p2["shirt"] and p1["speed"] == p2["speed"],
		"mesma semente: mesma pessoa (roupa e pressa)")
	check(float(p1["speed"]) > 0.9 and float(p1["speed"]) < 3.0,
		"pressa plausivel (%.2f m/s)" % float(p1["speed"]))
	var placed := 0
	for i in 12:
		var p := Pedestrians.spawn_ped(1000 + i, i)
		if Pedestrians.place_ped(p, Vector3(1600.0, 1.2, 100.0), 30.0, 120.0):
			var pos: Vector2 = p["pos"]
			var d := Vector2(pos.x - 1600.0, pos.y - 100.0).length()
			if d >= 20.0 and d <= 200.0 and pos.y > 40.0 and pos.y < 260.0:
				placed += 1
	check(placed >= 10, "nasce perto do jogador (%d de 12)" % placed)


## B-77: cabeca 3D do protagonista (modelo CC-BY) escalada pela altura do corpo.
## O CI carrega o .glb de verdade, conta os triangulos e confere a escala.
func _test_head_model() -> void:
	if not ResourceLoader.exists(Player.HEAD_PATH):
		known(false, "modelo de cabeca importado (rodar --import antes)")
		return
	var scene := Pedestrians.load_scene(Player.HEAD_PATH)
	check(scene != null, "cabeca 3D carrega (%s)" % Player.HEAD_PATH.get_file())
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	root.add_child(inst)
	var box := ModelProp.mesh_aabb(inst)
	var tris := 0
	for node in ModelProp.collect_meshes(inst):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var k := Player.head_scale(box.size.y, 1.80)
	check(tris > 100 and box.size.y > 0.1,
		"cabeca com %d triangulos e %.2f m de altura" % [tris, box.size.y])
	check(absf(box.size.y * k - Player.HEAD_HEIGHT_FRAC * 1.80) < 0.001,
		"cabeca escala para %.2f m num corpo de 1,80 m" % (box.size.y * k))
	var k_menor := Player.head_scale(box.size.y, 1.60)
	check(k_menor < k, "corpo menor tem cabeca menor (%.3f x %.3f)" % [k_menor, k])
	# B-78: cabelo (a cabeca escaneada e careca; o protagonista e de cabelo preto).
	var lay := Player.hair_layout(0.20, 1.82)
	var hs: Vector3 = lay["scale"]
	check(hs.x > hs.y and hs.y > 0.08,
		"cabelo mais largo que alto (%.3f x %.3f m)" % [hs.x, hs.y])
	check(float(lay["top"]) > 1.82, "cabelo passa do topo do cranio (%.3f)" % float(lay["top"]))
	var lay2 := Player.hair_layout(0.26, 1.82)
	var hs2: Vector3 = lay2["scale"]
	check(hs2.x > hs.x, "cabeca maior tem cabelo maior (%.3f x %.3f)" % [hs2.x, hs.x])
	inst.queue_free()


func _test_pedestrian_model() -> void:
	# B-57/B-58: corpos da Quaternius (CC0). A prova que faltava: nao basta o
	# clipe "casar" com o esqueleto. Os corpos modulares e o walker sao packs
	# DIFERENTES (o CI mediu 11% de casamento), e retargetar um no outro deixava
	# o pedestre em T-pose deslizando pela rua. Aqui se mede o casamento de cada
	# corpo, o movimento do clipe e, no fim, monta-se o modulo de verdade para
	# ver a caminhada tocando em cada pessoa.
	var clips := Pedestrians.load_clips(Pedestrians.ANIM_PATH)
	var walk := Pedestrians.pick_clip(clips, "walk")
	check(not clips.is_empty(), "animacoes do pedestre carregam (%d clipes)" % clips.size())
	check(walk != "", "clipe de caminhada encontrado (%s)" % walk)
	check(Pedestrians.pick_clip(clips, "idle") != "", "clipe de parado encontrado")
	if walk == "":
		return
	var anim: Animation = clips[walk]
	check(anim.get_track_count() > 10 and anim.length > 0.3,
		"caminhada com %d trilhas e %.2f s" % [anim.get_track_count(), anim.length])
	var motion := Pedestrians.clip_motion(anim)
	check(motion >= Pedestrians.MOTION_MIN,
		"o clipe de caminhada se mexe (%.2f)" % motion)
	var paths: Array = Pedestrians.BODY_PATHS.duplicate()
	paths.append(Pedestrians.ANIM_PATH)
	var usable := 0
	for path in paths:
		var sc := Pedestrians.load_scene(path)
		if sc == null:
			check(false, "corpo do pedestre importou (%s)" % String(path).get_file())
			continue
		var inst: Node3D = sc.instantiate()
		var sk := Pedestrians._find_skel(inst)
		var box := ModelProp.mesh_aabb(inst)
		var tris := ModelProp.count_tris(inst)
		var ratio := 0.0
		if sk != null:
			ratio = Pedestrians.match_ratio(anim, Pedestrians._bone_names(sk))
		inst.free()
		if ratio >= Pedestrians.MATCH_MIN:
			usable += 1
		print("  info: corpo %s: %d tris, %.2f m, casamento %.0f%%, %d superficies" % [
			String(path).get_file(), tris, box.size.y, ratio * 100.0,
			Pedestrians.scene_surfaces(sc)])
	check(usable >= 1, "pelo menos um corpo casa com a caminhada (%d de %d)" % [
		usable, paths.size()])
	var kinds := Pedestrians.choose_bodies(clips, walk)
	check(not kinds.is_empty(), "corpos aprovados para a rua (%d)" % kinds.size())
	var has_walker := false
	for kd in kinds:
		if String(kd["path"]) == Pedestrians.ANIM_PATH:
			has_walker = true
	check(has_walker, "o corpo com animacao no proprio arquivo entra sempre (sem T-pose)")
	# Integracao: o modulo montado de verdade, com a caminhada tocando em cada um.
	var peds := Pedestrians.new()
	root.add_child(peds)
	peds.setup(4242, Vector3(1600.0, 1.2, 100.0))
	check(peds._use_model, "o modulo monta pedestres com modelo (%s)" % peds.describe())
	var playing := 0
	for ap in peds._anims:
		if ap != null and ap.is_playing():
			playing += 1
	check(playing > 0 and playing == peds._anims.size(),
		"todo pedestre com a animacao tocando (%d de %d)" % [playing, peds._anims.size()])
	peds.free()
	# B-60: o corpo sem textura tem que sair VESTIDO (cor por vertice pela
	# altura) e a sombra de contato tem que ser uma mancha redonda, nao o
	# retangulo cinza do tamanho da pessoa que apareceu na tela.
	var body := Pedestrians.load_scene(Pedestrians.ANIM_PATH)
	check(body != null, "corpo do pedestre carregou para o teste de pintura")
	if body != null:
		var inst: Node3D = body.instantiate()
		var ok := false
		for node in ModelProp.collect_meshes(inst):
			var mi := node as MeshInstance3D
			if mi == null:
				continue
			if Pedestrians.paint_body(mi, Color(0.9, 0.7, 0.6), Color(0.8, 0.1, 0.1),
					Color(0.1, 0.1, 0.2)):
				var arr := mi.mesh.surface_get_arrays(0)
				if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] != null:
					var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
					ok = cols.size() > 0
		inst.free()
		check(ok, "corpo sem textura sai vestido (cor de vertice por altura)")
	var sm := Pedestrians.soft_shadow_material(0.45)
	check(sm.albedo_texture != null and sm.albedo_color.a > 0.2,
		"sombra de contato redonda (gradiente), nao um quadrado cinza")


func _test_pedestrian_life() -> void:
	# B-64: vida e animacoes dos NPCs. O que da para provar sem GPU: o clipe
	# escolhido em cada estado, o compasso que evita patinar no chao, o limite do
	# atropelamento, e quais clipes o arquivo realmente traz (gesto/queda podem
	# nao existir: nesse caso o jogo nao inventa animacao).
	var clips := Pedestrians.load_clips(Pedestrians.ANIM_PATH)
	var gesture := Pedestrians.pick_clip(clips, "work")
	if gesture == "":
		gesture = Pedestrians.pick_clip(clips, "punch")
	var roles := {
		"parado": Pedestrians.pick_clip(clips, "idle"),
		"andar": Pedestrians.pick_clip(clips, "walk"),
		"correr": Pedestrians.pick_clip(clips, "run"),
		"pulo": Pedestrians.pick_clip(clips, "jump"),
		"gesto": gesture,
		"queda": Pedestrians.pick_clip(clips, "death"),
	}
	print("  info: clipes do pedestre: %d no arquivo; papeis %s" % [clips.size(), str(roles)])
	check(roles["andar"] != "" and roles["parado"] != "", "pedestre tem andar e parado")
	check(Pedestrians.clip_for(true, true, true, 5.0, true, true, true, true) == "down",
		"atropelado: animacao de queda manda")
	check(Pedestrians.clip_for(false, true, false, 0.0, true, true, true, true) == "gesture",
		"parado gesticulando: gesto")
	check(Pedestrians.clip_for(false, false, true, 3.0, true, true, true, true) == "run",
		"correndo: clipe de corrida")
	check(Pedestrians.clip_for(false, false, true, 1.2, true, true, true, true) == "walk",
		"andando: clipe de passo")
	check(Pedestrians.clip_for(false, false, false, 0.0, true, true, true, true) == "idle",
		"parado: clipe de espera")
	check(Pedestrians.clip_for(true, false, false, 0.0, false, true, true, true) == "idle",
		"sem clipe de queda, atropelado nao inventa animacao")
	check(absf(Pedestrians.clip_pace("walk", 1.4) - 1.0) < 0.01, "passo a 1,4 m/s toca 1x")
	check(absf(Pedestrians.clip_pace("run", 4.6) - 1.0) < 0.01, "corrida a 4,6 m/s toca 1x")
	check(Pedestrians.clip_pace("run", 99.0) <= 2.0 and Pedestrians.clip_pace("walk", 0.0) >= 0.6,
		"compasso limitado (corrida %.2f, passo a %.2f)" % [
			Pedestrians.clip_pace("run", 99.0), Pedestrians.clip_pace("walk", 0.0)])
	var ped := Vector2(10.0, 20.0)
	check(not Pedestrians.car_hit(Vector3(10.0, 0.0, 20.0), 1.0, ped), "carro devagar nao atropela")
	check(Pedestrians.car_hit(Vector3(10.5, 0.0, 20.5), 6.0, ped), "carro rapido e perto atropela")
	check(not Pedestrians.car_hit(Vector3(15.0, 0.0, 20.0), 6.0, ped), "carro longe nao atropela")
	# Queda por codigo (o arquivo nao traz clipe de morte): 0 no comeco, deitado
	# (-90 graus) depois de 0,25 s.
	check(absf(Pedestrians.fall_pitch(Pedestrians.DOWN_TIME)) < 0.01, "queda comeca em pe")
	check(absf(Pedestrians.fall_pitch(Pedestrians.DOWN_TIME - 0.5) + PI * 0.5) < 0.01,
		"queda termina deitado (-90 graus)")
	check(absf(Pedestrians.fall_pitch(0.0) + PI * 0.5) < 0.01, "continua deitado ate levantar")


func _test_bone_activities() -> void:
	# B-82: animacoes de ATIVIDADE (celular, conversa, olhar o mar, balcao,
	# esperar o sinal, sentar na areia, acenar) e as do protagonista (soco,
	# mira, pulo, dano). Nenhuma delas vem em arquivo: sao construidas no
	# esqueleto de cada corpo. O que se prova sem GPU:
	#   1. o PAPEL do osso e reconhecido nos dois rigs do jogo (Quaternius
	#      "UpperArm.L" e Mixamo "mixamorig:LeftArm");
	#   2. a conta de conversao esta certa: com rotacao zero a pose devolve
	#      exatamente o REST do osso (essa igualdade e a assinatura da formula);
	#   3. o braco caido aponta para baixo (medido no repouso de cada rig);
	#   4. o clipe monta de verdade, tem movimento e, nos que ciclam, fecha;
	#   5. o modulo de pedestres instala as atividades nas pessoas da rua.
	check(BoneAnim.role_of("mixamorig_LeftUpLeg") == "thigh_l", "osso LeftUpLeg = coxa esquerda")
	check(BoneAnim.role_of("RightUpLeg") == "thigh_r", "osso RightUpLeg = coxa direita")
	check(BoneAnim.role_of("UpperArm.L") == "upperarm_l", "osso UpperArm.L = braco esquerdo")
	check(BoneAnim.role_of("LowerArm.R") == "forearm_r", "osso LowerArm.R = antebraco direito")
	check(BoneAnim.role_of("LeftLeg") == "shin_l", "osso LeftLeg = canela esquerda")
	check(BoneAnim.role_of("Hips") == "hips", "osso Hips = quadril")
	check(BoneAnim.role_of("Head") == "head", "osso Head = cabeca")
	check(BoneAnim.role_of("Fire") == "", "osso sem papel conhecido e ignorado")
	check(BoneAnim.cycles("talk") and not BoneAnim.cycles("punch"),
		"conversa cicla, soco toca uma vez")

	var sc0 := Pedestrians.load_scene(Pedestrians.ANIM_PATH)
	check(sc0 != null, "corpo do pedestre carrega para o teste de atividade")
	if sc0 == null:
		return
	var inst0: Node3D = sc0.instantiate()
	var sk0 := Pedestrians._find_skel(inst0)
	check(sk0 != null, "corpo do pedestre tem esqueleto")
	if sk0 == null:
		return
	var rg := BoneAnim.rig(sk0)
	var bones: Dictionary = rg["bone"]
	var names := PackedStringArray()
	for r in bones.keys():
		names.append(String(r))
	names.sort()
	print("  info: papeis reconhecidos no corpo do pedestre (%d): %s" % [
		bones.size(), " ".join(names)])
	for need in ["hips", "head", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"]:
		check(bones.has(need), "corpo do pedestre tem o papel '%s'" % need)
	# A prova da formula: rotacao zero tem de devolver o repouso do osso. Se a
	# conversao estivesse errada, o corpo inteiro sairia torto em TODA atividade.
	var id_ok := true
	var n_id := 0
	for role in bones.keys():
		var rn := String(role)
		if rn == "upperarm_l" or rn == "upperarm_r":
			continue   # esses levam a correcao de "braco caido" (testada abaixo)
		var rest_q := sk0.get_bone_rest(int(bones[role])).basis.get_rotation_quaternion().normalized()
		var q := BoneAnim.bone_pose(rg, rn, {})
		n_id += 1
		if absf(q.dot(rest_q)) < 0.99:
			id_ok = false
	check(id_ok and n_id >= 3, "pose de rotacao zero devolve o rest do osso (%d ossos)" % n_id)
	# Braco caido: a direcao de repouso e MEDIDA (osso -> filho) e a correcao
	# tem de virar essa direcao para baixo. Sem isso o NPC gesticula com o braco
	# esticado em T-pose.
	var dirs: Dictionary = rg["dir"]
	var n_arm := 0
	var down_ok := true
	for role in ["upperarm_l", "upperarm_r"]:
		if not dirs.has(role):
			continue
		var d: Vector3 = dirs[role]
		if d.length() < 0.5:
			continue
		n_arm += 1
		var turned: Vector3 = BoneAnim.stand(rg, String(role)) * d
		if turned.dot(Vector3.DOWN) < 0.9:
			down_ok = false
	check(n_arm >= 1 and down_ok, "braco caido aponta para baixo (%d bracos medidos)" % n_arm)
	# O clipe montado de verdade: trilhas para o corpo todo e chaves ao longo do
	# tempo. `_anim_span` olha TODAS as chaves (as atividades respiram em seno e
	# a volta passa pelo zero, entao `clip_motion` daria zero no celular).
	# A mensagem carrega os numeros do clipe: e por ela que o log do CI diz onde
	# a montagem parou (trilha? chave? valor?).
	for kind in BoneAnim.NPC_ACTIVITIES:
		var a: Animation = BoneAnim.build(String(kind), sk0, "Skeleton3D")
		var nt := 0
		var kc := 0
		var v0 := "?"
		var v1 := "?"
		if a != null:
			nt = a.get_track_count()
			if nt > 0:
				kc = a.track_get_key_count(0)
				if kc >= 2:
					v0 = str(a.track_get_key_value(0, 0))
					v1 = str(a.track_get_key_value(0, 1))
		var span := _anim_span(a)
		check(a != null and nt > 10 and span > 0.02,
			"clipe '%s': %s, %d trilhas, trilha0 com %d chaves, %.3f rad (%s -> %s), %d ossos" % [
				kind, "NULO" if a == null else "montado", nt, kc, span, v0, v1, bones.size()])
	# E a pose de cada atividade sai mesmo do repouso (senao o NPC "faria" o
	# gesto com o corpo reto, que era o defeito).
	var posed := 0
	for kind in BoneAnim.NPC_ACTIVITIES:
		if _pose_top(String(kind), 0.0) > 0.15:
			posed += 1
	check(posed == BoneAnim.NPC_ACTIVITIES.size(),
		"%d de %d atividades posam o corpo longe do repouso" % [
			posed, BoneAnim.NPC_ACTIVITIES.size()])
	check(_anim_span(BoneAnim.build("wait", sk0, "Skeleton3D")) > 0.2,
		"esperando o sinal: bate o pe no chao")
	check(_pose_top("sit", 0.0) > 1.0, "sentado na areia: dobra as pernas (%.2f rad)" % _pose_top("sit", 0.0))
	check(_pose_top("punch", 0.5) > 1.0, "o soco estica o braco de verdade")
	# Ciclo fechado: a pose em u = 0 e a de u = 1 tem de ser a mesma, senao o
	# NPC da um pulo de pose a cada volta do clipe.
	var p0: Dictionary = BoneAnim.pose("talk", 0.0)
	var p1: Dictionary = BoneAnim.pose("talk", 1.0)
	var loop_ok := not p0.is_empty()
	for k in p0.keys():
		if not p1.has(k) or absf((p0[k] as Quaternion).dot(p1[k] as Quaternion)) < 0.999:
			loop_ok = false
	check(loop_ok, "a conversa fecha o ciclo (pose em u=0 = pose em u=1)")
	# Os sete corpos da rua tem de reconhecer os ossos essenciais.
	var bodies: Array = Pedestrians.BODY_PATHS.duplicate()
	bodies.append(Pedestrians.ANIM_PATH)
	var all_ok := true
	for path in bodies:
		var sc := Pedestrians.load_scene(path)
		if sc == null:
			continue
		var bi: Node3D = sc.instantiate()
		var bb: Dictionary = BoneAnim.rig(Pedestrians._find_skel(bi))["bone"]
		bi.free()
		var got := 0
		for need in ["hips", "head", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"]:
			if bb.has(need):
				got += 1
		if got < 6:
			all_ok = false
			print("  info: %s reconheceu so %d de 6 ossos essenciais" % [
				String(path).get_file(), got])
	check(all_ok, "os %d corpos tem quadril, cabeca, bracos e coxas reconhecidos" % bodies.size())
	# Quem escolhe a atividade quando para: areia senta/olha o mar, calcada
	# fala no celular/espera.
	check(Pedestrians.activity_for(Pedestrians.MODE_BEACH, 0.10) == "sit", "na areia: senta")
	check(Pedestrians.activity_for(Pedestrians.MODE_BEACH, 0.50) == "sea", "na areia: olha o mar")
	check(Pedestrians.activity_for(Pedestrians.MODE_BLOCK, 0.10) == "phone", "na calcada: celular")
	check(Pedestrians.activity_for(Pedestrians.MODE_BLOCK, 0.70) == "wait", "na calcada: espera")
	check(Pedestrians.activity_for(Pedestrians.MODE_BLOCK, 0.95) == "",
		"e as vezes so fica parado olhando a rua")
	check(Pedestrians.clip_for(false, false, false, 0.0, true, true, true, true, "phone") == "phone",
		"parado toca a atividade")
	check(Pedestrians.clip_for(false, false, true, 1.2, true, true, true, true, "phone") == "walk",
		"andando a atividade nao rouba o passo")
	check(Pedestrians.clip_for(false, true, false, 0.0, true, true, true, true, "sit") == "sit",
		"a atividade vale mais que o gesto antigo")
	# Integracao: o modulo de pedestres instala os clipes nas pessoas da rua.
	var peds := Pedestrians.new()
	root.add_child(peds)
	peds.setup(4242, Vector3(1600.0, 1.2, 100.0))
	var with_acts := 0
	for d in peds._acts:
		if d == null:
			continue
		var acts: Dictionary = d
		if not acts.is_empty():
			with_acts += 1
	check(with_acts > 0, "pessoas na rua receberam atividades (%d de %d; %s; papeis=%d)" % [
		with_acts, peds._acts.size(), peds.act_note, BoneAnim.covered(sk0)])
	var has_phone := false
	var has_sit := false
	for d in peds._acts:
		var acts: Dictionary = d
		if acts.has("phone"):
			has_phone = true
		if acts.has("sit"):
			has_sit = true
	check(has_phone and has_sit, "clipes de celular e de sentar instalados (%s)" % peds.act_note)
	peds.free()
	inst0.free()
	# O protagonista: o .fbx do autor nao traz Jump nem soco — essas acoes sao
	# construidas no esqueleto dele. Se o rig nao for reconhecido, o teste diz
	# exatamente quantos papeis casaram.
	var psc := Pedestrians.load_scene(Player.PROTAGONISTA_PATH)
	if psc == null:
		known(false, "PROTAGONISTA.fbx importado para o teste das acoes do jogador")
		return
	var pin: Node3D = psc.instantiate()
	var psk := Pedestrians._find_skel(pin)
	var pb: Dictionary = BoneAnim.rig(psk)["bone"]
	var pnames := PackedStringArray()
	for r in pb.keys():
		pnames.append(String(r))
	pnames.sort()
	print("  info: papeis reconhecidos no PROTAGONISTA.fbx (%d): %s" % [
		pb.size(), " ".join(pnames)])
	var pgot := 0
	for need in ["hips", "head", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"]:
		if pb.has(need):
			pgot += 1
	check(pgot == 6, "protagonista tem os 6 ossos essenciais (%d)" % pgot)
	for kind in BoneAnim.PLAYER_ACTIVITIES:
		var pa: Animation = BoneAnim.build(String(kind), psk, "Skeleton3D")
		check(pa != null and pa.get_track_count() > 10 and _pose_top(String(kind), 0.5) > 0.25,
			"acao '%s' montada e posando no protagonista" % kind)
	var paim: Animation = BoneAnim.build("aim", psk, "Skeleton3D")
	check(paim != null and paim.loop_mode == Animation.LOOP_LINEAR, "a mira cicla")
	var ppunch: Animation = BoneAnim.build("punch", psk, "Skeleton3D")
	check(ppunch != null and ppunch.loop_mode == Animation.LOOP_NONE,
		"o soco toca uma vez e volta ao repouso")
	pin.free()


func _test_protagonista_fbx() -> void:
	# O modelo do autor (PROTAGONISTA.fbx) entra primeiro no jogador. O CI abre
	# o arquivo e RELATA o que ha dentro — esqueleto, clipes de animacao e
	# movimento — porque binario ninguem le de fora. Sem animacao de andar nele,
	# o jogo cai para o corpo CC0; este bloco e o raio-x que mostra o por que.
	var scene := Pedestrians.load_scene(Player.PROTAGONISTA_PATH)
	check(scene != null, "PROTAGONISTA.fbx carrega")
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	var sk := Pedestrians._find_skel(inst)
	var tris := ModelProp.count_tris(inst)
	var box := ModelProp.mesh_aabb(inst)
	var ap := Pedestrians._find_anim(inst)
	print("  info: PROTAGONISTA.fbx: %d tris, %.2f m de bind pose, rig %s, %s" % [
		tris, box.size.y, "sim" if sk != null else "NAO",
		"com AnimationPlayer" if ap != null else "SEM AnimationPlayer"])
	var clips := {}
	if ap != null:
		for nm in ap.get_animation_list():
			var a := ap.get_animation(String(nm))
			if a != null:
				clips[String(nm)] = a
	print("  info: PROTAGONISTA.fbx: %d clipes" % clips.size())
	for nm in clips.keys():
		print("  info:   clipe '%s': movimento %.3f" % [nm, Pedestrians.clip_motion(clips[nm])])
	if not clips.is_empty():
		print("  info: PROTAGONISTA.fbx papeis: { 'andar': '%s', 'parado': '%s', 'correr': '%s', 'pulo': '%s' }" % [
			Pedestrians.pick_clip(clips, "walk"),
			Pedestrians.pick_clip(clips, "idle"),
			Pedestrians.pick_clip(clips, "run"),
			Pedestrians.pick_clip(clips, "jump")])
	inst.free()


func _test_player_model() -> void:
	# B-63: o protagonista deixou de ser caixas. O CI prova o que o jogo usa: o
	# modelo carrega, tem esqueleto e clipes, a pintura acerta calca/camisa/pele/
	# cabelo, e o giro deixa o modelo OLHANDO para onde anda.
	var scene := Pedestrians.load_scene(Player.AVATAR_PATH)
	check(scene != null, "modelo do protagonista carrega (%s)" % Player.AVATAR_PATH)
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	var sk := Pedestrians._find_skel(inst)
	var tris := ModelProp.count_tris(inst)
	var box := ModelProp.mesh_aabb(inst)
	print("  info: protagonista: %d tris, %.2f m de bind pose, rig %s" % [
		tris, box.size.y, "sim" if sk != null else "NAO"])
	var ap := Pedestrians._find_anim(inst)
	var clips := {}
	if ap != null:
		for nm in ap.get_animation_list():
			var a := ap.get_animation(String(nm))
			if a != null:
				clips[String(nm)] = a
	check(sk != null and tris > 200, "protagonista tem esqueleto e geometria")
	var walk := Pedestrians.pick_clip(clips, "walk")
	check(walk != "", "clipe de andar no modelo")
	var idle := Pedestrians.pick_clip(clips, "idle")
	check(idle != "", "clipe de parado no modelo")
	check(walk != "" and Pedestrians.clip_motion(clips[walk]) > 0.05,
		"clipe de andar do protagonista tem movimento de verdade")
	if idle != "":
		# O clipe de parado pode ser uma pose estatica: nesse caso o jogo poe um
		# balanco por codigo (`_idle_static`). Aqui so se mede o que veio do arquivo.
		print("  info: protagonista parado: clipe %s com movimento %.3f %s" % [
			idle, Pedestrians.clip_motion(clips[idle]),
			"(estatico: o jogo balanca por codigo)" if Pedestrians.clip_motion(clips[idle]) < 0.02 else "(animado)"])
	inst.free()
	# Frente: o avatar gira por atan2(dir.x, dir.y) e o modelo leva PI (ele olha
	# para -Z). O -Z do modelo tem que apontar no sentido do passo — sem isso ele
	# anda de costas, que foi o bug corrigido nos pedestres (B-62).
	var facing_ok := true
	for d in [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-0.6, 0.8), Vector2(0.0, -1.0)]:
		var b := Basis(Vector3.UP, atan2(d.x, d.y)) * Basis(Vector3.UP, PI)
		var front := -b.z
		if Vector2(front.x, front.z).normalized().distance_to(d.normalized()) > 0.01:
			facing_ok = false
	check(facing_ok, "protagonista olha para onde anda (4 direcoes)")
	# Pintura por altura: calca embaixo, camisa no meio, pele no alto e cabelo na
	# nuca (z > 0 no modelo, que olha para -Z).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in [0.10, 1.00, 1.70]:
		var z := 0.10 if y > 1.5 else 0.0
		st.add_vertex(Vector3(0.0, y, z))
		st.add_vertex(Vector3(0.10, y, z))
		st.add_vertex(Vector3(0.20, y, z))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var painted := Pedestrians.paint_body(mi, Color(1, 1, 1), Color(0, 0, 1),
			Color(1, 0, 0), Color(0, 0, 0))
	check(painted, "pintura do corpo aplica")
	var cols: PackedColorArray = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(cols.size() == 9, "pintura gera 1 cor por vertice (%d)" % cols.size())
	if cols.size() == 9:
		check(cols[0].is_equal_approx(Color(1, 0, 0)), "pe = calca")
		check(cols[3].is_equal_approx(Color(0, 0, 1)), "tronco = camisa")
		check(cols[6].is_equal_approx(Color(0, 0, 0)), "nuca = cabelo preto")
	mi.free()


func _test_shops() -> void:
	# B-65: lojas com interior. O que da para provar sem GPU: o lado da rua que a
	# loja olha, os colisores deixarem o vao ABERTO para o jogador entrar (e as
	# paredes fechadas), a fachada com vao ter 3 pedacos e a loja gerar interior.
	check(CityGen.street_side(10.0, 32.0, 0.0, 0.0) == 0, "lote do oeste olha para o oeste")
	check(CityGen.street_side(54.0, 32.0, 0.0, 0.0) == 1, "lote do leste olha para o leste")
	check(CityGen.street_side(32.0, 10.0, 0.0, 0.0) == 2, "lote do sul olha para o sul")
	check(CityGen.street_side(32.0, 54.0, 0.0, 0.0) == 3, "lote do norte olha para o norte")
	# Colisores: o centro do vao fica LIVRE, o miolo do predio e a parede
	# lateral ficam fechados, nos quatro lados.
	var free_ok := true
	var body_ok := true
	var wall_ok := true
	for side in 4:
		var rects := CityGen.shop_colliders(0.0, 0.0, 12.0, 12.0, side, 5.0, 4.0)
		var bay := [Vector2(-4.0, 0.0), Vector2(4.0, 0.0), Vector2(0.0, -4.0), Vector2(0.0, 4.0)]
		var wall := [Vector2(-4.0, 4.0), Vector2(4.0, 4.0), Vector2(4.0, -4.0), Vector2(4.0, 4.0)]
		if _rect_list_has(rects, bay[side]):
			free_ok = false
		if not _rect_list_has(rects, Vector2(0.5, 0.5)):
			body_ok = false
		if not _rect_list_has(rects, wall[side]):
			wall_ok = false
		check(rects.size() == 3, "loja no lado %d tem 3 colisores (%d)" % [side, rects.size()])
	check(free_ok, "vao da loja aberto: o jogador entra andando")
	check(body_ok, "corpo do predio continua fechado")
	check(wall_ok, "paredes laterais do vao fechadas")
	# Fachada com vao: dois lados + verga (3 quads = 18 vertices), nada tapando
	# o buraco.
	var tb := CityGen.TBuf.new(22.9, 12.0)
	CityGen._wall_with_hole(tb, Vector2(0.0, 0.0), Vector2(10.0, 0.0), 0.0, 12.0,
			3.0, 4.0, 1.0, 4.0, Color.WHITE)
	check(tb.v.size() == 18, "fachada com vao = 3 pedacos (%d vertices)" % tb.v.size())
	var open := true
	for i in range(0, tb.v.size(), 6):
		var a := tb.v[i]
		var c := tb.v[i + 2]
		# Nenhum pedaco pode cobrir o miolo do vao (t entre 3 e 7, y entre 1 e 4).
		var x0 := minf(a.x, c.x)
		var x1 := maxf(a.x, c.x)
		var y0 := minf(a.y, c.y)
		var y1 := maxf(a.y, c.y)
		if x0 < 6.9 and x1 > 3.1 and y0 < 3.9 and y1 > 1.1:
			open = false
	check(open, "vao da fachada livre (sem parede tapando a porta)")
	# A loja gera interior de verdade (piso, forro, 3 paredes, balcao, placa).
	var gb := CityGen.GBuf.new()
	CityGen._add_shop(gb, 0.0, 0.0, 12.0, 12.0, 0, 5.0, 4.0, 1.0, 0)
	check(gb.v.size() > 200, "interior da loja gerado (%d vertices)" % gb.v.size())
	check(gb.v.size() % 3 == 0, "geometria da loja em triangulos")
	check(gb.n.size() == gb.v.size() and gb.c.size() == gb.v.size(),
		"loja com 1 normal e 1 cor por vertice")
	# B-66: cada loja publica balconista, entrada e nome, e o setor entrega isso
	# ao streamer (que alimenta o balconista e o aviso do HUD).
	var spot := CityGen._shop_spot(0.0, 0.0, 12.0, 12.0, 0, 5.0, 4.0, 1.0, 2)
	check(spot.has("stand") and spot.has("front") and spot.has("facing") and spot.has("name"),
		"loja publica stand/front/facing/name")
	var names: Array = []
	for st in CityGen.SHOP_TYPES:
		names.append(String(st[0]))
	check(names.has(String(spot["name"])), "nome da loja vem da tabela (%s)" % spot["name"])
	var stand: Vector3 = spot["stand"]
	var front: Vector3 = spot["front"]
	check(stand.x > -6.0 and stand.x < 6.0 and stand.y > 0.9,
		"balconista em pe dentro do vao (%.2f, %.2f)" % [stand.x, stand.y])
	check(absf(front.x + 4.6) < 0.01, "entrada da loja na boca do vao (%.2f)" % front.x)
	check(Vector2(spot["facing"]).is_equal_approx(Vector2(-1.0, 0.0)),
		"balconista olha para a rua (oeste)")
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	check(full.size() >= 25, "setor traz a lista de lojas (%d arrays)" % full.size())
	if full.size() >= 25:
		var shops: Array = full[24]
		check(shops.size() > 0, "setor com %d lojas publicadas" % shops.size())
		var ok_spots := true
		for s in shops:
			var d: Dictionary = s
			if not (d.has("stand") and d.has("front") and d.has("name")):
				ok_spots = false
		check(ok_spots, "todas as lojas do setor com balconista, entrada e nome")
		var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
		check((far[24] as Array).is_empty(),
			"LOD far sem lojas abertas (frente fechada, sem balconista)")


## O retangulo `p` cai dentro de algum dos Rect2 da lista?
func _rect_list_has(rects: Array, p: Vector2) -> bool:
	for r in rects:
		var rect: Rect2 = r
		if rect.has_point(p):
			return true
	return false


func _test_windows() -> void:
	# Fachada texturada: os predios saem da cor por vertice e vao para uma
	# surface com textura (parede + janela), presente nos dois LODs (predio
	# existe nos dois), com UV e a cor da paleta por vertice.
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	var sea := CityGen.generate(3, -1, 20260922, CityGen.LOD_FULL)
	var fv: PackedVector3Array = full[20]
	var fuv: PackedVector2Array = full[22]
	var fc: PackedColorArray = full[23]
	print("  info: fachada no setor full = %d vertices" % fv.size())
	check(fv.size() > 0 and fv.size() % 3 == 0, "fachadas texturadas geradas (%d vertices)" % fv.size())
	check(fuv.size() == fv.size(), "fachada com 1 UV por vertice")
	check(fc.size() == fv.size(), "fachada com cor por vertice (paleta)")
	check((far[20] as PackedVector3Array).size() > 0, "fachada tambem no LOD far")
	check((sea[20] as PackedVector3Array).is_empty(), "setor de mar sem predios")
	check((full[5] as PackedVector3Array).is_empty(), "sem surface de vidro separada (virou textura)")
	var props_ok := true
	for s in ["poste", "lampadaria", "banco", "lixeira", "carro", "carro_top"]:
		var sh := PropFactory.shape_for(s, 5.5)
		if sh.size() != 2:
			props_ok = false
	var car_col := PropFactory.color_for("carro", 0.5)
	var lamp_col := PropFactory.color_for("lampadaria", 0.0)
	if car_col.r < 0.0 or lamp_col.r < 0.0:
		props_ok = false
	check(props_ok, "props de rua com forma e cor (%d defs no setor)" % full[4].size())


func _test_building_shapes() -> void:
	# B-50: os predios eram TODOS a mesma caixa (o autor reclamou, com razao).
	# Agora o lote sorteia planta (largura x profundidade independentes), recuo
	# (setback / embasamento com torre) e detalhe de cobertura. O teste cobre a
	# matematica da planta e do prisma que o render usa, sem GPU.
	var rect := CityGen._plan_rect(10.0, 20.0, 8.0, 6.0, -1, 0.0)
	check(rect.size() == 4, "planta reta tem 4 cantos (%d)" % rect.size())
	check(absf(CityGen.plan_area(rect) - 48.0) < 0.01,
		"area da planta reta = 8 x 6 (%.2f m2)" % CityGen.plan_area(rect))
	var cham := CityGen._plan_rect(0.0, 0.0, 10.0, 10.0, 2, 3.0)
	check(cham.size() == 5, "planta com esquina chanfrada tem 5 cantos (%d)" % cham.size())
	check(absf(CityGen.plan_area(cham) - (100.0 - 4.5)) < 0.01,
		"chanfro tira o triangulo do canto (%.2f m2)" % CityGen.plan_area(cham))
	var inside := true
	for p in cham:
		var pt: Vector2 = p
		if pt.x < -5.001 or pt.x > 5.001 or pt.y < -5.001 or pt.y > 5.001:
			inside = false
	check(inside, "chanfro corta para dentro da planta")
	# Chanfro enorme nao pode comer metade do predio.
	var big := CityGen._plan_rect(0.0, 0.0, 10.0, 10.0, 0, 99.0)
	check(CityGen.plan_area(big) > 50.0,
		"chanfro limitado a 42%% do lado (%.2f m2 de 100)" % CityGen.plan_area(big))
	# Prisma: 5 paredes (quad = 6 verts) + teto em leque (5 triangulos de 3).
	var tb := CityGen.TBuf.new(22.9, 12.0)
	CityGen._add_prism_tx(tb, cham, 0.0, 12.0, Color.WHITE, Color.WHITE)
	check(tb.v.size() == 5 * 6 + 5 * 3,
		"prisma = 5 paredes + leque no teto (%d verts)" % tb.v.size())
	check(tb.uv.size() == tb.v.size() and tb.col.size() == tb.v.size(),
		"prisma com 1 UV e 1 cor por vertice")
	var bad := 0
	var tested := 0
	var i := 0
	while i + 2 < tb.v.size():
		var a := tb.v[i]
		var b := tb.v[i + 1]
		var c := tb.v[i + 2]
		var front := -(b - a).cross(c - a)
		if front.length() > 0.0001:
			tested += 1
			if front.normalized().dot(tb.n[i]) < 0.9:
				bad += 1
		i += 3
	check(tested >= 10 and bad == 0,
		"prisma com winding coerente (%d/%d)" % [tested - bad, tested])
	# No setor: cobertura detalhada e alturas variadas de topo.
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var kinds := {}
	for d in (full[4] as Array):
		var dd: Dictionary = d
		kinds[String(dd.get("kind", ""))] = true
	var roof_kinds := 0
	for k in ["caixa_dagua", "casa_maquinas", "antena"]:
		if kinds.has(k):
			roof_kinds += 1
	check(roof_kinds >= 2, "cobertura com %d tipos de detalhe" % roof_kinds)
	# B-52: vegetacao do setor tem copa separada do tronco.
	check(kinds.has("palm_crown") or kinds.has("tree_crown"),
		"vegetacao com copa em instancia propria (tronco + copa)")
	var tops := {}
	for p in (full[20] as PackedVector3Array):
		tops[snappedf(p.y, 0.5)] = true
	check(tops.size() > 12, "predios com %d alturas de topo diferentes" % tops.size())


func _test_scripts_compile() -> void:
	# B-20, B-23, B-28 e B-29 foram erros de COMPILACAO que derrubaram o boot
	# inteiro (tela azul no Safari): constante de API do Godot escrita errado
	# em main.gd e em sector_streamer.gd. O CI tem que pegar isso, nao o jogador.
	#
	# Duas licoes entraram aqui (B-30):
	# 1. GDScript NAO tem get_errors() no Godot 4. A chamada existia neste
	#    ponto e ABORTAVA a funcao antes do check(), entao falha de compilacao
	#    passava em silencio. Agora so se registra o arquivo que falhou — o
	#    proprio Godot imprime "Parse Error" com arquivo e linha no log.
	# 2. main.gd e os autoloads entram na lista: o analisador de GDScript
	#    resolve os nomes de autoload pelo project.godot, sem precisar da
	#    arvore de cena. Era por isso que o arquivo mais critico do jogo (o que
	#    monta a cena) nunca era compilado pelo CI.
	var paths := [
		"res://scripts/core/cfg.gd",
		"res://scripts/core/geo.gd",
		"res://scripts/core/perf_log.gd",
		"res://scripts/core/surface_db.gd",
		"res://scripts/physics/damage.gd",
		"res://scripts/physics/prop_body.gd",
		"res://scripts/physics/prop_field.gd",
		"res://scripts/world/city_gen.gd",
		"res://scripts/world/prop_factory.gd",
		"res://scripts/world/prop_mesh.gd",
		"res://scripts/world/model_prop.gd",
		"res://scripts/audio/vehicle_audio.gd",
		"res://scripts/world/traffic.gd",
		"res://scripts/world/pedestrians.gd",
		"res://scripts/world/bone_anim.gd",
		"res://scripts/world/sector_streamer.gd",
		"res://scripts/world/day_night.gd",
		"res://scripts/vehicles/car.gd",
		"res://scripts/vehicles/vehicle_physics.gd",
		"res://scripts/player/player.gd",
		"res://scripts/ui/touch_controls.gd",
		"res://scripts/ui/hud.gd",
		"res://scripts/autoload/world.gd",
		"res://scripts/autoload/save_manager.gd",
		"res://scripts/game/wanted.gd",
		"res://scripts/game/ipanema.gd",
		"res://scripts/game/missions.gd",
		"res://scripts/game/mission_runner.gd",
		"res://scripts/ui/gta_hud.gd",
		"res://scripts/ui/radar.gd",
		"res://scripts/world/police.gd",
		"res://scripts/main.gd",
	]
	var failed := PackedStringArray()
	for p in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			failed.append(p + " (nao abriu)")
			continue
		var gds := GDScript.new()
		gds.source_code = f.get_as_text()
		f.close()
		if gds.reload() != OK:
			failed.append(p)
	check(failed.is_empty(), "scripts do jogo compilam (%d/%d)%s" % [
		paths.size() - failed.size(), paths.size(),
		"" if failed.is_empty() else " - falharam: " + ",".join(failed)])


# --- Salvamento --------------------------------------------------------------

func _test_save_roundtrip() -> void:
	var sm = SaveManager.new()
	var state := {"player": {"pos": [10.0, 1.0, 20.0]}, "clock": {"hour": 13.5}, "n": 42}
	check(sm.save_state(state, "teste"), "salvar grava arquivo (erro: %s)" % sm.last_error)
	var loaded: Dictionary = sm.load_state("teste")
	check(not loaded.is_empty(), "carregar devolve estado (erro: %s)" % sm.last_error)
	check(int(loaded.get("schema", -1)) == Cfg.SAVE_SCHEMA, "schema gravado = %d" % Cfg.SAVE_SCHEMA)
	check(int(loaded.get("n", 0)) == 42, "dados preservados")
	check(loaded.has("saved_unix"), "timestamp presente")
	check(sm.has_save("teste") and sm.list_saves().has("teste"), "listagem de saves")
	sm.delete_save("teste")
	check(not sm.has_save("teste"), "exclusao de save")
	sm.free()


func _test_save_rejects() -> void:
	var sm = SaveManager.new()
	sm.save_state({"player": {}}, "teste2")
	var path: String = sm.save_path("teste2")

	# 1) Arquivo com schema do futuro: recusa sem apagar.
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var nl := -1
	for i in bytes.size():
		if bytes[i] == 10:
			nl = i
			break
	var rest := bytes.slice(nl + 1)
	# O cabecalho e TEXTO: MAGIC;schema;versao;sha256;tamanho. Antes daqui o
	# teste fazia str(bytes) (que nao devolve o texto) e estourava no indice 3,
	# abortando a funcao e pulando as 3 checagens abaixo sem avisar (B-30).
	var fields := bytes.slice(0, nl).get_string_from_utf8().split(";")
	var digest := String(fields[3]) if fields.size() == 5 else ""
	var header := "CARIOCA-SAVE;999;0.1.0-dev;%s;%d\n" % [digest, rest.size()]
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_buffer(header.to_utf8_buffer())
	w.store_buffer(rest)
	w.close()
	var r1: Dictionary = sm.load_state("teste2")
	check(r1.is_empty() and sm.last_error.contains("mais nova"), "recusa save de schema futuro")
	check(sm.has_save("teste2"), "arquivo de schema futuro nao e apagado")

	# 2) Byte alterado: checksum falha.
	sm.save_state({"player": {}}, "teste2")
	f = FileAccess.open(path, FileAccess.READ)
	bytes = f.get_buffer(f.get_length())
	f.close()
	bytes[bytes.size() - 1] = (bytes[bytes.size() - 1] + 1) % 256
	w = FileAccess.open(path, FileAccess.WRITE)
	w.store_buffer(bytes)
	w.close()
	var r2: Dictionary = sm.load_state("teste2")
	check(r2.is_empty() and sm.last_error.contains("checksum"), "recusa save corrompido")
	sm.delete_save("teste2")
	sm.free()


# --- Setores -----------------------------------------------------------------

func _test_sectors() -> void:
	check(Cfg.sector_of(0.0, 0.0) == Vector2i(0, 0), "sector_of(0,0) = (0,0)")
	check(Cfg.sector_of(-1.0, -1.0) == Vector2i(-1, -1), "sector_of(-1,-1) = (-1,-1)")
	check(Cfg.sector_of(513.0, 512.0) == Vector2i(1, 1), "sector_of(513,512) = (1,1)")
	check(Cfg.sector_in_bounds(Vector2i(0, 0)), "setor (0,0) valido")
	check(not Cfg.sector_in_bounds(Vector2i(99, 0)), "setor (99,0) invalido")
	var km2 := (Cfg.WORLD_MAX.x - Cfg.WORLD_MIN.x) * (Cfg.WORLD_MAX.y - Cfg.WORLD_MIN.y) / 1_000_000.0
	print("  info: fatia jogavel da Fase 1 = %.1f km2 (alvo do mundo completo: 83 km2)" % km2)


# --- GTA: procurado, bairro, missoes, policia, radar e HUD --------------------
# Tudo o que o jogador sente como "justo" ou nao (o nivel de procurado, a
# chegada de uma missao, o recorte do radar) e puro e verificado aqui, sem GPU.

func _test_wanted() -> void:
	check(Wanted.stars(0.0) == 0, "sem calor = sem estrela")
	check(Wanted.stars(1.0) == 1, "calor 1,0 = 1 estrela")
	check(Wanted.stars(0.4) == 1, "calor 0,4 ja acende 1 estrela (arredonda para cima)")
	check(Wanted.stars(2.1) == 3, "calor 2,1 = 3 estrelas")
	check(Wanted.stars(9.0) == Wanted.MAX_STARS, "calor acima do teto para em 5 estrelas")
	check(is_equal_approx(Wanted.add(0.0, "tiro"), Wanted.crime_heat("tiro")),
		"o calor do tiro vem da tabela de crimes")
	check(Wanted.stars(Wanted.add(0.0, "tiro")) >= 1, "o primeiro crime ja acende estrela")
	check(Wanted.stars(Wanted.add(0.0, "tiro")) >= 2, "um tiro em policial acende mais de uma")
	check(is_equal_approx(Wanted.add(4.9, "policial_morto"), 5.0),
		"calor satura em 5 (nao passa do teto)")
	check(Wanted.decay(1.0, 0.0, false) == 1.0, "sem tempo nao esfria")
	check(Wanted.decay(1.0, 10.0, true) == 1.0, "visto pela policia nao esfria")
	check(Wanted.decay(1.0, 1.0, false) < 1.0, "fora de vista esfria")
	check(Wanted.decay(0.5, 100.0, false) == 0.0, "calor nunca fica negativo")
	check(Wanted.decay_rate(5) < Wanted.decay_rate(1), "5 estrelas esfria mais devagar que 1")
	check(Wanted.cop_count(0) == 0 and Wanted.cop_count(3) == 3,
		"viaturas acompanham as estrelas")
	check(Wanted.cop_count(99) == Wanted.MAX_COPS, "viaturas tem teto")
	check(Wanted.cop_speed(5) > Wanted.cop_speed(1), "5 estrelas persegue mais rapido")
	check(Wanted.busted_fine(1000) == 200, "multa de ser preso = 20%")
	check(Wanted.busted_fine(-10) == 0, "multa nunca e negativa")
	check(Wanted.wanted_line(0) == "", "sem estrela nao anuncia procurado")
	check(Wanted.wanted_line(1).contains("1"), "uma estrela aparece no texto")


func _test_ipanema() -> void:
	var street := Ipanema.street_at(1728.0, 288.0)
	check(not street.is_empty(), "rua identificada numa linha da grade (%s)" % street)
	check(Ipanema.street_at(1728.0, 288.0) == Ipanema.street_at(1728.0, 310.0),
		"a mesma rua vale ao longo da quadra")
	check(Ipanema.street_at(1700.0, 500.0) == Ipanema.street_at(1700.0, 500.0),
		"nome de rua e deterministico")
	check(Ipanema.district_at(1600.0, 60.0) == "Praia de Ipanema",
		"ao sul da Avenida Atlantica e praia")
	check(Ipanema.district_at(2600.0, 200.0) == "Arpoador", "o leste e o Arpoador")
	check(Ipanema.place("posto9") != Vector3.ZERO, "ponto do bairro resolvido em metros")
	check(Ipanema.place("nao_existe") == Vector3.ZERO, "ponto desconhecido = origem")
	check(is_equal_approx(Ipanema.place("posto9").y, Cfg.surface_at(1632.0, 96.0)),
		"ponto do bairro apoiado no chao analitico")
	check(Ipanema.nearest_place(Ipanema.place("osorio")) == "osorio",
		"ponto mais proximo encontrado")
	check(Ipanema.location_line(1728.0, 288.0).contains("\n"),
		"localizacao traz bairro e rua")


func _test_missions() -> void:
	check(Missions.count() >= 3, "%d missoes no roteiro" % Missions.count())
	var m := Missions.mission_at(0)
	check(not m.is_empty(), "missao 0 existe")
	check(not Missions.title_of(m).is_empty(), "missao tem titulo")
	check(Missions.step_count(m) > 0, "missao tem passos")
	var first := Missions.mission_at(0)
	var after := Missions.mission_at(Missions.count())
	check(String(after.get("id", "")) == String(first.get("id", "")),
		"o roteiro volta ao comeco depois da ultima missao")
	check(Missions.giver_pos(m) != Vector3.ZERO, "ponto de inicio da missao no mundo")
	var got_goto := false
	for i in Missions.step_count(m):
		var st := Missions.step_at(m, i)
		if Missions.step_kind(st) == "goto":
			got_goto = true
			check(Missions.has_target(st), "passo goto tem alvo")
			check(Missions.step_pos(st) != Vector3.ZERO, "alvo do passo existe no mapa")
			check(Missions.step_radius(st) > 2.0, "passo tem raio de chegada")
			check(not Missions.objective_text(m, i).is_empty(), "passo tem objetivo escrito")
	check(got_goto, "missao com passo de deslocamento")
	check(Missions.step_at(m, 99).is_empty(), "passo fora do roteiro e vazio")
	check(Missions.reward_of(m) > 0, "missao paga")


func _test_police_pure() -> void:
	var mesh := Police.cop_mesh()
	check(mesh != null and mesh.get_surface_count() == 1,
		"malha da viatura assada em UMA superficie (1 desenho)")
	var verts := 0
	if mesh != null and mesh.get_surface_count() > 0:
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		verts = v.size()
	check(verts > 100 and verts < 1500, "viatura com %d vertices (barata)" % verts)


func _test_radar() -> void:
	var east := Radar.project(Vector2(10.0, 0.0), 0.0, 1.0)
	check(east.is_equal_approx(Vector2(10.0, 0.0)), "yaw 0: leste fica a direita do radar")
	var front := Radar.project(Vector2(0.0, -10.0), 0.0, 1.0)
	check(front.y < 0.0, "yaw 0: o que esta a frente (-Z) sobe no radar")
	var seg := Radar.clip_segment(Vector2(-500.0, 0.0), Vector2(500.0, 0.0), 100.0)
	check(seg.size() == 2, "rua que cruza o radar e recortada em 2 pontos")
	if seg.size() == 2:
		check(seg[0].is_equal_approx(Vector2(-100.0, 0.0)) and
			seg[1].is_equal_approx(Vector2(100.0, 0.0)),
			"o recorte cai exatamente na borda do circulo")
	check(Radar.clip_segment(Vector2(-500.0, 300.0), Vector2(500.0, 300.0), 100.0).is_empty(),
		"rua fora do circulo nao desenha")
	var poly := Radar.disc_below(0.0, 100.0)
	check(poly.size() > 10, "faixa do mar tem contorno (%d pontos)" % poly.size())
	var inside := true
	for p in poly:
		if p.length() > 100.5:
			inside = false
	check(inside, "faixa do mar nunca vaza do radar")
	check(Radar.disc_below(-200.0, 100.0).is_empty(), "faixa acima do circulo e vazia")
	check(Radar.disc_below(200.0, 100.0).size() >= 40,
		"faixa que cobre tudo devolve o circulo inteiro")


func _test_gta_hud_pure() -> void:
	check(GtaHud.money_text(0) == "0", "dinheiro zero")
	check(GtaHud.money_text(1500) == "1.500", "milhar com ponto")
	check(GtaHud.money_text(1234567) == "1.234.567", "milhoes com pontos")
	check(GtaHud.money_text(-2500) == "-2.500", "dinheiro negativo")
	var pts := GtaHud.star_points(Vector2.ZERO, 10.0, 4.0)
	check(pts.size() == 10, "estrela com 10 vertices")
	var fits := true
	for p in pts:
		if p.length() > 10.5:
			fits = false
	check(fits, "estrela cabe no raio externo")


func _test_player_combat() -> void:
	check(Player.WEAPONS.has("punho") and Player.WEAPONS.has("pistola"),
		"punho e pistola cadastrados")
	var fist: Dictionary = Player.WEAPONS["punho"]
	var gun: Dictionary = Player.WEAPONS["pistola"]
	check(float(gun["range"]) > float(fist["range"]), "a pistola alcanca mais que o punho")
	check(float(gun["damage"]) > float(fist["damage"]), "a pistola machuca mais")
	check(bool(gun["ammo"]) and not bool(fist["ammo"]), "so a pistola gasta municao")
	check(float(fist["cool"]) > float(gun["cool"]), "o punho tem mais espera entre golpes")
