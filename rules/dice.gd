class_name Dice
extends RefCounted
## Seeded dice for Black Death City. One instance lives in the Battle; never use global randi() in rules code.
## Expressions follow the book (p.8): "d6", "2d6", "d3" (d6 halved rounding up), "d3+1", "d6x2", "3d6x5", "4".

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


func d6() -> int:
	return rng.randi_range(1, 6)


func d3() -> int:
	return (d6() + 1) / 2


func roll_many(count: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(d6())
	return out


## Roll-off: re-roll ties (p.8). Returns 0 or 1 (the winning side).
func roll_off() -> int:
	while true:
		var a := d6()
		var b := d6()
		if a != b:
			return 0 if a > b else 1
	return 0


## Initiative/Willpower test (p.11): pass on a roll equal to or less than the value.
func test(value: int) -> Dictionary:
	var r := d6()
	return {"roll": r, "pass": r <= value}


## Random direction for scattering (p.8), as a unit vector.
func direction() -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU)


func roll(expr: String) -> int:
	var p := parse(expr)
	var total := 0
	for i in p["count"]:
		total += d3() if p["sides"] == 3 else rng.randi_range(1, p["sides"])
	return total * p["mult"] + p["bonus"]


## {"count", "sides", "bonus", "mult"}. Plain integers have count 0.
static func parse(expr: String) -> Dictionary:
	var s := expr.replace(" ", "").to_lower()
	if s == "" or s == "-":
		return {"count": 0, "sides": 6, "bonus": 0, "mult": 1}
	if s.is_valid_int():
		return {"count": 0, "sides": 6, "bonus": s.to_int(), "mult": 1}
	var m := RegEx.create_from_string("^(\\d*)d(\\d+)(?:x(\\d+))?([+-]\\d+)?$").search(s)
	if m == null:
		push_error("Bad dice expression '%s'" % expr)
		return {"count": 0, "sides": 6, "bonus": 0, "mult": 1}
	return {
		"count": 1 if m.get_string(1) == "" else m.get_string(1).to_int(),
		"sides": m.get_string(2).to_int(),
		"mult": 1 if m.get_string(3) == "" else m.get_string(3).to_int(),
		"bonus": m.get_string(4).to_int(),
	}


## Adds a flat modifier to an expression, e.g. add("d3", 1) -> "d3+1".
static func add(expr: String, amount: int) -> String:
	if amount == 0:
		return expr
	var p := parse(expr)
	if p["count"] == 0:
		return str(p["bonus"] + amount)
	var base := ("%dd%d" % [p["count"], p["sides"]]) if p["count"] > 1 else "d%d" % p["sides"]
	if p["mult"] != 1:
		base += "x%d" % p["mult"]
	var b: int = p["bonus"] + amount
	return base + ("" if b == 0 else ("%+d" % b))


static func average(expr: String) -> float:
	var p := parse(expr)
	var per: float = 2.0 if p["sides"] == 3 else (p["sides"] + 1) / 2.0
	return (p["count"] * per) * p["mult"] + p["bonus"]
