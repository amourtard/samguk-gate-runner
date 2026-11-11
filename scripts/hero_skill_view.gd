class_name HeroSkillView
extends Node3D
## 장수 기술 발동을 반투명 도형으로 보여준다. 기술 계산은 HeroSkill이 맡고 여기서는 그리기만 한다.
## strike(관우): 아군에서 전방 적 무리까지 퍼지는 직선 도형
## guard(장비): 효과가 지속되는 동안 아군 무리 주위 원형 도형
## focus(제갈량): 아군 무리에서 퍼지는 원형 도형 (병사 색 밝기는 ArmyView가 맡는다)

var _flash_time: float
var _lift: float
var _line_width: float
var _pulse_radius: float
var _guard_margin: float
# 기술 종류별 재질 설정: {"color", "alpha", "additive"}
var _styles: Dictionary
var _guard_disc: MeshInstance3D


func setup(tuning: Dictionary, visual: Dictionary) -> void:
	var data: Dictionary = tuning["hero_skill_view"]
	_flash_time = float(data["flash_time"])
	_lift = float(data["lift"])
	_line_width = float(data["line_width"])
	_pulse_radius = float(data["pulse_radius"])
	_guard_margin = float(data["guard_margin"])
	_styles = visual["skill_view"]

	_guard_disc = _make_disc("guard")
	_guard_disc.visible = false
	add_child(_guard_disc)


## 아군 앞에서 목표 지점까지 직선 도형을 늘리며 사라지게 한다.
func show_strike(from: Vector3, to: Vector3) -> void:
	var length := maxf(from.z - to.z, 0.1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(_line_width, length)
	var line := _make_instance(plane, "strike")
	add_child(line)
	# 아군 쪽 끝을 기준점으로 두고 전방(-Z)으로 늘린다
	line.global_position = Vector3(from.x, _lift, from.z)
	plane.center_offset = Vector3(0.0, 0.0, -length / 2.0)
	line.scale = Vector3(1.0, 1.0, 0.0)
	var tween := line.create_tween()
	tween.tween_property(line, "scale:z", 1.0, _flash_time)
	tween.parallel().tween_property(line.material_override, "albedo_color:a", 0.0, _flash_time)
	tween.tween_callback(line.queue_free)


## 아군 무리에서 퍼지는 원형 도형.
func show_pulse(center: Vector3) -> void:
	var disc := _make_disc("pulse")
	add_child(disc)
	disc.global_position = Vector3(center.x, _lift, center.z)
	disc.scale = Vector3(0.0, 1.0, 0.0)
	var tween := disc.create_tween().set_parallel()
	tween.tween_property(disc, "scale", Vector3(_pulse_radius, 1.0, _pulse_radius), _flash_time)
	tween.tween_property(disc.material_override, "albedo_color:a", 0.0, _flash_time)
	tween.chain().tween_callback(disc.queue_free)


## 지속형 원형 도형. 켜져 있는 동안 아군 무리를 따라다닌다.
func set_guard(on: bool, center: Vector3, formation_radius: float) -> void:
	_guard_disc.visible = on
	if not on:
		return
	var radius := formation_radius + _guard_margin
	_guard_disc.global_position = Vector3(center.x, _lift, center.z)
	_guard_disc.scale = Vector3(radius, 1.0, radius)


## 반지름 1인 납작한 원판. scale로 크기를 정한다.
func _make_disc(style: String) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = _lift
	return _make_instance(cylinder, style)


## 기술 종류별 색과 투명도. 더하기 혼합이면 땅 색에 빛이 얹힌 것처럼 보인다
func _make_instance(mesh: Mesh, style: String) -> MeshInstance3D:
	var data: Dictionary = _styles[style]
	var color := Color.html(data["color"])
	color.a = float(data["alpha"])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if bool(data["additive"]):
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
