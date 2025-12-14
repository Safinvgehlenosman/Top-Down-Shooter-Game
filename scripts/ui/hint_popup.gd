extends Control

@onready var title_label: Label = $Title
@onready var instr_label: Label = $Instruction

@export var show_duration: float = 2.0
@export var slide_pixels: float = 40.0
@export var fade_time: float = 0.2

var _queue: Array[Dictionary] = []
var _running := false
var _base_pos: Vector2
var _base_modulate: Color

func _ready() -> void:
	# Ensure this still animates when the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_base_pos = position
	_base_modulate = modulate

	# Start hidden
	visible = false
	modulate = Color(_base_modulate, 0.0)

func queue_hint(title: String, instruction: String) -> void:
	_queue.append({"title": title, "instruction": instruction})
	if not _running:
		call_deferred("_run_next")

func show_hint(title: String, instruction: String) -> void:
	# Immediate display (front of queue)
	_queue.insert(0, {"title": title, "instruction": instruction})
	if not _running:
		call_deferred("_run_next")

func _run_next() -> void:
	if _running or _queue.is_empty():
		return

	_running = true
	var item: Dictionary = _queue.pop_front()

	title_label.text = str(item.get("title", ""))
	instr_label.text = str(item.get("instruction", ""))

	visible = true

	# Reset state
	position = _base_pos + Vector2(0.0, slide_pixels)
	modulate = Color(_base_modulate, 0.0)

	# Fade + slide in
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.set_parallel(true)
	t.tween_method(_set_alpha, 0.0, 1.0, fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position", _base_pos, fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	# Hold
	await get_tree().create_timer(show_duration, true).timeout

	# Fade + slide out
	var t2 := create_tween()
	t2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t2.set_parallel(true)
	t2.tween_method(_set_alpha, 1.0, 0.0, fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t2.tween_property(self, "position", _base_pos + Vector2(0.0, slide_pixels), fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t2.finished

	visible = false
	_running = false

	if not _queue.is_empty():
		call_deferred("_run_next")

func _set_alpha(a: float) -> void:
	modulate = Color(_base_modulate, clamp(a, 0.0, 1.0))
