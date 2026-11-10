extends Node
## 화면 전환: 장수 선택 → 달리기(구간 끝 책략 선택 포함) → 결과 → 다음 스테이지, 다시 도전, 장수 선택
## 강화 화면은 단계 6에서 붙인다.

const HeroSelectScene := preload("res://scenes/ui/hero_select.tscn")
const RunScene := preload("res://scenes/run.tscn")
const ResultScreenScene := preload("res://scenes/ui/result_screen.tscn")

var _screen: Node


func _ready() -> void:
	_show_hero_select()


func _show_hero_select() -> void:
	_replace_screen(HeroSelectScene.instantiate())
	(_screen as HeroSelect).start_requested.connect(_start_run)


func _start_run() -> void:
	_replace_screen(RunScene.instantiate())
	_screen.finished.connect(_on_run_finished)


func _on_run_finished(result: Dictionary) -> void:
	var cleared: bool = result["cleared"]
	if cleared:
		GameState.mark_cleared(GameState.stage_index)
	var stage_id: String = GameState.current_stage()["id"]
	var title := "%s 돌파" % stage_id if cleared else "%s 패배" % stage_id
	var detail := "장수 %s\n남은 병력 %d\n책략: %s" % [result["hero"], int(result["count"]), result["strategies"]]
	# 결과 화면은 멈춘 판 위에 겹쳐 띄운다
	var screen: ResultScreen = ResultScreenScene.instantiate()
	_screen.add_child(screen)
	screen.setup(title, detail, cleared and GameState.has_next_stage())
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


func _replace_screen(screen: Node) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(_screen)
