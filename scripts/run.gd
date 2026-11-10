extends Node3D
## 한 판의 진행. 전진, 좌우 드래그 이동, 카메라 추종을 맡는다.

# 단계 1 확인용 병력 증감 키
const DEBUG_ADD_KEY := KEY_UP
const DEBUG_SUB_KEY := KEY_DOWN

@onready var _road_view: Node3D = $RoadView
@onready var _army_view: MultiMeshInstance3D = $ArmyView
@onready var _camera: Camera3D = $Camera3D

var army: Army

var _tuning: Dictionary
var _army_position := Vector3.ZERO
var _target_x := 0.0
var _lateral_limit: float
var _camera_offset: Vector3
var _camera_look_ahead: float


func _ready() -> void:
	_tuning = DataDb.table("tuning")
	var units := DataDb.table("units")
	var debug: Dictionary = _tuning["debug"]
	var unit_type: String = debug["start_unit"]

	army = Army.new(unit_type, float(units[unit_type]["health"]), int(debug["start_count"]))
	_army_view.setup(army, units, _tuning, Color.html(_tuning["colors"]["ally"]))
	_road_view.setup(_tuning)

	_lateral_limit = float(_tuning["road"]["lateral_limit"])

	# 아군 뒤쪽 위에서 지정 각도로 내려다본다
	var camera_data: Dictionary = _tuning["camera"]
	var pitch := deg_to_rad(float(camera_data["pitch_deg"]))
	var distance := float(camera_data["distance"])
	_camera_offset = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	_camera_look_ahead = float(camera_data["look_ahead"])
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = float(camera_data["fov"])
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		# 화면 폭 대비 드래그 거리만큼 목표 위치를 옮긴다 (상대 이동)
		var screen_width := get_viewport().get_visible_rect().size.x
		var meters_per_width := float(_tuning["input"]["drag_meters_per_screen_width"])
		_target_x = clampf(_target_x + event.relative.x / screen_width * meters_per_width, -_lateral_limit, _lateral_limit)
	elif event is InputEventKey and event.pressed and not event.echo:
		var step := int(_tuning["debug"]["count_step"])
		if event.keycode == DEBUG_ADD_KEY:
			army.set_count(army.count + step)
			print("병력: ", army.count)
		elif event.keycode == DEBUG_SUB_KEY:
			army.set_count(army.count - step)
			print("병력: ", army.count)


func _process(delta: float) -> void:
	_army_position.z -= float(_tuning["advance_speed"]) * delta
	_army_position.x = move_toward(_army_position.x, _target_x, float(_tuning["lateral_max_speed"]) * delta)
	_army_view.position = _army_position
	_road_view.follow(_army_position.z)
	_update_camera()


func _update_camera() -> void:
	# 좌우는 따라가지 않고 전진 방향만 따라가 도로가 화면 중앙에 머물게 한다
	var target := Vector3(0.0, 0.0, _army_position.z - _camera_look_ahead)
	_camera.position = target + _camera_offset
	_camera.look_at(target)
