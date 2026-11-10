class_name StrategyChoice
extends CanvasLayer
## 책략 3택 화면. 고르면 chosen 신호를 보내고 스스로 닫힌다.

signal chosen(id: String)

@onready var _title: Label = %Title
@onready var _cards: VBoxContainer = %Cards
@onready var _card_template: Button = %CardTemplate
@onready var _owned_label: Label = %OwnedLabel


func setup(offer: Array[String], strategy: Strategy, pick_number: int, pick_total: int) -> void:
	_title.text = "책략 선택 (%d/%d)" % [pick_number, pick_total]
	for id in offer:
		var family := strategy.family_of(id)
		var card := _card_template.duplicate() as Button
		card.unique_name_in_owner = false
		card.visible = true
		card.text = "%s  [%s]\n%s" % [strategy.display_name(id), strategy.family_name(family), strategy.description(id)]
		# 계열 색으로 테두리를 칠한다
		var style := card.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.border_color = strategy.family_color(family)
		for state in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(state, style)
		card.pressed.connect(_on_card_pressed.bind(id))
		_cards.add_child(card)
	_owned_label.text = _owned_text(strategy)


func _owned_text(strategy: Strategy) -> String:
	if strategy.owned.is_empty():
		return "보유 책략 없음"
	var names: PackedStringArray = []
	for id in strategy.owned:
		names.append("%s(%s)" % [strategy.display_name(id), strategy.family_name(strategy.family_of(id))])
	var text := "보유: " + ", ".join(names)
	var family := strategy.active_family()
	if family != "":
		text += "\n%s 계열 효과: %s" % [strategy.family_name(family), strategy.family_bonus_description(family)]
	return text


func _on_card_pressed(id: String) -> void:
	chosen.emit(id)
	queue_free()
