extends "res://scripts/bullets/base_bullet.gd"

@export var burn_damage: int = 5
@export var burn_duration: float = 2.0
@export var burn_interval: float = 0.2

# How long this flame particle lives (you can tweak this in the Inspector)
@export var lifetime: float = 0.35

var lifetime_timer: float


func _ready() -> void:
	# keep base_bullet setup (group etc.)
	super._ready()
	lifetime_timer = lifetime


func _physics_process(delta: float) -> void:
	# move like a normal bullet
	super._physics_process(delta)

	# countdown lifetime
	lifetime_timer -= delta
	if lifetime_timer <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		# optional direct hit damage (often 0 for pure DoT)
		if body.has_method("take_damage") and damage > 0:
			body.take_damage(damage)

		# Apply burn DoT if supported
		if body.has_method("apply_burn"):
			body.apply_burn(burn_damage, burn_duration, burn_interval)

	queue_free()
