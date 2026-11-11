class_name TrackView
extends Node3D
## 트랙 그림: 길·가장자리·점프대·계단·얼음·부스터 발판·출발 문·꾸밈을 트랙 정의로 코드에서 만든다.
## 꾸밈 모형: Kenney Platformer Kit (assets/kit)

const KIT := "res://assets/kit/%s.glb"

## 테마마다 색
const THEMES := {
	"grass": {"ground": "#5aa53c", "road": "#cdb27c", "edge": "#ffffff", "edge2": "#56b04a", "sky_top": "#5aa6ec", "sky_hor": "#cfeaff", "sun": 0.8, "ambient": "#b8d0e8", "fog": "#d6ecff"},
	"snow": {"ground": "#d5e2ee", "road": "#4fa8de", "edge": "#ffffff", "edge2": "#3d8fe0", "sky_top": "#6fb2ec", "sky_hor": "#eaf6ff", "sun": 0.85, "ambient": "#c8dcf0", "fog": "#eef6ff"},
	"sky": {"ground": "#62b544", "road": "#c9b48a", "edge": "#ffffff", "edge2": "#ff9ec7", "sky_top": "#4f9de8", "sky_hor": "#ffe9f4", "sun": 0.95, "ambient": "#d8e4f6", "fog": "#f4f0ff"},
	"forest": {"ground": "#3f8a3a", "road": "#b8925c", "edge": "#ffe9a8", "edge2": "#a0522d", "sky_top": "#e58a6b", "sky_hor": "#ffd59e", "sun": 0.75, "ambient": "#c8a8c8", "fog": "#ffcf9e"},
	"castle": {"ground": "#6aa84f", "road": "#a8a39c", "edge": "#f2efe8", "edge2": "#c8463c", "sky_top": "#5d9fe0", "sky_hor": "#dcecff", "sun": 0.9, "ambient": "#b8c8dc", "fog": "#dfeaf8"},
}

var trk: Dictionary
var def: Dictionary
var th: Dictionary
var theme := "grass"
var rng := RandomNumberGenerator.new()
var _meshes := {}
var pads: Array = []      # 부스터 발판 (반짝이게)
var springs: Array = []   # 스프링 발판 윗판 (통통)
var rings_n: Array = []   # 공중 고리 (빙글)
var _t := 0.0

func ground(i: int) -> bool:
	return Rules.height_at(trk, i) <= Rules.BRIDGE_H and not trk.sky

func col(key: String) -> Color:
	return Color.html(th[key])

func build(track_def: Dictionary, track: Dictionary, shadows := true) -> void:
	def = track_def
	trk = track
	theme = str(def.get("theme", "grass"))
	th = THEMES.get(theme, THEMES.grass)
	rng.seed = int(def.get("seed", 1))
	_environment(shadows)
	if trk.sky:
		_clouds()
		_sky_deck()
	else:
		_ground()
	_road()
	_edges()
	if trk.has_bridge:
		_bridges()
	_zones()
	_start()
	if not trk.sky:
		_fences()
	_scenery()

func kit_mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var inst: Node = (load(KIT % name) as PackedScene).instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	var m: Mesh = null
	if mis.size() == 1:
		m = (mis[0] as MeshInstance3D).mesh
	else:
		# 여러 조각이면 하나로 합친다
		var am := ArrayMesh.new()
		for x in mis:
			var mi := x as MeshInstance3D
			var xf := mi.transform
			var p := mi.get_parent()
			while p and p != inst:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			for s in mi.mesh.get_surface_count():
				var stt := SurfaceTool.new()
				stt.create_from(mi.mesh, s)
				stt.set_material(mi.mesh.surface_get_material(s))
				var arr := stt.commit_to_arrays()
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for vi in verts.size():
					verts[vi] = xf * verts[vi]
				arr[Mesh.ARRAY_VERTEX] = verts
				if arr[Mesh.ARRAY_NORMAL] != null:
					var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
					for ni in nr.size():
						nr[ni] = (xf.basis * nr[ni]).normalized()
					arr[Mesh.ARRAY_NORMAL] = nr
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				am.surface_set_material(am.get_surface_count() - 1, mi.mesh.surface_get_material(s))
		m = am
	inst.free()
	_meshes[name] = m
	return m

func _environment(shadows: bool) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = col("sky_top")
	sm.sky_horizon_color = col("sky_hor")
	sm.ground_horizon_color = col("sky_hor")
	sm.ground_bottom_color = col("sky_top").darkened(0.2) if trk.sky else col("ground").darkened(0.3)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = col("ambient")
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_exposure = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.12
	env.fog_enabled = true
	env.fog_light_color = col("fog")
	env.fog_density = 0.0028 if not trk.sky else 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -30, 0) if theme != "forest" else Vector3(-32, -60, 0)
	sun.light_energy = float(th.sun)
	sun.light_color = Color(1.0, 0.97, 0.9) if theme != "forest" else Color(1.0, 0.82, 0.62)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

func bounds() -> Rect2:
	var r := Rect2(trk.pts[0], Vector2.ZERO)
	for p in trk.pts:
		r = r.expand(p)
	return r

func _noise_tex(base: Color, amount: float, freq: float, size := 128) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var u := float(x) / size
			var v := float(y) / size
			var a := n.get_noise_2d(x, y) * (1 - u) * (1 - v) + n.get_noise_2d(x - size, y) * u * (1 - v) \
				+ n.get_noise_2d(x, y - size) * (1 - u) * v + n.get_noise_2d(x - size, y - size) * u * v
			img.set_pixel(x, y, base.lightened(a * amount) if a > 0 else base.darkened(-a * amount))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## 길 무늬: 테마마다 (돌 타일, 얼음 결, 흙길)
func _road_tex() -> ImageTexture:
	var size := 64
	var base := col("road")
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.12
	for y in size:
		for x in size:
			var a := n.get_noise_2d(x, y) * 0.06
			var c := base.lightened(a) if a > 0 else base.darkened(-a)
			if theme in ["castle", "grass", "sky"]:
				# 네모 돌 타일
				var row := y / 16
				var xx := (x + (8 if row % 2 == 1 else 0)) % 32
				if y % 16 == 0 or xx == 0:
					c = c.darkened(0.12)
			elif theme == "snow":
				if (x + y * 3) % 23 == 0:
					c = c.lightened(0.25)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _ground() -> void:
	var b := bounds().grow(260.0)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = b.size
	mi.mesh = pm
	mi.position = Vector3(b.get_center().x, 0.0, b.get_center().y)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(col("ground"), 0.22 if theme != "snow" else 0.05, 0.05)
	m.uv1_scale = Vector3(b.size.x / 24.0, b.size.y / 24.0, 1)
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)

## 가운데 선을 따라 띠. from/to = 옆 거리(오른쪽 +), y = 높이, keep(i) = 이 칸을 그릴지
func _strip(from: float, to: float, y: float, mat: Material, keep := Callable(), color_of := Callable(), lift := Callable()) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: int = trk.n
	for i in m:
		if keep.is_valid() and not keep.call(i):
			continue
		var j := (i + 1) % m
		var a0: Vector2 = trk.pts[i] + trk.nrm[i] * from
		var a1: Vector2 = trk.pts[i] + trk.nrm[i] * to
		var b0: Vector2 = trk.pts[j] + trk.nrm[j] * from
		var b1: Vector2 = trk.pts[j] + trk.nrm[j] * to
		var v0: float = trk.cum[i] / 6.0
		var v1: float = v0 + (trk.pts[i] as Vector2).distance_to(trk.pts[j]) / 6.0
		var c: Color = Color.WHITE if not color_of.is_valid() else color_of.call(i)
		var hi := Rules.height_at(trk, i) + (float(lift.call(i)) if lift.is_valid() else 0.0)
		var hj := Rules.height_at(trk, j) + (float(lift.call(j)) if lift.is_valid() else 0.0)
		for q in [[a0, 0.0, v0, hi], [b0, 0.0, v1, hj], [a1, 1.0, v0, hi], [a1, 1.0, v0, hi], [b0, 0.0, v1, hj], [b1, 1.0, v1, hj]]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q[1], q[2]))
			st.add_vertex(Vector3(q[0].x, y + q[3], q[0].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## i번 점이 낭떠러지 안인가
func in_gap(i: int) -> bool:
	var z := Rules.zone_at(trk, float(trk.cum[i]) + 1.0)
	return not z.is_empty() and z.type == "gap"

func _road() -> void:
	var hw: float = trk.half_width
	var m := StandardMaterial3D.new()
	m.albedo_texture = _road_tex()
	m.uv1_scale = Vector3(hw / 3.0, 1.0, 1)
	m.roughness = 0.6 if theme == "snow" else 0.9
	var keep := func(i: int) -> bool: return not in_gap(i) and not in_gap((i + 1) % trk.n)
	_strip(-hw, hw, 0.02, m, keep)
	# 길섶 (길과 풀밭 사이)
	if not trk.sky:
		var verge := StandardMaterial3D.new()
		verge.albedo_color = col("ground").lerp(col("road"), 0.35)
		verge.roughness = 1.0
		_strip(-hw - 1.6, -hw, 0.012, verge, ground)
		_strip(hw, hw + 1.6, 0.012, verge, ground)

## 가장자리: 두 색 줄무늬 띠 (사진처럼 눈길은 파랑·하양 둔덕)
func _edges() -> void:
	var hw: float = trk.half_width
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	var c1 := col("edge")
	var c2 := col("edge2")
	var stripe := func(i: int) -> Color: return c1 if (i / 2) % 2 == 0 else c2
	var keep := func(i: int) -> bool: return not in_gap(i) and not in_gap((i + 1) % trk.n)
	if theme == "snow":
		# 둥근 눈 둔덕 (낮은 벽처럼 보이게 띠 세 장)
		_strip(-hw - 1.3, -hw, 0.05, m, keep, stripe, func(_i): return 0.18)
		_strip(hw, hw + 1.3, 0.05, m, keep, stripe, func(_i): return 0.18)
		_side_wall(-hw - 0.05, 0.23, stripe, keep)
		_side_wall(hw + 0.05, 0.23, stripe, keep)
	else:
		_strip(-hw - 0.9, -hw, 0.04, m, keep, stripe)
		_strip(hw, hw + 0.9, 0.04, m, keep, stripe)

## 길 가장자리 세로 띠 (높이 h)
func _side_wall(lat: float, h: float, color_of: Callable, keep: Callable) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: int = trk.n
	for i in m:
		if not keep.call(i):
			continue
		var j := (i + 1) % m
		var a: Vector2 = trk.pts[i] + trk.nrm[i] * lat
		var b: Vector2 = trk.pts[j] + trk.nrm[j] * lat
		var hi := Rules.height_at(trk, i)
		var hj := Rules.height_at(trk, j)
		var c: Color = color_of.call(i)
		var nn := Vector3(trk.nrm[i].x, 0, trk.nrm[i].y) * -signf(lat)
		for v in [Vector3(a.x, hi, a.y), Vector3(b.x, hj, b.y), Vector3(a.x, hi + h, a.y), Vector3(a.x, hi + h, a.y), Vector3(b.x, hj, b.y), Vector3(b.x, hj + h, b.y)]:
			st.set_color(c)
			st.set_normal(nn)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)

# ─────────── 구간: 점프대·계단·얼음·발판·낭떠러지 ───────────

func _zones() -> void:
	for z in trk.zones:
		match str(z.type):
			"ramp": _ramp(z)
			"stairs": _stairs(z)
			"ice": _ice(z)
			"pad": _pad(z)
			"gap": _gap(z)
			"spring": _spring(z)
	for i in trk.get("rings", []).size():
		_ring(trk.rings[i])

## 거리 s, 옆 lat 자리의 3D 점 (높이 + 더할 높이)
func _at(s: float, lat: float, up := 0.0) -> Vector3:
	var p := Rules.point_at(trk, s)
	var q: Vector2 = p.pos + (p.nrm as Vector2) * lat
	return Vector3(q.x, float(p.h) + up, q.y)

func _ramp(z: Dictionary) -> void:
	var hw: float = trk.half_width + 0.3
	var s0: float = z.s0
	var s1: float = z.s1
	var RH: float = float(z.get("h", Rules.RAMP_H))
	var big := str(z.get("size", "")) == "big"
	var small := str(z.get("size", "")) == "small"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 10
	var wood := Color(0.86, 0.6, 0.35)
	var wood2 := Color(0.76, 0.5, 0.28)
	for k in steps:
		var a := s0 + (s1 - s0) * k / steps
		var b := s0 + (s1 - s0) * (k + 1) / steps
		var ha := RH * float(k) / steps
		var hb := RH * float(k + 1) / steps
		# 끝 쪽 16%는 EXCELLENT 자리 (노랑), 그 앞 NICE (주황), 처음은 나무
		var t := float(k + 1) / steps
		var c := wood if k % 2 == 0 else wood2
		if big:
			c = Color(0.92, 0.25, 0.22) if k % 2 == 0 else Color(0.97, 0.95, 0.92)
		elif small:
			c = Color(0.35, 0.75, 0.95) if k % 2 == 0 else Color(0.3, 0.62, 0.85)
		if t > 0.84:
			c = Color(1.0, 0.86, 0.25)
		elif t > 0.6:
			c = Color(1.0, 0.6, 0.3) if k % 2 == 0 else Color(0.95, 0.52, 0.25)
		var q := [_at(a, -hw, ha + 0.03), _at(b, -hw, hb + 0.03), _at(a, hw, ha + 0.03), _at(a, hw, ha + 0.03), _at(b, -hw, hb + 0.03), _at(b, hw, hb + 0.03)]
		for v in q:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		# 옆면
		for sd in [-1.0, 1.0]:
			var sq := [_at(a, sd * hw, 0.0), _at(b, sd * hw, 0.0), _at(a, sd * hw, ha + 0.03), _at(a, sd * hw, ha + 0.03), _at(b, sd * hw, 0.0), _at(b, sd * hw, hb + 0.03)]
			for v in sq:
				st.set_color(wood2.darkened(0.2))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	# 끝 벽 (앞에서 보이는 면)
	var e := [_at(s1, -hw, 0.0), _at(s1, hw, 0.0), _at(s1, -hw, RH + 0.03), _at(s1, -hw, RH + 0.03), _at(s1, hw, 0.0), _at(s1, hw, RH + 0.03)]
	for v in e:
		st.set_color(wood2.darkened(0.3))
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	mi.material_override = mat
	add_child(mi)
	# 화살표 셋 (위로 뛰라고)
	for f in [0.25, 0.45]:
		var s: float = s0 + (s1 - s0) * f
		_chevron(s, RH * f + 0.06, Color(1, 1, 1, 0.9), 1.4)
	# 양옆 깃발 기둥 (큰 점프대는 더 높게, 작은 점프대는 없음)
	if not small:
		for sd in [-1.0, 1.0]:
			var p := _at(s1, sd * (hw + 0.6))
			_put("flag", p, rng.randf() * TAU, 2.4 if big else 1.6)
	if big:
		# 받침 기둥
		for f in [0.5, 0.8, 1.0]:
			for sd in [-1.0, 1.0]:
				var q := _at(s0 + (s1 - s0) * f, sd * (hw - 0.3))
				var mi2 := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.3, RH * f, 0.3)
				mi2.mesh = bm
				mi2.material_override = BoardView.mat(Color(0.45, 0.3, 0.2))
				mi2.position = q + Vector3(0, RH * f * 0.5, 0)
				add_child(mi2)

## 스프링 발판: 파란 판 + 아래 용수철 + 위로 화살표
func _spring(z: Dictionary) -> void:
	var s0: float = z.s0
	var s1: float = z.s1
	var p := Rules.point_at(trk, (s0 + s1) * 0.5)
	var t: Vector2 = p.tan
	var q: Vector2 = p.pos
	var root := Node3D.new()
	root.position = Vector3(q.x, float(p.h), q.y)
	root.rotation.y = atan2(t.x, t.y)
	add_child(root)
	var w: float = float(trk.half_width) * 1.4
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.12, s1 - s0)
	base.mesh = bm
	base.material_override = BoardView.mat(Color(0.2, 0.25, 0.35))
	base.position.y = 0.06
	root.add_child(base)
	var coils := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22; tm.outer_radius = 0.32; tm.rings = 12; tm.ring_segments = 6
	for i in 5:
		for lay in 2:
			var c := MeshInstance3D.new()
			c.mesh = tm
			c.material_override = BoardView.mat(Color(0.85, 0.88, 0.95), false, false, 0.6)
			c.position = Vector3(-w * 0.4 + i * w * 0.2, 0.16 + lay * 0.1, 0)
			root.add_child(c)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(w, 0.1, s1 - s0)
	top.mesh = tb
	top.material_override = BoardView.mat(Color(0.25, 0.65, 1.0), true)
	top.position.y = 0.4
	root.add_child(top)
	springs.append(top)
	for i in 2:
		var ch := _chevron((s0 + s1) * 0.5, 0.48 + i * 0.01, Color(1, 1, 1, 0.95), 1.1 - i * 0.3, true)
		ch.position = root.position + Vector3(0, 0.48, 0)

## 공중 고리: 길 위 높이 h에 떠 있는 빛나는 고리 (지나가면 게이지)
func _ring(rg: Dictionary) -> void:
	var p := Rules.point_at(trk, float(rg.s))
	var t: Vector2 = p.tan
	var q: Vector2 = p.pos
	var r: float = rg.r
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.22; tm.outer_radius = r + 0.22; tm.rings = 40; tm.ring_segments = 10
	mi.mesh = tm
	mi.material_override = BoardView.mat(Color(1.0, 0.82, 0.25), true)
	mi.position = Vector3(q.x, float(p.h) + float(rg.h), q.y)
	# 길 방향을 보고 서 있게 (고리 구멍이 길을 따라)
	mi.basis = Basis(Vector3.UP, atan2(t.x, t.y)) * Basis(Vector3.RIGHT, PI / 2)
	add_child(mi)
	rings_n.append(mi)
	# 아래에서 위로 가는 줄 (어디 있는지 보이게)
	var line := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05; cm.bottom_radius = 0.05; cm.height = float(rg.h) - r
	line.mesh = cm
	line.material_override = BoardView.mat(Color(1.0, 0.9, 0.5, 0.5), false, true)
	(line.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.position = Vector3(q.x, float(p.h) + (float(rg.h) - r) * 0.5, q.y)
	add_child(line)

## 길 위 꺾쇠(▲) 표시
func _chevron(s: float, up: float, c: Color, size: float, emit := false) -> MeshInstance3D:
	var p := Rules.point_at(trk, s)
	var t: Vector2 = p.tan
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector2(0, 0.6), Vector2(-1, -0.2), Vector2(-0.55, -0.45), Vector2(0, 0.05), Vector2(0.55, -0.45), Vector2(1, -0.2)]
	for tri in [[0, 1, 3], [1, 2, 3], [0, 3, 5], [3, 4, 5]]:
		for idx in tri:
			var v: Vector2 = pts[idx] * size
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, 0, v.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BoardView.mat(c, emit, true)
	(mi.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var q: Vector2 = p.pos
	mi.position = Vector3(q.x, float(p.h) + up, q.y)
	mi.rotation.y = atan2(t.x, t.y)
	add_child(mi)
	return mi

func _stairs(z: Dictionary) -> void:
	var hw: float = trk.half_width + 0.2
	var s: float = z.s0
	var planks := []
	var dark := []
	var k := 0
	while s < float(z.s1):
		var p := Rules.point_at(trk, s)
		var t: Vector2 = p.tan
		var q: Vector2 = p.pos
		var xf := Transform3D(Basis(Vector3.UP, atan2(t.x, t.y)) * Basis.from_scale(Vector3(hw * 2.0, 0.16 if k % 2 == 0 else 0.1, 0.85)), Vector3(q.x, float(p.h) + 0.06, q.y))
		(planks if k % 2 == 0 else dark).append(xf)
		s += 1.0
		k += 1
	_boxes(planks, Color(0.85, 0.62, 0.36))
	_boxes(dark, Color(0.7, 0.48, 0.26))
	# 양옆 통나무 기둥 (사진처럼 줄지어)
	var logs := []
	s = float(z.s0)
	while s <= float(z.s1):
		for sd in [-1.0, 1.0]:
			var p2 := _at(s, sd * (hw + 0.5))
			logs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.45, 0.6 + rng.randf() * 0.25, 0.45)), p2 + Vector3(0, 0.55, 0)))
		s += 1.6
	_cylinders(logs, Color(0.78, 0.55, 0.32), Color(0.95, 0.82, 0.6))
	# 계단 양옆 큰 탑 두 개 (시작 쪽)
	if theme in ["grass", "castle", "forest"]:
		for sd in [-1.0, 1.0]:
			var tp := _at(float(z.s0) - 3.0, sd * (hw + 4.5))
			_tower(tp, 2.2, 9.0, Color(0.97, 0.95, 0.92) if theme != "castle" else Color(0.72, 0.7, 0.68), Color(0.35, 0.72, 0.85) if theme == "grass" else (Color(0.85, 0.35, 0.3) if theme == "castle" else Color(0.62, 0.35, 0.65)))

func _ice(z: Dictionary) -> void:
	var hw: float = trk.half_width
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.92, 1.0, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.3
	m.rim_enabled = true
	var a: float = z.s0
	var b: float = z.s1
	var keep := func(i: int) -> bool:
		var s: float = trk.cum[i]
		return fposmod(s - a, trk.length) <= b - a
	_strip(-hw + 0.2, hw - 0.2, 0.035, m, keep)
	# 반짝이 줄
	var white := BoardView.mat(Color(1, 1, 1, 0.75), false, true)
	var s := a
	while s < b:
		var lat := rng.randf_range(-hw * 0.7, hw * 0.7)
		var p0 := _at(s, lat, 0.05)
		var p1 := _at(s + 2.2, lat + rng.randf_range(-1, 1), 0.05)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.01, p0.distance_to(p1))
		mi.mesh = bm
		mi.material_override = white
		mi.position = (p0 + p1) * 0.5
		mi.rotation.y = atan2(p1.x - p0.x, p1.z - p0.z)
		add_child(mi)
		s += 1.6

func _pad(z: Dictionary) -> void:
	var s: float = z.s0
	for i in 3:
		var ch := _chevron(s + i * 1.0, 0.05, Color(1.0, 0.75, 0.2), 1.6, true)
		pads.append({"node": ch, "i": i})
	# 발판 바닥
	var p := Rules.point_at(trk, s + 1.0)
	var t: Vector2 = p.tan
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(trk.half_width * 1.2, 0.03, 3.8)
	mi.mesh = bm
	mi.material_override = BoardView.mat(Color(0.95, 0.4, 0.2))
	var q: Vector2 = p.pos
	mi.position = Vector3(q.x, float(p.h) + 0.03, q.y)
	mi.rotation.y = atan2(t.x, t.y)
	add_child(mi)

func _gap(z: Dictionary) -> void:
	# 낭떠러지 양쪽 끝에 노랑·검정 줄
	for s in [float(z.s0), float(z.s1)]:
		for k in 8:
			var lat: float = -trk.half_width + (k + 0.5) * trk.half_width * 2.0 / 8.0
			var p := _at(s + (0.3 if s == float(z.s1) else -0.3), lat, 0.04)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(trk.half_width * 2.0 / 8.0, 0.02, 0.6)
			mi.mesh = bm
			mi.material_override = BoardView.mat(Color(1.0, 0.85, 0.2) if k % 2 == 0 else Color(0.15, 0.15, 0.18))
			mi.position = p
			var t: Vector2 = Rules.point_at(trk, s).tan
			mi.rotation.y = atan2(t.x, t.y)
			add_child(mi)

func _process(dt: float) -> void:
	_t += dt
	for sp in springs:
		(sp as Node3D).position.y = 0.4 + absf(sin(_t * 5.0)) * 0.1
	for rn in rings_n:
		(rn as Node3D).rotate_object_local(Vector3.UP, dt * 1.2)
	for p in pads:
		var n: MeshInstance3D = p.node
		var on := int(_t * 6.0) % 3 == int(p.i)
		n.transparency = 0.0 if on else 0.55

# ─────────── 출발 문 ───────────

func _start() -> void:
	var hw: float = trk.half_width
	var p0: Vector2 = trk.pts[0]
	var t0: Vector2 = trk.tan[0]
	var yaw := atan2(t0.x, t0.y)
	var h0 := Rules.height_at(trk, 0)
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 2:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.12, 0.12, 0.14))
	var tex := ImageTexture.create_from_image(img)
	var line := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(hw * 2.0, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	line.mesh = q
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = tex
	lm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	line.material_override = lm
	line.position = Vector3(p0.x, h0 + 0.035, p0.y)
	line.rotation.y = yaw
	add_child(line)
	var arch := Node3D.new()
	arch.position = Vector3(p0.x, h0, p0.y)
	arch.rotation.y = yaw
	add_child(arch)
	var c1 := Color(0.25, 0.6, 0.95)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.5
		pc.bottom_radius = 0.6
		pc.height = 7.0
		post.mesh = pc
		post.material_override = BoardView.mat(Color(0.98, 0.98, 1.0))
		post.position = Vector3(sx * (hw + 1.4), 3.5, 0)
		arch.add_child(post)
		var ball := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.8
		bs.height = 1.6
		ball.mesh = bs
		ball.material_override = BoardView.mat(Color(1.0, 0.8, 0.25))
		ball.position = Vector3(sx * (hw + 1.4), 7.6, 0)
		arch.add_child(ball)
	var banner := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(hw * 2.0 + 3.6, 1.6, 0.4)
	banner.mesh = bb
	banner.material_override = BoardView.mat(c1)
	banner.position = Vector3(0, 6.4, 0)
	arch.add_child(banner)
	for side in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "바람보드" if side > 0 else "출발!"
		lb.font = Game.font_bold
		lb.font_size = 96
		lb.pixel_size = 0.012
		lb.outline_size = 14
		lb.modulate = Color(1, 1, 1)
		lb.outline_modulate = Color(0.1, 0.25, 0.5)
		lb.position = Vector3(0, 6.4, -side * 0.22)
		lb.rotation.y = 0.0 if side < 0 else PI
		arch.add_child(lb)

# ─────────── 꾸밈 ───────────

func _put(name: String, pos: Vector3, rot: float, scale: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = kit_mesh(name)
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * scale
	add_child(mi)
	return mi

func _multi(name: String, xforms: Array, shadow := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = kit_mesh(name)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _xf(p: Vector2, rot: float, s: float, y := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))

func clear_of_track(p: Vector2, margin: float) -> bool:
	var loc := Rules.locate(trk, p)
	return absf(loc.lat) > float(loc.wall) + margin

func _fences() -> void:
	var xs := []
	var step := 2.0 * 1.0
	var kind := "fence-low-straight" if theme in ["snow"] else "fence-straight"
	if theme == "castle":
		_castle_walls()
		return
	for side in [-1.0, 1.0]:
		var s := 0.0
		while s < trk.length:
			var i: int = int(s / trk.length * trk.n) % trk.n
			var p: Vector2 = trk.pts[i] + trk.nrm[i] * side * (trk.wall + 0.2)
			if ground(i) and Rules.height_at(trk, i) < 0.2 and clear_of_track(p, -0.1):
				var t: Vector2 = trk.tan[i]
				xs.append(_xf(p, atan2(t.x, t.y) + PI / 2, 1.0, 0.0))
			var k: float = 1.0 + float(trk.curv[i]) * side * (trk.wall + 0.2)
			s += step / maxf(0.35, k)
	_multi(kind, xs)

## 성벽: 돌 벽 + 톱니
func _castle_walls() -> void:
	var walls := []
	var teeth := []
	for side in [-1.0, 1.0]:
		var s := 0.0
		var n := 0
		while s < trk.length:
			var i: int = int(s / trk.length * trk.n) % trk.n
			var lat: float = side * (float(trk.walls[i]) + 0.4)
			var p: Vector2 = trk.pts[i] + trk.nrm[i] * lat
			var h := Rules.height_at(trk, i)
			if clear_of_track(p, -0.5) or not ground(i):
				var t: Vector2 = trk.tan[i]
				var yaw := atan2(t.x, t.y)
				var base := h if not ground(i) else 0.0
				walls.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.8, 1.2, 2.3)), Vector3(p.x, base + 0.6, p.y)))
				if n % 2 == 0:
					teeth.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.8, 0.5, 1.0)), Vector3(p.x, base + 1.45, p.y)))
			s += 2.1
			n += 1
	_boxes(walls, Color(0.68, 0.66, 0.63))
	_boxes(teeth, Color(0.6, 0.58, 0.56))

func _scenery() -> void:
	var b := bounds().grow(trk.wall + 50.0)
	var kinds := {}
	var add := func(name: String, xf: Transform3D) -> void:
		if not kinds.has(name):
			kinds[name] = []
		kinds[name].append(xf)
	var pick_tree := func() -> String:
		match theme:
			"snow": return ["tree-snow", "tree-pine-snow", "tree-pine-snow-small"][rng.randi() % 3]
			"forest": return ["tree-pine", "tree", "tree-pine-small", "tree-pine"][rng.randi() % 4]
			_: return ["tree", "tree-pine", "tree", "tree-pine-small"][rng.randi() % 4]
	if not trk.sky:
		var cell := 7.0
		var density: float = {"forest": 1.0, "snow": 0.7, "castle": 0.55}.get(theme, 0.8)
		var y := b.position.y
		while y < b.end.y:
			var x := b.position.x
			while x < b.end.x:
				var p := Vector2(x + rng.randf_range(-3, 3), y + rng.randf_range(-3, 3))
				var loc := Rules.locate(trk, p)
				var d: float = absf(loc.lat) - float(loc.wall)
				var r := rng.randf()
				if d > 2.0 and d < 50.0 and r < density - d * 0.006:
					var rot := rng.randf() * TAU
					var pk := rng.randf()
					if pk < 0.62:
						add.call(pick_tree.call(), _xf(p, rot, rng.randf_range(2.2, 3.6)))
					elif pk < 0.72:
						add.call("rocks" if theme != "snow" else "block-snow-low", _xf(p, rot, rng.randf_range(1.4, 2.4)))
					elif pk < 0.8:
						add.call("mushrooms" if theme == "forest" else ("flowers-tall" if theme != "snow" else "tree-pine-snow-small"), _xf(p, rot, rng.randf_range(1.6, 2.8) * (2.0 if theme == "forest" else 1.0)))
					elif pk < 0.88:
						add.call("hedge" if theme != "snow" else "crate", _xf(p, rot, rng.randf_range(1.2, 1.8)))
					elif pk < 0.94:
						add.call("stones", _xf(p, rot, rng.randf_range(1.2, 2.0)))
					else:
						add.call("grass" if theme != "snow" else "stones", _xf(p, rot, rng.randf_range(1.5, 2.5)))
				elif d > 0.5 and d < 2.0 and r < 0.3 and theme != "snow":
					add.call("flowers" if rng.randf() < 0.6 else "grass", _xf(p, rng.randf() * TAU, rng.randf_range(1.0, 1.6)))
				x += cell
			y += cell
		# 길섶 안쪽 풀·꽃 (달리는 데 막히지 않음)
		for i in range(0, trk.n, 4):
			for side in [-1.0, 1.0]:
				if ground(i) and rng.randf() < 0.3 and theme != "snow":
					var lat: float = side * rng.randf_range(trk.half_width + 2.0, trk.wall - 0.6)
					var p2: Vector2 = trk.pts[i] + trk.nrm[i] * lat
					add.call("flowers" if rng.randf() < 0.5 else "grass", _xf(p2, rng.randf() * TAU, rng.randf_range(0.9, 1.4)))
		# 동전·별 모양 큰 장식
		for k2 in 6:
			var i3: int = rng.randi() % trk.n
			var side2 := -1.0 if rng.randf() < 0.5 else 1.0
			var p3: Vector2 = trk.pts[i3] + trk.nrm[i3] * side2 * (trk.wall + rng.randf_range(6, 14))
			if clear_of_track(p3, 3.0):
				_put(["chest", "barrel", "crate", "sign"][k2 % 4], Vector3(p3.x, 0, p3.y), rng.randf() * TAU, 1.6)
	else:
		_islands(add, pick_tree)
	for k in kinds:
		_multi(k, kinds[k], k.begins_with("tree") or k in ["rocks", "hedge"])
	# 길 위 아치 (구간이 없는 곳에)
	if theme in ["snow", "grass", "sky"]:
		var n := 3 if theme == "snow" else 2
		var placed := 0
		var s: float = trk.length * 0.15
		while placed < n and s < trk.length * 0.95:
			var ok := true
			for o in [-8.0, 0.0, 8.0]:
				if not Rules.zone_at(trk, s + o).is_empty():
					ok = false
			if ok and absf(float(trk.curv[int(s / trk.length * trk.n) % trk.n])) < 0.02:
				_arch(s)
				placed += 1
				s += trk.length * 0.25
			else:
				s += 10.0

## 하늘 섬: 길 밑 흙덩이 + 떠 있는 섬
func _islands(add: Callable, pick_tree: Callable) -> void:
	for k in 14:
		var ang := rng.randf() * TAU
		var c := bounds().get_center() + Vector2(cos(ang), sin(ang)) * rng.randf_range(60, 220)
		if not clear_of_track(c, 12.0):
			continue
		var r := rng.randf_range(5, 12)
		var y := rng.randf_range(-14, 6)
		_island(Vector3(c.x, y, c.y), r)
		for t in 3:
			var tp := c + Vector2(rng.randf_range(-r * 0.6, r * 0.6), rng.randf_range(-r * 0.6, r * 0.6))
			add.call(pick_tree.call(), _xf(tp, rng.randf() * TAU, rng.randf_range(2.0, 3.2), y))

func _island(pos: Vector3, r: float) -> void:
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 0.9
	cm.height = 1.2
	cm.radial_segments = 10
	top.mesh = cm
	top.material_override = BoardView.mat(col("ground"))
	top.position = pos + Vector3(0, -0.6, 0)
	add_child(top)
	var cone := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = r * 0.9
	cc.bottom_radius = 0.6
	cc.height = r * 1.4
	cc.radial_segments = 10
	cone.mesh = cc
	cone.material_override = BoardView.mat(Color(0.62, 0.45, 0.32))
	cone.position = pos + Vector3(0, -1.2 - r * 0.7, 0)
	add_child(cone)

func _clouds() -> void:
	var m := BoardView.mat(Color(1, 1, 1, 0.92), false, true)
	var b := bounds().grow(120.0)
	for k in 70:
		var p := Vector2(rng.randf_range(b.position.x, b.end.x), rng.randf_range(b.position.y, b.end.y))
		var y := rng.randf_range(-38, -18) if rng.randf() < 0.8 else rng.randf_range(25, 40)
		for j in 3:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r := rng.randf_range(5, 11)
			sm.radius = r
			sm.height = r * 1.0
			sm.radial_segments = 12
			sm.rings = 6
			mi.mesh = sm
			mi.material_override = m
			mi.position = Vector3(p.x + j * r * 0.9, y + rng.randf_range(-1, 1), p.y + rng.randf_range(-r, r) * 0.5)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

## 하늘 길 밑: 풀 덮인 흙 (길 옆면) + 난간
func _sky_deck() -> void:
	var hw: float = trk.half_width
	var grass := BoardView.mat(col("ground"))
	var keep := func(i: int) -> bool: return not in_gap(i) and not in_gap((i + 1) % trk.n)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = col("ground")
	_strip(-hw - 1.2, -hw - 0.85, 0.03, gm, keep)
	_strip(hw + 0.85, hw + 1.2, 0.03, gm, keep)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: int = trk.n
	for i in m:
		var j := (i + 1) % m
		if not keep.call(i):
			continue
		var hi := Rules.height_at(trk, i)
		var hj := Rules.height_at(trk, j)
		for sd in [-1.0, 1.0]:
			var a: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw + 1.2)
			var b: Vector2 = trk.pts[j] + trk.nrm[j] * sd * (hw + 1.2)
			var a2: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw * 0.4)
			var b2: Vector2 = trk.pts[j] + trk.nrm[j] * sd * (hw * 0.4)
			var nn := Vector3(trk.nrm[i].x * sd, -0.4, trk.nrm[i].y * sd).normalized()
			for v in [Vector3(a.x, hi + 0.03, a.y), Vector3(b.x, hj + 0.03, b.y), Vector3(a2.x, hi - 5.0, a2.y), Vector3(a2.x, hi - 5.0, a2.y), Vector3(b.x, hj + 0.03, b.y), Vector3(b2.x, hj - 5.0, b2.y)]:
				st.set_color(Color(0.62, 0.45, 0.32))
				st.set_normal(nn)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	_rails(keep)

## 낮은 난간 (하늘 길·다리)
func _rails(keep: Callable) -> void:
	var hw: float = trk.half_width
	var posts := []
	var bars := {"a": [], "b": []}
	for i in trk.n:
		if not keep.call(i):
			continue
		var j: int = (i + 1) % trk.n
		for sd in [-1.0, 1.0]:
			var a: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw + 0.75)
			var b: Vector2 = trk.pts[j] + trk.nrm[j] * sd * (hw + 0.75)
			var mid := (a + b) * 0.5
			var hm := (Rules.height_at(trk, i) + Rules.height_at(trk, j)) * 0.5
			var yaw := atan2(b.x - a.x, b.y - a.y)
			bars["a" if (i / 2) % 2 == 0 else "b"].append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.22, 0.22, a.distance_to(b) + 0.05)), Vector3(mid.x, hm + 0.75, mid.y)))
			if i % 3 == 0:
				posts.append(Transform3D(Basis().scaled(Vector3(0.22, 0.8, 0.22)), Vector3(a.x, Rules.height_at(trk, i) + 0.4, a.y)))
	_boxes(bars.a, col("edge"))
	_boxes(bars.b, col("edge2"))
	_boxes(posts, Color(0.95, 0.95, 0.98))

## 다리 (성곽 8자 길): 옆면·난간·기둥
func _bridges() -> void:
	var hw: float = trk.half_width
	var m: int = trk.n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in m:
		var j := (i + 1) % m
		var hi := Rules.height_at(trk, i)
		var hj := Rules.height_at(trk, j)
		if hi < 0.3 and hj < 0.3:
			continue
		for sd in [-1.0, 1.0]:
			var a: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw + 0.9)
			var b: Vector2 = trk.pts[j] + trk.nrm[j] * sd * (hw + 0.9)
			var nrm3 := Vector3(trk.nrm[i].x * sd, 0, trk.nrm[i].y * sd)
			for v in [Vector3(a.x, hi + 0.05, a.y), Vector3(b.x, hj + 0.05, b.y), Vector3(a.x, maxf(0.0, hi - 1.0), a.y),
				Vector3(a.x, maxf(0.0, hi - 1.0), a.y), Vector3(b.x, hj + 0.05, b.y), Vector3(b.x, maxf(0.0, hj - 1.0), b.y)]:
				st.set_normal(nrm3)
				st.add_vertex(v)
	var side := MeshInstance3D.new()
	side.mesh = st.commit()
	var sm := BoardView.mat(Color(0.7, 0.67, 0.63)).duplicate()
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	side.material_override = sm
	add_child(side)
	var deck := BoardView.mat(Color(0.62, 0.6, 0.58))
	_strip(-hw - 0.9, -hw, 0.015, deck, func(i: int) -> bool: return not ground(i))
	_strip(hw, hw + 0.9, 0.015, deck, func(i: int) -> bool: return not ground(i))
	_rails(func(i: int) -> bool: return not ground(i) or not ground((i + 1) % m))
	var pillars := []
	for i in range(0, m, 6):
		var h := Rules.height_at(trk, i)
		if h < 1.5:
			continue
		for sd in [-1.0, 1.0]:
			var p: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw - 1.2)
			if _over_other_road(p, i):
				continue
			pillars.append(Transform3D(Basis().scaled(Vector3(1.2, h - 0.4, 1.2)), Vector3(p.x, (h - 0.4) * 0.5, p.y)))
	_boxes(pillars, Color(0.72, 0.68, 0.62))

func _over_other_road(p: Vector2, i: int) -> bool:
	var m: int = trk.n
	for j in range(0, m, 2):
		var di := absi(j - i)
		di = mini(di, m - di)
		if di < 25:
			continue
		if (trk.pts[j] as Vector2).distance_to(p) < trk.half_width + 3.0:
			return true
	return false

## 줄무늬 아치 (길 위)
func _arch(s: float) -> void:
	var p := Rules.point_at(trk, s)
	var t: Vector2 = p.tan
	var root := Node3D.new()
	var q: Vector2 = p.pos
	root.position = Vector3(q.x, float(p.h), q.y)
	root.rotation.y = atan2(t.x, t.y)
	add_child(root)
	var R: float = trk.half_width + 1.8
	var cols := [Color(0.62, 0.45, 0.95), Color(1, 1, 1), Color(1.0, 0.78, 0.25), Color(1, 1, 1), Color(1.0, 0.5, 0.35), Color(1, 1, 1)]
	var segs := 18
	for k in segs:
		var a0 := PI * float(k) / segs
		var a1 := PI * float(k + 1) / segs
		var c0 := Vector3(cos(a0) * R, sin(a0) * R * 0.75, 0)
		var c1 := Vector3(cos(a1) * R, sin(a1) * R * 0.75, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.55
		cm.height = c0.distance_to(c1) + 0.05
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = BoardView.mat(cols[k % cols.size()])
		mi.position = (c0 + c1) * 0.5
		var dir := (c1 - c0).normalized()
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
		root.add_child(mi)

## 둥근 탑 (흰 몸통 + 색 띠 + 뾰족 지붕)
func _tower(p: Vector3, r: float, h: float, body: Color, band: Color) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, 0.0 if ground(0) else p.y, p.z)
	add_child(root)
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.85
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	b.mesh = cm
	b.material_override = BoardView.mat(body)
	b.position.y = h * 0.5
	root.add_child(b)
	for k in 3:
		var ring := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		var yy := h * (0.25 + 0.3 * k)
		var rr := lerpf(r, r * 0.85, yy / h) + 0.06
		rc.top_radius = rr
		rc.bottom_radius = rr
		rc.height = 0.5
		rc.radial_segments = 16
		ring.mesh = rc
		ring.material_override = BoardView.mat(band)
		ring.position.y = yy
		root.add_child(ring)
	var roof := MeshInstance3D.new()
	var rf := CylinderMesh.new()
	rf.top_radius = 0.0
	rf.bottom_radius = r * 1.15
	rf.height = r * 1.6
	rf.radial_segments = 16
	roof.mesh = rf
	roof.material_override = BoardView.mat(band.darkened(0.15))
	roof.position.y = h + r * 0.8
	root.add_child(roof)
	var win := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(0.6, 0.9, 0.1)
	win.mesh = wb
	win.material_override = BoardView.mat(Color(0.25, 0.3, 0.45))
	win.position = Vector3(0, h * 0.72, r * 0.88)
	root.add_child(win)

func _boxes(xforms: Array, c: Color) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.material = BoardView.mat(c)
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

func _cylinders(xforms: Array, c: Color, top: Color) -> void:
	if xforms.is_empty():
		return
	for pair in [[c, 1.0], [top, 0.0]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5 if pair[1] > 0.0 else 0.44
		cm.bottom_radius = 0.5 if pair[1] > 0.0 else 0.44
		cm.height = 2.0 if pair[1] > 0.0 else 0.04
		cm.radial_segments = 12
		cm.material = BoardView.mat(pair[0])
		mm.mesh = cm
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var xf: Transform3D = xforms[i]
			if pair[1] == 0.0:
				xf = xf.translated(Vector3(0, xf.basis.get_scale().y * 1.0 + 0.01, 0))
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
