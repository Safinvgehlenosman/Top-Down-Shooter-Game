# 🎮 Roguelike Top-Down Shooter

A fast-paced pixel-art roguelike shooter built in **Godot 4.x** with **GDScript**.  
Fight through procedurally generated rooms, upgrade your arsenal, and survive as long as you can!

[![Gameplay Demo](https://img.shields.io/badge/▶️-Watch%20Demo-red?style=for-the-badge)](https://www.youtube.com/watch?v=cosuupup1mU)

---

## ✨ Features

### 🎯 Core Gameplay
- **Smooth player movement** with mouse/controller aiming
- **Multiple weapon systems:**
  - Primary weapon (pistol) with burst fire upgrades
  - 6 alternate weapons: Shotgun, Sniper, Flamethrower, Grenade Launcher, Shuriken, Turret Backpack
- **Procedural level generation** - every run is unique
- **Exit door system** - clear all enemies to progress to the next level
- **Smooth fade transitions** between levels

### 👾 Enemy Variety
- **7 unique enemy types** with different behaviors:
  - **Green Slime** - Basic melee enemy
  - **Dark Green Slime** - Fast chaser
  - **Purple Slime** - Ranged shooter with line-of-sight
  - **Fire Slime** - Shoots burning projectile clouds
  - **Ice Slime** - Slows player with freezing projectiles
  - **Poison Slime** - DoT (damage over time) projectile clouds
  - **Ghost Slime** - Phases through walls, always chases, 1 HP but spooky
- **Dynamic enemy AI:**
  - Wandering, chasing, and aggro systems
  - Line-of-sight checks for ranged enemies
  - De-aggro behavior when losing sight of player
  - Enemies ignore invisible players
- **Level-based enemy scaling** - health and damage increase per level
- **Smart enemy spawning curve** - new enemy types unlock at specific levels

### 🛍️ Progression System
- **Shop between levels** with 30+ upgrades:
  - Health refills and max HP increases
  - Ammo refills and max ammo increases
  - Primary weapon upgrades (damage, fire rate, burst shots)
  - Weapon unlocks (6 alternate weapons)
  - Ability unlocks (Dash, Bullet Time, Shield Bubble, Invisibility)
  - Ability cooldown reduction
- **Rarity-based card system** - Common, Uncommon, Rare, Epic upgrades
- **Dynamic shop pool** - cards adapt based on current loadout
- **Economy system** - earn coins from defeating enemies and breaking crates

### 🎨 Game Feel & Polish
- **Smooth camera system** with room transitions
- **Screen shake** on hits and explosions
- **Hit feedback:**
  - Red screen flash when damaged
  - Green screen flash when healed
  - Enemy sprite and lighting flash on hit
- **Knockback system** for player and enemies
- **Invincibility frames** with visual feedback
- **Pickup magnet system** - items fly towards the player
- **Floating "PRESS E" prompts** for interactive objects
- **Weapon-specific sound effects** with pitch variation
- **Empty magazine click sound**
- **Dynamic lighting system** with colored lights per enemy type

### ⚙️ Systems & Mechanics
- **Health component system** - supports burn, freeze, and poison status effects
- **Ability system** - 4 unique abilities with cooldowns:
  - **Dash** - Quick dodge with ghost trail effect
  - **Bullet Time** - Slow down time for precise shots
  - **Shield Bubble** - Blocks enemy projectiles and pushes enemies away
  - **Invisibility Cloak** - Enemies can't see you
- **Projectile variety:**
  - Bouncing bullets (Shuriken)
  - Explosive bullets (Grenade)
  - Area denial clouds (Fire/Ice/Poison)
  - Piercing bullets (Sniper)
- **Auto-targeting turret** with line-of-sight checks
- **Crate destruction** with health component and loot drops
- **Pause menu** with restart and quit options
- **Death screen** with slow-motion effect

### 🐛 Debug Tools
- **F1** - Open shop
- **F2** - Add 999 coins
- **F3** - Kill all enemies (spawn door)
- **F4** - Level select popup
- **F5** - Toggle god mode
- **F6** - Toggle infinite ammo
- **F7** - Toggle noclip
- **Shift+F8** - Laser mode (0 cooldown, massive damage)
- **F12** - Toggle debug overlay

---

## 🎯 Project Goals

This project demonstrates:
- ✅ Building complex game systems from scratch
- ✅ Structuring and maintaining clean, readable code
- ✅ Implementing procedural generation
- ✅ Creating responsive enemy AI with state machines
- ✅ Designing progression systems and economy balance
- ✅ Polishing game feel with visual and audio feedback
- ✅ Using Git for version control and documentation

---

## 📋 Project Planning

Development is tracked on Trello:
- [Main Task Board](https://trello.com/b/oc8C3eS6/shooter)
- [Feature Roadmap](https://trello.com/b/iZQbll1S/roadmap)

---

## 🕹️ Controls

### Keyboard & Mouse
- **Move:** WASD
- **Aim:** Mouse
- **Shoot (Primary):** Left Mouse Button
- **Shoot (Alt-Fire):** Right Mouse Button
- **Use Ability:** Space
- **Interact:** E
- **Pause:** ESC

---

## 📸 Screenshots

*(Screenshots coming soon - see [demo video](https://www.youtube.com/watch?v=cosuupup1mU) for now)*

### Core Gameplay
<p align="center">
  <img src="screenshots/gameplay.png" width="45%" />
  <img src="screenshots/turret.png" width="45%" />
</p>

*Left: Combat with multiple enemy types | Right: Turret backpack in action*

### Progression System
<p align="center">
  <img src="screenshots/shop.png" width="45%" />
  <img src="screenshots/chest.png" width="45%" />
</p>

*Left: Shop with upgrade cards | Right: Interactive chest with prompt*

### Weapons & Abilities
<p align="center">
  <img src="screenshots/flamethrower.png" width="45%" />
  <img src="screenshots/grenades.png" width="45%" />
</p>

<p align="center">
  <img src="screenshots/invisibility.png" width="45%" />
  <img src="screenshots/dash.png" width="45%" />
</p>

*Top: Flamethrower and Grenade Launcher | Bottom: Invisibility Cloak and Dash ability*

### Level Features
<p align="center">
  <img src="screenshots/door.png" width="45%" />
  <img src="screenshots/debug.png" width="45%" />
</p>

*Left: Exit door interaction | Right: Debug tools overlay*

---

## ▶️ How to Run

### Requirements
- **Godot Engine 4.5** or newer

### Steps
1. Clone this repository:
```bash
   git clone https://github.com/Safinvgehlenosman/Top-Down-Shooter-Game.git
```
2. Open **Godot Engine**
3. Click **Import**
4. Navigate to the cloned folder and select `project.godot`
5. Press **Play** (F5) to run the game

---

## 🛠️ Technical Details

### Engine & Language
- **Engine:** Godot 4.5
- **Language:** GDScript
- **Architecture:** Component-based with autoload singletons

### Key Systems
- **GameState** - Global run data (health, ammo, coins, upgrades)
- **GameConfig** - Centralized balance values
- **UpgradesDB** - All upgrade definitions and metadata
- **HealthComponent** - Reusable health/damage system with status effects
- **AbilityComponent** - Handles player abilities and cooldowns
- **Procedural Room Loading** - Spawns random rooms with no repeats

### Code Structure
```
scripts/
├── game_state.gd          # Global run state
├── game_config.gd         # Balance configuration
├── game_manager.gd        # Level loading & progression
├── Upgrades_DB.gd         # Upgrade definitions
├── player.gd              # Player controller
├── gun.gd                 # Weapon system
├── ability.gd             # Ability system
├── health_component.gd    # Damage/healing logic
├── slimes/
│   ├── base_slime.gd     # Base enemy AI
│   ├── purple_slime.gd   # Ranged shooter variant
│   ├── ghost_slime.gd    # Phase-through special enemy
│   └── ...
└── ui/
    ├── shop_ui.gd        # Shop interface
    ├── upgrade_card.gd   # Individual upgrade cards
    └── ...
```

---

## 🎨 Assets

- **Pixel Art:** Mix of custom edits and free assets
- **Sound Effects:** Placeholder sounds (to be replaced with original/licensed)
- **Font:** Pixel font for UI

---

## 🚀 Future Plans

- [ ] More enemy types and boss fights
- [ ] Additional weapons and abilities
- [ ] Meta-progression (permanent upgrades between runs)
- [ ] Achievements system
- [ ] Leaderboard/high score tracking
- [ ] Original soundtrack and sound design
- [ ] Steam release (long-term goal)

---

## 👤 About

**Developer:** Safin van Gehlen  
**Project Duration:** Started November 17, 2025 (ongoing)  
**Daily Development:** 8-10 hours/day

This is a solo learning project to demonstrate game development skills and passion for creating engaging gameplay experiences.

---

## 📝 License

This project is currently **not licensed for redistribution or commercial use**.  
Code may be viewed for educational purposes.

---

## 🔗 Links

- 🎥 [Gameplay Demo Video](https://www.youtube.com/watch?v=cosuupup1mU)
- 📋 [Development Trello Board](https://trello.com/b/oc8C3eS6/shooter)
- 🗺️ [Feature Roadmap](https://trello.com/b/iZQbll1S/roadmap)

---
