class_name BossPattern
extends RefCounted
## 보스 장각의 공격 패턴. 노드에 의존하지 않는 순수 계산이다.
## 체력과 아군이 주는 피해는 Combat이 보스를 적 병종 하나로 보고 계산한다.
## 여기서는 구역 예고와 공격, 접촉 중 병력 감소만 다룬다.

var warning_zone := -1

var _interval: float
var _warn_time: float
var _zones: int
var _hit_loss_ratio: float
var _contact_loss_per_second: float
var _road_width: float
var _hit_edge_tolerance: float
var _timer := 0.0
var _warn_left := 0.0
var _contact_loss_accum := 0.0


func _init(tuning: Dictionary) -> void:
	var data: Dictionary = tuning["boss"]
	_interval = float(data["pattern_interval"])
	_warn_time = float(data["warn_time"])
	_zones = int(data["zones"])
	_hit_loss_ratio = float(data["hit_loss_ratio"])
	_contact_loss_per_second = float(data["contact_loss_per_second"])
	_road_width = float(tuning["road"]["width"])
	_hit_edge_tolerance = float(data["hit_edge_tolerance"])


## 한 번의 계산. ally_left, ally_right는 아군 표시 대형의 좌우 끝 x다.
## 반환값: warn_started(예고 시작한 구역, 없으면 -1), hit(공격이 아군을 맞혔는가), attacked(공격한 구역, 없으면 -1)
func tick(dt: float, army: Army, ally_left: float, ally_right: float, in_contact: bool, rng: RandomNumberGenerator) -> Dictionary:
	var events := {"warn_started": -1, "attacked": -1, "hit": false}

	# 예고 중에도 간격 타이머는 계속 흘러 공격이 정해진 간격마다 시작된다
	_timer += dt
	if warning_zone >= 0:
		_warn_left -= dt
		if _warn_left <= 0.0:
			# 공격 순간 아군 무리가 그 구역에 걸쳐 있으면 병력의 일정 비율을 잃는다
			events["attacked"] = warning_zone
			if overlaps_zone(ally_left, ally_right, warning_zone, _road_width, _zones, _hit_edge_tolerance):
				army.lose_soldiers(roundi(army.count * _hit_loss_ratio))
				events["hit"] = true
			warning_zone = -1
	elif _timer >= _interval:
		_timer -= _interval
		warning_zone = rng.randi_range(0, _zones - 1)
		_warn_left = _warn_time
		events["warn_started"] = warning_zone

	# 접촉 중에는 초당 정해진 명수씩 잃는다
	if in_contact:
		_contact_loss_accum += _contact_loss_per_second * dt
		var whole := floori(_contact_loss_accum)
		if whole > 0:
			_contact_loss_accum -= whole
			army.lose_soldiers(whole)
	return events


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
