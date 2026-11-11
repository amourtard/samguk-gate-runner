extends Node
## 화면 전환: 장수 선택 → 달리기(구간 끝 책략 선택 포함) → 결과 → 다음 스테이지, 다시 도전, 장수 선택
## 강화 화면은 장수 선택과 결과 화면에서 겹쳐 띄운다.

const HeroSelectScene := preload("res://scenes/ui/hero_select.tscn")
const RunScene := preload("res://scenes/run.tscn")
const ResultScreenScene := preload("res://scenes/ui/result_screen.tscn")
const UpgradeScreenScene := preload("res://scenes/ui/upgrade_screen.tscn")

var _screen: Node


func _ready() -> void:
	_show_hero_select()


func _show_hero_select() -> void:
	_replace_screen(HeroSelectScene.instantiate())
	(_screen as HeroSelect).start_requested.connect(_start_run)
	# 강화로 시작 병력이 바뀌므로 닫으면 장수 선택을 다시 그린다
	(_screen as HeroSelect).upgrades_requested.connect(_show_upgrades.bind(true))


func _start_run() -> void:
	# 고른 장수와 스테이지를 다음에 켰을 때도 기억한다
	GameState.save_game()
	_replace_screen(RunScene.instantiate())
	_screen.finished.connect(_on_run_finished)


func _on_run_finished(result: Dictionary) -> void:
	var cleared: bool = result["cleared"]
	# 금화 지급, 다음 스테이지 열기, 저장
	var reward := GameState.finish_run(cleared, int(result["bonus_gold"]))
	result["gold_stage"] = reward["stage"]
	result["gold_bonus"] = reward["bonus"]
	var stage_id: String = GameState.current_stage()["id"]
	# 결과 화면은 멈춘 판 위에 겹쳐 띄운다
	var screen: ResultScreen = ResultScreenScene.instantiate()
	_screen.add_child(screen)
	screen.setup(result, stage_id, cleared and GameState.has_next_stage())
	screen.action_chosen.connect(_on_result_action)


func _on_result_action(action: String) -> void:
	match action:
		"next":
			GameState.stage_index += 1
			_start_run()
		"retry":
			_start_run()
		"heroes":
			_show_hero_select()
		"upgrades":
			_show_upgrades(false)


func _show_upgrades(refresh_hero_select: bool) -> void:
	var screen: UpgradeScreen = UpgradeScreenScene.instantiate()
	add_child(screen)
	if refresh_hero_select:
		screen.closed.connect(_show_hero_select)


func _replace_screen(screen: Node) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(_screen)
