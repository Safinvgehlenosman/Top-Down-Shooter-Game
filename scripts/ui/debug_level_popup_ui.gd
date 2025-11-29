extends Control

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label
@onready var line_edit: LineEdit = $Panel/LineEdit
@onready var button: Button = $Panel/Button


func _ready() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Updated label text
	label.text = "Debug Console (type 'help' for commands)"

	# Connect button and LineEdit submit
	button.pressed.connect(_on_button_pressed)
	line_edit.text_submitted.connect(_on_line_edit_submitted)


func open_popup() -> void:
	visible = true
	# Optional: pause game while picking
	get_tree().paused = true

	line_edit.text = ""
	line_edit.grab_focus()


func _on_button_pressed() -> void:
	_apply_level_from_input()


func _on_line_edit_submitted(_text: String) -> void:
	_apply_level_from_input()


func _apply_level_from_input() -> void:
	var text := line_edit.text.strip_edges()

	if text == "":
		_close_popup()
		return

	# Parse command
	var parts = text.split(" ", false)
	if parts.is_empty():
		_close_popup()
		return
	
	var command = parts[0].to_lower()
	
	match command:
		"level":
			_cmd_level(parts)
		
		"weapon":
			_cmd_weapon(parts)
		
		"ability":
			_cmd_ability(parts)
		
		"upgrade":
			_cmd_upgrade(parts)
		
		"coins":
			_cmd_coins(parts)
		
		"health":
			_cmd_health(parts)
		
		"clear":
			_cmd_clear()
		
		"help", "?":
			_cmd_help()
		
		_:
			# Backward compatibility: just a number
			if text.is_valid_int():
				var target_level := int(text)
				if target_level < 1:
					target_level = 1
				
				var gm := get_tree().get_first_node_in_group("game_manager")
				if gm and gm.has_method("debug_set_level"):
					gm.debug_set_level(target_level)
					print("[DEBUG] Set level to:", target_level)
			else:
				print("[DEBUG] Unknown command:", command, "- Type 'help' for commands")

	_close_popup()


func _close_popup() -> void:
	visible = false
	get_tree().paused = false


# ============================================================================
# COMMAND FUNCTIONS
# ============================================================================

func _cmd_level(parts: Array) -> void:
	if parts.size() < 2:
		print("[DEBUG] Usage: level <number>")
		return
	
	var target_level := int(parts[1])
	if target_level < 1:
		target_level = 1
	
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("debug_set_level"):
		gm.debug_set_level(target_level)
		print("[DEBUG] Jumped to level", target_level)
	else:
		print("[DEBUG] Could not find GameManager.debug_set_level()")


func _cmd_weapon(parts: Array) -> void:
	if parts.size() < 2:
		print("[DEBUG] Usage: weapon <name>")
		print("[DEBUG] Available: shotgun, sniper, flamethrower, grenade, shuriken, turret, none")
		return
	
	var weapon_name = parts[1].to_lower()
	
	match weapon_name:
		"shotgun":
			GameState.set_alt_weapon(GameState.AltWeaponType.SHOTGUN)
			print("[DEBUG] Equipped shotgun")
		
		"sniper":
			GameState.set_alt_weapon(GameState.AltWeaponType.SNIPER)
			print("[DEBUG] Equipped sniper")
		
		"flamethrower", "flame":
			GameState.set_alt_weapon(GameState.AltWeaponType.FLAMETHROWER)
			print("[DEBUG] Equipped flamethrower")
		
		"grenade":
			GameState.set_alt_weapon(GameState.AltWeaponType.GRENADE)
			print("[DEBUG] Equipped grenade")
		
		"shuriken":
			GameState.set_alt_weapon(GameState.AltWeaponType.SHURIKEN)
			print("[DEBUG] Equipped shuriken")
		
		"turret":
			GameState.set_alt_weapon(GameState.AltWeaponType.TURRET)
			print("[DEBUG] Equipped turret")
		
		"none":
			GameState.set_alt_weapon(GameState.AltWeaponType.NONE)
			print("[DEBUG] Removed weapon")
		
		_:
			print("[DEBUG] Unknown weapon:", weapon_name)

	# Optional: parts[2] = ammo override (e.g., "weapon shotgun 10")
	if parts.size() >= 3 and parts[2].is_valid_int():
		var amt := int(parts[2])
		# Clamp to current weapon's max_ammo after set_alt_weapon applied
		GameState.set_ammo(clamp(amt, 0, GameState.max_ammo))
		print("[DEBUG] Ammo set to", GameState.ammo, "/", GameState.max_ammo)


func _cmd_ability(parts: Array) -> void:
	if parts.size() < 2:
		print("[DEBUG] Usage: ability <name>")
		print("[DEBUG] Available: dash, slow, bubble, invis, none")
		return
	
	var ability_name = parts[1].to_lower()
	
	match ability_name:
		"dash":
			GameState.ability = UpgradesDB.ABILITY_DASH
			print("[DEBUG] Equipped dash ability")
		
		"slow", "slowmo", "bullet_time", "time":
			GameState.ability = UpgradesDB.ABILITY_SLOWMO
			print("[DEBUG] Equipped bullet time ability")
		
		"bubble", "shield":
			GameState.ability = UpgradesDB.ABILITY_BUBBLE
			print("[DEBUG] Equipped shield bubble ability")
		
		"invis", "invisibility":
			GameState.ability = UpgradesDB.ABILITY_INVIS
			print("[DEBUG] Equipped invisibility ability")
		
		"none":
			GameState.ability = UpgradesDB.ABILITY_NONE
			print("[DEBUG] Removed ability")
		
		_:
			print("[DEBUG] Unknown ability:", ability_name)


func _cmd_upgrade(parts: Array) -> void:
	if parts.size() < 2:
		print("[DEBUG] Usage: upgrade <upgrade_id>")
		print("[DEBUG] Examples: primary_damage_plus_10, shotgun_unlock, max_hp_plus_1")
		print("[DEBUG] See Upgrades_DB.gd for full list")
		return
	
	var upgrade_id = parts[1]
	
	# Apply upgrade through UpgradesDB
	UpgradesDB.apply_upgrade(upgrade_id)
	print("[DEBUG] Applied upgrade:", upgrade_id)


func _cmd_coins(parts: Array) -> void:
	if parts.size() < 2:
		print("[DEBUG] Usage: coins <amount>")
		return
	
	var amount = int(parts[1])
	GameState.coins = amount
	print("[DEBUG] Set coins to", amount)


func _cmd_health(parts: Array) -> void:
	if parts.size() < 2:
		print("[DEBUG] Usage: health <amount>")
		return
	
	var amount = int(parts[1])
	# Update GameState via setter to emit signals/UI
	GameState.set_health(amount)
	print("[DEBUG] Set GameState health to", GameState.health, "/", GameState.max_health)

	# Also update the player's runtime Health component so hits don't revert
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var hc := player.get_node_or_null("Health")
		if hc and hc.has_method("set"):
			# Directly set the health property on the Health script
			hc.health = clamp(amount, 0, hc.max_health if "max_health" in hc else GameState.max_health)
			if hc.has_method("_emit_health_changed"):
				# If component has a method to notify UI, call it (optional)
				hc._emit_health_changed()
			print("[DEBUG] Synced player Health component to", hc.health)


func _cmd_clear() -> void:
	# Reset to starting state
	GameState.alt_weapon = UpgradesDB.ALT_WEAPON_NONE
	GameState.ability = UpgradesDB.ABILITY_NONE
	GameState.alt_weapon_ammo = 0
	GameState.max_alt_weapon_ammo = 0
	
	# Reset stats to base values (match your game's defaults)
	GameState.primary_damage = 10.0
	GameState.primary_fire_rate = 1.0
	GameState.primary_burst_count = 1
	GameState.move_speed = 200.0
	GameState.ability_cooldown_multiplier = 1.0
	
	print("[DEBUG] Cleared all upgrades, weapons, and abilities")


func _cmd_help() -> void:
	print("=== DEBUG CONSOLE COMMANDS ===")
	print("level <num>                - Jump to level (e.g., level 15)")
	print("weapon <name> [ammo]       - Equip weapon, optional ammo override (e.g., weapon shotgun 10)")
	print("ability <name>     - Equip ability (dash, slow, bubble, invis, none)")
	print("upgrade <id>       - Add upgrade (e.g., primary_damage_plus_10, shotgun_unlock)")
	print("coins <amount>     - Set coins (e.g., coins 999)")
	print("health <amount>    - Set health (e.g., health 50)")
	print("clear              - Remove all upgrades/weapons/abilities")
	print("help               - Show this help")
	print("")
	print("TIP: You can still just type a number to jump to that level!")
	print("===============================")
