class_name BoardView
extends Node3D
## 보드 모양(코드로 만듦) + 타는 캐릭터(Kenney Platformer Kit) + 효과. 앞은 +Z.

const KIT := "res://assets/kit/%s.glb"
const HOVER := 0.42          ## 땅에서 떠 있는 높이

var deck: Node3D            # 보드 (기울고 돈다)
var spin_node: Node3D       # 묘기로 도는 부분 (보드 + 캐릭터)
const PIVOT := Vector3(0, 0.75, 0)   # 구르기 축 (몸 가운데쯤)
var rider: Node3D
var anim: AnimationPlayer
var anim_now := ""
var jets: Array[Node3D] = []
var flames: Array[MeshInstance3D] = []
var trail: CPUParticles3D
var boost_fx: CPUParticles3D
var spray: CPUParticles3D
var stars_fx: CPUParticles3D
var dizzy: Node3D
var glow: MeshInstance3D
var shadow: MeshInstance3D
var bubble: MeshInstance3D
var tag: Label3D
var blen := 1.9
var bwid := 0.62
var roll := 0.0
var pitch := 0.0
var bob := 0.0
var _prev_judge := {}
var _glow_col := Color.WHITE
var snow := false

static var _mats := {}

static func mat(c: Color, emit := false, unshaded := false, metal := 0.0) -> StandardMaterial3D:
	var key := "%s%s%s%s" % [c.to_html(), emit, unshaded, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.45 if metal == 0.0 else 0.25
	m.metallic = metal
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.2
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

static func vc_mat(metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "vc%s%s" % [metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35 if metal > 0.0 else 0.5
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

## 보드 윤곽 (위에서 본 2D, x 옆 / y 앞). 꼬리 모양: round 둥글게, split 가운데 홈, fork 두 갈래
static func outline(L: float, W: float, nose: float, tail: String) -> PackedVector2Array:
	var hw := W * 0.5
	var right := PackedVector2Array()
	var n := 22
	# 앞쪽 반 (오른쪽 가장자리: 꼬리 → 코)
	for i in n + 1:
		var u := -1.0 + 2.0 * float(i) / n
		var w := 1.0
		if u > 0.35:
			var q := (u - 0.35) / 0.65
			w = pow(maxf(0.0, 1.0 - q * q), 0.35 + nose * 0.9)
		elif u < -0.62 and tail == "round":
			var q2 := (-u - 0.62) / 0.38
			w = sqrt(maxf(0.0, 1.0 - q2 * q2))
		elif u < -0.75:
			w = 1.0 - (-u - 0.75) * 0.6
		w *= 1.0 - 0.08 * absf(u)   # 가운데가 살짝 넓게
		right.append(Vector2(hw * w, u * L * 0.5))
	var pts := PackedVector2Array()
	# 꼬리 끝
	match tail:
		"split":
			pts.append(Vector2(0, -L * 0.5 + L * 0.09))
		"fork":
			pts.append(Vector2(0, -L * 0.5 + L * 0.2))
			pts.append(Vector2(hw * 0.32, -L * 0.5 - L * 0.02))
		_:
			pass
	for p in right:
		if p.x > 0.001 or p.y > 0.0:
			pts.append(p)
	# 왼쪽 (코 → 꼬리)
	for i in range(right.size() - 1, -1, -1):
		var p2 := right[i]
		if p2.x > 0.001:
			pts.append(Vector2(-p2.x, p2.y))
	if tail == "fork":
		pts.append(Vector2(-hw * 0.32, -L * 0.5 - L * 0.02))
	return pts

## 윤곽을 두께 있게 (위·아래·옆). top_col = 위 색 함수(Vector2 → Color)
static func extrude(pts: PackedVector2Array, thick: float, top_col: Callable, side_col: Color, bottom_col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(pts)
	var y1 := thick * 0.5
	var y0 := -thick * 0.5
	for i in range(0, tris.size(), 3):
		var a := pts[tris[i]]
		var b := pts[tris[i + 1]]
		var c := pts[tris[i + 2]]
		# 위 (반시계로 보이게 순서 맞추기)
		var cross := (b - a).cross(c - a)
		var tri := [a, c, b] if cross < 0.0 else [a, b, c]
		for p in tri:
			st.set_color(top_col.call(p))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y1, p.y))
		for j in [0, 2, 1]:
			var p2: Vector2 = tri[j]
			st.set_color(bottom_col)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(Vector3(p2.x, y0, p2.y))
	var n := pts.size()
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	for i in n:
		var a2 := pts[i]
		var b2 := pts[(i + 1) % n]
		var d := (b2 - a2).normalized()
		var nr := Vector3(d.y, 0, -d.x) * (1.0 if area < 0.0 else -1.0)
		var quad := [Vector3(a2.x, y1, a2.y), Vector3(b2.x, y1, b2.y), Vector3(a2.x, y0, a2.y), Vector3(a2.x, y0, a2.y), Vector3(b2.x, y1, b2.y), Vector3(b2.x, y0, b2.y)]
		if area < 0.0:
			quad = [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
		for v in quad:
			st.set_color(side_col)
			st.set_normal(nr)
			st.add_vertex(v)
	return st.commit()

## def: boards.json 항목, rider_id: 캐릭터(없으면 보드만), name: 머리 위 이름(없으면 안 보임)
func setup(def: Dictionary, rider_id := "", name_text := "", tag_color := Color.WHITE) -> void:
	var look: Dictionary = def.get("look", {})
	var dc := Color.html(look.get("deck", "#4aa8e8"))
	var tc := Color.html(look.get("trim", "#ffffff"))
	_glow_col = Color.html(look.get("glow", "#8ff0ff"))
	blen = float(look.get("len", 1.9)) * 1.3
	bwid = float(look.get("wid", 0.62)) * 1.35
	var nose := float(look.get("nose", 0.4))
	var tail := str(look.get("tail", "round"))
	var rainbow: bool = look.get("rainbow", false)
	var shiny: bool = look.get("shiny", false)
	spin_node = Node3D.new()
	add_child(spin_node)
	deck = Node3D.new()
	deck.position.y = HOVER
	spin_node.add_child(deck)
	var pts := outline(blen, bwid, nose, tail)
	var L := blen
	var W := bwid
	var col_fn := func(p: Vector2) -> Color:
		var u := p.y / (L * 0.5)
		if rainbow:
			var hue := fposmod((u + 1.0) * 0.42, 1.0)
			return Color.from_hsv(hue, 0.55, 1.0)
		# 가운데 줄무늬와 코 끝 색
		if absf(p.x) < W * 0.09 and u > -0.7:
			return tc
		if u > 0.78:
			return tc
		return dc
	# 아래판: 가장자리 색(trim), 위판: 보드 색 (테두리가 보이게 조금 작게)
	var base_col := func(_p: Vector2) -> Color: return tc
	var dm := MeshInstance3D.new()
	dm.mesh = extrude(pts, 0.12, base_col, tc.darkened(0.2), Color(0.16, 0.16, 0.2))
	dm.material_override = vc_mat(0.85 if shiny else 0.2)
	deck.add_child(dm)
	var inner := outline(L * 0.84, W * 0.74, nose, tail)
	var top := MeshInstance3D.new()
	top.mesh = extrude(inner, 0.04, col_fn, dc.darkened(0.1), dc)
	top.material_override = vc_mat(0.85 if shiny else 0.1, 0.6 if look.get("stars", false) else 0.0)
	top.position = Vector3(0, 0.07, L * 0.02)
	deck.add_child(top)
	# 옆 빛 줄
	for sx in [-1.0, 1.0]:
		var sg := MeshInstance3D.new()
		var sgb := BoxMesh.new()
		sgb.size = Vector3(0.04, 0.035, L * 0.5)
		sg.mesh = sgb
		sg.position = Vector3(sx * W * 0.47, -0.01, -L * 0.04)
		sg.material_override = mat(_glow_col, true, true)
		deck.add_child(sg)
	# 엔진 덮개 (꼬리 위)
	var pod := MeshInstance3D.new()
	var pc := CapsuleMesh.new()
	pc.radius = 0.13
	pc.height = W * 0.78
	pc.radial_segments = 12
	pc.rings = 4
	pod.mesh = pc
	pod.rotation.z = PI / 2
	pod.scale = Vector3(1, 1, 0.8)
	pod.position = Vector3(0, 0.1, -L * 0.36)
	pod.material_override = mat(Color(0.3, 0.32, 0.38), false, false, 0.7)
	deck.add_child(pod)
	var ring := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(W * 0.6, 0.05, 0.06)
	ring.mesh = rb
	ring.position = Vector3(0, 0.2, -L * 0.36)
	ring.material_override = mat(_glow_col, true, true)
	deck.add_child(ring)
	# 위에 붙인 발판 (밟는 자리 두 개)
	for zs in [-0.22, 0.2]:
		var pad := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(W * 0.62, 0.02, 0.32)
		pad.mesh = bm
		pad.position = Vector3(0, 0.065, zs * L)
		pad.material_override = mat(Color(0.2, 0.2, 0.25))
		deck.add_child(pad)
	# 별 무늬
	if look.get("stars", false):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 14:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(0.015, 0.03)
			sm.height = sm.radius * 2.0
			s.mesh = sm
			var u2 := rng.randf_range(-0.8, 0.7)
			s.position = Vector3(rng.randf_range(-0.35, 0.35) * W, 0.06, u2 * L * 0.5)
			s.material_override = mat(Color(1, 0.95, 1.0), true, true)
			deck.add_child(s)
	# 아래 빛나는 띠
	var under := MeshInstance3D.new()
	var ub := BoxMesh.new()
	ub.size = Vector3(W * 0.5, 0.03, L * 0.7)
	under.mesh = ub
	under.position = Vector3(0, -0.07, -0.02 * L)
	under.material_override = mat(_glow_col, true, true)
	deck.add_child(under)
	# 분사구
	var njet := int(look.get("jets", 1))
	for i in njet:
		var x := (float(i) - (njet - 1) * 0.5) * W * 0.32
		var jet := Node3D.new()
		jet.position = Vector3(x, 0.08, -L * 0.44)
		deck.add_child(jet)
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.1
		cm.height = 0.22
		cm.radial_segments = 12
		body.mesh = cm
		body.rotation.x = PI / 2
		body.material_override = mat(tc.darkened(0.25), false, false, 0.6)
		jet.add_child(body)
		var core := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.055
		cc.bottom_radius = 0.0
		cc.height = 0.32
		cc.radial_segments = 10
		core.mesh = cc
		core.rotation.x = -PI / 2
		core.position.z = -0.24
		core.material_override = mat(_glow_col.lerp(Color.WHITE, 0.3), true, true)
		jet.add_child(core)
		flames.append(core)
		jets.append(jet)
	# 날개
	if look.get("fins", false):
		for sx in [-1.0, 1.0]:
			var fin := MeshInstance3D.new()
			var fb := PrismMesh.new()
			fb.size = Vector3(0.04, 0.22, 0.36)
			fin.mesh = fb
			fin.position = Vector3(sx * W * 0.44, 0.12, -L * 0.33)
			fin.rotation = Vector3(0, 0, -sx * 0.5)
			fin.material_override = mat(tc)
			deck.add_child(fin)
	# 그림자·떠 있는 빛
	shadow = _ground_quad(Vector2(W * 2.2, L * 1.25), Color(0, 0, 0, 0.42), false)
	glow = _ground_quad(Vector2(W * 2.6, L * 1.4), Color(_glow_col.r, _glow_col.g, _glow_col.b, 0.5), true)
	# 캐릭터
	if rider_id != "":
		_make_rider(rider_id)
	# 효과
	trail = _particles(_glow_col, 0.22, 0.5, true)
	trail.amount = 26
	trail.position = Vector3(0, HOVER, -L * 0.55)
	trail.direction = Vector3(0, 0.3, -1)
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.0
	trail.gravity = Vector3.ZERO
	spin_node.add_child(trail)
	boost_fx = _particles(Color(1.0, 0.7, 0.3, 0.95), 0.35, 0.35, true)
	boost_fx.position = Vector3(0, HOVER, -L * 0.6)
	boost_fx.direction = Vector3(0, 0.1, -1)
	boost_fx.initial_velocity_min = 3.0
	boost_fx.initial_velocity_max = 6.0
	boost_fx.gravity = Vector3.ZERO
	spin_node.add_child(boost_fx)
	spray = _particles(Color(1, 1, 1, 0.8), 0.3, 0.6)
	spray.position = Vector3(0, 0.15, -L * 0.2)
	spray.direction = Vector3(0, 1.4, -0.6)
	spray.spread = 50.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.5
	spray.gravity = Vector3(0, -9, 0)
	add_child(spray)
	stars_fx = _particles(Color(1.0, 0.95, 0.5), 0.25, 0.7, true)
	stars_fx.one_shot = true
	stars_fx.explosiveness = 0.95
	stars_fx.amount = 22
	stars_fx.position = Vector3(0, 1.4, 0)
	stars_fx.direction = Vector3(0, 1, 0)
	stars_fx.spread = 180.0
	stars_fx.initial_velocity_min = 3.0
	stars_fx.initial_velocity_max = 6.0
	stars_fx.gravity = Vector3(0, -6, 0)
	add_child(stars_fx)
	# 비틀거릴 때 머리 위 별
	dizzy = Node3D.new()
	dizzy.position.y = 2.3
	dizzy.visible = false
	add_child(dizzy)
	for i in 4:
		var s2 := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.09
		sp.height = 0.18
		s2.mesh = sp
		s2.position = Vector3(cos(i * TAU / 4) * 0.45, 0, sin(i * TAU / 4) * 0.45)
		s2.material_override = mat(Color(1, 0.9, 0.3), true, true)
		dizzy.add_child(s2)
	bubble = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 1.3
	bs.height = 2.6
	bubble.mesh = bs
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.6, 0.9, 1.0, 0.25)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.rim_enabled = true
	bubble.material_override = bmat
	bubble.position.y = 1.1
	bubble.visible = false
	add_child(bubble)
	if name_text != "":
		tag = Label3D.new()
		tag.text = name_text
		tag.font = Game.font_bold
		tag.font_size = 44
		tag.pixel_size = 0.01
		tag.outline_size = 14
		tag.modulate = Color(1, 1, 1)
		tag.outline_modulate = tag_color.darkened(0.25)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = false
		tag.position.y = 2.55
		tag.render_priority = 6
		add_child(tag)
		# 이름표 바탕 (둥근 색 판)
		var plate := MeshInstance3D.new()
		var q := QuadMesh.new()
		var wlen := 0.0
		for ch in name_text:
			wlen += 0.44 if ch.unicode_at(0) > 0x2000 else 0.26
		q.size = Vector2(wlen + 0.3, 0.52)
		plate.mesh = q
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pm.no_depth_test = true
		pm.render_priority = 5
		pm.albedo_color = Color(tag_color.r, tag_color.g, tag_color.b, 0.82)
		pm.albedo_texture = _plate_tex()
		plate.material_override = pm
		plate.position.y = 2.55
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plate)
		tag.outline_modulate = Color(0.08, 0.1, 0.2)
		tag.outline_size = 8

static var _plate: ImageTexture

## 둥근 네모 흰 그림 (이름표 바탕, 색은 재질 색으로)
static func _plate_tex() -> ImageTexture:
	if _plate:
		return _plate
	var w := 64
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := 10.0
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, r, w - r)
			var cy := clampf(y + 0.5, r, h - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d, 0.0, 1.0)))
	_plate = ImageTexture.create_from_image(img)
	return _plate

func _make_rider(id: String) -> void:
	var scene: PackedScene = load(KIT % ("character-" + id))
	rider = scene.instantiate()
	# 키 맞추기 (모델 높이 → 1.45)
	var aabb := AABB()
	var first := true
	for m in rider.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var box := mi.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	var h := maxf(aabb.size.y, 0.5)
	var sc := 1.4 / h
	rider.scale = Vector3.ONE * sc
	rider.position = Vector3(0, 0.06 - aabb.position.y * sc, 0)
	rider.rotation.y = -1.3   # 옆으로 서서 탄다
	deck.add_child(rider)
	anim = rider.find_child("AnimationPlayer", true, false)
	if anim:
		for a in ["idle", "crouch", "fall", "jump", "sit", "emote-yes", "die"]:
			if anim.has_animation(a):
				var an := anim.get_animation(a)
				an.loop_mode = Animation.LOOP_LINEAR if a in ["idle", "fall", "crouch"] else Animation.LOOP_NONE
		_play("idle")

func _play(a: String, blend := 0.15) -> void:
	if anim and anim_now != a and anim.has_animation(a):
		anim_now = a
		anim.play(a, blend)

func _ground_quad(size: Vector2, c: Color, add: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.position.y = 0.04
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, c)
	gr.set_color(1, Color(c.r, c.g, c.b, 0.0))
	gt.gradient = gr
	sm.albedo_texture = gt
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _particles(c: Color, size: float, life: float, glow_add := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 24
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 1, -0.4)
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	m.albedo_texture = gt
	if glow_add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	var cr := Gradient.new()
	cr.set_color(0, c)
	cr.set_color(1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = cr
	return p

## 보드 상태를 그림에 옮긴다. ground_h = 바로 아래 땅 높이(그림자 자리)
func show_state(k: Dictionary, steer: float, dt: float, ground_h := -999.0) -> void:
	var p: Vector2 = k.pos
	var alt: float = k.alt
	var gh := alt if ground_h < -900.0 else ground_h
	position = Vector3(p.x, alt, p.y)
	rotation.y = k.yaw
	var spd := Rules.speed_of(k)
	bob += dt * (3.0 + spd * 0.08)
	var air: bool = k.air
	# 묘기: 360·720은 빙글, GB는 보드를 잡고 기울인다
	var tname: String = k.get("trick", "")
	var spin: float = float(k.get("spin", 0.0))
	var flip: float = float(k.get("flip", 0.0))
	# 옆으로 돌기(spin)와 앞뒤로 구르기(flip). 구르기는 몸 가운데(PIVOT)를 축으로
	var b := Basis(Vector3.UP, -spin * TAU) * Basis(Vector3.RIGHT, flip * TAU)
	spin_node.transform = Transform3D(b, PIVOT - b * PIVOT)
	var want_roll := float(k.slip) * 0.55 + steer * 0.16 * clampf(spd / 20.0, 0.0, 1.0)
	var want_pitch := 0.0
	if air:
		want_pitch = clampf(float(k.vy) * 0.025, -0.25, 0.25)
	var grab := str(Rules.TRICKS[tname].get("grab", "")) if Rules.TRICKS.has(tname) else ""
	if grab != "":
		var gt := clampf(float(k.trick_t) / maxf(float(k.trick_dur), 0.01), 0.0, 1.0)
		var w := sin(gt * PI)
		match grab:
			"mid":
				want_roll += w * 0.9
				want_pitch += w * 0.45
			"nose":
				want_pitch += w * 0.95
				want_roll += w * 0.2
			"tail":
				want_pitch -= w * 0.95
				want_roll -= w * 0.2
			"wing":
				want_roll += sin(gt * TAU) * 1.1
				want_pitch += w * 0.3
	if float(k.get("stumble_t", 0.0)) > 0.0:
		want_roll += sin(bob * 6.0) * 0.3
	roll = lerpf(roll, want_roll, 1.0 - exp(-10.0 * dt))
	pitch = lerpf(pitch, want_pitch, 1.0 - exp(-10.0 * dt))
	deck.rotation = Vector3(-pitch, 0, roll)
	deck.position.y = HOVER + (0.0 if air else sin(bob) * 0.06)
	# 그림자: 땅에 붙어서, 높을수록 흐리고 크게
	var above := maxf(0.0, alt - gh)
	for q in [shadow, glow]:
		q.position.y = gh - alt + 0.05
		var s := 1.0 + above * 0.12
		q.scale = Vector3(s, 1, s)
	shadow.transparency = clampf(above * 0.12, 0.0, 0.8)
	glow.transparency = clampf(0.25 + above * 0.2, 0.0, 0.95) if gh > -10.0 else 1.0
	shadow.visible = gh > -10.0
	# 캐릭터 동작
	if anim:
		if float(k.get("stumble_t", 0.0)) > 0.0 or float(k.get("spin_t", 0.0)) > 0.0:
			_play("fall")
		elif (Rules.TRICKS.has(tname) and (Rules.TRICKS[tname].has("grab") or Rules.TRICKS[tname].has("flip"))) or (k.get("slide", false) and not air):
			_play("crouch")
		elif air:
			_play("jump" if float(k.vy) > 0.0 else "fall")
		else:
			_play("idle")
	var boost := Rules.boosting(k)
	for i in flames.size():
		var f := 0.9 + 0.3 * sin(bob * 11.0 + i)
		flames[i].scale = Vector3(1, (2.6 if k.boost_t > 0.0 else (1.7 if k.dash_t > 0.0 else 0.8)) * f, 1)
	boost_fx.emitting = boost
	trail.emitting = absf(spd) > 6.0
	spray.emitting = (k.get("slide", false) or str(k.get("ground", "")) in ["ice", "grass"] and absf(spd) > 14.0) and not air and absf(float(k.slip)) > 0.08
	dizzy.visible = float(k.get("stumble_t", 0.0)) > 0.0
	if dizzy.visible:
		dizzy.rotation.y += dt * 6.0
	bubble.visible = float(k.get("shield_t", 0.0)) > 0.0
	# 판정이 새로 나오면 반짝
	var j: Dictionary = k.get("judge", {})
	if not j.is_empty() and j != _prev_judge:
		_prev_judge = j
		if j.get("word", "") in ["EXCELLENT", "NICE"]:
			stars_fx.restart()
			stars_fx.emitting = true

## 결과 화면 등에서: 기뻐하기
func cheer() -> void:
	_play("emote-yes", 0.1)
