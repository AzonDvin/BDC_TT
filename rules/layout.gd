class_name Layout
extends RefCounted
## Saved battlefield layouts made in the terrain editor: {"version", "name", "board": [w, h], "pieces": [TerrainPiece dicts]}.

const DIR := "user://layouts/"


static func save(name: String, pieces: Array, board := Vector2(36, 36)) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var ds: Array = []
	for t in pieces:
		ds.append(t.to_dict())
	var f := FileAccess.open(DIR + name.validate_filename() + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "name": name, "board": [board.x, board.y], "pieces": ds}, "  "))
	return OK


static func load_file(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func pieces_of(d: Dictionary) -> Array:
	var out: Array = []
	for p in d.get("pieces", []):
		out.append(TerrainPiece.from_dict(p))
	return out


static func saved_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(DIR + f)
	return out
