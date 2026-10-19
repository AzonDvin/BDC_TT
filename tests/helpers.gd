extends RefCounted
## Builders for rules tests: a bare battle with chosen fighters placed by hand (no scenario set-up).


static func bare_battle(seed_value := 1) -> Battle:
	var b := Battle.new()
	b.dice = Dice.new(seed_value)
	b.player_names = ["Red", "Blue"]
	b.phase = "activation"
	b.round_no = 1
	b.scen = {"id": "test", "vp": [0, 0], "marks": [0, 0], "escaped": [0, 0], "reinforce_round": [99, 99], "entry": [0, 2]}
	return b


## Adds a fighter of def_id with equipment at pos (inches) for player p.
static func add(b: Battle, faction: String, def_id: String, p: int, pos: Vector2, equipment: Array = [], skills: Array = []) -> FighterState:
	var r := Roster.new()
	r.faction = faction
	var m := r.add_member(def_id)
	m["equipment"] = equipment
	for s in skills:
		m["skills"].append(s)
	var f := FighterState.from_member(r, m, p, b.new_uid())
	f.where = "board"
	f.pos = pos
	b.fighters.append(f)
	return f


static func activate(b: Battle, f: FighterState) -> String:
	b.turn = f.player
	b.pending = {}
	return b.activate(f.uid)
