class_name ArrowView
extends MultiMeshInstance3D
## 궁병 사격을 날아가는 작은 상자로 그린다. 피해 계산과 무관한 연출이다.
## 계산 간격마다 사격 사건이 오므로 쏘는 쪽마다 최소 간격을 두고 한 무더기씩 날린다.

var _interval: float
var _per_volley: int
var _flight_time: float
var _arc_height: float
var _spread: float
var _target_spread_ratio: float
var _height: float
var _max_count: int
# 날아가는 화살. 각 항목은 {"from": 시작점, "to": 도착점, "t": 지난 시간}
var _arrows: Array[Dictionary] = []
var _cooldowns := {}
var _rng := RandomNumberGenerator.new()


func setup(tuning: Dictionary) -> void:
	var data: Dictionary = tuning["arrow_view"]
	_interval = float(data["interval"])
	_per_volley = int(data["per_volley"])
	_flight_time = float(data["flight_time"])
	_arc_height = float(data["arc_height"])
	_spread = float(data["spread"])
	_target_spread_ratio = float(data["target_spread_ratio"])
	_height = float(data["height"])
	_max_count = int(data["max_count"])
	_rng.seed = randi()

	var box := BoxMesh.new()
	box.size = Vector3(float(data["size"][0]), float(data["size"][1]), float(data["size"][2]))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(data["color"])
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	material_override = material


## 쏘는 쪽(shooter)이 최소 간격을 지났으면 from에서 to로 한 무더기를 날린다.
func fire(shooter: String, from: Vector3, to: Vector3) -> void:
	if float(_cooldowns.get(shooter, 0.0)) > 0.0:
		return
	_cooldowns[shooter] = _interval
	for i in _per_volley:
		if _arrows.size() >= _max_count:
			return
		var jitter := Vector3(_rng.randf_range(-_spread, _spread), 0.0, _rng.randf_range(-_spread, _spread))
		_arrows.append({
			"from": from + jitter + Vector3.UP * _height,
			"to": to + jitter * _target_spread_ratio,
			"t": -_rng.randf_range(0.0, _interval),
		})


func _process(delta: float) -> void:
	for shooter in _cooldowns:
		_cooldowns[shooter] = float(_cooldowns[shooter]) - delta

	for arrow in _arrows:
		arrow["t"] = float(arrow["t"]) + delta
	_arrows = _arrows.filter(func(arrow: Dictionary) -> bool: return float(arrow["t"]) < _flight_time)

	multimesh.instance_count = _arrows.size()
	for i in _arrows.size():
		var arrow := _arrows[i]
		# 출발 전(음수 시간)인 화살은 시작점에 숨겨 둔다
		var progress := clampf(float(arrow["t"]) / _flight_time, 0.0, 1.0)
		var position_now := _arc_point(arrow, progress)
		var position_next := _arc_point(arrow, minf(progress + delta / _flight_time, 1.0))
		var basis := Basis.IDENTITY
		var direction := position_next - position_now
		if direction.length_squared() > 0.0 and not direction.normalized().abs().is_equal_approx(Vector3.UP):
			basis = Basis.looking_at(direction, Vector3.UP)
		var scale := 1.0 if float(arrow["t"]) >= 0.0 else 0.0
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * scale), position_now))


## 시작점과 도착점 사이의 포물선 위 점
func _arc_point(arrow: Dictionary, progress: float) -> Vector3:
	var point: Vector3 = (arrow["from"] as Vector3).lerp(arrow["to"], progress)
	point.y += sin(progress * PI) * _arc_height
	return point
