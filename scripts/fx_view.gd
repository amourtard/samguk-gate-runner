extends Node3D
## 파티클 연출(달리기 먼지, 타격 불꽃, 게이트 통과, 격파). 계산과 무관한 표시다.
## 웹(Compatibility)에서도 도는 CPUParticles3D만 쓴다. 터지는 연출은 정해진 개수의 발사기를 돌려 쓴다.
## 값은 visual.json의 particles에 둔다.

const BURST_KINDS: Array[String] = ["spark", "gate", "wipe", "boss_hit", "boss_zone"]

var _data: Dictionary
var _dust: CPUParticles3D
# 종류 → 발사기 목록, 종류 → 다음에 쓸 발사기 번호
var _pools := {}
var _next := {}


func setup(visual: Dictionary) -> void:
	_data = visual["particles"]
	_dust = _make_emitter(_data["dust"], false)
	add_child(_dust)
	for kind in BURST_KINDS:
		var list: Array[CPUParticles3D] = []
		for i in int(_data[kind]["pool"]):
			var emitter := _make_emitter(_data[kind], true)
			add_child(emitter)
			list.append(emitter)
		_pools[kind] = list
		_next[kind] = 0


## 달리는 무리 발밑의 먼지. 무리 크기에 맞춰 뿌리고, 멈춰 싸우는 동안에는 끈다.
func set_dust(center: Vector3, half_width: float, half_length: float, moving: bool) -> void:
	_dust.position = center
	_dust.emission_box_extents = Vector3(half_width, 0.05, half_length)
	_dust.emitting = moving


## at 위치에서 한 번 터뜨린다. color를 주면 그 색으로, half_width를 주면 그 폭으로 퍼뜨린다.
func burst(kind: String, at: Vector3, color := Color(0, 0, 0, 0), half_width := -1.0, half_length := 0.2) -> void:
	var list: Array = _pools[kind]
	var emitter: CPUParticles3D = list[int(_next[kind])]
	_next[kind] = (int(_next[kind]) + 1) % list.size()
	emitter.position = at
	emitter.color = color if color.a > 0.0 else Color.html(_data[kind]["color"])
	if half_width > 0.0:
		emitter.emission_box_extents = Vector3(half_width, 0.2, half_length)
	emitter.restart()
	emitter.emitting = true


func _make_emitter(data: Dictionary, one_shot: bool) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.amount = int(data["amount"])
	emitter.lifetime = float(data["lifetime"])
	emitter.one_shot = one_shot
	emitter.emitting = false
	emitter.explosiveness = 1.0 if one_shot else 0.0
	emitter.local_coords = false
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.emission_box_extents = Vector3(0.3, 0.1, 0.3)
	emitter.direction = Vector3.UP
	emitter.spread = float(data["spread_deg"])
	emitter.initial_velocity_min = float(data["speed"][0])
	emitter.initial_velocity_max = float(data["speed"][1])
	emitter.gravity = Vector3(0.0, float(data["gravity"]), 0.0)
	emitter.scale_amount_min = float(data["size"][0])
	emitter.scale_amount_max = float(data["size"][1])
	emitter.color = Color.html(data["color"])
	# 사라질 때 서서히 투명해진다
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	emitter.color_ramp = fade
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.disable_fog = true
	var image := UiText.texture(str(data.get("texture", "")))
	if image != null:
		material.albedo_texture = image
	elif bool(data.get("soft", false)):
		# 가운데가 진하고 가장자리가 투명한 둥근 무늬(먼지용). 그림 파일 없이 만든다
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		material.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	emitter.mesh = quad
	return emitter
