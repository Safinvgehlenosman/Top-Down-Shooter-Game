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
