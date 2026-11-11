class_name HeroSelect
extends CanvasLayer
## 장수 선택 화면. 장수와 도전할 스테이지를 고르고 출전한다.
## 스테이지는 1-1부터 순서대로 열리며, 열리지 않은 스테이지는 누를 수 없다.

signal start_requested

@onready var _hero_list: VBoxContainer = %HeroList
@onready var _hero_template: Button = %HeroTemplate
@onready var _stage_row: HFlowContainer = %StageRow
@onready var _stage_template: Button = %StageTemplate
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	var heroes: Dictionary = DataDb.table("heroes")
	var units: Dictionary = DataDb.table("units")
	var hero_group := ButtonGroup.new()
	for hero_id in heroes["order"]:
		var hero: Dictionary = heroes["list"][hero_id]
		var card := _hero_template.duplicate() as Button
		card.unique_name_in_owner = false
		card.visible = true
		card.button_group = hero_group
		card.text = "%s   %s %d명\n%s" % [hero["name"], units[hero["unit"]]["name"], int(hero["count"]),
			Strategy.fill_template(hero["skill_desc"], hero["skill"])]
		card.button_pressed = hero_id == GameState.hero_id
		card.pressed.connect(func() -> void: GameState.hero_id = hero_id)
		_hero_list.add_child(card)

	var stage_group := ButtonGroup.new()
	# 데이터 스테이지(1-1~1-5)는 모두 보여주고, 그 뒤 자동 생성 스테이지는 열린 것만 보여준다
	var shown_count := maxi(GameState.data_stage_count(), GameState.unlocked_stages)
	GameState.stage_index = clampi(GameState.stage_index, 0, GameState.unlocked_stages - 1)
	for i in shown_count:
		var button := _stage_template.duplicate() as Button
		button.unique_name_in_owner = false
		button.visible = true
		button.button_group = stage_group
		button.text = GameState.stage_at(i)["id"]
		button.disabled = i >= GameState.unlocked_stages
		button.button_pressed = i == GameState.stage_index
		button.pressed.connect(func() -> void: GameState.stage_index = i)
		_stage_row.add_child(button)

	_start_button.pressed.connect(func() -> void: start_requested.emit())
