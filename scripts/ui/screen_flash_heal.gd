extends ColorRect

var time_left: float = 0.0

func _ready() -> void:
	color.a = 0.0

func flash() -> void:
	time_left = GameConfig.hit_flash_duration
	color.a = GameConfig.hit_flash_max_alpha

func _process(delta: float) -> void:
	if time_left > 0:
		time_left -= delta
		var t: float = clamp(time_left / GameConfig.hit_flash_duration, 0.0, 1.0)
		color.a = GameConfig.hit_flash_max_alpha * t
	else:
		color.a = 0.0
