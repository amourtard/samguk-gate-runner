class_name Combat
extends RefCounted
## 아군 무리 하나와 적 무리 하나의 교전 계산. 노드와 렌더링에 의존하지 않는다.
## 명세 4장 전투 규칙 1~7과 책략의 전투 효과를 따른다. 호출하는 쪽이 계산 간격마다 tick()을 부른다.

var ally: Army
# 적 무리의 병종별 병력. 앞줄 순서(보병, 기병, 궁병)로 정렬해 둔다
var enemies: Array[Army] = []
var in_contact := false

var _units: Dictionary
var _strategy: Strategy
var _contact_distance: float
var _advantage_mult: float
var _melee_limit: int
var _ranged_limit: int
# 적에게 걸린 지속 피해 목록. 각 항목은 {"rate": 초당 피해, "time": 남은 시간}
var _dots: Array[Dictionary] = []
var _volley_timer := 0.0


func _init(p_ally: Army, p_enemies: Array[Army], units: Dictionary, tuning: Dictionary, melee_limit: int, strategy: Strategy) -> void:
	ally = p_ally
	_units = units
	_strategy = strategy
	var combat_data: Dictionary = tuning["combat"]
	_contact_distance = float(combat_data["contact_distance"])
	_advantage_mult = float(combat_data["advantage_multiplier"])
	_melee_limit = melee_limit
	_ranged_limit = int(tuning["ranged_fire_limit"])

	# 앞줄 순서대로 정렬한다
	for unit_type in combat_data["front_order"]:
		for pool in p_enemies:
			if pool.unit_type == unit_type:
				enemies.append(pool)


## 한 번의 계산. gap은 두 무리 앞줄 사이의 거리(m)다.
## 반환값은 연출용 사건 기록이다: contact_started, ally_fired, enemy_fired,
## damage_dealt(이번 계산에서 적 무리 체력이 실제로 줄어든 양)
func tick(dt: float, gap: float) -> Dictionary:
	var events := {"contact_started": false, "ally_fired": false, "enemy_fired": false, "damage_dealt": 0.0}
	if is_finished():
		return events
	var enemy_health_before := _enemy_health()

	# 연환은 이번 계산을 시작할 때 지속 피해가 걸려 있었는지로 판단한다
	var chain := _strategy.chain_mult() if not _dots.is_empty() else 1.0

	# 규칙 3: 거리 1m 이하면 근접 교전으로 들어간다
	if not in_contact and gap <= _contact_distance:
		in_contact = true
		events["contact_started"] = true
		# 화계: 교전 시작 때 무리 체력의 일정 비율을 병종마다 깎는다
		var fire_ratio := _strategy.fire_attack_ratio()
		if fire_ratio > 0.0:
			for pool in enemies:
				pool.take_damage(pool.total_health * fire_ratio * chain)
		# 연환: 교전 시작 때 적 무리에 불을 붙인다(그 시점 체력의 일정 비율을 정해진 시간에 걸쳐 깎는 지속 피해)
		var burn_ratio := _strategy.chain_burn_ratio()
		if burn_ratio > 0.0:
			var burn_time := _strategy.chain_burn_duration()
			_dots.append({"rate": _enemy_health() * burn_ratio / burn_time, "time": burn_time})

	# 피해는 계산 시작 시점의 병력으로 양쪽 모두 구한 뒤 한꺼번에 넣는다(동시 피해)
	var to_enemy := 0.0
	var to_ally := 0.0
	var ranged_to_enemy := 0.0

	if in_contact:
		if events["contact_started"]:
			# 접촉 순간의 한 방은 병력 전체가 아니라 맨 앞에서 싸우는 인원(교전 인원)만 준다
			var front := mini(ally.count, _melee_limit + _strategy.melee_limit_bonus())
			# 규칙 4: 접촉 순간 기병 돌격(선봉이면 배율 추가)
			to_enemy += _charge_damage(ally, front) * _strategy.charge_mult()
			# 선봉: 접촉 순간 교전 인원에 비례한 추가 피해
			to_enemy += front * _strategy.contact_damage_per_soldier() * ally.attack_mult
			# 적의 돌격도 앞줄 병종부터 교전 인원까지만 센다
			var slots := _melee_limit
			for pool in enemies:
				var charging := mini(pool.count, slots)
				slots -= charging
				to_ally += _charge_damage(pool, charging) * _matchup(pool.unit_type, ally.unit_type)
		# 규칙 5: 근접 단계(횡진이면 교전 인원 추가)
		var engaged := mini(ally.count, _melee_limit + _strategy.melee_limit_bonus())
		to_enemy += engaged * _dps(ally) * dt
		to_ally += _enemy_melee_damage(dt)
	else:
		# 규칙 2: 원거리 단계. 사거리 안이면 궁병이 쏜다
		if _range(ally) > 0.0 and gap <= _range(ally):
			ranged_to_enemy += mini(ally.count, _ranged_limit) * _dps(ally) * dt
			events["ally_fired"] = true
		var enemy_ranged := _enemy_ranged_damage(dt, gap)
		if enemy_ranged > 0.0:
			to_ally += enemy_ranged
			events["enemy_fired"] = true

	# 불화살: 궁병이 아니면 일정 간격으로 일제 사격
	if _strategy.has_volley() and _range(ally) <= 0.0:
		_volley_timer += dt
		if _volley_timer >= _strategy.volley_interval() and gap <= _strategy.volley_range():
			_volley_timer = 0.0
			ranged_to_enemy += ally.count * _strategy.volley_damage_per_soldier() * ally.damage_scale()
			events["ally_fired"] = true

	# 불화살: 원거리 피해의 일부를 지속 피해로 건다
	var dot_ratio := _strategy.dot_ratio()
	if ranged_to_enemy > 0.0 and dot_ratio > 0.0:
		var duration := _strategy.dot_duration()
		_dots.append({"rate": ranged_to_enemy * dot_ratio / duration, "time": duration})

	# 화살에 강한 상대(보스)는 원거리 피해를 일부만 받는다
	ranged_to_enemy *= _ranged_taken_mult()
	# 규칙 6: 아군 피해는 적 앞줄 병종부터 들어간다
	_deal_to_enemies(to_enemy + ranged_to_enemy, true, chain)
	_deal_to_enemies(_tick_dots(dt), false, chain)
	# 규칙 1: 체력 합계에서 빼고 병력 수를 올림으로 다시 구한다(Army가 처리)
	ally.take_damage(to_ally)
	events["damage_dealt"] = enemy_health_before - _enemy_health()
	return events


## 장수 기술처럼 상성 없이 정해진 피해를 앞줄부터 넣는다.
## 반환값은 적 무리 체력이 실제로 줄어든 양이다.
func deal_direct_damage(amount: float) -> float:
	var before := _enemy_health()
	_deal_to_enemies(amount, false, 1.0)
	return before - _enemy_health()


func is_enemy_defeated() -> bool:
	for pool in enemies:
		if pool.is_alive():
			return false
	return true


## 규칙 7: 아군 병력이 0이면 패배
func is_ally_defeated() -> bool:
	return not ally.is_alive()


func is_finished() -> bool:
	return is_enemy_defeated() or is_ally_defeated()


func _enemy_health() -> float:
	var total := 0.0
	for pool in enemies:
		total += pool.total_health
	return total


func enemy_count() -> int:
	var total := 0
	for pool in enemies:
		total += pool.count
	return total


## 상성 배율을 곱하기 전의 피해를 앞줄 병종부터 넣는다.
## 앞 병종이 전멸하고 남은 피해는 다음 병종의 상성으로 다시 계산해 넘긴다.
func _deal_to_enemies(base_damage: float, use_matchup: bool, chain: float) -> void:
	var remaining := base_damage
	for pool in enemies:
		if remaining <= 0.0:
			return
		if not pool.is_alive():
			continue
		var mult := chain
		if use_matchup:
			mult *= _matchup(ally.unit_type, pool.unit_type)
		var effective := remaining * mult
		var absorbed := pool.take_damage(effective)
		remaining = (effective - absorbed) / mult


## 이번 계산에 들어갈 지속 피해를 모으고 끝난 항목을 지운다.
func _tick_dots(dt: float) -> float:
	var damage := 0.0
	for dot in _dots:
		var step := minf(dt, float(dot["time"]))
		damage += float(dot["rate"]) * step
		dot["time"] = float(dot["time"]) - step
	_dots = _dots.filter(func(dot: Dictionary) -> bool: return float(dot["time"]) > 0.0)
	return damage


## 적 근접 피해. 교전 인원 상한을 앞줄 병종부터 채운다.
func _enemy_melee_damage(dt: float) -> float:
	var slots := _melee_limit
	var damage := 0.0
	for pool in enemies:
		if slots <= 0:
			break
		var engaged := mini(pool.count, slots)
		slots -= engaged
		damage += engaged * _dps(pool) * _matchup(pool.unit_type, ally.unit_type) * dt
	return damage


## 적 원거리 피해. 사거리 안에 아군이 있는 궁병만, 사격 인원 상한 안에서 쏜다.
func _enemy_ranged_damage(dt: float, gap: float) -> float:
	var slots := _ranged_limit
	var damage := 0.0
	for pool in enemies:
		if slots <= 0:
			break
		if _range(pool) <= 0.0 or gap > _range(pool) or not pool.is_alive():
			continue
		var firing := mini(pool.count, slots)
		slots -= firing
		damage += firing * _dps(pool) * _matchup(pool.unit_type, ally.unit_type) * dt
	return damage


## 맨 앞에 살아 있는 적 병종이 원거리 피해를 받는 비율(units.json의 ranged_taken_mult, 없으면 1)
func _ranged_taken_mult() -> float:
	for pool in enemies:
		if pool.is_alive():
			return float(_units[pool.unit_type].get("ranged_taken_mult", 1.0))
	return 1.0


## 돌격하는 인원(soldiers)이 접촉 순간 주는 피해
func _charge_damage(army: Army, soldiers: int) -> float:
	return soldiers * float(_units[army.unit_type]["charge_damage"]) * army.attack_mult


func _dps(army: Army) -> float:
	return float(_units[army.unit_type]["dps"]) * army.damage_scale()


func _range(army: Army) -> float:
	return float(_units[army.unit_type]["range"]) * army.range_mult


## 공격 병종이 유리하면 상성 배율, 아니면 1배
func _matchup(attacker_type: String, defender_type: String) -> float:
	if _units[attacker_type].get("strong_against", "") == defender_type:
		return _advantage_mult
	return 1.0
