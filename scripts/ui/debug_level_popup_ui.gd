extends Control

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label
@onready var line_edit: LineEdit = $Panel/LineEdit
@onready var button: Button = $Panel/Button
@onready var autocomplete_list: ItemList = $Panel/AutocompleteList if has_node("Panel/AutocompleteList") else null
var _autocomplete_suggestions: Array = []


func _ready() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Updated label text
	label.text = "Debug Console (type 'help' for commands)"

	# Connect button and LineEdit submit
	button.pressed.connect(_on_button_pressed)
	line_edit.text_submitted.connect(_on_line_edit_submitted)

	# Create autocomplete list if not present
	if autocomplete_list == null:
		autocomplete_list = ItemList.new()
		autocomplete_list.name = "AutocompleteList"
		panel.add_child(autocomplete_list)
		# Basic layout: below the line edit
		autocomplete_list.position = Vector2(line_edit.position.x, line_edit.position.y + line_edit.size.y + 8)
		autocomplete_list.size = Vector2(panel.size.x - 20.0, 180.0)
		autocomplete_list.visible = false
		autocomplete_list.select_mode = ItemList.SELECT_SINGLE
		# Simple styling
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
		style.border_color = Color(0.3, 0.3, 0.4)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		autocomplete_list.add_theme_stylebox_override("panel", style)

	# Connect text change and gui input
	line_edit.text_changed.connect(_on_debug_text_changed)
	line_edit.gui_input.connect(_on_debug_input_gui_input)
	# Connect autocomplete selection
	autocomplete_list.item_selected.connect(_on_autocomplete_selected)
	autocomplete_list.hide()


func open_popup() -> void:
	visible = true
	# Optional: pause game while picking
	get_tree().paused = true

	line_edit.text = ""
	line_edit.grab_focus()
	# Reset autocomplete
	autocomplete_list.hide()


func _on_button_pressed() -> void:
	_apply_level_from_input()


func _on_line_edit_submitted(_text: String) -> void:
	_apply_level_from_input()
	# Hide autocomplete after submit
	autocomplete_list.hide()


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
	# Ensure dropdown hidden
	autocomplete_list.hide()


func _close_popup() -> void:
	visible = false
	get_tree().paused = false
	autocomplete_list.hide()

# --- AUTOCOMPLETE LOGIC --------------------------------------------

func _on_debug_text_changed(new_text: String) -> void:
	if new_text.is_empty():
		autocomplete_list.hide()
		return

	var parts = new_text.split(" ", false)
	if parts.is_empty():
		autocomplete_list.hide()
		return

	var command = parts[0].to_lower()
	var partial = parts[1] if parts.size() > 1 else ""
	
	# Don't show autocomplete if we already have more than 2 words (e.g., "upgrade something 100")
	if parts.size() > 2:
		autocomplete_list.hide()
		return

	var suggestions: Array = []

	match command:
		"weapon":
			suggestions = _get_weapon_suggestions(partial)
		"ability":
			suggestions = _get_ability_suggestions(partial)
		"upgrade":
			suggestions = _get_upgrade_suggestions(partial)
		"level":
			# numeric only
			autocomplete_list.hide()
			return
		_:
			if partial == "":
				suggestions = ["weapon", "ability", "upgrade", "coins", "health", "level", "clear", "help"]

	if suggestions.size() > 0:
		# Normalize to plain strings to avoid typed array issues
		var normalized: Array = []
		for s in suggestions:
			normalized.append(String(s))
		_show_autocomplete(normalized)
	else:
		autocomplete_list.hide()

func _get_weapon_suggestions(partial: String) -> Array:
	var weapons = ["shotgun", "sniper", "flamethrower", "grenade", "shuriken", "turret", "none"]
	if partial == "":
		return weapons
	var filtered: Array = []
	for w in weapons:
		if w.begins_with(partial.to_lower()):
			filtered.append(w)
	return filtered

func _get_ability_suggestions(partial: String) -> Array:
	var abilities = ["dash", "slow", "bubble", "invisibility", "invis", "none"]
	if partial == "":
		return abilities
	var filtered: Array = []
	for a in abilities:
		if a.begins_with(partial.to_lower()):
			filtered.append(a)
	return filtered


func _get_upgrade_suggestions(partial: String) -> Array:
	var upgrades: Array = []
	# Access the autoloaded UpgradesDB singleton's ALL_UPGRADES constant directly
	if UpgradesDB and "ALL_UPGRADES" in UpgradesDB:
		var allu = UpgradesDB.ALL_UPGRADES
		for u in allu:
			if typeof(u) == TYPE_DICTIONARY and u.has("id"):
				upgrades.append(String(u["id"]))
	if partial == "":
		return upgrades
	var filtered: Array = []
	for id in upgrades:
		if id.begins_with(partial.to_lower()):
			filtered.append(id)
	return filtered

func _show_autocomplete(suggestions: Array) -> void:
	autocomplete_list.clear()
	_autocomplete_suggestions = suggestions
	for s in suggestions:
		autocomplete_list.add_item(s)
	autocomplete_list.show()
	if autocomplete_list.get_item_count() > 0:
		autocomplete_list.select(0)

func _on_autocomplete_selected(index: int) -> void:
	if index < 0 or index >= _autocomplete_suggestions.size():
		return
	var selected = _autocomplete_suggestions[index]
	var current_text = line_edit.text
	var parts = current_text.split(" ", false)
	if parts.size() > 0:
		var command = parts[0]
		line_edit.text = command + " " + selected
		line_edit.caret_column = line_edit.text.length()
	autocomplete_list.hide()
	line_edit.grab_focus()

func _on_debug_input_gui_input(event: InputEvent) -> void:
	if not autocomplete_list.visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DOWN:
				var sel := autocomplete_list.get_selected_items()
				var idx: int = sel[0] if sel.size() > 0 else -1
				var count: int = autocomplete_list.get_item_count()
				if count == 0:
					return
				var next_idx: int = 0
				if idx >= 0:
					next_idx = (idx + 1) % count
				else:
					next_idx = 0
				autocomplete_list.select(next_idx)
				autocomplete_list.ensure_current_is_visible()
				get_viewport().set_input_as_handled()
			KEY_UP:
				var sel2 := autocomplete_list.get_selected_items()
				var idx2: int = sel2[0] if sel2.size() > 0 else 0
				var count2: int = autocomplete_list.get_item_count()
				if count2 == 0:
					return
				var next_idx2: int = (idx2 - 1 + count2) % count2
				autocomplete_list.select(next_idx2)
				autocomplete_list.ensure_current_is_visible()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				var cur := autocomplete_list.get_selected_items()
				if cur.size() > 0:
					_on_autocomplete_selected(cur[0])
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				autocomplete_list.hide()
				get_viewport().set_input_as_handled()


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
		print("[DEBUG] Usage: upgrade <upgrade_id> [count]")
		print("[DEBUG] Examples: primary_damage_plus_10, shotgun_unlock, max_hp_plus_1")
		print("[DEBUG] Optional: upgrade primary_fire_rate_uncommon 10 (apply 10 times)")
		print("[DEBUG] See Upgrades_DB.gd for full list")
		return
	
	var upgrade_id = parts[1]
	var count = 1
	
	# Optional third parameter: number of times to apply
	if parts.size() >= 3 and parts[2].is_valid_int():
		count = int(parts[2])
		count = clamp(count, 1, 100)  # Safety clamp
	
	# Apply upgrade N times
	for i in range(count):
		GameState.apply_upgrade(upgrade_id)
	
	# Sync player Health component after upgrades (especially max_hp_plus_1)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var hc := player.get_node_or_null("Health")
		if hc and hc.has_method("sync_from_gamestate"):
			hc.sync_from_gamestate()
	
	if count > 1:
		print("[DEBUG] Applied upgrade '", upgrade_id, "' x", count)
	else:
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
	
	# If setting health above current max, increase max_health first
	if amount > GameState.max_health:
		GameState.max_health = amount
		print("[DEBUG] Increased max_health to", amount)
	
	# Update GameState via setter to emit signals/UI
	GameState.set_health(amount)
	print("[DEBUG] Set GameState health to", GameState.health, "/", GameState.max_health)

	# Sync player Health component from GameState
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var hc := player.get_node_or_null("Health")
		if hc and hc.has_method("sync_from_gamestate"):
			hc.sync_from_gamestate()
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
	print("ability <name>             - Equip ability (dash, slow, bubble, invis, none)")
	print("upgrade <id> [count]       - Add upgrade 1 or N times (e.g., upgrade primary_damage_common 10)")
	print("coins <amount>             - Set coins (e.g., coins 999)")
	print("health <amount>            - Set health (e.g., health 50)")
	print("clear                      - Remove all upgrades/weapons/abilities")
	print("help                       - Show this help")
	print("")
	print("TIP: You can still just type a number to jump to that level!")
	print("===============================")
