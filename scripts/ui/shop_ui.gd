
extends CanvasLayer




##
## ShopUI.gd - CORRECTED NODE PATHS
## AbilityBar is at ROOT level, not under Panel!
##

# Use GameState enums directly

const ALT_WEAPON_NONE = GameState.AltWeaponType.NONE
const ALT_WEAPON_SHOTGUN = GameState.AltWeaponType.SHOTGUN
const ALT_WEAPON_SNIPER = GameState.AltWeaponType.SNIPER
const ALT_WEAPON_TURRET = GameState.AltWeaponType.TURRET
const ALT_WEAPON_SHURIKEN = GameState.AltWeaponType.SHURIKEN

const ABILITY_NONE = GameState.AbilityType.NONE
const ABILITY_DASH = GameState.AbilityType.DASH
const ABILITY_INVIS = GameState.AbilityType.INVIS

# Helper: derive base upgrade id (so only one rarity per type appears)
func _get_base_upgrade_id(up: Dictionary) -> String:
	var id: String = up.get("id", "")
	if up.has("line_id"):
		return String(up.get("line_id"))
	
	# Special case: weapon/ability unlocks should each be unique (don't group them)
	if id.ends_with("_unlock"):
		return id
	
	var parts := id.split("_")
	if parts.size() > 1:
		var last := parts[-1].to_lower()
		# Remove tier suffix (t1, t2, t3, t4)
		if last.begins_with("t") and last.substr(1).is_valid_int():
			parts.remove_at(parts.size() - 1)
		# Remove old rarity suffix (common, uncommon, rare, epic)
		elif last in ["common", "uncommon", "rare", "epic"]:
			parts.remove_at(parts.size() - 1)
		# Remove numeric suffix
		elif parts[-1].is_valid_int():
			parts.remove_at(parts.size() - 1)
	return "_".join(parts)

@onready var continue_button := $Panel/ContinueButton
@onready var cards_container := $Panel/Cards


# Chest mode flag
var is_chest_mode: bool = false
var active_chest: Node2D = null  # Reference to the chest that opened this shop

# New UI structure - use get_node_or_null for safety
@onready var hp_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/HPFill")
@onready var hp_label: Label = get_node_or_null("PlayerInfo/HP")
@onready var ability_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/AbilityProgressBar")
@onready var ability_label: Label = get_node_or_null("PlayerInfo/ABILITY")
@onready var ammo_label: Label = get_node_or_null("Ammo/AmmoLabel")
@onready var coin_label: Label = get_node_or_null("Coins/CoinsLabel")
@onready var level_label: Label = get_node_or_null("Level/LevelLabel")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect to GameState signals
	var gs = GameState
	gs.connect("coins_changed", Callable(self, "_on_coins_changed"))
	gs.connect("health_changed", Callable(self, "_on_health_changed"))

	# Always start hidden
	if ability_progress_bar:
		ability_progress_bar.visible = false

	_setup_cards()
	_refresh_from_state_full()

	continue_button.pressed.connect(_on_continue_pressed)

	# Initialize all cards to non-hovered state
	await get_tree().process_frame
	for card in cards_container.get_children():
		if card.has_method("set_hovered"):
			card.set_hovered(false)

	# Debug: Monitor Panel mouse filter changes
	if has_node("Panel"):
		var panel = $Panel
		print("[SHOP UI] Panel mouse_filter at ready: ", panel.mouse_filter)
		# Force it to PASS
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		print("[SHOP UI] Forced Panel mouse_filter to PASS (1)")
		# Monitor it every frame to catch changes
		set_process(true)


func _process(_delta: float) -> void:
	# Debug: Check Panel mouse filter every frame
	if has_node("Panel"):
		var panel = $Panel
		if panel.mouse_filter != Control.MOUSE_FILTER_PASS:
			print("[SHOP UI] ⚠️ Panel mouse_filter changed to: ", panel.mouse_filter, " - FORCING BACK TO PASS")
			panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Update displays continuously
	_update_hp_from_state()
	_update_ability_bar()
	_update_level_label()


# -------------------------------------------------------------------
# CARD SETUP
# -------------------------------------------------------------------

func _setup_card_hover_events(card: Control) -> void:
	"""Connect hover events to card for scaling effect."""
	if not card.has_method("set_hovered"):
		return
	
	# Connect mouse entered/exited
	card.mouse_entered.connect(func(): _on_card_hovered(card, true))
	card.mouse_exited.connect(func(): _on_card_hovered(card, false))


func _on_card_hovered(hovered_card: Control, is_hovered: bool) -> void:
	"""Handle card hover - scale the hovered card, reset others."""
	if is_hovered:
		# Set this card as hovered, others as not
		for card in cards_container.get_children():
			if card.has_method("set_hovered"):
				card.set_hovered(card == hovered_card)
	else:
		# Reset just this card
		if hovered_card.has_method("set_hovered"):
			hovered_card.set_hovered(false)


# -------------------------------------------------------------------
# PRICE CALCULATION
# -------------------------------------------------------------------

func _calculate_upgrade_price(upgrade: Dictionary) -> int:
	"""Return price from upgrade data (loaded from CSV), reduced by 15%."""
	var base_price = upgrade.get("price", 50)
	var final_price = base_price * 1.0 # shop_price_mult removed
	return int(final_price)


func _setup_cards() -> void:
	# ⭐ Reset all cards first to clear any chaos/single-card state
	_reset_all_cards()
	
	# Disconnect old signals (both shop AND chest handlers)
	for card in cards_container.get_children():
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)
		if card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.disconnect(_on_chest_card_purchased)

	var offers := _roll_shop_offers()
	
	# Apply calculated prices to all offers (duplicate to avoid read-only state)
	for i in range(offers.size()):
		var calculated_price = _calculate_upgrade_price(offers[i])
		# Duplicate the dictionary to make it writable
		var offer_copy = offers[i].duplicate()
		offer_copy["price"] = calculated_price
		offers[i] = offer_copy
	
	# Sort offers by rarity (highest rarity first)
	offers = _sort_offers_by_rarity(offers)
	
	# Assign to positions: center (2), middle (1,3), outer (0,4)
	# This puts rarest in center
	var position_order = [2, 1, 3, 0, 4]  # Center-out order
	var children := cards_container.get_children()
	var used_positions = []  # Track which positions we've used
	
	for i in range(position_order.size()):
		if i >= offers.size():
			break
		
		var position = position_order[i]
		if position >= children.size():
			continue
		
		var card = children[position]
		card.visible = true
		card.modulate = Color(1, 1, 1, 1)  # Reset to fully opaque
		card.setup(offers[i])
		
		if not card.purchased.is_connected(_on_card_purchased):
			card.purchased.connect(_on_card_purchased)
		
		# Connect hover events
		# Hover events removed as they are broken
		
		used_positions.append(position)
	
	# Hide unused cards
	for i in range(children.size()):
		if i not in used_positions:
			children[i].visible = false

func _roll_shop_offers() -> Array:
	var result: Array = []
	var taken_ids: Array[String] = []
	var taken_bases := {}

	var gm := get_tree().get_first_node_in_group("game_manager")
	var current_level := 1
	if gm and "current_level" in gm:
		current_level = gm.current_level

	var rarity_weights := _get_rarity_weights_for_level(current_level)
	
	# Get enabled shop upgrades only
	var all_upgrades: Array = UpgradesDB.filter_by_pool("shop")
	# Remove combustion upgrade explicitly
	all_upgrades = all_upgrades.filter(func(up): return up.get("id", "") != "general_combustion_1")
	
	# Filter by loadout requirements if possible
	var equipped_weapon := _get_equipped_weapon_name()
	var equipped_ability := _get_equipped_ability_name()
	
	var loadout_filtered := []
	for upgrade in all_upgrades:
		if UpgradesDB.is_upgrade_available_for_loadout(upgrade, equipped_weapon, equipped_ability):
			loadout_filtered.append(upgrade)
	
	all_upgrades = loadout_filtered
	print("[Shop] Built shop pool with %d upgrades" % all_upgrades.size())

	var max_cards = min(5, cards_container.get_child_count())

	for i in range(max_cards):
		var rarity := _roll_rarity(rarity_weights)
		var candidates := _filter_upgrades(all_upgrades, rarity, taken_ids, taken_bases)
		if candidates.is_empty():
			candidates = _filter_upgrades(all_upgrades, null, taken_ids, taken_bases)
		if candidates.is_empty():
			break
		candidates.shuffle()
		
		# Pick first candidate (already filtered by _filter_upgrades to exclude taken bases)
		var chosen: Dictionary = candidates[0]
		result.append(chosen)
		taken_ids.append(chosen["id"])
		var chosen_base := _get_base_upgrade_id(chosen)
		taken_bases[chosen_base] = true

	return result

func _get_equipped_weapon_name() -> String:
	"""Convert GameState alt_weapon enum to lowercase string name."""
	if not GameState:
		return ""
	
	match GameState.alt_weapon:
		GameState.AltWeaponType.SHOTGUN: return "shotgun"
		GameState.AltWeaponType.SNIPER: return "sniper"
		GameState.AltWeaponType.SHURIKEN: return "shuriken"
		GameState.AltWeaponType.TURRET: return "turret"
		_: return ""

func _get_equipped_ability_name() -> String:
	"""Convert GameState ability enum to lowercase string name."""
	if not GameState:
		return ""
	
	match GameState.ability:
		GameState.AbilityType.DASH: return "dash"
		GameState.AbilityType.INVIS: return "invis"
		_: return ""

func _player_has_any_synergy_upgrade() -> bool:
	"""Check if player has purchased any synergy rarity upgrade."""
	var all_upgrades := UpgradesDB.get_all()
	for upgrade in all_upgrades:
		if upgrade.get("rarity") == UpgradesDB.Rarity.SYNERGY:
			var upgrade_id: String = upgrade.get("id", "")
			if upgrade_id != "" and GameState.has_upgrade(upgrade_id):
				return true
	return false

func _sort_offers_by_rarity(offers: Array) -> Array:
	"""Sort offers by rarity (highest first), then by price (highest first) for same rarity."""
	var sorted = offers.duplicate()
	
	# Custom sort: higher rarity first, then higher price within same rarity
	sorted.sort_custom(func(a, b):
		var rarity_a = a.get("rarity", UpgradesDB.Rarity.COMMON)
		var rarity_b = b.get("rarity", UpgradesDB.Rarity.COMMON)
		
		if rarity_a == rarity_b:
			# Same rarity: sort by price (highest first)
			var price_a = a.get("price", 0)
			var price_b = b.get("price", 0)
			return price_a > price_b
		else:
			# Higher rarity comes first
			return rarity_a > rarity_b
	)
	
	return sorted


func _get_rarity_weights_for_level(level: int) -> Dictionary:
	# New rarity curve: shifts rarities earlier
	# Level 1: 50/35/12/3
	# Level 5: 45/38/14/3
	# Level 10: 40/40/16/4
	# Level 20: 30/45/18/7
	# Level 30+: 25/48/18/9
	
	var common := 50.0
	var uncommon := 35.0
	var rare := 12.0
	var epic := 3.0
	
	if level >= 30:
		common = 25.0
		uncommon = 48.0
		rare = 18.0
		epic = 9.0
	elif level >= 20:
		common = 30.0
		uncommon = 45.0
		rare = 18.0
		epic = 7.0
	elif level >= 10:
		common = 40.0
		uncommon = 40.0
		rare = 16.0
		epic = 4.0
	elif level >= 5:
		common = 45.0
		uncommon = 38.0
		rare = 14.0
		epic = 3.0
	# else: use initial values (level 1-4)

	# Only add synergy to pool if:
	# 1. Player has unlocked ANY weapon AND ANY ability
	# Individual synergies are filtered by their requirements and stackable flag
	var has_weapon := GameState.get_unlocked_weapons().size() > 0
	var has_ability := GameState.get_unlocked_abilities().size() > 0
	var can_access_synergy := has_weapon and has_ability
	
	print("[SYNERGY DEBUG] Unlocked weapons: %d, Unlocked abilities: %d, Can access: %s" % [GameState.get_unlocked_weapons().size(), GameState.get_unlocked_abilities().size(), can_access_synergy])
	
	var base_total := common + uncommon + rare + epic
	var synergy := 0.0
	if can_access_synergy:
		# Synergy gets 25% chance, other rarities share the remaining 75%
		synergy = base_total / 3.0  # 25% synergy means base_total is 75%, so synergy = 75/3 = 25%

	var total := base_total + synergy
	if total <= 0.0:
		return {
			UpgradesDB.Rarity.COMMON: 1.0,
			UpgradesDB.Rarity.UNCOMMON: 0.0,
			UpgradesDB.Rarity.RARE: 0.0,
			UpgradesDB.Rarity.EPIC: 0.0,
			UpgradesDB.Rarity.SYNERGY: 0.0,
		}

	return {
		UpgradesDB.Rarity.COMMON: common / total,
		UpgradesDB.Rarity.UNCOMMON: uncommon / total,
		UpgradesDB.Rarity.RARE: rare / total,
		UpgradesDB.Rarity.EPIC: epic / total,
		UpgradesDB.Rarity.SYNERGY: synergy / total,
	}

func _roll_rarity(weights: Dictionary = {}) -> UpgradesDB.Rarity:
	# Use provided weights or default to level-based weights
	if weights.is_empty():
		var gm := get_tree().get_first_node_in_group("game_manager")
		var current_level := 1
		if gm and "current_level" in gm:
			current_level = gm.current_level
		weights = _get_rarity_weights_for_level(current_level)
	
	var r := randf()
	var acc := 0.0

	for rarity in [UpgradesDB.Rarity.COMMON, UpgradesDB.Rarity.UNCOMMON, UpgradesDB.Rarity.RARE, UpgradesDB.Rarity.EPIC, UpgradesDB.Rarity.SYNERGY]:
		acc += float(weights.get(rarity, 0.0))
		if r <= acc:
			return rarity as UpgradesDB.Rarity

	return UpgradesDB.Rarity.COMMON

func _filter_upgrades(all_upgrades: Array, wanted_rarity: Variant, taken_ids: Array[String], taken_bases: Dictionary) -> Array:
	var res: Array = []

	for u in all_upgrades:
		var id: String = u.get("id", "")
		if id == "" or id in taken_ids:
			continue
		
		# Debug synergy filtering
		if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
			pass

		# ⭐ EXCLUDE CHAOS UPGRADES FROM NORMAL SHOPS/CHESTS
		if u.get("effect") == "chaos_challenge":
			continue
		
		# ⭐ EXCLUDE HP UPGRADES DURING ACTIVE CHAOS CHALLENGE
		if not GameState.active_chaos_challenge.is_empty():
			if id == "max_hp_plus_1" or id == "hp_refill":
				continue

		if wanted_rarity != null and u.get("rarity", UpgradesDB.Rarity.COMMON) != wanted_rarity:
			continue

		if not _upgrade_meets_requirements(u):
			if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
				print("[SYNERGY DEBUG] Synergy %s FAILED requirements" % u.get("id", ""))
			continue
		
		# If we got here, synergy passed all requirements
		if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
			print("[SYNERGY DEBUG] Synergy %s PASSED all requirements!" % u.get("id", ""))

		# Skip non-stackable upgrades that the player already owns
		var stackable := bool(u.get("stackable", true))
		if not stackable and GameState.has_upgrade(id):
			continue

		# Enforce base uniqueness (skip if base already used)
		var base_id := _get_base_upgrade_id(u)
		if taken_bases.has(base_id):
			continue
		res.append(u)
		
		# Debug when synergy passes all filters
		if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
			pass

	return res

func _upgrade_meets_requirements(u: Dictionary) -> bool:
	# Use new CSV schema fields if available
	if u.has("requires_weapon") and u["requires_weapon"] != "":
		var equipped_weapon := _get_equipped_weapon_name()
		var required_weapon: String = u["requires_weapon"]
		
		# "none" means this upgrade only appears when NO weapon is equipped
		if required_weapon == "none":
			if equipped_weapon != "":
				return false
		else:
			# Specific weapon required
			if required_weapon != equipped_weapon:
				if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
					print("[SYNERGY DEBUG] %s requires weapon '%s' but equipped is '%s' - FAILED" % [u.get("id", ""), required_weapon, equipped_weapon])
				return false
			else:
				if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
					print("[SYNERGY DEBUG] %s weapon requirement '%s' PASSED" % [u.get("id", ""), required_weapon])
	
	if u.has("requires_ability") and u["requires_ability"] != "":
		var equipped_ability := _get_equipped_ability_name()
		var required_ability: String = u["requires_ability"]
		
		
		# "none" means this upgrade only appears when NO ability is equipped
		if required_ability == "none":
			if equipped_ability != "":
				return false
		else:
			# Specific ability required
			if required_ability != equipped_ability:
				if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
					print("[SYNERGY DEBUG] %s requires ability '%s' (original: '%s') but equipped is '%s' - FAILED" % [u.get("id", ""), required_ability, u["requires_ability"], equipped_ability])
				return false
			else:
				if u.get("rarity", 0) == UpgradesDB.Rarity.SYNERGY:
					print("[SYNERGY DEBUG] %s ability requirement '%s' PASSED" % [u.get("id", ""), required_ability])
	
	# Legacy: Exact weapon requirement (old schema with int values)
	if u.has("requires_alt_weapon"):
		var req_weapon = u["requires_alt_weapon"]
		if typeof(req_weapon) == TYPE_INT and req_weapon != GameState.alt_weapon:
			return false

	# Legacy: Needs any ammo-using weapon (NOT turret)
	if u.get("requires_ammo_weapon", false):
		if GameState.alt_weapon == ALT_WEAPON_NONE or GameState.alt_weapon == ALT_WEAPON_TURRET:
			return false

	# Legacy: Ability must match (old schema with int values)
	if u.has("requires_ability"):
		var req_ability = u["requires_ability"]
		if typeof(req_ability) == TYPE_INT and GameState.ability != req_ability:
			return false

	# Legacy: Any ability required
	if u.get("requires_any_ability", false) and GameState.ability == ABILITY_NONE:
		return false

	return true

# -------------------------------------------------------------------
# UI REFRESH
# -------------------------------------------------------------------

func _refresh_from_state_full() -> void:
	_update_coin_label()
	_update_hp_from_state()
	_update_level_label()
	_update_ability_bar()
	_update_card_button_states()

func _update_coin_label() -> void:
	if not coin_label:
		return
	coin_label.text = str(GameState.coins)


func flash_coin_label_red() -> void:
	"""Flash the coin label red when buying items."""
	if not coin_label:
		return
	
	# Kill any existing tween
	var existing_tween = coin_label.get_meta("flash_tween", null)
	if existing_tween and existing_tween is Tween:
		existing_tween.kill()
	
	var tween := create_tween()
	coin_label.set_meta("flash_tween", tween)
	
	# Flash red then back to white
	tween.tween_property(coin_label, "modulate", Color(1.0, 0.2, 0.2), 0.1)
	tween.tween_property(coin_label, "modulate", Color.WHITE, 0.2)

func _update_hp_from_state() -> void:
	if not hp_progress_bar:
		return
	hp_progress_bar.max_value = GameState.max_health
	hp_progress_bar.value = GameState.health
	
	# Update HP label with current/max format
	if hp_label:
		hp_label.text = "%d/%d" % [GameState.health, GameState.max_health]

# REMOVED: _update_ammo_from_state() - fuel system handles this

func _update_level_label() -> void:
	if not level_label:
		return
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and "current_level" in gm:
		level_label.text = str(gm.current_level)

func _update_card_button_states() -> void:
	for card in cards_container.get_children():
		if card.has_method("_update_button_state"):
			card._update_button_state()

func _update_ability_bar() -> void:
	# Check if node exists
	if not ability_progress_bar:
		return
	
	# Hide if no ability unlocked
	if GameState.ability == ABILITY_NONE:
		ability_progress_bar.visible = false
		if ability_label:
			ability_label.visible = false
		return
	
	var data = GameState.ABILITY_DATA.get(GameState.ability, {})
	if data.is_empty():
		ability_progress_bar.visible = false
		if ability_label:
			ability_label.visible = false
		return
	
	# Apply cooldown multiplier (from upgrades)
	var base_cd: float = data.get("cooldown", 0.0)
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	var actual_max_cd: float = base_cd * multiplier
	ability_progress_bar.max_value = actual_max_cd
	var cd_left: float = GameState.ability_cooldown_left
	var bar_value: float = actual_max_cd - cd_left
	ability_progress_bar.value = bar_value
	
	# Update ability cooldown label
	if ability_label:
		ability_label.visible = true
		if cd_left > 0.0:
			ability_label.text = "%.1f/%.1f" % [cd_left, actual_max_cd]
		else:
			ability_label.text = "READY"

# -------------------------------------------------------------------
# SIGNALS
# -------------------------------------------------------------------

func _on_card_purchased() -> void:
	# Skip refresh if in chest mode (chest has its own handler)
	if is_chest_mode:
		return
	
	# Flash coin label red when spending money
	flash_coin_label_red()
	
	_refresh_from_state_full()
	# Refresh all cards to update prices and dynamic text
	var purchased_card_id = null
	# Find the purchased card (the one with disabled button after purchase)
	for card in cards_container.get_children():
		if card.visible and card.has_method("setup") and card.buy_button and card.buy_button.disabled:
			purchased_card_id = card.upgrade_id
			break
	for card in cards_container.get_children():
		if card.visible and card.has_method("setup"):
			var upgrade_data := UpgradesDB.get_by_id(card.upgrade_id)
			if not upgrade_data.is_empty():
				var upgrade_copy = upgrade_data.duplicate()
				var calculated_price = _calculate_upgrade_price(upgrade_copy)
				upgrade_copy["price"] = calculated_price
				var flash = (card.upgrade_id == purchased_card_id)
				card.setup(upgrade_copy)
	_update_card_button_states()

func _on_continue_pressed() -> void:
	# Only allow continue in normal shop mode, not chest mode
	if is_chest_mode:
		return
	
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("load_next_level"):
		gm.load_next_level()

func refresh_from_state() -> void:
	_refresh_from_state_full()


# -------------------------------------------------------------------
# CARD ANIMATION
# -------------------------------------------------------------------

func _animate_cards_in() -> void:
	"""Quick fade in animation: center -> middle -> outer."""
	var cards := cards_container.get_children()
	
	# Start all cards invisible
	for card in cards:
		if not card.visible:
			continue
		
		var visual_root = card.get_node_or_null("VisualRoot")
		if not visual_root:
			continue
			
		visual_root.modulate.a = 0.0
	
	# Animate cards from center outward: 2 -> (1,3) -> (0,4)
	var animation_groups = [
		{"indices": [2], "delay": 0.0},      # Card 2 (center)
		{"indices": [1, 3], "delay": 0.1},   # Cards 1 & 3
		{"indices": [0, 4], "delay": 0.2}    # Cards 0 & 4
	]
	
	for group in animation_groups:
		for card_index in group["indices"]:
			if card_index >= cards.size():
				continue
			
			var card = cards[card_index]
			if not card.visible:
				continue
			
			var visual_root = card.get_node_or_null("VisualRoot")
			if not visual_root:
				continue
			
			var tween := create_tween()
			tween.tween_property(visual_root, "modulate:a", 1.0, 0.3).set_delay(group["delay"])


# -------------------------------------------------------------------
# SHOP OPENING (NORMAL MODE)
# -------------------------------------------------------------------

func open_as_shop() -> void:
	"""Open shop in normal mode (via door)."""
	# Ensure chest mode is OFF
	is_chest_mode = false
	active_chest = null
	
	# Make sure all UI elements are visible
	var coin_ui = get_node_or_null("Coins")
	if coin_ui:
		coin_ui.visible = true
	
	var hp_ui = get_node_or_null("PlayerInfo")
	if hp_ui:
		hp_ui.visible = true
	
	var ammo_ui = get_node_or_null("Ammo")
	if ammo_ui:
		ammo_ui.visible = true
	
	var level_ui = get_node_or_null("Level")
	if level_ui:
		level_ui.visible = true
	
	var title_label = get_node_or_null("Panel/TitleLabel")
	if title_label:
		title_label.visible = true
	
	if continue_button:
		continue_button.visible = true
	
	# Setup normal shop cards
	_setup_cards()
	_refresh_from_state_full()
	
	# Animate cards in
	call_deferred("_animate_cards_in")


# -------------------------------------------------------------------
# CHEST MODE
# -------------------------------------------------------------------

func open_as_chest(chest: Node2D = null) -> void:
	"""Open shop in chest mode with free upgrades."""
	is_chest_mode = true
	active_chest = chest
	
	# Pause game
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Show shop
	visible = true
	
	# Hide UI elements
	var coin_ui = get_node_or_null("CoinUI")
	if coin_ui:
		coin_ui.visible = false
	
	var hp_bar = get_node_or_null("HPBar")
	if hp_bar:
		hp_bar.visible = false
	
	var ammo_ui = get_node_or_null("AmmoUI")
	if ammo_ui:
		ammo_ui.visible = false
	
	var level_ui = get_node_or_null("LevelUI")
	if level_ui:
		level_ui.visible = false
	
	if ability_progress_bar:
		ability_progress_bar.visible = false
	
	var title_label = get_node_or_null("Panel/TitleLabel")
	if title_label:
		title_label.visible = false
	
	if continue_button:
		continue_button.visible = false
	
	# Setup chest cards
	_setup_chest_cards()
	
	# Animate cards in
	call_deferred("_animate_cards_in")


func open_as_chest_with_loot(loot: Array) -> void:
	"""Open shop in chest mode with predefined loot from chest."""
	is_chest_mode = true
	active_chest = null
	
	# Pause game
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Show shop
	visible = true
	
	# Hide UI elements
	var coin_ui = get_node_or_null("Coins")
	if coin_ui:
		coin_ui.visible = false
	
	var hp_ui = get_node_or_null("PlayerInfo")
	if hp_ui:
		hp_ui.visible = false
	
	var ammo_ui = get_node_or_null("Ammo")
	if ammo_ui:
		ammo_ui.visible = false
	
	var level_ui = get_node_or_null("Level")
	if level_ui:
		level_ui.visible = false
	
	if ability_progress_bar:
		ability_progress_bar.visible = false
	
	var title_label = get_node_or_null("Panel/TitleLabel")
	if title_label:
		title_label.visible = false
	
	if continue_button:
		continue_button.visible = false
	
	# Setup cards with predefined loot
	_setup_chest_cards_with_loot(loot)
	
	# Animate cards in
	call_deferred("_animate_cards_in")


func _setup_chest_cards() -> void:
	"""Generate 5 free upgrades with chest rarity weights."""
	var children := cards_container.get_children()
	
	# ⭐ FORCE RESET: Set ALL cards to full opacity FIRST (prevents transparency bugs)
	for card in children:
		card.modulate = Color(1, 1, 1, 1)
		card.visible = true
		card.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Disconnect old signals
	for card in children:
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)
		if card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.disconnect(_on_chest_card_purchased)
	
	var chest_weights := _get_chest_rarity_weights()
	var all_upgrades: Array = UpgradesDB.get_all()
	var taken_ids: Array[String] = []
	var taken_bases := {}
	var offers: Array = []
	
	# Generate 5 upgrades
	for i in range(5):
		var rarity := _roll_rarity(chest_weights)
		var candidates := _filter_upgrades(all_upgrades, rarity, taken_ids, taken_bases)
		
		# Fallback: any rarity if we ran out
		if candidates.is_empty():
			candidates = _filter_upgrades(all_upgrades, -1, taken_ids, taken_bases)
		if candidates.is_empty():
			break
		
		candidates.shuffle()
		
		# Pick first candidate (already filtered by _filter_upgrades to exclude taken bases)
		var chosen: Dictionary = candidates[0]
		offers.append(chosen)
		taken_ids.append(chosen["id"])
		var base_chosen := _get_base_upgrade_id(chosen)
		taken_bases[base_chosen] = true
	
	# Sort by rarity
	offers = _sort_offers_by_rarity(offers)
	
	# Assign to positions: center (2), middle (1,3), outer (0,4)
	var position_order = [2, 1, 3, 0, 4]
	# Reuse children array from above
	var used_positions = []  # Track which positions we've used
	
	for i in range(position_order.size()):
		if i >= offers.size():
			break
		
		var position = position_order[i]
		if position >= children.size():
			continue
		
		var card = children[position]
		card.visible = true
		card.modulate = Color(1, 1, 1, 1)
		
		# Make a copy and set price to 0 for chest mode
		var upgrade_data = offers[i].duplicate()
		upgrade_data["price"] = 0
		card.setup(upgrade_data)
		
		if not card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.connect(_on_chest_card_purchased)
		
		used_positions.append(position)
	
	# Hide unused cards
	for i in range(children.size()):
		if i not in used_positions:
			children[i].visible = false


func _setup_chest_cards_with_loot(loot: Array) -> void:
	"""Setup cards with predefined loot from chest (rarity-based)."""
	# ⭐ FORCE RESET: Set ALL cards to full opacity FIRST (prevents transparency bugs)
	var children := cards_container.get_children()
	for card in children:
		card.modulate = Color(1, 1, 1, 1)
		card.visible = true
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		# Root card scale stays at ONE - VisualRoot handles scaling
		# ⭐ Also restore child visibility (was hidden for single-card mode)
		for child in card.get_children():
			# Restore all except: TooltipLabel (temporary), ColorRect (hidden by design)
			if child is CanvasItem and child.name != "TooltipLabel" and child.name != "ColorRect":
				child.visible = true
	
	# Disconnect old signals
	for card in children:
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)
		if card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.disconnect(_on_chest_card_purchased)
	
	# Sort loot by rarity
	var sorted_loot = _sort_offers_by_rarity(loot)
	
	# Reuse children array from above
	
	# Special case: if only 1 item (like chaos chest), center it by making side cards invisible
	if sorted_loot.size() == 1:
		# Make all cards visible but transparent except the center one
		for i in range(children.size()):
			var card = children[i]
			card.visible = true
			
			if i == 2:  # Center card - show the chaos upgrade
				card.modulate = Color(1, 1, 1, 1)
				card.mouse_filter = Control.MOUSE_FILTER_STOP
				
				var upgrade_data = sorted_loot[0].duplicate()
				upgrade_data["price"] = 0
				card.setup(upgrade_data)
				
				if not card.purchased.is_connected(_on_chest_card_purchased):
					card.purchased.connect(_on_chest_card_purchased)
			else:  # Side cards - make completely transparent and non-interactive
				card.modulate = Color(1, 1, 1, 0)  # Completely transparent
				card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse
				
				# Also hide all child nodes to ensure nothing shows
				for child in card.get_children():
					if child is CanvasItem:
						child.visible = false
		return
	
	# Normal multi-card logic
	# Assign to positions: center (2), middle (1,3), outer (0,4)
	var position_order = [2, 1, 3, 0, 4]
	var used_positions = []
	
	for i in range(position_order.size()):
		if i >= sorted_loot.size():
			break
		
		var position = position_order[i]
		if position >= children.size():
			continue
		
		var card = children[position]
		card.visible = true
		card.modulate = Color(1, 1, 1, 1)
		
		# Make a copy and set price to 0 for chest mode
		var upgrade_data = sorted_loot[i].duplicate()
		upgrade_data["price"] = 0
		card.setup(upgrade_data)
		
		if not card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.connect(_on_chest_card_purchased)
		
		used_positions.append(position)
	
	# Hide unused cards
	for i in range(children.size()):
		if i not in used_positions:
			children[i].visible = false


func _get_chest_rarity_weights() -> Dictionary:
	"""Return chest-specific rarity weights (no commons)."""
	return {
		UpgradesDB.Rarity.COMMON: 0.0,
		UpgradesDB.Rarity.UNCOMMON: 0.6,
		UpgradesDB.Rarity.RARE: 0.3,
		UpgradesDB.Rarity.EPIC: 0.1,
		UpgradesDB.Rarity.SYNERGY: 0.05,
	}


func _on_chest_card_purchased() -> void:
	"""Handle chest card purchase (free upgrade)."""
	# Upgrade is already applied by card script
	
	# Close chest mode first
	_close_chest_mode()
	
	# Despawn the chest with SFX
	if active_chest and is_instance_valid(active_chest):
		# Play despawn sound if available
		var sfx_despawn = active_chest.get_node_or_null("SFX_Despawn")
		if sfx_despawn:
			sfx_despawn.play()
		
		# Hide all visuals immediately
		var sprite = active_chest.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
		
		var collision = active_chest.get_node_or_null("CollisionShape2D")
		if collision:
			collision.set_deferred("disabled", true)
		
		var prompt = active_chest.get_node_or_null("InteractPrompt")
		if prompt:
			prompt.visible = false
		
		var light = active_chest.get_node_or_null("PointLight2D")
		if light:
			light.visible = false
		
		# Queue free after a short delay to let sound play
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(active_chest):
			active_chest.queue_free()
		active_chest = null


func _close_chest_mode() -> void:
	"""Close chest mode and restore normal UI."""
	is_chest_mode = false
	
	# ⭐ Reset all cards to default state to prevent chaos/single-card state from persisting
	_reset_all_cards()
	
	# Hide shop
	visible = false
	
	# Unpause game
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# Show UI elements again
	var coin_ui = get_node_or_null("Coins")
	if coin_ui:
		coin_ui.visible = true
	
	var hp_ui = get_node_or_null("PlayerInfo")
	if hp_ui:
		hp_ui.visible = true
	
	var ammo_ui = get_node_or_null("Ammo")
	if ammo_ui:
		ammo_ui.visible = true
	
	var level_ui = get_node_or_null("Level")
	if level_ui:
		level_ui.visible = true
	
	# Ability bar visibility is handled by _update_ability_bar()


func _reset_all_cards() -> void:
	"""Reset all cards to default visible state (fixes chaos chest leaving cards invisible)."""
	var children := cards_container.get_children()
	
	for card in children:
		# Reset visibility and opacity
		card.visible = true
		card.modulate = Color(1, 1, 1, 1)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		# Root card scale stays at ONE - VisualRoot handles scaling
		
		# Remove any tooltips
		var tooltip = card.get_node_or_null("TooltipLabel")
		if tooltip:
			tooltip.queue_free()
		
		# Make all child nodes visible again
		for child in card.get_children():
			if child is CanvasItem and child.name != "TooltipLabel":
				child.visible = true
		
		# Disconnect any existing signals
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)
		if card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.disconnect(_on_chest_card_purchased)
	
	var title_label = get_node_or_null("Panel/TitleLabel")
	if title_label:
		title_label.visible = true
	
	if continue_button:
		continue_button.visible = true

# IMPLEMENT CHEST MODE:
# 
# Add variable at top:
# - is_chest_mode: bool = false
# 
# Add new function: open_as_chest()
# - Set is_chest_mode to true
# - Pause game (get_tree().paused = true)
# - Show mouse cursor (Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE))
# - Make ShopUI visible
# - Hide all UI EXCEPT Panel/Cards:
#   - Hide CoinUI
#   - Hide HPBar  
#   - Hide AmmoUI
#   - Hide LevelUI
#   - Hide AbilityBar
#   - Hide Panel/TitleLabel
#   - Hide Panel/ContinueButton
# - Generate 3 chest upgrades with custom rarity weights:
#   - 60% Uncommon
#   - 30% Rare  
#   - 10% Epic
# - Show only 3 cards (hide cards 4 and 5)
# - Make cards show NO PRICE (set price to 0 or hide price label)
# - When card is purchased, call _close_chest_mode() instead of normal flow
# 
# Add new function: _close_chest_mode()
# - Set is_chest_mode back to false
# - Hide ShopUI (visible = false)
# - Unpause game (get_tree().paused = false)
# - Hide mouse cursor (Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN))
# - Show all normal UI elements again
# 
# Modify _setup_cards() to handle chest mode:
# - If is_chest_mode, use 3 cards with chest rarity weights
# - If normal mode, use 5 cards with normal rarity weights
# 
# Modify upgrade_card purchase signal:
# - After purchase in chest mode, call _close_chest_mode()
# - In normal mode, use existing logic


# --------------------------------------------------------------------
# SIGNAL HANDLERS (matching ui.gd)
# --------------------------------------------------------------------

func _on_coins_changed(_new_value: int) -> void:
	_update_coin_label()

func _on_health_changed(_new_value: int, _max_value: int) -> void:
	_update_hp_from_state()
