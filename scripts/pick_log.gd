class_name PickLog
extends RefCounted
## 게이트와 책략 선택, 판 결과를 user:// 아래 CSV로 쌓는다.
## 한 줄이 사건 하나이고, 같은 판은 run_id로 묶는다.

const PATH := "user://pick_log.csv"
const HEADER := ["time", "run_id", "kind", "section", "choice", "not_chosen", "unit", "count_before", "count_after", "strategies"]

var _run_id: String


func _init() -> void:
	_run_id = Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	if not FileAccess.file_exists(PATH):
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		if file == null:
			push_error("기록 파일을 만들지 못했습니다: " + PATH)
			return
		file.store_csv_line(PackedStringArray(HEADER))


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
