extends CanvasLayer

@onready var start_button: Button = $StartButton
@onready var quit_button: Button = $QuitButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	
	
func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
