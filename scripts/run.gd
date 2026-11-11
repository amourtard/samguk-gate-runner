extends Node3D
## 한 판의 진행. 전진, 좌우 드래그 이동, 카메라 추종, 스테이지 배치, 교전 진행,
## 출전 직전의 책략 선택, 장수 기술, 보스전, 선택 기록을 맡는다.
## 전투 결과는 Combat, BossPattern, HeroSkill이 계산하고, 여기서는 위치와 흐름만 다룬다.

## 판이 끝나면 결과를 알린다: cleared, count, unit_type, hero, strategies, section_text, strategy_items
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
# 개발용 글자(디버그 표시) 켜고 끄기 키
const DEBUG_OVERLAY_KEY := KEY_F3

@onready var _road_view: Node3D = $RoadView
@onready var _army_view: ArmyView = $ArmyView
@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Hud = $Hud
@onready var _sfx: Sfx = $Sfx
@onready var _arrow_view: ArrowView = $ArrowView
@onready var _environment: Environment = ($WorldEnvironment as WorldEnvironment).environment
@onready var _light: DirectionalLight3D = $DirectionalLight3D

var army: Army

var _tuning: Dictionary
var _visual: Dictionary
var _units: Dictionary
var _gates: Dictionary
var _strategy: Strategy
var _hero: HeroSkill
var _pick_log: PickLog
var _stage_id: String
var _army_position := Vector3.ZERO
var _target_x := 0.0
# 좌우 이동 범위의 최소값. 실제 범위는 도로 반폭에서 무리 표시 반폭을 뺀 값이다
var _lateral_limit_min: float
var _road_width: float
var _spacing: float
var _display_limit: int
# 카메라는 아군 표시 대형 크기에 따라 물러나는 거리를 부드럽게 따라간다
var _camera_distance := -1.0
var _hero_view: HeroView
# 지금 표시 대형의 최대 폭 비율. 보스 구간에 들어가면 정해진 시간에 걸쳐 좁힌다
var _width_ratio: float
var _skill_interval: float

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
var _boss_group: EnemyGroup
# 보스 모델 높이. 체력 막대를 머리 위에 붙일 때 쓴다
var _boss_height := 0.0

# 아직 지나지 않았거나 화면에 남아 있는 게이트 쌍
var _gate_pairs: Array[GatePair] = []
var _gate_slowdown_enabled: bool
var _rng := RandomNumberGenerator.new()
# 함정 게이트로 모은 금화. 판이 끝나면 결과와 함께 넘겨 지급한다
var _bonus_gold := 0

# 지금 달리는 구간(1부터). 마지막 구간 뒤는 보스전이다
var _section := 1
var _section_count: int
var _section_length: float
# 출전 직전 책략을 고르는 동안은 달리지 않는다
var _choosing := false
var _pick_number := 0
var _pick_total := 0

# 화면 흔들림 남은 시간
var _shake_time := 0.0

# 평소 교전 피해 숫자. 앞 적 무리(보스 포함)에 준 피해를 모았다가 정해진 간격마다 하나로 띄운다
var _damage_accum := 0.0
var _damage_timer := 0.0
var _display_damage_mult: float

# 장수 기술 표시
var _skill_view: HeroSkillView
# 안내 띠를 띄운 마지막 구간
var _announced_section := 0
# 근접 충돌 지점 번쩍임
var _clash_view: ClashView
var _focus_lit := false


func _ready() -> void:
	_tuning = DataDb.table("tuning")
	_visual = DataDb.table("visual")
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
	# 영구 강화: 병영은 시작 병력을, 무기고는 공격력을 올린다
	army = Army.new(unit_type, float(_units[unit_type]["health"]), int(hero["count"]) + GameState.start_count_bonus())
	army.attack_mult *= GameState.attack_mult()
	_army_view.setup(army, _units, _tuning, _visual, Color.html(_tuning["colors"]["ally"]), -1.0, float(_visual["soldier"]["bob_height"]))
	_road_view.setup(_tuning, _visual)
	_hero_view = HeroView.new()
	add_child(_hero_view)
	_hero_view.setup(GameState.hero_id, unit_type, _visual)
	_skill_interval = float(hero["skill"]["interval"])

	_lateral_limit_min = float(_tuning["road"]["lateral_limit_min"])
	_road_width = float(_tuning["road"]["width"])
	_spacing = float(_tuning["formation"]["spacing"])
	_width_ratio = float(_tuning["formation_max_width_ratio"])
	_display_limit = int(_tuning["soldier_display_limit"])
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
	var field := FieldView.new()
	add_child(field)
	# 다리 구간 양옆은 물이라 길가 소품을 두지 않는다
	var clear_ranges: Array[Vector2] = []
	if not (plan["bridge"] as Dictionary).is_empty():
		var margin := float(_visual["bridge"]["bank"])
		clear_ranges.append(Vector2(float(plan["bridge"]["start"]) - margin, float(plan["bridge"]["end"]) + margin))
	field.setup(_environment, _light, float(plan["boss"]["distance"]), _road_width, _visual, clear_ranges)

	_hud.setup(army, _units, _tuning, _visual, _hero.name)
	_sfx.setup(_tuning)
	_arrow_view.setup(_tuning, _visual)
	_display_damage_mult = float(_tuning["display_damage_multiplier"])
	_skill_view = HeroSkillView.new()
	add_child(_skill_view)
	_skill_view.setup(_tuning, _visual)
	_clash_view = ClashView.new()
	add_child(_clash_view)
	_clash_view.setup(_visual)

	# 아군 뒤쪽 위에서 지정 각도로 내려다본다. 화각은 가로 기준이다
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = float(_visual["camera"]["fov"])
	_update_camera()
	_update_hud()
	# 달리기 전에 책략을 정해진 횟수만큼 고른다
	_pick_total = int(DataDb.table("strategies")["picks_per_run"])
	_open_strategy_choice()


# --- 배치 ---

func _spawn_enemy_groups(group_list: Array) -> void:
	var color := Color.html(_tuning["colors"]["enemy"])
	for entry in group_list:
		var group: EnemyGroup = EnemyGroupScene.instantiate()
		add_child(group)
		group.position = Vector3(0.0, 0.0, -float(entry["distance"]))
		group.section = int(entry["section"])
		group.setup(entry["units"], _units, _tuning, _visual, color)
		_enemy_groups.append(group)
	# 가까운 무리부터 상대한다
	_enemy_groups.sort_custom(func(a: EnemyGroup, b: EnemyGroup) -> bool: return a.position.z > b.position.z)


func _spawn_boss(boss: Dictionary) -> void:
	var group: EnemyGroup = BossScene.instantiate()
	add_child(group)
	group.position = Vector3(0.0, 0.0, -float(boss["distance"]))
	group.section = _section_count + 1
	group.is_boss = true
	group.setup({boss["unit"]: 1}, _units, _tuning, _visual, Color.html(_tuning["colors"]["boss"]), float(boss["health"]))
	_boss_view = group.get_node("BossView")
	_boss_view.setup(_tuning, _visual)
	_boss_group = group
	_boss_height = ModelBuilder.height_of(ModelBuilder.build(_visual["models"][boss["unit"]])) * ArmyView.model_scale(boss["unit"], _visual)
	_enemy_groups.append(group)


func _spawn_gate_pairs(pair_list: Array) -> void:
	for entry in pair_list:
		var pair: GatePair = GatePairScene.instantiate()
		add_child(pair)
		pair.position = Vector3(0.0, 0.0, -float(entry["distance"]))
		pair.section = int(entry["section"])
		pair.setup(entry["left"], entry["right"], _gates, _units, _tuning, _visual)
		_gate_pairs.append(pair)


## 좁은 다리 구간을 표시한다. 나무 다리와 난간, 양옆 물을 깐다. 이름은 구간에 들어갈 때 안내 띠로 보여준다.
func _add_bridge(start: float, end: float) -> void:
	var bridge := BridgeView.new()
	add_child(bridge)
	bridge.setup(start, end, _road_width, _visual)


# --- 입력 ---

func _unhandled_input(event: InputEvent) -> void:
	if _finished or _choosing:
		return
	if event is InputEventScreenDrag:
		# 화면 폭 대비 드래그 거리만큼 목표 위치를 옮긴다 (상대 이동)
		var screen_width := get_viewport().get_visible_rect().size.x
		var meters_per_width := float(_tuning["input"]["drag_meters_per_screen_width"])
		var limit := _lateral_limit()
		_target_x = clampf(_target_x + event.relative.x / screen_width * meters_per_width, -limit, limit)
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
		elif event.keycode == DEBUG_OVERLAY_KEY:
			_hud.toggle_debug()
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

	_update_width_ratio(delta)
	# 병력이 늘어 무리가 넓어지면 이동 범위가 줄어든다
	var limit := _lateral_limit()
	_target_x = clampf(_target_x, -limit, limit)
	_army_position.x = move_toward(_army_position.x, _target_x, float(_tuning["lateral_max_speed"]) * delta)
	_army_view.position = _army_position
	_hero_view.follow(_army_position, _army_radius())
	_update_skill_view()
	_road_view.follow(_army_position.z)
	_update_camera()
	_check_gates()
	_update_hud()
	if not _finished and _section <= _section_count and -_army_position.z >= _section * _section_length:
		_enter_next_section()


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

	_damage_timer += delta
	if _damage_timer >= float(_tuning["damage_number"]["interval"]):
		_flush_damage_number()

	_tick_accum += delta
	while _tick_accum >= _tick_interval:
		_tick_accum -= _tick_interval
		var events := _combat.tick(_tick_interval, _gap_to_front_enemy())
		_damage_accum += float(events["damage_dealt"])
		if events["contact_started"]:
			print("접촉: 아군 ", army.count, " / 적 ", _combat.enemy_count())
			_shake_time = float(_tuning["screen_shake_duration"])
			# 접촉 순간 터지는 책략을 적 무리 위에 띄운다
			var enemy_anchor := _damage_anchor(_enemy_groups[0].global_position)
			_show_strategy_trigger("fire_attack", enemy_anchor)
			_show_strategy_trigger("vanguard", enemy_anchor - Vector2(0.0, float(_visual["hud"]["delta_font_size"])))
		if events["ally_fired"] or events["enemy_fired"]:
			_sfx.play("arrow")
		# 불화살: 궁병이 아닌데 쏘았다면 일제 사격이다
		if events["ally_fired"] and float(_units[army.unit_type]["range"]) <= 0.0:
			_show_strategy_trigger("fire_arrows", _count_anchor())
		_show_arrows(events)
		if _combat.in_contact:
			_sfx.play("hit")
			_spawn_clash()

		if _combat.is_ally_defeated():
			_on_defeat()
			return
		if _combat.is_enemy_defeated():
			_on_enemy_group_defeated()
			return


func _on_enemy_group_defeated() -> void:
	# 전멸시킨 마지막 피해도 사라지기 전에 띄운다
	_flush_damage_number()
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
		var dealt := _combat.deal_direct_damage(float(events["strike_damage"]))
		_shake_time = float(_tuning["screen_shake_duration"])
		var group := _enemy_groups[0]
		_skill_view.show_strike(_army_position - Vector3(0.0, 0.0, _army_radius()), group.global_position)
		_show_strike_numbers(dealt, group)
	if _hero.skill_type() == "focus":
		_skill_view.show_pulse(_display_center())
	_hud.show_delta("%s 기술" % _hero.name, _count_anchor(), Color.html(_tuning["colors"]["hero_skill"]))
	print("%s 기술 발동" % _hero.name)


## 보스 패턴. 마지막 책략을 고른 뒤 보스가 활성 거리 안에 들어오면 돈다.
func _run_boss_pattern(delta: float) -> void:
	if _enemy_groups.is_empty() or not _enemy_groups[0].is_boss or _section <= _section_count:
		return
	if _gap_to_front_enemy() > float(_tuning["boss"]["activate_distance"]):
		return
	# 판정은 화면에 보이는 무리의 좌우 끝으로 한다. 붉은 면에 걸쳐 보이면 맞는다
	var half_width := _display_extent().x
	var before := army.count
	var in_contact := _combat != null and _combat.in_contact
	var events := _boss_pattern.tick(delta, army, _army_position.x - half_width, _army_position.x + half_width, in_contact, _rng)
	if int(events["warn_started"]) >= 0:
		_boss_view.show_warning(int(events["warn_started"]))
	if int(events["attacked"]) >= 0:
		_boss_view.flash_attack(int(events["attacked"]))
		_shake_time = float(_tuning["screen_shake_duration"])
		_sfx.play("hit")
	if events["hit"]:
		_hud.show_delta("%+d" % (army.count - before), _count_anchor(), Color.html(_tuning["colors"]["enemy"]))
		print("보스 공격 적중: ", before, " → ", army.count)
	if not army.is_alive():
		_on_defeat()


# --- 책략 ---

## 출전 직전에 책략 3택 화면을 띄운다. 정해진 횟수를 다 고를 때까지 달리지 않는다.
func _open_strategy_choice() -> void:
	_choosing = true
	_pick_number += 1
	_hud.set_overlay_hidden(true)
	_hide_world_text()
	var offer := _strategy.offer(_rng)
	var screen: StrategyChoice = StrategyChoiceScene.instantiate()
	add_child(screen)
	screen.setup(offer, _strategy, _pick_number, _pick_total)
	screen.chosen.connect(_on_strategy_chosen.bind(offer))


func _on_strategy_chosen(id: String, offer: Array[String]) -> void:
	var before := army.count
	var new_family := _strategy.add(id, army)
	var not_chosen := PackedStringArray()
	for other in offer:
		if other != id:
			not_chosen.append(other)
	# 출전 전에 고르므로 구간은 0으로 적는다
	_pick_log.write("strategy", 0, id, "|".join(not_chosen), army.unit_type, before, army.count, _strategy.owned)
	print("책략 %s 선택 (보유: %s)" % [_strategy.display_name(id), ", ".join(_strategy.owned)])
	# 같은 계열을 모으면 병사 색이 바뀐다
	if new_family != "":
		_army_view.set_color(_strategy.family_color(new_family))
	if _pick_number < _pick_total:
		_open_strategy_choice()
		return

	# 다 골랐으면 출발한다
	_choosing = false
	_hud.set_overlay_hidden(false)
	# 게이트 글자는 다음 프레임에 거리 규칙으로 다시 켜진다
	_hero_view.set_flag_text_visible(true)
	if new_family != "":
		_hud.show_delta("%s 계열 효과" % _strategy.family_name(new_family), _count_anchor(), _strategy.family_color(new_family))
	_start_section()


## 구간 끝에 닿으면 멈추지 않고 다음 구간으로 넘어간다. 마지막 구간 뒤에는 보스전이 이어진다.
func _enter_next_section() -> void:
	_section += 1
	_start_section()


## 구간(보스전 포함)을 시작할 때: 지형 안내와 의병의 병력 추가
func _start_section() -> void:
	_announce_section()
	var add := _strategy.section_start_add()
	if add > 0:
		army.set_count(army.count + add)
		_hud.show_delta("의병\n%+d" % add, _count_anchor(), _strategy_color("volunteers"))
	_update_hud()


func _strategy_color(id: String) -> Color:
	return _strategy.family_color(_strategy.family_of(id))


## 책략이 작동한 순간 그 이름을 계열 색으로 띄운다. 가진 책략만 띄운다.
func _show_strategy_trigger(id: String, screen_pos: Vector2) -> void:
	if _strategy.has(id):
		_hud.show_delta(_strategy.display_name(id), screen_pos, _strategy_color(id))


# --- 게이트 ---

## 아군 중심이 통과선을 지나면 좌우 위치로 고른 게이트의 효과를 적용한다.
func _check_gates() -> void:
	var remove_behind := float(_tuning["gate_view"]["remove_behind"])
	for pair in _gate_pairs.duplicate():
		# 전환 게이트의 대상이 지금 병종과 같으면 다른 종류의 게이트로 바꾼다(명세 3장)
		if not pair.passed:
			pair.avoid_switch_unit(army.unit_type, _rng)
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
			pair.play_pass(_army_position.x)
			print("게이트 %s: %s" % [_gates[spec["type"]]["name"], str(result["popup"]).replace("\n", " ")])
			if not army.is_alive():
				_on_defeat()
				return
		# 먼 게이트의 글자는 숨겨 화면 위쪽에 겹쳐 보이지 않게 한다
		if not pair.passed:
			var ahead: float = _army_position.z - pair.position.z
			pair.set_text_visible(ahead <= float(_visual["gate"]["text_hide_distance"]))
			# 가까이 오면 지금 선택될 칸을 밝게 보여준다. 판정과 같은 기준(무리 중심)이다
			pair.set_choice_preview(GatePair.side_for_x(_army_position.x) if ahead <= float(_visual["gate"]["preview_distance"]) else -1)
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
	_hud.set_overlay_hidden(true)
	_hide_world_text()
	print("돌파" if cleared else "패배")
	_pick_log.write("result", mini(_section, _section_count + 1), "clear" if cleared else "lose", "", army.unit_type, army.count, army.count, _strategy.owned)
	_update_hud()
	finished.emit({
		"cleared": cleared,
		"count": army.count,
		"hero": _hero.name,
		"strategies": _owned_text(),
		"unit_type": army.unit_type,
		"section_text": _reached_text(cleared),
		"strategy_items": _strategy_items(),
		"bonus_gold": _bonus_gold,
	})


## 책략 선택과 결과 화면 뒤로 전장의 글자(게이트, 깃발)가 비치지 않게 숨긴다.
func _hide_world_text() -> void:
	for pair in _gate_pairs:
		pair.set_text_visible(false)
	_hero_view.set_flag_text_visible(false)


## 지형이 있는 구간에 처음 들어가면 화면 위쪽 안내 띠로 알린다.
func _announce_section() -> void:
	if _announced_section == _section:
		return
	_announced_section = _section
	if _section == _bridge_section:
		_hud.show_banner("좁은 다리")


## 결과 화면의 "도달": 돌파면 보스 격파, 아니면 끝난 구간
func _reached_text(cleared: bool) -> String:
	if cleared:
		return "보스 격파"
	if _section > _section_count:
		return "보스전"
	return "구간 %d/%d" % [_section, _section_count]


func _strategy_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for id in _strategy.owned:
		var family := _strategy.family_of(id)
		items.append({"name": _strategy.display_name(id), "family": family, "color": _strategy.family_color(family)})
	return items


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


## 아군 앞줄(계산 위치)의 접촉선에 충돌 번쩍임을 띄운다.
func _spawn_clash() -> void:
	var front := Vector3(_army_position.x, 0.0, _army_position.z - _army_radius())
	_clash_view.spawn(front, _display_extent().x * float(_visual["clash"]["width_ratio"]))


## 모은 피해를 표시 배율을 곱해 앞 적 무리 위에 하나로 띄운다.
func _flush_damage_number() -> void:
	_damage_timer = 0.0
	var value := roundi(_damage_accum * _display_damage_mult)
	_damage_accum = 0.0
	if value <= 0 or _enemy_groups.is_empty():
		return
	_hud.show_damage(value, _damage_anchor(_enemy_groups[0].global_position))


## 장수 공격 기술의 피해를 여러 개로 나눠 맞은 적 무리 위에 흩뿌린다. 합계는 실제 피해 × 표시 배율이다.
func _show_strike_numbers(dealt: float, group: EnemyGroup) -> void:
	var total := roundi(dealt * _display_damage_mult)
	if total <= 0:
		return
	var range_data: Dictionary = _tuning["hero_skill_view"]["strike_numbers"]
	var pieces := _rng.randi_range(int(range_data["min"]), int(range_data["max"]))
	var weights: Array[float] = []
	var weight_sum := 0.0
	for i in pieces:
		# 조각 크기가 너무 고르지도, 너무 작지도 않게 정해진 범위에서 뽑는다
		var weight := _rng.randf_range(float(range_data["weight_min"]), float(range_data["weight_max"]))
		weights.append(weight)
		weight_sum += weight
	var scatter := float(_tuning["damage_number"]["scatter"])
	var shown := 0
	for i in pieces:
		var value := total - shown if i == pieces - 1 else roundi(total * weights[i] / weight_sum)
		shown += value
		if value <= 0:
			continue
		var offset := Vector3(_rng.randf_range(-scatter, scatter), _rng.randf_range(0.0, scatter), _rng.randf_range(-scatter, scatter))
		_hud.show_damage(value, _damage_anchor(group.global_position + offset))


## 적 무리 머리 위의 화면 좌표
func _damage_anchor(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos + Vector3.UP * float(_tuning["damage_number"]["height"]))


## 지속형 기술 표시. 장비는 원형 도형, 제갈량은 병사 밝기를 효과가 켜진 동안 유지한다.
func _update_skill_view() -> void:
	var active := _hero.is_active()
	_skill_view.set_guard(active and _hero.skill_type() == "guard", _display_center(), _display_extent().y)
	var lit := active and _hero.skill_type() == "focus"
	if lit != _focus_lit:
		_focus_lit = lit
		_army_view.set_brightness(float(_tuning["hero_skill_view"]["brighten"]) if lit else 0.0)


func _gap_to_front_enemy() -> float:
	var ally_front := _army_position.z - _army_radius()
	return ally_front - _enemy_groups[0].position.z


func _army_radius() -> float:
	return ArmyView.formation_radius(army.count, _spacing)


## 아군 표시 대형의 반폭(x)과 앞뒤 반길이(y)
func _display_extent() -> Vector2:
	return ArmyView.display_extent(army.count, _visual, _display_limit, _road_width, _width_ratio)


## 보스 구간에서는 대형 최대 폭을 정해진 시간에 걸쳐 좁힌다(명세 4장 보스 장각).
func _update_width_ratio(delta: float) -> void:
	var normal := float(_tuning["formation_max_width_ratio"])
	var boss := float(_tuning["boss_formation_max_width_ratio"])
	var target := boss if _section > _section_count else normal
	var speed := absf(normal - boss) / float(_tuning["boss_formation_shrink_time"])
	_width_ratio = move_toward(_width_ratio, target, speed * delta)
	_army_view.set_max_width_ratio(_width_ratio)


## 좌우 이동 범위: 도로 반폭 − 무리 표시 반폭. 무리가 길 밖으로 나가지 않게 하되 최소값은 보장한다
func _lateral_limit() -> float:
	return maxf(_road_width / 2.0 - _display_extent().x, _lateral_limit_min)


## 아군 표시 대형의 중심. 앞줄을 계산 위치에 맞추느라 계산 중심보다 조금 뒤에 있다.
func _display_center() -> Vector3:
	return _army_position + Vector3(0.0, 0.0, maxf(_display_extent().y - _army_radius(), 0.0))


func _update_camera() -> void:
	# 좌우는 따라가지 않고 전진 방향만 따라가 도로가 화면 중앙에 머물게 한다.
	# 아군 무리가 화면 높이의 정해진 위치(아래에서 3분의 1 근처)에 오도록 내려다보는 각을 더한다
	var data: Dictionary = _visual["camera"]
	var pitch := deg_to_rad(float(data["pitch_deg"]))
	var view_size := get_viewport().get_visible_rect().size
	var half_vfov := atan(tan(deg_to_rad(_camera.fov) / 2.0) * view_size.y / view_size.x)
	var depression := pitch + atan((float(data["army_screen_y"]) - 0.5) * 2.0 * tan(half_vfov))
	var target_distance := float(data["distance_base"]) + float(data["distance_per_radius"]) * _display_extent().y
	if _camera_distance < 0.0:
		_camera_distance = target_distance
	else:
		var weight := 1.0 - exp(-float(data["follow_rate"]) * get_process_delta_time())
		_camera_distance = lerpf(_camera_distance, target_distance, weight)
	var anchor := Vector3(0.0, 0.0, _display_center().z)
	_camera.position = anchor + Vector3(0.0, sin(depression), cos(depression)) * _camera_distance
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
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
	var stage_text := "%s   %s" % [_stage_id, "보스전" if _section > _section_count else "구간 %d/%d" % [mini(_section, _section_count), _section_count]]
	if _section == _bridge_section:
		stage_text += "   좁은 다리"
	_hud.set_stage_text(stage_text)
	_hud.set_skill(1.0 - _hero.time_left() / _skill_interval, _hero.is_active())
	var owned: Array[Dictionary] = []
	for id in _strategy.owned:
		var family := _strategy.family_of(id)
		owned.append({"family": family, "color": _strategy.family_color(family)})
	_hud.set_strategies(owned)
	_update_boss_bar()
	var section_text := "보스전" if _section > _section_count else "구간 %d/%d" % [_section, _section_count]
	if _section == _bridge_section:
		section_text += " (좁은 다리)"
	var skill_text := "발동 중" if _hero.is_active() else "%d초" % ceili(_hero.time_left())
	_hud.set_status("%s %s   %s   책략: %s\n%s 기술 %s   감속 %s (G)   함정 금화 %d" % [
		_stage_id, _hero.name, section_text, _owned_text(),
		_hero.name, skill_text, "켜짐" if _gate_slowdown_enabled else "꺼짐", _bonus_gold])


## 보스가 화면에 들어오면 머리 위에 이름을 붙인다. 체력은 상단 띠에 보인다.
func _update_boss_bar() -> void:
	if _boss_group == null or not is_instance_valid(_boss_group) or _boss_group.is_queued_for_deletion():
		_hud.set_boss(false, "", Vector2.ZERO)
		return
	var pool: Army = _boss_group.pools[0]
	var center: Vector3 = (_boss_group.views[pool.unit_type] as ArmyView).display_center()
	var head := center + Vector3.UP * (_boss_height + float(_visual["boss_view"]["name_above"]))
	var shown := _gap_to_boss() <= float(_visual["gate"]["text_hide_distance"]) and not _camera.is_position_behind(head)
	_hud.set_boss(shown and pool.is_alive(), _units[pool.unit_type]["name"], _camera.unproject_position(head))


func _gap_to_boss() -> float:
	return _army_position.z - _boss_group.position.z


func _owned_text() -> String:
	var names: PackedStringArray = []
	for id in _strategy.owned:
		names.append(_strategy.display_name(id))
	return ", ".join(names) if not names.is_empty() else "없음"


## 무리 머리 위의 화면 좌표. 표시 대형 중심 위, 병사 키보다 조금 높은 곳이다
func _count_anchor() -> Vector2:
	var height := ModelBuilder.height_of(_army_view.multimesh.mesh) + float(_visual["hud"]["count_height"])
	return _camera.unproject_position(_display_center() + Vector3.UP * height)
