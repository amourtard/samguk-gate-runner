class_name ResultScreen
extends CanvasLayer
## 판 결과 화면. 다음 스테이지, 다시 도전, 장수 선택 중 하나를 고른다.

signal action_chosen(action: String)

@onready var _title: Label = %Title
@onready var _detail: Label = %Detail
@onready var _next_button: Button = %NextButton
@onready var _retry_button: Button = %RetryButton
@onready var _heroes_button: Button = %HeroesButton


func _ready() -> void:
	_next_button.pressed.connect(func() -> void: action_chosen.emit("next"))
	_retry_button.pressed.connect(func() -> void: action_chosen.emit("retry"))
	_heroes_button.pressed.connect(func() -> void: action_chosen.emit("heroes"))


func setup(title: String, detail: String, can_go_next: bool) -> void:
	_title.text = title
	_detail.text = detail
	_next_button.visible = can_go_next
