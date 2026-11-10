class_name Strategy
extends RefCounted
## 한 판에서 고른 책략과 계열 효과. 노드에 의존하지 않는 순수 계산이다.
## 게이트, 전투, 구간 진행이 필요한 값을 여기에 물어본다.

var owned: Array[String] = []

var _data: Dictionary
var _list: Dictionary
var _families: Dictionary
var _bonus_count: int


func _init(strategies: Dictionary) -> void:
	_data = strategies
	_list = strategies["list"]
	_families = strategies["families"]
	_bonus_count = int(strategies["family_bonus_count"])


## 아직 고르지 않은 책략 중에서 무작위로 제시한다.
func offer(rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array[String] = []
	for id in _list:
		if not id in owned:
			pool.append(id)
	# 피셔-예이츠 섞기. 판 안의 난수를 같은 생성기로 쓰기 위해 직접 섞는다
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := pool[i]
		pool[i] = pool[j]
		pool[j] = temp
	return pool.slice(0, mini(int(_data["offer_count"]), pool.size()))


## 책략을 얻고 즉시 효과를 병력에 적용한다. 계열 효과가 새로 켜지면 그 계열 id를 돌려준다.
func add(id: String, army: Army) -> String:
	var family_before := active_family()
	owned.append(id)
	var entry: Dictionary = _list[id]
	if entry.has("loss_ratio"):
		army.set_count(roundi(army.count * (1.0 - float(entry["loss_ratio"]))))
	if entry.has("attack_mult"):
		army.attack_mult *= float(entry["attack_mult"])
	if entry.has("damage_taken_reduction"):
		army.damage_taken_mult *= 1.0 - float(entry["damage_taken_reduction"])

	var family_after := active_family()
	if family_after != family_before and family_after != "":
		var bonus: Dictionary = _families[family_after]["bonus"]
		if bonus.has("attack_bonus"):
			army.attack_mult *= 1.0 + float(bonus["attack_bonus"])
		return family_after
	return ""


func has(id: String) -> bool:
	return id in owned


func family_of(id: String) -> String:
	return _list[id]["family"]


## 같은 계열을 기준 개수 이상 모은 계열. 없으면 빈 문자열
func active_family() -> String:
	var counts := {}
	for id in owned:
		var family := family_of(id)
		counts[family] = int(counts.get(family, 0)) + 1
		if counts[family] >= _bonus_count:
			return family
	return ""


func family_color(family: String) -> Color:
	return Color.html(_families[family]["color"])


# --- 게이트 ---

## 증원 게이트로 늘어난 병력에 징병과 물량 계열 효과를 더한다.
func adjust_reinforce(gained: int) -> int:
	var result := float(gained)
	if has("conscription"):
		result *= 1.0 + float(_list["conscription"]["reinforce_bonus"])
	var bonus := _active_bonus()
	if bonus.has("reinforce_flat"):
		result += float(bonus["reinforce_flat"])
	return roundi(result)


# --- 구간 ---

func section_start_add() -> int:
	if has("volunteers"):
		return int(_list["volunteers"]["section_start_add"])
	return 0


# --- 전투 ---

func melee_limit_bonus() -> int:
	if has("wide_formation"):
		return int(_list["wide_formation"]["melee_limit_bonus"])
	return 0


## 선봉: 접촉 순간 병사 1명당 추가 피해
func contact_damage_per_soldier() -> float:
	if has("vanguard"):
		return float(_list["vanguard"]["contact_damage_per_soldier"])
	return 0.0


## 선봉: 기병 돌격 피해 배율
func charge_mult() -> float:
	if has("vanguard"):
		return float(_list["vanguard"]["charge_mult"])
	return 1.0


## 불화살: 원거리 피해 중 지속 피해로 더하는 비율(화공 계열 효과 포함)
func dot_ratio() -> float:
	if not has("fire_arrows"):
		return 0.0
	return float(_list["fire_arrows"]["dot_ratio"]) * _dot_mult()


func dot_duration() -> float:
	return float(_list["fire_arrows"]["dot_duration"])


func has_volley() -> bool:
	return has("fire_arrows")


func volley_interval() -> float:
	return float(_list["fire_arrows"]["volley_interval"])


func volley_range() -> float:
	return float(_list["fire_arrows"]["volley_range"])


func volley_damage_per_soldier() -> float:
	return float(_list["fire_arrows"]["volley_damage_per_soldier"])


## 화계: 교전 시작 때 적 무리 체력 대비 피해 비율
func fire_attack_ratio() -> float:
	if has("fire_attack"):
		return float(_list["fire_attack"]["health_ratio"])
	return 0.0


## 연환: 지속 피해 중인 적이 받는 피해 배율
func chain_mult() -> float:
	if has("chain"):
		return 1.0 + float(_list["chain"]["damage_taken_bonus"])
	return 1.0


# --- 표시 ---

func display_name(id: String) -> String:
	return _list[id]["name"]


func family_name(family: String) -> String:
	return _families[family]["name"]


func description(id: String) -> String:
	return fill_template(_list[id]["desc"], _list[id])


func family_bonus_description(family: String) -> String:
	return fill_template(_families[family]["bonus_desc"], _families[family]["bonus"])


func _dot_mult() -> float:
	return float(_active_bonus().get("dot_mult", 1.0))


func _active_bonus() -> Dictionary:
	var family := active_family()
	if family == "":
		return {}
	return _families[family]["bonus"]


## 설명 문구의 {키}와 {키_pct}를 데이터 값으로 채운다.
static func fill_template(template: String, values: Dictionary) -> String:
	var params := {}
	for key in values:
		var value: Variant = values[key]
		if value is float or value is int:
			params[key] = _number_text(float(value))
			params[key + "_pct"] = str(roundi(float(value) * 100.0))
	return template.format(params)


static func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return str(value)
