class_name BridgeView
extends Node3D
## 좁은 다리 구간: 도로 폭의 나무 다리(가로 판자), 양옆 난간, 다리 밖을 덮는 물.
## 계산(근접 동시 교전 수 감소)과 무관한 표시다. 물 아래 어두운 바닥을 깔고 반투명 물 면을 겹쳐 깊어 보이게 한다.


func setup(start: float, end: float, road_width: float, visual: Dictionary) -> void:
	var data: Dictionary = visual["bridge"]
	var length := end - start
	var center_z := -(start + end) / 2.0
	var water_width := float(data["water_width"])
	var bank := float(data["bank"])

	# 양옆 물: 어두운 바닥 위에 반투명 물 면
	for side in [-1.0, 1.0]:
		var x: float = side * (road_width / 2.0 + water_width / 2.0)
		var size := Vector2(water_width, length + bank * 2.0)
		_add_plane(size, Vector3(x, float(data["bed_lift"]), center_z), _flat(Color.html(data["bed_color"])))
		var water := _flat(Color.html(data["water_color"]))
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.roughness = 0.15
		water.metallic_specular = 0.8
		_add_plane(size, Vector3(x, float(data["water_lift"]), center_z), water)

	# 다리 판자와 난간은 한 메시로 합친다
	var parts: Array = []
	var deck_top := float(data["deck_top"])
	var plank := float(data["plank_depth"])
	var plank_count := int(ceil(length / plank))
	var deck_width := road_width + float(data["deck_overhang"]) * 2.0
	for i in plank_count:
		var z := -start - (i + 0.5) * plank
		var color: String = data["plank_colors"][i % (data["plank_colors"] as Array).size()]
		parts.append({"shape": "box", "size": [deck_width, 0.06, plank * 0.92], "pos": [0, deck_top - 0.03, z], "color": color})
	var rail_x := deck_width / 2.0
	var post_gap := float(data["post_gap"])
	var post_height := float(data["post_height"])
	var post_count := int(floor(length / post_gap)) + 1
	for side in [-1.0, 1.0]:
		for i in post_count:
			parts.append({"shape": "box", "size": [0.16, post_height, 0.16], "pos": [side * rail_x, deck_top + post_height / 2.0, -start - i * post_gap], "color": data["rail_color"]})
		for rail_y in data["rail_heights"]:
			parts.append({"shape": "box", "size": [0.1, 0.1, length], "pos": [side * rail_x, deck_top + float(rail_y), center_z], "color": data["rail_color"]})
		# 다리 옆면 들보
		parts.append({"shape": "box", "size": [0.22, 0.3, length], "pos": [side * rail_x, deck_top - 0.12, center_z], "color": data["beam_color"]})
	var deck := MeshInstance3D.new()
	deck.mesh = ModelBuilder.build(parts)
	deck.material_override = ModelBuilder.make_material(Color.WHITE)
	add_child(deck)


func _add_plane(size: Vector2, at: Vector3, material: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	add_child(instance)


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
