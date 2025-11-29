extends Control

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label
@onready var line_edit: LineEdit = $Panel/LineEdit
@onready var button: Button = $Panel/Button


func _ready() -> void:
	visible = false

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
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_SHOTGUN
			GameState.alt_weapon_ammo = 10
			GameState.max_alt_weapon_ammo = 10
			print("[DEBUG] Equipped shotgun")
		
		"sniper":
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_SNIPER
			GameState.alt_weapon_ammo = 5
			GameState.max_alt_weapon_ammo = 5
			print("[DEBUG] Equipped sniper")
		
		"flamethrower", "flame":
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_FLAMETHROWER
			GameState.alt_weapon_ammo = 50
			GameState.max_alt_weapon_ammo = 50
			print("[DEBUG] Equipped flamethrower")
		
		"grenade":
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_GRENADE
			GameState.alt_weapon_ammo = 5
			GameState.max_alt_weapon_ammo = 5
			print("[DEBUG] Equipped grenade")
		
		"shuriken":
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_SHURIKEN
			GameState.alt_weapon_ammo = 20
			GameState.max_alt_weapon_ammo = 20
			print("[DEBUG] Equipped shuriken")
		
		"turret":
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_TURRET
			GameState.alt_weapon_ammo = 3
			GameState.max_alt_weapon_ammo = 3
			print("[DEBUG] Equipped turret")
		
		"none":
			GameState.alt_weapon = UpgradesDB.ALT_WEAPON_NONE
			GameState.alt_weapon_ammo = 0
			GameState.max_alt_weapon_ammo = 0
			print("[DEBUG] Removed weapon")
		
		_:
			print("[DEBUG] Unknown weapon:", weapon_name)


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
	GameState.health = amount
	print("[DEBUG] Set health to", amount)


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
	print("level <num>        - Jump to level (e.g., level 15)")
	print("weapon <name>      - Equip weapon (shotgun, sniper, flamethrower, grenade, shuriken, turret, none)")
	print("ability <name>     - Equip ability (dash, slow, bubble, invis, none)")
	print("upgrade <id>       - Add upgrade (e.g., primary_damage_plus_10, shotgun_unlock)")
	print("coins <amount>     - Set coins (e.g., coins 999)")
	print("health <amount>    - Set health (e.g., health 50)")
	print("clear              - Remove all upgrades/weapons/abilities")
	print("help               - Show this help")
	print("")
	print("TIP: You can still just type a number to jump to that level!")
	print("===============================")
