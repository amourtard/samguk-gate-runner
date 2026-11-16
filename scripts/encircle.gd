extends RefCounted
## 십면매복(보스 포위전)의 계산. 노드와 렌더링에 의존하지 않는 순수 계산이다.
## 장수가 지나온 길 위에 병사가 줄지어 서고(꼬리), 그 꼬리로 보스를 고리 모양으로 감싸면 큰 피해를 준다.
## 값은 tuning.json의 encircle과 boss, 병종 값은 units.json에서 읽는다. 규칙은 명세 4장 "보스 장각: 십면매복".

var encircle_count := 0
var enraged := false

var _data: Dictionary
var _boss_data: Dictionary
var _units: Dictionary
var _strategy: Strategy
# 마지막 포위 뒤로 장수가 새로 달린 거리. 이 길이 안의 꼬리로만 다음 고리를 닫을 수 있다
var _fresh_length := 0.0
var _cooldown := 0.0
var _first_loop_done := false
# 보스에 걸린 지속 피해 목록: {"rate": 초당 피해, "time": 남은 시간}
var _burns: Array[Dictionary] = []
var _volley_timer := 0.0
var _zone_timer: float
var _orb_timer: float
var _stun_left := 0.0


func _init(tuning: Dictionary, units: Dictionary, strategy: Strategy) -> void:
	_data = tuning["encircle"]
	_boss_data = tuning["boss"]
	_units = units
	_strategy = strategy
	_zone_timer = float(_data["zone_first_delay"])
	_orb_timer = float(_data["orb_first_delay"])
	# 판을 시작할 때는 꼬리 전체를 쓸 수 있다
	_fresh_length = INF


# --- 꼬리 배치 ---

## 한 줄에 서는 병사 수(열). 꼬리 길이가 tail_max_length를 넘지 않도록 병력이 많으면 열을 늘린다.
func columns(shown: int) -> int:
	var spacing := float(_data["rank_spacing"])
	var max_ranks := maxi(1, floori(float(_data["tail_max_length"]) / spacing))
	return clampi(ceili(float(shown) / max_ranks), 1, int(_data["columns_max"]))


## 줄 간격. 병력이 적어도 보스를 한 바퀴 감쌀 수 있도록 꼬리 길이가 tail_min_length보다 짧아지지 않게 간격을 벌린다.
func spacing(shown: int) -> float:
	return maxf(float(_data["rank_spacing"]), float(_data["tail_min_length"]) / ranks(shown))


## 꼬리의 줄(마디) 수
func ranks(shown: int) -> int:
	return maxi(1, ceili(float(shown) / columns(shown)))


## 장수가 지나온 길(trail, 최근 것이 앞) 위에 줄 간격마다 마디를 놓는다. 길이 모자라면 마지막 점에 겹친다.
func tail_nodes(head: Vector2, trail: PackedVector2Array, shown: int) -> PackedVector2Array:
	var nodes := PackedVector2Array()
	var gap := spacing(shown)
	var index := 0
	var walked := 0.0
	var previous := head
	for rank in ranks(shown):
		var target := (rank + 1) * gap
		var placed := false
		while index < trail.size():
			var next := trail[index]
			var segment := previous.distance_to(next)
			if walked + segment >= target and segment > 0.0:
				nodes.append(previous.lerp(next, (target - walked) / segment))
				placed = true
				break
			walked += segment
			previous = next
			index += 1
		if not placed:
			nodes.append(trail[trail.size() - 1] if not trail.is_empty() else head)
	return nodes


## 길을 얼마나 기억해 둬야 하는가(m). 꼬리 최대 길이보다 조금 길게 둔다.
func trail_keep_length() -> float:
	return float(_data["tail_max_length"]) + float(_data["tail_min_length"])


# --- 포위 ---

## 장수가 달린 거리를 알린다(한 번 쓴 꼬리를 다시 쓰지 못하게 새로 달린 길이를 센다).
func add_travel(distance: float) -> void:
	if _fresh_length != INF:
		_fresh_length += distance


## 한 프레임만큼 시간을 흘린다.
func advance(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	_stun_left = maxf(_stun_left - dt, 0.0)


## 장수가 다가가면 고리가 닫히는 꼬리 위의 자리. 없으면 빈 사전, 있으면 {"pos": 자리, "loop": 그 자리까지의 고리}.
## 꼬리는 병사가 선 자리만이 아니라 장수가 달린 길(trail, 바닥의 띠) 전체로 본다. 병사가 적어 마디가 드물어도 띠를 건드리면 닫힌다.
## 조건: 장수에서 길을 따라 loop_min_length보다 멀고, 꼬리 길이 안이고, 마지막 포위 뒤로 새로 달린 길 위에 있고,
## 그 자리까지의 고리가 targets(보스와 호위병의 위치) 중 하나라도 감싼다.
## 감싸지 않는 가까운 자리를 먼저 잡으면 보스를 다 감싸고도 포위가 되지 않으므로 감싸는 자리 중 가장 가까운 것을 고른다.
func closing_point(head: Vector2, trail: PackedVector2Array, shown: int, within: float, targets: Array[Vector2]) -> Dictionary:
	var limit := minf(ranks(shown) * spacing(shown), _fresh_length)
	var loop := PackedVector2Array()
	loop.append(head)
	var best := {}
	var best_distance := within
	var walked := 0.0
	var previous := head
	for point in trail:
		walked += previous.distance_to(point)
		if walked > limit:
			break
		loop.append(point)
		previous = point
		if walked < float(_data["loop_min_length"]):
			continue
		var distance := head.distance_to(point)
		if distance > best_distance:
			continue
		for target in targets:
			if encloses(loop, target):
				best_distance = distance
				best = {"pos": point, "loop": loop.duplicate()}
				break
	return best


## 지금 닫힌 고리(다각형). 닫히지 않았거나 재사용 대기 중이면 빈 배열.
func closed_loop(head: Vector2, trail: PackedVector2Array, shown: int, targets: Array[Vector2]) -> PackedVector2Array:
	if _cooldown > 0.0:
		return PackedVector2Array()
	var found := closing_point(head, trail, shown, float(_data["loop_close_distance"]), targets)
	if found.is_empty():
		return PackedVector2Array()
	return found["loop"]


## 고리 안에 그 점이 있는가. 보스는 중심이 고리 안에 있어야 포위다.
static func encloses(loop: PackedVector2Array, point: Vector2) -> bool:
	return loop.size() >= 3 and Geometry2D.is_point_in_polygon(point, loop)


## 포위가 성립했다: 횟수를 올리고, 쓴 꼬리를 못 쓰게 하고, 보스를 잠깐 멈춘다. boss_enclosed가 false면(호위병만 감쌌으면) 보스는 멈추지 않는다.
func register_loop(boss_enclosed: bool) -> void:
	encircle_count += 1
	_cooldown = float(_data["loop_cooldown"])
	_fresh_length = 0.0
	if boss_enclosed:
		_stun_left = float(_data["stun"])


## 보스를 포위했을 때의 피해. 기본값에 병력 수에 비례하는 몫을 더한다(병력이 한 명 늘 때마다 피해가 는다). 책략은 화면의 설명대로만 적용한다.
## register_loop보다 먼저 부른다(첫 포위인지 본다).
func loop_damage(army: Army, boss: Army) -> float:
	var damage := float(_data["loop_base_damage"]) + army.count * float(_data["loop_damage_per_soldier"]) * army.attack_mult
	if not _first_loop_done:
		_first_loop_done = true
		# 선봉과 기병 돌격: 첫 접촉 피해를 첫 포위에 싣는다(근접 동시 교전 수까지)
		var engaged := mini(army.count, int(_data["melee_limit"]))
		damage += engaged * _strategy.contact_damage_per_soldier() * army.attack_mult
		damage += engaged * float(_units[army.unit_type]["charge_damage"]) * _strategy.charge_mult() * army.attack_mult
		# 화계: 첫 포위에 보스의 그 시점 체력의 일정 비율
		damage += boss.total_health * _strategy.fire_attack_ratio()
	damage *= _burn_mult()
	# 연환: 포위하면 불을 붙인다(그 시점 체력의 일정 비율을 정해진 시간에 걸쳐)
	var burn_ratio := _strategy.chain_burn_ratio()
	if burn_ratio > 0.0:
		var burn_time := _strategy.chain_burn_duration()
		_burns.append({"rate": boss.total_health * burn_ratio / burn_time, "time": burn_time})
	return damage


# --- 꼬리 교전 ---

## 한 번의 교전 계산. distances는 꼬리 마디마다 보스까지의 거리다.
## 반환값: damage(보스에 줄 피해), melee(근접 교전 인원), ranged(사격 인원), volley(일제 사격을 했는가)
func combat_tick(dt: float, army: Army, distances: PackedFloat32Array) -> Dictionary:
	var result := {"damage": 0.0, "melee": 0, "ranged": 0, "volley": false}
	if distances.is_empty() or army.count <= 0:
		return result
	var unit: Dictionary = _units[army.unit_type]
	var unit_range := float(unit["range"]) * army.range_mult
	var per_rank := maxi(1, army.count / distances.size())
	var melee := 0
	var ranged := 0
	var nearest := INF
	for distance in distances:
		nearest = minf(nearest, distance)
		if unit_range > 0.0:
			if distance <= unit_range:
				ranged += per_rank
		elif distance <= float(_data["melee_reach"]):
			melee += per_rank
	melee = mini(melee, int(_data["melee_limit"]))
	ranged = mini(ranged, int(_data["ranged_limit"]))
	var per_soldier := float(unit["dps"]) * army.attack_mult * army.attack_speed_mult
	var melee_damage := melee * per_soldier * dt
	# 보스가 받는 화살 피해 비율
	var ranged_taken := float(_units["boss"].get("ranged_taken_mult", 1.0))
	var ranged_damage := ranged * per_soldier * dt * ranged_taken

	# 불화살: 궁병이 아니면 정해진 간격마다, 보스가 일제 사격 거리 안일 때 병력 수만큼 쏜다
	if _strategy.has_volley() and unit_range <= 0.0:
		_volley_timer += dt
		if _volley_timer >= _strategy.volley_interval() and nearest <= _strategy.volley_range():
			_volley_timer = 0.0
			ranged_damage += army.count * _strategy.volley_damage_per_soldier() * army.attack_mult * ranged_taken
			result["volley"] = true
	# 불화살: 원거리 피해의 일정 비율을 지속 피해로 더한다
	var dot_ratio := _strategy.dot_ratio()
	if ranged_damage > 0.0 and dot_ratio > 0.0:
		var duration := _strategy.dot_duration()
		_burns.append({"rate": ranged_damage * dot_ratio / duration, "time": duration})

	var burn_mult := _burn_mult()
	var burn_damage := 0.0
	for burn in _burns:
		var step := minf(dt, float(burn["time"]))
		burn_damage += float(burn["rate"]) * step
		burn["time"] = float(burn["time"]) - step
	_burns = _burns.filter(func(burn: Dictionary) -> bool: return float(burn["time"]) > 0.0)

	result["damage"] = (melee_damage + ranged_damage + burn_damage) * burn_mult
	result["melee"] = melee
	result["ranged"] = ranged
	return result


## 연환: 지속 피해가 걸려 있는 동안 보스가 받는 피해 배율
func _burn_mult() -> float:
	return _strategy.chain_mult() if not _burns.is_empty() else 1.0


# --- 보스의 공격 ---

func is_stunned() -> bool:
	return _stun_left > 0.0


## 보스 체력 비율을 보고 분노를 켠다. 이번에 분노했으면 true.
func check_enrage(health_ratio: float) -> bool:
	if enraged or health_ratio > float(_boss_data["enrage_ratio"]):
		return false
	enraged = true
	return true


## 이번 프레임에 시작할 공격 목록. 멈춰 있는(포위당한) 동안에는 공격하지 않는다.
## 모든 공격은 장수가 달려갈 앞쪽을 겨냥한다. 방향을 틀면 피할 수 있고, 꼬리는 장수가 지나간 길만 따라오므로 같이 피한다.
## 반환값의 항목: {"kind": "zone" 또는 "orb", "pos": 떨어질 자리, "radius": 반지름, "time": 떨어질 때까지 남은 시간}
func start_attacks(dt: float, head: Vector2, heading: float, speed: float, nodes: PackedVector2Array, shown: int, arena_center: Vector2, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var attacks: Array[Dictionary] = []
	if is_stunned():
		return attacks
	var rate := 1.0 / float(_boss_data["enrage_interval_mult"]) if enraged else 1.0
	var forward := Vector2.from_angle(heading)
	_zone_timer -= dt * rate
	if _zone_timer <= 0.0:
		_zone_timer = float(_data["zone_interval"])
		var warn := float(_boss_data["warn_time"])
		var radius := float(_data["zone_radius"])
		# 장수가 그대로 달리면 예고가 끝날 때 닿는 자리, 그리고 그 좌우 한쪽
		var ahead := head + forward * speed * warn * float(_data["zone_lead"])
		var side := forward.orthogonal() * (radius * float(_data["zone_side_offset"])) * (1.0 if rng.randf() < 0.5 else -1.0)
		for target: Vector2 in [ahead, ahead + side]:
			var spot := _clear_spot(target, radius, warn, speed, head, nodes, shown, arena_center)
			if spot != Vector2.INF:
				attacks.append({"kind": "zone", "pos": spot, "radius": radius, "time": warn})
	_orb_timer -= dt * rate
	if _orb_timer <= 0.0:
		_orb_timer = float(_boss_data["normal_interval"])
		var flight := float(_boss_data["normal_flight"])
		var radius := float(_boss_data["normal_radius"])
		var target := head + forward * speed * flight * float(_data["orb_lead"])
		var spot := _clear_spot(target, radius, flight, speed, head, nodes, shown, arena_center)
		if spot != Vector2.INF:
			attacks.append({"kind": "orb", "pos": spot, "radius": radius, "time": flight})
	return attacks


## 공격이 떨어질 자리를 고른다. 떨어질 때(time 뒤)까지 꼬리가 지나가고 있을 자리는 피한다. 꼬리는 길을 따라
## 같은 자리를 차례로 지나가므로 거기에 떨어지면 피할 수 없다. 꼬리 끝에 가까운 마디만 있는 자리는 그 전에 비므로 괜찮다.
## target에서 시작해 거리와 방향을 조금씩 바꿔 가며 찾고, 없으면 Vector2.INF(그 공격은 하지 않는다).
func _clear_spot(target: Vector2, radius: float, time: float, speed: float, head: Vector2, nodes: PackedVector2Array, shown: int, arena_center: Vector2) -> Vector2:
	var offset := target - head
	var margin := radius + float(_data["attack_clear_margin"])
	var step := deg_to_rad(float(_data["attack_search_step_deg"]))
	var gap := spacing(shown)
	# 이 길이보다 뒤에 꼬리가 남아 있는 마디는 떨어질 때까지 그 자리를 다 지나가지 못한다
	var passing := speed * time * float(_data["attack_pass_ratio"])
	var tail_length := nodes.size() * gap
	for scale: float in _data["attack_search_scales"]:
		for i in int(_data["attack_search_tries"]):
			# 0, +1, -1, +2, -2 ... 순서로 돌린다
			var turn := step * ceili(i / 2.0) * (1.0 if i % 2 == 1 else -1.0)
			var spot := clamp_to_arena(head + (offset * scale).rotated(turn), arena_center, radius)
			var blocked := false
			for k in nodes.size():
				if nodes[k].distance_to(spot) <= margin and tail_length - (k + 1) * gap > passing:
					blocked = true
					break
			if not blocked:
				return spot
	return Vector2.INF


## 공격이 떨어지는 순간 장수나 꼬리 마디가 원 안에 있는가.
static func is_hit(pos: Vector2, radius: float, head: Vector2, nodes: PackedVector2Array) -> bool:
	if head.distance_to(pos) <= radius:
		return true
	for node in nodes:
		if node.distance_to(pos) <= radius:
			return true
	return false


## 맞았을 때 잃는 병력. 받는 피해 배율(장수 기술, 철갑, 방어 강화)을 곱하고, 맞았으면 최소 1명은 잃는다.
func loss(kind: String, army: Army) -> int:
	# 불덩이는 정해진 명수를 잃되, 병력이 적을 때 한 번에 거의 다 잃지 않도록 병력의 hit_loss_ratio까지만 잃는다
	var base := minf(float(_boss_data["normal_loss"]), maxf(army.count * float(_boss_data["hit_loss_ratio"]), 1.0))
	if kind == "zone":
		base = army.count * float(_boss_data["hit_loss_ratio"]) * float(_data["zone_loss_mult"])
	return mini(maxi(1, roundi(base * army.damage_taken_mult)), army.count)


## 호위병이 붙어 있는 동안 잃는 병력(무리 하나, 한 번 물 때). 받는 피해 배율을 곱한다.
func escort_bite(army: Army) -> int:
	return mini(maxi(1, roundi(float(_data["escort_bite"]) * army.damage_taken_mult)), army.count)


# --- 결투장 ---

## 점을 타원 결투장 안으로 끌어들인다. margin만큼 안쪽에 둔다.
func clamp_to_arena(point: Vector2, center: Vector2, margin := 0.0) -> Vector2:
	var rx := maxf(float(_data["rx"]) - margin, 0.1)
	var rz := maxf(float(_data["rz"]) - margin, 0.1)
	var scaled := Vector2((point.x - center.x) / rx, (point.y - center.y) / rz)
	if scaled.length() <= 1.0:
		return point
	scaled = scaled.normalized()
	return center + Vector2(scaled.x * rx, scaled.y * rz)


## 타원 밖으로 나갔는가
func is_outside_arena(point: Vector2, center: Vector2) -> bool:
	var scaled := Vector2((point.x - center.x) / float(_data["rx"]), (point.y - center.y) / float(_data["rz"]))
	return scaled.length() > 1.0


## 타원 벽 위의 점에서 벽을 따라가는 방향. 두 접선 방향 중 지금 가던 쪽(heading)에 가까운 것을 돌려준다.
func wall_tangent(point: Vector2, center: Vector2, heading: Vector2) -> Vector2:
	# 타원 x²/rx² + z²/rz² = 1의 법선은 (x/rx², z/rz²)이다
	var normal := Vector2((point.x - center.x) / pow(float(_data["rx"]), 2.0), (point.y - center.y) / pow(float(_data["rz"]), 2.0)).normalized()
	var tangent := normal.orthogonal()
	return tangent if tangent.dot(heading) >= 0.0 else -tangent
