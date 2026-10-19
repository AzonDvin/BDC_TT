class_name TerrainPiece
extends RefCounted
## A terrain feature's footprint on the battlefield floor (p.16).
## kind: "low" (<1.5" tall: crossable at -1", obscures), "high" (walls >=1.5": blocks movement and sight;
## climbing comes later), "impassable" (statues, trees: never crossed), "deadly" (crossing deals d3 damage).

const HIGH_THRESHOLD := 1.5

var name := ""
var kind := "high"
var polygon := PackedVector2Array()
var height := 3.0


static func make(p_name: String, p_kind: String, p_polygon: PackedVector2Array, p_height: float) -> TerrainPiece:
	var t := TerrainPiece.new()
	t.name = p_name
	t.kind = p_kind
	t.polygon = p_polygon
	t.height = p_height
	return t


func blocks_movement() -> bool:
	return kind == "high" or kind == "impassable"


func is_low() -> bool:
	return kind == "low"


## Solid terrain the observer can't see over or through (simplified: everything tall enough to hide a fighter).
func blocks_sight(model_height: float) -> bool:
	return kind != "low" and height >= minf(HIGH_THRESHOLD, model_height)


func to_dict() -> Dictionary:
	var pts: Array = []
	for p in polygon:
		pts.append([p.x, p.y])
	return {"name": name, "kind": kind, "height": height, "polygon": pts}


static func from_dict(d: Dictionary) -> TerrainPiece:
	var pts := PackedVector2Array()
	for p in d["polygon"]:
		pts.append(Vector2(p[0], p[1]))
	return make(d["name"], d["kind"], pts, d["height"])
