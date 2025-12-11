extends Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label
@onready var background: ColorRect = $Background
@onready var fade_out: ColorRect = $FadeOut

var _finished := false
var _skipped := false

func _ready() -> void:
	# Background stays black always
	background.position = Vector2.ZERO
	background.size = get_viewport_rect().size
	background.color = Color(0, 0, 0, 1.0)
	
	# FadeOut starts fully black (covers background)
	fade_out.position = Vector2.ZERO
	fade_out.size = get_viewport_rect().size
	fade_out.color = Color(0, 0, 0, 1.0)
	fade_out.modulate.a = 1.0  # Start OPAQUE
	
	# Start with text invisible
	label.self_modulate.a = 0.0
	
	sprite.play()
	_run_intro_sequence()

func _input(event: InputEvent) -> void:
	if _finished or _skipped:
		return
	if event.is_pressed():
		_skip_to_end()

func _skip_to_end() -> void:
	_skipped = true
	
	# Set to last frame (91 if you have 92 frames, 0-indexed)
	sprite.frame = 91  # Hardcode the last frame number
	sprite.pause()
	
	# Make everything visible instantly
	fade_out.modulate.a = 0.0
	sprite.modulate.a = 1.0
	label.self_modulate.a = 1.0
	
	# Wait 1.5 seconds so they see it
	await get_tree().create_timer(1.5).timeout
	
	# Fade OUT logo and text
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(label, "self_modulate:a", 0.0, 0.5)
	await t.finished
	
	# Fade OUT to black
	t = create_tween()
	t.tween_property(fade_out, "modulate:a", 1.0, 0.5)
	await t.finished
	
	_goto_main_menu()

func _run_intro_sequence() -> void:
	await get_tree().process_frame
	
	# 1. Fade IN (fade_out goes transparent)
	var t := create_tween()
	t.tween_property(fade_out, "modulate:a", 0.0, 0.5)
	await t.finished
	
	if _skipped:
		return
	
	# 2. Wait 3 seconds, then fade in text (while animation is still playing)
	await get_tree().create_timer(3.0).timeout
	if _finished or _skipped:
		return
	
	t = create_tween()
	t.tween_property(label, "self_modulate:a", 1.0, 0.5)
	await t.finished
	if _finished or _skipped:
		return
	
	# 3. Wait for rest of animation to finish (6.13 - 3.0 - 0.5 = 2.63 seconds)
	await get_tree().create_timer(2.63).timeout
	if _finished or _skipped:
		return
	
	# 4. Hold both visible for 1 second
	await get_tree().create_timer(1.0).timeout
	if _finished or _skipped:
		return
	
	# 5. Fade OUT logo and text
	t = create_tween()
	t.tween_property(sprite, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(label, "self_modulate:a", 0.0, 0.5)
	await t.finished
	if _finished or _skipped:
		return
	
	# 6. Fade OUT to black (fade_out becomes opaque again)
	t = create_tween()
	t.tween_property(fade_out, "modulate:a", 1.0, 0.5)
	await t.finished
	
	_goto_main_menu()

func _goto_main_menu() -> void:
	if _finished:
		return
	_finished = true
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")