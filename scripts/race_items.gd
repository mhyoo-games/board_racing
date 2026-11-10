extends Node3D
## 아이템전: 아이템 상자, 날아가는 것(물풍선·먹구름), 깔아 둔 것(끈끈이). 규칙은 rules.gd의 아이템 부분.
## 공중에 높이 떠 있으면 바닥의 끈끈이를 피한다.

var race: Node
var trk: Dictionary
var boxes: Array = []      # {pos, h, node, away}
var shots: Array = []      # {kind, s, lat, speed, owner, target, life, node}
var traps: Array = []      # {pos, h, owner, arm, life, node}
var rng := RandomNumberGenerator.new()
var stats := {"get": 0, "use": 0, "hit": 0}

func setup(r: Node) -> void:
	race = r
	trk = r.trk
	rng.randomize()
	for f in [0.12, 0.31, 0.5, 0.69, 0.88]:
		var sf: float = trk.length * f
		while not Rules.zone_at(trk, sf).is_empty() or not Rules.zone_at(trk, sf + 6.0).is_empty():
			sf += 4.0
		var base: Dictionary = Rules.point_at(trk, sf)
		for c in 6:
			var lat: float = (c - 2.5) * trk.half_width * 0.32
			var p: Vector2 = base.pos + base.nrm * lat
			var node := _box_node()
			node.position = Vector3(p.x, 1.2 + base.h, p.y)
			add_child(node)
			boxes.append({"pos": p, "h": base.h, "node": node, "away": 0.0})

func _box_node() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 1.3, 1.3)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.3, 0.6, 1.0)
	m.emission_energy_multiplier = 0.8
	mi.material_override = m
	n.add_child(mi)
	var q := Label3D.new()
	q.text = "?"
	q.font = Game.font_bold
	q.font_size = 96
	q.pixel_size = 0.01
	q.outline_size = 10
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.modulate = Color(1, 1, 0.8)
	n.add_child(q)
	return n

func _ball(c: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = BoardView.mat(c)
	return mi

func _shot_node(kind: String) -> Node3D:
	var n := Node3D.new()
	if kind == "balloon":
		var b := _ball(Color(0.35, 0.7, 1.0, 0.85), 0.5)
		b.scale = Vector3(1, 1.15, 1)
		n.add_child(b)
	else:   # 먹구름 (동글동글 셋 + 번개)
		for i in 3:
			var b := _ball(Color(0.35, 0.36, 0.45), 0.55)
			b.position = Vector3((i - 1) * 0.55, 1.2 + 0.1 * (i % 2), 0)
			n.add_child(b)
		var bolt := _ball(Color(1.0, 0.95, 0.3), 0.18)
		bolt.scale = Vector3(0.5, 2.2, 0.5)
		bolt.position = Vector3(0, 0.5, 0)
		n.add_child(bolt)
	return n

func _trap_node() -> Node3D:
	var n := Node3D.new()
	var goo := _ball(Color(0.55, 0.9, 0.35, 0.9), 1.0)
	goo.scale = Vector3(1.2, 0.18, 1.2)
	goo.position.y = 0.08
	n.add_child(goo)
	for i in 3:
		var bub := _ball(Color(0.7, 1.0, 0.5, 0.9), 0.22)
		bub.position = Vector3(cos(i * 2.1) * 0.5, 0.2, sin(i * 2.1) * 0.5)
		n.add_child(bub)
	return n

## 아이템 쓰기 (맨 앞 칸)
func use(r: Dictionary) -> void:
	var k: Dictionary = r.k
	var items: Array = k.get("items", [])
	if items.is_empty() or float(k.get("spin_t", 0.0)) > 0.0:
		return
	var it: String = items.pop_front()
	k.items = items
	stats.use += 1
	match it:
		"boost":
			k.boost_t = r.st.boost_time
			k.events.append("boost")
		"shield":
			k.shield_t = Rules.SHIELD_TIME
			k.events.append("shield")
		"goo":
			var p: Vector2 = (k.pos as Vector2) - Rules.fwd(k.yaw) * 2.8
			var gl := Rules.locate(trk, p, r.hint, float(k.alt))
			var gh: float = Rules.ground_at(trk, gl).h
			var node := _trap_node()
			node.position = Vector3(p.x, gh, p.y)
			add_child(node)
			traps.append({"pos": p, "h": gh, "owner": r, "arm": 0.5, "life": 40.0, "node": node})
			k.events.append("drop")
		"balloon", "cloud":
			var loc := Rules.locate(trk, k.pos, r.hint)
			var target: Variant = null
			if it == "cloud":
				for o in race.racers:
					if o.place == r.place - 1:
						target = o
				if target == null:
					return
				if target.human:
					target.hud.say("먹구름이 쫓아와요!", Color(0.8, 0.85, 1.0), 2.0)
			var node2 := _shot_node(it)
			add_child(node2)
			shots.append({"kind": it, "s": r.dist + 2.5, "lat": float(loc.lat), "speed": maxf(56.0, k.vel.length() + 24.0),
				"owner": r, "target": target, "life": 5.0 if it == "balloon" else 9.0, "node": node2})
			k.events.append("throw")
		"quake":
			for o in race.racers:
				if o.place < r.place and o.finish < 0.0 and not o.k.air:
					if Rules.hit(o.k, 0.9) and o.human:
						o.hud.say("쿵쿵! 땅이 흔들려요", Color(1.0, 0.85, 0.6), 1.5)
			k.events.append("quake")

func _process(dt: float) -> void:
	if race == null:
		return
	for b in boxes:
		(b.node as Node3D).rotation.y += dt * 1.5
		if b.away > 0.0:
			b.away -= dt
			b.node.visible = b.away <= 0.0

func tick(dt: float) -> void:
	# 상자 먹기
	for b in boxes:
		if b.away > 0.0:
			continue
		for r in race.racers:
			if r.remote:
				continue
			var k: Dictionary = r.k
			if (k.pos as Vector2).distance_squared_to(b.pos) < 2.5 * 2.5 and absf(float(k.alt) - float(b.h)) < 2.6:
				b.away = 2.0
				b.node.visible = false
				if Rules.give_item(k, Rules.item_roll(r.place, race.racers.size(), rng.randf())):
					k.events.append("item_get")
					stats.get += 1
				break
	# 날아가는 것
	for sh in shots.duplicate():
		sh.life -= dt
		sh.s += sh.speed * dt
		if sh.kind == "cloud" and sh.target != null:
			var tl := Rules.locate(trk, sh.target.k.pos, sh.target.hint)
			sh.lat = lerpf(sh.lat, float(tl.lat), 1.0 - exp(-3.0 * dt))
			sh.speed = maxf(sh.speed, sh.target.k.vel.length() + 20.0)
		var pa := Rules.point_at(trk, sh.s)
		var lim: float = trk.half_width + 1.0
		var pos: Vector2 = pa.pos + pa.nrm * clampf(sh.lat, -lim, lim)
		(sh.node as Node3D).position = Vector3(pos.x, pa.h + (0.9 if sh.kind == "balloon" else 1.6) + sin(sh.life * 12.0) * 0.15, pos.y)
		(sh.node as Node3D).rotation.y += dt * (8.0 if sh.kind == "balloon" else 1.5)
		var gone: bool = sh.life <= 0.0
		for r in race.racers:
			if gone:
				break
			if r == sh.owner and sh.life > 4.6:
				continue
			if sh.kind == "cloud" and r != sh.target:
				continue
			var k: Dictionary = r.k
			if (k.pos as Vector2).distance_squared_to(pos) < 2.0 * 2.0 and absf(float(k.alt) - float(pa.h)) < 3.0:
				_hit(r, "물풍선에 맞았어요!" if sh.kind == "balloon" else "번개에 찌릿!")
				gone = true
		if sh.kind == "cloud" and sh.target != null and sh.target.finish >= 0.0:
			gone = true
		if gone:
			sh.node.queue_free()
			shots.erase(sh)
	# 함정
	for tp in traps.duplicate():
		tp.arm -= dt
		tp.life -= dt
		var gone2: bool = tp.life <= 0.0
		if tp.arm <= 0.0:
			for r in race.racers:
				var k: Dictionary = r.k
				if (k.pos as Vector2).distance_squared_to(tp.pos) < 1.8 * 1.8 and absf(float(k.alt) - float(tp.h)) < 1.0:
					_hit(r, "끈끈이에 붙었어요!")
					gone2 = true
					break
		if gone2:
			tp.node.queue_free()
			traps.erase(tp)

func _hit(r: Dictionary, msg: String) -> void:
	stats.hit += 1
	if Rules.hit(r.k) and r.human:
		r.hud.say(msg, Color(1, 0.55, 0.4), 1.6)

## 이 선수를 노리는 것이 있나 (컴퓨터가 방패를 쓸지)
func threatened(r: Dictionary) -> bool:
	for sh in shots:
		if sh.target == r or (sh.kind == "balloon" and sh.owner != r and r.dist - sh.s < 25.0 and r.dist > sh.s):
			return true
	return false
