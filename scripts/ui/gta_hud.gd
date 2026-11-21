extends Control
## GtaHud: a interface do jogo, com o vocabulario visual do GTA — dinheiro no
## canto, vida e colete em barras, estrelas de procurado, arma, missao, legenda
## e o radar circular. Tudo desenhado por codigo (nenhuma textura nova).
##
## Este arquivo NAO guarda regra de jogo: ele le o estado de player/police/
## mission_runner e desenha. A telemetria de desenvolvimento continua no hud.gd,
## que fica ESCONDIDO por padrao e volta com um toque no botao DEV.

signal debug_toggled(on: bool)

const Cfg = preload("res://scripts/core/cfg.gd")
const Wanted = preload("res://scripts/game/wanted.gd")
const Ipanema = preload("res://scripts/game/ipanema.gd")
const Radar = preload("res://scripts/ui/radar.gd")

const HEALTH_COL := Color(0.35, 0.82, 0.40)
const HEALTH_LOW := Color(0.90, 0.25, 0.20)
const ARMOR_COL := Color(0.35, 0.62, 0.95)
const MONEY_COL := Color(0.62, 0.90, 0.62)
const STAR_COL := Color(1.00, 0.84, 0.20)
const STAR_OFF := Color(0.18, 0.18, 0.19, 0.85)
const PANEL := Color(0.05, 0.05, 0.06, 0.55)
const TEXT := Color(1, 1, 1, 1)

var player = null
var police = null
var runner = null
var radar = null

var _ui := 1.0
var _rmoney: Label
var _robjective: Label
var _rsubtitle: Label
var _rlocation: Label
var _rweapon: Label
var _rtoast: Label
var _rbanner: Label
var _rstate: Label

var _toast_t := 0.0
var _sub_t := 0.0
var _banner_t := 0.0
var _state_t := 0.0
var _flash := 0.0
var _pulse := 0.0
var _refresh := 0.0
var _debug := false
var _dev_rect := Rect2()
var _focus := Vector3.ZERO
var _focus_yaw := 0.0
var _has_focus := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func setup(p: Node, pol: Node, run: Node) -> void:
	player = p
	police = pol
	runner = run
	if radar != null:
		radar.player = p
		radar.police = pol
		radar.runner = run


## Foco do mundo para o radar e para o nome da rua: o carro quando dirigindo,
## o personagem a pe. `yaw` e o rumo da camera (ou do carro) para girar o mapa.
func update_focus(p: Vector3, yaw: float) -> void:
	_focus = p
	_focus_yaw = yaw
	_has_focus = true
	if radar != null:
		radar.focus_pos = p
		radar.focus_yaw = yaw
		radar.has_focus = true


func _build() -> void:
	var vs := get_viewport_rect().size
	_ui = clampf(vs.y * get_tree().root.content_scale_factor / 640.0, 1.15, 2.2)

	_rtoast = _label(17.0, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_rtoast.set_anchors_preset(Control.PRESET_CENTER)
	_rtoast.offset_left = -420.0 * _ui
	_rtoast.offset_right = 420.0 * _ui
	_rtoast.offset_top = -120.0 * _ui
	_rtoast.offset_bottom = -80.0 * _ui
	_rtoast.modulate.a = 0.0

	_rbanner = _label(34.0, Color(1.0, 0.94, 0.80), HORIZONTAL_ALIGNMENT_CENTER)
	_rbanner.set_anchors_preset(Control.PRESET_CENTER)
	_rbanner.offset_left = -520.0 * _ui
	_rbanner.offset_right = 520.0 * _ui
	_rbanner.offset_top = -190.0 * _ui
	_rbanner.offset_bottom = -110.0 * _ui
	_rbanner.modulate.a = 0.0

	_rstate = _label(64.0, Color(0.90, 0.18, 0.15), HORIZONTAL_ALIGNMENT_CENTER)
	_rstate.set_anchors_preset(Control.PRESET_CENTER)
	_rstate.offset_left = -560.0 * _ui
	_rstate.offset_right = 560.0 * _ui
	_rstate.offset_top = -60.0 * _ui
	_rstate.offset_bottom = 40.0 * _ui
	_rstate.modulate.a = 0.0

	_robjective = _label(19.0, Color(1.0, 0.92, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_robjective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_robjective.offset_left = -460.0 * _ui
	_robjective.offset_right = 460.0 * _ui
	_robjective.offset_top = 14.0 * _ui
	_robjective.offset_bottom = 80.0 * _ui
	_robjective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_rmoney = _label(28.0, MONEY_COL, HORIZONTAL_ALIGNMENT_RIGHT)
	_rmoney.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rmoney.offset_left = -320.0 * _ui
	_rmoney.offset_right = -22.0 * _ui
	_rmoney.offset_top = 58.0 * _ui
	_rmoney.offset_bottom = 98.0 * _ui

	_rlocation = _label(15.0, Color(0.92, 0.94, 0.98), HORIZONTAL_ALIGNMENT_RIGHT)
	_rlocation.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_rlocation.offset_left = -420.0 * _ui
	_rlocation.offset_right = -22.0 * _ui
	_rlocation.offset_top = -250.0 * _ui
	_rlocation.offset_bottom = -196.0 * _ui

	_rweapon = _label(17.0, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_RIGHT)
	_rweapon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_rweapon.offset_left = -420.0 * _ui
	_rweapon.offset_right = -22.0 * _ui
	_rweapon.offset_top = -190.0 * _ui
	_rweapon.offset_bottom = -158.0 * _ui

	_rsubtitle = _label(20.0, Color(1.0, 1.0, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_rsubtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_rsubtitle.offset_left = -520.0 * _ui
	_rsubtitle.offset_right = 520.0 * _ui
	_rsubtitle.offset_top = -330.0 * _ui
	_rsubtitle.offset_bottom = -260.0 * _ui
	_rsubtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rsubtitle.modulate.a = 0.0

	radar = Radar.new()
	radar.name = "Radar"
	add_child(radar)


func _label(sz: float, col: Color, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", int(sz * _ui))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(2, int(4.0 * _ui)))
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# --- Textos puros (testados no CI) -------------------------------------------

## Dinheiro no formato brasileiro: 1500 -> "1.500".
static func money_text(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	var n := s.length()
	for i in n:
		if i > 0 and (n - i) % 3 == 0:
			out += "."
		out += s[i]
	if out.is_empty():
		out = "0"
	return ("-" if neg else "") + out


## Pontos de uma estrela de 5 pontas (poligono fechado) centrada em `c`.
static func star_points(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var r := outer if (i % 2) == 0 else inner
		var a := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


# --- API usada pelo main ------------------------------------------------------

func toast(msg: String) -> void:
	if _rtoast == null:
		return
	_rtoast.text = msg
	_toast_t = 3.2


func say(who: String, text: String, secs: float = 4.0) -> void:
	if _rsubtitle == null:
		return
	_rsubtitle.text = ("%s: %s" % [who, text]) if not who.is_empty() else text
	_sub_t = maxf(1.5, secs)


func banner(text: String, secs: float = 2.5) -> void:
	if _rbanner == null:
		return
	_rbanner.text = text
	_banner_t = maxf(0.5, secs)


func show_state(text: String, secs: float = 2.6) -> void:
	if _rstate == null:
		return
	_rstate.text = text
	_state_t = maxf(0.5, secs)


## Dano na tela: um piscar vermelho proporcional (o "flinch" do GTA).
func flinch(amount: float) -> void:
	_flash = clampf(_flash + maxf(0.15, amount), 0.0, 1.0)


func is_debug_visible() -> bool:
	return _debug


# --- Ciclo --------------------------------------------------------------------

func _process(delta: float) -> void:
	_pulse += delta
	_toast_t = maxf(0.0, _toast_t - delta)
	_sub_t = maxf(0.0, _sub_t - delta)
	_banner_t = maxf(0.0, _banner_t - delta)
	_state_t = maxf(0.0, _state_t - delta)
	_flash = maxf(0.0, _flash - delta * 1.8)
	if _rtoast != null:
		_rtoast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _rsubtitle != null:
		_rsubtitle.modulate.a = clampf(_sub_t, 0.0, 1.0)
	if _rbanner != null:
		_rbanner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	if _rstate != null:
		_rstate.modulate.a = clampf(_state_t, 0.0, 1.0)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_refresh_texts()
	queue_redraw()


func _refresh_texts() -> void:
	if player == null:
		return
	if _rmoney != null:
		_rmoney.text = "R$ " + money_text(int(player.money))
	if _rweapon != null:
		var ammo := ""
		if int(player.ammo) > 0:
			ammo = "  %d" % int(player.ammo)
		_rweapon.text = String(player.weapon_label()) + ammo
	if _rlocation != null:
		var here: Vector3 = _focus if _has_focus else player.position
		_rlocation.text = Ipanema.location_line(here.x, here.z)
	if _robjective != null:
		if runner != null and bool(runner.get("active")):
			var title := String(runner.get("mission_title"))
			var obj := String(runner.get("objective"))
			_robjective.text = "%s\n%s" % [title, obj]
		else:
			_robjective.text = ""


# --- Desenho ------------------------------------------------------------------

func _draw() -> void:
	var sz := size
	# Barras de vida e colete (canto superior esquerdo).
	if player != null:
		var w := 200.0 * _ui
		var h := 13.0 * _ui
		var x := 22.0 * _ui
		var y := 26.0 * _ui
		var hp := clampf(float(player.health) / maxf(1.0, float(player.max_health)), 0.0, 1.0)
		_bar(Rect2(x, y, w, h), hp, HEALTH_COL.lerp(HEALTH_LOW, 1.0 - hp))
		var ar := clampf(float(player.armor) / 100.0, 0.0, 1.0)
		if ar > 0.0:
			_bar(Rect2(x, y + h + 5.0 * _ui, w * 0.82, h * 0.78), ar, ARMOR_COL)
	# Estrelas de procurado (canto superior direito).
	var stars := 0
	if police != null:
		stars = int(police.stars)
	for i in Wanted.MAX_STARS:
		var c := Vector2(sz.x - (30.0 + float(Wanted.MAX_STARS - 1 - i) * 26.0) * _ui, 32.0 * _ui)
		var pts := star_points(c, 11.0 * _ui, 4.6 * _ui)
		if i < stars:
			# A estrela mais recente pisca: e o aviso de que subiu de nivel.
			var hot := (i == stars - 1) and fmod(_pulse, 0.8) < 0.45
			draw_colored_polygon(pts, STAR_COL if not hot else Color(1, 0.55, 0.25))
			draw_polyline(_closed(pts), Color(0.35, 0.24, 0.02, 0.9), maxf(1.0, 1.2 * _ui))
		else:
			draw_colored_polygon(pts, STAR_OFF)
	# Dano: pisca vermelho nas bordas da tela.
	if _flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.75, 0.05, 0.05, 0.30 * _flash))
	# Botao DEV (toque): abre e fecha a telemetria. Vive no rodape, longe dos
	# controles de toque, e e lido por _input (Button do Godot nao funciona no
	# iPhone — B-38).
	var dev_w := 54.0 * _ui
	var dev_h := 22.0 * _ui
	_dev_rect = Rect2(Vector2(sz.x * 0.5 - dev_w * 0.5, sz.y - dev_h - 8.0 * _ui), Vector2(dev_w, dev_h))
	draw_rect(_dev_rect, PANEL)
	draw_rect(_dev_rect, Color(1, 1, 1, 0.18), false, maxf(1.0, 1.0 * _ui))
	var f := ThemeDB.fallback_font
	if f != null:
		var fs := int(11.0 * _ui)
		var tw := f.get_string_size("DEV", HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, _dev_rect.position + Vector2((dev_w - tw) * 0.5, dev_h * 0.72), "DEV",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75))


func _bar(r: Rect2, fill: float, col: Color) -> void:
	draw_rect(r, Color(0.04, 0.04, 0.05, 0.72))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(fill, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.22), false, maxf(1.0, 1.0 * _ui))


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if out.size() > 0:
		out.append(out[0])
	return out


# --- Toque no DEV ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var pos := Vector2(-1.0, -1.0)
	var pressed := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		pos = t.position
		pressed = t.pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pos = mb.position
			pressed = mb.pressed
	if not pressed:
		return
	if _dev_rect.has_point(pos):
		_debug = not _debug
		debug_toggled.emit(_debug)
