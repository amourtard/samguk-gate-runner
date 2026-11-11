class_name FieldView
extends Node3D
## 전장 꾸미기: 그라데이션 하늘과 안개, 방향광과 그림자, 길가 소품(나무, 바위, 깃발).
## 소품은 판 시작부터 보스 너머까지 한 번에 MultiMesh로 뿌리고, 도로 안쪽에는 두지 않는다.


func setup(environment: Environment, light: DirectionalLight3D, length: float, road_width: float, visual: Dictionary) -> void:
	_setup_sky(environment, visual)
	_setup_light(light, environment, visual)
	_scatter_props(length, road_width, visual["props"])


func _setup_sky(environment: Environment, visual: Dictionary) -> void:
	var sky_data: Dictionary = visual["sky"]
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color.html(sky_data["top"])
	sky_material.sky_horizon_color = Color.html(sky_data["horizon"])
	sky_material.ground_horizon_color = Color.html(sky_data["ground_horizon"])
	sky_material.ground_bottom_color = Color.html(sky_data["ground_bottom"])
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# 먼 곳을 하늘 지평선 색으로 흐리게 해 도로 끝이 잘려 보이지 않게 한다
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color.html(sky_data["fog_color"])
	environment.fog_depth_begin = float(sky_data["fog_begin"])
	environment.fog_depth_end = float(sky_data["fog_end"])
	environment.fog_sky_affect = 0.0


func _setup_light(light: DirectionalLight3D, environment: Environment, visual: Dictionary) -> void:
	var data: Dictionary = visual["light"]
	light.rotation = Vector3(deg_to_rad(float(data["pitch_deg"])), deg_to_rad(float(data["yaw_deg"])), 0.0)
	light.light_energy = float(data["energy"])
	light.shadow_enabled = bool(data["shadow"])
	light.directional_shadow_max_distance = float(data["shadow_max_distance"])
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.html(data["ambient_color"])
	environment.ambient_light_energy = float(data["ambient_energy"])


func _scatter_props(length: float, road_width: float, data: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data["seed"])
	var segment := float(data["segment"])
	var inner := road_width / 2.0 + float(data["margin"])
	var band := float(data["band"])
	var start_z := float(data["behind"])
	var end_z := -(length + float(data["ahead_extra"]))
	var segments := int((start_z - end_z) / segment)
	for type_name in data["types"]:
		var type_data: Dictionary = data["types"][type_name]
		var transforms: Array[Transform3D] = []
		for s in segments:
			# 구간마다 평균 개수만큼, 소수 부분은 확률로 하나 더 놓는다
			var expected := float(type_data["per_segment"])
			var count := int(expected) + (1 if rng.randf() < expected - int(expected) else 0)
			for i in count:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var x := side * rng.randf_range(inner, inner + band)
				var z := start_z - (s + rng.randf()) * segment
				var size := rng.randf_range(float(type_data["scale_min"]), float(type_data["scale_max"]))
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
				transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = ModelBuilder.build(type_data["parts"])
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = ModelBuilder.make_material(Color.WHITE)
		add_child(instance)
