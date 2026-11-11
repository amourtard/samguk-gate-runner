class_name HeroSelect
extends CanvasLayer
## 장수 선택 화면. 장수 카드(깃발, 이름, 시작 병종과 병력, 기술)와 도전할 스테이지를 고르고 출전한다.
## 스테이지는 한 줄에 놓고 깬 곳, 열린 곳, 잠긴 곳을 색으로 나눈다. 1-1부터 순서대로 열린다.
## 화면에는 5개가 보이고, 1-6 이후가 열리면 줄을 좌우로 밀어서 고른다.

signal start_requested
signal upgrades_requested

const UNIT_ICON := "res://assets/icons/%s.svg"

@onready var _hero_list: VBoxContainer = %HeroList
@onready var _stage_scroll: ScrollContainer = %StageScroll
@onready var _stage_grid: GridContainer = %StageGrid
@onready var _start_button: Button = %StartButton

var _ui: Dictionary


func _ready() -> void:
	var visual: Dictionary = DataDb.table("visual")
	_ui = visual["hero_ui"]
	var heroes: Dictionary = DataDb.table("heroes")
	var units: Dictionary = DataDb.table("units")
	var hero_group := ButtonGroup.new()
	for hero_id in heroes["order"]:
		var card := _make_hero_card(hero_id, heroes["list"][hero_id], units)
		card.button_group = hero_group
		card.button_pressed = hero_id == GameState.hero_id
		card.pressed.connect(func() -> void: GameState.hero_id = hero_id)
		_hero_list.add_child(card)

	var stage_group := ButtonGroup.new()
	var selected_button: Button
	# 데이터 스테이지(1-1~1-5)는 모두 보여주고, 그 뒤 자동 생성 스테이지는 열린 것만 보여준다
	var shown_count := maxi(GameState.data_stage_count(), GameState.unlocked_stages)
	GameState.stage_index = clampi(GameState.stage_index, 0, GameState.unlocked_stages - 1)
	# 한 줄로 놓는다. 화면 폭에 정해진 개수만 보이고 나머지는 좌우로 밀어서 본다
	_stage_grid.columns = shown_count
	_stage_scroll.custom_minimum_size = Vector2(0, float(_ui["stage_height"]))
	for i in shown_count:
		var button := _make_stage_button(i)
		button.button_group = stage_group
		button.button_pressed = i == GameState.stage_index
		button.pressed.connect(func() -> void: GameState.stage_index = i)
		_stage_grid.add_child(button)
		if i == GameState.stage_index:
			selected_button = button
	_show_selected_stage(selected_button)

	for state in ["normal", "hover", "pressed", "focus"]:
		var style := _style(Color.html(_ui["start_button"]), Color.html(_ui["start_button"]), 0)
		if state == "hover":
			style.bg_color = style.bg_color.lightened(0.12)
		_start_button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_start_button.add_theme_color_override(state, Color.html(_ui["start_text"]))
	_start_button.pressed.connect(func() -> void: start_requested.emit())
	_add_upgrade_row()


## 고른 스테이지가 화면에 보이도록 줄을 민다. 배치가 끝난 다음 프레임에 해야 위치가 맞는다.
func _show_selected_stage(button: Button) -> void:
	if button == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_stage_scroll.ensure_control_visible(button)


## 출전 버튼 바로 위에 보유 금화와 강화 화면으로 가는 버튼을 둔다.
func _add_upgrade_row() -> void:
	var view: Dictionary = DataDb.table("visual")["upgrade_ui"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var gold := _label("금화 %s" % UpgradeScreen.gold_text(GameState.gold), int(view["entry_font_size"]))
	gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold.add_theme_color_override("font_color", Color.html(view["gold_color"]))
	row.add_child(gold)
	var button := Button.new()
	button.text = "강화"
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, float(view["entry_height"]))
	button.add_theme_font_size_override("font_size", int(view["entry_font_size"]))
	UpgradeScreen.style_button(button, Color.html(view["entry_button"]), Color.html(view["entry_text"]), int(view["corner"]))
	button.pressed.connect(func() -> void: upgrades_requested.emit())
	row.add_child(button)
	var parent := _start_button.get_parent()
	parent.add_child(row)
	parent.move_child(row, _start_button.get_index())


func _make_hero_card(hero_id: String, hero: Dictionary, units: Dictionary) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, float(_ui["card_height"]))
	var normal := _style(Color.html(_ui["card_back"]), Color.html(_ui["border"]), int(_ui["border_width"]))
	var selected := _style(Color.html(_ui["card_back_selected"]), Color.html(_ui["border_selected"]), int(_ui["border_width_selected"]))
	for state in ["normal", "hover"]:
		card.add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		card.add_theme_stylebox_override(state, selected)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28
	row.offset_right = -28
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# 달리기 화면과 같은 장수 모델(시작 병종 모델, 장수 색, 이름 깃발)을 작은 3D 화면에 그린다
	row.add_child(_make_model_view(hero_id, hero["unit"]))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 8)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name_label := _label(hero["name"], int(_ui["name_font_size"]))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(name_label)

	var unit_row := HBoxContainer.new()
	unit_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = load(UNIT_ICON % hero["unit"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_size := float(_ui["unit_icon_size"])
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.modulate = Color.html(units[hero["unit"]]["hud_color"])
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_row.add_child(icon)
	# 병영 강화로 늘어난 시작 병력을 더해 보여준다
	unit_row.add_child(_label("%s %d명" % [units[hero["unit"]]["name"], int(hero["count"]) + GameState.start_count_bonus()], int(_ui["info_font_size"])))
	info.add_child(unit_row)

	# 기술: 이름과 쉬운 한 줄 설명, 그 아래 수치를 작은 글자로
	var text_width := get_viewport().get_visible_rect().size.x - float(_ui["text_width_margin"])
	var skill_font := int(_ui["skill_font_size"])
	var skill := _label(UiText.wrap_words("%s - %s" % [hero["skill_name"], hero["skill_short"]], UiText.default_font(), skill_font, text_width), skill_font)
	skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	skill.add_theme_color_override("font_color", Color.html(_ui["skill_color"]))
	info.add_child(skill)
	var detail_font := int(_ui["skill_detail_font_size"])
	var detail := _label(UiText.wrap_words("(%s)" % Strategy.fill_template(hero["skill_desc"], hero["skill"]), UiText.default_font(), detail_font, text_width), detail_font)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail.modulate = Color(1, 1, 1, 0.7)
	info.add_child(detail)
	return card


## 장수 모델 미리보기. 자기만의 3D 세계를 가진 작은 화면에 카메라, 빛, 장수 모델을 둔다
func _make_model_view(hero_id: String, unit_type: String) -> SubViewportContainer:
	var size_data: Array = _ui["model_view_size"]
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(float(size_data[0]), float(size_data[1]))
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)

	var environment := Environment.new()
	# 어두운 장수(장비)가 카드에 묻히지 않게 모델 뒤에 밝은 바탕을 깐다
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.html(_ui["model_back"])
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = float(_ui["model_ambient"])
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)

	var light := DirectionalLight3D.new()
	var angles: Array = _ui["model_light"]
	light.rotation_degrees = Vector3(float(angles[0]), float(angles[1]), float(angles[2]))
	viewport.add_child(light)

	var hero_view := HeroView.new()
	viewport.add_child(hero_view)
	hero_view.setup(hero_id, unit_type, DataDb.table("visual"))

	var camera := Camera3D.new()
	camera.fov = float(_ui["model_fov"])
	viewport.add_child(camera)
	# 아직 화면 트리 밖이라 look_at 대신 변환을 직접 만든다
	var eye := ModelBuilder.to_vector3(_ui["model_camera_pos"])
	camera.transform = Transform3D(Basis.looking_at(ModelBuilder.to_vector3(_ui["model_look_at"]) - eye, Vector3.UP), eye)
	return container


## 스테이지 버튼. 깬 곳(돌파), 열린 곳(도전), 잠긴 곳(잠김)을 배경색과 아래 글자로 나눈다
func _make_stage_button(index: int) -> Button:
	var cleared := index < GameState.unlocked_stages - 1
	var locked := index >= GameState.unlocked_stages
	var back_key := "stage_cleared" if cleared else ("stage_locked" if locked else "stage_open")
	var back := Color.html(_ui[back_key])

	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = locked
	button.custom_minimum_size = Vector2(float(_ui["stage_width"]), float(_ui["stage_height"]))
	var normal := _style(back, back.lightened(0.15), int(_ui["border_width"]))
	var selected := _style(back.lightened(0.1), Color.html(_ui["border_selected"]), int(_ui["border_width_selected"]))
	for state in ["normal", "hover", "disabled"]:
		button.add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, selected)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var text_color := Color.html(_ui["stage_locked_text"]) if locked else Color.WHITE
	var id_label := _label(GameState.stage_at(index)["id"], int(_ui["stage_font_size"]))
	id_label.add_theme_color_override("font_color", text_color)
	box.add_child(id_label)
	var sub := _label("돌파" if cleared else ("잠김" if locked else "도전"), int(_ui["stage_sub_font_size"]))
	sub.add_theme_color_override("font_color", text_color)
	box.add_child(sub)
	return button


func _style(back: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = back
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(int(_ui["corner"]))
	return style


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
