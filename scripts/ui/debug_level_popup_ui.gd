extends Control

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label
@onready var line_edit: LineEdit = $Panel/LineEdit
@onready var button: Button = $Panel/Button


func _ready() -> void:
	visible = false

	# Optional: label text
	label.text = "Set level"

	# Connect button and LineEdit submit
	button.pressed.connect(_on_button_pressed)
	line_edit.text_submitted.connect(_on_line_edit_submitted)


func open_popup() -> void:
	visible = true
	# Optional: pause game while picking
	get_tree().paused = true

	line_edit.text = ""
	line_edit.grab_focus()


func _on_button_pressed() -> void:
	_apply_level_from_input()


func _on_line_edit_submitted(_text: String) -> void:
	_apply_level_from_input()


func _apply_level_from_input() -> void:
	var text := line_edit.text.strip_edges()

	if text == "":
		_close_popup()
		return

	var target_level := int(text)
	if target_level < 1:
		target_level = 1

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("debug_set_level"):
		gm.debug_set_level(target_level)
		print("[DEBUG] Set level to:", target_level)
	else:
		print("[DEBUG] Could not find GameManager.debug_set_level()")

	_close_popup()


func _close_popup() -> void:
	visible = false
	get_tree().paused = false
