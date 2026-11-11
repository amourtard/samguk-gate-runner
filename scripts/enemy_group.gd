class_name EnemyGroup
extends Node3D
## 적 무리 하나. 병종별 Army를 만들고 ArmyView로 그린다.
## 노드의 z 위치가 무리의 앞줄이고, 병종은 앞줄 순서대로 뒤(-Z)로 늘어선다.
## 보스도 병종 하나짜리 무리로 만든다(체력만 스테이지 값으로 덮어쓴다).

var pools: Array[Army] = []
# 이 무리가 놓인 구간(1부터). 좁은 다리 판정에 쓴다
var section := 0
var is_boss := false
# 병종별 무리 중심의 상대 위치. 화살 연출의 출발점으로 쓴다
var _pool_offsets := {}


## health_override가 0보다 크면 병사 1명의 체력을 그 값으로 바꾼다(보스용).
func setup(composition: Dictionary, units: Dictionary, tuning: Dictionary, visual: Dictionary, color: Color, health_override := 0.0) -> void:
	var spacing := float(tuning["formation"]["spacing"])
	var depth := 0.0
	for unit_type in tuning["combat"]["front_order"]:
		if not composition.has(unit_type):
			continue
		var count := int(composition[unit_type])
		var health := health_override if health_override > 0.0 else float(units[unit_type]["health"])
		var pool := Army.new(unit_type, health, count)
		pools.append(pool)

		# 큰 도형(보스)은 도형 깊이의 절반을 반지름으로 본다. 도형 데이터가 없는 일반 병종은 대형 반지름만 쓴다
		var radius := maxf(ArmyView.formation_radius(count, spacing), _mesh_half_depth(units[unit_type].get("mesh", {})))
		var view := ArmyView.new()
		add_child(view)
		view.position = Vector3(0.0, 0.0, -(depth + radius))
		_pool_offsets[unit_type] = view.position
		# 적은 서서 기다리고, 앞줄은 처음 계산 위치에 고정한다
		view.setup(pool, units, tuning, visual, color, 1.0, float(visual["soldier"]["enemy_bob_height"]), radius)
		depth += radius * 2.0


## 병종 무리 중심의 월드 좌표
func pool_center(unit_type: String) -> Vector3:
	return global_position + (_pool_offsets.get(unit_type, Vector3.ZERO) as Vector3)


func total_count() -> int:
	var total := 0
	for pool in pools:
		total += pool.count
	return total


func _mesh_half_depth(mesh_data: Dictionary) -> float:
	if mesh_data.is_empty():
		return 0.0
	if mesh_data["shape"] == "box":
		return float(mesh_data["size"][2]) / 2.0
	return float(mesh_data.get("radius", 0.0))
