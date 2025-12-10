extends Camera2D

@export var pan_speed: float = 25.0
@export var left_limit: float = -200.0
@export var right_limit: float = 200.0

var direction: float = 1.0

func _process(delta: float) -> void:
	position.x += direction * pan_speed * delta

	if position.x > right_limit:
		direction = -1.0
	elif position.x < left_limit:
		direction = 1.0
