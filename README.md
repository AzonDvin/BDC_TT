# Black Death City — Tabletop Simulator

A 3D tabletop for **Black Death City**, Sam Pearson's narrative skirmish wargame. It runs the Playtest v1.03 rules for you. Play alone against a computer opponent, or with two players sharing one screen and taking turns ("hot-seat"). The game measures, rolls the dice, applies the rules, and tells you whose decision it is.

> This is an unofficial fan project for playtesting. Black Death City and its rules belong to Sam Pearson. Get the rulebook, warband roster and reference sheet at [blackdeathcity.com](https://www.blackdeathcity.com). The rulebook PDF is not included here.

---

## Getting started

1. Install **Godot 4.7** (the standard version, not the .NET one). It's free on [godotengine.org](https://godotengine.org) and on Steam.
2. Download or clone this repository.
3. Open Godot, click **Import**, and choose the `project.godot` file in this folder.
4. Press **Play** (F5) or the ▶ button at the top right.

The main menu offers:

| Button | What it does |
|---|---|
| **New Battle** | Choose two warbands, a scenario and a battlefield, and start a battle. |
| **Warband Builder** | Recruit and equip your own warbands within 1000 silver. |
| **Terrain Editor** | Build and save your own battlefields. |
| **Continue Saved Battle** | Pick up where you left off (battles save automatically). |

---

## Warband Builder

The builder covers all four factions in the playtest: **Guild Mercenaries, Verminkin, Death Covens and The Blighted Cloister**.

1. **Faction and Origin.** The origin decides your Leader and may change some limits. For example, Knights-Militant can recruit any number of Cloister Knights.
2. **Recruit.** Click fighters in the middle column. Hover over one to see its stats and special rules.
3. **Equip.** Click a fighter in your roster on the right to:
   - rename it;
   - add wargear from the lists it's allowed;
   - pick its skills and signature spells;
   - choose its Bloodline Mutation (Misbegotten only).
4. **Check legality.** The left panel shows silver spent, the warband rating, and every rule your warband breaks. When it says **"This warband is legal and ready to fight"**, you're done.
5. **Save** it. Saved warbands appear in the New Battle screen.

The builder checks:
- 1 Leader, 0–3 Champions, 5+ Henchmen, 0–2 Brutes, 0–3 Beasts, 15 fighters at most;
- per-fighter limits (0-1 and so on);
- carrying limits (2 melee, 1 ranged, 1 armour, 2 items);
- two-handed weapons and held items;
- Full-Plate restrictions;
- Rare items;
- duplicate skills;
- the 1000-silver budget.

**Sample** loads a ready-made legal warband for the selected faction.

---

## Starting a battle

On the **New Battle** screen:

- **Player 1 / Player 2:** pick a sample warband or one you saved.
- **Played by:** *Human*, or a computer opponent:
  - *Computer (normal)* plans its turns. It goes for the scenario's objectives, charges what it can reach, shoots the most damaging target, picks up and carries off treasure, keeps shooters and casters away from danger, and parries blows that would hurt. Shooters with a weapon reaching over 15" climb ladders and walls to high ground and hold it while they have targets. Casters with attack spells blast from range instead of charging, and draw power when no enemy is within 6".
  - *Computer (easy)* simply heads for the nearest enemy and attacks.

  For a one-player game, set one side to a computer. Set both to Human for hot-seat, or both to Computer to watch a battle.
- **Scenario:** one of the six from the book, or *Random* to roll a d6 as the book does.
- **Twist:** a specific twist, or *Random*.
- **Battlefield:** random ruins laid out for the scenario, or a layout you made in the Terrain Editor.
- **Dice seed:** leave it blank. Enter a number to replay exactly the same dice.

Then press **Start Battle ▶**.

The game sets up the scenario for you:
- the underdog (lower warband rating);
- battle groups and reserves;
- entry points;
- treasure;
- spell preparation.

Some of these ask a player to choose, such as which entry point to take.

---

## Playing a battle

### The screen

- **Top bar:** scenario, twist, round, who has priority, who the underdog is, the score, and **whose decision it is**. The player's name is shown in their colour (red for Player 1, blue for Player 2).
- **Left:** both warbands. Click a name to find that fighter. ✓ = activated this round, ⟳ = made a surge activation.
- **Right, top:** the selected fighter's full profile, with current Armour (including shields and cover), weapons, skills, prepared spells and statuses.
- **Right, bottom:** the battle log. Every roll and rule is written out.
- **Bottom:** the actions and decisions available right now.
- **Hover over any fighter** to see a quick profile, its distance from the activating fighter, and whether that fighter can see it or it's in cover.

### Figures

Fighters are shown as figures from the free KayKit Adventurers pack:

| Fighter | Figure |
|---|---|
| Wizards and Priests | Mage |
| Leaders | Knight |
| Champions | Barbarian |
| Henchmen with a bow or crossbow | Ranger |
| Other henchmen | Rogue or Hooded Rogue |
| Brutes | A big stone-grey Skeleton Warrior (golem-like) |
| Vampyres (Bloodcursed, Misbegotten) | Skeleton Mage |
| Vampyres (Bloodcursed, Misbegotten) | Skeleton Mage |
| Skeletons (Death Covens) | Skeleton Warriors and Minions; Skeleton Mage or Rogue for skeleton casters and crossbowmen |
| Zombies | Green Skeleton Minions that shamble |
| Lycanfell Beast | A fur-tinted Barbarian (the figure changes when the noble transforms) |
| Blighted Cloister demons | Rot Demons are red imps, the Rot-Herald a blue demon, the Rotspawn a spiky one-eyed blob, the Rot-Colossal a hulking yeti, Rotlings small green blobs and Bloat Flies buzzing bees |
| Darkcloven Beastmen and Shamans | A club-wielding orc, and a masked tribal shaman |
| Mercenary Ogre, Zombie Ogre | A blocky Giant (the Zombie Ogre in zombie green) |
| Hunting Dogs, Dire Wolves, Dire Bats | Huskies, pale wolves, and a bat-winged creature |
| Gargoyle | A horned, bat-winged flyer |
| Giant Rats and Rat-Mutants | Rats, the Rat-Mutant big and dark |

They hold their weapons (swords, axes, daggers, staffs, bows, crossbows and shields), face the way they move or the enemy they fight, walk or run along their moves, flinch when wounded, and fall when taken down.

Attacks are shown on the table: arrows and crossbow bolts fly to the target (or past it on a miss), spells fire glowing bolts, blasts explode and flames roar along their template. Melee fighters lunge with each blow. Results rise above the fighters ("-2", "SAVED", "MISS", "PARRIED"), with sparks on armour and parries, a red burst on a wound and a camera shake on a critical hit. On the computer's turn the camera frames the attacker and its target.

Figures swing, chop and stab with one-handed, two-handed or paired weapons (claws and bites punch and kick), block parries, draw and loose bows, shoot crossbows and pistols, throw slings and bombs, cast spells, channel power, reload, and dodge shots that miss them. These come from the [KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) pack in `assets/kaykit_character_animations/`; without it, fighters lunge instead.

The base shows the team colour; activated fighters are darkened. Skeletons carry bone weapons, crawl up out of the ground when they arrive or Rise Again, and collapse when taken down. Creatures bring their own idle, walk, run, attack, hit and death animations, and flyers hover above their bases. Weapons the packs don't have (guns, claws) aren't shown; the Rolling-Contraption is a stone-grey stand-in.

### Camera

| Control | Action |
|---|---|
| Right-drag | Orbit around the table |
| Middle-drag, or W A S D | Pan |
| Mouse wheel | Zoom |
| Q / E | Rotate |

### Deployment and reinforcements

When the game asks a player to deploy or place arriving fighters:
- the allowed area is shaded in that player's colour;
- **click inside it** to place each fighter, and click a placed fighter to pick it up again;
- **Auto-place the rest** fills in anyone left.

A fighter can't be placed overlapping terrain or another fighter, or engaged with an enemy.

### A round

Each round runs as in the book:

1. **Priority roll** (ties go to the underdog). The player with priority chooses who activates first.
2. **Start of round:** twists and arriving reinforcements.
3. **Activations.** Players take turns activating one fighter each. When you run out of fighters you may make **surge activations** (1 move or 1 action), or pass.
4. **End of round:** scoring and victory checks.
5. **Flee tests** for any warband with 5 or more fighters bloodied or taken down. You can choose to flee instead of rolling.

### Activating a fighter

Click one of your fighters that hasn't activated yet (or use the buttons at the bottom). It gets **1 Move and 1 Action** in either order, plus any bonus actions it has. A bloodied fighter, or a surge activation, gets a move **or** an action. Press **End activation** when done.

**Moves**

- **Normal** (Move value), **Run** (+d6", no action afterwards), **Charge** (+d6", must end within 1" of an enemy, or the activation ends), **Disengage** (Initiative test, 3", must end more than 1" from all enemies).
- After choosing a move, **click the destination**. The path shows the inches used and turns red if the move isn't legal, with the reason.
  - **Click again** to change the destination.
  - **Shift+click** adds a bend before the destination (to go round walls or through a doorway).
  - **Alt+click** aims at the ground underneath a roof or upper floor.
  - **Enter** or **Confirm move** to make the move. **Undo last point** removes the last bend or destination.
- The game applies the movement rules:
  - normal and run moves can't come within 1" of an enemy;
  - low terrain, doorways and windows cost 1";
  - fighters can't move through walls or other fighters;
  - deadly terrain deals damage;
  - the whole base must stay on the table.
- **Going up and down:**
  - **Ladders** cost 1".
  - **Climbing a wall** costs its height (Beasts can't climb).
  - **Jumping** across a gap is limited to 3" through the air.
  - **Jumping down** 3" or more causes impact damage. The **Getting down** option lets you choose climb or jump.
  - Fighters with **Fly** pass over everything.
- **Treasure:** tick **Pick up treasure** on a Normal move that ends within ½" of a token (it costs 1"). A fighter carrying treasure who reaches a table edge escapes with it.

**Actions**

- **Melee attack** (when engaged): pick the target and your weapon, and an off-hand weapon if you have one. The defending player then picks their weapons. Both sides roll, and initiative goes to the charger, or to the higher d6 + Initiative. Then the players take turns choosing **attack** or **parry** from the buttons until the dice run out. Each player makes their own choices.
- **Shoot:**
  - only legal targets light up green (the **closest-target rule** applies);
  - obscured targets are in cover (+1 Armour);
  - shooting from 3" or more above the target gives +1 (vantage);
  - **Blast** weapons: click a point on the table;
  - **Flame** weapons: click a direction;
  - **Volley** weapons let you spread their attacks;
  - reloading, Heavy, misfires and one-use weapons are handled for you.
- **Hide:** the fighter must be touching terrain, not engaged, and more than 3" from all enemies. If it can't hide, the button says why.
- **Arcane** (Wizards and Priests):
  - **Draw power** gives an extra casting die on the fighter's next activation;
  - or **Cast** a prepared spell, then click its target, point or direction as the hint says. Eldritch Barrier needs two clicks, one for each end;
  - miscasts, Grimoires and Ensorcelled Bells are applied automatically.
- **Reload:** shown when a weapon needs it, forgoing either the move or the action.
- **Special:** bonus actions and special actions from skills and items. Examples:
  - Rallying Cry, Smoke Bomb, the Bomb Rat, Witchfire;
  - Recite Holy Litanies, Patch You Up;
  - the Lycanfell Noble's transformation.

### Winning

Each scenario has its own victory conditions, and the top bar keeps the score. Hover over the scenario or twist name in the top bar to read what it means and how it is won. In any scenario, a warband that **flees** loses, and so does a warband with nobody left in the battle: every fighter taken down (or escaped), with none in reserve. If both are wiped out together, it's a draw. When the battle ends, the result is shown with options to start a new battle or return to the menu.

### Playing against the computer

On the computer's turn, the action panel says it is playing, the camera follows its active fighter, and the panel lists what its **last step** did (the move, the dice, the hits). Its fighters slide along their path, and the path stays drawn on the table until its next step.

Use **Computer:** in the top bar to set the pace: *Slow*, *Normal*, *Fast* or *Paused*. When paused, press **Step ▶** to watch it make one move, action or decision at a time. You can still orbit the camera and hover over fighters to read their profiles. When the computer attacks one of your fighters, you choose that fighter's weapons and duel moves as usual.

The computer plays by exactly the same rules and dice as you do. It can't see anything the rules don't let a player know.

### Tools at the top right

- **Undo:** undoes the current activation, until dice have been rolled. It isn't available during the computer's turn.
- **Table tools:** for anything you agree to settle by hand, as at a real table:
  - move any fighter by clicking it and then the table;
  - change life, take a fighter down or bring it back;
  - toggle poisoned, hidden or activated, and clear effects.

  Every change is written to the log.
- **Sound:** turns the sound effects on or off. You hear footsteps for moves, a whoosh for missed blows, a whiz for missed shots, a thud when a blow wounds, a clank when armour saves, a clash for parries, a bowstring for shots, and a heavy fall when a fighter is taken down. The setting is remembered.
- **Dice:** roll 2d6 openly into the log.
- **Save** and **Menu:** the battle also saves automatically after every activation. **Continue Saved Battle** on the main menu resumes it.

---

## Terrain Editor

Build your own ruined district and fight over it.

- **Palette (left):** ruin (walls with a doorway, a window and often an upper floor with a ladder), ruined house (walkable roof), tower, high wall, low wall, rubble, upper floor, ladder, doorway, window, statue, dead tree and deadly pit. Click one, then click the table to place it. Hold **Shift** to keep placing.
- **Editing:** click a piece to select it, and **drag** to move it. A ruin's walls, floor and ladder move together.

| Key | Action |
|---|---|
| R / F | Rotate 15° |
| ↑ / ↓ | Raise or lower the height |
| + / − | Make it bigger or smaller |
| Delete | Remove the selected group |
| Ctrl+D | Duplicate |
| Esc | Deselect |

  The buttons on the right also toggle doors open or closed and delete single pieces.
- **Random** generates a layout for the chosen scenario to start from. **Clear table** empties it.
- Name your layout and press **Save layout**. Choose it under **Battlefield** on the New Battle screen.

Leave the entry corners and the scenario areas (the centre, the chapel, the holding) reasonably open, because the scenarios use them.

---

## How the simulator handles the rules

The playtest leaves some things open, and a computer has to decide them. The main rulings:

- **Line of sight** is checked in 3D, from the observer's eye to points across the target's body.
  - Walls, upper floors and other fighters block sight.
  - Low walls hide the legs of fighters close behind them, which puts those fighters in cover.
  - A fighter is visible if any part of it can be seen, and obscured if any part is hidden.
- **Touching terrain** (for Hide) means within 0.35", since bases can't be pushed flush against a wall by hand.
- **Charging fighters** may pass within 1" of enemies on the way in. Normal and run moves may not.
- **Doom** is applied to the doomed fighter's first successful armour roll.
- **Treasure** carriers who reach an edge escape automatically.
- **Climbing:** a fighter can't end its move part-way up a wall (the book allows it).
- **The campaign rules** (injuries, experience, income) aren't in Playtest v1.03, so the simulator plays single battles.

Everything that happens is written to the battle log, with the dice rolled, so any result can be checked against the book.

---

## Credits

Fighter figures and animations: [KayKit Adventurers](https://kaylousberg.itch.io/kaykit-adventurers), [KayKit Skeletons](https://kaylousberg.itch.io/kaykit-skeletons) and [KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) by Kay Lousberg (www.kaylousberg.com), CC0.
Creatures: [Ultimate Monsters](https://poly.pizza/bundle/Ultimate-Monsters-Bundle-5oyGWAmOB6), [Ultimate Animated Animals](https://quaternius.com/packs/ultimateanimatedanimals.html), [Rat](https://poly.pizza/m/iltq5bVNaV) and [Giant](https://poly.pizza/m/BldaiPtyJa) by Quaternius (quaternius.com), CC0.

---

## For developers

The rules engine is plain GDScript in `rules/`, and the 3D screens are in `view/`. Run the tests with:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

`CLAUDE.md` describes the architecture, and `tools/` has scripts for bot-vs-bot battle reports (`ai_report.gd` compares the computer levels), battle logs and screenshots.
