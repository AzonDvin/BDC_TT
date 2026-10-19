class_name CombatFx
extends Node
## Attack visuals on the battle table: arrows and bolts that fly to their target (or past it), magic bolts,
## blasts and flames, impacts (sparks on armour and parries, a red burst on a wound, dust where a miss lands),
## a lunge for each melee blow (or an attack animation when the figure has one), floating results ("-2",
## "SAVED", "MISS", "PARRIED") and a small camera shake on critical hits.
## Like the sound effects, everything is driven from the battle log (events_for), so the rules know nothing
## about it, and events are queued a little apart so a burst of log lines plays out in order.

var b: Battle
var board: Board3D
var _queue: Array = []              # [{"at": seconds, "e": event}]
var _clock := 0.0
var _free_at := 0.0
var _names := {}                    # fighter name -> uid (names shared by both sides are left out)
var _name_list: Array = []          # longest first
var _name_count := -1
var _float_stack := {}              # uid -> [time, count] so results on one fighter stack upward
var _shake := 0.0


func setup(battle: Battle, board3d: Board3D) -> void:
	b = battle
	board = board3d


func _process(delta: float) -> void:
	_clock += delta
	while not _queue.is_empty() and _queue[0]["at"] <= _clock:
		var e: Dictionary = _queue.pop_front()["e"]
		if board != null and is_instance_valid(board):
			_play(e)
	if _shake > 0.0 and board != null and board.camera != null:
		_shake = maxf(0.0, _shake - delta)
		var k := _shake * 0.6
		board.camera.h_offset = randf_range(-k, k)
		board.camera.v_offset = randf_range(-k, k)
		if _shake == 0.0:
			board.camera.h_offset = 0.0
			board.camera.v_offset = 0.0


func on_log(text: String) -> void:
	if b == null:
		return
	_refresh_names()
	for e in events_for(text, _names, _name_list):
		var at := maxf(_clock, _free_at)
		if _queue.size() > 40:
			return
		_queue.append({"at": at, "e": e})
		_free_at = at + float(e.get("gap", 0.15))


func _refresh_names() -> void:
	if _name_count == b.fighters.size():
		return
	_name_count = b.fighters.size()
	_names = {}
	var clash := {}
	for f in b.fighters:
		if _names.has(f.name) and b.fighter(_names[f.name]).player != f.player:
			clash[f.name] = true
		_names[f.name] = f.uid
	for n in clash:
		_names.erase(n)
	_name_list = _names.keys()
	_name_list.sort_custom(func(x, y): return x.length() > y.length())


# =============================================================================================
# Reading the log

## The fighter name starting at `at` in text (longest match), or "".
static func _name_at(text: String, at: int, names: Array) -> String:
	for n in names:
		if text.substr(at, n.length()) == n:
			return n
	return ""


## Events for one log line: [{"kind", ...}] with fighter uids. Static so tests can check it.
static func events_for(text: String, names: Dictionary, name_list: Array) -> Array:
	var out: Array = []
	if text.begins_with("[") or text.begins_with("—") or text.begins_with("("):
		return out
	var who := _name_at(text, 0, name_list)
	var from: int = names.get(who, -1)
	# "X fires Crossbow (Bow 4+): 4✓ 1✗."  /  "X fires Bombs: rolled 3 — on target."  /  "X unleashes Flamethrower: ..."
	if who != "" and text.substr(who.length()).begins_with(" fires "):
		var rest := text.substr(who.length() + 7)
		var paren := rest.find(" (Bow")
		if paren >= 0:
			var weapon := rest.substr(0, paren)
			var results: Array = []
			for ch in rest.substr(rest.find("):") + 2):
				if ch == "✓" or ch == "!":
					results.append("crit" if ch == "!" else "hit")
				elif ch == "✗":
					results.append("miss")
			out.append({"kind": "shot", "from": from, "weapon": weapon, "results": results, "gap": 0.18 + 0.12 * results.size()})
		else:
			out.append({"kind": "template", "from": from, "gap": 0.6})
		return out
	if who != "" and text.substr(who.length()).begins_with(" unleashes "):
		out.append({"kind": "template", "from": from, "gap": 0.6})
		return out
	# Melee dice: "X rolls: Sword 4✓ 5✓ 1✗." -> the misses.
	if who != "" and text.substr(who.length()).begins_with(" rolls: "):
		var misses := text.count("✗")
		if misses > 0:
			out.append({"kind": "float", "to": from, "text": "MISS" if misses == 1 else "MISS ×%d" % misses, "color": "d8d0c0", "gap": 0.2})
		return out
	# "A hits B (CRIT) with W: armour 4+, rolled 2 — not saved; 2 damage (d3)."
	if who != "" and text.substr(who.length()).begins_with(" hits "):
		var p := who.length() + 6
		var tname := _name_at(text, p, name_list)
		if tname != "":
			var after := text.substr(p + tname.length())
			var crit := after.begins_with(" (CRIT)")
			var weapon := ""
			var wi := after.find(" with ")
			if wi >= 0:
				var colon := after.find(":", wi)
				weapon = after.substr(wi + 6, (colon if colon >= 0 else after.length()) - wi - 6)
			var dmg := 0
			var m := RegEx.create_from_string("; (\\d+) damage").search(after)
			if m:
				dmg = int(m.get_string(1))
			elif after.contains("Bludgeon still deals 1"):
				dmg = 1
			var saved := after.contains("SAVED") and dmg == 0
			out.append({"kind": "hit", "from": from, "to": names.get(tname, -1), "weapon": weapon, "crit": crit, "saved": saved, "dmg": dmg, "gap": 0.45})
		return out
	if who != "" and text.substr(who.length()).begins_with(" parries "):
		var foe := _name_at(text, who.length() + 9, name_list)
		out.append({"kind": "parry", "from": from, "to": names.get(foe, -1), "gap": 0.4})
		return out
	if who != "" and text.substr(who.length()).begins_with("'s parry fails"):
		out.append({"kind": "float", "to": from, "text": "PARRY FAILS", "color": "ff9a70", "gap": 0.2})
		return out
	if who != "" and (text.substr(who.length()).begins_with(" casts ") or text.substr(who.length()).begins_with(" attempts ")):
		var failed := text.contains("MISCAST") or text.contains("fails")
		var verb := " casts " if text.substr(who.length()).begins_with(" casts ") else " attempts "
		var rest2 := text.substr(who.length() + verb.length())
		var spell := rest2.substr(0, rest2.find(":")) if rest2.find(":") >= 0 else rest2
		out.append({"kind": "cast", "from": from, "spell": spell, "ok": not failed, "miscast": text.contains("MISCAST"), "gap": 0.35})
		return out
	if who != "" and text.substr(who.length()).begins_with(" reloads"):
		out.append({"kind": "motion", "from": from, "motion": "reload", "gap": 0.3})
		return out
	if who != "" and text.substr(who.length()).begins_with(" draws power"):
		out.append({"kind": "motion", "from": from, "motion": "draw_power", "gap": 0.3})
		return out
	# Other damage: "X suffers 2 damage" (falls, deadly terrain, miscasts, Eldritch Barrier...)
	var sm := RegEx.create_from_string("^(.+?) suffers (\\d+) damage").search(text)
	if sm and names.has(sm.get_string(1)):
		out.append({"kind": "float", "to": names[sm.get_string(1)], "text": "-" + sm.get_string(2), "color": "ff5a4a", "big": true, "gap": 0.25})
	return out


# =============================================================================================
# Playing the effects

func _play(e: Dictionary) -> void:
	match e["kind"]:
		"shot":
			_play_shot(e)
		"template":
			_play_template(e)
		"hit":
			_play_hit(e)
		"parry":
			var a := b.fighter(e["from"])
			var t := b.fighter(e["to"])
			if a != null and t != null:
				_attack_motion(a, t, "block")
				_burst((_chest(a) + _chest(t)) / 2.0, Color("ffe08a"), 18, 0.35)
				_float(a.uid, "PARRIED", Color("ffd36a"))
		"float":
			_float(e["to"], e["text"], Color(e["color"]), e.get("big", false))
		"motion":
			var mf := b.fighter(e["from"])
			if mf != null:
				_attack_motion(mf, null, e["motion"])
				if e["motion"] == "draw_power":
					_burst(_chest(mf), Color("8a7cff"), 16, 0.8, 0.8)
		"cast":
			var c := b.fighter(e["from"])
			if c != null:
				_attack_motion(c, _likely_target(c) if AI.DAMAGE_SPELLS.has(e.get("spell", "")) else null,
					"cast_attack" if AI.DAMAGE_SPELLS.has(e.get("spell", "")) else "cast")
				var col := Color("ff4040") if e["miscast"] else (Color("b07cff") if e["ok"] else Color("8070a0"))
				_burst(_chest(c), col, 24 if e["ok"] else 10, 0.6, 1.2)
				if e["miscast"]:
					_float(c.uid, "MISCAST", Color("ff5a4a"), true)
				elif not e["ok"]:
					_float(c.uid, "SPELL FAILS", Color("b0a8c0"))


func _play_shot(e: Dictionary) -> void:
	var s := b.fighter(e["from"])
	if s == null or not s.on_board():
		return
	var t := _likely_target(s)
	_frame(s, t)
	_attack_motion(s, t, "shoot", e["weapon"])
	if t != null and not e["results"].is_empty() and not ("hit" in e["results"] or "crit" in e["results"]):
		var tn: Node3D = board.fighter_nodes.get(t.uid)
		var tm: Node3D = tn.get_node_or_null("Model") if tn != null else null
		if tm != null:
			var dodge_at := create_tween()
			dodge_at.tween_interval(0.25)
			dodge_at.tween_callback(func(): FighterModels.play_attack(tm, t, "dodge"))
	if t == null:
		return
	var model := "arrow_crossbow" if String(e["weapon"]).to_lower().contains("crossbow") or String(e["weapon"]).to_lower().contains("arbalest") \
		else ("arrow_bow" if String(e["weapon"]).to_lower().contains("bow") else "")
	var i := 0
	for r in e["results"]:
		var from := _chest(s)
		var to := _chest(t)
		var dir := (to - from).normalized()
		if r == "miss":
			var side := dir.cross(Vector3.UP).normalized() * randf_range(0.8, 1.6) * (1.0 if randi() % 2 == 0 else -1.0)
			to = to + side + dir * 2.5
			to.y = 0.05
		_projectile(from, to, model, 0.12 * i, r == "miss")
		i += 1


func _play_template(e: Dictionary) -> void:
	var s := b.fighter(e["from"])
	var lt: Dictionary = b.scen.get("last_template", {})
	if s != null:
		_attack_motion(s, null, "shoot")
	if lt.is_empty():
		return
	if lt["type"] == "blast":
		var c := Vector3(lt["pos"].x, float(lt.get("elev", 0.0)) + 0.3, lt["pos"].y)
		if s != null:
			_projectile(_chest(s), c, "", 0.0, false, Color("ffb050"), true)
		_explosion(c, 0.35)
	else:
		var o: Vector2 = lt["origin"]
		var d: Vector2 = lt["dir"]
		for k in 6:
			var p := o + d * (1.0 + k * 1.3)
			_burst(Vector3(p.x, 0.5, p.y), Color("ff8a2a"), 14, 0.5, 1.0, 0.06 * k)


func _play_hit(e: Dictionary) -> void:
	var a := b.fighter(e["from"])
	var t := b.fighter(e["to"])
	if t == null:
		return
	_frame(a, t)
	var melee := a != null and a.on_board() and _uses_melee(a, e["weapon"]) and Effects.dist(a, t) <= 1.3
	var spell := Magic.SPELLS.has(e["weapon"])
	if melee:
		_attack_motion(a, t, "melee", e["weapon"])
	elif spell and a != null and a.on_board():
		_projectile(_chest(a), _chest(t), "", 0.0, false, Color("b07cff"), true)
	var delay := 0.18 if melee else (0.35 if spell else 0.0)
	var at := _chest(t)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if e["saved"]:
			_burst(at, Color("ffe08a"), 14, 0.3)
			_float(t.uid, "SAVED", Color("c8c8c8"))
		else:
			_burst(at, Color("d02020"), 22 if e["crit"] else 14, 0.45)
			_float(t.uid, ("-%d" % e["dmg"]) + (" CRIT" if e["crit"] else ""), Color("ff5a4a"), true)
			if e["crit"]:
				_shake = 0.25)


## The figure's attack animation if it has one (from the KayKit Character Animations pack), else a lunge.
func _attack_motion(f: FighterState, target: FighterState, kind: String, weapon := "") -> void:
	var n: Node3D = board.fighter_nodes.get(f.uid)
	if n == null:
		return
	var figure: Node3D = n.get_node_or_null("Model")
	if figure == null:
		figure = n.get_node_or_null("Body")
	if figure == null:
		return
	if target != null:
		Board3D._face(n, f.pos, target.pos)
	if figure.name == "Model" and FighterModels.play_attack(figure, f, kind, weapon):
		return
	if not kind in ["melee", "shoot"]:
		return
	var dir := Vector3(0, 0, 0)
	if target != null:
		dir = Vector3(target.pos.x - f.pos.x, 0, target.pos.y - f.pos.y).normalized()
	var reach := 0.35 if kind == "melee" else -0.12   # a step in for a blow, a small recoil for a shot
	var home := figure.position
	var tw := create_tween()
	tw.tween_property(figure, "position", home + dir * reach, 0.09)
	tw.tween_property(figure, "position", home, 0.18)


func _uses_melee(a: FighterState, weapon: String) -> bool:
	for w in a.melee:
		if w["name"] == weapon:
			return true
	return not Magic.SPELLS.has(weapon) and Effects.is_engaged(b, a)


## On the computer's turn, centres the camera between the attacker and its target so both are in view.
## (The player's own attacks never move the camera.)
func _frame(a: FighterState, t: FighterState) -> void:
	if a == null or t == null or not AI.is_ai(b, a.player) or not a.on_board() or not t.on_board():
		return
	board.focus((a.pos + t.pos) / 2.0)


## The enemy a shooter most likely aimed at: the closest one (the closest-target rule, p.28).
func _likely_target(s: FighterState) -> FighterState:
	var best: FighterState = null
	for o in b.on_board(b.other(s.player)):
		if best == null or Effects.dist(s, o) < Effects.dist(s, best):
			best = o
	return best


func _chest(f: FighterState) -> Vector3:
	var n: Node3D = board.fighter_nodes.get(f.uid)
	var base := n.global_position if n != null else Vector3(f.pos.x, f.elev, f.pos.y)
	return base + Vector3(0, 0.12 + f.height * 0.6, 0)


# --- Building blocks --------------------------------------------------------------------------------

func _projectile(from: Vector3, to: Vector3, model: String, delay: float, miss: bool, glow := Color("ffd27a"), magic := false) -> void:
	var node: Node3D = null
	if model != "":
		var sc := FighterModels._scene(FighterModels.KAYKIT + "Assets/gltf/%s.gltf" % model)
		if sc != null:
			node = sc.instantiate()
			node.scale = Vector3.ONE * 0.6
	if node == null:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.12 if magic else 0.06
		sp.height = sp.radius * 2.0
		mi.mesh = sp
		var m := StandardMaterial3D.new()
		m.albedo_color = glow
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		node = mi
	node.visible = false
	board.add_child(node)
	node.position = from
	if from.distance_to(to) > 0.01:
		node.look_at_from_position(from, to, Vector3.UP)
		if model != "":
			node.rotate_object_local(Vector3.RIGHT, -PI / 2.0)   # KayKit arrows point up their Y axis
	var secs := clampf(from.distance_to(to) / 32.0, 0.12, 0.6) * (1.6 if magic else 1.0)
	var tw := node.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): node.visible = true)
	tw.tween_property(node, "position", to, secs)
	if magic:
		tw.tween_callback(func(): _burst(to, glow, 18, 0.5))
	elif miss:
		tw.tween_callback(func(): _burst(to, Color("a09070"), 8, 0.3, 0.6))
	tw.tween_interval(1.2 if (miss and model != "") else 0.0)
	tw.tween_callback(node.queue_free)


## A one-shot spray of glowing particles.
func _burst(at: Vector3, color: Color, amount: int, life: float, speed := 2.0, delay := 0.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = false
	mesh.material = m
	p.mesh = mesh
	board.add_child(p)
	p.position = at
	var tw := p.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): p.emitting = true)
	tw.tween_interval(life + 0.3)
	tw.tween_callback(p.queue_free)


func _explosion(at: Vector3, delay: float) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.5
	sp.height = 3.0
	mi.mesh = sp
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color("ff8a2a")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.scale = Vector3.ONE * 0.1
	mi.visible = false
	board.add_child(mi)
	mi.position = at
	var tw := mi.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		mi.visible = true
		_burst(at, Color("ff9a3a"), 30, 0.7, 4.0)
		_shake = 0.3)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.25)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(mi.queue_free)


## A result that rises and fades above a fighter ("-2", "SAVED", "MISS"...). Several on one fighter stack up.
func _float(uid: int, text: String, color: Color, big := false) -> void:
	var f := b.fighter(uid)
	if f == null:
		return
	var stack: Array = _float_stack.get(uid, [-10.0, 0])
	var n := int(stack[1]) + 1 if _clock - float(stack[0]) < 0.8 else 0
	_float_stack[uid] = [_clock, n]
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 30 if big else 24
	l.outline_size = 8
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	board.add_child(l)
	# Beside the figure (to the camera's right) so it doesn't sit on the name label, stacking upward.
	var side := board.camera.global_basis.x.normalized() * (f.radius + 0.6) if board.camera != null else Vector3.ZERO
	var start := _chest(f) + side + Vector3(0, 0.1 + n * 0.5, 0)
	l.position = start
	var tw := l.create_tween()
	tw.tween_property(l, "position", start + Vector3(0, 1.0, 0), 1.3)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.3).set_delay(0.5)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 1.3).set_delay(0.5)
	tw.tween_callback(l.queue_free)
