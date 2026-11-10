class_name EnemyGroup
extends Node3D
## 적 무리 하나. 병종별 Army를 만들고 ArmyView로 그린다.
## 노드의 z 위치가 무리의 앞줄이고, 병종은 앞줄 순서대로 뒤(-Z)로 늘어선다.

var pools: Array[Army] = []
# 병종별 무리 중심의 상대 위치. 화살 연출의 출발점으로 쓴다
var _pool_offsets := {}


func setup(composition: Dictionary, units: Dictionary, tuning: Dictionary) -> void:
	var spacing := float(tuning["formation"]["spacing"])
	var color := Color.html(tuning["colors"]["enemy"])
	var depth := 0.0
	for unit_type in tuning["combat"]["front_order"]:
		if not composition.has(unit_type):
			continue
		var count := int(composition[unit_type])
		var pool := Army.new(unit_type, float(units[unit_type]["health"]), count)
		pools.append(pool)

		var radius := ArmyView.formation_radius(count, spacing)
		var view := ArmyView.new()
		add_child(view)
		view.position = Vector3(0.0, 0.0, -(depth + radius))
		_pool_offsets[unit_type] = view.position
		view.setup(pool, units, tuning, color)
		depth += radius * 2.0


## 병종 무리 중심의 월드 좌표
func pool_center(unit_type: String) -> Vector3:
	return global_position + (_pool_offsets.get(unit_type, Vector3.ZERO) as Vector3)


func total_count() -> int:
	var total := 0
	for pool in pools:
		total += pool.count
	return total
