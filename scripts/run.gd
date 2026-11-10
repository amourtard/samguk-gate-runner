extends Node3D
## 한 판의 진행. 전진, 좌우 드래그 이동, 카메라 추종, 스테이지 배치, 교전 진행,
## 구간이 끝날 때의 책략 선택, 장수 기술, 보스전, 선택 기록을 맡는다.
## 전투 결과는 Combat, BossPattern, HeroSkill이 계산하고, 여기서는 위치와 흐름만 다룬다.

## 판이 끝나면 결과를 알린다: cleared, count, hero, strategies
signal finished(result: Dictionary)

const EnemyGroupScene := preload("res://scenes/enemy_group.tscn")
const BossScene := preload("res://scenes/boss.tscn")
const GatePairScene := preload("res://scenes/gate_pair.tscn")
const StrategyChoiceScene := preload("res://scenes/ui/strategy_choice.tscn")

# 확인용 병력 증감 키
const DEBUG_ADD_KEY := KEY_UP
const DEBUG_SUB_KEY := KEY_DOWN
# 확인용 병종 전환 키
const DEBUG_UNIT_KEYS := {KEY_1: "infantry", KEY_2: "archer", KEY_3: "cavalry"}
# 게이트 앞 감속 켜고 끄기 키 (켠 판과 끈 판 비교용)
const SLOWDOWN_TOGGLE_KEY := KEY_G

@onready var _road_view: Node3D = $RoadView
@onready var _army_view: ArmyView = $ArmyView
@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Hud = $Hud
@onready var _sfx: Sfx = $Sfx
@onready var _arrow_view: ArrowView = $ArrowView

var army: Army

var _tuning: Dictionary
var _units: Dictionary
var _gates: Dictionary
var _strategy: Strategy
var _hero: HeroSkill
var _pick_log: PickLog
var _stage_id: String
var _army_position := Vector3.ZERO
var _target_x := 0.0
var _lateral_limit: float
var _road_width: float
var _camera_offset: Vector3
var _camera_look_ahead: float
var _spacing: float

# 앞에서부터 차례로 상대할 적 무리(마지막이 보스)
var _enemy_groups: Array[EnemyGroup] = []
var _combat: Combat
var _tick_interval: float
var _tick_accum := 0.0
var _finished := false
var _bridge_section := 0

# 보스 패턴. 마지막 책략을 고른 뒤 보스에 가까워지면 움직인다
var _boss_pattern: BossPattern
var _boss_view: BossView

# 아직 지나지 않았거나 화면에 남아 있는 게이트 쌍
var _gate_pairs: Array[GatePair] = []
var _gate_slowdown_enabled: bool
var _rng := RandomNumberGenerator.new()
# 함정 게이트로 모은 금화. 판 종료 시 지급은 단계 6에서 붙인다
var _bonus_gold := 0

# 지금 달리는 구간(1부터). 구간 끝에 닿으면 책략을 고른다. 마지막 구간 뒤는 보스전이다
var _section := 1
var _section_count: int
var _section_length: float
var _choosing := false

# 화면 흔들림 남은 시간
var _shake_time := 0.0


func _ready() -> void:
	_tuning = DataDb.table("tuning")
	_units = DataDb.table("units")
	_gates = DataDb.table("gates")
	_strategy = Strategy.new(DataDb.table("strategies"))
	# randomize() 직후 첫 값이 한쪽으로 치우쳐서 엔진 시작 때 섞인 전역 난수로 시드를 정한다
	_rng.seed = randi()

	var stage := GameState.current_stage()
	var hero := GameState.current_hero()
	_stage_id = stage["id"]
	_hero = HeroSkill.new(GameState.hero_id, hero)
	_pick_log = PickLog.new(_stage_id, GameState.hero_id)

	var unit_type: String = hero["unit"]
	army = Army.new(unit_type, float(_units[unit_type]["health"]), int(hero["count"]))
	_army_view.setup(army, _units, _tuning, Color.html(_tuning["colors"]["ally"]))
	_road_view.setup(_tuning)

	_lateral_limit = float(_tuning["road"]["lateral_limit"])
	_road_width = float(_tuning["road"]["width"])
	_spacing = float(_tuning["formation"]["spacing"])
	_tick_interval = float(_tuning["combat"]["tick"])
	_gate_slowdown_enabled = bool(_tuning["gate_slowdown"]["enabled"])
	_boss_pattern = BossPattern.new(_tuning)

	var plan := StageBuilder.plan(stage, DataDb.table("stages"), _gates, _units, _tuning, _rng)
	_section_count = int(plan["sections"])
	_section_length = float(plan["section_length"])
	_bridge_section = int(plan["bridge_section"])
	_spawn_enemy_groups(plan["enemy_groups"])
	_spawn_boss(plan["boss"])
	_spawn_gate_pairs(plan["gate_pairs"])
	if not (plan["bridge"] as Dictionary).is_empty():
		_add_bridge(float(plan["bridge"]["start"]), float(plan["bridge"]["end"]))

	_hud.setup(army, _units, _tuning)
	_sfx.setup(_tuning)
	_arrow_view.setup(_tuning)

	# 아군 뒤쪽 위에서 지정 각도로 내려다본다
	var camera_data: Dictionary = _tuning["camera"]
	var pitch := deg_to_rad(float(camera_data["pitch_deg"]))
	var distance := float(camera_data["distance"])
	_camera_offset = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	_camera_look_ahead = float(camera_data["look_ahead"])
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = float(camera_data["fov"])
	_update_camera()
	_update_hud()


# --- 배치 ---

func _spawn_enemy_groups(group_list: Array) -> void:
	var color := Color.html(_tuning["colors"]["enemy"])
	for entry in group_list:
		var group: EnemyGroup = EnemyGroupScene.instantiate()
		add_child(group)
		group.position = Vector3(0.0, 0.0, -float(entry["distance"]))
		group.section = int(entry["section"])
		group.setup(entry["units"], _units, _tuning, color)
		_enemy_groups.append(group)
	# 가까운 무리부터 상대한다
	_enemy_groups.sort_custom(func(a: EnemyGroup, b: EnemyGroup) -> bool: return a.position.z > b.position.z)


func _spawn_boss(boss: Dictionary) -> void:
	var group: EnemyGroup = BossScene.instantiate()
	add_child(group)
	group.position = Vector3(0.0, 0.0, -float(boss["distance"]))
	group.section = _section_count + 1
	group.is_boss = true
	group.setup({boss["unit"]: 1}, _units, _tuning, Color.html(_tuning["colors"]["boss"]), float(boss["health"]))
	_boss_view = group.get_node("BossView")
	_boss_view.setup(_units[boss["unit"]]["name"], _tuning)
	_enemy_groups.append(group)


func _spawn_gate_pairs(pair_list: Array) -> void:
	for entry in pair_list:
		var pair: GatePair = GatePairScene.instantiate()
		add_child(pair)
		pair.position = Vector3(0.0, 0.0, -float(entry["distance"]))
		pair.setup(entry["left"], entry["right"], _gates, _units, _tuning)
		_gate_pairs.append(pair)


## 좁은 다리 구간을 표시한다. 도로 위에 다리 판을 깔고 양옆을 물로 칠한다.
func _add_bridge(start: float, end: float) -> void:
	var road: Dictionary = _tuning["road"]
	var length := end - start
	var center_z := -(start + end) / 2.0
	var lift := float(road["overlay_lift"])
	var water_width := float(road["ground_size"]) / 2.0
	_add_flat(Vector2(_road_width, length), Vector3(0.0, lift, center_z), Color.html(_tuning["colors"]["bridge"]))
	for side in [-1.0, 1.0]:
		var x: float = side * (_road_width + water_width) / 2.0
		_add_flat(Vector2(water_width, length), Vector3(x, lift, center_z), Color.html(_tuning["colors"]["water"]))

	var label := Label3D.new()
	label.text = "좁은 다리"
	label.font_size = int(_tuning["gate_view"]["label_font_size"])
	label.pixel_size = float(_tuning["gate_view"]["label_pixel_size"])
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, float(_tuning["gate_view"]["height"]), -start)
	add_child(label)


func _add_flat(size: Vector2, at: Vector3, color: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.material_override = material
	instance.position = at
	add_child(instance)


# --- 입력 ---

func _unhandled_input(event: InputEvent) -> void:
	if _finished or _choosing:
		return
	if event is InputEventScreenDrag:
		# 화면 폭 대비 드래그 거리만큼 목표 위치를 옮긴다 (상대 이동)
		var screen_width := get_viewport().get_visible_rect().size.x
		var meters_per_width := float(_tuning["input"]["drag_meters_per_screen_width"])
		_target_x = clampf(_target_x + event.relative.x / screen_width * meters_per_width, -_lateral_limit, _lateral_limit)
	elif event is InputEventKey and event.pressed and not event.echo:
		var step := int(_tuning["debug"]["count_step"])
		if event.keycode == DEBUG_ADD_KEY:
			army.set_count(army.count + step)
		elif event.keycode == DEBUG_SUB_KEY:
			army.set_count(army.count - step)
		elif DEBUG_UNIT_KEYS.has(event.keycode):
			var unit_type: String = DEBUG_UNIT_KEYS[event.keycode]
			army.set_unit_type(unit_type, float(_units[unit_type]["health"]))
		elif event.keycode == SLOWDOWN_TOGGLE_KEY:
			_gate_slowdown_enabled = not _gate_slowdown_enabled
		_update_hud()


# --- 진행 ---

func _process(delta: float) -> void:
	if _finished or _choosing:
		return

	_run_combat(delta)
	if _finished:
		return
	_run_hero_skill(delta)
	_run_boss_pattern(delta)
	if _finished:
		return

	# 규칙 3: 근접 교전 중에는 전진 속도가 떨어진다
	var speed := float(_tuning["advance_speed"])
	if _combat != null and _combat.in_contact:
		speed *= float(_tuning["combat_advance_ratio"])
	if _is_before_gate():
		speed *= float(_tuning["gate_slowdown"]["speed_ratio"])
	_army_position.z -= speed * delta

	# 적 무리 앞줄을 뚫고 지나가지 않는다
	if not _enemy_groups.is_empty():
		var stop_z := _enemy_groups[0].position.z + _army_radius()
		_army_position.z = maxf(_army_position.z, stop_z)

	_army_position.x = move_toward(_army_position.x, _target_x, float(_tuning["lateral_max_speed"]) * delta)
	_army_view.position = _army_position
	_road_view.follow(_army_position.z)
	_update_camera()
	_check_gates()
	_update_hud()
	if not _finished and _section <= _section_count and -_army_position.z >= _section * _section_length:
		_open_strategy_choice()


## 정해진 간격마다 가장 가까운 적 무리와의 교전을 계산한다.
func _run_combat(delta: float) -> void:
	if _enemy_groups.is_empty():
		return
	if _combat == null:
		var group := _enemy_groups[0]
		# 좁은 다리 구간의 무리와는 근접 동시 교전 수가 줄어든다
		var limit_key := "melee_engage_limit_bridge" if group.section == _bridge_section else "melee_engage_limit"
		_combat = Combat.new(army, group.pools, _units, _tuning, int(_tuning[limit_key]), _strategy)
		_tick_accum = 0.0

	_tick_accum += delta
	while _tick_accum >= _tick_interval:
		_tick_accum -= _tick_interval
		var events := _combat.tick(_tick_interval, _gap_to_front_enemy())
		if events["contact_started"]:
			print("접촉: 아군 ", army.count, " / 적 ", _combat.enemy_count())
			_shake_time = float(_tuning["screen_shake_duration"])
		if events["ally_fired"] or events["enemy_fired"]:
			_sfx.play("arrow")
		_show_arrows(events)
		if _combat.in_contact:
			_sfx.play("hit")

		if _combat.is_ally_defeated():
			_on_defeat()
			return
		if _combat.is_enemy_defeated():
			_on_enemy_group_defeated()
			return


func _on_enemy_group_defeated() -> void:
	var group: EnemyGroup = _enemy_groups.pop_front()
	print("적 무리 전멸. 남은 아군 ", army.count)
	_combat = null
	if group.is_boss:
		_boss_view.hide_warning()
		_on_clear()
	group.queue_free()


## 장수 기술. 전방 적 무리까지의 거리를 넘겨 공격 기술의 발동 여부를 정한다.
func _run_hero_skill(delta: float) -> void:
	var gap := INF
	if not _enemy_groups.is_empty():
		gap = maxf(_gap_to_front_enemy(), 0.0)
	var events := _hero.tick(delta, army, gap)
	if not events["activated"]:
		return
	if float(events["strike_damage"]) > 0.0 and _combat != null:
		_combat.deal_direct_damage(float(events["strike_damage"]))
		_shake_time = float(_tuning["screen_shake_duration"])
	_hud.show_delta("%s 기술" % _hero.name, _count_anchor(), Color.html(_tuning["colors"]["hero_skill"]))
	print("%s 기술 발동" % _hero.name)


## 보스 패턴. 마지막 책략을 고른 뒤 보스가 활성 거리 안에 들어오면 돈다.
func _run_boss_pattern(delta: float) -> void:
	if _enemy_groups.is_empty() or not _enemy_groups[0].is_boss or _section <= _section_count:
		return
	if _gap_to_front_enemy() > float(_tuning["boss"]["activate_distance"]):
		return
	var zones := int(_tuning["boss"]["zones"])
	var ally_zone := BossPattern.zone_of(_army_position.x, _road_width, zones)
	var before := army.count
	var in_contact := _combat != null and _combat.in_contact
	var events := _boss_pattern.tick(delta, army, ally_zone, in_contact, _rng)
	if int(events["warn_started"]) >= 0:
		_boss_view.show_warning(int(events["warn_started"]))
	if int(events["attacked"]) >= 0:
		_boss_view.hide_warning()
		_shake_time = float(_tuning["screen_shake_duration"])
		_sfx.play("hit")
	if events["hit"]:
		_hud.show_delta("%+d" % (army.count - before), _count_anchor(), Color.html(_tuning["colors"]["enemy"]))
		print("보스 공격 적중: ", before, " → ", army.count)
	if not army.is_alive():
		_on_defeat()


# --- 책략 ---

## 구간 끝에서 책략 3택 화면을 띄우고 진행을 멈춘다.
func _open_strategy_choice() -> void:
	_choosing = true
	var offer := _strategy.offer(_rng)
	var screen: StrategyChoice = StrategyChoiceScene.instantiate()
	add_child(screen)
	screen.setup(offer, _strategy, _section, _section_count)
	screen.chosen.connect(_on_strategy_chosen.bind(offer))


func _on_strategy_chosen(id: String, offer: Array[String]) -> void:
	var before := army.count
	var new_family := _strategy.add(id, army)
	var not_chosen := PackedStringArray()
	for other in offer:
		if other != id:
			not_chosen.append(other)
	_pick_log.write("strategy", _section, id, "|".join(not_chosen), army.unit_type, before, army.count, _strategy.owned)
	print("책략 %s 선택 (보유: %s)" % [_strategy.display_name(id), ", ".join(_strategy.owned)])
	if army.count != before:
		_hud.show_delta("%s\n%+d" % [_strategy.display_name(id), army.count - before], _count_anchor(), Color.WHITE)
	# 같은 계열을 모으면 병사 색이 바뀐다
	if new_family != "":
		_army_view.set_color(_strategy.family_color(new_family))
		_hud.show_delta("%s 계열 효과" % _strategy.family_name(new_family), _count_anchor(), _strategy.family_color(new_family))

	# 마지막 구간 뒤에는 보스전이 이어진다
	_section += 1
	_choosing = false
	# 의병: 새 구간(보스전 포함)을 시작할 때 병력 추가
	var add := _strategy.section_start_add()
	if add > 0:
		army.set_count(army.count + add)
		_hud.show_delta("의병\n%+d" % add, _count_anchor(), Color.WHITE)
	_update_hud()


# --- 게이트 ---

## 아군 중심이 통과선을 지나면 좌우 위치로 고른 게이트의 효과를 적용한다.
func _check_gates() -> void:
	var remove_behind := float(_tuning["gate_view"]["remove_behind"])
	for pair in _gate_pairs.duplicate():
		if not pair.passed and _army_position.z <= pair.position.z:
			pair.passed = true
			var spec: Dictionary = pair.spec_for_x(_army_position.x)
			var other: Dictionary = pair.right_spec if spec == pair.left_spec else pair.left_spec
			var before := army.count
			var result := Gate.apply(army, spec, _gates, _units, _rng, _strategy)
			_pick_log.write("gate", _section, _gate_id(spec), _gate_id(other), army.unit_type, before, army.count, _strategy.owned)
			_bonus_gold += int(result["gold"])
			_sfx.play("gate")
			var color := Color.html(_gates[spec["type"]]["color"]).lightened(float(_tuning["delta_popup"]["lighten"]))
			_hud.show_delta(result["popup"], _count_anchor(), color)
			print("게이트 %s: %s" % [_gates[spec["type"]]["name"], str(result["popup"]).replace("\n", " ")])
			if not army.is_alive():
				_on_defeat()
				return
		# 지나간 게이트는 화면 뒤로 충분히 멀어지면 지운다
		if pair.passed and pair.position.z > _army_position.z + remove_behind:
			_gate_pairs.erase(pair)
			pair.queue_free()


## 기록용 게이트 이름. 예: reinforce:add_20, switch:archer
func _gate_id(spec: Dictionary) -> String:
	var id: String = spec["type"]
	if spec.has("option"):
		id += ":" + str(spec["option"])
	if spec.has("unit"):
		id += ":" + str(spec["unit"])
	return id


## 감속이 켜져 있고 아직 지나지 않은 게이트가 감속 거리 안에 있는가
func _is_before_gate() -> bool:
	if not _gate_slowdown_enabled:
		return false
	var slow_distance := float(_tuning["gate_slowdown"]["distance"])
	for pair in _gate_pairs:
		if pair.passed:
			continue
		var ahead := _army_position.z - pair.position.z
		if ahead > 0.0 and ahead <= slow_distance:
			return true
	return false


# --- 종료 ---

func _on_defeat() -> void:
	_finish(false)


func _on_clear() -> void:
	_finish(true)


func _finish(cleared: bool) -> void:
	if _finished:
		return
	_finished = true
	print("돌파" if cleared else "패배")
	_pick_log.write("result", mini(_section, _section_count + 1), "clear" if cleared else "lose", "", army.unit_type, army.count, army.count, _strategy.owned)
	_update_hud()
	finished.emit({
		"cleared": cleared,
		"count": army.count,
		"hero": _hero.name,
		"strategies": _owned_text(),
	})


# --- 보조 ---

## 사격 사건을 화살 연출로 보여준다. 아군은 적 앞줄로, 적 궁병은 아군 무리로 쏜다.
func _show_arrows(events: Dictionary) -> void:
	var group := _enemy_groups[0]
	if events["ally_fired"]:
		_arrow_view.fire("ally", _army_position, group.global_position)
	if events["enemy_fired"]:
		for pool in group.pools:
			if pool.is_alive() and float(_units[pool.unit_type]["range"]) > 0.0:
				_arrow_view.fire("enemy_" + pool.unit_type, group.pool_center(pool.unit_type), _army_position)


func _gap_to_front_enemy() -> float:
	var ally_front := _army_position.z - _army_radius()
	return ally_front - _enemy_groups[0].position.z


func _army_radius() -> float:
	return ArmyView.formation_radius(army.count, _spacing)


func _update_camera() -> void:
	# 좌우는 따라가지 않고 전진 방향만 따라가 도로가 화면 중앙에 머물게 한다
	var target := Vector3(0.0, 0.0, _army_position.z - _camera_look_ahead)
	_camera.position = target + _camera_offset
	_camera.look_at(target)
	# 근접 접촉과 보스 공격 순간 짧게 흔든다
	if _shake_time > 0.0:
		_shake_time -= get_process_delta_time()
		var strength := float(_tuning["screen_shake_strength"])
		_camera.position += Vector3(_rng.randf_range(-strength, strength), _rng.randf_range(-strength, strength), 0.0)


func _update_hud() -> void:
	_hud.set_count_anchor(_count_anchor())
	var pools: Array[Army] = []
	if not _enemy_groups.is_empty():
		pools = _enemy_groups[0].pools
	_hud.set_next_enemy(pools)
	var section_text := "보스전" if _section > _section_count else "구간 %d/%d" % [_section, _section_count]
	if _section == _bridge_section:
		section_text += " (좁은 다리)"
	var skill_text := "발동 중" if _hero.is_active() else "%d초" % ceili(_hero.time_left())
	_hud.set_status("%s %s   %s   책략: %s\n%s 기술 %s   감속 %s (G)   함정 금화 %d" % [
		_stage_id, _hero.name, section_text, _owned_text(),
		_hero.name, skill_text, "켜짐" if _gate_slowdown_enabled else "꺼짐", _bonus_gold])


func _owned_text() -> String:
	var names: PackedStringArray = []
	for id in _strategy.owned:
		names.append(_strategy.display_name(id))
	return ", ".join(names) if not names.is_empty() else "없음"


## 무리 머리 위의 화면 좌표
func _count_anchor() -> Vector2:
	var head := _army_position + Vector3.UP * float(_tuning["hud"]["count_label_height"])
	return _camera.unproject_position(head)
