class_name SkillGauge
extends Control
## 장수 기술의 충전 정도를 둥근 게이지로 그린다. 가운데에 장수 이름을 쓴다.

var _ratio := 0.0
var _active := false
var _text := ""
var _radius := 50.0
var _width := 10.0
var _back := Color.BLACK
var _fill := Color.WHITE
var _active_color := Color.WHITE
var _font_size := 32


func setup(text: String, hud: Dictionary) -> void:
	_text = text
	_radius = float(hud["gauge_radius"])
	_width = float(hud["gauge_width"])
	_back = Color.html(hud["gauge_back"])
	_fill = Color.html(hud["gauge_fill"])
	_active_color = Color.html(hud["gauge_active"])
	_font_size = int(hud["gauge_font_size"])
	custom_minimum_size = Vector2.ONE * _radius * 2.0
	queue_redraw()


## ratio: 0~1 충전 정도, active: 효과가 켜져 있는가
func set_state(ratio: float, active: bool) -> void:
	if is_equal_approx(ratio, _ratio) and active == _active:
		return
	_ratio = ratio
	_active = active
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, _radius, _back)
	var color := _active_color if _active else _fill
	var ratio := 1.0 if _active else _ratio
	if ratio > 0.0:
		draw_arc(center, _radius - _width / 2.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 48, color, _width, true)
	var font := get_theme_default_font()
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, _font_size)
	var baseline := center + Vector2(-text_size.x / 2.0, font.get_ascent(_font_size) - text_size.y / 2.0)
	draw_string_outline(font, baseline, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, 8, Color.BLACK)
	draw_string(font, baseline, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color if ratio >= 1.0 else Color.WHITE)
