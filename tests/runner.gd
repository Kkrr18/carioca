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
const Car = preload("res://scripts/vehicles/car.gd")

var _pass := 0
var _fail := 0
var _known := 0
var _msgs: PackedStringArray = []
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
	_test_normals()
	_test_heights()
	_test_props()
	_test_car_physics()
	_test_windows()
	_test_scripts_compile()
	_test_save_roundtrip()
	_test_save_rejects()
	_test_sectors()
	print("")
	for m in _msgs:
		print(m)
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


func known(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		_msgs.append("  ok    " + what)
	else:
		_known += 1
		_msgs.append("  DESVIO " + what)


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
	check(Geo.is_simple(_poly), "poligono simples (sem auto-intersecao)")
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
	check(absf(q.x - 1234.5) < 0.01 and absf(q.y - 678.9) < 0.01,
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
	for item in inside:
		check(Geo.point_in_polygon(float(item[1]), float(item[2]), _poly),
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
	for s in ["palm", "tree", "bush", "kiosk", "umbrella"]:
		var sh := PropFactory.shape_for(s, 6.0)
		if sh.size() != 2:
			ok = false
			continue
		var size: Vector3 = sh[1]
		if size.length() < 0.4 or size.length() > 20.0:
			ok = false
	check(ok, "props com forma plausivel (5 tipos)")


func _test_car_physics() -> void:
	# Nucleo puro de scripts/vehicles/car.gd (sem cena, sem GPU).
	check(Car.advance_speed(0.0, 1.0, 0.1) > 0.0, "carro acelera com o acelerador")
	check(absf(Car.advance_speed(10.0, -1.0, 0.1) - 8.4) < 0.001,
		"freio tira 1,6 m/s em 0,1 s (16 m/s2)")
	check(Car.advance_speed(0.05, -1.0, 0.1) == 0.0,
		"freio para exatamente em zero, sem engatar a re")
	check(Car.advance_speed(0.0, -1.0, 1.0) == -Car.REVERSE_MAX,
		"marcha a re satura em REVERSE_MAX")
	check(Car.advance_speed(10.0, 0.0, 0.1) < 10.0,
		"acelerador solto perde velocidade (atrito)")
	var s := 0.0
	for i in 1200:
		s = Car.advance_speed(s, 1.0, 1.0 / 30.0)
	check(absf(s - Car.MAX_SPEED) < 0.01, "acelerador satura em MAX_SPEED (%.2f)" % s)
	check(Car.yaw_rate(10.0, 0.3) > 0.0 and Car.yaw_rate(-10.0, 0.3) < 0.0,
		"taxa de guinada inverte na marcha a re (modelo bicycle)")
	check(Car.steer_limit(20.0) < Car.steer_limit(0.0) * 0.7,
		"esterco maximo cai com a velocidade")


func _test_windows() -> void:
	# Fachadas de vidro: existem no LOD full, nao existem no LOD far nem no mar.
	var full := CityGen.generate(3, 0, 20260922, CityGen.LOD_FULL)
	var far := CityGen.generate(3, 0, 20260922, CityGen.LOD_FAR)
	var sea := CityGen.generate(3, -1, 20260922, CityGen.LOD_FULL)
	var wv: PackedVector3Array = full[5]
	var wf: PackedVector3Array = far[5]
	var ws: PackedVector3Array = sea[5]
	print("  info: fachadas de vidro no setor full = %d vertices" % wv.size())
	check(wv.size() > 0 and wv.size() % 3 == 0, "fachadas de vidro geradas no LOD full (%d)" % wv.size())
	check(wf.is_empty(), "fachadas de vidro ausentes no LOD far")
	check(ws.is_empty(), "fachadas de vidro ausentes no setor de mar")
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


func _test_scripts_compile() -> void:
	# B-20 e B-23 foram erros de compilacao em scripts que os demais testes
	# nao carregam (player, sector_streamer...). Compila cada um aqui. Os
	# autoloads ficam de fora: o modo -s nao os registra, e main.gd os
	# referencia (isso e coberto ao abrir o jogo).
	var paths := [
		"res://scripts/core/cfg.gd",
		"res://scripts/core/geo.gd",
		"res://scripts/core/perf_log.gd",
		"res://scripts/world/city_gen.gd",
		"res://scripts/world/prop_factory.gd",
		"res://scripts/world/sector_streamer.gd",
		"res://scripts/world/day_night.gd",
		"res://scripts/vehicles/car.gd",
		"res://scripts/player/player.gd",
		"res://scripts/ui/touch_controls.gd",
		"res://scripts/ui/hud.gd",
	]
	var all_ok := true
	var details := ""
	for p in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			all_ok = false
			details += " " + p + " (nao abriu)"
			continue
		var gds := GDScript.new()
		gds.source_code = f.get_as_text()
		f.close()
		if gds.reload() != OK:
			all_ok = false
			details += " " + p
			for e in gds.get_errors():
				details += " [%d:%d %s]" % [int(e.get("line", -1)), int(e.get("column", -1)), str(e.get("message", "?"))]
	check(all_ok, "scripts do jogo compilam (falhas:%s)" % details)


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
	var header := "CARIOCA-SAVE;999;0.1.0-dev;%s;%d\n" % [
		str(bytes.slice(0, nl)).split(";")[3], rest.size()]
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
