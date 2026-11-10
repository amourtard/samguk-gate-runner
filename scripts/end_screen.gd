class_name EndScreen
extends CanvasLayer
## 판 종료 화면(돌파 또는 패배). 다시 하기를 누르면 현재 씬을 처음부터 다시 연다.
## 단계 5의 결과 화면이 생기면 그쪽으로 합친다.

@onready var _title: Label = %Title
@onready var _detail: Label = %Detail
@onready var _retry_button: Button = %RetryButton


func _ready() -> void:
	_retry_button.pressed.connect(_on_retry_pressed)


func setup(title: String, detail: String) -> void:
	_title.text = title
	_detail.text = detail


func _on_retry_pressed() -> void:
	get_tree().reload_current_scene()
