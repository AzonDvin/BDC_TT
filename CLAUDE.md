# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A 3D tabletop simulator (hot-seat or against a computer opponent) for **Black Death City** (Sam Pearson's skirmish wargame, Playtest v1.03). The rulebook is `BlackDeathCity-Playtest-1.03.pdf` in the project root. Cite **printed** page numbers (PDF page minus 1) in code comments.

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
"$GODOT" --headless --path . --script res://tools/ai_report.gd -- 4          # normal AI vs easy bot, 4 games per scenario (sides swapped)
"$GODOT" --headless --path . --script res://tools/ai_log.gd -- the_find 2 0  # full log of one AI game (scenario, pairing, normal side)
"$GODOT" --path . --script res://tools/screenshot.gd -- res://view/battle.tscn out.png 70   # windowed screenshot after 70 bot steps
"$GODOT" --path .                                                            # play
```

Tool scripts run with `--script` can't name the `App` autoload at compile time. Use `get_root().get_node("App")` at runtime instead.

## Architecture

**The rules engine (`rules/`) is plain GDScript with no nodes.** The 3D scene (`view/`) only displays it and calls its public methods. Keep rules logic out of `view/`.

- `Battle` (`rules/battle.gd`) holds all battle state and the round/activation flow (p.18-19): priority roll, alternating activations, surge activations, end of round, flee tests.
  - Player decisions are a **`pending` dictionary** answered with `Battle.respond()`, never `await`. Decision types include choose_first, surge_or_pass, flee_test, deploy/place, pick_entry, pick_reserve_group, melee_weapons, duel_turn and volley.
  - The view, `SimpleBot` and `AI` all drive the game only through this API.
- **Rules modules are static functions taking the `Battle`:**
  - `Movement`: declare a move, then commit a path of waypoints in inches.
  - `Combat`: ranged attacks with the closest-target rule, templates, `resolve_hit`, and the alternating melee **duel** state machine kept in `battle.duel`.
  - `Magic`: casting, miscasts, and the `SPELLS` targeting table for all 48 spells.
  - `Abilities`: bonus and special actions.
  - `Scenario`: terrain generation, deployment zones, reserves, treasure and victory for all 6 scenarios.
  - `Twists`: scenario twists and round-long spell effects.
  - `Height`: surfaces, climbing faces, falling and impact damage.
- **Computer player** (`rules/ai.gd`, `AI`): `battle.cfg["ai"] = [p0, p1]`, each `""` (human), `"easy"` (SimpleBot) or `"normal"`.
  - `AI.step(b)` does one thing: answer a pending decision, pick a fighter, or one part of an activation. `AI.should_act(b)` says whether the current decider is a computer.
  - Moves come from `AINav` (`rules/ai_nav.gd`): a 0.5" floor grid, Dijkstra, then path straightening. `Movement.evaluate` always has the last word.
  - It plans with `Options`, `Combat`, `Magic` and `Abilities` only and never rolls `battle.dice` for its own choices. Per-activation memory is in `scen["ai_tried"]`.
  - The view calls `_ai_do_step` from `_ai_tick` at the pace in `AI_SPEEDS` (`App.ai_speed`; Paused + Step button). It animates moves (`Board3D.animate_path`, using `AI.last_move`), draws the trail and shows the step's log lines. Human clicks are ignored meanwhile. The setup screen's "Played by" sets it.
- **Sound** (`view/sfx.gd`, `Sfx`): effects are synthesised in code (no audio files) and triggered from log lines by `Sfx.events_for(text)`. If you change the wording of a move, hit, save, parry or take-down log line, update it and `tests/test_sfx.gd`. `tools/sfx_preview.gd` exports them as .wav. Settings (sound, computer pace) are in `user://settings.cfg` via `App`.
- **`Effects` is the single place for number-changing rules:** armour, attack modifiers, crit thresholds, damage, ranges, auras and **visibility/cover**. Add new skill or spell modifiers there, not at call sites.
- **Data:** `data/bdc/*.json` is the faction data (fighters, armouries, spells, skills), read via `Catalog`. It is copied from the bdc-rules-expert skill's `data/` folder, so keep the two in sync. `Roster` builds and validates warbands. `FighterState` is a fighter's battle state, built from a roster member.
- **Determinism and saves:**
  - All randomness goes through `battle.dice`, which is seeded. Never use global `randi()` in `rules/`.
  - `Battle.to_dict()`/`from_dict()` snapshot everything. They are used for undo (cleared as soon as dice are rolled) and for the save file `user://battle_save.bdc` (`var_to_str`).
- **Geometry:**
  - One unit = one inch. Battle `(x, y)` maps to world `(x, 0, y)`.
  - Fighter distances are base edge to base edge (`Geo.base_gap`, clamped at 0).
  - **Use `Geo.signed_gap` for overlap checks.** A clamped gap can never be negative.
  - Terrain (`TerrainPiece`) is floor polygons with a height. Kinds are high, low, impassable, deadly, platform, ladder, door and window.
    - `solid_bands()` gives the heights that block sight.
    - `has_surface()` marks walkable tops: platforms, and roofs at least 1"x1".
  - **Height** (`rules/height.gd`): a fighter is `(pos, elev)`.
    - All fighter-to-fighter distances are 3D: use `Effects.dist()` and `Effects.near()`, not `Geo` helpers.
    - Moves are waypoints with a level each. `Movement._segment` decides walk, jump (max 3" through the air), ladder (1"), climb (vertical distance counts), jump down (impact damage from 3") or fly.
    - `Battle.after_action()` runs fall checks.
  - **Sight** (`Effects.sight_blocked`) is true 3D: from the observer's eye to three heights across the target's body.
- **Twists and lingering effects** live in `rules/twists.gd`, hooked from `Scenario`.
  - Every twist in all six scenarios is automated. Start-of-round choices (Forsaken Quarter, Condemned) are `pick_quarter`/`pick_fighter` decisions.
  - Eldritch Barrier, Umbral Vortex and Plague Pit last until the end of the round in `scen`, and `Twists.clear_round()` removes them.
- **Terrain editor** (`view/terrain_editor.gd`): saves layouts to `user://layouts/` via `Layout`. `Battle.setup(..., layout)` uses a saved layout instead of generating terrain. Pieces share a `group` id so a ruin moves as one.
- **Scope limits (current version):**
  - Fighters can't end a move part-way up a wall (the book allows it, p.22).
  - The campaign chapter is absent from v1.03.

## Conventions

- When implementing a rule the book leaves open, follow `references/ambiguities.md` in the bdc-rules-expert skill. Put the ruling in a comment and, where practical, a `Battle.cfg` flag.
- Every rules change needs a test. `tests/test_full_battles.gd` plays bot games in every scenario, and any script error fails it. `tests/test_ui_smoke.gd` drives the real screens. `tests/test_ai.gd` covers the computer player.
