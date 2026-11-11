class_name ArmyView
extends MultiMeshInstance3D
## army.gd의 병력 수를 MultiMesh로 그린다. 계산 결과를 그리기만 한다.

# 해바라기 배치용 황금각(라디안)
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))

var _army: Army
var _units: Dictionary
var _display_limit: int
var _spacing: float
var _mesh_cache: Dictionary = {}
var _base_color: Color
var _brightness := 0.0


func setup(army: Army, units: Dictionary, tuning: Dictionary, color: Color) -> void:
	_army = army
	_units = units
	_display_limit = int(tuning["soldier_display_limit"])
	_spacing = float(tuning["formation"]["spacing"])

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D

	_base_color = color
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material_override = material

	_army.changed.connect(_rebuild)
	_rebuild()


## 병력 수에 따른 원형 대형의 반지름. 앞줄 위치 계산에 쓴다.
static func formation_radius(count: int, spacing: float) -> float:
	return spacing * sqrt(maxi(count, 1))


## 계열 효과 같은 상태 변화로 병사 색을 바꾼다. 밝기 보정은 유지한다.
func set_color(color: Color) -> void:
	_base_color = color
	_apply_color()


## 기본 색은 그대로 두고 밝기만 올린다. 0이면 원래 색이다.
func set_brightness(amount: float) -> void:
	_brightness = amount
	_apply_color()


func _apply_color() -> void:
	(material_override as StandardMaterial3D).albedo_color = _base_color.lightened(_brightness)


func _rebuild() -> void:
	var mesh_data: Dictionary = _units[_army.unit_type]["mesh"]
	multimesh.mesh = _get_mesh(_army.unit_type, mesh_data)

	# 표시 상한을 넘으면 상한만큼만 그린다
	var shown := mini(_army.count, _display_limit)
	multimesh.instance_count = shown

	var half_height := _mesh_height(mesh_data) / 2.0
	for i in shown:
		# 중심에서 바깥으로 퍼지는 원형 대형
		var radius := _spacing * sqrt(i + 0.5)
		var angle := i * GOLDEN_ANGLE
		var offset := Vector3(cos(angle) * radius, half_height, sin(angle) * radius)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, offset))


func _get_mesh(unit_type: String, mesh_data: Dictionary) -> Mesh:
	if _mesh_cache.has(unit_type):
		return _mesh_cache[unit_type]

	var mesh: Mesh
	match mesh_data["shape"]:
		"box":
			var box := BoxMesh.new()
			box.size = _to_vector3(mesh_data["size"])
			mesh = box
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(mesh_data["radius"])
			cylinder.bottom_radius = float(mesh_data["radius"])
			cylinder.height = float(mesh_data["height"])
			cylinder.radial_segments = int(mesh_data["radial_segments"])
			mesh = cylinder
		_:
			push_error("알 수 없는 병사 도형: " + str(mesh_data["shape"]))
			mesh = BoxMesh.new()

	_mesh_cache[unit_type] = mesh
	return mesh


func _mesh_height(mesh_data: Dictionary) -> float:
	if mesh_data["shape"] == "box":
		return float(mesh_data["size"][1])
	return float(mesh_data.get("height", 0.0))


func _to_vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
