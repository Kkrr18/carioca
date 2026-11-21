extends Node3D
## MissionRunner: executa o roteiro de missions.gd no mundo (a parte de cena).
##
## - Parado, mostra o marcador amarelo no ponto onde a proxima missao comeca.
##   O jogador entra no marcador e a missao comeca (no iPhone, tocar em marcador
##   e pior do que simplesmente dirigir ate ele).
## - Cada passo e "goto" (chegar), "say" (fala com tempo), "wait" e "survive".
##   A regra de quando avancar mora AQUI; o TEXTO e os numeros vem do missions.gd.
## - O marcador e 1 cilindro translucido + 1 anel no chao: dois desenhos.

signal started(title: String)
signal objective_changed(text: String)
signal finished(title: String, reward: int)

const Cfg = preload("res://scripts/core/cfg.gd")
const Missions = preload("res://scripts/game/missions.gd")

const START_RADIUS := 13.0
const MARK_RADIUS := 1.9
const MARK_HEIGHT := 9.0
const MARK_COL := Color(1.00, 0.82, 0.18)

var player = null
var police = null
var hud = null

var active := false
var mission_index := 0
var mission_title := ""
var objective := ""
var has_target := false
var target_pos := Vector3.ZERO
var step_index := 0
var reward_last := 0

var _mission: Dictionary = {}
var _timer := 0.0
var _radius := 18.0
var _mark: MeshInstance3D
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _pulse := 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = MARK_COL
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(MARK_COL.r, MARK_COL.g, MARK_COL.b, 0.30)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var cyl := CylinderMesh.new()
	cyl.top_radius = MARK_RADIUS
	cyl.bottom_radius = MARK_RADIUS
	cyl.height = MARK_HEIGHT
	cyl.radial_segments = 14
	_mark = MeshInstance3D.new()
	_mark.name = "MissionMark"
	_mark.mesh = cyl
	_mark.material_override = _mat
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mark)

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = MARK_RADIUS * 1.25
	ring_mesh.bottom_radius = MARK_RADIUS * 1.25
	ring_mesh.height = 0.12
	ring_mesh.radial_segments = 18
	_ring = MeshInstance3D.new()
	_ring.name = "MissionRing"
	_ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.92, 0.35)
	ring_mat.emission_enabled = true
	ring_mat.emission = MARK_COL
	ring_mat.emission_energy_multiplier = 1.4
	_ring.material_override = ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_show_giver()


func _mission_now() -> Dictionary:
	return Missions.mission_at(mission_index)


## Marcador parado no ponto onde a proxima missao comeca.
func _show_giver() -> void:
	var m := _mission_now()
	if m.is_empty():
		_mark.visible = false
		_ring.visible = false
		return
	var p := Missions.giver_pos(m)
	_place(p)
	has_target = true
	target_pos = p
	_radius = START_RADIUS


func _place(p: Vector3) -> void:
	_mark.visible = true
	_ring.visible = true
	_mark.global_position = Vector3(p.x, p.y + MARK_HEIGHT * 0.5 - 0.4, p.z)
	_ring.global_position = Vector3(p.x, p.y + 0.06, p.z)


func start_mission() -> void:
	if active:
		return
	_mission = _mission_now()
	if _mission.is_empty():
		return
	active = true
	step_index = 0
	_timer = 0.0
	mission_title = Missions.title_of(_mission)
	reward_last = Missions.reward_of(_mission)
	started.emit(mission_title)
	if hud != null:
		hud.banner(mission_title, 2.6)
	_enter_step(0)


func abort() -> void:
	active = false
	objective = ""
	has_target = false
	_step_hidden()
	_show_giver()


func _step_hidden() -> void:
	_passive()
	_mark.visible = false
	_ring.visible = false


func _passive() -> void:
	has_target = false
	_radius = 18.0


## Entra no passo `i`: arma o alvo/tempo e manda o texto para o HUD.
func _enter_step(i: int) -> void:
	step_index = i
	var step := Missions.step_at(_mission, i)
	if step.is_empty():
		_finish()
		return
	objective = Missions.objective_text(_mission, i)
	objective_changed.emit(objective)
	var heat := Missions.step_heat(step)
	if heat > 0.0 and police != null and police.has_method("raise_heat"):
		police.raise_heat(heat)
	var kind := Missions.step_kind(step)
	match kind:
		"goto":
			var p := Missions.step_pos(step)
			target_pos = p
			has_target = true
			_radius = Missions.step_radius(step)
			_place(p)
		"say":
			_passive()
			_mark.visible = false
			_ring.visible = false
			_timer = Missions.step_seconds(step)
			if hud != null:
				hud.say(String(step.get("who", "")), String(step.get("text", "")), _timer)
		_:
			_passive()
			_mark.visible = false
			_ring.visible = false
			_timer = Missions.step_seconds(step)


func _advance() -> void:
	if not active:
		return
	_enter_step(step_index + 1)


func _finish() -> void:
	active = false
	has_target = false
	objective = ""
	_mark.visible = false
	_ring.visible = false
	var title := mission_title
	var reward := reward_last
	mission_index = (mission_index + 1) % maxi(1, Missions.count())
	_show_giver()
	finished.emit(title, reward)


func update(delta: float, focus: Vector3) -> void:
	_pulse += delta
	if _mark.visible:
		# Pulsar barato: so a escala do marcador, nenhum material novo.
		var s := 1.0 + sin(_pulse * 3.4) * 0.06
		_mark.scale = Vector3(s, 1.0, s)
		_mat.albedo_color = Color(MARK_COL.r, MARK_COL.g, MARK_COL.b,
				0.20 + 0.12 * (0.5 + 0.5 * sin(_pulse * 3.4)))
	if not active:
		if not _mission_now().is_empty():
			var g := Missions.giver_pos(_mission_now())
			if Vector2(g.x - focus.x, g.z - focus.z).length() <= START_RADIUS:
				start_mission()
		return
	if has_target:
		if Vector2(target_pos.x - focus.x, target_pos.z - focus.z).length() <= _radius:
			_advance()
		return
	_timer -= delta
	if _timer <= 0.0:
		_advance()


func describe() -> String:
	if active:
		return "missao: %s - passo %d (%s)" % [mission_title, step_index, objective]
	return "missao: aguardando (%s)" % Missions.title_of(_mission_now())
