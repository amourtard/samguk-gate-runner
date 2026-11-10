class_name GatePair
extends Node3D
## 좌우 게이트 한 쌍의 표시. 효과 계산은 Gate가 맡고 여기서는 그리기만 한다.
## 노드의 z 위치가 통과선이다. 아군 중심이 왼쪽 절반이면 왼쪽 게이트를 고른 것으로 본다.

var left_spec: Dictionary
var right_spec: Dictionary
var passed := false


func setup(p_left: Dictionary, p_right: Dictionary, gates: Dictionary, units: Dictionary, tuning: Dictionary) -> void:
	left_spec = p_left
	right_spec = p_right
	var view: Dictionary = tuning["gate_view"]
	var half_road := float(tuning["road"]["width"]) / 2.0
	_add_panel(left_spec, -half_road / 2.0, half_road, view, gates, units)
	_add_panel(right_spec, half_road / 2.0, half_road, view, gates, units)


func spec_for_x(x: float) -> Dictionary:
	return left_spec if x <= 0.0 else right_spec


func _add_panel(spec: Dictionary, center_x: float, half_road: float, view: Dictionary, gates: Dictionary, units: Dictionary) -> void:
	var height := float(view["height"])
	var depth := float(view["depth"])
	var color := Color.html(gates[spec["type"]]["color"])
	color.a = float(view["alpha"])

	var box := BoxMesh.new()
	box.size = Vector3(half_road - float(view["side_gap"]), height, depth)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var panel := MeshInstance3D.new()
	panel.mesh = box
	panel.material_override = material
	panel.position = Vector3(center_x, height / 2.0, 0.0)
	add_child(panel)

	var text := Label3D.new()
	text.text = Gate.label(spec, gates, units)
	text.font_size = int(view["label_font_size"])
	text.pixel_size = float(view["label_pixel_size"])
	text.outline_size = int(view["label_outline_size"])
	text.modulate = Color.WHITE
	text.position = Vector3(center_x, height / 2.0, depth)
	add_child(text)
