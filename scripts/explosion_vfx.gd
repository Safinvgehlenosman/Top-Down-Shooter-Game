extends Node2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	anim.play("explode")
	anim.animation_finished.connect(_on_anim_finished)

func _on_anim_finished() -> void:
	queue_free()
