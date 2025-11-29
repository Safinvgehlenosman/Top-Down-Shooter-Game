extends "res://scripts/slimes/base_slime.gd"

# --- Shooting settings ---
@export var projectile_scene: PackedScene
@export var shoot_interval: float = 1.2
@export var projectile_speed: float = 140.0
@export var shoot_range: float = 220.0

var shoot_timer: float = 0.0


func _ready() -> void:
	# Ensure base setup runs
	super._ready()
	# Increase projectile speed to match global pacing
	projectile_speed *= 1.2


func _physics_process(delta: float) -> void:
	# base AI (movement, aggro, hit logic)
	super(delta)

	if is_dead or player == null:
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()

	# only shoot when:
	# - aggro
	# - in range
	# - has clear line of sight
	if aggro and dist <= shoot_range and _has_line_of_sight_to_player():
		shoot_timer -= delta

		if shoot_timer <= 0.0:
			_shoot_at_player()
			shoot_timer = shoot_interval
	else:
		# reset timer when out of sight or range so it can't "insta-shoot"
		shoot_timer = 0.0


func _shoot_at_player() -> void:
	if not projectile_scene or player == null:
		return

	var proj = projectile_scene.instantiate()
	var dir := (player.global_position - global_position).normalized()
	if dir == Vector2.ZERO:
		return

	# spawn slightly in front of the slime to avoid self-hit
	proj.global_position = global_position + dir * 6.0

	# 🔥 Hard-assign common projectile fields
	# All your enemy projectile scripts (enemyprojectile, fire, ice, poison)
	# have these same variables, so we can just set them directly.
	proj.direction = dir
	proj.speed = projectile_speed
	proj.target_group = "player"

	# Scale damage based on level (+10% per level)
	if "damage" in proj:
		var game_manager = get_tree().get_first_node_in_group("game_manager")
		if game_manager and "current_level" in game_manager:
			var level = game_manager.current_level
			var base_damage = 5.0
			var scaled_damage = base_damage * (1.0 + (level - 1) * 0.1)
			proj.damage = int(scaled_damage)

	get_tree().current_scene.add_child(proj)



func _has_line_of_sight_to_player() -> bool:
	if player == null:
		return false

	var space_state = get_world_2d().direct_space_state

	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = player.global_position
	query.exclude = [self]
	query.collision_mask = 1  # <-- make sure WALL layer is bit 1

	var result = space_state.intersect_ray(query)

	# If nothing hit → the line is clear
	return result.is_empty()
