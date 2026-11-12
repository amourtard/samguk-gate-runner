extends CanvasLayer
## 타이틀 화면. 제목과 "터치해서 시작"을 보여주고, 화면을 누르면 started 신호를 보낸다.
## 브라우저는 사용자가 한 번 눌러야 소리를 낼 수 있어서 웹 빌드의 첫 화면으로도 필요하다.

signal started

var _ui: Dictionary


func _ready() -> void:
	_ui = DataDb.table("visual")["title_ui"]
	layer = 5

	# 위에서 아래로 어두워지는 바탕. 그림 파일을 받으면 이 자리에 넣는다
	var gradient := Gradient.new()
	gradient.set_color(0, Color.html(_ui["back_top"]))
	gradient.set_color(1, Color.html(_ui["back_bottom"]))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	var back := TextureRect.new()
	back.texture = texture
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.stretch_mode = TextureRect.STRETCH_SCALE
	# 배경 그림이 있으면 화면을 채워 넣는다
	var background_path := str(_ui.get("background", ""))
	if background_path != "" and ResourceLoader.exists(background_path):
		back.texture = load(background_path)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var view_size := get_viewport().get_visible_rect().size
	# 로고 그림이 있으면 그림을, 없으면 글자 제목을 쓴다
	var logo_path := str(_ui.get("logo", ""))
	if logo_path != "" and ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var logo_width := view_size.x * float(_ui["logo_width"])
		var logo_height := logo_width * logo.texture.get_height() / logo.texture.get_width()
		logo.position = Vector2((view_size.x - logo_width) / 2.0, view_size.y * float(_ui["logo_y"]))
		logo.size = Vector2(logo_width, logo_height)
		add_child(logo)
	else:
		var title := _label(_ui["title"], int(_ui["title_font_size"]), Color.html(_ui["title_color"]), int(_ui["title_outline"]))
		title.position = Vector2(0.0, view_size.y * float(_ui["title_y"]))
		title.size = Vector2(view_size.x, 0.0)
		add_child(title)

	var tagline := _label(_ui["tagline"], int(_ui["tagline_font_size"]), Color.html(_ui["tagline_color"]), int(_ui.get("tagline_outline", 0)))
	tagline.position = Vector2(0.0, view_size.y * float(_ui["tagline_y"]))
	tagline.size = Vector2(view_size.x, 0.0)
	add_child(tagline)

	var prompt := _label(_ui["prompt"], int(_ui["prompt_font_size"]), Color.WHITE, int(_ui["prompt_outline"]))
	prompt.position = Vector2(0.0, view_size.y * float(_ui["prompt_y"]))
	prompt.size = Vector2(view_size.x, 0.0)
	add_child(prompt)
	# 누르라는 글자는 천천히 깜빡인다
	var blink := prompt.create_tween().set_loops()
	blink.tween_property(prompt, "modulate:a", float(_ui["prompt_min_alpha"]), float(_ui["prompt_blink"]))
	blink.tween_property(prompt, "modulate:a", 1.0, float(_ui["prompt_blink"]))

	# 화면 어디를 눌러도 시작한다
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: started.emit())
	add_child(button)


func _label(text: String, font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label
