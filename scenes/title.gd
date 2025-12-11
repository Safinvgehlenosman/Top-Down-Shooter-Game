extends Node2D

@export var amplitude: float = 4.0   # how high they bounce
@export var speed: float = 1.5       # how fast they bounce

var _time := 0.0
var _letters: Array = []

func _ready() -> void:
	for child in get_children():
		if child is Label:
			_letters.append({
				"node": child,
				"base_pos": child.position,
				"phase": randf() * TAU, # random offset so they don't sync
			})

func _process(delta: float) -> void:
	_time += delta
	for data in _letters:
		var node: Label = data["node"]
		var base_pos: Vector2 = data["base_pos"]
		var phase: float = data["phase"]
		node.position.y = base_pos.y + sin(_time * speed + phase) * amplitude
