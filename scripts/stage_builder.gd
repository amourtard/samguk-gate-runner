class_name StageBuilder
extends RefCounted
## 스테이지 데이터로 한 판의 배치 계획을 만든다. 노드에 의존하지 않는 순수 계산이다.
## 실제 노드 배치는 run.gd가 이 계획을 받아서 한다.
## 계획: {"gate_pairs": [{distance, left, right}], "enemy_groups": [{distance, units, section}],
##        "bridge": {"start", "end"} 또는 빈 사전, "boss": {distance, health}, "section_length", "sections"}

# 규칙에 맞는 게이트 쌍을 찾을 때까지 다시 뽑는 최대 횟수
const MAX_PAIR_ATTEMPTS := 200
# 병종 비율 상한을 지키는 구성을 찾을 때까지 다시 뽑는 최대 횟수
const MAX_COMPOSITION_ATTEMPTS := 200


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

		# 구간마다 적 무리 2개. 스테이지 병종 비율을 무리마다 그대로 나눈다
		for offset in layout["enemies"]:
			enemy_groups.append({
				"distance": section_start + float(offset),
				"units": _split_composition(group_counts[group_index], stage["composition"]),
				"section": section,
			})
			group_index += 1

		# 구간마다 게이트 2~3쌍. 전환 게이트의 대상은 그 게이트 다음에 만날 적 무리로 정한다
		var pair_count := rng.randi_range(int(stages["gate_pairs_per_section"]["min"]), int(stages["gate_pairs_per_section"]["max"]))
		for i in pair_count:
			var distance := section_start + float(layout["gates"][i])
			var pair := _random_pair(section, gates, rng, switch_target(distance, enemy_groups, units, tuning))
			pair["distance"] = distance
			pair["section"] = section
			gate_pairs.append(pair)

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


## 데이터 목록 뒤(1-5 이후)의 스테이지를 만든다. index는 0부터 센 스테이지 순번이다.
## 마지막 데이터 스테이지를 기준으로 한 단계마다 적 병력 합계와 보스 체력에 배율을 곱한다.
## 적 구성은 전투 병종 비율을 무작위로 정하되 한 병종이 상한을 넘지 않고, 좁은 다리는 확률로 한 구간에 둔다.
static func endless_stage(index: int, stages: Dictionary, units: Dictionary, tuning: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var list: Array = stages["list"]
	var last: Dictionary = list[list.size() - 1]
	var steps := index - (list.size() - 1)
	var endless: Dictionary = tuning["endless"]

	# 이름은 마지막 데이터 스테이지 번호에 이어 붙인다. 예: 1-5 다음은 1-6
	var id_parts: PackedStringArray = str(last["id"]).split("-")
	var id := "%s-%d" % [id_parts[0], int(id_parts[1]) + steps]

	var bridge_section := 0
	if rng.randf() < float(endless["bridge_chance"]):
		bridge_section = rng.randi_range(1, int(stages["sections"]))

	return {
		"id": id,
		"composition": _random_composition(units, float(endless["max_unit_ratio"]), rng),
		"enemy_total": roundi(float(last["enemy_total"]) * pow(float(endless["enemy_total_mult"]), steps)),
		"bridge_section": bridge_section,
		"boss_health": roundi(float(last["boss_health"]) * pow(float(endless["boss_health_mult"]), steps)),
	}


## 전투 병종(보스 제외) 비율을 무작위로 정한다. 한 병종이 max_ratio를 넘으면 다시 뽑는다.
static func _random_composition(units: Dictionary, max_ratio: float, rng: RandomNumberGenerator) -> Dictionary:
	var unit_types: Array = []
	for unit_type in units:
		if float(units[unit_type]["dps"]) > 0.0:
			unit_types.append(unit_type)
	for attempt in MAX_COMPOSITION_ATTEMPTS:
		var weights := {}
		var sum := 0.0
		for unit_type in unit_types:
			weights[unit_type] = rng.randf()
			sum += float(weights[unit_type])
		if sum <= 0.0:
			continue
		var composition := {}
		var within_limit := true
		for unit_type in unit_types:
			composition[unit_type] = float(weights[unit_type]) / sum
			if float(composition[unit_type]) > max_ratio:
				within_limit = false
		if within_limit:
			return composition
	# 상한을 지키는 비율을 찾지 못하면 고르게 나눈다
	var even := {}
	for unit_type in unit_types:
		even[unit_type] = 1.0 / unit_types.size()
	return even


## distance 다음에 만날 적 무리에서 가장 많은 병종에게 유리한 병종. 그런 무리나 병종이 없으면 빈 문자열.
## 수가 같으면 앞줄 순서(tuning의 front_order)가 빠른 병종을 기준으로 삼는다.
static func switch_target(distance: float, enemy_groups: Array[Dictionary], units: Dictionary, tuning: Dictionary) -> String:
	var next := {}
	for group in enemy_groups:
		if float(group["distance"]) > distance and (next.is_empty() or float(group["distance"]) < float(next["distance"])):
			next = group
	if next.is_empty():
		return ""
	var dominant := ""
	var dominant_count := 0
	for unit_type: String in tuning["combat"]["front_order"]:
		var count := int((next["units"] as Dictionary).get(unit_type, 0))
		if count > dominant_count:
			dominant = unit_type
			dominant_count = count
	for unit_type in Gate.switch_units(units):
		if str(units[unit_type]["strong_against"]) == dominant:
			return unit_type
	return ""


## 명세의 쌍 규칙(좌우 다른 종류, 도박과 함정은 증원 +N과만, ×2는 2구간부터)을 지키는 쌍을 무작위로 뽑는다.
## switch_unit은 전환 게이트의 대상 병종이고, 비어 있으면 전환 게이트를 뽑지 않는다.
static func _random_pair(section: int, gates: Dictionary, rng: RandomNumberGenerator, switch_unit: String) -> Dictionary:
	var types: Array = gates.keys()
	if switch_unit == "":
		types.erase("switch")
	for attempt in MAX_PAIR_ATTEMPTS:
		var left := _random_gate(types[rng.randi_range(0, types.size() - 1)], gates, rng, switch_unit)
		var right := _random_gate(types[rng.randi_range(0, types.size() - 1)], gates, rng, switch_unit)
		if Gate.pair_error(left, right, gates, section) == "":
			return {"left": left, "right": right}
	push_error("규칙에 맞는 게이트 쌍을 찾지 못했습니다")
	return {"left": {"type": "reinforce", "option": gates["reinforce"]["options"].keys()[0]}, "right": {"type": "trap"}}


static func _random_gate(type: String, gates: Dictionary, rng: RandomNumberGenerator, switch_unit: String) -> Dictionary:
	var spec := {"type": type}
	var data: Dictionary = gates[type]
	if data.has("options"):
		var options: Array = data["options"].keys()
		spec["option"] = options[rng.randi_range(0, options.size() - 1)]
	if type == "switch":
		spec["unit"] = switch_unit
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
