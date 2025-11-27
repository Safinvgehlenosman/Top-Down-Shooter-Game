extends Area2D

@export var min_speed: float = 80.0
@export var max_speed: float = 140.0
@export var friction: float = 260.0       # how fast it slows down
@export var lifetime: float = 2.0         # how long the cloud stays
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


# Helper: recursively search descendants for a node that implements `apply_burn`
func _search_descendants(root: Node, depth: int, max_depth: int) -> Node:
	if depth > max_depth:
		return null
	for child in root.get_children():
		if typeof(child) == TYPE_OBJECT:
			var cn := child as Node
			if cn == null:
				continue
			if cn.has_method("apply_burn"):
				return cn
			if cn.name.to_lower().find("health") != -1:
				if cn.has_method("apply_burn"):
					return cn
			var found := _search_descendants(cn, depth + 1, max_depth)
			if found:
				return found
	return null


# Helper: find best target node for a collider `n` by checking the node,
# its ancestors (for group membership or Health child) and some descendants.
func _find_target_for_node(n: Node, max_ancestor_depth: int = 8) -> Node:
	# 1) Check the node itself
	if n.has_method("apply_burn"):
		return n
	if n.name.to_lower().find("health") != -1 and n.has_method("apply_burn"):
		return n

	# 2) Walk up ancestors and inspect each
	var cur: Node = n
	var depth := 0
	while cur and depth < max_ancestor_depth:
		if cur.is_in_group(str(target_group)):
			return cur
		if cur.has_node("Health"):
			var hc := cur.get_node("Health")
			if hc and hc.has_method("apply_burn"):
				return hc
		if cur.has_method("apply_burn"):
			return cur
		var found_desc := _search_descendants(cur, 0, 4)
		if found_desc:
			return found_desc
		cur = cur.get_parent()
		depth += 1

	# 3) Finally, try searching descendants of the original collider
	return _search_descendants(n, 0, 6)


func _ready() -> void:
	time_left = lifetime
	add_to_group("enemy_bullet")

	# Pick a random speed in range for this pellet (LOGIC UNCHANGED)
	var s := randf_range(min_speed, max_speed)
	velocity = direction.normalized() * s

	# --- Visual setup (no logic changes) -----------------------------
	if sprite:
		# random texture from list, if provided
		if cloud_textures.size() > 0:
			var idx := randi() % cloud_textures.size()
			sprite.texture = cloud_textures[idx]

		_base_sprite_pos = sprite.position
		_max_alpha = sprite.modulate.a

		# slight random size & rotation
		var scale_rand := randf_range(0.9, 1.2)
		sprite.scale = Vector2(scale_rand, scale_rand)
		sprite.rotation = randf_range(-0.2, 0.2)

	_wobble_phase = randf_range(0.0, TAU)


func _physics_process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return

	# --- Move (LOGIC UNCHANGED) --------------------------------------
	position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

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

	# Find a target (Health node or node with apply_burn) by inspecting the
	# collider and walking ancestors; also search descendants as a fallback.

	# If debug prints are enabled, log the ancestor chain to help debugging
	if debug_prints:
		var chain := []
		var walker: Node = body
		while walker:
			chain.append(str(walker.name) + "(" + str(walker.get_class()) + ") groups=" + str(walker.get_groups()))
			walker = walker.get_parent()
		print("[FireProjectile] ancestor_chain=", chain)

	var target_node: Node = _find_target_for_node(body)
	if target_node == null:
		if debug_prints:
			print("[FireProjectile] no target_node found for collider", body, "(full_chain above)")
		return

	# If the resolved node is a Health child, call apply_burn on it. Otherwise
	# call apply_burn on the node itself if it supports it.
	if debug_prints:
		print("[FireProjectile] resolved target =>", target_node, "name=", target_node.name, "groups=", target_node.get_groups())

	if target_node.has_method("apply_burn"):
		target_node.apply_burn(burn_damage_per_tick, burn_duration, burn_tick_interval)
	else:
		# As a defensive fallback, try to find a Health child now and call it
		var hc2 := target_node.get_node_or_null("Health")
		if hc2 and hc2.has_method("apply_burn"):
			hc2.apply_burn(burn_damage_per_tick, burn_duration, burn_tick_interval)
		else:
			if debug_prints:
				print("[FireProjectile] resolved target has no apply_burn; giving up:", target_node)

	# No direct impact damage, just the DoT
	queue_free()
