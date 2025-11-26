extends Area2D

@export var speed: float  = GameConfig.bullet_speed
@export var damage: int   = GameConfig.bullet_base_damage
@export var target_group: StringName = "player"

var direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	# So the shield bubble can recognize / block these
	add_to_group("enemy_bullet")

	# Safety: if the spawner never set direction, aim at the player
	if direction == Vector2.ZERO:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player:
			direction = (player.global_position - global_position).normalized()


func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO or speed == 0.0:
		return

	position += direction * speed * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Only damage bodies in the chosen group
	if body.is_in_group(target_group) and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif not body.is_in_group(target_group):
		# Hit a wall or something else: just despawn
		queue_free()
