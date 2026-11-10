class_name Gate
extends RefCounted
## 게이트 효과 적용과 표시 문구. 노드에 의존하지 않는 순수 계산이다.
## 게이트 하나는 {"type": 종류, "option": 선택지 이름, "unit": 전환 병종} 형태의 사전이다.


## 게이트 효과를 병력에 적용한다.
## 반환값: count_delta(병력 변화량), popup(변화량 문구), gold(판 종료 시 받을 금화)
static func apply(army: Army, spec: Dictionary, gates: Dictionary, units: Dictionary, rng: RandomNumberGenerator, strategy: Strategy) -> Dictionary:
	var data: Dictionary = gates[spec["type"]]
	var before := army.count
	var gold := 0
	var extra := ""

	match spec["type"]:
		"reinforce":
			var option: Dictionary = data["options"][spec["option"]]
			var gained := 0
			if option.has("add"):
				gained = int(option["add"])
			else:
				gained = army.count * (int(option["mult"]) - 1)
			# 징병과 물량 계열 효과는 늘어나는 양에 붙는다
			army.set_count(army.count + strategy.adjust_reinforce(gained))
		"switch":
			var unit_type: String = spec["unit"]
			army.set_unit_type(unit_type, float(units[unit_type]["health"]))
			army.set_count(_after_loss(army.count, float(data["loss_ratio"])))
			extra = units[unit_type]["name"]
		"empower":
			var option: Dictionary = data["options"][spec["option"]]
			if option.has("attack_speed_bonus"):
				army.attack_speed_mult *= 1.0 + float(option["attack_speed_bonus"])
				extra = "공격속도 +%d%%" % _percent(option["attack_speed_bonus"])
			if option.has("damage_taken_reduction"):
				army.damage_taken_mult *= 1.0 - float(option["damage_taken_reduction"])
				extra = "받는 피해 -%d%%" % _percent(option["damage_taken_reduction"])
			army.set_count(_after_loss(army.count, float(option["loss_ratio"])))
		"gamble":
			if rng.randf() < float(data["win_chance"]):
				army.set_count(army.count * int(data["win_mult"]))
				extra = "성공"
			else:
				army.set_count(roundi(float(army.count) / float(data["lose_divisor"])))
				extra = "실패"
		"trap":
			army.set_count(_after_loss(army.count, float(data["loss_ratio"])))
			gold = int(data["gold_bonus"])
			extra = "금화 +%d" % gold
		_:
			push_error("알 수 없는 게이트 종류: " + str(spec["type"]))

	var delta := army.count - before
	var popup := "%+d" % delta
	if extra != "":
		popup = extra + "\n" + popup
	return {"count_delta": delta, "popup": popup, "gold": gold}


## 게이트 판에 쓰는 문구. 첫 줄은 크게 보일 효과, 둘째 줄은 대가다.
static func label(spec: Dictionary, gates: Dictionary, units: Dictionary) -> String:
	var data: Dictionary = gates[spec["type"]]
	match spec["type"]:
		"reinforce":
			var option: Dictionary = data["options"][spec["option"]]
			if option.has("add"):
				return "+%d" % int(option["add"])
			return "×%d" % int(option["mult"])
		"switch":
			return "%s 전환\n병력 -%d%%" % [units[spec["unit"]]["name"], _percent(data["loss_ratio"])]
		"empower":
			var option: Dictionary = data["options"][spec["option"]]
			var effect := ""
			if option.has("attack_speed_bonus"):
				effect = "공속 +%d%%" % _percent(option["attack_speed_bonus"])
			else:
				effect = "방어 +%d%%" % _percent(option["damage_taken_reduction"])
			return "%s\n병력 -%d%%" % [effect, _percent(option["loss_ratio"])]
		"gamble":
			return "도박\n×%d 또는 ÷%d" % [int(data["win_mult"]), int(data["lose_divisor"])]
		"trap":
			return "함정\n병력 -%d%% 금화 +%d" % [_percent(data["loss_ratio"]), int(data["gold_bonus"])]
	return ""


## 한 쌍이 명세 규칙을 지키는지 검사한다. 어긋나면 이유를, 맞으면 빈 문자열을 돌려준다.
static func pair_error(left: Dictionary, right: Dictionary, gates: Dictionary, section: int) -> String:
	if left["type"] == right["type"]:
		return "좌우가 같은 종류입니다"
	for pair in [[left, right], [right, left]]:
		var spec: Dictionary = pair[0]
		var other: Dictionary = pair[1]
		var data: Dictionary = gates[spec["type"]]
		# 도박은 증원(+N)과만 짝짓는다
		if data.has("pair_with"):
			if not other["type"] in data["pair_with"]:
				return "%s은 %s와 짝지을 수 없습니다" % [data["name"], gates[other["type"]]["name"]]
			var other_option: Dictionary = gates[other["type"]].get("options", {}).get(other.get("option", ""), {})
			if not other_option.has("add"):
				return "%s은 증원(+N)과만 짝짓습니다" % data["name"]
		# 구간 제한이 있는 선택지 (×2는 2구간부터)
		if data.has("options"):
			var option: Dictionary = data["options"][spec["option"]]
			if section < int(option.get("min_section", section)):
				return "%s는 %d구간부터 나옵니다" % [label(spec, gates, {}), int(option["min_section"])]
	return ""


static func _after_loss(count: int, loss_ratio: float) -> int:
	return roundi(count * (1.0 - loss_ratio))


static func _percent(ratio: Variant) -> int:
	return roundi(float(ratio) * 100.0)
