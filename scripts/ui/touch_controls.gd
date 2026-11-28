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
static var fire_press_s := false
static var fire_held_s := false
static var weapon_press_s := false

var _stick_index := NONE
var _stick_origin := Vector2.ZERO
var _look_index := NONE
## Ultima posicao do dedo de olhar: o delta da camera e calculado por nos,
## de posicao em posicao do MESMO dedo (ver comentario em _drag).
var _look_last := Vector2.ZERO
var _jump_index := NONE
var _sprint_index := NONE
var _fire_index := NONE
var _weapon_index := NONE
var _jump_pos := Vector2.ZERO
var _sprint_pos := Vector2.ZERO
var _fire_pos := Vector2.ZERO
var _weapon_pos := Vector2.ZERO
## A arma equipada (o main avisa): o botao muda de BATER para ATIRAR.
var armed := false
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
	# Combate (so a pe): BATER/ATIRAR e TROCAR de arma.
	_fire_pos = Vector2(vs.x - 186.0 * _ui, vs.y - 176.0 * _ui)
	_weapon_pos = Vector2(vs.x - 292.0 * _ui, vs.y - 110.0 * _ui)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_layout_buttons()
		queue_redraw()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Na web, trocar de aba ou um gesto do sistema pode encerrar o toque sem
		# touchend nenhum: o dedo "preso" segurava o joystick e a camera para
		# sempre. Perder o foco solta tudo — o toque recomeca do zero.
		_stick_index = NONE
		_look_index = NONE
		stick_vec = Vector2.ZERO
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


## Consome o toque de BATER/ATIRAR.
static func take_fire_press() -> bool:
	var out := fire_press_s
	fire_press_s = false
	return out


## Dedo segurando o botao de fogo (tiro automatico enquanto segura).
static func fire_held() -> bool:
	return fire_held_s


## Consome o toque de TROCAR de arma.
static func take_weapon_press() -> bool:
	var out := weapon_press_s
	weapon_press_s = false
	return out


## O main avisa qual arma esta na mao (muda o rotulo do botao).
func set_armed(on: bool) -> void:
	if armed == on:
		return
	armed = on
	queue_redraw()


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
	fire_press_s = false
	fire_held_s = false
	weapon_press_s = false
	_jump_index = NONE
	_sprint_index = NONE
	_fire_index = NONE
	_weapon_index = NONE
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
		elif index == _fire_index:
			_fire_index = NONE
			fire_held_s = false
			queue_redraw()
		elif index == _weapon_index:
			_weapon_index = NONE
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

	# Combate a pe: BATER/ATIRAR e TROCAR. Lidos ANTES de PULAR/CORRER para um
	# dedo entre os dois nunca virar pulo por engano.
	if not _driving and pos.distance_to(_fire_pos) < _radius * 1.4:
		_fire_index = index
		fire_held_s = true
		fire_press_s = true
		queue_redraw()
		return
	if not _driving and pos.distance_to(_weapon_pos) < _radius * 1.3:
		_weapon_index = index
		weapon_press_s = true
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
	elif pos.x >= vs.x * 0.5 and _look_index == NONE:
		# A camera e so na metade direita. Um segundo toque na metade esquerda
		# (regrip do polegar no joystick, palma encostando na tela) nunca vira
		# olhar — era o que fazia a camera girar sozinha ao usar o analogico e
		# a camera ao mesmo tempo. Dedos alem de joystick + olhar sao ignorados.
		_look_index = index
		_look_last = pos


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _stick_index:
		var d := pos - _stick_origin
		# O clamp usa o raio DESENHADO (_stick_max), nao a constante: com o
		# raio escalado pelo iPhone o stick_vec travava em ~0.4-0.9 — andava
		# fraco e o botao do stick nunca chegava na borda do circulo.
		if d.length() > _stick_max:
			d = d.normalized() * _stick_max
			_stick_origin = pos - d
		stick_vec = d / maxf(1.0, _stick_max)
		queue_redraw()
	elif index == _look_index:
		# Delta calculado de posicao em posicao do MESMO dedo — e nao pelo
		# `relative` do evento. No build web o relative e reconstruido pelo
		# Godot a partir das posicoes que o navegador manda, e com DOIS dedos
		# na tela ele nao e confiavel (pode vir contra a posicao do OUTRO
		# dedo): a camera virava louca so quando anal e camera andavam juntos.
		# A posicao chega certa (os botoes funcionam por posicao), entao o
		# delta proprio e a leitura segura — um dedo ou dois, o valor e igual.
		look_delta += pos - _look_last
		_look_last = pos


# --- Desenho ------------------------------------------------------------------

func _draw() -> void:
	var vs := get_viewport_rect().size
	var hint := Vector2(110.0 * _ui, vs.y - 120.0 * _ui)
	if _stick_index != NONE:
		# Base do stick: disco + dois aneis, legivel contra qualquer piso.
		draw_circle(_stick_origin, _stick_max + 6.0 * _ui, Color(0, 0, 0, 0.20))
		draw_circle(_stick_origin, _stick_max, Color(0, 0, 0, 0.10))
		draw_arc(_stick_origin, _stick_max, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.0 * _ui)
		draw_arc(_stick_origin, _stick_max * 0.55, 0.0, TAU, 32, Color(1, 1, 1, 0.14), 2.0 * _ui)
		# Bola: sombra + vidro + filete + centro — o toque fica legivel.
		var knob := _stick_origin + stick_vec * _stick_max
		draw_circle(knob, 30.0 * _ui, Color(0, 0, 0, 0.18))
		draw_circle(knob, 28.0 * _ui, Color(0.92, 0.93, 0.95, 0.55))
		draw_arc(knob, 28.0 * _ui, 0.0, TAU, 32, Color(1, 1, 1, 0.80), 2.0 * _ui)
		draw_circle(knob + Vector2(-8.0 * _ui, -8.0 * _ui), 9.0 * _ui, Color(1, 1, 1, 0.50))
	else:
		# Base sempre visivel, com um convite que respira devagar.
		var t := float(Time.get_ticks_msec()) / 1000.0
		var breathe := 0.05 + 0.03 * (0.5 + 0.5 * sin(t * 1.8))
		draw_circle(hint, 64.0 * _ui, Color(0, 0, 0, 0.18))
		draw_arc(hint, 60.0 * _ui, 0.0, TAU, 40, Color(1, 1, 1, breathe + 0.12), 2.0 * _ui)
		draw_circle(hint, 22.0 * _ui, Color(1, 1, 1, breathe + 0.08))

	if car_available:
		var car_col := Color(1.0, 0.78, 0.20, 0.60)
		if not car_occupied:
			# O ENTRAR respira: e o unico convite do mundo que muda de lugar,
			# e o olho precisa ser puxado para ele sem piscar na cara.
			var t := float(Time.get_ticks_msec()) / 1000.0
			car_col.a = 0.45 + 0.25 * (0.5 + 0.5 * sin(t * 3.0))
		# Acao contextual como o "Drive"/"Get in" do PUBG: pílula com borda de
		# acento, nao mais um disco de acao.
		_draw_pill(_car_pos, "SAIR" if car_occupied else "ENTRAR",
			car_col, car_press_s)

	if _driving:
		_draw_button(_jump_pos, "ACEL", Color(0.30, 0.72, 0.40, 0.55), pedal_gas_s)
		_draw_button(_sprint_pos, "FREIO", Color(0.90, 0.35, 0.30, 0.55), pedal_brake_s)
	else:
		_draw_button(_jump_pos, "PULAR", Color(0.95, 0.55, 0.25, 0.55), jump_held_s)
		_draw_button(_sprint_pos, "CORRER", Color(0.35, 0.62, 0.90, 0.50), sprint_held_s)
		_draw_button(_fire_pos, "ATIRAR" if armed else "BATER",
			Color(0.95, 0.32, 0.28, 0.55), fire_held_s)
		_draw_button(_weapon_pos, "TROCAR", Color(0.62, 0.62, 0.68, 0.42), false)


## Poligono fechado de retangulo com cantos arredondados (o idioma das píluas
## de ação contextual do PUBG). Pontos em sentido horario.
static func _rounded_points(r: Rect2, radius: float, segments: int = 6) -> PackedVector2Array:
	var rad := clampf(radius, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	if rad <= 0.01:
		pts.append(r.position)
		pts.append(r.position + Vector2(r.size.x, 0.0))
		pts.append(r.position + r.size)
		pts.append(r.position + Vector2(0.0, r.size.y))
		return pts
	var centers: Array[Vector2] = [
		r.position + Vector2(r.size.x - rad, rad),
		r.position + Vector2(r.size.x - rad, r.size.y - rad),
		r.position + Vector2(rad, r.size.y - rad),
		r.position + Vector2(rad, rad),
	]
	var starts: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for i in 4:
		for s in segments + 1:
			var a := starts[i] + PI * 0.5 * float(s) / float(segments)
			pts.append(centers[i] + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw_button(center: Vector2, label: String, col: Color, active: bool) -> void:
	var r := _radius
	# Halo escuro sempre: e ele que faz o botao ler contra ceu claro e asfalto
	# (o padrao comum das referencias: o interior nunca decide a leitura sozinho).
	draw_circle(center, r * 1.16, Color(0, 0, 0, 0.26))
	# No toque, um halo NA COR da acao — o destaque que o PUBG da ao selecionar.
	if active:
		draw_circle(center, r * 1.24, Color(col.r, col.g, col.b, 0.16))
	# Interior escuro translucido (25-45% no PUBG): o jogo aparece por tras.
	# A cor da acao entra como uma tinta leve; no toque ela sobe.
	var fill := Color(0.06, 0.07, 0.09, 0.42 + (0.14 if active else 0.0))
	var tint := 0.22 if active else 0.14
	fill.r = lerp(fill.r, col.r, tint)
	fill.g = lerp(fill.g, col.g, tint)
	fill.b = lerp(fill.b, col.b, tint)
	draw_circle(center, r * (0.95 if active else 1.0), fill)
	# Meia-lua de vidro no topo: relevo sem custo de pixel.
	draw_circle(center + Vector2(0.0, -r * 0.26), r * 0.55, Color(1, 1, 1, 0.10))
	# ARO fino quase branco (o idioma comum) com UM acento da cor da acao;
	# no toque ele acende, engrossa e o disco encolhe um tico (afunda).
	var ring := Color(
		lerp(0.86, col.r, 0.35 if active else 0.20),
		lerp(0.87, col.g, 0.35 if active else 0.20),
		lerp(0.89, col.b, 0.35 if active else 0.20),
		0.90 if active else 0.55)
	draw_arc(center, r * (0.94 if active else 1.0), 0.0, TAU, 40, ring, maxf(2.0, 2.4 * _ui))
	_draw_label(center, label, 14.0)


## Acao contextual (ENTRAR/SAIR) como as píluas "Drive"/"Get in" do PUBG:
## retangulo translucido de cantos redondos, borda fina na cor de acento,
## rotulo branco com sombra. Nada de disco aqui — e um convite, nao um pedais.
func _draw_pill(center: Vector2, label: String, col: Color, active: bool) -> void:
	var pad := 10.0 * _ui
	var size := int(14.0 * _ui)
	var tw := 0.0
	if _font != null:
		tw = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	var w := maxf(_radius * 1.8, tw + pad * 2.0)
	var h := _radius * 1.05
	var rect := Rect2(center - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_colored_polygon(_rounded_points(rect.grow(3.0 * _ui), h * 0.5), Color(0, 0, 0, 0.30))
	var fill := Color(0.06, 0.07, 0.09, 0.55 + (0.15 if active else 0.0))
	if active:
		fill.r = lerp(fill.r, col.r, 0.30)
		fill.g = lerp(fill.g, col.g, 0.30)
		fill.b = lerp(fill.b, col.b, 0.30)
	var pts := _rounded_points(rect, h * 0.45)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, col, maxf(2.0, 2.4 * _ui))
	_draw_label(center, label, 14.0)


## Rotulo branco com sombra desenhada por baixo (o fallback de fonte nao tem
## outline de tema): le sobre ceu, asfalto e areia.
func _draw_label(center: Vector2, label: String, font_size: float) -> void:
	if _font == null:
		return
	var size := int(font_size * _ui)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	var tp := center + Vector2(-w * 0.5, size * 0.38)
	draw_string(_font, tp + Vector2(0.0, 1.5 * _ui), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.70))
	draw_string(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.98))
