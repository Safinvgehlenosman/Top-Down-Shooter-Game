extends Area2D

@export var min_speed: float = 150.0
@export var max_speed: float = 250.0
@export var friction: float = 260.0       # how fast it slows down
@export var lifetime: float = 3.0         # how long the cloud stays
@export var target_group: StringName = "player"
# 🔥 burn parameters (DOT)
@export var burn_damage_per_tick: float = 1.0
@export var burn_duration: float = 2.0
@export var burn_tick_interval: float = 0.3

var direction: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var time_left: float = 0.0

# --- VISUAL EXTRAS (CLOUD LOOK) --------------------------------------

@export var cloud_textures: Array[Texture2D] = []  # assign multiple cloud sprites here

@export var wobble_amplitude: float = 4.0          # pixels up/down
@export var wobble_frequency: float = 3.0          # wobble cycles per second

@export var fade_in_time: float = 0.15             # seconds to fade in
@export var fade_out_time: float = 0.4             # seconds to fade out

@onready var sprite: Sprite2D = $Sprite2D
@onready var light: PointLight2D = $PointLight2D

@export var debug_prints: bool = false

var _base_sprite_pos: Vector2 = Vector2.ZERO
var _wobble_phase: float = 0.0
var _max_alpha: float = 1.0


# Note: previous deep-search helpers removed — keep collision handling
# simple and fast. If needed later, they can be restored.


func _ready() -> void:
	time_left = lifetime
	add_to_group("enemy_bullet")

	# Pick a random speed in range for this pellet
	var s := randf_range(min_speed, max_speed)
	velocity = direction.normalized() * s

	if debug_prints:
		print("[FireProjectile] Spawned - Speed: ", s, " Lifetime: ", lifetime, " Direction: ", direction)

	# --- Visual setup (no logic changes) -----------------------------
	if sprite:
		# random texture from list, if provided
		if cloud_textures.size() > 0:
			var idx := randi() % cloud_textures.size()
			sprite.texture = cloud_textures[idx]

		_base_sprite_pos = sprite.position
		_max_alpha = sprite.modulate.a

		# slight random size & rotation
		var scale_rand := randf_range(0.8, 1.1)
		sprite.scale = Vector2(scale_rand, scale_rand)
		sprite.rotation = randf_range(-0.2, 0.2)

	_wobble_phase = randf_range(0.0, TAU)


func _physics_process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return

	# --- Move --------------------------------------
	position += velocity * delta
	# No friction - maintain speed to travel far

	# --- Wobble / bobbing (visual only) ------------------------------
	if sprite and wobble_amplitude > 0.0:
		var offset_y := sin(_wobble_phase + (lifetime - time_left) * wobble_frequency) * wobble_amplitude
		sprite.position.y = _base_sprite_pos.y + offset_y

	# --- Fade in / out (visual only) --------------------------------
	if sprite:
		var age := lifetime - time_left
		var alpha := _max_alpha

		if age < fade_in_time:
			alpha = _max_alpha * (age / max(fade_in_time, 0.001))
		elif time_left < fade_out_time:
			var t = time_left / max(fade_out_time, 0.001)
			alpha = _max_alpha * clamp(t, 0.0, 1.0)

		var c := sprite.modulate
		c.a = alpha
		sprite.modulate = c

	if light:
		light.energy = sprite.modulate.a


func _on_body_entered(body: Node2D) -> void:
	if debug_prints:
		print("[FireProjectile] collided with:", body, "name=", body.name, "groups=", body.get_groups(), "target_group=", target_group)

	# Ignore collisions with TileMap (floor) so the cloud doesn't immediately
	# despawn when it overlaps the level geometry. This lets the cloud pass
	# through the tilemap and reach enemies.
	if body is TileMap:
		if debug_prints:
			print("[FireProjectile] ignored TileMap collision (floor)")
		return

	# Simple, fast target resolution:
	# 1) Check collider for a `Health` child or `apply_burn` method.
	# 2) Walk up parents up to 3 levels looking for the same.
	var target_node: Node = null

	if body.has_node("Health"):
		var hc := body.get_node("Health")
		if hc and hc.has_method("apply_burn"):
			target_node = hc
	elif body.has_method("apply_burn"):
		target_node = body

	if target_node == null:
		var p: Node = body.get_parent()
		var depth := 0
		while p and depth < 3:
			if p.has_node("Health"):
				var ph := p.get_node("Health")
				if ph and ph.has_method("apply_burn"):
					target_node = ph
					break
			if p.has_method("apply_burn"):
				target_node = p
				break
			p = p.get_parent()
			depth += 1

	if target_node == null:
		if debug_prints:
			print("[FireProjectile] no target found for collider", body)
		return

	if target_node.has_method("apply_burn"):
		target_node.apply_burn(burn_damage_per_tick, burn_duration, burn_tick_interval)
	else:
		if debug_prints:
			print("[FireProjectile] resolved target has no apply_burn:", target_node)

	# No direct impact damage, just the DoT
	queue_free()
