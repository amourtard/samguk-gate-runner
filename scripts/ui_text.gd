class_name UiText
extends RefCounted
## 화면 글자 도우미. 한국어는 글자마다 줄을 바꿀 수 있어 낱말 중간에서 끊기므로,
## 띄어쓰기 단위로만 줄을 바꾼 문자열을 만들어 자동 줄바꿈 없이 쓴다.


## 띄어쓰기 단위로 width(픽셀) 안에 들어가게 줄을 나눈다. 원래 있던 줄바꿈은 그대로 둔다.
## 낱말 하나가 width보다 길면 그 낱말만 한 줄에 둔다(넘치더라도 낱말을 자르지 않는다).
static func wrap_words(text: String, font: Font, font_size: int, width: float) -> String:
	var lines: PackedStringArray = []
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var candidate := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				lines.append(line)
				line = word
			else:
				line = candidate
		lines.append(line)
	return "\n".join(lines)


## 프로젝트 Theme의 기본 글꼴
static func default_font() -> Font:
	var project_theme := ThemeDB.get_project_theme()
	if project_theme != null and project_theme.default_font != null:
		return project_theme.default_font
	return ThemeDB.fallback_font


## 그림을 읽는다. 없거나 아직 가져오지 않았으면 null을 돌려준다(부르는 쪽이 그림 없는 모양으로 그린다).
static func texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 테두리 그림으로 만든 9칸 늘림 상자. 그림이 없으면 null.
static func texture_box(path: String, margin: float, tint := Color.WHITE) -> StyleBoxTexture:
	var image := texture(path)
	if image == null:
		return null
	var box := StyleBoxTexture.new()
	box.texture = image
	box.set_texture_margin_all(margin)
	box.modulate_color = tint
	return box


## 버튼에 테두리 그림을 입힌다. kind는 visual.json의 ui_skin.buttons 항목 이름이다. 그림이 없으면 아무것도 바꾸지 않는다.
static func skin_button(button: Button, kind: String) -> void:
	var skin: Dictionary = DataDb.table("visual")["ui_skin"]
	var entry: Dictionary = skin["buttons"][kind]
	var margin := float(skin["margin"])
	if texture(str(entry["texture"])) == null:
		return
	var tints := {
		"normal": Color.WHITE,
		"focus": Color.WHITE,
		"hover": Color.WHITE * float(skin["hover_light"]),
		"pressed": Color.WHITE * float(skin["pressed_dark"]),
		"disabled": Color.html(skin["disabled_tint"]),
	}
	for state: String in tints:
		var tint: Color = tints[state]
		tint.a = 1.0
		button.add_theme_stylebox_override(state, texture_box(str(entry["texture"]), margin, tint))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.html(entry["text"]))


## 화면 전체를 덮는 배경 그림과 그 위의 어두운 막을 parent의 index 자리에 넣는다. name은 ui_skin.backgrounds 항목 이름이다.
static func add_backdrop(parent: Node, name: String, index: int) -> void:
	var skin: Dictionary = DataDb.table("visual")["ui_skin"]
	var entry: Dictionary = skin["backgrounds"][name]
	var image := texture(str(entry["texture"]))
	if image == null:
		return
	var picture := TextureRect.new()
	picture.texture = image
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, float(entry["dim"]))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	parent.move_child(picture, index)
	parent.add_child(dim)
	parent.move_child(dim, index + 1)
