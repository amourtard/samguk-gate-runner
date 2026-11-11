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


func setup(tuning: Dictionary, visual: Dictionary) -> void:
	var data: Dictionary = tuning["boss"]
	var view: Dictionary = visual["boss_view"]
	var road_width := float(tuning["road"]["width"])
	var zones := int(data["zones"])
	var length := float(data["warn_length"])
	var lift := float(data["warn_lift"])
	_warn_time = float(data["warn_time"])
	_warn_color = Color.html(data["warn_color"])
	_alpha_start = float(view["warn_alpha_start"])
	_alpha_end = float(data["warn_alpha"])
	_flash_color = Color.html(view["flash_color"])
	_flash_time = float(view["flash_time"])

	# 예고 면은 판정에 쓰는 구역 범위 그대로 그린다
	for zone in zones:
		var range_ := BossPattern.zone_range(zone, road_width, zones)
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
