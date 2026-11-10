class_name Army
extends RefCounted
## 병력 모델. 노드와 렌더링에 의존하지 않는 순수 계산이다.

signal changed

var unit_type: String
var unit_health: float
var count: int
var total_health: float


func _init(p_unit_type: String, p_unit_health: float, p_count: int) -> void:
	unit_type = p_unit_type
	unit_health = p_unit_health
	set_count(p_count)


func set_count(value: int) -> void:
	count = maxi(value, 0)
	total_health = count * unit_health
	changed.emit()
