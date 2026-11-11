class_name Hud
extends CanvasLayer
## 병력 수, 다음 적 구성 띠, 스테이지와 구간, 장수 기술 게이지, 고른 책략, 숫자 팝업을 그린다.
## 계산 결과를 보여주기만 한다. 개발용 글자는 디버그 표시로 묶어 기본으로 숨긴다.

const UNIT_ICON := "res://assets/icons/%s.svg"
const FAMILY_ICON := "res://assets/icons/family_%s.svg"

@onready var _count_box: HBoxContainer = %CountBox
@onready var _count_icon: TextureRect = %CountIcon
@onready var _count_label: Label = %CountLabel
@onready var _stage_label: Label = %StageLabel
@onready var _strip_back: Panel = %StripBack
@onready var _strip_title: Label = %StripTitle
@onready var _strip: HBoxContainer = %EnemyStrip
@onready var _strip_empty: Label = %StripEmpty
@onready var _skill_gauge: SkillGauge = %SkillGauge
@onready var _strategy_row: HBoxContainer = %StrategyRow
@onready var _status_label: Label = %StatusLabel
@onready var _popup_root: Control = %PopupRoot
# 피해 숫자는 병력 수와 변화량 팝업보다 아래 층에 그려 가리지 않게 한다
@onready var _damage_root: Control = %DamageRoot

var _army: Army
var _units: Dictionary
var _hud: Dictionary
var _last_count := -1
var _last_unit := ""
var _strip_signature := ""
var _strategy_signature := ""
var _pop_duration: float
var _pop_scale: float
var _delta_duration: float
var _delta_rise: float
var _count_tween: Tween
var _damage_data: Dictionary
var _damage_color: Color


func setup(army: Army, units: Dictionary, tuning: Dictionary, visual: Dictionary, hero_name: String) -> void:
	_army = army
	_units = units
	_hud = visual["hud"]
	_damage_data = tuning["damage_number"]
	_damage_color = Color.html(_damage_data["color"])
	_pop_duration = float(tuning["number_popup"]["duration"])
	_pop_scale = float(tuning["number_popup"]["scale"])
	_delta_duration = float(tuning["delta_popup"]["duration"])
	_delta_rise = float(tuning["delta_popup"]["rise"])

	_count_label.add_theme_font_size_override("font_size", int(_hud["count_font_size"]))
	_count_label.add_theme_constant_override("outline_size", int(_hud["count_outline"]))
	var icon_size := float(_hud["count_icon_size"])
	_count_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	_stage_label.add_theme_font_size_override("font_size", int(_hud["stage_font_size"]))
	_strip_title.add_theme_font_size_override("font_size", int(_hud["stage_font_size"]))
	_strip_empty.add_theme_font_size_override("font_size", int(_hud["strip_font_size"]))
	var back := StyleBoxFlat.new()
	back.bg_color = Color.html(_hud["strip_color"])
	back.set_corner_radius_all(int(_hud["strip_corner"]))
	_strip_back.add_theme_stylebox_override("panel", back)
	_skill_gauge.setup(hero_name, _hud)
	_status_label.visible = bool(visual["debug"]["overlay_visible"])

	_army.changed.connect(_on_army_changed)
	_on_army_changed()


## 무리 머리 위 화면 좌표에 병력 수를 붙인다.
func set_count_anchor(screen_pos: Vector2) -> void:
	_count_box.position = screen_pos - _count_box.size / 2.0


func set_stage_text(text: String) -> void:
	_stage_label.text = text


## ratio: 기술 충전 정도(0~1), active: 효과가 켜져 있는가
func set_skill(ratio: float, active: bool) -> void:
	_skill_gauge.set_state(ratio, active)


## 고른 책략을 계열 아이콘 줄로 보여준다. families: 책략마다 {"family", "color"}
func set_strategies(entries: Array[Dictionary]) -> void:
	var signature := str(entries)
	if signature == _strategy_signature:
		return
	_strategy_signature = signature
	for child in _strategy_row.get_children():
		child.queue_free()
	var size := float(_hud["strategy_icon_size"])
	for entry in entries:
		var icon := TextureRect.new()
		icon.texture = load(FAMILY_ICON % entry["family"])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(size, size)
		icon.modulate = entry["color"]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_strategy_row.add_child(icon)


## 다음 적 무리 구성을 병종 아이콘과 비율 띠로 보여준다. 구성이 바뀔 때만 다시 만든다.
func set_next_enemy(pools: Array[Army]) -> void:
	var signature := ""
	for pool in pools:
		signature += "%s:%d:%d," % [pool.unit_type, pool.count, ceili(pool.total_health)]
	if signature == _strip_signature:
		return
	_strip_signature = signature

	for child in _strip.get_children():
		child.queue_free()
	var total := 0
	for pool in pools:
		total += pool.count
	_strip_empty.visible = total == 0
	_strip.visible = total > 0
	if total == 0:
		return

	var icon_size := float(_hud["strip_icon_size"])
	for pool in pools:
		if not pool.is_alive():
			continue
		var unit: Dictionary = _units[pool.unit_type]
		var color := Color.html(unit["hud_color"])
		# 무리 수에 비례한 폭. 아래에 병종 색 막대를 깔아 비율이 보이게 한다
		var segment := VBoxContainer.new()
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.size_flags_stretch_ratio = float(pool.count)
		segment.alignment = BoxContainer.ALIGNMENT_CENTER
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.add_theme_constant_override("separation", 2)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = load(UNIT_ICON % pool.unit_type)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.modulate = color
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var text := Label.new()
		# 보스처럼 체력으로 보여주는 항목
		if unit.get("show_health", false):
			text.text = "%d/%d" % [ceili(pool.total_health), ceili(pool.unit_health)]
		else:
			text.text = str(pool.count)
		text.add_theme_font_size_override("font_size", int(_hud["strip_font_size"]))
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(text)
		segment.add_child(row)
		var bar := ColorRect.new()
		bar.color = color
		bar.custom_minimum_size = Vector2(0, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.add_child(bar)
		_strip.add_child(segment)


func set_status(text: String) -> void:
	_status_label.text = text


func toggle_debug() -> void:
	_status_label.visible = not _status_label.visible


## 게이트 통과 같은 변화량을 무리 위에 띄우고 위로 올리며 사라지게 한다.
func show_delta(text: String, screen_pos: Vector2, color: Color) -> void:
	var popup := Label.new()
	popup.text = text
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", int(_hud["delta_font_size"]))
	popup.add_theme_constant_override("outline_size", int(_hud["count_outline"]))
	popup.modulate = color
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_root.add_child(popup)
	popup.reset_size()
	popup.position = screen_pos - popup.size / 2.0
	var tween := popup.create_tween().set_parallel()
	tween.tween_property(popup, "position:y", popup.position.y - _delta_rise, _delta_duration)
	tween.tween_property(popup, "modulate:a", 0.0, _delta_duration)
	tween.chain().tween_callback(popup.queue_free)


## 피해 숫자를 작은 글자로 띄우고 위로 올리며 사라지게 한다. 표시 배율은 호출하는 쪽이 곱한다.
func show_damage(value: int, screen_pos: Vector2) -> void:
	var label := Label.new()
	label.text = str(value)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", int(_damage_data["font_size"]))
	label.add_theme_constant_override("outline_size", int(_damage_data["outline_size"]))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.modulate = _damage_color
	_damage_root.add_child(label)
	label.reset_size()
	label.position = screen_pos - label.size / 2.0
	var duration := float(_damage_data["duration"])
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - float(_damage_data["rise"]), duration)
	tween.tween_property(label, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(label.queue_free)


func _on_army_changed() -> void:
	if _army.unit_type != _last_unit:
		_last_unit = _army.unit_type
		_count_icon.texture = load(UNIT_ICON % _army.unit_type)
	_count_label.text = str(_army.count)
	_count_box.reset_size()
	_count_box.pivot_offset = _count_box.size / 2.0
	if _army.count == _last_count:
		return
	_last_count = _army.count
	# 병력 수가 바뀔 때마다 순간 확대했다가 원래 크기로 돌아온다
	if _count_tween != null:
		_count_tween.kill()
	_count_box.scale = Vector2.ONE * _pop_scale
	_count_tween = _count_box.create_tween()
	_count_tween.tween_property(_count_box, "scale", Vector2.ONE, _pop_duration)
