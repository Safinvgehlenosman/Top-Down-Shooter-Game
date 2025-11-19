extends CanvasLayer


@onready var restart_button: Button = $RestartButton
@onready var quit_button: Button = $QuitButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_button_pressed() -> void:
	get_tree().quit()
