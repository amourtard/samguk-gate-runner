class_name HeroView
extends Node3D
## 아군 무리 맨 앞줄보다 한 걸음 앞에 서는 장수 모델과 깃발. 기술 계산과 무관한 표시다.
## 장수의 시작 병종 모델을 크게 쓰고, 장수마다 다른 색을 칠한 뒤 등에 이름 깃발을 단다.

var _ahead_front: float
var _flag_texts: Array[Label3D] = []


func setup(hero_id: String, unit_type: String, visual: Dictionary) -> void:
	var data: Dictionary = visual["hero"]
	_ahead_front = float(data["ahead_front"])
	var color := Color.html(data["colors"][hero_id])
	var material := ModelBuilder.make_material(color, float(visual["soldier"]["bob_height"]), float(visual["soldier"]["bob_speed"]))

	var body := MeshInstance3D.new()
	# 장수마다 따로 만든 모델이 있으면 그것을, 없으면 시작 병종 모델을 쓴다
	var hero_model := "hero_" + hero_id
	body.mesh = ModelBuilder.model(hero_model if (visual.get("model_files", {}) as Dictionary).has(hero_model) else unit_type, visual)
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
	_flag_texts.append(text)

	# 깃발 앞면에도 같은 글자를 붙인다(장수 선택 화면은 앞에서 본다). 뒤에서는 깃발에 가려 보이지 않는다
	var front := text.duplicate() as Label3D
	front.position = ModelBuilder.to_vector3(data["flag_text_front_pos"])
	front.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	front.double_sided = false
	add_child(front)
	_flag_texts.append(front)

	scale = Vector3.ONE * float(data["scale"])


func set_flag_text_visible(on: bool) -> void:
	for text in _flag_texts:
		text.visible = on


## 아군 무리의 앞줄(계산 위치)보다 한 걸음 앞에 선다.
func follow(army_position: Vector3, front_radius: float) -> void:
	position = Vector3(army_position.x, 0.0, army_position.z - front_radius - _ahead_front)
