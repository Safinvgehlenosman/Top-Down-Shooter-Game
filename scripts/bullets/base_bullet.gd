extends Area2D

@export var speed: float  = GameConfig.bullet_speed
@export var damage: int   = GameConfig.bullet_base_damage

@export var target_group: StringName = "enemy"

var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player_bullet")


func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO:
		return

	position += direction * speed * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()