class_name ModelBuilder
extends RefCounted
## data/visual.json의 부품 목록으로 저폴리 메시 하나를 만든다. 기본 도형을 옮기고 돌려 한 메시로 합친다.
## 부품: {"shape": box|cylinder|sphere, "pos": [x,y,z], "rot": [도 x,y,z], "scale": [x,y,z],
##        box는 "size", cylinder는 "top", "bottom", "height", "segments", sphere는 "radius", "segments", "rings",
##        색은 "color": "#hex"(고정 색) 또는 "team": 명암(팀 색에 곱할 0~1 값)}
## 꼭짓점 색의 알파로 팀 색 여부를 넘긴다. 재질은 assets/shaders/unit.gdshader가 해석한다.

const UNIT_SHADER := preload("res://assets/shaders/unit.gdshader")


static func build(parts: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var primitive := _primitive(part)
		var arrays := primitive.get_mesh_arrays()
		var transform := _transform(part)
		var color := _vertex_color(part)
		var base := vertices.size()
		var part_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var part_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in part_vertices.size():
			vertices.append(transform * part_vertices[i])
			normals.append((transform.basis * part_normals[i]).normalized())
			colors.append(color)
		var part_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in part_indices:
			indices.append(base + index)

	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## 팀 색과 흔들림을 받는 공용 재질
static func make_material(team_color: Color, bob_height := 0.0, bob_speed := 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = UNIT_SHADER
	material.set_shader_parameter("team_color", team_color)
	material.set_shader_parameter("bob_height", bob_height)
	material.set_shader_parameter("bob_speed", bob_speed)
	return material


## 모델의 높이(발에서 가장 높은 꼭짓점까지)
static func height_of(mesh: Mesh) -> float:
	var aabb := mesh.get_aabb()
	return aabb.position.y + aabb.size.y


static func _primitive(part: Dictionary) -> PrimitiveMesh:
	match part["shape"]:
		"box":
			var box := BoxMesh.new()
			box.size = to_vector3(part["size"])
			return box
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(part["top"])
			cylinder.bottom_radius = float(part["bottom"])
			cylinder.height = float(part["height"])
			cylinder.radial_segments = int(part.get("segments", 8))
			cylinder.rings = 1
			return cylinder
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = float(part["radius"])
			sphere.height = float(part["radius"]) * 2.0
			sphere.radial_segments = int(part.get("segments", 8))
			sphere.rings = int(part.get("rings", 4))
			return sphere
	push_error("알 수 없는 부품 도형: " + str(part["shape"]))
	return BoxMesh.new()


static func _transform(part: Dictionary) -> Transform3D:
	var rot := to_vector3(part.get("rot", [0, 0, 0]))
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	basis = basis * Basis.from_scale(to_vector3(part.get("scale", [1, 1, 1])))
	return Transform3D(basis, to_vector3(part.get("pos", [0, 0, 0])))


## 고정 색은 셰이더가 선형 색으로 쓰도록 바꿔 넣는다. 팀 부품은 명암 값과 알파 1을 넣는다.
static func _vertex_color(part: Dictionary) -> Color:
	if part.has("team"):
		var shade := float(part["team"])
		return Color(shade, shade, shade, 1.0)
	var color := Color.html(part["color"]).srgb_to_linear()
	color.a = 0.0
	return color


static func to_vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
