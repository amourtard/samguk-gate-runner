class_name BossPattern
extends RefCounted
## 보스 장각의 공격 패턴. 노드에 의존하지 않는 순수 계산이다.
## 체력과 아군이 주는 피해는 Combat이 보스를 적 병종 하나로 보고 계산한다.
## 여기서는 구역 예고와 공격, 일반 공격(불덩이), 분노만 다룬다.

var warning_zone := -1

var _interval: float
var _warn_time: float
var _zones: int
var _hit_loss_ratio: float
var _normal_interval: float
var _normal_loss: int
var _normal_flight: float
var _normal_radius: float
var _normal_core: float
var _enrage_ratio: float
var _enrage_interval_mult: float
# 체력이 일정 비율 아래로 내려가면 분노해 구역 공격 간격이 짧아진다
var enraged := false
var _road_width: float
var _hit_edge_tolerance: float
var _timer := 0.0
var _warn_left := 0.0
var _normal_timer := 0.0
# 날아가는 중인 불덩이: {"t": 남은 시간, "x": 떨어질 자리}
var _normal_flights: Array[Dictionary] = []


func _init(tuning: Dictionary) -> void:
	var data: Dictionary = tuning["boss"]
	_interval = float(data["pattern_interval"])
	_warn_time = float(data["warn_time"])
	_zones = int(data["zones"])
	_hit_loss_ratio = float(data["hit_loss_ratio"])
	_normal_interval = float(data["normal_interval"])
	_normal_loss = int(data["normal_loss"])
	_normal_flight = float(data["normal_flight"])
	_normal_radius = float(data["normal_radius"])
	_normal_core = float(data["normal_core"])
	_enrage_ratio = float(data["enrage_ratio"])
	_enrage_interval_mult = float(data["enrage_interval_mult"])
	# 보스전은 광장에서 하므로 구역은 광장 폭을 나눈 것이다
	_road_width = float(tuning["boss_road_width"])
	_hit_edge_tolerance = float(data["hit_edge_tolerance"])


## 한 번의 계산. ally_left, ally_right는 아군 표시 대형의 좌우 끝 x, in_range는 아군이 일반 공격 거리 안에 있는가,
## health_ratio는 보스의 남은 체력 비율이다.
## 반환값: warn_started(예고 시작한 구역, 없으면 -1), attacked(공격한 구역, 없으면 -1), hit(구역 공격이 아군을 맞혔는가),
## normal_fired(불덩이를 던졌는가), normal_target(그 불덩이가 떨어질 x), normal_landed(이번에 떨어진 불덩이 목록 {x, lost}),
## normal_hit(이번에 떨어진 불덩이로 잃은 병력 수 합계), enraged(이번에 분노했는가)
func tick(dt: float, army: Army, ally_left: float, ally_right: float, in_range: bool, health_ratio: float, rng: RandomNumberGenerator) -> Dictionary:
	var events := {"warn_started": -1, "attacked": -1, "hit": false, "normal_fired": false, "normal_target": 0.0, "normal_landed": [], "normal_hit": 0, "enraged": false}

	if not enraged and health_ratio <= _enrage_ratio:
		enraged = true
		events["enraged"] = true
	var interval := _interval * (_enrage_interval_mult if enraged else 1.0)

	# 예고 중에도 간격 타이머는 계속 흘러 공격이 정해진 간격마다 시작된다
	_timer += dt
	if warning_zone >= 0:
		_warn_left -= dt
		if _warn_left <= 0.0:
			# 공격 순간 아군 무리가 그 구역에 걸쳐 있으면 병력의 일정 비율을 잃는다
			events["attacked"] = warning_zone
			if overlaps_zone(ally_left, ally_right, warning_zone, _road_width, _zones, _hit_edge_tolerance):
				army.lose_soldiers(_scaled_loss(army, roundi(army.count * _hit_loss_ratio)))
				events["hit"] = true
			warning_zone = -1
	elif _timer >= interval:
		_timer -= interval
		warning_zone = rng.randi_range(0, _zones - 1)
		_warn_left = _warn_time
		events["warn_started"] = warning_zone

	# 일반 공격: 거리 안에 있으면 정해진 간격마다 불덩이를 던진다. 던지는 순간 아군 중심이 있던 자리를 겨냥한다
	# 구역 공격 예고 중에는 새로 던지지 않는다(예고와 겹쳐 피할 자리가 없어지는 것을 막는다). 이미 던진 것은 떨어진다
	if in_range and warning_zone < 0:
		_normal_timer += dt
		if _normal_timer >= _normal_interval:
			_normal_timer -= _normal_interval
			var target := (ally_left + ally_right) / 2.0
			_normal_flights.append({"t": _normal_flight, "x": target})
			events["normal_fired"] = true
			events["normal_target"] = target
	# 떨어지는 순간 무리의 중심부(장수 좌우 _normal_core, 무리가 더 좁으면 무리 폭)가 그 자리에 걸쳐 있을 때만 병력을 잃는다
	var center := (ally_left + ally_right) / 2.0
	var core := minf((ally_right - ally_left) / 2.0, _normal_core)
	for i in range(_normal_flights.size() - 1, -1, -1):
		var flight: Dictionary = _normal_flights[i]
		flight["t"] = float(flight["t"]) - dt
		if float(flight["t"]) <= 0.0:
			_normal_flights.remove_at(i)
			var x := float(flight["x"])
			var lost := 0
			if minf(center + core, x + _normal_radius) - maxf(center - core, x - _normal_radius) > _hit_edge_tolerance:
				lost = mini(_scaled_loss(army, _normal_loss), army.count)
				army.lose_soldiers(lost)
			(events["normal_landed"] as Array).append({"x": x, "lost": lost})
			events["normal_hit"] = int(events["normal_hit"]) + lost
	return events


## 날아오는 중인 불덩이가 떨어질 x 목록(자동 조작 확인용)
func incoming_targets() -> Array[float]:
	var result: Array[float] = []
	for flight in _normal_flights:
		result.append(float(flight["x"]))
	return result


## 보스 공격으로 잃는 병력에도 받는 피해 배율(장수 기술, 철갑, 방어 강화)을 곱한다. 맞았으면 최소 1명은 잃는다.
func _scaled_loss(army: Army, base: int) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(base * army.damage_taken_mult))


func normal_radius() -> float:
	return _normal_radius


## 도로를 같은 폭의 구역(지금은 좌, 우 2개)으로 나눴을 때 x가 속한 구역(0부터)
static func zone_of(x: float, road_width: float, zones: int) -> int:
	var ratio := (x + road_width / 2.0) / road_width
	return clampi(floori(ratio * zones), 0, zones - 1)


## 무리(왼쪽 끝 left, 오른쪽 끝 right)가 구역에 tolerance보다 넓게 걸쳐 있는가.
## 무리 전체가 구역 밖에 있어야 피한 것이다(명세 4장 보스 장각).
static func overlaps_zone(left: float, right: float, zone: int, road_width: float, zones: int, tolerance: float) -> bool:
	var range_ := zone_range(zone, road_width, zones)
	return minf(right, range_.y) - maxf(left, range_.x) > tolerance


## 구역의 범위(왼쪽 x, 오른쪽 x). 판정과 예고 면이 같이 쓴다
static func zone_range(zone: int, road_width: float, zones: int) -> Vector2:
	var zone_width := road_width / zones
	var left := -road_width / 2.0 + zone_width * zone
	return Vector2(left, left + zone_width)


## 구역 중심의 x 좌표
static func zone_center(zone: int, road_width: float, zones: int) -> float:
	var zone_width := road_width / zones
	return -road_width / 2.0 + zone_width * (zone + 0.5)
