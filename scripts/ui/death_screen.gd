extends CanvasLayer

@export var coins_label_path: NodePath = ^"CoinsCollected"
@export var slimes_label_path: NodePath = ^"SlimesKilled"
@export var level_label_path: NodePath = ^"LevelReached"

@export var quit_button_path: NodePath = ^"QuitButton"
@export var restart_button_path: NodePath = ^"RestartButton" # optional

const MIN_DURATION := 0.5
const MAX_DURATION := 1.5
const BETWEEN_DELAY := 0.25

@onready var coins_label: Label = get_node_or_null(coins_label_path) as Label
@onready var slimes_label: Label = get_node_or_null(slimes_label_path) as Label
@onready var level_label: Label = get_node_or_null(level_label_path) as Label

@onready var quit_button: Button = get_node_or_null(quit_button_path) as Button
@onready var restart_button: Button = get_node_or_null(restart_button_path) as Button

var _active_tween: Tween

func _ready() -> void:
	print("[DeathScreen] _ready()  path=", get_path(), " parent=", get_parent() if get_parent() else "null")

	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	print("[DeathScreen] coins_label=", coins_label, " path=", coins_label_path)
	print("[DeathScreen] slimes_label=", slimes_label, " path=", slimes_label_path)
	print("[DeathScreen] level_label=", level_label, " path=", level_label_path)
	print("[DeathScreen] quit_button=", quit_button, " restart_button=", restart_button)

	_reset_visuals()

	if quit_button:
		quit_button.disabled = true
		if not quit_button.pressed.is_connected(_on_quit_pressed):
			quit_button.pressed.connect(_on_quit_pressed)

	if restart_button:
		restart_button.disabled = true
		if not restart_button.pressed.is_connected(_on_restart_pressed):
			restart_button.pressed.connect(_on_restart_pressed)


func show_death_screen(coins: int = -1, slimes: int = -1, level: int = -1) -> void:
	print("[DeathScreen] show_death_screen called  args coins=", coins, " slimes=", slimes, " level=", level)
	print("[DeathScreen] paused before=", get_tree().paused)

	# Ensure this overlay still animates while paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Stop gameplay
	get_tree().paused = true
	print("[DeathScreen] paused after=", get_tree().paused)

	_reset_visuals()

	if quit_button:
		quit_button.disabled = true
	if restart_button:
		restart_button.disabled = true

	# Prefer passed-in values, otherwise read from GameState
	var final_coins := coins if coins >= 0 else _gs_int(["coins_collected", "coins", "total_coins"])
	var final_slimes := slimes if slimes >= 0 else _gs_int(["total_kills", "kills", "slimes_killed"])
	var final_level := level if level >= 0 else _gs_int(["current_level", "level", "level_index"])

	final_coins = max(0, final_coins)
	final_slimes = max(0, final_slimes)
	final_level = max(0, final_level)

	print("[DeathScreen] resolved coins=", final_coins, " slimes=", final_slimes, " level=", final_level)

	await _reveal_sequence(final_coins, final_slimes, final_level)

	if quit_button:
		quit_button.disabled = false
		print("[DeathScreen] quit enabled")
	if restart_button:
		restart_button.disabled = false
		print("[DeathScreen] restart enabled")


func _reset_visuals() -> void:
	if coins_label:
		coins_label.visible = false
		coins_label.text = "Coins collected: 0"
	if slimes_label:
		slimes_label.visible = false
		slimes_label.text = "Slimes killed: 0"
	if level_label:
		level_label.visible = false
		level_label.text = "Level reached: 0"


func _reveal_sequence(final_coins: int, final_slimes: int, final_level: int) -> void:
	# COINS
	print("[DeathScreen] reveal coins start ->", final_coins)
	if coins_label:
		coins_label.visible = true
		await _count_up_label(coins_label, "Coins collected: %d", final_coins)
	print("[DeathScreen] reveal coins end")
	await get_tree().create_timer(BETWEEN_DELAY, true).timeout

	# SLIMES
	print("[DeathScreen] reveal slimes start ->", final_slimes)
	if slimes_label:
		slimes_label.visible = true
		await _count_up_label(slimes_label, "Slimes killed: %d", final_slimes)
	print("[DeathScreen] reveal slimes end")
	await get_tree().create_timer(BETWEEN_DELAY, true).timeout

	# LEVEL (snap)
	print("[DeathScreen] reveal level ->", final_level)
	if level_label:
		level_label.visible = true
		level_label.text = "Level reached: %d" % final_level


func _count_up_label(label: Label, fmt: String, target: int) -> void:
	target = max(0, target)
	var dur = clamp(MIN_DURATION + float(target) * 0.005, MIN_DURATION, MAX_DURATION)

	# Kill previous tween if any
	if _active_tween and _active_tween.is_running():
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	_active_tween.tween_method(
		func(v: float) -> void:
			label.text = fmt % int(round(v)),
		0.0,
		float(target),
		dur
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await _active_tween.finished


func _gs_int(keys: Array[String]) -> int:
	var gs := get_node_or_null("/root/GameState")
	if not gs:
		print("[DeathScreen] GameState not found at /root/GameState")
		# Fall back to GameManager if available
		var game_manager = get_tree().get_first_node_in_group("game_manager")
		if game_manager and game_manager.has_method("get") and game_manager.has("current_level"):
			print("[DeathScreen] Using GameManager.current_level ->", game_manager.get("current_level"))
			return int(game_manager.get("current_level"))
		return 0

	for k in keys:
		var v = gs.get(k)
		if v != null:
			return int(v)

	# If not found in GameState, try GameManager.current_level as last resort
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("get") and gm.has("current_level"):
		print("[DeathScreen] Fallback GameManager.current_level ->", gm.get("current_level"))
		return int(gm.get("current_level"))

	print("[DeathScreen] GameState missing keys: ", keys)
	return 0


func _on_restart_pressed() -> void:
	print("[DeathScreen] restart pressed")
	get_tree().paused = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if has_node("/root/GameState"):
		GameState.start_new_run()

	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/level_1.tscn")


func _on_quit_pressed() -> void:
	print("[DeathScreen] quit pressed")
	get_tree().paused = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if has_node("/root/GameState"):
		GameState.end_run_to_menu()

	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
