extends CanvasLayer

##
## ShopUI.gd
## Pulls upgrades from UpgradesDB, rolls rarities,
## shows 5 cards, and applies upgrades via GameState.
##

const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_TURRET := 3
const ALT_WEAPON_FLAMETHROWER := 4
const ALT_WEAPON_SHURIKEN := 5
const ALT_WEAPON_GRENADE := 6

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2
const ABILITY_BUBBLE := 3
const ABILITY_INVIS := 4

@onready var continue_button       := $Panel/ContinueButton
@onready var cards_container       := $Panel/Cards
@onready var coin_label: Label     =  $CoinUI/CoinLabel

@onready var hp_fill: TextureProgressBar = $HPBar/HPFill
@onready var hp_label: Label             = $HPBar/HPLabel

@onready var ammo_label: Label           = $AmmoUI/AmmoLabel
@onready var level_label: Label          = $LevelUI/LevelLabel

@onready var ability_bar_container: Control      = $AbilityBar
@onready var ability_bar: TextureProgressBar     = $AbilityBar/AbilityFill
@onready var ability_label: Label                = $AbilityBar/AbilityLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	if gm and gm.has_method("debug_set_level"):
		current_level = gm.current_level

	var rarity_weights := _get_rarity_weights_for_level(current_level)
	var all_upgrades: Array = UpgradesDB.get_all()

	var max_cards = min(5, cards_container.get_child_count())

	for i in range(max_cards):
		var rarity := _roll_rarity(rarity_weights)
		var candidates := _filter_upgrades(all_upgrades, rarity, taken_ids)

		# Fallback: any rarity if we ran out for this tier
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
	# Base distribution
	var common := 60.0
	var uncommon := 30.0
	var rare := 9.0
	var epic := 1.0

	# Every 5 levels, shift a bit towards higher rarities
	var tiers = max(0, int((level - 1) / 5))
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


func _roll_rarity(weights: Dictionary) -> int:
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

		res.append(u)

	return res


func _upgrade_meets_requirements(u: Dictionary) -> bool:
	# Exact weapon requirement
	if u.has("requires_alt_weapon") and u["requires_alt_weapon"] != GameState.alt_weapon:
		return false

	# Needs any ammo-using weapon (NOT turret, since that fires automatically)
	if u.get("requires_ammo_weapon", false):
		if GameState.alt_weapon == ALT_WEAPON_NONE or GameState.alt_weapon == ALT_WEAPON_TURRET:
			return false

	# Ability must be NONE
	if u.has("requires_ability") and GameState.ability != u["requires_ability"]:
		return false

	# Any ability required
	if u.get("requires_any_ability", false) and GameState.ability == ABILITY_NONE:
		return false

	return true


# -------------------------------------------------------------------
# UI REFRESH HELPERS
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
	var gs = GameState
	hp_fill.max_value = gs.max_health
	hp_fill.value = gs.health
	hp_label.text = "%d/%d" % [gs.health, gs.max_health]


func _update_ammo_from_state() -> void:
	var gs = GameState
	if gs.max_ammo <= 0:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [gs.ammo, gs.max_ammo]


func _update_level_label() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm:
		level_label.text = str(gm.current_level)


func _update_card_button_states() -> void:
	for card in cards_container.get_children():
		if card.has_method("_update_button_state"):
			card._update_button_state()


# --- Ability bar (same logic as main HUD) ---------------------------

func _update_ability_bar() -> void:
	var gs = GameState

	if gs.ability == ABILITY_NONE:
		ability_bar_container.visible = false
		return

	var data = gs.ABILITY_DATA.get(gs.ability, {})
	if data.is_empty():
		ability_bar_container.visible = false
		return

	var max_cd: float = data.get("cooldown", 0.0)
	if max_cd <= 0.0:
		ability_bar_container.visible = false
		return

	ability_bar_container.visible = true

	var cd_left: float = gs.ability_cooldown_left
	ability_bar.max_value = max_cd
	ability_bar.value = max_cd - cd_left

	if ability_label:
		var remaining = round(cd_left * 10.0) / 10.0
		var max_display = round(max_cd * 10.0) / 10.0
		ability_label.text = "%s / %s s" % [remaining, max_display]


# -------------------------------------------------------------------
# SIGNALS
# -------------------------------------------------------------------

func _on_card_purchased() -> void:
	# Shop card applied an upgrade (via GameState) → refresh everything
	_refresh_from_state_full()
	_update_card_button_states()


func _on_continue_pressed() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("load_next_level"):
		gm.load_next_level()


# Called by GameManager when shop opens
func refresh_from_state() -> void:
	_refresh_from_state_full()
