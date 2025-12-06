extends CharacterBody2D

@export var base_speed: float = 500.0
@export var base_damage: int = 10
@export var max_lifetime: float = 4.0
@export var default_bounces: int = 1   # base number of bounces
@export var target_group: StringName = "enemy"
var direction: Vector2 = Vector2.ZERO
var speed: float = 0.0
var damage: int = 0
var bounces_left: int = 0
var life_timer: float = 0.0

# Chainshot system
var chain_count: int = 0
var chain_radius: float = 300.0
var chain_speed_mult: float = 1.0
var blade_split_chance: float = 0.0
var is_mini_shuriken: bool = false
var hit_enemies: Array[Node2D] = []  # Track hit enemies to avoid re-hitting


func _ready() -> void:
	add_to_group("player_bullet")

	# fallback if gun didn't override them
	if speed <= 0.0:
		speed = base_speed
	if damage <= 0:
		damage = base_damage
	if bounces_left <= 0:
		bounces_left = default_bounces   # ensure at least 1 bounce

func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO:
		return

	# lifetime safety
	life_timer += delta
	if life_timer >= max_lifetime:
		queue_free()
		return

	var motion := direction * speed * delta
	var collision := move_and_collide(motion)

	if collision:
		var collider := collision.get_collider()
		var normal: Vector2 = collision.get_normal()

		# ✅ Hit enemy → deal damage and chain or disappear
		if collider and collider.is_in_group("enemy"):
			# Avoid hitting same enemy immediately after chain
			if collider in hit_enemies:
				return  # Skip this collision, already hit this one
			
			if collider.has_method("take_damage"):
				collider.take_damage(damage)
			
			# Add to hit list
			hit_enemies.append(collider)
			
			# Try to chain to next enemy
			if chain_count > 0:
				_chain_to_next_enemy(collider)
			else:
				queue_free()
			return

		# ✅ Hit wall / anything else solid → bounce or die
		if bounces_left > 0:
			bounces_left -= 1

			# reflect direction
			if normal != Vector2.ZERO:
				direction = direction.bounce(normal).normalized()
			else:
				direction = -direction.normalized()

			# move slightly out of the wall so we don't instantly collide again
			global_position = collision.get_position() + normal * 2.0

		else:

			queue_free()


func _chain_to_next_enemy(last_hit: Node2D) -> void:
	"""Find next enemy and redirect shuriken toward it."""
	var next_target = _find_nearest_enemy_in_radius(last_hit)
	
	if next_target:
		# Redirect toward next enemy
		direction = (next_target.global_position - global_position).normalized()
		
		# Increase speed
		speed *= chain_speed_mult
		
		# Reduce chain count
		chain_count -= 1
		
		print("[CHAIN] Shuriken chaining → target: %s (chains left: %d)" % [next_target.name, chain_count])
		
		# Blade Split: chance to spawn mini-shuriken
		if not is_mini_shuriken and blade_split_chance > 0.0 and randf() < blade_split_chance:
			_spawn_mini_shuriken(next_target)
	else:
		print("[CHAIN] No valid targets left → ending chain")
		queue_free()


func _find_nearest_enemy_in_radius(exclude: Node2D) -> Node2D:
	"""Find nearest enemy within chain radius, excluding already-hit enemies."""
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist := chain_radius
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy == exclude or enemy in hit_enemies:
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	
	return nearest


func _spawn_mini_shuriken(target: Node2D) -> void:
	"""Spawn a mini-shuriken with 50% damage that auto-targets next enemy."""
	var mini_shu = duplicate()
	mini_shu.global_position = global_position
	mini_shu.damage = int(damage * 0.5)  # 50% damage
	mini_shu.speed = speed * 1.2  # Slightly faster
	mini_shu.chain_count = 0  # No further chaining
	mini_shu.is_mini_shuriken = true  # Mark as mini
	mini_shu.direction = (target.global_position - global_position).normalized()
	mini_shu.hit_enemies = hit_enemies.duplicate()  # Copy hit list
	
	get_tree().current_scene.add_child(mini_shu)
	print("[SPLIT] Spawned mini shuriken!")
