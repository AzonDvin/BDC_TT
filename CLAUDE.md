# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A hot-seat 3D tabletop simulator for **Black Death City** (Sam Pearson's skirmish wargame, Playtest v1.03). The rulebook is `BlackDeathCity-Playtest-1.03.pdf` in the project root. Cite **printed** page numbers (PDF page minus 1) in code comments.

Two user-level skills apply here. Load them for rules or engine work:
- **bdc-rules-expert**: rules digest, scenario details, the list of rulings and ambiguities, and the faction JSON conventions.
- **godot-wargame-dev**: architecture conventions and the headless test runner.

## Commands

Godot 4.7.2 (standard build, GDScript only):

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path . --import                                        # after adding/renaming class_name scripts
"$GODOT" --headless --path . --script res://tests/run_tests.gd               # all tests (exit code 0 = pass)
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- melee      # tests whose id contains "melee"
"$GODOT" --headless --path . --check-only --script res://rules/combat.gd     # parse-check one script
"$GODOT" --headless --path . --script res://tools/sim_report.gd              # bot-vs-bot battle in every scenario, prints outcomes
"$GODOT" --path . --script res://tools/screenshot.gd -- res://view/battle.tscn out.png 70   # windowed screenshot after 70 bot steps
"$GODOT" --path .                                                            # play
```

Tool scripts run with `--script` can't name the `App` autoload at compile time. Use `get_root().get_node("App")` at runtime instead.

## Architecture

**The rules engine (`rules/`) is plain GDScript with no nodes.** The 3D scene (`view/`) only displays it and calls its public methods. Keep rules logic out of `view/`.

- `Battle` (`rules/battle.gd`) holds all battle state and the round/activation flow (p.18-19): priority roll, alternating activations, surge activations, end of round, flee tests.
  - Player decisions are a **`pending` dictionary** answered with `Battle.respond()`, never `await`. Decision types include choose_first, surge_or_pass, flee_test, deploy/place, pick_entry, pick_reserve_group, melee_weapons, duel_turn and volley.
  - The view and `SimpleBot` both drive the game only through this API.
- **Rules modules are static functions taking the `Battle`:**
  - `Movement`: declare a move, then commit a path of waypoints in inches.
  - `Combat`: ranged attacks with the closest-target rule, templates, `resolve_hit`, and the alternating melee **duel** state machine kept in `battle.duel`.
  - `Magic`: casting, miscasts, and the `SPELLS` targeting table for all 48 spells.
  - `Abilities`: bonus and special actions.
  - `Scenario`: terrain generation, deployment zones, reserves, treasure, twists and victory for all 6 scenarios.
- **`Effects` is the single place for number-changing rules:** armour, attack modifiers, crit thresholds, damage, ranges, auras and **visibility/cover**. Add new skill or spell modifiers there, not at call sites.
- **Data:** `data/bdc/*.json` is the faction data (fighters, armouries, spells, skills), read via `Catalog`. It is copied from the bdc-rules-expert skill's `data/` folder, so keep the two in sync. `Roster` builds and validates warbands. `FighterState` is a fighter's battle state, built from a roster member.
- **Determinism and saves:**
  - All randomness goes through `battle.dice`, which is seeded. Never use global `randi()` in `rules/`.
  - `Battle.to_dict()`/`from_dict()` snapshot everything. They are used for undo (cleared as soon as dice are rolled) and for the save file `user://battle_save.bdc` (`var_to_str`).
- **Geometry:**
  - One unit = one inch. Battle `(x, y)` maps to world `(x, 0, y)`.
  - Fighter distances are base edge to base edge (`Geo.base_gap`, clamped at 0).
  - **Use `Geo.signed_gap` for overlap checks.** A clamped gap can never be negative.
  - Terrain is floor polygons with a height. High terrain (1.5" or taller) blocks movement and sight. Low terrain costs 1" to cross and obscures fighters close behind it.
- **Scope limits (current version):**
  - Fighters stay on the battlefield floor: no climbing, platforms, jumping, falling or vantage.
  - Doors and windows aren't modelled.
  - Scenario twists not in `Scenario.AUTOMATED_TWISTS`, and spells with `target: "manual"`, are announced for the players to resolve with the in-game **Table tools**.
  - The campaign chapter is absent from v1.03.

## Conventions

- When implementing a rule the book leaves open, follow `references/ambiguities.md` in the bdc-rules-expert skill. Put the ruling in a comment and, where practical, a `Battle.cfg` flag.
- Every rules change needs a test. `tests/test_full_battles.gd` plays bot games in every scenario, and any script error fails it. `tests/test_ui_smoke.gd` drives the real screens.
