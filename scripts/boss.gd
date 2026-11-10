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


## 한 번의 계산. 반환값: warn_started(예고 시작한 구역, 없으면 -1), hit(공격이 아군을 맞혔는가), attacked(공격한 구역, 없으면 -1)
func tick(dt: float, army: Army, ally_zone: int, in_contact: bool, rng: RandomNumberGenerator) -> Dictionary:
	var events := {"warn_started": -1, "attacked": -1, "hit": false}

	# 예고 중에도 간격 타이머는 계속 흘러 공격이 정해진 간격마다 시작된다
	_timer += dt
	if warning_zone >= 0:
		_warn_left -= dt
		if _warn_left <= 0.0:
			# 공격 순간 아군 중심이 그 구역에 있으면 병력의 일정 비율을 잃는다
			events["attacked"] = warning_zone
			if ally_zone == warning_zone:
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


## 도로를 좌, 중, 우 구역으로 나눴을 때 x가 속한 구역(0부터)
static func zone_of(x: float, road_width: float, zones: int) -> int:
	var ratio := (x + road_width / 2.0) / road_width
	return clampi(floori(ratio * zones), 0, zones - 1)


## 구역 중심의 x 좌표
static func zone_center(zone: int, road_width: float, zones: int) -> float:
	var zone_width := road_width / zones
	return -road_width / 2.0 + zone_width * (zone + 0.5)
