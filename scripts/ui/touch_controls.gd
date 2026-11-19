extends Control
## TouchControls: entrada de toque do jogo (Fase 1).
##
## Layout (paisagem):
##   - metade esquerda da tela   -> joystick virtual flutuante (anda)
##   - metade direita da tela    -> arrastar gira a camera
##   - botao PULAR (canto inferior direito)  -> pulo
##   - botao CORRER (ao lado do PULAR)       -> corrida
## A faixa superior (TOP_UI) e reservada a interface e nao vira camera.
##
## Cada dedo e reivindicado por um controle pelo seu index. NONE (-99) indica
## controle livre; MOUSE (-1) e usado no desktop.

const STICK_MAX := 90.0
const TOP_UI := 0.17
const BUTTON_RADIUS := 46.0
const NONE := -99
const MOUSE := -1

static var stick_vec := Vector2.ZERO
static var look_delta := Vector2.ZERO
static var jump_held_s := false
static var jump_pressed_s := false
static var sprint_held_s := false

var _stick_index := NONE
var _stick_origin := Vector2.ZERO
var _look_index := NONE
var _jump_index := NONE
var _sprint_index := NONE
var _jump_pos := Vector2.ZERO
var _sprint_pos := Vector2.ZERO
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_layout_buttons()


func _layout_buttons() -> void:
	var vs := get_viewport_rect().size
	var safe_bottom := vs.y - 40.0
	_jump_pos = Vector2(vs.x - 86.0, safe_bottom - 60.0)
	_sprint_pos = Vector2(vs.x - 196.0, safe_bottom - 24.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_layout_buttons()
		queue_redraw()


# --- API estatica (usada por player.gd) --------------------------------------

static func stick() -> Vector2:
	return stick_vec


static func is_active() -> bool:
	return stick_vec.length() > 0.08


static func consume_look() -> Vector2:
	var out := look_delta
	look_delta = Vector2.ZERO
	return out


static func jump_pressed() -> bool:
	var out := jump_pressed_s
	jump_pressed_s = false
	return out


static func jump_held() -> bool:
	return jump_held_s


static func sprint_held() -> bool:
	return sprint_held_s


# --- Entrada ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_touch(int(t.index), t.position, t.pressed)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(int(d.index), d.position, d.relative)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_touch(MOUSE, mb.position, mb.pressed)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mm := event as InputEventMouseMotion
		_drag(MOUSE, mm.position, mm.relative)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if index == _stick_index:
			_stick_index = NONE
			stick_vec = Vector2.ZERO
			queue_redraw()
		elif index == _look_index:
			_look_index = NONE
		elif index == _jump_index:
			_jump_index = NONE
			jump_held_s = false
			queue_redraw()
		elif index == _sprint_index:
			_sprint_index = NONE
			sprint_held_s = false
			queue_redraw()
		return

	var vs := get_viewport_rect().size
	if pos.y < vs.y * TOP_UI:
		return  # faixa da interface

	if pos.distance_to(_jump_pos) < BUTTON_RADIUS * 1.5:
		_jump_index = index
		jump_held_s = true
		jump_pressed_s = true
		queue_redraw()
		return
	if pos.distance_to(_sprint_pos) < BUTTON_RADIUS * 1.3:
		_sprint_index = index
		sprint_held_s = true
		queue_redraw()
		return

	if pos.x < vs.x * 0.5 and _stick_index == NONE:
		_stick_index = index
		_stick_origin = pos
		stick_vec = Vector2.ZERO
		queue_redraw()
	elif _look_index == NONE:
		_look_index = index


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _stick_index:
		var d := pos - _stick_origin
		if d.length() > STICK_MAX:
			d = d.normalized() * STICK_MAX
			_stick_origin = pos - d
		stick_vec = d / STICK_MAX
		queue_redraw()
	elif index == _look_index:
		look_delta += relative


# --- Desenho ------------------------------------------------------------------

func _draw() -> void:
	var vs := get_viewport_rect().size
	var hint := Vector2(110.0, vs.y - 120.0)
	if _stick_index != NONE:
		draw_circle(_stick_origin, STICK_MAX + 8.0, Color(1, 1, 1, 0.07))
		draw_arc(_stick_origin, STICK_MAX, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
		draw_circle(_stick_origin + stick_vec * STICK_MAX, 28.0, Color(1, 1, 1, 0.42))
	else:
		draw_circle(hint, 62.0, Color(1, 1, 1, 0.05))
		draw_circle(hint, 26.0, Color(1, 1, 1, 0.12))

	_draw_button(_jump_pos, "PULAR", Color(0.95, 0.55, 0.25, 0.55), jump_held_s)
	_draw_button(_sprint_pos, "CORRER", Color(0.35, 0.62, 0.90, 0.50), sprint_held_s)


func _draw_button(center: Vector2, label: String, col: Color, active: bool) -> void:
	var c := col
	c.a = col.a + (0.25 if active else 0.0)
	draw_circle(center, BUTTON_RADIUS, c)
	draw_arc(center, BUTTON_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.0)
	if _font == null:
		return
	var size := 13
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(_font, center + Vector2(-w * 0.5, 5.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.95))
