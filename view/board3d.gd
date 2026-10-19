class_name Board3D
extends Node3D
## The 3D tabletop. One world unit = one inch; battle (x, y) maps to world (x, 0, y).
## Only displays the Battle; never changes it.

const FACTION_TINT := {
	"guild_mercenaries": Color("b89a6a"),
	"verminkin": Color("7d6a4f"),
	"death_covens": Color("9a93ad"),
	"blighted_cloister": Color("7f9a5a"),
}

var battle: Battle
var fighter_nodes := {}
var terrain_nodes: Array = []
var token_root: Node3D
var overlay_mesh := ImmediateMesh.new()
var fill_root: Node3D
var cam_pivot: Node3D
var camera: Camera3D
var yaw := -0.6
var pitch := 0.95
var dist := 42.0
var _line_mat: StandardMaterial3D


func build(b: Battle) -> void:
	battle = b
	for c in get_children():
		c.queue_free()
	fighter_nodes.clear()
	terrain_nodes.clear()
	_environment()
	_ground()
	for t in b.terrain:
		_terrain(t)
	token_root = Node3D.new()
	add_child(token_root)
	fill_root = Node3D.new()
	add_child(fill_root)
	var ov := MeshInstance3D.new()
	ov.mesh = overlay_mesh
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.no_depth_test = true
	_line_mat.render_priority = 10
	ov.material_override = _line_mat
	ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ov)
	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(b.board_size.x / 2.0, 0, b.board_size.y / 2.0)
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.fov = 50
	camera.far = 400
	cam_pivot.add_child(camera)
	camera.make_current()
	_update_camera()
	sync()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.13, 0.12)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	add_child(sun)


func _ground() -> void:
	var size := battle.board_size
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = 7
	for y in 512:
		for x in 512:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var cobble := absf(sin(x * 0.55) * sin(y * 0.55)) * 0.08
			var c := Color(0.23, 0.22, 0.2).lerp(Color(0.32, 0.3, 0.26), n) - Color(cobble, cobble, cobble)
			img.set_pixel(x, y, c)
	var px_per_inch := 512.0 / size.x
	for i in int(size.x) + 1:
		var p := int(round(i * px_per_inch))
		if i % 6 != 0 and i % 2 != 0:
			continue
		var col := Color(0.46, 0.41, 0.31) if i % 6 == 0 else Color(0.29, 0.28, 0.25)
		for k in 512:
			if p < 512:
				img.set_pixel(p, k, col)
				img.set_pixel(k, p, col)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.95
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(size.x / 2.0, 0, size.y / 2.0)
	add_child(mi)
	# Table edge
	var edge := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x + 2, 0.6, size.y + 2)
	edge.mesh = bm
	edge.position = Vector3(size.x / 2.0, -0.31, size.y / 2.0)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.16, 0.1, 0.06)
	edge.material_override = em
	add_child(edge)


func _terrain(t: TerrainPiece) -> void:
	var root := Node3D.new()
	root.set_meta("piece", t)
	add_child(root)
	terrain_nodes.append(root)
	var stone := _textured(stone_texture(), Color(0.78, 0.74, 0.68), 0.5)
	match t.kind:
		"high":
			_add_extrusion(root, t.polygon, 0.0, t.height, stone)
		"low":
			_add_extrusion(root, t.polygon, 0.0, t.height, _textured(stone_texture(), Color(0.6, 0.56, 0.5), 0.8))
		"impassable":
			_add_extrusion(root, t.polygon, 0.0, t.height, _textured(stone_texture(), Color(0.9, 0.88, 0.84), 0.9))
		"deadly":
			_add_extrusion(root, t.polygon, 0.0, maxf(t.height, 0.1), _mat(Color(0.5, 0.2, 0.15)))
		"platform":
			_add_extrusion(root, t.polygon, t.height - TerrainPiece.SLAB, t.height, _textured(plank_texture(), Color(0.85, 0.8, 0.75), 0.6))
		"door":
			_add_extrusion(root, t.polygon, t.lintel, t.height, stone)
			if t.closed:
				_add_extrusion(root, _shrink(t.polygon, 0.15), 0.0, t.lintel, _mat(Color(0.3, 0.2, 0.12)))
		"window":
			_add_extrusion(root, t.polygon, 0.0, t.sill, stone)
			_add_extrusion(root, t.polygon, t.lintel, t.height, stone)
		"ladder":
			_ladder(root, t)


static var _stone_tex: ImageTexture
static var _plank_tex: ImageTexture


## A double-sided material with a texture projected from all three axes (no UVs needed on extruded meshes).
## `scale` = texture repeats per inch.
func _textured(tex: Texture2D, tint: Color, scale: float) -> StandardMaterial3D:
	var m := _mat(tint)
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


## Procedural dressed-stone bricks: 4 courses x 2 bricks per tile, mortar lines, per-brick tone and grit.
static func stone_texture() -> ImageTexture:
	if _stone_tex != null:
		return _stone_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.seed = 11
	var rows := 4
	var bh := n / rows
	var bw := n / 2
	for y in n:
		var row := y / bh
		var off := (bw / 2) if row % 2 == 1 else 0
		for x in n:
			var xx := (x + off) % n
			var brick := Vector2i(xx / bw, row)
			var tone := 0.42 + 0.1 * sin(brick.x * 12.9898 + brick.y * 78.233) * 0.5
			var mortar := (y % bh) < 4 or (xx % bw) < 4
			var g := noise.get_noise_2d(x, y) * 0.06
			var c := Color(tone + g, tone * 0.93 + g, tone * 0.85 + g)
			if mortar:
				c = Color(0.2, 0.19, 0.17)
			elif (y % bh) < 7 or (xx % bw) < 7:
				c = c.darkened(0.18)  # bevel so each brick reads as raised
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_stone_tex = ImageTexture.create_from_image(img)
	return _stone_tex


## Procedural floorboards for upper floors.
static func plank_texture() -> ImageTexture:
	if _plank_tex != null:
		return _plank_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.15
	noise.seed = 5
	for y in n:
		var board := y / 16
		for x in n:
			var grain := noise.get_noise_2d(x * 0.15, y * 2.0) * 0.08
			var tone := 0.36 + 0.04 * sin(board * 3.7)
			var c := Color(tone + grain, tone * 0.72 + grain, tone * 0.5 + grain)
			if y % 16 < 2 or (x + board * 37) % n < 2:
				c = Color(0.12, 0.08, 0.05)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_plank_tex = ImageTexture.create_from_image(img)
	return _plank_tex


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # extruded polygons come in either winding
	return m


func _add_extrusion(root: Node3D, poly: PackedVector2Array, y0: float, y1: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = extrude(poly, y1 - y0)
	mi.position.y = y0
	mi.material_override = mat
	root.add_child(mi)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()


static func _shrink(poly: PackedVector2Array, k: float) -> PackedVector2Array:
	var c := _centroid(poly)
	var out := PackedVector2Array()
	for p in poly:
		out.append(c + (p - c) * (1.0 - k))
	return out


## Two rails and rungs along the ladder footprint's long side, from `base` up to `height`.
func _ladder(root: Node3D, t: TerrainPiece) -> void:
	var poly := t.polygon
	var e0 := poly[1] - poly[0]
	var e1 := poly[2] - poly[1]
	var long := e0 if e0.length() >= e1.length() else e1
	var c := _centroid(poly)
	var half := long / 2.0 * 0.8
	var wood := _mat(Color(0.5, 0.36, 0.2))
	for s in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, t.height - t.base, 0.1)
		rail.mesh = bm
		var p: Vector2 = c + half * s
		rail.position = Vector3(p.x, t.base + (t.height - t.base) / 2.0, p.y)
		rail.material_override = wood
		root.add_child(rail)
	var y := t.base + 0.4
	while y < t.height:
		var rung := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(long.length() * 0.8, 0.06, 0.06)
		rung.mesh = rm
		rung.position = Vector3(c.x, y, c.y)
		rung.rotation.y = -long.angle()
		rung.material_override = wood
		root.add_child(rung)
		y += 0.5


## Extrudes a floor polygon (inches) up to `h` inches: a top cap and outward-facing sides with correct normals,
## so walls catch the light (materials are double-sided, so triangle winding doesn't matter).
static func extrude(poly: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= poly.size()
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		st.set_normal(Vector3.UP)
		for k in [0, 2, 1]:
			var q := poly[tris[i + k]]
			st.add_vertex(Vector3(q.x, h, q.y))
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var edge := p1 - p0
		var n2 := Vector2(edge.y, -edge.x).normalized()
		if n2.dot((p0 + p1) / 2.0 - centroid) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0, n2.y)
		var v0 := Vector3(p0.x, 0, p0.y)
		var v1 := Vector3(p1.x, 0, p1.y)
		var v2 := Vector3(p1.x, h, p1.y)
		var v3 := Vector3(p0.x, h, p0.y)
		for v in [v0, v2, v1, v0, v3, v2]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


## Re-creates the terrain meshes after the terrain list changed (terrain editor).
func rebuild_terrain() -> void:
	for n in terrain_nodes:
		n.queue_free()
	terrain_nodes.clear()
	for t in battle.terrain:
		_terrain(t)


# --- Fighters & tokens --------------------------------------------------------------------------

func _make_fighter(f: FighterState) -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = f.radius
	cyl.bottom_radius = f.radius
	cyl.height = 0.12
	base.mesh = cyl
	base.position.y = 0.06
	var bm := StandardMaterial3D.new()
	bm.albedo_color = App.player_color(f.player)
	base.material_override = bm
	root.add_child(base)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = f.radius * 0.5
	cap.height = maxf(f.height, cap.radius * 2.0 + 0.1)
	body.mesh = cap
	body.position.y = 0.12 + cap.height / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FACTION_TINT.get(f.faction, Color.GRAY)
	body.material_override = mat
	body.name = "Body"
	root.add_child(body)
	var head_band := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = cap.radius * 0.9
	tor.outer_radius = cap.radius * 1.15
	head_band.mesh = tor
	head_band.position.y = 0.12 + cap.height * 0.85
	head_band.material_override = bm
	root.add_child(head_band)
	var ring := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = f.radius + 0.06
	rt.outer_radius = f.radius + 0.2
	ring.mesh = rt
	ring.position.y = 0.05
	var rm := StandardMaterial3D.new()
	rm.albedo_color = App.GOLD
	rm.emission_enabled = true
	rm.emission = App.GOLD
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.name = "Ring"
	ring.visible = false
	root.add_child(ring)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.016
	label.font_size = 34
	label.outline_size = 10
	label.position.y = 0.4 + cap.height + 0.5
	label.name = "Label"
	root.add_child(label)
	add_child(root)
	return root


var _moving := {}                # uid -> Tween while a fighter slides along its move


## Slides a fighter's model through the given world points over `seconds` (sync leaves it alone meanwhile).
func animate_path(uid: int, pts: Array, seconds: float) -> void:
	var n: Node3D = fighter_nodes.get(uid)
	if n == null or pts.size() < 2:
		return
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i - 1] as Vector3).distance_to(pts[i])
	if total < 0.05:
		return
	if _moving.has(uid):
		(_moving[uid] as Tween).kill()
	n.position = pts[0]
	var tw := create_tween()
	for i in range(1, pts.size()):
		tw.tween_property(n, "position", pts[i], seconds * (pts[i - 1] as Vector3).distance_to(pts[i]) / total)
	_moving[uid] = tw
	tw.finished.connect(func(): _moving.erase(uid))


func sync(selected := -1, active := -1, highlight := {}) -> void:
	for f in battle.fighters:
		var n: Node3D = fighter_nodes.get(f.uid)
		if n == null:
			n = _make_fighter(f)
			fighter_nodes[f.uid] = n
		n.visible = f.on_board()
		if not _moving.has(f.uid):
			n.position = Vector3(f.pos.x, f.elev, f.pos.y)
		var ring: MeshInstance3D = n.get_node("Ring")
		ring.visible = f.uid == selected or f.uid == active or highlight.has(f.uid)
		var rm := ring.material_override as StandardMaterial3D
		var rc: Color = highlight.get(f.uid, App.GOLD if f.uid != active else Color("f2e6a0"))
		rm.albedo_color = rc
		rm.emission = rc
		var body: MeshInstance3D = n.get_node("Body")
		var bmat := body.material_override as StandardMaterial3D
		var tint: Color = FACTION_TINT.get(f.faction, Color.GRAY)
		bmat.albedo_color = tint.darkened(0.55) if f.activated and f.uid != active else tint
		var label: Label3D = n.get_node("Label")
		var tags: PackedStringArray = []
		if f.statuses.get("hidden", false):
			tags.append("hidden")
		if f.statuses.get("poisoned", false):
			tags.append("poison")
		if f.treasure > 0:
			tags.append("$")
		if "hit" in f.marks:
			tags.append("HIT")
		if f.statuses.get("drawn_power", false):
			tags.append("power")
		label.text = "%s\n♥%d/%d%s" % [UI.tagged_name(f), f.life, f.max_life(), ("  " + " ".join(tags)) if not tags.is_empty() else ""]
		label.modulate = App.player_color(f.player).lightened(0.35) if not f.is_bloodied() else Color("ff8060")
	for c in token_root.get_children():
		c.queue_free()
	for t in battle.tokens:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.5
		cyl.height = 0.25
		mi.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("e0b84a")
		m.metallic = 0.8
		m.roughness = 0.3
		mi.material_override = m
		mi.position = Vector3(t["pos"].x, float(t.get("elev", 0.0)) + 0.13, t["pos"].y)
		token_root.add_child(mi)


# --- Overlays -----------------------------------------------------------------------------------

## lines: [{"pts": PackedVector2Array, "color": Color, "closed": bool}]; fills: [{"poly": PackedVector2Array, "color": Color}]
func draw_overlay(lines: Array, fills: Array = []) -> void:
	overlay_mesh.clear_surfaces()
	var any := false
	for l in lines:
		if (l["pts"] as PackedVector2Array).size() >= 2:
			any = true
	if any:
		overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
		for l in lines:
			var pts: PackedVector2Array = l["pts"]
			var col: Color = l["color"]
			var n := pts.size()
			var lv: Array = l.get("levels", [])
			var z0: float = l.get("z", 0.0)
			var segs := n if l.get("closed", false) else n - 1
			for i in segs:
				var a := pts[i]
				var c := pts[(i + 1) % n]
				var za: float = (float(lv[i]) if i < lv.size() else z0) + 0.08
				var zc: float = (float(lv[(i + 1) % n]) if (i + 1) % n < lv.size() else z0) + 0.08
				for off in [0.0, 0.04, -0.04]:
					var o: Vector2 = (c - a).orthogonal().normalized() * off
					overlay_mesh.surface_set_color(col)
					overlay_mesh.surface_add_vertex(Vector3(a.x + o.x, za, a.y + o.y))
					overlay_mesh.surface_set_color(col)
					overlay_mesh.surface_add_vertex(Vector3(c.x + o.x, zc, c.y + o.y))
		overlay_mesh.surface_end()
	for c in fill_root.get_children():
		c.queue_free()
	for f in fills:
		var poly: PackedVector2Array = f["poly"]
		if poly.size() < 3:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = extrude(poly, 0.03)
		var m := StandardMaterial3D.new()
		m.albedo_color = f["color"]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 0.02 + float(f.get("z", 0.0))
		fill_root.add_child(mi)


static func circle(c: Vector2, r: float, steps := 48) -> PackedVector2Array:
	return Geo.circle_polygon(c, r, steps)


# --- Camera --------------------------------------------------------------------------------------

func _update_camera() -> void:
	if camera == null:
		return
	pitch = clampf(pitch, 0.25, 1.45)
	dist = clampf(dist, 6.0, 90.0)
	var off := Vector3(0, sin(pitch), cos(pitch)) * dist
	off = off.rotated(Vector3.UP, yaw)
	camera.position = off
	camera.look_at(cam_pivot.global_position, Vector3.UP)


func orbit(dx: float, dy: float) -> void:
	yaw -= dx * 0.008
	pitch += dy * 0.006
	_update_camera()


func zoom(factor: float) -> void:
	dist *= factor
	_update_camera()


func pan(screen_delta: Vector2) -> void:
	var right := camera.global_transform.basis.x
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	right.y = 0
	right = right.normalized()
	var k := dist * 0.0015
	cam_pivot.position += (-right * screen_delta.x + fwd * screen_delta.y) * k
	cam_pivot.position.x = clampf(cam_pivot.position.x, -5, battle.board_size.x + 5)
	cam_pivot.position.z = clampf(cam_pivot.position.z, -5, battle.board_size.y + 5)


func focus(p: Vector2) -> void:
	cam_pivot.position = Vector3(p.x, 0, p.y)


## The table point under the mouse, in inches, or Vector2.INF.
func ground_point(screen: Vector2) -> Vector2:
	if camera == null:
		return Vector2.INF
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector2.INF
	var t := -from.y / dir.y
	if t < 0:
		return Vector2.INF
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


## The point under the mouse on the topmost surface the ray meets: Vector3(x, y, level) in inches,
## or Vector3.INF. With floor_only, roofs and upper floors are ignored (to aim at the ground beneath them).
func surface_point(screen: Vector2, floor_only := false) -> Vector3:
	if camera == null:
		return Vector3.INF
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var best_t := INF
	var best := Vector3.INF
	var levels: Array = [{"poly": PackedVector2Array(), "elev": 0.0}]
	if not floor_only:
		levels.append_array(Height.surfaces(battle))
	for s in levels:
		var e: float = s["elev"]
		if absf(dir.y) < 0.0001:
			continue
		var t := (e - from.y) / dir.y
		if t < 0 or t >= best_t:
			continue
		var hit := from + dir * t
		var p := Vector2(hit.x, hit.z)
		var poly: PackedVector2Array = s["poly"]
		if poly.is_empty():
			if p.x < -2 or p.y < -2 or p.x > battle.board_size.x + 2 or p.y > battle.board_size.y + 2:
				continue
		elif not Geometry2D.is_point_in_polygon(p, poly):
			continue
		best_t = t
		best = Vector3(p.x, p.y, e)
	return best


## The fighter drawn nearest the mouse (within ~30 px), whatever its height.
func fighter_at_screen(screen: Vector2) -> FighterState:
	var best: FighterState = null
	var best_d := 30.0
	for f in battle.fighters:
		if not f.on_board():
			continue
		var w := Vector3(f.pos.x, f.elev + f.height * 0.5, f.pos.y)
		if camera.is_position_behind(w):
			continue
		var d := camera.unproject_position(w).distance_to(screen)
		if d < best_d:
			best_d = d
			best = f
	return best


func fighter_at(p: Vector2) -> FighterState:
	var best: FighterState = null
	for f in battle.fighters:
		if f.on_board() and f.pos.distance_to(p) <= f.radius + 0.25:
			if best == null or f.pos.distance_to(p) < best.pos.distance_to(p):
				best = f
	return best
