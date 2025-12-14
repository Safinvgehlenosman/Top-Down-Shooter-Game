PROJECT CONTEXT
Engine: Godot 4.5.1 (GDScript) MAKE SURE YOU USE GODOT 4 CODE AND API'SNOT GODOT 3.
Project root contains `project.godot`, `export_presets.cfg`, and `assets/`, `scenes/`, `scripts/`.

This project is in a STABILIZATION PHASE.
Correctness > predictability > cleanliness > speed.

────────────────────────────────────────
ABSOLUTE RULES (NON-NEGOTIABLE)
────────────────────────────────────────
- Do NOT create new functions unless explicitly asked.
- Do NOT duplicate existing functions.
- Do NOT define a function that already exists under any name.
- Do NOT rename functions, signals, or variables unless explicitly instructed.
- Modify ONLY existing code blocks when fixing bugs.
- Preserve indentation, structure, and formatting exactly (GDScript is indentation-sensitive).
- Prefer minimal diffs over refactors.
- If unsure, ASK instead of guessing or inventing logic.

If any instruction conflicts with these rules, THESE RULES WIN.

────────────────────────────────────────
CORE ARCHITECTURE (DO NOT DEVIATE)
────────────────────────────────────────
Single-source run state:
- `scripts/game_state.gd` is the global singleton (GameState).
- GameState aggregates upgrade effects, exposes signals, and centralizes runtime flags and stats.
- Other systems READ from GameState; they should not silently mutate run-level stats.

Big-picture data flow:
- Upgrades:
  - Static definitions live in `scripts/Upgrades_DB.gd` (`UPGRADE_DEFS`).
  - Runtime ownership & counts live in:
    - `GameState.acquired_upgrades`
    - `GameState.upgrade_purchase_counts`
  - Application paths:
    - Immediate effects → `GameState.apply_upgrade()`
    - Per-run aggregation → `GameState.start_new_run()`

- Weapons:
  - Primary weapon logic lives in `scripts/weapons/gun.gd`.
  - Gun queries GameState for damage, fire rate, burst, crit, etc.
  - Bullet spawning uses `PackedScene.instantiate()` and
    `get_tree().current_scene.add_child()`.

- Player:
  - `scripts/player/player.gd` handles input.
  - Calls `gun.handle_primary_fire(is_pressed, aim_dir)`.
  - Syncs stats from GameState.

- UI / Shop:
  - Upgrade selection & purchase is handled in `scripts/ui/upgrade_card.gd`.
  - Purchases call:
    - `GameState.record_upgrade_purchase()`
    - `UpgradesDB.apply_upgrade()`

────────────────────────────────────────
UPGRADE IMPLEMENTATION RULES
────────────────────────────────────────
To add or modify an upgrade:
1) Add or edit the entry in `UPGRADE_DEFS` in `scripts/Upgrades_DB.gd`.
2) Handle its effect in `GameState.apply_upgrade()`:
   - Modify numeric counters or boolean flags only.
   - Call `_record_acquired_upgrade()` if ownership is required.
   - Call `_emit_all_signals()` when state changes.
3) If the upgrade affects per-run aggregated stats:
   - Ensure `start_new_run()` resets related counters BEFORE aggregation.

Do NOT:
- Apply upgrades implicitly at run start.
- Modify weapon behavior directly without going through GameState.
- Invent new upgrade categories, effects, or systems.

Upgrades may be applied in TWO places:
- Immediate: `apply_upgrade()`
- Aggregated: `start_new_run()`
New upgrades must be consistent with this split.

────────────────────────────────────────
GODOT-SPECIFIC CONSTRAINTS
────────────────────────────────────────
- One function = one definition. Never create parallel versions.
- No nested function definitions.
- No duplicate signal handlers.
- No frame-based logic (`_process`) for cooldown-gated actions.
- Auto-fire MUST always respect cooldowns and input state.

Delayed actions:
- Use `call_deferred()` or
  `await get_tree().create_timer(delay).timeout`
- Required for trailing shots, burst delays, and timed effects.

Audio / SFX:
- Audio is local to weapon nodes using `AudioStreamPlayer2D`.
- Do not move audio logic into GameState.
- Example: `gun.gd` uses `../SFX_Shoot`.

Node lookup:
- Prefer existing helpers and patterns:
  - `get_tree().get_first_node_in_group("player")`
  - `get_node("Gun")`
- Do not introduce new lookup patterns unless necessary.

────────────────────────────────────────
KNOWN PITFALLS (DO NOT REINTRODUCE)
────────────────────────────────────────
- `GameState.start_new_run()` may be called from multiple places (UI + manager).
  - A frame guard using `Engine.get_frames_drawn()` exists.
  - Do NOT remove or bypass this guard.

- Previous bugs were caused by:
  - Duplicate function definitions
  - Over-eager refactors
  - Logic split across multiple locations

Always search before adding similarly named logic.

────────────────────────────────────────
DEBUGGING RULES
────────────────────────────────────────
- Add TEMPORARY debug prints only.
- Remove debug prints once the issue is fixed.
- Debug first, change logic second.
- Never “clean up” unrelated code while debugging.

────────────────────────────────────────
DEVELOPER WORKFLOW
────────────────────────────────────────
- Run via Godot Editor Play button.
- No automated tests; use editor console for `print()` debugging.
- Treat this as a live production codebase, not a tutorial.

Frequently touched files:
- `scripts/game_state.gd`
- `scripts/Upgrades_DB.gd`
- `scripts/weapons/gun.gd`
- `scripts/player/player.gd`
- `scripts/player/health_component.gd`
- `scripts/ui/upgrade_card.gd`

────────────────────────────────────────
FINAL NOTE
────────────────────────────────────────
Be conservative.
Be explicit.
Do not optimize or refactor unless explicitly asked.
Minimal, correct changes are always preferred.
