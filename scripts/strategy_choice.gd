class_name StrategyChoice
extends CanvasLayer
## 책략 3택 화면. 카드 세 장을 화면 아래쪽(엄지 영역 위)에 가로로 놓고, 카드 위쪽 어두운 판에 고른 책략과 계열 효과 진행도를 보여준다.
## 고르면 계열 효과가 켜지는 카드는 카드 아래쪽 띠로 미리 알린다. 고르면 chosen 신호를 보내고 스스로 닫힌다.

signal chosen(id: String)

const FAMILY_ICON := "res://assets/icons/family_%s.svg"

@onready var _margin: MarginContainer = %Margin
@onready var _owned_panel: PanelContainer = %OwnedPanel
@onready var _title: Label = %Title
@onready var _cards: HBoxContainer = %Cards
@onready var _owned_row: HBoxContainer = %OwnedRow
@onready var _family_row: HBoxContainer = %FamilyRow
@onready var _active_label: Label = %ActiveLabel

var _ui: Dictionary
var _card_height: float
# 카드 안 글자가 쓸 수 있는 폭(픽셀). 낱말 단위 줄바꿈에 쓴다
var _text_width: float


func setup(offer: Array[String], strategy: Strategy, pick_number: int, pick_total: int) -> void:
	_ui = DataDb.table("visual")["strategy_ui"]
	_title.text = "책략 선택 %d/%d" % [pick_number, pick_total]
	# 카드는 화면 높이의 정해진 구간(위쪽 끝 ~ 아래쪽 끝)에 놓는다
	var view_size := get_viewport().get_visible_rect().size
	_card_height = view_size.y * (float(_ui["cards_bottom"]) - float(_ui["cards_top"]))
	_margin.add_theme_constant_override("margin_bottom", int(view_size.y * (1.0 - float(_ui["cards_bottom"]))))
	var columns := offer.size()
	var outer := float(_margin.get_theme_constant("margin_left") + _margin.get_theme_constant("margin_right"))
	var gaps := float(_cards.get_theme_constant("separation") * (columns - 1))
	_text_width = (view_size.x - outer - gaps) / columns - float(_ui["card_padding"]) * 2.0 - float(_ui["border_active"]) * 2.0

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color.html(_ui["owned_back"])
	panel.set_corner_radius_all(int(_ui["corner"]))
	panel.set_content_margin_all(float(_ui["owned_padding"]))
	var skinned := UiText.panel_box("metal", float(_ui["owned_padding"]))
	_owned_panel.add_theme_stylebox_override("panel", skinned if skinned != null else panel)
	for id in offer:
		_cards.add_child(_make_card(id, strategy))
	_fill_owned(strategy)


func _make_card(id: String, strategy: Strategy) -> Button:
	var family := strategy.family_of(id)
	var color := strategy.family_color(family)
	var activates := strategy.would_activate(id)

	var card := Button.new()
	card.custom_minimum_size = Vector2(0, _card_height)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	var normal: StyleBox = _card_style(color, Color.html(_ui["card_back"]), activates)
	var hover: StyleBox = _card_style(color, Color.html(_ui["card_back_hover"]), activates)
	# 계열별 테두리 그림이 있으면 그것을 쓴다
	var border_path := str(_ui["border_texture"]) % family
	if UiText.texture(border_path) != null:
		normal = UiText.texture_box(border_path, float(_ui["border_texture_margin"]))
		var light := Color.WHITE * float(_ui["border_texture_hover"])
		light.a = 1.0
		hover = UiText.texture_box(border_path, float(_ui["border_texture_margin"]), light)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.pressed.connect(_on_card_pressed.bind(id))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := float(_ui["card_padding"])
	box.offset_left = pad
	box.offset_right = -pad
	box.offset_top = pad
	box.offset_bottom = -pad
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	# 책략 그림이 있으면 그림을, 없으면 계열 아이콘을 둔다
	var art := UiText.texture(str(_ui["art_dir"]) + id + ".png")
	var icon := _icon(family, color, float(_ui["card_art_size"] if art != null else _ui["card_icon_size"]))
	if art != null:
		icon.texture = art
		icon.modulate = Color.WHITE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	box.add_child(_label(strategy.display_name(id), int(_ui["name_font_size"]), Color.WHITE))
	box.add_child(_label("%s 계열" % strategy.family_name(family), int(_ui["family_font_size"]), color))
	var desc := _label(_wrap(strategy.description(id), int(_ui["desc_font_size"])), int(_ui["desc_font_size"]), Color.html(_ui["desc_color"]))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	# 고른 뒤의 계열 진행도. 계열 효과가 새로 켜지면 계열 색 띠로 강조한다
	var after := strategy.family_count(family) + 1
	var preview := PanelContainer.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_style := StyleBoxFlat.new()
	preview_style.set_corner_radius_all(12)
	preview_style.set_content_margin_all(10)
	preview_style.bg_color = color if activates else Color.html(_ui["preview_back"])
	preview.add_theme_stylebox_override("panel", preview_style)
	var preview_text: String
	if activates:
		preview_text = "계열 효과 발동!\n%s" % strategy.family_bonus_description(family)
	else:
		preview_text = "%s %d/%d" % [strategy.family_name(family), mini(after, strategy.bonus_count()), strategy.bonus_count()]
	var preview_font := int(_ui["preview_font_size"])
	var preview_label := _label(_wrap(preview_text, preview_font), preview_font, Color.html(_ui["preview_text_on"]) if activates else color)
	if activates:
		preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
		preview_label.add_theme_constant_override("outline_size", int(_ui["preview_outline"]))
	preview.add_child(preview_label)
	box.add_child(preview)
	return card


## 카드 아래: 고른 책략 아이콘과 이름, 계열마다 진행도
func _fill_owned(strategy: Strategy) -> void:
	var small := float(_ui["owned_icon_size"])
	if strategy.owned.is_empty():
		_owned_row.add_child(_label("아직 없음", int(_ui["owned_font_size"]), Color.html(_ui["desc_color"])))
	for id in strategy.owned:
		var family := strategy.family_of(id)
		var item := HBoxContainer.new()
		item.add_child(_icon(family, strategy.family_color(family), small))
		item.add_child(_label(strategy.display_name(id), int(_ui["owned_font_size"]), Color.WHITE))
		_owned_row.add_child(item)

	var active := strategy.active_family()
	for family in strategy.family_ids():
		var count := strategy.family_count(family)
		var color := strategy.family_color(family)
		var item := HBoxContainer.new()
		var icon := _icon(family, color, small)
		var text := _label("%s %d/%d" % [strategy.family_name(family), mini(count, strategy.bonus_count()), strategy.bonus_count()], int(_ui["owned_font_size"]), color)
		# 아직 하나도 없는 계열은 흐리게
		if count == 0:
			icon.modulate.a = float(_ui["empty_alpha"])
			text.modulate.a = float(_ui["empty_alpha"])
		item.add_child(icon)
		item.add_child(text)
		_family_row.add_child(item)
	if active != "":
		_active_label.text = "%s 계열 효과 발동 중: %s" % [strategy.family_name(active), strategy.family_bonus_description(active)]
		_active_label.add_theme_color_override("font_color", strategy.family_color(active))
	else:
		_active_label.text = "같은 계열 %d개를 모으면 계열 효과가 켜진다" % strategy.bonus_count()


## 카드 글자 폭에 맞춰 띄어쓰기 단위로만 줄을 바꾼다
func _wrap(text: String, font_size: int) -> String:
	return UiText.wrap_words(text, UiText.default_font(), font_size, _text_width)


func _card_style(border: Color, back: Color, activates: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = back
	style.border_color = border
	style.set_border_width_all(int(_ui["border_active"] if activates else _ui["border"]))
	style.set_corner_radius_all(int(_ui["corner"]))
	if activates:
		style.shadow_color = Color(border, float(_ui["glow_alpha"]))
		style.shadow_size = int(_ui["glow_size"])
	return style


func _icon(family: String, color: Color, size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(FAMILY_ICON % family)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(size, size)
	icon.modulate = color
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_card_pressed(id: String) -> void:
	chosen.emit(id)
	queue_free()
