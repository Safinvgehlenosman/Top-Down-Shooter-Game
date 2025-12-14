extends Node2D

# Strict 2-node setup: TurretHead rotates; VisualRoot only flips (visuals)
@onready var turret_head: Node2D = $TurretHead as Node2D
@onready var muzzle: Marker2D = $TurretHead/VisualRoot/Muzzle as Marker2D
@onready var visual_root: Node2D = $TurretHead/VisualRoot as Node2D
@onready var sfx_shoot: AudioStreamPlayer2D = $SFX_Shoot as AudioStreamPlayer2D

@export var back_offset: Vector2 = Vector2(-10, -6)

var fire_interval: float = 0.8
var turret_range: float = 100.0
var spread_rad: float = deg_to_rad(20.0)
var bullet_scene: PackedScene = null
var bullet_speed: float = 100.0
var damage: int = 1

var fire_timer: float = 0.0
var _turret_root_warned: bool = false


func _ready() -> void:
	add_to_group("turret")

	# Fail fast if critical nodes missing to avoid repeated null errors during play
	if turret_head == null or muzzle == null:
		push_error("[TURRET] Missing TurretHead or Muzzle node; disabling turret processing.")
		set_process(false)
		set_physics_process(false)
		return

	# Reset visual transforms to a sane baseline so facing is handled externally
	if turret_head != null:
		turret_head.scale = Vector2.ONE
		turret_head.rotation = 0.0
	if visual_root != null:
		visual_root.scale = Vector2.ONE
		visual_root.rotation = 0.0
		# Do not set Backpack.rotation — backpack rotation must be owned by visuals and not programmatically rotated.
		var backpack := visual_root.get_node_or_null("Backpack")
		if backpack:
			# Keep backpack orientation unchanged here; any flip should use flip_h only and be handled by Player
			pass


# Called from Player.sync_from_gamestate()
func configure(data: Dictionary) -> void:
	print("[TURRET DEBUG] configure() called with data: %s" % data)
	
	# Map "fire_rate" (from ALT_WEAPON_DATA) to "fire_interval" (turret's variable)
	if data.has("fire_rate"):
		fire_interval = float(data["fire_rate"]) * float(GameState.turret_fire_rate_mult)
	else:
		fire_interval = float(data.get("fire_interval", fire_interval)) * float(GameState.turret_fire_rate_mult)
	
	turret_range = data.get("range", turret_range)

	# get degrees from data, convert once to radians
	var spread_deg: float = data.get("spread_degrees", 20.0)
	spread_rad = deg_to_rad(spread_deg)

	bullet_scene = data.get("bullet_scene", bullet_scene)
	# Apply GameState bullet speed multiplier (clamped in GameState)
	bullet_speed = float(data.get("bullet_speed", bullet_speed)) * float(GameState.turret_bullet_speed_mult)
	damage       = data.get("damage", damage)

func _process(delta: float) -> void:
	if bullet_scene == null:
		return

	# Safety clamp: turret root must never rotate. Warn once if external code sets rotation.
	if abs(rotation) > 0.001:
		if not _turret_root_warned:
			push_error("[TURRET WARNING] root rotation non-zero: %f" % rotation)
			_turret_root_warned = true
		# Clamp back to zero to enforce invariant
		rotation = 0.0



	fire_timer -= delta

	var target := _find_target()
	if target == null:
		return

	# Aim at enemy (only when turret_head is valid)
	if turret_head != null:
		turret_head.look_at(target.global_position)

	# Visual flipping not handled here; visuals are static and backpack rotation is set in _ready()

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
		
		# Skip dead enemies (check health component)
		if body.has_node("Health"):
			var health_comp = body.get_node("Health")
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
	
	# Guard muzzle usage
	if muzzle == null:
		push_error("[TURRET] muzzle missing in _fire_at")
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
