extends CharacterBody2D

@export var target_group: StringName = "enemy"
@export var base_speed: float = 260.0
@export var base_damage: int = 25
@export var max_lifetime: float = 6.0

@export var default_explosion_radius: float = 60.0
@export var fuse_time: float = 2.5

@export var friction: float = 500.0         # slows the roll
@export var bounciness: float = 0.6         # how “springy” the bounces are
@export var min_speed_before_stop: float = 40.0

# flashing
@export var flash_interval_start: float = 0.35
@export var flash_interval_end: float = 0.06

# camera shake + knockback
@export var cam_shake_strength: float = 6.0
@export var cam_shake_duration: float = 0.12
@export var explosion_knockback: float = 220.0

# optional explosion VFX scene (AnimatedSprite2D/CPUParticles2D etc.)
@export var explosion_fx_scene: PackedScene
@export var wall_collision_mask: int = 2 # Set to your wall layer mask

var direction: Vector2 = Vector2.ZERO
var speed: float = 0.0
var damage: int = 0
var explosion_radius: float = 0.0

var grenade_velocity: Vector2 = Vector2.ZERO
var life_timer: float = 0.0
var fuse_left: float = 0.0

var flash_timer: float = 0.0
var flash_on: bool = false
var exploded: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_explode: AudioStreamPlayer2D = $SFX_Explode
@onready var light: PointLight2D = $PointLight2D   # <- light to hide on explode

@onready var radius_indicator: Sprite2D = $RadiusIndicator
@onready var tween: Tween = null

# Helper to get final explosion radius
func _get_explosion_radius() -> float:
	var mult := 1.0
	if Engine.has_singleton("GameState"):
		mult = GameState.grenades_radius_mult
	var radius = default_explosion_radius * mult
	print("[GRENADE] Explosion radius=%.1f (mult=%.2f)" % [radius, mult])
	return radius


func _ready() -> void:
	add_to_group("player_bullet")

	if speed <= 0.0:
		speed = base_speed
	if damage <= 0:
		damage = base_damage
	if explosion_radius <= 0.0:
		explosion_radius = default_explosion_radius

	grenade_velocity = direction.normalized() * speed
	fuse_left = fuse_time
	sprite.modulate = Color(1, 1, 1)

	_update_radius_indicator()
	if radius_indicator:
		radius_indicator.visible = false

	tween = create_tween()


func _process(delta: float) -> void:
	if exploded:
		return

	# lifetime safety
	life_timer += delta
	if life_timer >= max_lifetime:
		_explode()
		return

	# fuse countdown
	fuse_left -= delta
	if fuse_left <= 0.0:
		_explode()
		return

	# flashing faster over time
	var t = clamp(1.0 - fuse_left / fuse_time, 0.0, 1.0)
	var current_interval = lerp(flash_interval_start, flash_interval_end, t)

	flash_timer += delta
	if flash_timer >= current_interval:
		flash_timer = 0.0
		flash_on = not flash_on
		sprite.modulate = Color(1, 0.3, 0.3) if flash_on else Color(1, 1, 1)
		if radius_indicator:
			radius_indicator.modulate = Color(1, 0, 0, 0.7) if flash_on else Color(1, 0, 0, 0.3)


func _physics_process(delta: float) -> void:
	if exploded:
		return

	if grenade_velocity.length() > 0.0:
		var motion := grenade_velocity * delta
		var collision := move_and_collide(motion)

		if collision:
			var normal: Vector2 = collision.get_normal()
			grenade_velocity = grenade_velocity.bounce(normal) * bounciness
			global_position = collision.get_position() + normal * 1.5

		# apply friction
		grenade_velocity = grenade_velocity.move_toward(Vector2.ZERO, friction * delta)

		if grenade_velocity.length() < min_speed_before_stop:
			grenade_velocity = Vector2.ZERO

		# Show radius indicator when stopped
		if radius_indicator:
			radius_indicator.visible = (grenade_velocity.length() < 10)
			if radius_indicator.visible and tween and not tween.is_running():
				tween.tween_property(radius_indicator, "modulate:a", 0.3, 0.25).from(0.0)
				tween.play()


func _update_radius_indicator() -> void:
	if not radius_indicator or not radius_indicator.texture:
		return
	var radius := _get_explosion_radius()
	var tex_size := radius_indicator.texture.get_width() / 2.0
	var radius_scale := radius / tex_size
	print("[GRENADE] Indicator scale=%.2f (radius=%.1f, tex_size=%.1f)" % [radius_scale, radius, tex_size])
	radius_indicator.scale = Vector2.ONE * radius_scale
	# Optionally pulse effect
	if tween and radius_indicator.visible:
		tween.tween_property(radius_indicator, "scale", Vector2.ONE * (radius_scale * 1.05), 0.3).from(Vector2.ONE * radius_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_loops()


func _explode() -> void:
	if exploded:
		return
	exploded = true

	# stop colliding / showing the grenade itself
	if collision_shape:
		collision_shape.disabled = true
	if sprite:
		sprite.visible = false
	if light:
		light.visible = false   # hide grenade light instantly
	if radius_indicator:
		radius_indicator.visible = false

	# 🔊 play explosion SFX
	if sfx_explode:
		sfx_explode.play()

	# 💥 spawn optional explosion VFX
	if explosion_fx_scene:
		var fx = explosion_fx_scene.instantiate()
		fx.global_position = global_position
		get_tree().current_scene.add_child(fx)

	# 📸 camera shake
	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(cam_shake_strength, cam_shake_duration)

	# 💣 radial damage + knockback on enemies with LOS check
	var enemies := get_tree().get_nodes_in_group("enemy")
	var space_state := get_world_2d().direct_space_state
	for e in enemies:
		if not (e is Node2D) or not e.is_inside_tree():
			continue
		var to_enemy: Vector2 = e.global_position - global_position
		var dist := to_enemy.length()
		if dist <= _get_explosion_radius():
			var params := PhysicsRayQueryParameters2D.create(global_position, e.global_position)
			params.collision_mask = wall_collision_mask
			var result = space_state.intersect_ray(params)
			if result.is_empty() or (result.has("collider") and result.collider == e):
				# LOS is clear
				if e.has_method("take_damage"):
					e.take_damage(damage)
				if e.has_method("apply_knockback"):
					e.apply_knockback(global_position, explosion_knockback)
				elif dist > 0.0 and "velocity" in e:
					var dir := to_enemy.normalized()
					e.velocity += dir * explosion_knockback
			# else:
			#     print("[GRENADE] Blocked by wall between explosion and %s" % e.name)

	# 💥 PLAYER DAMAGE + KNOCKBACK (half damage)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var to_player := player.global_position - global_position
		var p_dist := to_player.length()

		if p_dist <= _get_explosion_radius():
			# Half damage to player
			if player.has_method("take_damage"):
				player.take_damage(int(damage * 0.5))

			# Use player's own knockback strength/duration
			if player.has_method("apply_knockback"):
				player.apply_knockback(global_position)
			elif p_dist > 0.0 and "velocity" in player:
				var dir := to_player.normalized()
				player.velocity += dir * explosion_knockback

	# wait for sound to finish then free
	if sfx_explode:
		await sfx_explode.finished

	queue_free()
