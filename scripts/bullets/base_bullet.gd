extends Area2D

@export var speed: float  = GameConfig.PRIMARY_BULLET_BASE_SPEED # fallback default, set by gun.gd
@export var damage: int   = GameConfig.bullet_base_damage

@export var target_group: StringName = "enemy"

# Homing logic (for turret bullets)
var homing_enabled: bool = false
var homing_angle_deg: float = 0.0
var homing_turn_speed: float = 0.0

var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player_bullet")


func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO:
		return
	
	# Homing behavior
	if homing_enabled and homing_turn_speed > 0.0:
		var nearest = _find_nearest_enemy_within_cone()
		if nearest:
			var to_target = (nearest.global_position - global_position).normalized()
			var angle_diff = direction.angle_to(to_target)
			var max_turn = homing_turn_speed * delta
			direction = direction.rotated(clamp(angle_diff, -max_turn, max_turn))

	position += direction * speed * delta


func _find_nearest_enemy_within_cone() -> Node2D:
	"""Find nearest enemy within homing cone angle."""
	if homing_angle_deg <= 0.0:
		return null
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist := INF
	var cone_rad := deg_to_rad(homing_angle_deg)
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist: float = to_enemy.length()
		
		# Check if enemy is within cone
		var angle_to_enemy := direction.angle_to(to_enemy.normalized())
		if abs(angle_to_enemy) > cone_rad:
			continue
		
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	
	return nearest


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()