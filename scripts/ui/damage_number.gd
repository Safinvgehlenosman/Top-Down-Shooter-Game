extends Node2D

@export var rise_speed: float = 30.0
@export var lifetime: float = 1.2
@export var fade_start: float = 0.5

var velocity: Vector2 = Vector2.ZERO
var time_alive: float = 0.0
var rotation_speed: float = 0.0
var initial_scale: float = 0.58
var total_damage: int = 0

var follow_target: Node2D = null  # Enemy to follow while stacking
var follow_offset: Vector2 = Vector2(0, -20)  # Offset from enemy position
var is_following: bool = true  # Whether to follow the target

@onready var label: Label = $Label
@onready var point_light: PointLight2D = get_node_or_null("PointLight2D")


func _ready() -> void:
	# Set velocity but don't apply it yet
	velocity = Vector2(randf_range(-10, 10), -rise_speed)
	
	# Start with punch scale (reduced from 1.2 to 1.15)
	scale = Vector2(initial_scale, initial_scale)
	
	# Small initial rotation
	rotation = randf_range(-0.1, 0.1)


func setup(damage: int, is_crit: bool = false, target: Node2D = null) -> void:
	if not label:
		return
	
	# Track the enemy so we can follow them
	follow_target = target
	
	total_damage = damage
	
	# Configure outline for readability
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	# Update display with initial damage
	_update_display(is_crit)


func add_damage(additional_damage: int) -> void:
	var old_total := total_damage
	total_damage += additional_damage
	
	# RESET lifetime completely so it stays visible
	time_alive = 0.0
	
	# Bounce effect
	_do_combo_bounce()
	
	# Update display
	_update_display(false)


func _update_display(is_crit: bool) -> void:
	if not label:
		return
	
	# Update text
	var damage_text := str(total_damage)
	if is_crit:
		damage_text += "!"
	label.text = damage_text
	
	# Color based on total damage
	var color := Color(1.0, 0.4, 0.4)
	var font_size := 10
	
	if is_crit:
		# CRITICAL HIT - Gold color and larger
		color = Color(1.0, 0.85, 0.0)
		if total_damage < 20:
			font_size = 12
		elif total_damage < 40:
			font_size = 14
		elif total_damage < 60:
			font_size = 16
		else:
			font_size = 18
		# Extra scale bounce for crits
		initial_scale = 0.63
		scale = Vector2(initial_scale, initial_scale)
	else:
		# NORMAL DAMAGE - Color gradient by amount
		if total_damage < 20:
			color = Color(1.0, 0.4, 0.4)  # Light red (small hits)
			font_size = 10
		elif total_damage < 40:
			color = Color(1.0, 0.5, 0.3)  # Orange-red (medium hits)
			font_size = 12
		elif total_damage < 60:
			color = Color(1.0, 0.7, 0.2)  # Bright orange (big hits)
			font_size = 14
		else:  # 60+
			color = Color(1.0, 0.9, 0.3)  # Yellow-orange (huge hits)
			font_size = 16
			# Extra scale for huge damage
			initial_scale = 0.60
			scale = Vector2(initial_scale, initial_scale)
	
	# Apply font size
	label.add_theme_font_size_override("font_size", font_size)
	
	# Apply color
	label.add_theme_color_override("font_color", color)
	
	# Set point light color if it exists
	if point_light:
		point_light.color = color
		point_light.energy = 0.8


func _do_combo_bounce() -> void:
	# Quick elastic bounce when damage is added
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	
	tween.tween_property(self, "scale", Vector2(0.65, 0.65), 0.1)
	tween.tween_property(self, "scale", Vector2(0.50, 0.50), 0.15)


func stop_following() -> void:
	is_following = false
	# Set initial velocity for floating away
	velocity = Vector2(randf_range(-10, 10), -rise_speed)


func _process(delta: float) -> void:
	time_alive += delta
	
	# Check if lifetime expired
	if time_alive >= lifetime:
		queue_free()
		return
	
	# FOLLOW TARGET while stacking is active
	if is_following and follow_target != null and is_instance_valid(follow_target):
		# Update position to follow enemy (with offset)
		global_position = follow_target.global_position + follow_offset
	else:
		# Normal floating movement when not following
		global_position += velocity * delta
	
	# Rotation wobble (sin wave between -5° and +5°)
	rotation = sin(time_alive * 3.0) * deg_to_rad(5.0)
	
	# Scale punch - shrink from initial to 0.50 in first 0.1 seconds
	if time_alive < 0.1:
		var t := time_alive / 0.1
		var punch_scale = lerp(initial_scale, 0.50, t)
		scale = Vector2(punch_scale, punch_scale)
	
	# Fade out in the last portion of lifetime
	if time_alive > (lifetime - fade_start):
		var fade_time := time_alive - (lifetime - fade_start)
		var alpha := 1.0 - (fade_time / fade_start)
		
		# Fade label
		if label:
			label.modulate.a = alpha
		
		# Fade point light if it exists
		if point_light:
			point_light.energy = 0.8 * alpha