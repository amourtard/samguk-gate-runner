class_name StageBuilder
extends RefCounted
## 스테이지 데이터로 한 판의 배치 계획을 만든다. 노드에 의존하지 않는 순수 계산이다.
## 실제 노드 배치는 run.gd가 이 계획을 받아서 한다.
## 계획: {"gate_pairs": [{distance, left, right}], "enemy_groups": [{distance, units, section}],
##        "bridge": {"start", "end"} 또는 빈 사전, "boss": {distance, health}, "section_length", "sections"}

# 규칙에 맞는 게이트 쌍을 찾을 때까지 다시 뽑는 최대 횟수
const MAX_PAIR_ATTEMPTS := 200


static func plan(stage: Dictionary, stages: Dictionary, gates: Dictionary, units: Dictionary, tuning: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var section_length := float(tuning["section_length"])
	var sections := int(stages["sections"])
	var layout: Dictionary = stages["section_layout"]
	var weights: Array = stages["enemy_group_weights"]
	var group_counts := _split_total(int(stage["enemy_total"]), weights)

	var gate_pairs: Array[Dictionary] = []
	var enemy_groups: Array[Dictionary] = []
	var group_index := 0
	for section in range(1, sections + 1):
		var section_start := (section - 1) * section_length

		# 구간마다 게이트 2~3쌍
		var pair_count := rng.randi_range(int(stages["gate_pairs_per_section"]["min"]), int(stages["gate_pairs_per_section"]["max"]))
		for i in pair_count:
			var pair := _random_pair(section, gates, units, rng)
			pair["distance"] = section_start + float(layout["gates"][i])
			gate_pairs.append(pair)

		# 구간마다 적 무리 2개. 스테이지 병종 비율을 무리마다 그대로 나눈다
		for offset in layout["enemies"]:
			enemy_groups.append({
				"distance": section_start + float(offset),
				"units": _split_composition(group_counts[group_index], stage["composition"]),
				"section": section,
			})
			group_index += 1

	var bridge := {}
	var bridge_section := int(stage["bridge_section"])
	if bridge_section > 0:
		bridge = {"start": (bridge_section - 1) * section_length, "end": bridge_section * section_length}

	var boss_data: Dictionary = stages["boss"]
	return {
		"gate_pairs": gate_pairs,
		"enemy_groups": enemy_groups,
		"bridge": bridge,
		"bridge_section": bridge_section,
		"boss": {
			"unit": boss_data["unit"],
			"distance": sections * section_length + float(boss_data["distance_after_last_section"]),
			"health": float(stage["boss_health"]),
		},
		"section_length": section_length,
		"sections": sections,
	}


## 명세의 쌍 규칙(좌우 다른 종류, 도박은 증원 +N과만, ×2는 2구간부터)을 지키는 쌍을 무작위로 뽑는다.
static func _random_pair(section: int, gates: Dictionary, units: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var types: Array = gates.keys()
	for attempt in MAX_PAIR_ATTEMPTS:
		var left := _random_gate(types[rng.randi_range(0, types.size() - 1)], gates, units, rng)
		var right := _random_gate(types[rng.randi_range(0, types.size() - 1)], gates, units, rng)
		if Gate.pair_error(left, right, gates, section) == "":
			return {"left": left, "right": right}
	push_error("규칙에 맞는 게이트 쌍을 찾지 못했습니다")
	return {"left": {"type": "reinforce", "option": gates["reinforce"]["options"].keys()[0]}, "right": {"type": "trap"}}


static func _random_gate(type: String, gates: Dictionary, units: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var spec := {"type": type}
	var data: Dictionary = gates[type]
	if data.has("options"):
		var options: Array = data["options"].keys()
		spec["option"] = options[rng.randi_range(0, options.size() - 1)]
	if type == "switch":
		var unit_types: Array = []
		for unit_type in units:
			# 보스처럼 체력만 쓰는 항목은 전환 대상이 아니다
			if float(units[unit_type]["dps"]) > 0.0:
				unit_types.append(unit_type)
		spec["unit"] = unit_types[rng.randi_range(0, unit_types.size() - 1)]
	return spec


## 합계를 비율대로 나누고 반올림 차이는 남은 몫이 큰 쪽부터 채운다(최대 나머지 방식).
static func _split_total(total: int, weights: Array) -> Array[int]:
	var keys: Array = range(weights.size())
	var ratios := {}
	for i in keys:
		ratios[i] = float(weights[i])
	var split := _largest_remainder(total, ratios)
	var result: Array[int] = []
	for i in keys:
		result.append(int(split[i]))
	return result


static func _split_composition(total: int, composition: Dictionary) -> Dictionary:
	var split := _largest_remainder(total, composition)
	var result := {}
	for unit_type in split:
		if int(split[unit_type]) > 0:
			result[unit_type] = int(split[unit_type])
	return result


static func _largest_remainder(total: int, ratios: Dictionary) -> Dictionary:
	var ratio_sum := 0.0
	for key in ratios:
		ratio_sum += float(ratios[key])
	var result := {}
	var remainders: Array = []
	var assigned := 0
	for key in ratios:
		var exact := total * float(ratios[key]) / ratio_sum
		result[key] = floori(exact)
		assigned += floori(exact)
		remainders.append([exact - floori(exact), key])
	remainders.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in total - assigned:
		var key: Variant = remainders[i % remainders.size()][1]
		result[key] = int(result[key]) + 1
	return result
