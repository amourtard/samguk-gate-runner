class_name HeroView
extends Node3D
## 아군 무리 맨 앞에 서는 장수 모델과 깃발. 기술 계산과 무관한 표시다.
## 장수의 시작 병종 모델을 크게 쓰고, 장수마다 다른 색을 칠한 뒤 등에 이름 깃발을 단다.

var _behind_front: float


func setup(hero_id: String, unit_type: String, visual: Dictionary) -> void:
	var data: Dictionary = visual["hero"]
	_behind_front = float(data["behind_front"])
	var color := Color.html(data["colors"][hero_id])
	var material := ModelBuilder.make_material(color, float(visual["soldier"]["bob_height"]), float(visual["soldier"]["bob_speed"]))

	var body := MeshInstance3D.new()
	body.mesh = ModelBuilder.build(visual["models"][unit_type])
	body.material_override = material
	add_child(body)

	var flag := MeshInstance3D.new()
	flag.mesh = ModelBuilder.build(data["flag"])
	flag.material_override = material
	add_child(flag)

	var text := Label3D.new()
	text.text = data["flag_text"][hero_id]
	text.font_size = int(data["flag_font_size"])
	text.pixel_size = float(data["flag_pixel_size"])
	text.modulate = Color.html(data["flag_text_color"])
	text.outline_modulate = Color.html(data["flag_text_outline"])
	text.outline_size = int(data["flag_outline_size"])
	text.position = ModelBuilder.to_vector3(data["flag_text_pos"])
	add_child(text)

	scale = Vector3.ONE * float(data["scale"])


## 아군 무리의 앞줄(계산 위치) 바로 뒤에 선다.
func follow(army_position: Vector3, front_radius: float) -> void:
	position = Vector3(army_position.x, 0.0, army_position.z - front_radius + _behind_front)
