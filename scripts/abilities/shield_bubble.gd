extends Area2D

@export var duration: float = 3.0
@export var radius: float = 80.0
@export var push_strength: float = 500.0

var lifetime: float = 0.0

@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# DO NOT put the bubble in any bullet group
	# add_to_group("enemy_bullet") ← remove this

	# Make sure the collision radius matches the export
	if shape and shape.shape is CircleShape2D:
		shape.shape.radius = radius

	# ⭐ SYNERGY 3: Fire shield (orange modulate)
	if GameState.has_fireshield_synergy:
		if sprite:
			# Use self_modulate to override the blue base color completely
			sprite.self_modulate = Color(1.0, 0.5, 0.0)  # Pure orange
		
		# Change PointLight2D nodes to orange
		if has_node("PointLight2D"):
			$PointLight2D.color = Color(1.0, 0.4, 0.0)  # Orange glow
		if has_node("PointLight2D2"):
			$PointLight2D2.color = Color(1.0, 0.5, 0.0)  # Lighter orange

	# ⭐ SYNERGY 6: Spawn shuriken nova
	if GameState.has_shuriken_bubble_nova_synergy:
		_spawn_shuriken_nova()


func setup(p_duration: float) -> void:
	duration = p_duration
	lifetime = 0.0


func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime >= duration:
		queue_free()
		return

	var bodies := get_overlapping_bodies()
	var areas := get_overlapping_areas()

	# --- PUSH ENEMIES OUT ------------------------------------------
	for body in bodies:
		if body == null:
			continue

		if body.is_in_group("enemy"):
			var to_enemy: Vector2 = body.global_position - global_position
			var dist := to_enemy.length()

			# small margin so they sit close to the edge
			if dist > 0.0 and dist < radius + 4.0:
				var dir := to_enemy.normalized()

				if body.has_method("apply_knockback"):
					body.apply_knockback(global_position, push_strength)
				elif "velocity" in body:
					body.velocity += dir * (push_strength * delta)

		# --- BLOCK ENEMY BULLET BODIES ------------------------------
		elif body.is_in_group("enemy_bullet"):
			body.queue_free()

	# --- BLOCK ENEMY BULLET AREAS ---------------------------------
	for area in areas:
		if area == null:
			continue

		if area.is_in_group("enemy_bullet"):
			area.queue_free()

	# ⭐ SYNERGY 3: Fire shield - apply burn damage to touching enemies
	if GameState.has_fireshield_synergy:
		_apply_fire_shield_damage(bodies)


func _apply_fire_shield_damage(bodies: Array) -> void:
	"""SYNERGY 3: Apply flamethrower burn DoT to enemies touching the fire shield."""
	for body in bodies:
		if body == null:
			continue
		
		if body.is_in_group("enemy"):
			# Apply burn status effect (same as flamethrower)
			if body.has_method("apply_burn"):
				var burn_damage := 2  # Low damage per tick (fire shield is weaker than direct flame)
				var burn_duration := 2.0  # Shorter duration
				var burn_interval := 0.5  # Tick every 0.5 seconds
				body.apply_burn(burn_damage, burn_duration, burn_interval)


func _spawn_shuriken_nova() -> void:
	"""SYNERGY 6: Spawn 360° ring of shuriken projectiles."""
	# Get shuriken data from GameState
	var shuriken_data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.AltWeaponType.SHURIKEN, {})
	if shuriken_data.is_empty():
		return
	
	var bullet_scene: PackedScene = shuriken_data.get("bullet_scene")
	if bullet_scene == null:
		return
	
	var bullet_speed: float = shuriken_data.get("bullet_speed", 400.0)
	var damage: float = shuriken_data.get("damage", 15.0)
	var num_projectiles: int = 12  # 360° / 12 = 30° between each shuriken
	
	for i in range(num_projectiles):
		var angle := (float(i) / num_projectiles) * TAU  # Full circle
		var dir := Vector2.RIGHT.rotated(angle)
		
		var shuriken = bullet_scene.instantiate()
		shuriken.global_position = global_position
		shuriken.direction = dir
		shuriken.speed = bullet_speed
		shuriken.damage = roundi(damage)
		
		get_tree().current_scene.add_child(shuriken)
