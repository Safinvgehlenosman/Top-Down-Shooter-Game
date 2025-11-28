🎮 Roguelike Top-Down Shooter

A fast-paced pixel-art roguelike shooter built in Godot 4.x with GDScript.

Fight through procedurally generated rooms, upgrade your arsenal, and survive as long as you can!

✨ Features
🎯 Core Gameplay

Smooth player movement with mouse or controller aiming

Multiple weapon systems:

Primary pistol with burst-fire upgrades

6 alternate weapons: Shotgun, Sniper, Flamethrower, Grenade Launcher, Shuriken, Turret Backpack

Procedurally generated levels — every run is unique

Exit-door progression system

Smooth level transition fades

👾 Enemy Variety

7 unique enemy types, each with different AI behaviors:

Green Slime — Basic melee

Dark Green Slime — Fast chaser

Purple Slime — Ranged shooter with line-of-sight

Fire Slime — Burning projectile clouds

Ice Slime — Freezing clouds

Poison Slime — DoT poison clouds

Ghost Slime — Phases through walls, 1 HP, always chases

Dynamic AI systems:

Wandering, chasing, aggro, and de-aggro states

LOS checks for ranged enemies

Enemies ignore invisible players

Level-based scaling (health & damage)

Smart spawn curve — enemy types unlock over time

🛍️ Progression & Upgrades

Shop between levels with 30+ upgrades:

Health refills / max HP boosts

Ammo refills / max ammo boosts

Pistol upgrades: damage, fire rate, burst shots

Alternate weapon unlocks

Abilities: Dash, Bullet Time, Shield Bubble, Invisibility

Ability cooldown upgrades

Systems:

Rarity system — Common / Uncommon / Rare / Epic

Dynamic shop pool based on your loadout

Coin economy

Breakable crates with loot

🎨 Game Feel & Polish

Smooth room-based camera transitions

Screen shake, hit flashes, explosions

Enemy hit feedback (sprite flash + light flash)

Healing flash

Knockback system

Pickup magnet

“PRESS E” floating prompts

Weapon-specific SFX with pitch variation

Dynamic colored lighting

Empty-magazine click

⚙️ Systems & Mechanics

Modular health component (supports burn/freeze/poison)

4 ability types:

Dash

Bullet Time

Shield Bubble

Invisibility

Projectile variants:

Bouncing, explosive, freezing, poison, piercing

Auto-turret with LOS

Crates with loot + destruction animation

Pause & death menus

🐛 Debug Tools
F1  - Open shop
F2  - Add 999 coins
F3  - Kill all enemies
F4  - Level select
F5  - God mode
F6  - Infinite ammo
F7  - Noclip
Shift+F8 - Laser mode
F12 - Debug overlay

🎯 Project Goals

This project demonstrates:

✔️ Procedural generation

✔️ Clean & modular code architecture

✔️ State-machine enemy AI

✔️ Progression & economy systems

✔️ Strong game feel polish

✔️ Solid Git workflow and documentation

📋 Project Planning

Development tracked on Trello:

📌 Main Task Board

🗺️ Feature Roadmap

🕹️ Controls
Keyboard + Mouse
Action	Input
Move	WASD
Aim	Mouse
Shoot	LMB
Alt-Fire	RMB
Ability	Space
Interact	E
Pause	ESC
Controller
Action	Input
Move	Left Stick
Aim	Right Stick
Shoot	RT
Alt-Fire	LT
Ability	A
Pause	Start
📸 Screenshots

(Coming soon — demo video available.)

▶️ How to Run
Requirements

Godot Engine 4.5+

Steps
git clone https://github.com/Safinvgehlenosman/Top-Down-Shooter-Game.git


Open Godot

Click Import

Select project.godot

Press F5

🛠️ Technical Details
Engine & Language

Engine: Godot 4.5

Language: GDScript

Architecture: Component-based + autoload singletons

Key Systems

GameState — global run data

GameConfig — global balance values

UpgradesDB — all upgrades definitions

HealthComponent — status effects, damage, healing

AbilityComponent — cooldowns & ability logic

Procedural room loader — no room repeats

Code Structure
scripts/
 ├── game_state.gd
 ├── game_config.gd
 ├── game_manager.gd
 ├── Upgrades_DB.gd
 ├── player.gd
 ├── gun.gd
 ├── ability.gd
 ├── health_component.gd
 ├── slimes/
 │    ├── base_slime.gd
 │    ├── purple_slime.gd
 │    ├── ghost_slime.gd
 └── ui/
      ├── shop_ui.gd
      ├── upgrade_card.gd

🎨 Assets

Pixel art — custom edits + free sources

SFX — placeholders (to be replaced)

Pixel UI font

🚀 Future Plans

More enemies + boss fights

More weapons & abilities

Permanent meta-progression

Achievements

High score / leaderboard

Original soundtrack

Long-term: Steam release

👤 About

Developer: Safin van Gehlen
Started: January 20, 2025
Development: 8–10 hours per day
Solo learning project showcasing gameplay programming, design, and systems engineering.

📝 License

This project is not licensed for redistribution or commercial use.
Viewing source code for educational purposes is allowed.

🔗 Links

🎥 Gameplay Demo Video

📋 Trello Board

🗺️ Roadmap
