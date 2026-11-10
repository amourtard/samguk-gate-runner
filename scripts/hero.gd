class_name HeroSkill
extends RefCounted
## 장수 고유 기술(자동 발동). 노드에 의존하지 않는 순수 계산이다.
## strike: 일정 간격으로 전방 적 무리에 병력 수 비례 피해
## guard: 일정 시간 받는 피해 감소
## focus: 일정 시간 사거리와 공격속도 증가

var hero_id: String
var name: String

var _skill: Dictionary
var _timer := 0.0
var _active_left := 0.0


func _init(p_hero_id: String, hero: Dictionary) -> void:
	hero_id = p_hero_id
	name = hero["name"]
	_skill = hero["skill"]


## 한 번의 계산. target_gap은 전방 적 무리까지의 거리(없으면 INF).
## 반환값: activated(이번에 발동했는가), strike_damage(전방 적에게 줄 피해)
func tick(dt: float, army: Army, target_gap: float) -> Dictionary:
	var events := {"activated": false, "strike_damage": 0.0}

	# 지속 효과가 끝나면 원래대로 되돌린다
	if _active_left > 0.0:
		_active_left -= dt
		if _active_left <= 0.0:
			_apply_buff(army, false)
		return events

	_timer = minf(_timer + dt, float(_skill["interval"]))
	if _timer < float(_skill["interval"]):
		return events

	match _skill["type"]:
		"strike":
			# 전방에 적이 없으면 준비된 채로 기다린다
			if target_gap > float(_skill["target_range"]):
				return events
			events["strike_damage"] = army.count * float(_skill["damage_per_soldier"])
		"guard", "focus":
			_apply_buff(army, true)
			_active_left = float(_skill["duration"])
	_timer = 0.0
	events["activated"] = true
	return events


## 다음 발동까지 남은 시간(지속 중이면 0)
func time_left() -> float:
	if _active_left > 0.0:
		return 0.0
	return maxf(float(_skill["interval"]) - _timer, 0.0)


func is_active() -> bool:
	return _active_left > 0.0


func _apply_buff(army: Army, on: bool) -> void:
	match _skill["type"]:
		"guard":
			var mult := 1.0 - float(_skill["damage_taken_reduction"])
			army.damage_taken_mult = army.damage_taken_mult * mult if on else army.damage_taken_mult / mult
		"focus":
			var range_mult := 1.0 + float(_skill["range_bonus"])
			var speed_mult := 1.0 + float(_skill["attack_speed_bonus"])
			if on:
				army.range_mult *= range_mult
				army.attack_speed_mult *= speed_mult
			else:
				army.range_mult /= range_mult
				army.attack_speed_mult /= speed_mult
