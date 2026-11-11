extends Node
## 자동 로드. data 폴더의 JSON을 읽어 제공한다.

const DATA_DIR := "res://data/"
const TABLE_NAMES: Array[String] = ["units", "gates", "strategies", "heroes", "stages", "upgrades", "tuning", "visual"]

var _tables: Dictionary = {}


func _ready() -> void:
	for table_name in TABLE_NAMES:
		var path := DATA_DIR + table_name + ".json"
		# 아직 만들지 않은 데이터 파일은 건너뛴다
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_tables[table_name] = parsed
		else:
			push_error("데이터 파일을 읽지 못했습니다: " + path)


func table(table_name: String) -> Dictionary:
	if not _tables.has(table_name):
		push_error("데이터 테이블이 없습니다: " + table_name)
		return {}
	return _tables[table_name]
