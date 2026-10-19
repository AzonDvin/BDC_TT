class_name AINav
extends RefCounted
## Pathfinding for the computer player on the battlefield floor: a 0.5" grid, Dijkstra from the fighter,
## then the path is straightened and checked with Movement.evaluate (the rules always have the last word).

const CELL := 0.5

var b: Battle
var f: FighterState
var w := 0
var h := 0
var blocked := PackedByteArray()
var cost := PackedFloat32Array()
var parent := PackedInt32Array()


## kind: "normal"/"run" keep more than 1" from enemies; "charge"/"disengage" may approach them.
static func build(battle: Battle, fighter: FighterState, kind: String, max_cost: float) -> AINav:
	var nav := AINav.new()
	nav.b = battle
	nav.f = fighter
	nav.w = int(battle.board_size.x / CELL)
	nav.h = int(battle.board_size.y / CELL)
	nav._mark_blocked(kind)
	nav._dijkstra(max_cost)
	return nav


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, w - 1), clampi(int(p.y / CELL), 0, h - 1))


func center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


var _kind := "normal"
var _others: Array = []
var _boxes: Array = []          # [Rect2 grown by the base radius, TerrainPiece] for pieces that block the floor


func _mark_blocked(kind: String) -> void:
	_kind = kind
	blocked.resize(w * h)
	blocked.fill(255)           # 255 = not computed yet; cells are checked lazily as the search reaches them
	for o in b.on_board():
		if o != f and absf(o.elev) < 1.0:
			_others.append(o)
	for t in b.terrain:
		if t.blocks_movement() or t.kind == "ladder":
			_boxes.append([t.bounds().grow(f.radius + 0.05), t])


func is_blocked(i: int) -> bool:
	if blocked[i] == 255:
		var p := center(Vector2i(i % w, i / w))
		var r := f.radius
		var bad := not Geo.base_inside_board(p, r, b.board_size)
		if not bad:
			for bx in _boxes:
				if (bx[0] as Rect2).has_point(p) and Geo.base_overlaps_polygon(p, r, bx[1].polygon):
					bad = true
					break
		if not bad:
			for o in _others:
				var gap := Geo.signed_gap(p, r, o.pos, o.radius)
				if gap < 0.02 or (o.player != f.player and _kind in ["normal", "run"] and gap < 1.0):
					bad = true
					break
		blocked[i] = 1 if bad else 0
	return blocked[i] == 1


func _crossing_extra(a: Vector2, c: Vector2) -> float:
	var extra := 0.0
	for t in b.terrain:
		if t.costs_crossing() and not Geometry2D.is_point_in_polygon(a, t.polygon) and Geometry2D.is_point_in_polygon(c, t.polygon):
			extra += 1.0
	return extra


func _dijkstra(max_cost: float) -> void:
	cost.resize(w * h)
	parent.resize(w * h)
	cost.fill(INF)
	parent.fill(-1)
	var start := cell_of(f.pos)
	cost[idx(start)] = 0.0
	blocked[idx(start)] = 0
	_hc = PackedFloat32Array([0.0])
	_hi = PackedInt32Array([idx(start)])
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var crossing_terrain := false
	for t in b.terrain:
		if t.costs_crossing():
			crossing_terrain = true
	while _hc.size() > 0:
		var cc := _hc[0]
		var ci := _hi[0]
		_heap_pop()
		if cc > cost[ci] + 0.0001:
			continue
		var c := Vector2i(ci % w, ci / w)
		for d in dirs:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var ni := idx(n)
			if is_blocked(ni):
				continue
			if d.x != 0 and d.y != 0 and (is_blocked(idx(Vector2i(c.x + d.x, c.y))) or is_blocked(idx(Vector2i(c.x, c.y + d.y)))):
				continue
			var step := CELL * (1.41421 if d.x != 0 and d.y != 0 else 1.0)
			var nc := cc + step
			if crossing_terrain:
				nc += _crossing_extra(center(c), center(n))
			if nc < cost[ni] and nc <= max_cost:
				cost[ni] = nc
				parent[ni] = ci
				_heap_push(nc, ni)


var _hc := PackedFloat32Array()
var _hi := PackedInt32Array()


func _heap_push(c: float, i: int) -> void:
	_hc.append(c)
	_hi.append(i)
	var k := _hc.size() - 1
	while k > 0:
		var p := (k - 1) / 2
		if _hc[p] <= _hc[k]:
			break
		var tc := _hc[p]
		_hc[p] = _hc[k]
		_hc[k] = tc
		var ti := _hi[p]
		_hi[p] = _hi[k]
		_hi[k] = ti
		k = p


func _heap_pop() -> void:
	var last := _hc.size() - 1
	_hc[0] = _hc[last]
	_hi[0] = _hi[last]
	_hc.resize(last)
	_hi.resize(last)
	var k := 0
	while true:
		var l := 2 * k + 1
		var r := l + 1
		var m := k
		if l < _hc.size() and _hc[l] < _hc[m]:
			m = l
		if r < _hc.size() and _hc[r] < _hc[m]:
			m = r
		if m == k:
			break
		var tc := _hc[m]
		_hc[m] = _hc[k]
		_hc[k] = tc
		var ti := _hi[m]
		_hi[m] = _hi[k]
		_hi[k] = ti
		k = m


func reachable(c: Vector2i) -> bool:
	return cost[idx(c)] < INF


## Cells reachable within `limit` inches (sampled every `stride` cells to keep scoring cheap).
func reachable_cells(limit: float, stride := 2) -> Array:
	var out: Array = []
	for y in range(0, h, stride):
		for x in range(0, w, stride):
			var i := y * w + x
			if cost[i] <= limit:
				out.append(Vector2i(x, y))
	return out


## Raw cell path from the fighter to cell c, as floor points (first point = fighter position).
func path_to(c: Vector2i) -> PackedVector2Array:
	var pts: Array = []
	var i := idx(c)
	while i >= 0:
		pts.push_front(center(Vector2i(i % w, i / w)))
		i = parent[i]
	var out := PackedVector2Array([f.pos])
	for k in range(1, pts.size()):
		out.append(pts[k])
	return out


## Straightens a cell path: keeps a point only where a straight leg would hit something.
func simplify(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	var out := PackedVector2Array([path[0]])
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1 and not _clear_leg(path[i], path[j]):
			j -= 1
		out.append(path[j])
		i = j
	return out


func _clear_leg(a: Vector2, c: Vector2) -> bool:
	var n := maxi(1, int(a.distance_to(c) / (CELL * 0.5)))
	for k in range(1, n):
		if is_blocked(idx(cell_of(a.lerp(c, float(k) / n)))):
			return false
	return true
