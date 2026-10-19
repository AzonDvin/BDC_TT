class_name Geo
extends RefCounted
## Tabletop geometry in inches on the battlefield floor (x, y). The 3D view maps (x, y) to (x, 0, y).
## Distances between fighters use the closest points of their bases (p.7).

const MM_PER_INCH := 25.4
## Floats drift: a fighter placed exactly 1" away should count as 1" away.
const EPS := 0.001


static func radius_from_mm(base_mm: float) -> float:
	return base_mm / MM_PER_INCH / 2.0


static func base_gap(a: Vector2, ra: float, b: Vector2, rb: float) -> float:
	return maxf(0.0, a.distance_to(b) - ra - rb)


## Edge-to-edge distance that goes negative when bases overlap (use for overlap checks).
static func signed_gap(a: Vector2, ra: float, b: Vector2, rb: float) -> float:
	return a.distance_to(b) - ra - rb


static func within(a: Vector2, ra: float, b: Vector2, rb: float, inches: float) -> bool:
	return a.distance_to(b) - ra - rb <= inches + EPS


## "Wholly within X of point p": every part of the base is within X.
static func wholly_within_point(pos: Vector2, r: float, p: Vector2, inches: float) -> bool:
	return pos.distance_to(p) + r <= inches + EPS


static func path_length(path: PackedVector2Array) -> float:
	var t := 0.0
	for i in range(1, path.size()):
		t += path[i - 1].distance_to(path[i])
	return t


static func truncate(path: PackedVector2Array, max_len: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.is_empty():
		return out
	out.append(path[0])
	var left := max_len
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if seg <= left:
			out.append(path[i])
			left -= seg
		else:
			out.append(path[i - 1].move_toward(path[i], maxf(left, 0.0)))
			break
	return out


static func segment_crosses_polygon(a: Vector2, b: Vector2, poly: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
		return true
	return not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly).is_empty()


## The point on segment a-b nearest to where it first enters poly (or null).
static func first_entry(a: Vector2, b: Vector2, poly: PackedVector2Array) -> Variant:
	var parts := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly)
	if parts.is_empty():
		return null
	var best: Vector2 = parts[0][0]
	for part in parts:
		if a.distance_to(part[0]) < a.distance_to(best):
			best = part[0]
	return best


static func path_touches_polygon(path: PackedVector2Array, radius: float, poly: PackedVector2Array) -> bool:
	if path.size() == 1:
		path = PackedVector2Array([path[0], path[0] + Vector2(0.0001, 0)])
	var grown := Geometry2D.offset_polygon(poly, radius - EPS, Geometry2D.JOIN_ROUND) if radius > EPS else [poly]
	for g in grown:
		if Geometry2D.is_polygon_clockwise(g):
			continue  # holes from offsetting
		if not Geometry2D.intersect_polyline_with_polygon(path, g).is_empty():
			return true
		if Geometry2D.is_point_in_polygon(path[0], g) or Geometry2D.is_point_in_polygon(path[path.size() - 1], g):
			return true
	return false


## Closest approach between a moving base (radius r along path) and a stationary base at c (radius rc), edge to edge.
static func path_min_gap(path: PackedVector2Array, r: float, c: Vector2, rc: float) -> float:
	var best := INF
	if path.size() == 1:
		return base_gap(path[0], r, c, rc)
	for i in range(1, path.size()):
		var q := Geometry2D.get_closest_point_to_segment(c, path[i - 1], path[i])
		best = minf(best, q.distance_to(c) - r - rc)
	return best


static func segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < r - EPS


## Sample points on a base: the centre plus a ring just inside the edge.
static func base_samples(center: Vector2, radius: float, count := 8) -> PackedVector2Array:
	var pts := PackedVector2Array([center])
	for i in count:
		pts.append(center + Vector2.from_angle(TAU * i / count) * radius * 0.85)
	return pts


static func base_inside_board(pos: Vector2, r: float, size: Vector2) -> bool:
	return pos.x - r >= -EPS and pos.y - r >= -EPS and pos.x + r <= size.x + EPS and pos.y + r <= size.y + EPS


## Teardrop flame template (p.32): narrow end at `origin`, pointing along `dir`, length 8".
static func flame_polygon(origin: Vector2, dir: Vector2, length := 8.0, end_radius := 1.25) -> PackedVector2Array:
	var d := dir.normalized()
	var centre := origin + d * (length - end_radius)
	var steps := 12
	# Narrow point at the fighter, then a half-circle cap around the far end.
	var pts := PackedVector2Array([origin])
	for i in steps + 1:
		var t := -PI / 2.0 + PI * float(i) / steps
		pts.append(centre + d.rotated(t) * end_radius)
	return pts


static func circle_polygon(centre: Vector2, radius: float, steps := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		pts.append(centre + Vector2.from_angle(TAU * i / steps) * radius)
	return pts


## True if any part of a round base overlaps the polygon.
static func base_overlaps_polygon(pos: Vector2, r: float, poly: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(pos, poly):
		return true
	for i in poly.size():
		if Geometry2D.get_closest_point_to_segment(pos, poly[i], poly[(i + 1) % poly.size()]).distance_to(pos) < r - EPS:
			return true
	return false


static func rect_polygon(center: Vector2, size: Vector2, angle := 0.0) -> PackedVector2Array:
	var h := size / 2.0
	var corners := [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]
	var out := PackedVector2Array()
	for c in corners:
		out.append(center + (c as Vector2).rotated(angle))
	return out
