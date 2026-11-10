class_name PickLog
extends RefCounted
## 게이트와 책략 선택, 판 결과를 user:// 아래 CSV로 쌓는다.
## 한 줄이 사건 하나이고, 같은 판은 run_id로 묶는다.

const PATH := "user://pick_log.csv"
const HEADER := ["time", "run_id", "stage", "hero", "kind", "section", "choice", "not_chosen", "unit", "count_before", "count_after", "strategies"]

var _run_id: String
var _stage: String
var _hero: String


func _init(stage_id: String, hero_id: String) -> void:
	_run_id = Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	_stage = stage_id
	_hero = hero_id
	_ensure_header()


## kind는 gate, strategy, result 중 하나다.
func write(kind: String, section: int, choice: String, not_chosen: String, unit: String, count_before: int, count_after: int, strategies: Array[String]) -> void:
	var file := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if file == null:
		push_error("기록 파일을 열지 못했습니다: " + PATH)
		return
	file.seek_end()
	file.store_csv_line(PackedStringArray([
		Time.get_datetime_string_from_system(),
		_run_id,
		_stage,
		_hero,
		kind,
		str(section),
		choice,
		not_chosen,
		unit,
		str(count_before),
		str(count_after),
		"|".join(strategies),
	]))


static func absolute_path() -> String:
	return ProjectSettings.globalize_path(PATH)


## 열 구성이 바뀐 옛 기록 파일은 이름을 바꿔 남기고 새 파일을 시작한다.
func _ensure_header() -> void:
	if FileAccess.file_exists(PATH):
		var existing := FileAccess.open(PATH, FileAccess.READ)
		var first_line := existing.get_csv_line() if existing != null else PackedStringArray()
		existing = null
		if first_line == PackedStringArray(HEADER):
			return
		var backup := PATH.get_basename() + "_old_" + _run_id + ".csv"
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(backup))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("기록 파일을 만들지 못했습니다: " + PATH)
		return
	file.store_csv_line(PackedStringArray(HEADER))
