class_name TerrainPiece
extends RefCounted
## A terrain feature (p.16). `polygon` is its footprint on the battlefield floor in inches.
## kind:
##   "high"       walls >= 1.5" (block movement and sight; climbable). Big enough blocks (>= 1"x1") have a walkable roof.
##   "low"        rubble, low walls (< 1.5"): crossed at -1", hide fighters' lower bodies.
##   "impassable" statues, trees, sloped roofs: never crossed or climbed.
##   "deadly"     crossing deals d3 damage.
##   "platform"   an upper floor slab whose top is at `height`; fighters walk on it and underneath it.
##   "ladder"     joins the floor (or `base`) to a platform at `height`: climbing it costs 1".
##   "door"       an opening in a wall (crossed at -1"); `closed` doors block sight and only allow Normal moves.
##   "window"     an opening in a wall with a sill: crossed at -1"; sight passes between `sill` and `lintel`.

const HIGH_THRESHOLD := 1.5
const SLAB := 0.25

var name := ""
var kind := "high"
var polygon := PackedVector2Array()
var height := 3.0
var base := 0.0          # ladders: bottom level
var closed := false      # doors
var sill := 1.0          # windows
var lintel := 2.6        # windows and doors: top of the opening
var group := 0           # pieces placed together (a ruin's walls, floor and ladder) move together in the editor


static func make(p_name: String, p_kind: String, p_polygon: PackedVector2Array, p_height: float) -> TerrainPiece:
	var t := TerrainPiece.new()
	t.name = p_name
	t.kind = p_kind
	t.polygon = p_polygon
	t.height = p_height
	return t


## Blocks fighters moving on the battlefield floor.
func blocks_movement() -> bool:
	return kind == "high" or kind == "impassable"


func is_low() -> bool:
	return kind == "low"


## Crossing it costs 1" of movement (low terrain, doors, windows: p.21).
func costs_crossing() -> bool:
	return kind == "low" or kind == "door" or kind == "window"


func is_climbable() -> bool:
	return kind == "high" or kind == "platform"


## A walkable top surface: platforms, and high blocks with a roof at least 1" by 1" (p.16).
func has_surface() -> bool:
	if kind == "platform":
		return true
	if kind != "high":
		return false
	var r := bounds()
	return r.size.x >= 1.0 and r.size.y >= 1.0 and _area() >= 1.0


## Height ranges (from, to) of solid material that sight lines can't pass through.
func solid_bands() -> Array:
	match kind:
		"high", "low", "impassable":
			return [Vector2(0.0, height)]
		"platform":
			return [Vector2(height - SLAB, height)]
		"door":
			return [Vector2(0.0, height)] if closed else [Vector2(lintel, height)]
		"window":
			return [Vector2(0.0, sill), Vector2(lintel, height)]
	return []


func bounds() -> Rect2:
	var r := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		r = r.expand(p)
	return r


func _area() -> float:
	var a := 0.0
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) / 2.0


func to_dict() -> Dictionary:
	var pts: Array = []
	for p in polygon:
		pts.append([p.x, p.y])
	return {"name": name, "kind": kind, "height": height, "polygon": pts, "base": base, "closed": closed, "sill": sill, "lintel": lintel, "group": group}


static func from_dict(d: Dictionary) -> TerrainPiece:
	var pts := PackedVector2Array()
	for p in d["polygon"]:
		pts.append(Vector2(p[0], p[1]))
	var t := make(d["name"], d["kind"], pts, d["height"])
	t.base = d.get("base", 0.0)
	t.closed = d.get("closed", false)
	t.sill = d.get("sill", 1.0)
	t.lintel = d.get("lintel", 2.6)
	t.group = int(d.get("group", 0))
	return t


func duplicate_piece() -> TerrainPiece:
	return from_dict(to_dict())
