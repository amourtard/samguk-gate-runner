class_name ResultScreen
extends CanvasLayer
## 판 결과 화면. 승리와 패배를 색과 제목으로 나누고, 도달한 구간과 남은 병력, 고른 책략을 요약한다.
## 버튼은 엄지가 닿는 아래쪽에 두고, 패배하면 "다음 스테이지"를 숨긴다.

signal action_chosen(action: String)

const UNIT_ICON := "res://assets/icons/%s.svg"
const FAMILY_ICON := "res://assets/icons/family_%s.svg"

@onready var _banner: PanelContainer = %Banner
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _summary_panel: PanelContainer = %SummaryPanel
@onready var _summary: VBoxContainer = %Summary
@onready var _next_button: Button = %NextButton
@onready var _retry_button: Button = %RetryButton
@onready var _heroes_button: Button = %HeroesButton
@onready var _upgrade_button: Button = %UpgradeButton

var _ui: Dictionary


func _ready() -> void:
	_next_button.pressed.connect(func() -> void: action_chosen.emit("next"))
	_retry_button.pressed.connect(func() -> void: action_chosen.emit("retry"))
	_heroes_button.pressed.connect(func() -> void: action_chosen.emit("heroes"))
	_upgrade_button.pressed.connect(func() -> void: action_chosen.emit("upgrades"))


## result: 한 판의 결과(cleared, count, unit_type, hero, section_text, strategy_items, gold_stage, gold_bonus)
func setup(result: Dictionary, stage_id: String, can_go_next: bool) -> void:
	_ui = DataDb.table("visual")["result_ui"]
	var cleared: bool = result["cleared"]
	var color := Color.html(_ui["win_color"] if cleared else _ui["lose_color"])

	var banner := StyleBoxFlat.new()
	banner.bg_color = Color.html(_ui["win_back"] if cleared else _ui["lose_back"])
	banner.border_color = color
	banner.set_border_width_all(8)
	banner.set_corner_radius_all(28)
	banner.set_content_margin_all(24)
	_banner.add_theme_stylebox_override("panel", banner)
	_title.text = "돌파!" if cleared else "패배"
	_title.add_theme_font_size_override("font_size", int(_ui["title_font_size"]))
	_title.add_theme_color_override("font_color", color)
	_subtitle.text = "%s   %s" % [stage_id, result["hero"]]
	_subtitle.add_theme_font_size_override("font_size", int(_ui["subtitle_font_size"]))

	_add_row("도달", [_label(result["section_text"])])
	var units: Dictionary = DataDb.table("units")
	var unit_type: String = result["unit_type"]
	_add_row("남은 병력", [_icon(UNIT_ICON % unit_type, Color.html(units[unit_type]["hud_color"])), _label("%d명" % int(result["count"]))])
	var items: Array = result["strategy_items"]
	var strategy_parts: Array[Control] = []
	if items.is_empty():
		strategy_parts.append(_label("없음"))
	for item in items:
		strategy_parts.append(_icon(FAMILY_ICON % item["family"], item["color"]))
		strategy_parts.append(_label(item["name"]))
	_add_row("책략", strategy_parts)
	var gold_label := _label("+%s" % UpgradeScreen.gold_text(int(result["gold_stage"]) + int(result["gold_bonus"])))
	gold_label.add_theme_color_override("font_color", Color.html(_ui["win_color"]))
	var gold_parts: Array[Control] = [gold_label]
	if int(result["gold_bonus"]) > 0:
		var note := _label("(함정 +%s 포함)" % UpgradeScreen.gold_text(int(result["gold_bonus"])))
		note.modulate = Color(1, 1, 1, 0.7)
		gold_parts.append(note)
	_add_row("금화", gold_parts)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color.html(_ui["summary_back"])
	panel.set_corner_radius_all(24)
	panel.set_content_margin_all(32)
	_summary_panel.add_theme_stylebox_override("panel", panel)

	for button in [_next_button, _retry_button]:
		button.custom_minimum_size = Vector2(0, float(_ui["button_height"]))
		button.add_theme_font_size_override("font_size", int(_ui["button_font_size"]))
	# 가장 자주 누를 버튼(돌파면 다음 스테이지, 패배면 다시 도전)을 맨 아래에 밝게 둔다
	_style_button(_next_button, Color.html(_ui["primary_button"]), Color.html(_ui["primary_text"]))
	_style_button(_retry_button, Color.html(_ui["primary_button"] if not cleared else _ui["secondary_button"]),
		Color.html(_ui["primary_text"] if not cleared else _ui["secondary_text"]))
	_style_button(_heroes_button, Color.html(_ui["minor_button"]), Color.html(_ui["secondary_text"]))
	_style_button(_upgrade_button, Color.html(_ui["minor_button"]), Color.html(_ui["win_color"]))
	_next_button.visible = cleared and can_go_next


func _style_button(button: Button, back: Color, text: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = back.lightened(0.12) if state == "hover" else back
		style.set_corner_radius_all(24)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text)


## 왼쪽에 항목 이름, 오른쪽에 내용
func _add_row(title: String, parts: Array[Control]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := _label(title)
	name_label.custom_minimum_size = Vector2(float(_ui["row_title_width"]), 0)
	name_label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(name_label)
	for part in parts:
		row.add_child(part)
	_summary.add_child(row)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(_ui["row_font_size"]))
	return label


func _icon(path: String, color: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var size := float(_ui["icon_size"])
	icon.custom_minimum_size = Vector2(size, size)
	icon.modulate = color
	return icon
