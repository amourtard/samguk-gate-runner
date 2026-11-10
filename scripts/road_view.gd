extends Node3D
## 도로와 바닥, 가장자리 표지를 그린다. 아군을 따라 표지 간격 단위로 옮겨 끝없이 이어지게 보인다.

var _marker_spacing: float
var _road_center_offset: float


func setup(tuning: Dictionary) -> void:
	var road: Dictionary = tuning["road"]
	var colors: Dictionary = tuning["colors"]
	var width := float(road["width"])
	var length := float(road["visible_length"])
	var behind := float(road["behind_length"])
	var lift := float(road["surface_lift"])
	var ground_size := float(road["ground_size"])
	_marker_spacing = float(road["marker_spacing"])
	# 도로 중심을 아군보다 앞쪽에 둔다 (-Z가 전방)
	_road_center_offset = -(length / 2.0 - behind)

	_add_plane(Vector2(ground_size, ground_size), Vector3(0.0, 0.0, _road_center_offset), Color.html(colors["ground"]))
	_add_plane(Vector2(width, length), Vector3(0.0, lift, _road_center_offset), Color.html(colors["road"]))
	_add_markers(road, width, length, Color.html(colors["marker"]))


func follow(z: float) -> void:
	# 표지 간격 단위로만 옮겨 표지가 지나가는 것처럼 보이게 한다
	position.z = snappedf(z, _marker_spacing)


func _add_plane(size: Vector2, at: Vector3, color: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.position = at
	instance.material_override = _make_material(color)
	add_child(instance)


func _add_markers(road: Dictionary, width: float, length: float, color: Color) -> void:
	var marker_size := Vector3(float(road["marker_size"][0]), float(road["marker_size"][1]), float(road["marker_size"][2]))
	var box := BoxMesh.new()
	box.size = marker_size

	var per_side := int(length / _marker_spacing)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	# 좌우 가장자리 두 줄
	multimesh.instance_count = per_side * 2

	var start_z := _road_center_offset + length / 2.0
	var edge_x := width / 2.0
	for i in per_side:
		var z := start_z - i * _marker_spacing
		multimesh.set_instance_transform(i * 2, Transform3D(Basis.IDENTITY, Vector3(-edge_x, marker_size.y / 2.0, z)))
		multimesh.set_instance_transform(i * 2 + 1, Transform3D(Basis.IDENTITY, Vector3(edge_x, marker_size.y / 2.0, z)))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _make_material(color)
	add_child(instance)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
