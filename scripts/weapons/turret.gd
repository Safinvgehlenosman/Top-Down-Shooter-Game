extends Node2D

@onready var head: Node2D = $TurretHead
@onready var muzzle: Marker2D = $TurretHead/Muzzle
@onready var sfx_shoot: AudioStreamPlayer2D = $SFX_Shoot  # NEW

var fire_interval: float = 0.8
var turret_range: float = 100.0
var spread_rad: float = deg_to_rad(20.0)
var bullet_scene: PackedScene = null
var bullet_speed: float = 100.0
var damage: int = 1

var fire_timer: float = 0.0


# Called from Player.sync_from_gamestate()
func configure(data: Dictionary) -> void:
	fire_interval = data.get("fire_interval", fire_interval)
	turret_range = data.get("range", turret_range)

	# get degrees from data, convert once to radians
	var spread_deg: float = data.get("spread_degrees", 20.0)
	spread_rad = deg_to_rad(spread_deg)

	bullet_scene = data.get("bullet_scene", bullet_scene)
	bullet_speed = data.get("bullet_speed", bullet_speed)
	damage       = data.get("damage", damage)


func _process(delta: float) -> void:
	if bullet_scene == null:
		return

	fire_timer -= delta

	var target := _find_target()
	if target == null:
		return

	# Aim at enemy
	head.look_at(target.global_position)
	head.rotation += deg_to_rad(180)

	# Auto fire
	if fire_timer <= 0.0:
		_fire_at(target)
		fire_timer = fire_interval


func _find_target() -> Node2D:
	var best_target: Node2D = null
	var best_dist := turret_range

	for body in get_tree().get_nodes_in_group("enemy"):
		if not body.is_inside_tree():
			continue

		var to_target = body.global_position - global_position
		var dist = to_target.length()
		if dist > turret_range:
			continue

		# Line-of-sight check
		var space_state := get_world_2d().direct_space_state

		var query := PhysicsRayQueryParameters2D.new()
		query.from = global_position
		query.to = body.global_position
		query.exclude = [self]
		query.collision_mask = 1

		var result := space_state.intersect_ray(query)

		# If we hit something and it's NOT our target, LOS is blocked
		if result and result.get("collider") != body:
			continue

		if dist < best_dist:
			best_dist = dist
			best_target = body

	return best_target


func _fire_at(target: Node2D) -> void:
	var dir := (target.global_position - muzzle.global_position).normalized()

	# add inaccuracy
	if spread_rad > 0.0:
		dir = dir.rotated(randf_range(-spread_rad, spread_rad))

	var bullet = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.damage = damage

	get_tree().current_scene.add_child(bullet)
	
	# Play shoot sound with turret-specific pitch
	if sfx_shoot:
		sfx_shoot.pitch_scale = randf_range(1.1, 1.3)  # Slightly higher, mechanical
		sfx_shoot.volume_db = -6.0  # Quieter (fires often)
		sfx_shoot.play()