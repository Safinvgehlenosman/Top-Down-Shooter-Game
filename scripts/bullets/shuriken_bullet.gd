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


func _ready() -> void:
	add_to_group("player_bullet")

	# fallback if gun didn't override them
	if speed <= 0.0:
		speed = base_speed
	if damage <= 0:
		damage = base_damage
	if bounces_left <= 0:
		bounces_left = default_bounces   # ensure at least 1 bounce

	print("Shuriken ready. speed=", speed, " damage=", damage, " bounces_left=", bounces_left)


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
		print("Shuriken hit:", collider, " normal=", normal, " bounces_left=", bounces_left)

		# ✅ Hit enemy → deal damage and disappear
		if collider and collider.is_in_group("enemy"):
			if collider.has_method("take_damage"):
				collider.take_damage(damage)
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

			print("Bounced! new dir=", direction, " bounces_left=", bounces_left)
		else:
			print("No bounces left -> despawn")
			queue_free()
