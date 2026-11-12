extends Node3D
## 도로와 바닥, 가장자리 돌을 그린다. 아군을 따라 표지 간격 단위로 옮겨 끝없이 이어지게 보인다.
## 흙길과 풀밭 무늬는 월드 좌표로 입혀서 판이 옮겨져도 무늬는 제자리에 있다.

var _marker_spacing: float
var _road_center_offset: float
var _lift: float
var _ground: Dictionary
var _marker_size: Vector3
var _markers: MultiMesh
# 가장자리 돌의 원래 위치(노드 기준)
var _marker_origins: Array[Vector3] = []
# 광장 구간(전진 거리 시작, 끝). 이 구간에서는 길 가장자리 돌을 숨긴다
var _plaza_range := Vector2(-1.0, -1.0)


func setup(tuning: Dictionary, visual: Dictionary) -> void:
	var road: Dictionary = tuning["road"]
	var ground: Dictionary = visual["ground"]
	var width := float(road["width"])
	var length := float(road["visible_length"])
	var behind := float(road["behind_length"])
	var lift := float(road["surface_lift"])
	var ground_size := float(road["ground_size"])
	_marker_spacing = float(road["marker_spacing"])
	_lift = lift
	_ground = ground
	# 도로 중심을 아군보다 앞쪽에 둔다 (-Z가 전방)
	_road_center_offset = -(length / 2.0 - behind)

	_add_plane(Vector2(ground_size, ground_size), Vector3(0.0, 0.0, _road_center_offset),
		_ground_material(ground, "grass", 1))
	# 흙길과 풀밭 사이의 어두운 가장자리
	var edge_width := float(ground["edge_width"])
	_add_plane(Vector2(width + edge_width * 2.0, length), Vector3(0.0, lift * 0.5, _road_center_offset), _flat_material(Color.html(ground["edge"])))
	_add_plane(Vector2(width, length), Vector3(0.0, lift, _road_center_offset),
		_ground_material(ground, "road", 2))
	_add_markers(road, width, length, Color.html(ground["marker"]))


func follow(z: float) -> void:
	# 표지 간격 단위로만 옮겨 표지가 지나가는 것처럼 보이게 한다
	var snapped_z := snappedf(z, _marker_spacing)
	if is_equal_approx(snapped_z, position.z):
		return
	position.z = snapped_z
	_clip_markers()


## 보스전 광장을 깐다. 전진 거리 start~end 구간의 길을 width로 넓히고 가장자리에 돌을 놓는다.
## 길과 함께 움직이지 않도록 부모 아래에 따로 둔다.
func add_plaza(start: float, end: float, width: float) -> void:
	_plaza_range = Vector2(start, end)
	var plaza := Node3D.new()
	plaza.name = "Plaza"
	get_parent().add_child.call_deferred(plaza)
	var length := end - start
	var center_z := -(start + end) / 2.0
	var edge_width := float(_ground["edge_width"])
	plaza.add_child(_make_plane(Vector2(width + edge_width * 2.0, length + edge_width * 2.0), Vector3(0.0, _lift * 1.5, center_z), _flat_material(Color.html(_ground["edge"]))))
	plaza.add_child(_make_plane(Vector2(width, length), Vector3(0.0, _lift * 2.0, center_z),
		_noise_material(_ground, Color.html(_ground["road_a"]), Color.html(_ground["road_b"]), 2)))

	var box := BoxMesh.new()
	box.size = _marker_size
	var per_side := int(length / _marker_spacing) + 1
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = per_side * 2
	for i in per_side:
		var z := -start - i * _marker_spacing
		multimesh.set_instance_transform(i * 2, Transform3D(Basis.IDENTITY, Vector3(-width / 2.0, _marker_size.y / 2.0, z)))
		multimesh.set_instance_transform(i * 2 + 1, Transform3D(Basis.IDENTITY, Vector3(width / 2.0, _marker_size.y / 2.0, z)))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _flat_material(Color.html(_ground["marker"]))
	plaza.add_child(instance)
	_clip_markers()


## 광장 구간에 들어간 길 가장자리 돌을 숨긴다(크기를 0으로).
func _clip_markers() -> void:
	if _markers == null:
		return
	for i in _marker_origins.size():
		var origin := _marker_origins[i]
		var distance := -(position.z + origin.z)
		var hidden := distance >= _plaza_range.x and distance <= _plaza_range.y
		_markers.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO if hidden else Vector3.ONE), origin))


func _add_plane(size: Vector2, at: Vector3, material: Material) -> void:
	add_child(_make_plane(size, at, material))


func _make_plane(size: Vector2, at: Vector3, material: Material) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _add_markers(road: Dictionary, width: float, length: float, color: Color) -> void:
	var marker_size := Vector3(float(road["marker_size"][0]), float(road["marker_size"][1]), float(road["marker_size"][2]))
	var box := BoxMesh.new()
	box.size = marker_size
	_marker_size = marker_size

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
		_marker_origins.append(Vector3(-edge_x, marker_size.y / 2.0, z))
		_marker_origins.append(Vector3(edge_x, marker_size.y / 2.0, z))
		multimesh.set_instance_transform(i * 2, _transform_at(_marker_origins[i * 2]))
		multimesh.set_instance_transform(i * 2 + 1, _transform_at(_marker_origins[i * 2 + 1]))
	_markers = multimesh

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _flat_material(color)
	add_child(instance)


func _transform_at(origin: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


## 흙길("road")이나 풀밭("grass")의 바닥 재질. 반복 무늬 그림이 있으면 그것을, 없으면 잡음 무늬를 쓴다.
func _ground_material(ground: Dictionary, kind: String, noise_seed: int) -> StandardMaterial3D:
	var image := UiText.texture(str(ground.get(kind + "_texture", "")))
	if image == null:
		return _noise_material(ground, Color.html(ground[kind + "_a"]), Color.html(ground[kind + "_b"]), noise_seed)
	var material := StandardMaterial3D.new()
	material.albedo_texture = image
	material.albedo_color = Color.html(ground[kind + "_tint"])
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	var tile_scale := 1.0 / float(ground[kind + "_tile_m"])
	material.uv1_scale = Vector3(tile_scale, tile_scale, tile_scale)
	return material


## 두 색 사이를 잡음으로 섞은 무늬. 월드 좌표 투영이라 이어 붙인 자국이 없다.
func _noise_material(ground: Dictionary, color_a: Color, color_b: Color, noise_seed: int) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = float(ground["noise_frequency"])
	var gradient := Gradient.new()
	gradient.set_color(0, color_a)
	gradient.set_color(1, color_b)
	var texture := NoiseTexture2D.new()
	texture.width = int(ground["texture_size"])
	texture.height = int(ground["texture_size"])
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = gradient
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 1.0
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	var world_scale := float(ground["world_scale"])
	material.uv1_scale = Vector3(world_scale, world_scale, world_scale)
	return material
