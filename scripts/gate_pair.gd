class_name GatePair
extends Node3D
## 좌우 게이트 한 쌍의 표시. 효과 계산은 Gate가 맡고 여기서는 그리기만 한다.
## 노드의 z 위치가 통과선이다. 아군 중심이 왼쪽 절반이면 왼쪽 게이트를 고른 것으로 본다.
## 나무 기둥 세 개와 위쪽 들보로 도로 폭 전체를 막고, 좌우 칸에 반투명 색 판과 아이콘, 글자를 세운다.

const ICON_DIR := "res://assets/icons/gate_%s.svg"

var left_spec: Dictionary
var right_spec: Dictionary
var passed := false
# 이 게이트가 놓인 구간(1부터). 게이트를 바꿔 끼울 때 구간 제한을 보는 데 쓴다
var section := 1

var _view: Dictionary
var _gates: Dictionary
var _units: Dictionary
var _half_road: float
var _text_visible := true
# 지금 선택될 칸(0 왼쪽, 1 오른쪽). 표시하지 않을 때는 -1
var _preview_side := -1
# 칸별 표시 노드: {"panel": MeshInstance3D, "color": 판의 원래 색}
var _sides: Array[Dictionary] = []
# 칸을 다시 그릴 때 지울 노드(판, 받침판, 글자, 아이콘)
var _side_nodes: Array[Node] = []
var _wood_material: StandardMaterial3D
var _text_nodes: Array[Node3D] = []
var _plates: Array[StandardMaterial3D] = []


func setup(p_left: Dictionary, p_right: Dictionary, gates: Dictionary, units: Dictionary, tuning: Dictionary, visual: Dictionary) -> void:
	left_spec = p_left
	right_spec = p_right
	_view = visual["gate"]
	_gates = gates
	_units = units
	var road_width := float(tuning["road"]["width"])
	_half_road = road_width / 2.0
	_add_frame(road_width)
	_build_sides()


## 좌우 칸(판, 받침판, 아이콘, 글자)을 만든다. 문구가 바뀌면 다시 부른다.
func _build_sides() -> void:
	for node in _side_nodes:
		node.queue_free()
	_side_nodes.clear()
	_text_nodes.clear()
	_plates.clear()
	_sides.clear()

	var texts := [_texts(left_spec, _gates, _units), _texts(right_spec, _gates, _units)]
	var panel_width := _half_road - float(_view["post_size"])
	var font_size := int(_view["font_size"])
	var main_width := panel_width * float(_view["main_width_ratio"])
	# 주 효과: 긴 쪽은 판 폭의 정해진 비율을 채우는 크기, 단 글자 높이 상한을 넘지 않는다
	var height_cap := float(_view["main_max_height"]) / (_font().get_height(font_size))
	var long_pixel := height_cap
	for side in texts:
		long_pixel = minf(long_pixel, _pixel_for_width(side["main"], font_size, main_width))
	# 짧은 쪽("+10", "×2")은 칸마다 따로 키우되 긴 쪽 글자 크기의 정해진 배수를 넘지 않는다
	var short_cap := minf(long_pixel * float(_view["main_short_scale_max"]), height_cap)
	var main_pixels: Array[float] = []
	for side in texts:
		main_pixels.append(minf(_pixel_for_width(side["main"], font_size, main_width), short_cap))
	# 대가는 좌우 같은 크기로, 긴 쪽 주 효과의 정해진 비율. 판 폭을 넘으면 줄인다
	var cost_pixel := long_pixel * float(_view["cost_ratio"])
	for side in texts:
		cost_pixel = minf(cost_pixel, _pixel_for_width(side["cost"], font_size, panel_width * float(_view["text_width_limit"])))
	if cost_pixel < long_pixel * float(_view["cost_min_ratio"]):
		push_warning("게이트 대가 글자가 주 효과의 정해진 비율보다 작다: %s / %s" % [texts[0]["cost"], texts[1]["cost"]])
	_add_side(left_spec, texts[0], -_half_road / 2.0, panel_width, main_pixels[0], cost_pixel, _gates)
	_add_side(right_spec, texts[1], _half_road / 2.0, panel_width, main_pixels[1], cost_pixel, _gates)
	set_text_visible(_text_visible)
	_apply_preview()


func spec_for_x(x: float) -> Dictionary:
	return left_spec if side_for_x(x) == 0 else right_spec


## 무리 중심 x로 고르게 될 칸. 0 왼쪽, 1 오른쪽. 정확히 중앙이면 왼쪽이다
static func side_for_x(x: float) -> int:
	return 0 if x <= 0.0 else 1


## 병종 전환 칸의 대상이 지금 아군 병종과 같으면 그 칸을 다른 종류의 게이트로 바꾸고 판을 다시 그린다(명세 3장).
func avoid_switch_unit(current_unit: String, rng: RandomNumberGenerator) -> void:
	var new_left := Gate.switch_replacement(left_spec, right_spec, current_unit, _gates, section, rng)
	var new_right := Gate.switch_replacement(right_spec, left_spec, current_unit, _gates, section, rng)
	if new_left.is_empty() and new_right.is_empty():
		return
	if not new_left.is_empty():
		left_spec = new_left
	if not new_right.is_empty():
		right_spec = new_right
	_build_sides()


## 지금 선택될 칸을 밝게, 반대쪽 칸을 어둡게 표시한다. side가 -1이면 표시를 끈다.
func set_choice_preview(side: int) -> void:
	if side == _preview_side:
		return
	_preview_side = side
	_apply_preview()


func _apply_preview() -> void:
	for i in _sides.size():
		var color: Color = _sides[i]["color"]
		if _preview_side >= 0:
			if i == _preview_side:
				color = color.lightened(float(_view["preview_lighten"]))
				color.a = float(_view["preview_alpha"])
			else:
				color = color.darkened(float(_view["preview_other_darken"]))
		((_sides[i]["panel"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = color


## 먼 게이트의 글자와 아이콘을 숨긴다.
func set_text_visible(on: bool) -> void:
	_text_visible = on
	for node in _text_nodes:
		node.visible = on


## 통과한 칸을 번쩍이고 게이트 전체를 흐리게 지운다.
func play_pass(chosen_x: float) -> void:
	var chosen := side_for_x(chosen_x)
	var flash := Color.html(_view["flash_color"])
	var flash_time := float(_view["flash_time"])
	var fade_time := float(_view["fade_time"])
	var tween := create_tween()
	var chosen_material := (_sides[chosen]["panel"] as MeshInstance3D).material_override as StandardMaterial3D
	tween.tween_property(chosen_material, "albedo_color", flash, flash_time)
	tween.set_parallel()
	for side in _sides:
		var material := (side["panel"] as MeshInstance3D).material_override as StandardMaterial3D
		tween.tween_property(material, "albedo_color:a", 0.0, fade_time).set_delay(flash_time)
	for node in _text_nodes:
		# 받침판은 재질 투명도로 따로 지운다
		if not node is SpriteBase3D and not node is Label3D:
			continue
		tween.tween_property(node, "modulate:a", 0.0, fade_time).set_delay(flash_time)
		if node is Label3D:
			tween.tween_property(node, "outline_modulate:a", 0.0, fade_time).set_delay(flash_time)
	for plate in _plates:
		tween.tween_property(plate, "albedo_color:a", 0.0, fade_time).set_delay(flash_time)
	tween.tween_property(_wood_material, "albedo_color:a", 0.0, fade_time).set_delay(flash_time)
	tween.chain().tween_callback(hide)


## 기둥 세 개(양끝과 가운데)와 위쪽 들보
func _add_frame(road_width: float) -> void:
	_wood_material = StandardMaterial3D.new()
	_wood_material.albedo_color = Color.html(_view["wood"])
	_wood_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var post := float(_view["post_size"])
	var height := float(_view["post_height"])
	for x in [-road_width / 2.0, 0.0, road_width / 2.0]:
		_add_box(Vector3(post, height, post), Vector3(x, height / 2.0, 0.0), _wood_material)
	var beam := float(_view["beam_height"])
	_add_box(Vector3(road_width + post, beam, post), Vector3(0.0, height - beam / 2.0, 0.0), _wood_material)


func _add_side(spec: Dictionary, texts: Dictionary, center_x: float, width: float, main_pixel: float, cost_pixel: float, gates: Dictionary) -> void:
	var bottom := float(_view["panel_bottom"])
	var top := float(_view["panel_top"])
	var color := Color.html(gates[spec["type"]]["color"])
	color.a = float(_view["panel_alpha"])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var panel := _add_box(Vector3(width, top - bottom, float(_view["panel_depth"])), Vector3(center_x, (top + bottom) / 2.0, 0.0), material)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_side_nodes.append(panel)

	# 받침판, 글자, 아이콘은 판 앞(아군 쪽)에 차례로 띄워 판에 묻히지 않게 한다
	var font_size := int(_view["font_size"])
	var plate_z := float(_view["panel_depth"]) / 2.0 + float(_view["plate_offset"])
	var text_z := float(_view["panel_depth"]) / 2.0 + float(_view["text_offset"])
	var icon := Sprite3D.new()
	icon.texture = load(ICON_DIR % spec["type"])
	icon.pixel_size = float(_view["icon_size"]) / float(icon.texture.get_height())
	icon.position = Vector3(center_x, float(_view["icon_y"]), text_z)
	icon.render_priority = 1
	icon.shaded = false
	add_child(icon)
	_text_nodes.append(icon)
	_side_nodes.append(icon)

	# 주 효과와 대가 글자 뒤 어두운 반투명 받침판
	var margin: Array = _view["plate_margin"]
	var line_height := _font().get_height(font_size)
	var main_y := float(_view["main_y"])
	var cost_y := float(_view["cost_y"])
	var block_width := _text_width(texts["main"], font_size) * main_pixel
	var block_bottom := main_y - line_height * main_pixel / 2.0
	if texts["cost"] != "":
		block_width = maxf(block_width, _text_width(texts["cost"], font_size) * cost_pixel)
		block_bottom = cost_y - line_height * cost_pixel / 2.0
	var block_top := main_y + line_height * main_pixel / 2.0
	var plate_material := StandardMaterial3D.new()
	plate_material.albedo_color = Color.html(_view["plate_color"])
	plate_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plate_size := Vector3(minf(block_width + float(margin[0]) * 2.0, width), block_top - block_bottom + float(margin[1]) * 2.0, 0.01)
	var plate := _add_box(plate_size, Vector3(center_x, (block_top + block_bottom) / 2.0, plate_z), plate_material)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_text_nodes.append(plate)
	_side_nodes.append(plate)
	_plates.append(plate_material)

	var main_label := _add_label(texts["main"], font_size, main_pixel, Vector3(center_x, main_y, text_z))
	_text_nodes.append(main_label)
	_side_nodes.append(main_label)
	if texts["cost"] != "":
		var cost_label := _add_label(texts["cost"], font_size, cost_pixel, Vector3(center_x, cost_y, text_z))
		_text_nodes.append(cost_label)
		_side_nodes.append(cost_label)
	_sides.append({"panel": panel, "color": color})


func _add_label(text: String, font_size: int, pixel_size: float, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = int(_view["outline_size"])
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.position = at
	label.render_priority = 2
	label.outline_render_priority = 1
	add_child(label)
	return label


func _add_box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance


## 글자 폭이 width(m)가 되는 픽셀 크기. 빈 글자는 제한하지 않는다
func _pixel_for_width(text: String, font_size: int, width: float) -> float:
	if text == "":
		return INF
	return width / _text_width(text, font_size)


## 테두리를 포함한 글자 폭(픽셀)
func _text_width(text: String, font_size: int) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + float(_view["outline_size"])


func _font() -> Font:
	var project_theme := ThemeDB.get_project_theme()
	if project_theme != null and project_theme.default_font != null:
		return project_theme.default_font
	return ThemeDB.fallback_font


## 판에 쓸 문구. 주 효과는 크게, 대가는 그 아래 작게. 종류는 아이콘으로 보여준다.
func _texts(spec: Dictionary, gates: Dictionary, units: Dictionary) -> Dictionary:
	var data: Dictionary = gates[spec["type"]]
	match spec["type"]:
		"reinforce":
			var option: Dictionary = data["options"][spec["option"]]
			if option.has("add"):
				return {"main": "+%d" % int(option["add"]), "cost": ""}
			return {"main": "×%d" % int(option["mult"]), "cost": ""}
		"switch":
			return {"main": "%s 전환" % units[spec["unit"]]["name"], "cost": "병력 -%d%%" % _percent(data["loss_ratio"]) if float(data["loss_ratio"]) > 0.0 else ""}
		"empower":
			var option: Dictionary = data["options"][spec["option"]]
			var effect := ""
			if option.has("attack_speed_bonus"):
				effect = "공속 +%d%%" % _percent(option["attack_speed_bonus"])
			else:
				effect = "방어 +%d%%" % _percent(option["damage_taken_reduction"])
			return {"main": effect, "cost": "병력 -%d%%" % _percent(option["loss_ratio"])}
		"gamble":
			return {"main": "×%d / ÷%d" % [int(data["win_mult"]), int(data["lose_divisor"])], "cost": "확률 %d%%" % _percent(data["win_chance"])}
		"trap":
			return {"main": "금화 +%d" % int(data["gold_bonus"]), "cost": "병력 -%d%%" % _percent(data["loss_ratio"])}
	return {"main": "", "cost": ""}


static func _percent(ratio: Variant) -> int:
	return roundi(float(ratio) * 100.0)
