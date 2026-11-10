class_name Hud
extends CanvasLayer
## 병력 수, 다음 적 구성 띠, 숫자 팝업을 그린다. 계산 결과를 보여주기만 한다.

@onready var _count_label: Label = %CountLabel
@onready var _strip: HBoxContainer = %EnemyStrip
@onready var _strip_empty: Label = %StripEmpty
@onready var _status_label: Label = %StatusLabel
@onready var _popup_root: Control = %PopupRoot

var _army: Army
var _units: Dictionary
var _last_count := -1
var _strip_signature := ""
var _pop_duration: float
var _pop_scale: float
var _delta_duration: float
var _delta_rise: float
var _count_tween: Tween


func setup(army: Army, units: Dictionary, tuning: Dictionary) -> void:
	_army = army
	_units = units
	_pop_duration = float(tuning["number_popup"]["duration"])
	_pop_scale = float(tuning["number_popup"]["scale"])
	_delta_duration = float(tuning["delta_popup"]["duration"])
	_delta_rise = float(tuning["delta_popup"]["rise"])
	_army.changed.connect(_on_army_changed)
	_on_army_changed()


## 무리 머리 위 화면 좌표에 병력 수를 붙인다.
func set_count_anchor(screen_pos: Vector2) -> void:
	_count_label.position = screen_pos - _count_label.size / 2.0


## 다음 적 무리 구성을 병종별 비율 띠로 보여준다. 구성이 바뀔 때만 다시 만든다.
func set_next_enemy(pools: Array[Army]) -> void:
	var signature := ""
	for pool in pools:
		signature += "%s:%d," % [pool.unit_type, pool.count]
	if signature == _strip_signature:
		return
	_strip_signature = signature

	for child in _strip.get_children():
		child.queue_free()
	var total := 0
	for pool in pools:
		total += pool.count
	_strip_empty.visible = total == 0
	if total == 0:
		return

	for pool in pools:
		if not pool.is_alive():
			continue
		var unit: Dictionary = _units[pool.unit_type]
		var segment := ColorRect.new()
		segment.color = Color.html(unit["hud_color"])
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.size_flags_stretch_ratio = float(pool.count)
		var text := Label.new()
		text.text = "%s %d" % [unit["name"], pool.count]
		text.add_theme_font_size_override("font_size", _strip_empty.get_theme_font_size("font_size"))
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.clip_text = true
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		segment.add_child(text)
		_strip.add_child(segment)


func set_status(text: String) -> void:
	_status_label.text = text


## 게이트 통과 같은 변화량을 무리 위에 띄우고 위로 올리며 사라지게 한다.
func show_delta(text: String, screen_pos: Vector2, color: Color) -> void:
	var popup := _count_label.duplicate() as Label
	popup.unique_name_in_owner = false
	popup.text = text
	popup.modulate = color
	popup.scale = Vector2.ONE
	_popup_root.add_child(popup)
	popup.reset_size()
	popup.position = screen_pos - popup.size / 2.0
	var tween := popup.create_tween().set_parallel()
	tween.tween_property(popup, "position:y", popup.position.y - _delta_rise, _delta_duration)
	tween.tween_property(popup, "modulate:a", 0.0, _delta_duration)
	tween.chain().tween_callback(popup.queue_free)


func _on_army_changed() -> void:
	_count_label.text = "%s %d" % [_units[_army.unit_type]["name"], _army.count]
	_count_label.reset_size()
	_count_label.pivot_offset = _count_label.size / 2.0
	if _army.count == _last_count:
		return
	_last_count = _army.count
	# 병력 수가 바뀔 때마다 순간 확대했다가 원래 크기로 돌아온다
	if _count_tween != null:
		_count_tween.kill()
	_count_label.scale = Vector2.ONE * _pop_scale
	_count_tween = _count_label.create_tween()
	_count_tween.tween_property(_count_label, "scale", Vector2.ONE, _pop_duration)
