extends "res://scripts/base_slime.gd"

# --- Shooting settings ---
@export var projectile_scene: PackedScene
@export var shoot_interval: float = 1.2
@export var projectile_speed: float = 140.0
@export var shoot_range: float = 220.0





var shoot_timer: float = 0.0


func _physics_process(delta: float) -> void:
	# Run base slime movement / AI / damage first
	super(delta)

	if is_dead:
		return
	if not player:
		return

	# only shoot when aggro and within range
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()

	if aggro and distance <= shoot_range:
		shoot_timer -= delta
		if shoot_timer <= 0.0:
			_shoot_at_player()
			shoot_timer = shoot_interval
	else:
		shoot_timer = 0.0


func _shoot_at_player() -> void:
	if not projectile_scene:
		return
	if not player:
		return

	var proj := projectile_scene.instantiate()
	var dir: Vector2 = (player.global_position - global_position).normalized()

	# spawn slightly in front of the slime so it doesn't hit itself
	proj.global_position = global_position + dir * 6.0

	if "direction" in proj:
		proj.direction = dir
	if "target_group" in proj:
		proj.target_group = "player"

	get_tree().current_scene.add_child(proj)
