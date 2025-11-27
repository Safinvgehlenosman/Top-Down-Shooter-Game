extends Node

func _input(event: InputEvent) -> void:
	# Existing stuff
	if event.is_action_pressed("debug_open_shop"):
		_debug_open_shop()

	if event.is_action_pressed("debug_add_coins"):
		_debug_give_coins()

	if event.is_action_pressed("debug_kill_slimes"):
		_debug_kill_slimes()

	if event.is_action_pressed("debug_next_level"):
		_debug_open_level_popup()

	# NEW: toggles
	if event.is_action_pressed("debug_toggle_god_mode"):
		_debug_toggle_god_mode()

	if event.is_action_pressed("debug_toggle_infinite_ammo"):
		_debug_toggle_infinite_ammo()

	if event.is_action_pressed("debug_toggle_noclip"):
		_debug_toggle_noclip()

	if event.is_action_pressed("debug_toggle_overlay"):
		_debug_toggle_overlay()

	if event.is_action_pressed("debug_laser_mode"):
		_debug_toggle_laser_mode()

# ------------------------------------------------------------
# DEBUG ACTIONS
# ------------------------------------------------------------

func _debug_open_shop() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("_open_shop"):
		gm._open_shop()
		print("[DEBUG] Shop opened.")
	else:
		print("[DEBUG] Could not find GameManager._open_shop()")


func _debug_give_coins() -> void:
	GameState.add_coins(99999)
	print("[DEBUG] +99999 coins")


func _debug_kill_slimes() -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")

	for e in enemies:
		if e:
			# Tell GameManager "this enemy died"
			if e.has_signal("died"):
				e.emit_signal("died")

			# Then remove it from the scene
			e.queue_free()

	print("[DEBUG] Killed", enemies.size(), "enemies (and notified GameManager)")


func _debug_open_level_popup() -> void:
	var popup := get_tree().get_first_node_in_group("debug_level_popup")
	if popup and popup.has_method("open_popup"):
		popup.open_popup()
	else:
		print("[DEBUG] DebugLevelPopup not found (group 'debug_level_popup').")


# ------------------------------------------------------------
# GOD MODE / INFINITE AMMO / NOCLIP
# ------------------------------------------------------------

func _debug_toggle_god_mode() -> void:
	GameState.debug_god_mode = !GameState.debug_god_mode
	print("[DEBUG] God mode:", GameState.debug_god_mode)
	_update_overlay_text()


func _debug_toggle_infinite_ammo() -> void:
	GameState.debug_infinite_ammo = !GameState.debug_infinite_ammo
	print("[DEBUG] Infinite ammo:", GameState.debug_infinite_ammo)
	_update_overlay_text()


func _debug_toggle_noclip() -> void:
	GameState.debug_noclip = !GameState.debug_noclip

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var shape := player.get_node_or_null("CollisionShape2D")
		if shape and shape is CollisionShape2D:
			shape.disabled = GameState.debug_noclip

	print("[DEBUG] Noclip:", GameState.debug_noclip)
	_update_overlay_text()

func _debug_toggle_laser_mode() -> void:
	GameState.debug_laser_mode = not GameState.debug_laser_mode
	var state := "ON" if GameState.debug_laser_mode else "OFF"
	print("[DEBUG] Laser mode:", state)
	_update_overlay_text()


# ------------------------------------------------------------
# OVERLAY (F12)
# ------------------------------------------------------------

func _debug_toggle_overlay() -> void:
	var overlay := get_tree().get_first_node_in_group("debug_overlay") as Control
	if overlay == null:
		print("[DEBUG] DebugOverlay not found (group 'debug_overlay').")
		return

	overlay.visible = not overlay.visible

	if overlay.visible:
		_update_overlay_text()
		print("[DEBUG] Debug overlay ON")
	else:
		print("[DEBUG] Debug overlay OFF")


func _update_overlay_text() -> void:
	var overlay := get_tree().get_first_node_in_group("debug_overlay")
	if overlay == null or not overlay.has_method("set_text"):
		return

	var god_str    = "ON" if GameState.debug_god_mode else "OFF"
	var ammo_str   = "ON" if GameState.debug_infinite_ammo else "OFF"
	var noclip_str = "ON" if GameState.debug_noclip else "OFF"
	var laser_str  = "ON" if GameState.debug_laser_mode else "OFF"

	var text := """
DEBUG HOTKEYS
-------------

F1 – Open shop
F2 – +99999 coins
F3 – Kill all enemies (spawn door)
F4 – Open level popup (set level)

F5 – God mode: %s
F6 – Infinite ammo: %s
F7 – Noclip (disable player collision): %s
Shift+F8 – Laser mode (0 CD, huge dmg): %s

F12 – Toggle this overlay
""" % [god_str, ammo_str, noclip_str, laser_str]

	overlay.set_text(text)
