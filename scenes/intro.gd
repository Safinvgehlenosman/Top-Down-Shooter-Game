extends Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label
@onready var background: ColorRect = $Background
@onready var fade_out: ColorRect = $FadeOut

var _finished := false

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
	if _finished:
		return
	if event.is_pressed():
		_goto_main_menu()

func _run_intro_sequence() -> void:
	await get_tree().process_frame
	
	# 1. Fade IN (fade_out goes transparent)
	var t := create_tween()
	t.tween_property(fade_out, "modulate:a", 0.0, 0.5)
	await t.finished
	
	# 2. Wait 3 seconds, then fade in text (while animation is still playing)
	await get_tree().create_timer(3.0).timeout
	if _finished:
		return
	
	t = create_tween()
	t.tween_property(label, "self_modulate:a", 1.0, 0.5)
	await t.finished
	if _finished:
		return
	
	# 3. Wait for rest of animation to finish (6.13 - 3.0 - 0.5 = 2.63 seconds)
	await get_tree().create_timer(2.63).timeout
	if _finished:
		return
	
	# 4. Hold both visible for 1 second
	await get_tree().create_timer(1.0).timeout
	if _finished:
		return
	
	# 5. Fade OUT logo and text
	t = create_tween()
	t.tween_property(sprite, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(label, "self_modulate:a", 0.0, 0.5)
	await t.finished
	if _finished:
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