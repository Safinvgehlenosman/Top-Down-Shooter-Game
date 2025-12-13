extends Area2D

@export var speed: float  = GameConfig.PRIMARY_BULLET_BASE_SPEED
@export var damage: int   = GameConfig.bullet_base_damage
@export var target_group: StringName = "player"

var direction: Vector2 = Vector2.ZERO
var last_position: Vector2 = Vector2.ZERO
var stuck_frames: int = 0


func _ready() -> void:
	# So the shield can filter these out
	add_to_group("enemy_bullet")
	last_position = global_position


func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO or speed == 0.0:
		return

	position += direction * speed * delta

	# --- Stuck detector (corner failsafe) ---
	var moved: float = global_position.distance_to(last_position)
	if moved < 0.25:
		stuck_frames += 1
	else:
		stuck_frames = 0

	if stuck_frames >= 6:
		queue_free()

	last_position = global_position


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
