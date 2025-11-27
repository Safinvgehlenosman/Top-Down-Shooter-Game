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
const ALT_WEAPON_FLAMETHROWER = GameState.AltWeaponType.FLAMETHROWER
const ALT_WEAPON_SHURIKEN = GameState.AltWeaponType.SHURIKEN
const ALT_WEAPON_GRENADE = GameState.AltWeaponType.GRENADE

const ABILITY_NONE = GameState.AbilityType.NONE
const ABILITY_DASH = GameState.AbilityType.DASH
const ABILITY_SLOWMO = GameState.AbilityType.SLOWMO
const ABILITY_BUBBLE = GameState.AbilityType.BUBBLE
const ABILITY_INVIS = GameState.AbilityType.INVIS

@onready var continue_button := $Panel/ContinueButton
@onready var cards_container := $Panel/Cards
@onready var coin_label: Label = $CoinUI/CoinLabel

# Chest mode flag
var is_chest_mode: bool = false
var active_chest: Node2D = null  # Reference to the chest that opened this shop

@onready var hp_fill: TextureProgressBar = $HPBar/HPFill
@onready var hp_label: Label = $HPBar/HPLabel

@onready var ammo_label: Label = $AmmoUI/AmmoLabel
@onready var level_label: Label = $LevelUI/LevelLabel

# ✅ FIXED: AbilityBar is at ROOT level, not under Panel!
@onready var ability_bar_container: Control = $AbilityBar
@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill
@onready var ability_label: Label = $AbilityBar/AbilityLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Always start hidden
	if ability_bar_container:
		ability_bar_container.visible = false

	_setup_cards()
	_refresh_from_state_full()

	continue_button.pressed.connect(_on_continue_pressed)

# -------------------------------------------------------------------
# CARD SETUP
# -------------------------------------------------------------------

func _setup_cards() -> void:
	# Disconnect old signals
	for card in cards_container.get_children():
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)

	var offers := _roll_shop_offers()

	var children := cards_container.get_children()
	for i in range(children.size()):
		var card = children[i]
		if i < offers.size():
			card.visible = true
			card.setup(offers[i])
			if not card.purchased.is_connected(_on_card_purchased):
				card.purchased.connect(_on_card_purchased)
		else:
			card.visible = false

func _roll_shop_offers() -> Array:
	var result: Array = []
	var taken_ids: Array[String] = []

	var gm := get_tree().get_first_node_in_group("game_manager")
	var current_level := 1
	if gm and "current_level" in gm:
		current_level = gm.current_level

	var rarity_weights := _get_rarity_weights_for_level(current_level)
	var all_upgrades: Array = preload("res://scripts/Upgrades_DB.gd").get_all()

	var max_cards = min(5, cards_container.get_child_count())

	for i in range(max_cards):
		var rarity := _roll_rarity(rarity_weights)
		var candidates := _filter_upgrades(all_upgrades, rarity, taken_ids)

		# Fallback: any rarity if we ran out
		if candidates.is_empty():
			candidates = _filter_upgrades(all_upgrades, -1, taken_ids)
		if candidates.is_empty():
			break

		candidates.shuffle()
		var chosen = candidates[0]
		result.append(chosen)
		taken_ids.append(chosen["id"])

	return result

func _get_rarity_weights_for_level(level: int) -> Dictionary:
	var common := 60.0
	var uncommon := 30.0
	var rare := 9.0
	var epic := 1.0

	var tiers = max(0, int((level - 1) / 5.0))
	for i in range(tiers):
		common = max(20.0, common - 5.0)
		uncommon += 3.0
		rare += 1.0
		epic += 1.0

	var total := common + uncommon + rare + epic
	if total <= 0.0:
		return {
			UpgradesDB.Rarity.COMMON: 1.0,
			UpgradesDB.Rarity.UNCOMMON: 0.0,
			UpgradesDB.Rarity.RARE: 0.0,
			UpgradesDB.Rarity.EPIC: 0.0,
		}

	return {
		UpgradesDB.Rarity.COMMON: common / total,
		UpgradesDB.Rarity.UNCOMMON: uncommon / total,
		UpgradesDB.Rarity.RARE: rare / total,
		UpgradesDB.Rarity.EPIC: epic / total,
	}

func _roll_rarity(weights: Dictionary = {}) -> int:
	# Use provided weights or default to level-based weights
	if weights.is_empty():
		var gm := get_tree().get_first_node_in_group("game_manager")
		var current_level := 1
		if gm and "current_level" in gm:
			current_level = gm.current_level
		weights = _get_rarity_weights_for_level(current_level)
	
	var r := randf()
	var acc := 0.0

	for rarity in [UpgradesDB.Rarity.COMMON, UpgradesDB.Rarity.UNCOMMON, UpgradesDB.Rarity.RARE, UpgradesDB.Rarity.EPIC]:
		acc += float(weights.get(rarity, 0.0))
		if r <= acc:
			return rarity

	return UpgradesDB.Rarity.COMMON

func _filter_upgrades(all_upgrades: Array, wanted_rarity: int, taken_ids: Array[String]) -> Array:
	var res: Array = []

	for u in all_upgrades:
		var id: String = u.get("id", "")
		if id == "" or id in taken_ids:
			continue

		if wanted_rarity != -1 and u.get("rarity", UpgradesDB.Rarity.COMMON) != wanted_rarity:
			continue

		if not _upgrade_meets_requirements(u):
			continue

		# Skip non-stackable upgrades that the player already owns
		var stackable := bool(u.get("stackable", true))
		if not stackable and GameState.has_upgrade(id):
			continue

		res.append(u)

	return res

func _upgrade_meets_requirements(u: Dictionary) -> bool:
	# Exact weapon requirement
	if u.has("requires_alt_weapon") and u["requires_alt_weapon"] != GameState.alt_weapon:
		return false

	# Needs any ammo-using weapon (NOT turret)
	if u.get("requires_ammo_weapon", false):
		if GameState.alt_weapon == ALT_WEAPON_NONE or GameState.alt_weapon == ALT_WEAPON_TURRET:
			return false

	# Ability must match
	if u.has("requires_ability") and GameState.ability != u["requires_ability"]:
		return false

	# Any ability required
	if u.get("requires_any_ability", false) and GameState.ability == ABILITY_NONE:
		return false

	return true

# -------------------------------------------------------------------
# UI REFRESH
# -------------------------------------------------------------------

func _refresh_from_state_full() -> void:
	_update_coin_label()
	_update_hp_from_state()
	_update_ammo_from_state()
	_update_level_label()
	_update_ability_bar()
	_update_card_button_states()

func _update_coin_label() -> void:
	coin_label.text = str(GameState.coins)

func _update_hp_from_state() -> void:
	hp_fill.max_value = GameState.max_health
	hp_fill.value = GameState.health
	hp_label.text = "%d/%d" % [GameState.health, GameState.max_health]

func _update_ammo_from_state() -> void:
	# Display ammo only for ammo-using alt weapons; show "-/-" for NONE or TURRET
	if GameState.alt_weapon == ALT_WEAPON_NONE or GameState.alt_weapon == ALT_WEAPON_TURRET:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [GameState.ammo, GameState.max_ammo]

func _update_level_label() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and "current_level" in gm:
		level_label.text = str(gm.current_level)

func _update_card_button_states() -> void:
	for card in cards_container.get_children():
		if card.has_method("_update_button_state"):
			card._update_button_state()

func _update_ability_bar() -> void:
	# Check if nodes exist
	if not ability_bar_container or not ability_bar:
		return
	
	# Hide if no ability unlocked
	if GameState.ability == ABILITY_NONE:
		ability_bar_container.visible = false
		return
	
	var data = GameState.ABILITY_DATA.get(GameState.ability, {})
	if data.is_empty():
		ability_bar_container.visible = false
		return
	
	# Get BASE cooldown
	var base_cd: float = data.get("cooldown", 0.0)
	if base_cd <= 0.0:
		ability_bar_container.visible = false
		return
	
	# Apply cooldown multiplier (from upgrades)
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	
	# Actual cooldown after upgrades
	var actual_max_cd: float = base_cd * multiplier
	
	# Show the bar (ability is unlocked)
	ability_bar_container.visible = true
	
	# Bar fills as cooldown recovers
	ability_bar.max_value = actual_max_cd
	var cd_left: float = GameState.ability_cooldown_left
	var bar_value: float = actual_max_cd - cd_left
	ability_bar.value = bar_value
	
	# Show time remaining
	if ability_label:
		var remaining = round(GameState.ability_cooldown_left * 10.0) / 10.0
		var max_display = round(actual_max_cd * 10.0) / 10.0
		ability_label.text = "%s / %s s" % [remaining, max_display]

# -------------------------------------------------------------------
# SIGNALS
# -------------------------------------------------------------------

func _on_card_purchased() -> void:
	# Skip refresh if in chest mode (chest has its own handler)
	if is_chest_mode:
		return
	
	_refresh_from_state_full()
	# Refresh all cards to update prices and dynamic text
	for card in cards_container.get_children():
		if card.visible and card.has_method("setup"):
			# Get the upgrade data again and refresh
			var upgrade_data := preload("res://scripts/Upgrades_DB.gd").get_by_id(card.upgrade_id)
			if not upgrade_data.is_empty():
				card.setup(upgrade_data)
	_update_card_button_states()

func _on_continue_pressed() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("load_next_level"):
		gm.load_next_level()

func refresh_from_state() -> void:
	_refresh_from_state_full()


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
	
	if ability_bar_container:
		ability_bar_container.visible = false
	
	var title_label = get_node_or_null("Panel/TitleLabel")
	if title_label:
		title_label.visible = false
	
	if continue_button:
		continue_button.visible = false
	
	# Setup chest cards
	_setup_chest_cards()


func _setup_chest_cards() -> void:
	"""Generate 3 free upgrades with chest rarity weights."""
	# Disconnect old signals
	for card in cards_container.get_children():
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)
		if card.purchased.is_connected(_on_chest_card_purchased):
			card.purchased.disconnect(_on_chest_card_purchased)
	
	var chest_weights := _get_chest_rarity_weights()
	var all_upgrades: Array = preload("res://scripts/Upgrades_DB.gd").get_all()
	var taken_ids: Array[String] = []
	var offers: Array = []
	
	# Generate 3 upgrades
	for i in range(3):
		var rarity := _roll_rarity(chest_weights)
		var candidates := _filter_upgrades(all_upgrades, rarity, taken_ids)
		
		# Fallback: any rarity if we ran out
		if candidates.is_empty():
			candidates = _filter_upgrades(all_upgrades, -1, taken_ids)
		if candidates.is_empty():
			break
		
		candidates.shuffle()
		var chosen = candidates[0]
		offers.append(chosen)
		taken_ids.append(chosen["id"])
	
	# Setup cards - use middle 3 slots (indices 1, 2, 3) with spacers
	var children := cards_container.get_children()
	for i in range(children.size()):
		var card = children[i]
		# Show cards at positions 1, 2, 3 (middle three)
		if i >= 1 and i <= 3:
			var offer_index = i - 1  # Map card index to offer array (1->0, 2->1, 3->2)
			if offer_index < offers.size():
				card.visible = true
				# Make a copy and set price to 0 for chest mode
				var upgrade_data = offers[offer_index].duplicate()
				upgrade_data["price"] = 0
				card.setup(upgrade_data)
				if not card.purchased.is_connected(_on_chest_card_purchased):
					card.purchased.connect(_on_chest_card_purchased)
			else:
				card.visible = false
		else:
			# Keep spacer cards visible but make them transparent to center the layout
			card.visible = true
			card.modulate = Color(1, 1, 1, 0)  # Fully transparent


func _get_chest_rarity_weights() -> Dictionary:
	"""Return chest-specific rarity weights (no commons)."""
	return {
		UpgradesDB.Rarity.COMMON: 0.0,
		UpgradesDB.Rarity.UNCOMMON: 0.6,
		UpgradesDB.Rarity.RARE: 0.3,
		UpgradesDB.Rarity.EPIC: 0.1,
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
	
	# Hide shop
	visible = false
	
	# Unpause game
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# Show UI elements again
	var coin_ui = get_node_or_null("CoinUI")
	if coin_ui:
		coin_ui.visible = true
	
	var hp_bar = get_node_or_null("HPBar")
	if hp_bar:
		hp_bar.visible = true
	
	var ammo_ui = get_node_or_null("AmmoUI")
	if ammo_ui:
		ammo_ui.visible = true
	
	var level_ui = get_node_or_null("LevelUI")
	if level_ui:
		level_ui.visible = true
	
	# Ability bar visibility is handled by _update_ability_bar()
	
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