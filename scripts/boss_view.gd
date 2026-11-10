class_name BossView
extends Node3D
## 보스 이름표와 공격 예고 구역을 그린다. 패턴 계산은 BossPattern이 맡는다.
## 보스 무리(EnemyGroup)의 자식으로 붙어 보스 앞(+Z 쪽, 아군이 오는 방향)으로 예고 띠를 깐다.

var _zone_meshes: Array[MeshInstance3D] = []


func setup(boss_name: String, tuning: Dictionary) -> void:
	var data: Dictionary = tuning["boss"]
	var road_width := float(tuning["road"]["width"])
	var zones := int(data["zones"])
	var length := float(data["warn_length"])
	var lift := float(data["warn_lift"])

	var color := Color.html(data["warn_color"])
	color.a = float(data["warn_alpha"])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for zone in zones:
		var plane := PlaneMesh.new()
		plane.size = Vector2(road_width / zones, length)
		var instance := MeshInstance3D.new()
		instance.mesh = plane
		instance.material_override = material
		instance.position = Vector3(BossPattern.zone_center(zone, road_width, zones), lift, length / 2.0)
		instance.visible = false
		add_child(instance)
		_zone_meshes.append(instance)

	var label := Label3D.new()
	label.text = boss_name
	label.font_size = int(data["label_font_size"])
	label.pixel_size = float(data["label_pixel_size"])
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, float(data["label_height"]), 0.0)
	add_child(label)


func show_warning(zone: int) -> void:
	for i in _zone_meshes.size():
		_zone_meshes[i].visible = i == zone


func hide_warning() -> void:
	for mesh in _zone_meshes:
		mesh.visible = false
