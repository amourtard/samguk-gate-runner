extends Node
## 화면 전환: 타이틀 → 장수 선택 → 달리기(출전 직전 책략 선택 포함) → 결과 → 다음 스테이지, 다시 도전, 장수 선택
## 화면이 바뀔 때는 잠깐 어두워졌다 밝아진다.
## 강화 화면은 장수 선택과 결과 화면에서 겹쳐 띄운다.

const HeroSelectScene := preload("res://scenes/ui/hero_select.tscn")
const RunScene := preload("res://scenes/run.tscn")
const ResultScreenScene := preload("res://scenes/ui/result_screen.tscn")
const UpgradeScreenScene := preload("res://scenes/ui/upgrade_screen.tscn")
const TitleScreenScript := preload("res://scripts/title_screen.gd")

var _screen: Node
# 화면 전환용 가림막
var _fade: ColorRect
var _fading := false


func _ready() -> void:
	var transition: Dictionary = DataDb.table("visual")["transition"]
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.html(transition["color"])
	_fade.color.a = 0.0
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_show_title()


func _show_title() -> void:
	var title: CanvasLayer = TitleScreenScript.new()
	_replace_screen(title)
	title.started.connect(_transition.bind(_show_hero_select))


## 메뉴 화면의 배경음
func _play_menu_music() -> void:
	Sound.play_music("menu", Sound.menu_music_volume())


## 어두워졌다가 action으로 화면을 바꾸고 다시 밝아진다. 바뀌는 동안에는 누를 수 없다.
func _transition(action: Callable) -> void:
	if _fading:
		return
	_fading = true
	var data: Dictionary = DataDb.table("visual")["transition"]
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, float(data["out_time"]))
	tween.tween_callback(action)
	tween.tween_property(_fade, "color:a", 0.0, float(data["in_time"]))
	tween.tween_callback(func() -> void:
		_fading = false
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)


func _show_hero_select() -> void:
	_play_menu_music()
	_replace_screen(HeroSelectScene.instantiate())
	(_screen as HeroSelect).start_requested.connect(_transition.bind(_start_run))
	# 강화로 시작 병력이 바뀌므로 닫으면 장수 선택을 다시 그린다
	(_screen as HeroSelect).upgrades_requested.connect(_show_upgrades.bind(true))


func _start_run() -> void:
	# 고른 장수와 스테이지를 다음에 켰을 때도 기억한다
	GameState.save_game()
	Sound.play_music("run", Sound.music_volume())
	_replace_screen(RunScene.instantiate())
	_screen.finished.connect(_on_run_finished)


func _on_run_finished(result: Dictionary) -> void:
	var cleared: bool = result["cleared"]
	# 금화 지급, 다음 스테이지 열기, 저장
	var reward := GameState.finish_run(cleared, int(result["bonus_gold"]))
	result["gold_stage"] = reward["stage"]
	result["gold_bonus"] = reward["bonus"]
	# 배경음을 끊고 승리, 패배 음악을 낸다
	Sound.stop_music()
	Sound.play("victory" if cleared else "defeat")
	if int(reward["total"]) > 0:
		get_tree().create_timer(float(DataDb.table("visual")["result_ui"]["gold_sound_delay"])).timeout.connect(Sound.play.bind("gold"))
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
			_transition(_start_run)
		"retry":
			_transition(_start_run)
		"heroes":
			_transition(_show_hero_select)
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
