class_name ArmyView
extends MultiMeshInstance3D
## army.gd의 병력 수를 MultiMesh로 그린다. 계산 결과를 그리기만 한다.
## 표시 대형은 계산 대형보다 넓게 펼치되, 앞줄(교전이 일어나는 면)은 계산 위치에 맞춘다.
## 표시 대형의 폭은 도로 폭의 일정 비율을 넘지 않고, 넘는 인원은 뒤쪽으로 길게 세운다.
## 병사가 줄면 빠진 병사를 짧게 작아지며 사라지게 한다. 적 무리는 뒤쪽 위로 튕겨 날아가게 할 수 있다.

# 해바라기 배치용 황금각(라디안)
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))
# 병사마다 흔들림 박자를 어긋나게 하는 비율(황금비의 소수 부분)
const PHASE_STEP := 0.618034

var _army: Army
var _units: Dictionary
var _visual: Dictionary
var _display_limit: int
var _calc_spacing: float
var _road_width: float
var _max_width_ratio: float
# 앞줄 방향. 아군은 -1(-Z가 전방), 적은 +1(아군 쪽)
var _facing := -1.0
# 0 이상이면 앞줄을 이 계산 반지름에 고정한다(적 무리는 처음 앞줄에서 움직이지 않는다)
var _fixed_front := -1.0
var _death_time: float
var _mesh_cache: Dictionary = {}
var _material: ShaderMaterial
var _base_color: Color
var _brightness := 0.0
var _unit_type := ""
var _alive_transforms: Array[Transform3D] = []
# 표시 대형 중심의 앞뒤 위치(노드 기준)
var _center_z := 0.0
# 사라지는 병사: {"transform": 원래 변환, "t": 지난 시간}. 날아가는 병사는 "velocity", "axis", "spin"이 더 있다
var _dying: Array[Dictionary] = []
# 죽은 병사를 날려 보내는 설정(visual.json의 soldier.death_fly). 비어 있으면 제자리에서 작아진다
var _death_fly := {}


func setup(army: Army, units: Dictionary, tuning: Dictionary, visual: Dictionary, color: Color, facing: float, bob_height: float, fixed_front_radius := -1.0) -> void:
	_army = army
	_units = units
	_visual = visual
	_display_limit = int(tuning["soldier_display_limit"])
	_calc_spacing = float(tuning["formation"]["spacing"])
	_road_width = float(tuning["road"]["width"])
	_max_width_ratio = float(tuning["formation_max_width_ratio"])
	_facing = facing
	_fixed_front = fixed_front_radius
	_death_time = float(visual["soldier"]["death_time"])

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	# Compatibility 렌더러는 인스턴스 색이 없으면 꼭짓점 색이 어둡게 나온다. 흰색을 넣어 영향이 없게 한다
	multimesh.use_colors = true

	_base_color = color
	_material = ModelBuilder.make_material(color, bob_height, float(visual["soldier"]["bob_speed"]))
	material_override = _material

	_army.changed.connect(_rebuild)
	_rebuild()


## 병력 수에 따른 계산 대형의 반지름. 교전 거리 계산에 쓴다.
static func formation_radius(count: int, spacing: float) -> float:
	return spacing * sqrt(maxi(count, 1))


## 표시 대형의 간격. 병력이 적을 때는 넓게, 많을 때는 촘촘하게 펼친다.
static func display_spacing(count: int, visual: Dictionary) -> float:
	var data: Dictionary = visual["formation"]
	var t := inverse_lerp(float(data["count_small"]), float(data["count_large"]), float(count))
	return lerpf(float(data["spacing_small"]), float(data["spacing_large"]), clampf(t, 0.0, 1.0))


## 폭 제한 전의 표시 대형 반지름. 카메라 거리에 쓴다.
static func display_radius(count: int, visual: Dictionary, display_limit: int) -> float:
	var shown := clampi(count, 1, display_limit)
	return display_spacing(shown, visual) * sqrt(shown)


## 표시 대형의 반폭(x)과 앞뒤 반길이(y). 반지름이 폭 제한을 넘으면 넓이를 유지한 채 앞뒤로 늘인 타원이 된다.
static func display_extent(count: int, visual: Dictionary, display_limit: int, road_width: float, max_width_ratio: float) -> Vector2:
	var radius := display_radius(count, visual, display_limit)
	var max_half := road_width * max_width_ratio / 2.0
	if radius <= max_half:
		return Vector2(radius, radius)
	return Vector2(max_half, radius * radius / max_half)


## 표시 대형 중심의 월드 좌표(보스 이름을 머리 위에 붙일 때 쓴다)
func display_center() -> Vector3:
	return global_position + Vector3(0.0, 0.0, _center_z)


## 표시 대형의 최대 폭 비율을 바꾼다(보스 구간에서 좁힌다).
func set_max_width_ratio(ratio: float) -> void:
	if is_equal_approx(ratio, _max_width_ratio):
		return
	_max_width_ratio = ratio
	_rebuild()


## 죽은 병사가 뒤쪽 위로 튕겨 날아가게 한다. 표시만 바뀌고 계산과는 무관하다.
func set_death_fly(data: Dictionary) -> void:
	_death_fly = data
	_death_time = float(data["time"])


## 달릴 때의 위아래 흔들림 높이를 바꾼다(적 무리가 서 있다가 달려올 때).
func set_bob(height: float) -> void:
	_material.set_shader_parameter("bob_height", height)


## 계열 효과 같은 상태 변화로 병사 색을 바꾼다. 밝기 보정은 유지한다.
func set_color(color: Color) -> void:
	_base_color = color
	_apply_color()


## 기본 색은 그대로 두고 밝기만 올린다. 0이면 원래 색이다.
func set_brightness(amount: float) -> void:
	_brightness = amount
	_apply_color()


## 앞줄의 표시 반지름이 아니라 계산 반지름(앞줄 위치)
func front_offset() -> float:
	return _front_radius()


func _apply_color() -> void:
	_material.set_shader_parameter("team_color", _base_color.lightened(_brightness))


func _front_radius() -> float:
	if _fixed_front >= 0.0:
		return _fixed_front
	return formation_radius(_army.count, _calc_spacing)


func _rebuild() -> void:
	if _army.unit_type != _unit_type:
		_unit_type = _army.unit_type
		multimesh.instance_count = 0
		multimesh.mesh = _get_mesh(_unit_type)
		multimesh.instance_count = _display_limit * 2
		_dying.clear()
		_alive_transforms.clear()

	var shown := mini(_army.count, _display_limit)
	# 줄어든 만큼 바깥쪽 병사를 사라지는 목록으로 옮긴다
	for i in range(shown, _alive_transforms.size()):
		var entry := {"transform": _alive_transforms[i], "t": 0.0}
		if not _death_fly.is_empty():
			# 보는 방향의 반대쪽(맞은 방향)으로, 위로, 조금씩 다른 세기로 튕긴다
			var back: Array = _death_fly["back_speed"]
			var up: Array = _death_fly["up_speed"]
			var spin: Array = _death_fly["spin_speed"]
			var side := float(_death_fly["side_speed"])
			entry["velocity"] = Vector3(randf_range(-side, side), randf_range(float(up[0]), float(up[1])), -_facing * randf_range(float(back[0]), float(back[1])))
			entry["axis"] = Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0)).normalized()
			entry["spin"] = randf_range(float(spin[0]), float(spin[1]))
		_dying.append(entry)
	while _dying.size() > _display_limit:
		_dying.pop_front()

	# 표시 대형의 앞줄을 계산 대형의 앞줄에 맞춘다
	var spacing := display_spacing(shown, _visual)
	var display_r := spacing * sqrt(maxi(shown, 1))
	var extent := display_extent(shown, _visual, _display_limit, _road_width, _max_width_ratio)
	# 원형 배치를 좌우로 줄이고 앞뒤로 늘여 폭 제한 안에 넣는다(넓이는 같다)
	var squeeze := Vector2(extent.x / display_r, extent.y / display_r)
	var center_z := _facing * (_front_radius() - extent.y)
	# 몸집이 큰 항목(보스)은 모델 앞면을 계산 앞줄에 맞춘다(크게 그려도 교전 거리가 어긋나 보이지 않게)
	if _units[_unit_type].has("body_radius"):
		var front_extent := -multimesh.mesh.get_aabb().position.z * model_scale(_unit_type, _visual)
		center_z = _facing * (_front_radius() - front_extent)
	_center_z = center_z
	_alive_transforms.resize(shown)
	for i in shown:
		var radius := spacing * sqrt(i + 0.5)
		var angle := i * GOLDEN_ANGLE
		var offset := Vector3(cos(angle) * radius * squeeze.x, 0.0, center_z + sin(angle) * radius * squeeze.y)
		_alive_transforms[i] = Transform3D(_facing_basis().scaled(Vector3.ONE * model_scale(_unit_type, _visual)), offset)
		multimesh.set_instance_transform(i, _alive_transforms[i])
		multimesh.set_instance_custom_data(i, Color(fposmod(i * PHASE_STEP, 1.0), 0.0, 0.0, 0.0))
		multimesh.set_instance_color(i, Color.WHITE)
	_write_dying()


func _process(delta: float) -> void:
	if _dying.is_empty():
		return
	for entry in _dying:
		entry["t"] = float(entry["t"]) + delta
	_dying = _dying.filter(func(entry: Dictionary) -> bool: return float(entry["t"]) < _death_time)
	_write_dying()


## 사라지는 병사를 살아 있는 병사 뒤 칸에 작아지는 크기로 쓴다.
func _write_dying() -> void:
	var start := _alive_transforms.size()
	for k in _dying.size():
		var entry: Dictionary = _dying[k]
		var t := float(entry["t"])
		var shrink := clampf(1.0 - t / _death_time, 0.0, 1.0)
		var transform: Transform3D = entry["transform"]
		if entry.has("velocity"):
			# 포물선으로 날아가며 돌고, 끝날 무렵에만 작아진다
			var velocity: Vector3 = entry["velocity"]
			transform.origin += velocity * t + Vector3.DOWN * (float(_death_fly["gravity"]) * t * t / 2.0)
			transform.origin.y = maxf(transform.origin.y, 0.0)
			transform.basis = Basis(entry["axis"] as Vector3, float(entry["spin"]) * t) * transform.basis
			var shrink_start := float(_death_fly["shrink_start"])
			shrink = clampf((1.0 - t / _death_time) / (1.0 - shrink_start), 0.0, 1.0)
		transform.basis = transform.basis.scaled(Vector3.ONE * maxf(shrink, 0.001))
		multimesh.set_instance_transform(start + k, transform)
		multimesh.set_instance_custom_data(start + k, Color(fposmod((start + k) * PHASE_STEP, 1.0), 0.0, 0.0, 0.0))
		multimesh.set_instance_color(start + k, Color.WHITE)
	multimesh.visible_instance_count = start + _dying.size()


## 모델은 -Z를 앞으로 만든다. 적은 아군 쪽(+Z)을 보도록 돌린다.
## 모델 표시 배율(보스처럼 크게 보일 항목). 없으면 1
static func model_scale(unit_type: String, visual: Dictionary) -> float:
	return float(visual["model_scale"].get(unit_type, 1.0))


func _facing_basis() -> Basis:
	return Basis.IDENTITY if _facing < 0.0 else Basis(Vector3.UP, PI)


func _get_mesh(unit_type: String) -> Mesh:
	if not _mesh_cache.has(unit_type):
		_mesh_cache[unit_type] = ModelBuilder.model(unit_type, _visual)
	return _mesh_cache[unit_type]
