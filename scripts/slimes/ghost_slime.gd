extends "res://scripts/slimes/base_slime.gd"   # <-- adjust path if needed

@export var ghost_speed: float = 25.0   # slow creepy speed
@export var ghost_health: int = 1       # always 1 HP

# --- Spooky visual tuning ---
@export var alpha_min: float = 0.4
@export var alpha_max: float = 0.9
@export var pulse_speed: float = 2.5    # how fast alpha pulses

@export var bob_amount: float = 2.0     # pixels sprite bobs up/down
@export var bob_speed: float = 2.0

@export var light_flicker_strength: float = 0.25  # 0 = no flicker, 0.25 = mild

var _pulse_time: float = 0.0
var _sprite_base_pos: Vector2
var _light_base_energy: float = 0.0

func _ready() -> void:
	# Run base slime setup
	super._ready()

	# Override base stats
	speed = ghost_speed
	var hc := $Health

	hc.max_health = ghost_health
	hc.health = ghost_health


	# Always aggro from start
	aggro = true

	# Make ghost semi-transparent & maybe tinted slightly bluish/green
	var c := animated_sprite.modulate
	# Example tint: pale cyan
	c.r = 0.8
	c.g = 1.0
	c.b = 1.0
	animated_sprite.modulate = c

	# Store original local sprite position so we can bob visually
	_sprite_base_pos = animated_sprite.position

	# Light flicker setup
	if hit_light:
		_light_base_energy = hit_light.energy


func apply_level(_level: int) -> void:
	# Ghost ignores level scaling entirely
	return


func _update_ai(_delta: float) -> void:
	if not player:
		return

	# Always move toward player directly (no LOS, no wandering)
	var to_player := player.global_position - global_position
	if to_player.length() > 0.1:
		velocity = to_player.normalized() * speed
	else:
		velocity = Vector2.ZERO


func _process(delta: float) -> void:
	_pulse_time += delta

	# --- Alpha pulse (breathing ghost) ---
	var t := (sin(_pulse_time * pulse_speed) + 1.0) * 0.5  # 0..1
	var alpha = lerp(alpha_min, alpha_max, t)

	var c := animated_sprite.modulate
	c.a = alpha
	animated_sprite.modulate = c

	# --- Floaty bob (only sprite, not collision) ---
	var bob_offset := sin(_pulse_time * bob_speed) * bob_amount
	animated_sprite.position.y = _sprite_base_pos.y + bob_offset

	# --- Light flicker ---
	if hit_light and _light_base_energy > 0.0 and light_flicker_strength > 0.0:
		# subtle random flicker around base energy
		var noise := randf_range(-light_flicker_strength, light_flicker_strength)
		hit_light.energy = _light_base_energy * (1.0 + noise)
