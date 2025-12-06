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

# Synergy: Spiral firing during slowmo
var spiral_rotation: float = 0.0
var spiral_fire_timer: float = 0.0
var spiral_fire_interval: float = 0.05  # Very fast firing (20 bullets per second)


func _ready() -> void:
	add_to_group("turret")


# Called from Player.sync_from_gamestate()
func configure(data: Dictionary) -> void:
	print("[TURRET DEBUG] configure() called with data: %s" % data)
	
	# Map "fire_rate" (from ALT_WEAPON_DATA) to "fire_interval" (turret's variable)
	if data.has("fire_rate"):
		fire_interval = data["fire_rate"]
	else:
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

	# ⭐ SYNERGY 4: Spiral firing during slowmo
	if GameState.has_turret_slowmo_sprinkler_synergy and GameState.ability_active_left > 0.0:
		_do_spiral_fire(delta)
		return  # Skip normal targeting when doing spiral

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


func _do_spiral_fire(delta: float) -> void:
	"""⭐ SYNERGY 4: Continuously fire in a rotating spiral pattern during slowmo."""
	spiral_fire_timer -= delta
	
	if spiral_fire_timer <= 0.0:
		# Fire a bullet in the current rotation direction
		var dir := Vector2.RIGHT.rotated(spiral_rotation)
		
		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = damage
		
		get_tree().current_scene.add_child(bullet)
		
		# Rotate turret head to match firing direction
		head.rotation = spiral_rotation + deg_to_rad(180)
		
		# Increment rotation for spiral effect (360° per second = fast spiral)
		spiral_rotation += deg_to_rad(360.0 * spiral_fire_interval)  # Rotates 18° per shot
		if spiral_rotation >= TAU:
			spiral_rotation -= TAU
		
		spiral_fire_timer = spiral_fire_interval


func _find_target() -> Node2D:
	var best_target: Node2D = null
	var best_dist := turret_range

	for body in get_tree().get_nodes_in_group("enemy"):
		if not body.is_inside_tree():
			continue
		
		# Skip dead enemies (check health component)
		if body.has_node("HealthComponent"):
			var health_comp = body.get_node("HealthComponent")
			if health_comp.health <= 0:
				continue
		
		# Skip ghost slimes (turret can't target them)
		if body.name.to_lower().contains("ghost"):
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
	if bullet_scene == null:

		return
	
	var dir := (target.global_position - muzzle.global_position).normalized()

	# Apply accuracy spread (improves with upgrades)
	var spread_radians := deg_to_rad(10.0 * GameState.turret_accuracy_mult)
	dir = dir.rotated(randf_range(-spread_radians, spread_radians))

	var bullet = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.damage = int(damage * GameState.turret_damage_mult)
	
	# Apply homing to bullet (if upgraded)
	if "homing_enabled" in bullet:
		bullet.homing_enabled = GameState.turret_homing_angle_deg > 0.0
		bullet.homing_angle_deg = GameState.turret_homing_angle_deg
		bullet.homing_turn_speed = GameState.turret_homing_turn_speed
	
	print("[TURRET] accuracy_mult=%.2f, homing_angle=%.1f°, turn_speed=%.2f" % [GameState.turret_accuracy_mult, GameState.turret_homing_angle_deg, GameState.turret_homing_turn_speed])

	get_tree().current_scene.add_child(bullet)
	
	# Play shoot sound with turret-specific pitch
	if sfx_shoot:
		sfx_shoot.pitch_scale = randf_range(1.1, 1.3)  # Slightly higher, mechanical
		sfx_shoot.volume_db = -6.0  # Quieter (fires often)
		sfx_shoot.play()


func do_sprinkler_burst() -> void:
	"""SYNERGY 4: Fire 360° burst of bullets (turret + slowmo synergy)."""
	if bullet_scene == null:
		return
	
	var num_bullets: int = 16  # 360° / 16 = 22.5° between bullets
	
	for i in range(num_bullets):
		var angle := (float(i) / num_bullets) * TAU  # Full circle
		var dir := Vector2.RIGHT.rotated(angle)
		
		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = damage
		
		get_tree().current_scene.add_child(bullet)
	
	# Play shoot sound
	if sfx_shoot:
		sfx_shoot.pitch_scale = 1.0  # Normal pitch for burst
		sfx_shoot.volume_db = -3.0  # Louder for special attack
		sfx_shoot.play()
