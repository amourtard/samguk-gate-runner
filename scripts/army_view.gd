class_name ArmyView
extends MultiMeshInstance3D
## army.gd의 병력 수를 MultiMesh로 그린다. 계산 결과를 그리기만 한다.
## 표시 대형은 계산 대형보다 넓게 펼치되, 앞줄(교전이 일어나는 면)은 계산 위치에 맞춘다.
## 표시 대형의 폭은 도로 폭의 일정 비율을 넘지 않고, 넘는 인원은 뒤쪽으로 길게 세운다.
## 병사가 줄면 빠진 병사를 짧게 작아지며 사라지게 한다.

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
# 사라지는 병사: {"transform": 원래 변환, "t": 지난 시간}
var _dying: Array[Dictionary] = []


func setup(army: Army, units: Dictionary, tuning: Dictionary, visual: Dictionary, color: Color, facing: float, bob_height: float, fixed_front_radius := -1.0) -> void:
	_army = army
	_units = units
	_visual = visual
	_display_limit = int(tuning["soldier_display_limit"])
	_calc_spacing = float(tuning["formation"]["spacing"])
	_road_width = float(tuning["road"]["width"])
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
static func display_extent(count: int, visual: Dictionary, display_limit: int, road_width: float) -> Vector2:
	var radius := display_radius(count, visual, display_limit)
	var max_half := road_width * float(visual["formation"]["max_width_road_ratio"]) / 2.0
	if radius <= max_half:
		return Vector2(radius, radius)
	return Vector2(max_half, radius * radius / max_half)


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
		_dying.append({"transform": _alive_transforms[i], "t": 0.0})
	while _dying.size() > _display_limit:
		_dying.pop_front()

	# 표시 대형의 앞줄을 계산 대형의 앞줄에 맞춘다
	var spacing := display_spacing(shown, _visual)
	var display_r := spacing * sqrt(maxi(shown, 1))
	var extent := display_extent(shown, _visual, _display_limit, _road_width)
	# 원형 배치를 좌우로 줄이고 앞뒤로 늘여 폭 제한 안에 넣는다(넓이는 같다)
	var squeeze := Vector2(extent.x / display_r, extent.y / display_r)
	var center_z := _facing * (_front_radius() - extent.y)
	# 모델이 없는 큰 도형(보스)은 계산 위치 그대로 둔다
	if not _visual["models"].has(_unit_type):
		center_z = 0.0
	_alive_transforms.resize(shown)
	for i in shown:
		var radius := spacing * sqrt(i + 0.5)
		var angle := i * GOLDEN_ANGLE
		var offset := Vector3(cos(angle) * radius * squeeze.x, 0.0, center_z + sin(angle) * radius * squeeze.y)
		_alive_transforms[i] = Transform3D(_facing_basis(), offset)
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
		var shrink := clampf(1.0 - float(entry["t"]) / _death_time, 0.0, 1.0)
		var transform: Transform3D = entry["transform"]
		transform.basis = transform.basis.scaled(Vector3.ONE * maxf(shrink, 0.001))
		multimesh.set_instance_transform(start + k, transform)
		multimesh.set_instance_custom_data(start + k, Color(fposmod((start + k) * PHASE_STEP, 1.0), 0.0, 0.0, 0.0))
		multimesh.set_instance_color(start + k, Color.WHITE)
	multimesh.visible_instance_count = start + _dying.size()


## 모델은 -Z를 앞으로 만든다. 적은 아군 쪽(+Z)을 보도록 돌린다.
func _facing_basis() -> Basis:
	return Basis.IDENTITY if _facing < 0.0 else Basis(Vector3.UP, PI)


func _get_mesh(unit_type: String) -> Mesh:
	if _mesh_cache.has(unit_type):
		return _mesh_cache[unit_type]
	var mesh: Mesh
	if _visual["models"].has(unit_type):
		mesh = ModelBuilder.build(_visual["models"][unit_type])
	else:
		# 모델이 없는 항목(보스)은 데이터의 기본 도형을 발이 바닥에 닿게 쓴다
		mesh = _fallback_mesh(_units[unit_type]["mesh"])
	_mesh_cache[unit_type] = mesh
	return mesh


func _fallback_mesh(mesh_data: Dictionary) -> Mesh:
	var part := {"shape": mesh_data["shape"], "team": 1.0}
	var height := 0.0
	if mesh_data["shape"] == "box":
		part["size"] = mesh_data["size"]
		height = float(mesh_data["size"][1])
	else:
		part["top"] = mesh_data["radius"]
		part["bottom"] = mesh_data["radius"]
		part["height"] = mesh_data["height"]
		part["segments"] = mesh_data.get("radial_segments", 8)
		height = float(mesh_data["height"])
	part["pos"] = [0, height / 2.0, 0]
	return ModelBuilder.build([part])
