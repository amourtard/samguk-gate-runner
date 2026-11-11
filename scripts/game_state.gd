extends Node
## 자동 로드. 고른 장수, 도전할 스테이지, 열린 스테이지 수, 금화, 영구 강화 레벨을 들고 있고 파일로 저장한다.
## 데이터 목록(1-1~1-5) 뒤의 스테이지는 처음 필요할 때 만들어 두고 다시 도전할 때 그대로 쓴다.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var hero_id := ""
var stage_index := 0
# 1-1부터 순서대로 연다. 1이면 1-1만 열린 상태. 1-5 이후로는 끝없이 늘어난다
var unlocked_stages := 1
var gold := 0
# 영구 강화 레벨. 시설 이름 → 레벨
var upgrade_levels := {}

# 자동 생성한 스테이지. 순번 → 스테이지 데이터
var _generated := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var heroes: Dictionary = DataDb.table("heroes")
	hero_id = heroes["order"][0]
	_rng.seed = randi()
	load_game()


## 데이터 파일에 적힌 스테이지 수
func data_stage_count() -> int:
	return (DataDb.table("stages")["list"] as Array).size()


func current_stage() -> Dictionary:
	return stage_at(stage_index)


func stage_at(index: int) -> Dictionary:
	var stages: Dictionary = DataDb.table("stages")
	var list: Array = stages["list"]
	if index < list.size():
		return list[index]
	if not _generated.has(index):
		_generated[index] = StageBuilder.endless_stage(index, stages, DataDb.table("units"), DataDb.table("tuning"), _rng)
	return _generated[index]


func current_hero() -> Dictionary:
	return DataDb.table("heroes")["list"][hero_id]


## 클리어하면 다음 스테이지를 연다.
func mark_cleared(index: int) -> void:
	unlocked_stages = maxi(unlocked_stages, index + 2)


func has_next_stage() -> bool:
	return stage_index + 1 < unlocked_stages


# --- 금화 ---

## 스테이지 번호. 1-3이면 3, 자동 생성한 1-7이면 7
func stage_number(index: int) -> int:
	return index + 1


## 한 판의 금화 보상. 클리어는 스테이지 번호에 비례하고 상한이 있으며, 실패는 그 일부만 준다.
## 함정 게이트로 모은 금화는 상한과 별도로 더한다. 반환값: stage(스테이지 보상), bonus(함정 금화), total
func run_reward(cleared: bool, index: int, bonus_gold: int) -> Dictionary:
	var data: Dictionary = DataDb.table("tuning")["gold"]
	var stage_gold := mini(int(data["clear_per_stage"]) * stage_number(index), int(data["clear_cap"]))
	if not cleared:
		stage_gold = roundi(stage_gold * float(data["fail_ratio"]))
	return {"stage": stage_gold, "bonus": bonus_gold, "total": stage_gold + bonus_gold}


## 판이 끝났을 때: 금화를 주고, 클리어면 다음 스테이지를 열고, 저장한다. 반환값은 run_reward와 같다.
func finish_run(cleared: bool, bonus_gold: int) -> Dictionary:
	var reward := run_reward(cleared, stage_index, bonus_gold)
	gold += int(reward["total"])
	if cleared:
		mark_cleared(stage_index)
	save_game()
	return reward


# --- 영구 강화 ---

func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


## 다음 레벨로 올리는 비용: 기본 비용 × 다음 레벨
func upgrade_cost(id: String) -> int:
	return int(DataDb.table("upgrades")["list"][id]["cost_base"]) * (upgrade_level(id) + 1)


func can_buy_upgrade(id: String) -> bool:
	return gold >= upgrade_cost(id)


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	gold -= upgrade_cost(id)
	upgrade_levels[id] = upgrade_level(id) + 1
	save_game()
	return true


## 시설의 효과 합계(레벨 × 레벨당 값). level을 주면 그 레벨일 때의 값
func upgrade_value(id: String, level := -1) -> float:
	var entry: Dictionary = DataDb.table("upgrades")["list"][id]
	return float(entry["per_level"]) * (upgrade_level(id) if level < 0 else level)


## 병영: 시작 병력에 더할 명수
func start_count_bonus() -> int:
	return roundi(_stat_total("start_count"))


## 무기고: 공격력에 곱할 배율
func attack_mult() -> float:
	return 1.0 + _stat_total("attack")


func _stat_total(stat: String) -> float:
	var total := 0.0
	var list: Dictionary = DataDb.table("upgrades")["list"]
	for id: String in list:
		if str(list[id]["stat"]) == stat:
			total += upgrade_value(id)
	return total


# --- 저장 ---

func save_game() -> void:
	var generated := {}
	for index: int in _generated:
		generated[str(index)] = _generated[index]
	var data := {
		"version": SAVE_VERSION,
		"hero_id": hero_id,
		"stage_index": stage_index,
		"unlocked_stages": unlocked_stages,
		"gold": gold,
		"upgrades": upgrade_levels,
		"generated": generated,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("저장 파일을 열지 못했습니다: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


## 저장 파일이 없거나 읽지 못하면 처음 상태로 둔다.
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("저장 파일을 읽지 못해 처음 상태로 시작합니다")
		return
	var data: Dictionary = parsed
	var heroes: Dictionary = DataDb.table("heroes")["list"]
	if heroes.has(str(data.get("hero_id", ""))):
		hero_id = str(data["hero_id"])
	unlocked_stages = maxi(int(data.get("unlocked_stages", 1)), 1)
	stage_index = clampi(int(data.get("stage_index", 0)), 0, unlocked_stages - 1)
	gold = maxi(int(data.get("gold", 0)), 0)
	upgrade_levels = {}
	var upgrades: Dictionary = DataDb.table("upgrades")["list"]
	var saved_levels: Variant = data.get("upgrades", {})
	if saved_levels is Dictionary:
		for id: String in upgrades:
			upgrade_levels[id] = maxi(int(saved_levels.get(id, 0)), 0)
	_generated = {}
	var saved_generated: Variant = data.get("generated", {})
	if saved_generated is Dictionary:
		for key: String in saved_generated:
			if key.is_valid_int() and saved_generated[key] is Dictionary:
				_generated[int(key)] = saved_generated[key]


## 저장을 지우고 처음 상태로 되돌린다(확인용).
func reset_game() -> void:
	hero_id = DataDb.table("heroes")["order"][0]
	stage_index = 0
	unlocked_stages = 1
	gold = 0
	upgrade_levels = {}
	_generated = {}
	save_game()
