class_name GatePair
extends Node3D
## 좌우 게이트 한 쌍의 표시. 효과 계산은 Gate가 맡고 여기서는 그리기만 한다.
## 노드의 z 위치가 통과선이다. 아군 중심이 왼쪽 절반이면 왼쪽 게이트를 고른 것으로 본다.
## 나무 기둥 세 개와 위쪽 들보로 도로 폭 전체를 막고, 좌우 칸에 반투명 색 판과 아이콘, 글자를 세운다.

const ICON_DIR := "res://assets/icons/gate_%s.svg"

var left_spec: Dictionary
var right_spec: Dictionary
var passed := false

var _view: Dictionary
# 칸별 표시 노드: {"panel": MeshInstance3D, "nodes": [글자와 아이콘]}
var _sides: Array[Dictionary] = []
var _wood_material: StandardMaterial3D
var _text_nodes: Array[Node3D] = []


func setup(p_left: Dictionary, p_right: Dictionary, gates: Dictionary, units: Dictionary, tuning: Dictionary, visual: Dictionary) -> void:
	left_spec = p_left
	right_spec = p_right
	_view = visual["gate"]
	var road_width := float(tuning["road"]["width"])
	var half_road := road_width / 2.0
	_add_frame(road_width)

	var texts := [_texts(left_spec, gates, units), _texts(right_spec, gates, units)]
	var panel_width := half_road - float(_view["post_size"])
	# 좌우 글자 크기를 같게: 두 칸 모두 판 안에 들어가는 크기 중 작은 쪽을 쓴다
	var main_pixel := minf(_fit_pixel_size(texts[0]["main"], int(_view["main_font_size"]), panel_width), _fit_pixel_size(texts[1]["main"], int(_view["main_font_size"]), panel_width))
	var cost_pixel := minf(_fit_pixel_size(texts[0]["cost"], int(_view["cost_font_size"]), panel_width), _fit_pixel_size(texts[1]["cost"], int(_view["cost_font_size"]), panel_width))
	_add_side(left_spec, texts[0], -half_road / 2.0, panel_width, main_pixel, cost_pixel, gates)
	_add_side(right_spec, texts[1], half_road / 2.0, panel_width, main_pixel, cost_pixel, gates)


func spec_for_x(x: float) -> Dictionary:
	return left_spec if x <= 0.0 else right_spec


## 먼 게이트의 글자와 아이콘을 숨긴다.
func set_text_visible(on: bool) -> void:
	for node in _text_nodes:
		node.visible = on


## 통과한 칸을 번쩍이고 게이트 전체를 흐리게 지운다.
func play_pass(chosen_x: float) -> void:
	var chosen := 0 if chosen_x <= 0.0 else 1
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
		tween.tween_property(node, "modulate:a", 0.0, fade_time).set_delay(flash_time)
		if node is Label3D:
			tween.tween_property(node, "outline_modulate:a", 0.0, fade_time).set_delay(flash_time)
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

	# 글자와 아이콘은 판 앞(아군 쪽)에 살짝 띄워 판에 묻히지 않게 한다
	var front_z := float(_view["panel_depth"])
	var icon := Sprite3D.new()
	icon.texture = load(ICON_DIR % spec["type"])
	icon.pixel_size = float(_view["icon_size"]) / float(icon.texture.get_height())
	icon.position = Vector3(center_x, float(_view["icon_y"]), front_z)
	icon.render_priority = 1
	icon.shaded = false
	add_child(icon)
	_text_nodes.append(icon)

	_text_nodes.append(_add_label(texts["main"], int(_view["main_font_size"]), main_pixel, Vector3(center_x, float(_view["main_y"]), front_z)))
	if texts["cost"] != "":
		_text_nodes.append(_add_label(texts["cost"], int(_view["cost_font_size"]), cost_pixel, Vector3(center_x, float(_view["cost_y"]), front_z)))
	_sides.append({"panel": panel})


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


## 판 폭 안에 글자가 들어가는 픽셀 크기. 기본 크기보다 키우지는 않는다.
func _fit_pixel_size(text: String, font_size: int, panel_width: float) -> float:
	var base := float(_view["base_pixel_size"])
	if text == "":
		return base
	var font := ThemeDB.fallback_font
	var project_theme := ThemeDB.get_project_theme()
	if project_theme != null and project_theme.default_font != null:
		font = project_theme.default_font
	var text_px := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + float(_view["outline_size"])
	var limit := panel_width * float(_view["text_width_ratio"])
	return minf(base, limit / text_px)


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
			return {"main": "%s 전환" % units[spec["unit"]]["name"], "cost": "병력 -%d%%" % _percent(data["loss_ratio"])}
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
