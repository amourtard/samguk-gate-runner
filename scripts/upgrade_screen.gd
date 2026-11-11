class_name UpgradeScreen
extends CanvasLayer
## 강화 화면. 금화로 영구 강화(병영, 무기고)를 올린다. 다른 화면 위에 겹쳐 띄우고 닫으면 사라진다.
## 계산과 저장은 GameState가 맡고 여기서는 보여주고 누른 것을 넘기기만 한다.

signal closed

var _ui: Dictionary
var _gold_label: Label
# 시설 이름 → {"level": Label, "effect": Label, "button": Button}
var _cards := {}


func _ready() -> void:
	_ui = DataDb.table("visual")["upgrade_ui"]

	var back := ColorRect.new()
	back.color = Color.html(_ui["back"])
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	margin.add_theme_constant_override("margin_top", 140)
	margin.add_theme_constant_override("margin_bottom", 120)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 36)
	margin.add_child(box)

	box.add_child(_label("강화", int(_ui["title_font_size"]), HORIZONTAL_ALIGNMENT_CENTER))
	_gold_label = _label("", int(_ui["gold_font_size"]), HORIZONTAL_ALIGNMENT_CENTER)
	_gold_label.add_theme_color_override("font_color", Color.html(_ui["gold_color"]))
	box.add_child(_gold_label)

	# 카드와 버튼은 엄지가 닿는 아래쪽에 모은다
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var upgrades: Dictionary = DataDb.table("upgrades")
	for id: String in upgrades["order"]:
		box.add_child(_make_card(id, upgrades["list"][id]))

	var close := Button.new()
	close.text = "닫기"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, float(_ui["close_height"]))
	close.add_theme_font_size_override("font_size", int(_ui["close_font_size"]))
	style_button(close, Color.html(_ui["close_button"]), Color.html(_ui["close_text"]), int(_ui["corner"]))
	close.pressed.connect(_on_close)
	box.add_child(close)

	_refresh()


## 다른 화면의 "강화" 버튼이 같은 모양을 쓰도록 열어 둔다.
static func style_button(button: Button, back: Color, text: Color, corner: int) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = back.lightened(0.12) if state == "hover" else back
		style.set_corner_radius_all(corner)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, text)


## 천 단위 쉼표를 넣은 금화 글자
static func gold_text(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


func _make_card(id: String, entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.html(_ui["card_back"])
	style.border_color = Color.html(_ui["card_border"])
	style.set_border_width_all(int(_ui["card_border_width"]))
	style.set_corner_radius_all(int(_ui["corner"]))
	style.set_content_margin_all(float(_ui["card_padding"]))
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := _label(entry["name"], int(_ui["name_font_size"]), HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var level := _label("", int(_ui["level_font_size"]), HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(level)

	var effect := _label("", int(_ui["effect_font_size"]), HORIZONTAL_ALIGNMENT_LEFT)
	effect.add_theme_color_override("font_color", Color.html(_ui["effect_color"]))
	box.add_child(effect)

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, float(_ui["buy_height"]))
	button.add_theme_font_size_override("font_size", int(_ui["buy_font_size"]))
	button.pressed.connect(_on_buy.bind(id))
	box.add_child(button)

	_cards[id] = {"level": level, "effect": effect, "button": button}
	return panel


func _on_buy(id: String) -> void:
	if GameState.buy_upgrade(id):
		_refresh()


func _on_close() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	_gold_label.text = "금화 %s" % gold_text(GameState.gold)
	var list: Dictionary = DataDb.table("upgrades")["list"]
	for id: String in _cards:
		var card: Dictionary = _cards[id]
		var entry: Dictionary = list[id]
		var level := GameState.upgrade_level(id)
		(card["level"] as Label).text = "레벨 %d" % level
		(card["effect"] as Label).text = "%s  →  %s" % [_effect_text(id, entry, level), _effect_text(id, entry, level + 1)]
		var button: Button = card["button"]
		var affordable := GameState.can_buy_upgrade(id)
		button.text = "올리기  금화 %s" % gold_text(GameState.upgrade_cost(id))
		button.disabled = not affordable
		style_button(button,
			Color.html(_ui["buy_button"] if affordable else _ui["buy_disabled"]),
			Color.html(_ui["buy_text"] if affordable else _ui["buy_disabled_text"]), int(_ui["corner"]))


## 그 레벨일 때의 효과 문구. 예: "시작 병력 +4명", "공격력 +10%"
func _effect_text(id: String, entry: Dictionary, level: int) -> String:
	var value := GameState.upgrade_value(id, level)
	if bool(entry.get("percent", false)):
		value *= 100.0
	return str(entry["effect"]).replace("{value}", str(roundi(value)))


func _label(text: String, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	return label
