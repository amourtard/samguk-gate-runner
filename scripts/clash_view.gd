class_name ClashView
extends MultiMeshInstance3D
## 근접 충돌 지점의 짧은 번쩍임. 교전 계산과 무관한 연출이다.
## 근접 교전 중 계산 간격마다 접촉선 위 무작위 지점에 몇 개씩 띄우고, 화면 전체 개수는 상한을 넘지 않는다.

var _per_tick: int
var _life: float
var _size: float
var _stretch: float
var _max_count: int
var _height_min: float
var _height_max: float
var _depth: float
# 번쩍임. 각 항목은 {"pos": 위치, "basis": 방향, "t": 지난 시간}
var _flashes: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func setup(visual: Dictionary) -> void:
	var data: Dictionary = visual["clash"]
	_per_tick = int(data["per_tick"])
	_life = float(data["life"])
	_size = float(data["size"])
	_stretch = float(data["stretch"])
	_max_count = int(data["max_count"])
	_height_min = float(data["height_min"])
	_height_max = float(data["height_max"])
	_depth = float(data["depth"])
	_rng.seed = randi()

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	# 꼭짓점 넷짜리 마름모를 한 축으로 늘이고 무작위로 돌려 불꽃처럼 보이게 한다
	sphere.radial_segments = 4
	sphere.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(data["color"])
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sphere
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 접촉선(가운데 center, 좌우 반폭 half_width) 위에 번쩍임을 더한다. 상한을 넘으면 더하지 않는다.
func spawn(center: Vector3, half_width: float) -> void:
	for i in _per_tick:
		if _flashes.size() >= _max_count:
			return
		var offset := Vector3(_rng.randf_range(-half_width, half_width), _rng.randf_range(_height_min, _height_max), _rng.randf_range(-_depth, _depth))
		var axis := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		var basis := Basis(axis.normalized() if axis.length() > 0.01 else Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(1.0, _stretch, 1.0))
		_flashes.append({"pos": center + offset, "basis": basis, "t": 0.0})


func _process(delta: float) -> void:
	for flash in _flashes:
		flash["t"] = float(flash["t"]) + delta
	_flashes = _flashes.filter(func(flash: Dictionary) -> bool: return float(flash["t"]) < _life)
	multimesh.instance_count = _flashes.size()
	for i in _flashes.size():
		# 빠르게 커졌다가 작아진다
		var progress := float(_flashes[i]["t"]) / _life
		var scale := _size * sin(progress * PI)
		var basis: Basis = _flashes[i]["basis"]
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * maxf(scale, 0.001)), _flashes[i]["pos"]))
