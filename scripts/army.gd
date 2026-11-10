class_name Army
extends RefCounted
## 병력 모델. 노드와 렌더링에 의존하지 않는 순수 계산이다.
## 적 무리는 병종마다 Army 하나씩을 묶어 표현한다.

signal changed

# 부동소수 오차로 병력 수가 1명 더 많게 올림되는 것을 막는 허용 오차
const HEALTH_EPSILON := 0.0001

var unit_type: String
var unit_health: float
var count: int
var total_health: float

# 보정치. 1.0이 기본이고 게이트, 책략, 장수가 바꾼다
var attack_mult := 1.0
var attack_speed_mult := 1.0
var damage_taken_mult := 1.0


func _init(p_unit_type: String, p_unit_health: float, p_count: int) -> void:
	unit_type = p_unit_type
	unit_health = p_unit_health
	set_count(p_count)


func set_count(value: int) -> void:
	count = maxi(value, 0)
	total_health = count * unit_health
	changed.emit()


## 병종을 바꾼다. 병력 수는 유지하고 체력 합계는 새 병종 기준으로 다시 채운다.
func set_unit_type(p_unit_type: String, p_unit_health: float) -> void:
	unit_type = p_unit_type
	unit_health = p_unit_health
	set_count(count)


func is_alive() -> bool:
	return count > 0


## 받는 피해 보정을 적용해 체력 합계에서 뺀다.
## 반환값은 amount 중 실제로 소모된 양이다(남는 피해를 다음 병종에 넘기기 위해).
func take_damage(amount: float) -> float:
	if amount <= 0.0 or count <= 0:
		return 0.0
	var effective := amount * damage_taken_mult
	var absorbed := minf(effective, total_health)
	total_health -= absorbed
	var new_count := 0
	if total_health > HEALTH_EPSILON:
		new_count = ceili(total_health / unit_health - HEALTH_EPSILON)
	else:
		total_health = 0.0
	if new_count != count:
		count = new_count
		changed.emit()
	return absorbed / damage_taken_mult


## 초당 피해에 곱할 공격 보정 합계.
func damage_scale() -> float:
	return attack_mult * attack_speed_mult
