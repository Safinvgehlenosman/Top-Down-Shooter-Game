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
@onready var sfx_despawn: AudioStreamPlayer2D = get_node_or_null("SFX_Despawn")


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
	# Play despawn sound before fading out
	if sfx_despawn:
		sfx_despawn.play()
	
	# Fade out and queue_free
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


## Generate loot based on chest type
func _generate_loot() -> Array:

	print("[Chest] Chest type: ", _get_chest_type_name())
	
	var loot := []
	var used_upgrade_bases := {}
	var target_count := 5
	
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
	
	print("[Chest] Built chest pool with %d upgrades" % loot.size())
	
	# ⭐ SAFETY: If we couldn't get 5 upgrades, fill with any valid upgrade
	if loot.size() < target_count:
		print("[Chest] WARNING: Only got ", loot.size(), " upgrades, filling rest with any valid upgrade")
		
		var attempts := 0
		var max_attempts := 100
		
		while loot.size() < target_count and attempts < max_attempts:
			attempts += 1
			
			# Get any upgrade that meets requirements
			var all_valid := []
			for upgrade in UpgradesDB.ALL_UPGRADES:
				# ⭐ Skip chaos upgrades
				if upgrade.get("effect") == "chaos_challenge":
					continue
				
				if _meets_requirements(upgrade):
					# Skip chaos upgrades
					if upgrade.get("effect") == "chaos_challenge":
						continue
					all_valid.append(upgrade)
			
			if all_valid.is_empty():

				break
			
			var filler_upgrade = all_valid.pick_random()
			var filler_id: String = filler_upgrade.get("id", "")
			var filler_base := _get_base_upgrade_id(filler_id)
			
			# Check for duplicates
			var is_duplicate := false
			for existing in loot:
				if existing.get("id") == filler_id:
					is_duplicate = true
					break
			
			# Check if base already used
			if used_upgrade_bases.has(filler_base):
				continue
			
			if not is_duplicate:
				loot.append(filler_upgrade)
				used_upgrade_bases[filler_base] = true
				print("[Chest] Added filler upgrade: ", filler_upgrade.get("name"), " (", filler_upgrade.get("rarity"), ")")

	loot.shuffle()
	
	print("[Chest] Final upgrade count: ", loot.size())
	
	for i in range(loot.size()):
		print("[Chest]   ", i + 1, ". ", loot[i].get("name"), " (rarity: ", loot[i].get("rarity"), ")")

	return loot
func _get_base_upgrade_id(upgrade_id: String) -> String:
	# Check if upgrade data has a line_id (use that as base)
	# Note: This version takes a String id, so we can't check the upgrade dict
	# But we can strip rarity suffixes like shop_ui does
	var parts := upgrade_id.split("_")
	if parts.size() > 1:
		var last := parts[-1].to_lower()
		# Remove rarity suffix if present
		if last in ["common", "uncommon", "rare", "epic"]:
			parts.remove_at(parts.size() - 1)
		# Remove numeric suffix if present
		elif parts[-1].is_valid_int():
			parts.remove_at(parts.size() - 1)
	return "_".join(parts)


## Get random upgrades of specific rarity that meet requirements
func _get_random_upgrades_by_rarity(rarity: int, count: int, used_bases: Dictionary) -> Array:
	var filtered := _filter_by_rarity(rarity)

	print("[Chest] Available upgrades in pool: ", filtered.size())
	
	if filtered.is_empty():
		push_warning("[Chest] No valid upgrades found for rarity %d" % rarity)
		return []
	
	var selected := []
	var attempts := 0
	var max_attempts := count * 20  # Increased from 10 to 20
	
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
		
		# Check if base upgrade type already used
		if used_bases.has(base_id):
			continue
		
		if not is_duplicate:
			selected.append(upgrade)
			used_bases[base_id] = true
			print("[Chest] Added: ", upgrade.get("name"), " - Total: ", selected.size())
	
	if selected.size() < count:
		push_warning("[Chest] Could only find %d/%d unique upgrades for rarity %d (attempts: %d)" % [selected.size(), count, rarity, attempts])
	
	return selected


## Filter all upgrades by rarity and requirements
func _filter_by_rarity(rarity: int) -> Array:
	var filtered := []
	
	for upgrade in UpgradesDB.ALL_UPGRADES:
		# ⭐ Skip chaos upgrades from normal chests
		if upgrade.get("effect") == "chaos_challenge":
			continue
		
		# ⭐ Skip HP upgrades during chaos challenge
		var id: String = upgrade.get("id", "")
		if not GameState.active_chaos_challenge.is_empty():
			if id == "max_hp_plus_1" or id == "hp_refill":
				continue
		
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
	# Weapon requirements (CSV stores as lowercase string like "shotgun")
	var requires_weapon: String = upgrade.get("requires_weapon", "").strip_edges().to_lower()
	if requires_weapon != "":
		var current_weapon: int = GameState.alt_weapon
		var current_weapon_name := _get_weapon_name(current_weapon)
		
		if requires_weapon != current_weapon_name:
			return false
	
	# Ability requirements (CSV stores as lowercase string like "dash")
	var requires_ability: String = upgrade.get("requires_ability", "").strip_edges().to_lower()
	if requires_ability != "":
		var current_ability: int = GameState.ability
		var current_ability_name := _get_ability_name(current_ability)
		
		if requires_ability != current_ability_name:
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

func _get_weapon_name(weapon_type: int) -> String:
	"""Convert weapon enum to lowercase string name."""
	match weapon_type:
		GameState.AltWeaponType.SHOTGUN: return "shotgun"
		GameState.AltWeaponType.SNIPER: return "sniper"
		GameState.AltWeaponType.SHURIKEN: return "shuriken"
		GameState.AltWeaponType.TURRET: return "turret"
		_: return ""

func _get_ability_name(ability_type: int) -> String:
	"""Convert ability enum to lowercase string name."""
	match ability_type:
		GameState.AbilityType.DASH: return "dash"
		GameState.AbilityType.INVIS: return "invis"
		_: return ""


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
