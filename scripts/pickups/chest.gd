extends Area2D

## Chest types: determines loot rarity distribution
enum ChestType {
	BRONZE,
	NORMAL,
	GOLD
}

## Export: Set chest type in scene or via code
@export var chest_type: ChestType = ChestType.NORMAL

var is_opened: bool = false
var player_nearby: bool = false
var interact_prompt: Label

# Hover animation
var hover_time: float = 0.0
var base_prompt_pos: Vector2
@export var hover_amplitude: float = 3.0
@export var hover_speed: float = 2.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_spawn: AudioStreamPlayer2D = get_node_or_null("SFX_Spawn")
@onready var sfx_open: AudioStreamPlayer2D = get_node_or_null("SFX_Open")


func _ready() -> void:
	add_to_group("room_cleanup")
	
	# Get reference to InteractPrompt
	interact_prompt = get_node_or_null("InteractPrompt")
	
	# Hide interact_prompt by default
	if interact_prompt:
		interact_prompt.visible = false
		base_prompt_pos = interact_prompt.position
	
	# Play spawn sound
	if sfx_spawn:
		sfx_spawn.play()
	
	# body_entered signal already connected in scene file
	# Only connect body_exited if not already connected
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Check for interact input
	if Input.is_action_just_pressed("interact"):
		if player_nearby and not is_opened:
			_open_chest()
	
	# Hover animation for prompt
	if interact_prompt and interact_prompt.visible and not is_opened:
		hover_time += delta
		var offset_y := sin(hover_time * hover_speed) * hover_amplitude
		interact_prompt.position.y = base_prompt_pos.y + offset_y


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		# Show interact prompt if not opened
		if not is_opened and interact_prompt:
			interact_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		# Hide interact prompt
		if interact_prompt:
			interact_prompt.visible = false


func _open_chest() -> void:
	# Mark as opened
	is_opened = true
	
	# Hide interact prompt
	if interact_prompt:
		interact_prompt.visible = false
	
	# Disable collision
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Play open sound if exists
	if sfx_open:
		sfx_open.play()
	
	# Get ShopUI and open as chest with rarity-filtered loot
	var shop_ui = get_tree().get_first_node_in_group("shop")
	if shop_ui and shop_ui.has_method("open_as_chest_with_loot"):
		var loot = _generate_loot()
		shop_ui.open_as_chest_with_loot(loot)
	elif shop_ui and shop_ui.has_method("open_as_chest"):
		# Fallback for older shop_ui without custom loot support
		shop_ui.open_as_chest()

	# Despawn chest immediately after opening shop
	_despawn_chest()

func _despawn_chest() -> void:
	# Fade out and queue_free
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


## Generate loot based on chest type
func _generate_loot() -> Array:
	var loot := []
	var used_upgrade_bases := {}
	match chest_type:
		ChestType.BRONZE:
			# 2 Common, 3 Uncommon
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.COMMON, 2, used_upgrade_bases))
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.UNCOMMON, 3, used_upgrade_bases))
		ChestType.NORMAL:
			# 2 Uncommon, 3 Rare
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.UNCOMMON, 2, used_upgrade_bases))
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.RARE, 3, used_upgrade_bases))
		ChestType.GOLD:
			# 1 Uncommon, 3 Rare, 1 Epic
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.UNCOMMON, 1, used_upgrade_bases))
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.RARE, 3, used_upgrade_bases))
			loot.append_array(_get_random_upgrades_by_rarity(UpgradesDB.Rarity.EPIC, 1, used_upgrade_bases))
	loot.shuffle()
	print("[Chest] Generated %d upgrades for %s chest" % [loot.size(), _get_chest_type_name()])
	return loot
func _get_base_upgrade_id(upgrade_id: String) -> String:
	var parts := upgrade_id.split("_")
	if parts.size() > 1:
		var last_part := parts[-1]
		if last_part.is_valid_int():
			parts.remove_at(parts.size() - 1)
	return "_".join(parts)


## Get random upgrades of specific rarity that meet requirements
func _get_random_upgrades_by_rarity(rarity: int, count: int, used_bases: Dictionary) -> Array:
	var filtered := _filter_by_rarity(rarity)
	if filtered.is_empty():
		push_warning("[Chest] No valid upgrades found for rarity %d" % rarity)
		return []
	var selected := []
	var attempts := 0
	var max_attempts := count * 10
	while selected.size() < count and attempts < max_attempts:
		attempts += 1
		var upgrade = filtered.pick_random()
		var upgrade_id: String = upgrade.get("id", "")
		var base_id := _get_base_upgrade_id(upgrade_id)
		# Check if already selected (no duplicates)
		var is_duplicate := false
		for s in selected:
			if s.get("id") == upgrade_id:
				is_duplicate = true
				break
		# NEW: Check if base upgrade type already used
		if used_bases.has(base_id):
			continue
		if not is_duplicate:
			selected.append(upgrade)
			used_bases[base_id] = true
	if selected.size() < count:
		push_warning("[Chest] Could only find %d/%d unique upgrades for rarity %d" % [selected.size(), count, rarity])
	return selected


## Filter all upgrades by rarity and requirements
func _filter_by_rarity(rarity: int) -> Array:
	var filtered := []
	
	for upgrade in UpgradesDB.ALL_UPGRADES:
		# Check rarity match
		if upgrade.get("rarity") != rarity:
			continue
		
		# Check if upgrade meets player requirements
		if not _meets_requirements(upgrade):
			continue
		
		filtered.append(upgrade)
	
	return filtered


## Check if player meets upgrade requirements
func _meets_requirements(upgrade: Dictionary) -> bool:
	# Weapon requirements
	if upgrade.has("requires_alt_weapon"):
		var required = upgrade.get("requires_alt_weapon")
		var current: int = GameState.alt_weapon
		
		# If requires NONE, player must not have any alt weapon
		if required == UpgradesDB.ALT_WEAPON_NONE:
			if current != UpgradesDB.ALT_WEAPON_NONE:
				return false
		# If requires specific weapon, player must have it
		elif current != required:
			return false
	
	# Ability requirements
	if upgrade.has("requires_ability"):
		var required = upgrade.get("requires_ability")
		var current: int = GameState.ability
		
		# If requires NONE, player must not have any ability
		if required == UpgradesDB.ABILITY_NONE:
			if current != UpgradesDB.ABILITY_NONE:
				return false
		# If requires specific ability, player must have it
		elif current != required:
			return false
	
	# Ammo weapon requirement
	if upgrade.get("requires_ammo_weapon", false):
		if not _player_has_ammo_weapon():
			return false
	
	# Any ability requirement
	if upgrade.get("requires_any_ability", false):
		if GameState.ability == UpgradesDB.ABILITY_NONE:
			return false
	
	return true


## Check if player has an ammo-consuming weapon
func _player_has_ammo_weapon() -> bool:
	var weapon_type: int = GameState.alt_weapon
	
	# Weapons that consume ammo
	var ammo_weapons := [
		UpgradesDB.ALT_WEAPON_SHOTGUN,
		UpgradesDB.ALT_WEAPON_SNIPER,
		UpgradesDB.ALT_WEAPON_GRENADE,
	]
	
	return weapon_type in ammo_weapons


## Get chest type name for debug
func _get_chest_type_name() -> String:
	match chest_type:
		ChestType.BRONZE:
			return "BRONZE"
		ChestType.NORMAL:
			return "NORMAL"
		ChestType.GOLD:
			return "GOLD"
		_:
			return "UNKNOWN"
