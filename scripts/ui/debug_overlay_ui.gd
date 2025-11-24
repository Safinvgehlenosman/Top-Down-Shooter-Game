extends Control

@onready var label: Label = $Panel/Label

func _ready() -> void:
	visible = false

func set_text(t: String) -> void:
	if label:
		label.text = t
