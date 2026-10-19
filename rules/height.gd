class_name Height
extends RefCounted
## Vertical rules (pp.16, 21-22): surfaces fighters can stand on, climbing, jumping, falling and impact damage.
## A fighter's position is (pos, elev): pos on the floor plan in inches, elev = height of the surface under it.

const LEVEL_EPS := 0.15
const CLIMB_REACH := 0.5     # climbers stay within 1/2" of the terrain (p.22)
const JUMP_MAX := 3.0        # max horizontal distance through the air (p.21)
const JUMP_UP_MAX := 1.0     # max upward distance while jumping


## Distance between two fighters' bases including vertical separation (p.7).
static func gap3(a_pos: Vector2, ra: float, a_elev: float, b_pos: Vector2, rb: float, b_elev: float) -> float:
	var h := maxf(0.0, a_pos.distance_to(b_pos) - ra - rb)
	var v := absf(a_elev - b_elev)
	return sqrt(h * h + v * v)


## Walkable surfaces: [{"poly", "elev", "piece"}], highest first.
static func surfaces(b: Battle) -> Array:
	var out: Array = []
	for t in b.terrain:
		if t.has_surface():
			out.append({"poly": t.polygon, "elev": t.height, "piece": t})
	out.sort_custom(func(x, y): return x["elev"] > y["elev"])
	return out


## Can a fighter's base centre stand at p on level elev? (The base may overhang edges: p.16.)
static func supports(b: Battle, p: Vector2, elev: float) -> bool:
	if elev <= LEVEL_EPS:
		for t in b.terrain:
			if t.blocks_movement() and Geometry2D.is_point_in_polygon(p, t.polygon):
				return false
		return true
	for s in surfaces(b):
		if absf(s["elev"] - elev) <= LEVEL_EPS and Geometry2D.is_point_in_polygon(p, s["poly"]):
			return true
	return false


## Is a base of radius r at p on level elev clear of walls, statues and ladders on that level?
static func base_clear(b: Battle, p: Vector2, r: float, elev: float) -> String:
	for t in b.terrain:
		var in_the_way := false
		if elev <= LEVEL_EPS:
			in_the_way = t.blocks_movement() or t.kind == "ladder"
		else:
			in_the_way = (t.kind == "high" or t.kind == "ladder") and t.height > elev + 0.3
		if in_the_way and Geo.base_overlaps_polygon(p, r, t.polygon):
			return t.name
	return ""


## Nearest spot to p (searching outward) where a base of radius r can stand on level elev.
static func nearest_clear(b: Battle, p: Vector2, r: float, elev: float) -> Vector2:
	if supports(b, p, elev) and base_clear(b, p, r, elev) == "":
		return p
	for ring in range(1, 40):
		var d := ring * 0.15
		for k in 16:
			var q := p + Vector2.from_angle(TAU * k / 16.0) * d
			if Geo.base_inside_board(q, r, b.board_size) and supports(b, q, elev) and base_clear(b, q, r, elev) == "":
				return q
	return p


## Levels a fighter could stand on at p (floor first if open, then surfaces).
static func levels_at(b: Battle, p: Vector2) -> Array:
	var out: Array = []
	if supports(b, p, 0.0):
		out.append(0.0)
	for s in surfaces(b):
		if Geometry2D.is_point_in_polygon(p, s["poly"]):
			out.append(float(s["elev"]))
	return out


## The highest level strictly below `elev` at p (what you land on when falling).
static func level_below(b: Battle, p: Vector2, elev: float) -> float:
	for s in surfaces(b):
		if s["elev"] < elev - LEVEL_EPS and Geometry2D.is_point_in_polygon(p, s["poly"]):
			return s["elev"]
	return 0.0


## The surface a fighter at (p, elev) stands on, or {} for the floor.
static func surface_at(b: Battle, p: Vector2, elev: float) -> Dictionary:
	if elev <= LEVEL_EPS:
		return {}
	for s in surfaces(b):
		if absf(s["elev"] - elev) <= LEVEL_EPS and Geometry2D.is_point_in_polygon(p, s["poly"]):
			return s
	return {}


static func edge_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p))
	return best


## Within 1/2" of an open platform edge, i.e. an edge with no wall rising above the platform (p.16).
static func near_open_edge(b: Battle, f: FighterState) -> bool:
	if f.elev <= LEVEL_EPS or f.has_kw("Fly"):
		return false
	var s := surface_at(b, f.pos, f.elev)
	if s.is_empty():
		return false
	var poly: PackedVector2Array = s["poly"]
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var q := Geometry2D.get_closest_point_to_segment(f.pos, a, c)
		if q.distance_to(f.pos) > f.radius + 0.5 + Geo.EPS:
			continue
		var enclosed := false
		for t in b.terrain:
			if t.kind == "high" and t.height > f.elev + 0.5 and t != s["piece"] and Geo.base_overlaps_polygon(q, 0.35, t.polygon):
				enclosed = true
		if not enclosed:
			return true
	return false


## Faces a fighter at p (radius r) can start climbing: high terrain or platform edges within 1/2" (p.22).
static func climbable_near(b: Battle, p: Vector2, r: float, ignore_piece = null) -> Array:
	var out: Array = []
	for t in b.terrain:
		if t.is_climbable() and t != ignore_piece and Geo.base_overlaps_polygon(p, r + CLIMB_REACH, t.polygon):
			out.append(t)
	return out


static func ladder_between(b: Battle, a: Vector2, la: float, c: Vector2, lc: float, r: float) -> TerrainPiece:
	var lo := minf(la, lc)
	var hi := maxf(la, lc)
	for t in b.terrain:
		if t.kind != "ladder":
			continue
		if absf(t.height - hi) > 0.5 or absf(t.base - lo) > 0.5:
			continue
		if Geo.base_overlaps_polygon(a, r + 0.35, t.polygon) and Geo.base_overlaps_polygon(c, r + 1.2, t.polygon):
			return t
	return null


## Impact damage (p.22): a dice per whole inch fallen, each 4+ is 1 damage.
static func impact(b: Battle, f: FighterState, drop: float, why := "a fall") -> void:
	var n := int(floor(drop))
	if n < 3:
		return
	var rolls := b.dice.roll_many(n)
	var dmg := 0
	for r in rolls:
		if r >= 4:
			dmg += 1
	b.log_line("%s drops %d\" (%s): impact rolls %s → %d damage." % [f.name, n, why, ", ".join(rolls.map(func(x): return str(x))), dmg])
	if dmg > 0:
		Combat.apply_damage(b, f, dmg, null, why)


## Falls off the platform by the shortest route and drops to the level below (pp.16, 21).
static func fall(b: Battle, f: FighterState) -> void:
	var s := surface_at(b, f.pos, f.elev)
	if s.is_empty():
		return
	var poly: PackedVector2Array = s["poly"]
	var best := Vector2.INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(f.pos, poly[i], poly[(i + 1) % poly.size()])
		if best == Vector2.INF or q.distance_to(f.pos) < best.distance_to(f.pos):
			best = q
	var out_dir := (best - f.pos).normalized() if best.distance_to(f.pos) > 0.01 else Vector2.RIGHT
	var land := best + out_dir * (f.radius + 0.1)
	var from := f.elev
	var lvl := level_below(b, land, from)
	land.x = clampf(land.x, f.radius, b.board_size.x - f.radius)
	land.y = clampf(land.y, f.radius, b.board_size.y - f.radius)
	land = nearest_clear(b, land, f.radius, lvl)
	f.pos = land
	f.elev = lvl
	b.log_line("%s falls from the platform!" % f.name)
	impact(b, f, from - lvl)


## After an action: fighters damaged near an open platform edge must pass an Initiative test or fall (p.16).
static func fall_checks(b: Battle) -> void:
	for f in b.fighters:
		if not f.statuses.get("fall_check", false):
			continue
		f.statuses.erase("fall_check")
		if not f.on_board() or not near_open_edge(b, f):
			continue
		var t := b.dice.test(int(f.stats["initiative"]))
		if t["pass"]:
			b.log_line("%s keeps their footing at the edge (rolled %d)." % [f.name, t["roll"]])
		else:
			b.log_line("%s loses their footing (rolled %d)." % [f.name, t["roll"]])
			fall(b, f)
