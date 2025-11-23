extends CanvasLayer  # or Control if your UI root is Control

@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill


func _process(delta: float) -> void:
	_update_ability_bar()


func _update_ability_bar() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		ability_bar.visible = false
		return

	# No ability equipped
	if GameState.ability == GameState.ABILITY_NONE:
		ability_bar.visible = false
		return

	# Load runtime ability stats
	var data: Dictionary = GameState.ABILITY_DATA.get(GameState.ability, {})
	if data.is_empty():
		ability_bar.visible = false
		return

	var max_cd: float = data.get("cooldown", 0.0)
	if max_cd <= 0.0:
		ability_bar.visible = false
		return
	
	ability_bar.visible = true
	ability_bar.max_value = max_cd

	# Player's cooldown time left
	var cd_left: float = player.ability_cooldown_left

	# Fill bar as cooldown refills
	ability_bar.value = max_cd - cd_left
