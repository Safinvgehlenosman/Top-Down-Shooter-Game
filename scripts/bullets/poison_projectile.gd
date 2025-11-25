extends Area2D

@export var min_speed: float = 80.0
@export var max_speed: float = 140.0
@export var friction: float = 260.0       # how fast it slows down
@export var lifetime: float = 2.0         # how long the cloud stays

@export var poison_damage_per_tick: float = 0.5
@export var poison_duration: float = 3.0
@export var poison_tick_interval: float = 0.5

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

var _base_sprite_pos: Vector2 = Vector2.ZERO
var _wobble_phase: float = 0.0
var _max_alpha: float = 1.0


func _ready() -> void:
	time_left = lifetime

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
	# Only affect player (same as ice version)
	if not body.is_in_group("player"):
		return

	var hc := body.get_node_or_null("Health")
	if hc and hc.has_method("apply_poison"):
		hc.apply_poison(poison_damage_per_tick, poison_duration, poison_tick_interval)

	queue_free()
