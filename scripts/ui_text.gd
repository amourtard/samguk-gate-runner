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
