extends Control
## TouchControls: entrada de toque do jogo (Fase 1).
##
## Layout a pe (paisagem):
##   - metade esquerda da tela   -> joystick virtual flutuante (anda)
##   - metade direita da tela    -> arrastar gira a camera
##   - botoes no canto inferior direito: PULAR / CORRER
## Dirigindo (set_driving(true)), os MESMOS dois botoes viram:
##   - ACEL (acelerar) e FREIO (frear / marcha a re)
## e o joystick passa a virar o volante (o carro tambem aceita o arrasto do
## joystick para cima como acelerador, so pela metade).
## A faixa superior (TOP_UI) e reservada a interface e nao vira camera.
##
## Cada dedo e reivindicado por um controle pelo seu index. NONE (-99) indica
## controle livre; MOUSE (-1) e usado no desktop.
##
## ESCALA (B-35): o jogo e desenhado num viewport logico de 1280x720 esticado
## para a tela do iPhone. Em retrato a altura logica chega a ~2770 px e um
## botao de 46 px aparecia com ~16 px reais, pequeno demais para o dedo. Os
## tamanhos aqui sao multiplicados por _ui, derivado da altura logica.

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
static var pedal_gas_s := false
static var pedal_brake_s := false
static var car_press_s := false

var _stick_index := NONE
var _stick_origin := Vector2.ZERO
var _look_index := NONE
var _jump_index := NONE
var _sprint_index := NONE
var _jump_pos := Vector2.ZERO
var _sprint_pos := Vector2.ZERO
var _font: Font = null
var _driving := false
var car_available := false
var car_occupied := false
var _car_index := NONE
var _car_pos := Vector2.ZERO
var _ui := 1.0
var _radius := BUTTON_RADIUS
var _stick_max := STICK_MAX


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_layout_buttons()


func _layout_buttons() -> void:
	var vs := get_viewport_rect().size
	_ui = clampf(vs.y / 640.0, 1.15, 2.6)
	_radius = BUTTON_RADIUS * _ui
	_stick_max = STICK_MAX * _ui
	_jump_pos = Vector2(vs.x - 86.0 * _ui, vs.y - 100.0 * _ui)
	_sprint_pos = Vector2(vs.x - 196.0 * _ui, vs.y - 64.0 * _ui)
	# Botao ENTRAR/SAIR do carro: acima dos pedais, no lado direito.
	_car_pos = Vector2(vs.x - 86.0 * _ui, vs.y - 240.0 * _ui)


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


## Pedal do acelerador (so existe enquanto o jogador esta dirigindo).
static func pedal_gas() -> bool:
	return pedal_gas_s


## Pedal do freio / marcha a re.
static func pedal_brake() -> bool:
	return pedal_brake_s


## Consome o toque no botao ENTRAR/SAIR do carro (o main le a cada quadro).
static func take_car_press() -> bool:
	var out := car_press_s
	car_press_s = false
	return out


## O main avisa se o carro esta ao alcance e se o jogador esta dirigindo.
## Este botao vive aqui, e nao no HUD, porque no iPhone o toque em Button do
## Godot nao chegava ao jogo (B-38) — ja o toque tratado pelo TouchControls,
## como o PULAR, sempre funcionou.
func set_car_state(near: bool, occupied: bool) -> void:
	if car_available == near and car_occupied == occupied:
		return
	car_available = near
	car_occupied = occupied
	if not near and not occupied:
		car_press_s = false
		_car_index = NONE
	queue_redraw()


# --- Direcao (o main chama ao entrar/sair do carro) --------------------------

func set_driving(on: bool) -> void:
	if _driving == on:
		return
	_driving = on
	# Solta tudo: trocar de contexto com um dedo pressionado nao pode deixar o
	# personagem pulando nem o carro acelerando sozinho.
	jump_held_s = false
	jump_pressed_s = false
	sprint_held_s = false
	pedal_gas_s = false
	pedal_brake_s = false
	_jump_index = NONE
	_sprint_index = NONE
	queue_redraw()


func is_driving() -> bool:
	return _driving


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
			pedal_gas_s = false
			queue_redraw()
		elif index == _sprint_index:
			_sprint_index = NONE
			sprint_held_s = false
			pedal_brake_s = false
			queue_redraw()
		elif index == _car_index:
			_car_index = NONE
			queue_redraw()
		return

	var vs := get_viewport_rect().size
	if pos.y < vs.y * TOP_UI:
		return  # faixa da interface

	if car_available and pos.distance_to(_car_pos) < _radius * 1.5:
		_car_index = index
		car_press_s = true
		queue_redraw()
		return

	if pos.distance_to(_jump_pos) < _radius * 1.5:
		_jump_index = index
		if _driving:
			pedal_gas_s = true
		else:
			jump_held_s = true
			jump_pressed_s = true
		queue_redraw()
		return
	if pos.distance_to(_sprint_pos) < _radius * 1.3:
		_sprint_index = index
		if _driving:
			pedal_brake_s = true
		else:
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
		stick_vec = d / maxf(1.0, _stick_max)
		queue_redraw()
	elif index == _look_index:
		look_delta += relative


# --- Desenho ------------------------------------------------------------------

func _draw() -> void:
	var vs := get_viewport_rect().size
	var hint := Vector2(110.0 * _ui, vs.y - 120.0 * _ui)
	if _stick_index != NONE:
		draw_circle(_stick_origin, _stick_max + 8.0 * _ui, Color(1, 1, 1, 0.07))
		draw_arc(_stick_origin, _stick_max, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0 * _ui)
		draw_circle(_stick_origin + stick_vec * _stick_max, 28.0 * _ui, Color(1, 1, 1, 0.42))
	else:
		draw_circle(hint, 62.0 * _ui, Color(1, 1, 1, 0.05))
		draw_circle(hint, 26.0 * _ui, Color(1, 1, 1, 0.12))

	if car_available:
		_draw_button(_car_pos, "SAIR" if car_occupied else "ENTRAR",
			Color(1.0, 0.78, 0.20, 0.60), car_press_s)

	if _driving:
		_draw_button(_jump_pos, "ACEL", Color(0.30, 0.72, 0.40, 0.55), pedal_gas_s)
		_draw_button(_sprint_pos, "FREIO", Color(0.90, 0.35, 0.30, 0.55), pedal_brake_s)
	else:
		_draw_button(_jump_pos, "PULAR", Color(0.95, 0.55, 0.25, 0.55), jump_held_s)
		_draw_button(_sprint_pos, "CORRER", Color(0.35, 0.62, 0.90, 0.50), sprint_held_s)


func _draw_button(center: Vector2, label: String, col: Color, active: bool) -> void:
	var c := col
	c.a = col.a + (0.25 if active else 0.0)
	draw_circle(center, _radius, c)
	draw_arc(center, _radius, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.0 * _ui)
	if _font == null:
		return
	var size := int(13.0 * _ui)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(_font, center + Vector2(-w * 0.5, 5.0 * _ui), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.95))
