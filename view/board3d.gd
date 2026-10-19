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
	var mi := MeshInstance3D.new()
	mi.mesh = extrude(t.polygon, t.height)
	var mat := StandardMaterial3D.new()
	match t.kind:
		"high":
			mat.albedo_color = Color(0.45, 0.41, 0.36)
		"low":
			mat.albedo_color = Color(0.36, 0.33, 0.28)
		"impassable":
			mat.albedo_color = Color(0.5, 0.48, 0.44)
		"deadly":
			mat.albedo_color = Color(0.5, 0.2, 0.15)
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)


## Extrudes a floor polygon (inches) up to `h` inches.
static func extrude(poly: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	var cw := Geometry2D.is_polygon_clockwise(poly)
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		st.set_normal(Vector3.UP)
		if cw:
			st.add_vertex(Vector3(a.x, h, a.y))
			st.add_vertex(Vector3(b.x, h, b.y))
			st.add_vertex(Vector3(c.x, h, c.y))
		else:
			st.add_vertex(Vector3(a.x, h, a.y))
			st.add_vertex(Vector3(c.x, h, c.y))
			st.add_vertex(Vector3(b.x, h, b.y))
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var n := Vector3(p1.y - p0.y, 0, -(p1.x - p0.x)).normalized()
		if not cw:
			n = -n
		var v0 := Vector3(p0.x, 0, p0.y)
		var v1 := Vector3(p1.x, 0, p1.y)
		var v2 := Vector3(p1.x, h, p1.y)
		var v3 := Vector3(p0.x, h, p0.y)
		st.set_normal(n)
		if cw:
			for v in [v0, v2, v1, v0, v3, v2]:
				st.add_vertex(v)
		else:
			for v in [v0, v1, v2, v0, v2, v3]:
				st.add_vertex(v)
	return st.commit()


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


func sync(selected := -1, active := -1, highlight := {}) -> void:
	for f in battle.fighters:
		var n: Node3D = fighter_nodes.get(f.uid)
		if n == null:
			n = _make_fighter(f)
			fighter_nodes[f.uid] = n
		n.visible = f.on_board()
		n.position = Vector3(f.pos.x, 0, f.pos.y)
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
		label.text = "%s\n♥%d/%d%s" % [f.name, f.life, f.max_life(), ("  " + " ".join(tags)) if not tags.is_empty() else ""]
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
		mi.position = Vector3(t["pos"].x, 0.13, t["pos"].y)
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
			var segs := n if l.get("closed", false) else n - 1
			for i in segs:
				var a := pts[i]
				var c := pts[(i + 1) % n]
				for off in [0.0, 0.04, -0.04]:
					var o: Vector2 = (c - a).orthogonal().normalized() * off
					overlay_mesh.surface_set_color(col)
					overlay_mesh.surface_add_vertex(Vector3(a.x + o.x, 0.08, a.y + o.y))
					overlay_mesh.surface_set_color(col)
					overlay_mesh.surface_add_vertex(Vector3(c.x + o.x, 0.08, c.y + o.y))
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
		mi.position.y = 0.02
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


func fighter_at(p: Vector2) -> FighterState:
	var best: FighterState = null
	for f in battle.fighters:
		if f.on_board() and f.pos.distance_to(p) <= f.radius + 0.25:
			if best == null or f.pos.distance_to(p) < best.pos.distance_to(p):
				best = f
	return best
