class_name BossView
extends Node3D
## 보스 공격 예고 구역을 그린다. 패턴 계산은 BossPattern이 맡는다.
## 보스 무리(EnemyGroup)의 자식으로 붙어 보스 앞(+Z 쪽, 아군이 오는 방향)으로 예고 면을 깐다.
## 예고 면은 예고 시간 동안 점점 진해지고, 공격 순간 밝게 번쩍인 뒤 사라진다.
## 보스 이름과 체력 막대는 HUD가 그린다.

var _zone_meshes: Array[MeshInstance3D] = []
var _warn_color: Color
var _alpha_start: float
var _alpha_end: float
var _warn_time: float
var _flash_color: Color
var _flash_time: float
var _warning_zone := -1
var _warn_elapsed := 0.0
var _view: Dictionary
# 구역마다의 좌우 범위와 예고 면 길이. 번개 기둥을 세울 때 쓴다
var _zone_ranges: Array[Vector2] = []
var _length := 0.0


func setup(tuning: Dictionary, visual: Dictionary, warn_length := -1.0) -> void:
	var data: Dictionary = tuning["boss"]
	var view: Dictionary = visual["boss_view"]
	var road_width := float(tuning["boss_road_width"])
	var zones := int(data["zones"])
	# 예고 면 길이. 광장보다 길면 run이 광장 길이로 줄여서 넘긴다
	var length := warn_length if warn_length > 0.0 else float(data["warn_length"])
	var lift := float(data["warn_lift"])
	_warn_time = float(data["warn_time"])
	_view = view
	_length = length
	_warn_color = Color.html(data["warn_color"])
	_alpha_start = float(view["warn_alpha_start"])
	_alpha_end = float(data["warn_alpha"])
	_flash_color = Color.html(view["flash_color"])
	_flash_time = float(view["flash_time"])

	# 예고 면은 판정에 쓰는 구역 범위 그대로 그린다
	for zone in zones:
		var range_ := BossPattern.zone_range(zone, road_width, zones)
		_zone_ranges.append(range_)
		var plane := PlaneMesh.new()
		plane.size = Vector2(range_.y - range_.x, length)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var instance := MeshInstance3D.new()
		instance.mesh = plane
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.position = Vector3((range_.x + range_.y) / 2.0, lift, length / 2.0)
		instance.visible = false
		add_child(instance)
		_zone_meshes.append(instance)


func show_warning(zone: int) -> void:
	_warning_zone = zone
	_warn_elapsed = 0.0
	for i in _zone_meshes.size():
		_zone_meshes[i].visible = i == zone
	_apply_warn_alpha()


## 공격 순간: 예고하던 구역을 번쩍이고 사라지게 한다.
func flash_attack(zone: int) -> void:
	_warning_zone = -1
	if zone < 0 or zone >= _zone_meshes.size():
		return
	var mesh := _zone_meshes[zone]
	mesh.visible = true
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = _flash_color
	var tween := mesh.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, _flash_time)
	tween.tween_callback(func() -> void:
		if _warning_zone != zone:
			mesh.visible = false)


## 구역 공격이 떨어지는 순간 그 구역에 번개 기둥을 세웠다가 가늘어지며 사라지게 한다.
func strike_zone(zone: int) -> void:
	if zone < 0 or zone >= _zone_ranges.size():
		return
	var range_ := _zone_ranges[zone]
	var height := float(_view["bolt_height"])
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(_view["bolt_color"])
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	# 번개 그림이 있으면 세로로 선 그림 판을, 없으면 상자 기둥을 쓴다
	var image := UiText.texture(str(_view.get("bolt_texture", "")))
	if image != null:
		material.albedo_texture = image
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in int(_view["bolt_count"]):
		var bolt := MeshInstance3D.new()
		if image != null:
			var quad := QuadMesh.new()
			quad.size = Vector2(height * float(_view["bolt_texture_width_ratio"]), height)
			bolt.mesh = quad
		else:
			var box := BoxMesh.new()
			box.size = Vector3(float(_view["bolt_width"]), height, float(_view["bolt_width"]))
			bolt.mesh = box
		bolt.material_override = material
		bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt.position = Vector3(randf_range(range_.x, range_.y), height / 2.0, randf_range(0.0, _length))
		add_child(bolt)
		var tween := bolt.create_tween()
		# 그림 번개는 좌우를 뒤집어 가며 서로 달라 보이게 한다
		if image != null and randf() < 0.5:
			bolt.scale.x = -1.0
		tween.tween_property(bolt, "scale", Vector3(0.0, 1.0, 0.0), float(_view["bolt_time"]))
		tween.tween_callback(bolt.queue_free)


## 불덩이가 떨어질 자리를 바닥의 붉은 원으로 예고한다. 안쪽 원이 점점 커져 꽉 차면 떨어진다.
## 반환한 노드를 불덩이의 목표로 쓰고, 떨어진 뒤 호출한 쪽이 지운다.
func show_target(at: Vector3, radius: float, flight: float) -> Node3D:
	var marker := Node3D.new()
	marker.top_level = true
	add_child(marker)
	marker.global_position = at + Vector3.UP * float(_view["target_lift"])
	var color := Color.html(_view["target_color"])
	for inner in [false, true]:
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.02
		disc.radial_segments = 24
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.disable_fog = true
		color.a = float(_view["target_alpha"]) * (1.0 if inner else 0.5)
		material.albedo_color = color
		var instance := MeshInstance3D.new()
		instance.mesh = disc
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(instance)
		if inner:
			instance.position.y = 0.01
			var start := float(_view["target_start_scale"])
			instance.scale = Vector3(start, 1.0, start)
			instance.create_tween().tween_property(instance, "scale", Vector3.ONE, flight)
	# 구역 예고의 붉은 면 위에서도 보이도록 밝은 테두리를 두른다
	var ring := TorusMesh.new()
	ring.outer_radius = radius
	ring.inner_radius = radius - float(_view["target_ring_width"])
	ring.rings = 32
	ring.ring_segments = 4
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color.html(_view["target_ring_color"])
	ring_material.disable_fog = true
	var ring_instance := MeshInstance3D.new()
	ring_instance.mesh = ring
	ring_instance.material_override = ring_material
	ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_instance.scale = Vector3(1.0, float(_view["target_ring_flatten"]), 1.0)
	ring_instance.position.y = 0.02
	marker.add_child(ring_instance)
	return marker


## 일반 공격: 보스에서 예고한 자리(target)로 불덩이를 포물선으로 날린다. from은 월드 좌표다.
func fire_orb(from: Vector3, target: Node3D, flight: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = float(_view["orb_radius"])
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(_view["orb_color"])
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	var orb := MeshInstance3D.new()
	orb.mesh = sphere
	orb.material_override = material
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.top_level = true
	add_child(orb)
	orb.global_position = from
	var arc := float(_view["orb_arc"])
	var tween := orb.create_tween()
	tween.tween_method(func(progress: float) -> void:
		var to := target.global_position if is_instance_valid(target) else orb.global_position
		orb.global_position = from.lerp(to, progress) + Vector3.UP * sin(progress * PI) * arc, 0.0, 1.0, flight)
	tween.tween_callback(orb.queue_free)


func hide_warning() -> void:
	_warning_zone = -1
	for mesh in _zone_meshes:
		mesh.visible = false


func _process(delta: float) -> void:
	if _warning_zone < 0:
		return
	_warn_elapsed += delta
	_apply_warn_alpha()


func _apply_warn_alpha() -> void:
	var color := _warn_color
	color.a = lerpf(_alpha_start, _alpha_end, clampf(_warn_elapsed / _warn_time, 0.0, 1.0))
	(_zone_meshes[_warning_zone].material_override as StandardMaterial3D).albedo_color = color
