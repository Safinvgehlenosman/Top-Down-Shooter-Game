extends Area2D

@export var min_speed: float = 80.0
@export var max_speed: float = 140.0
@export var friction: float = 260.0       # how fast it slows down
@export var lifetime: float = 2.0         # how long the cloud stays
@export var freeze_factor: float = 0.3    # 0.3 = 70% slower
@export var freeze_duration: float = 1.5  # seconds of slow

var direction: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var time_left: float = 0.0


func _ready() -> void:
	time_left = lifetime

	# Pick a random speed in range for this pellet
	var s := randf_range(min_speed, max_speed)
	velocity = direction.normalized() * s


func _physics_process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return

	# Move
	position += velocity * delta
	# Slow down so it becomes a “lingering” cloud
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _on_body_entered(body: Node2D) -> void:
	# Only affect player
	if not body.is_in_group("player"):
		return

	# Get Health component under the player and apply freeze
	var hc := body.get_node_or_null("Health")
	if hc and hc.has_method("apply_freeze"):
		hc.apply_freeze(freeze_factor, freeze_duration)
	# No direct damage, just the slow
	queue_free()
