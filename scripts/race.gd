extends Node3D
## 경주 한 판: 트랙 그림·보드·컴퓨터·카메라·순위·팀

signal done(result: Dictionary)
signal quit_race

const AI_NAMES := ["하늘", "구름", "별빛", "바다", "솔솔", "새벽", "노을", "봄비", "단비", "보라", "모래", "이슬"]
const TEAM_COLORS := [Color(1.0, 0.42, 0.42), Color(0.38, 0.62, 1.0)]
const TEAM_NAMES := ["빨강팀", "파랑팀"]
const COUNT := 3.6
const FALL_TIME := 1.3

var def: Dictionary
var trk: Dictionary
var line: PackedFloat32Array
var mode := "race"
var racers: Array = []
var humans: Array = []
var state := "count"       # count → run → end
var count_left := COUNT
var clock := 0.0
var end_wait := -1.0
var view: TrackView
var cams: Array = []
var huds: Array = []
var coins: Array = []
var rng := RandomNumberGenerator.new()
var autopilot := false      # 개발용: 사람 보드도 컴퓨터가 몬다
var pause_menu: Control
var touchpad: Control
var _last_beep := 4
var online := false
var is_host := false
var remote_humans: Array = []
var by_pid := {}
var host_order: Array = []
var _send_t := 0.0
var _wait_remote := -1.0
var _lost_said := false
var items_on := false
var items: Node3D
var teams := false

## 컴퓨터 상대 설정 (온라인이면 방장이 만들어 친구에게 보낸다)
static func make_ai_specs(n: int, level: int, r: RandomNumberGenerator) -> Array:
	var ids: Array = Game.boards.filter(func(b): return not b.get("rare", false)).map(func(b): return b.id)
	var names := AI_NAMES.duplicate()
	var out := []
	for i in n:
		var j := r.randi_range(i, names.size() - 1)
		var tmp = names[i]; names[i] = names[j]; names[j] = tmp
		out.append({
			"board": ids[r.randi_range(0, mini(ids.size() - 1, 2 + level))], "name": names[i],
			"rider": Rules.RIDERS[r.randi_range(0, Rules.RIDERS.size() - 1)],
			"skill": clampf(0.4 + 0.55 * float(i) / maxf(1.0, n - 1) + r.randf_range(-0.08, 0.08), 0.3, 1.0) * (0.86 + 0.04 * float(level)),
			"offset": r.randf_range(-3.2, 3.2),
		})
	return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mode = Game.mode
	def = Game.track_def(Game.track_id)
	trk = Rules.build_track(def)
	line = Rules.racing_line(trk)
	rng.seed = int(Time.get_ticks_usec())
	view = TrackView.new()
	add_child(view)
	view.build(def, trk, true)
	online = mode == "online"
	var setup: Dictionary = Game.online_setup if online else {}
	is_host = online and Net.role == "host"
	teams = mode == "team" or (online and setup.get("teams", false))
	var players: Array = setup.get("players", []) if online else []
	var n_humans := players.size() if online else 1
	var specs: Array = []
	if online:
		specs = setup.get("ai", [])
	elif mode in ["race", "team"]:
		specs = make_ai_specs(7, int(def.level), rng)
	var n_ai := specs.size()
	var total := n_humans + n_ai
	var human_slots: Array = []
	for i in n_humans:
		human_slots.append(total - 1 - i if n_ai > 0 else i)
	var ref_stats := {}
	var made := 0
	if online:
		for j in players.size():
			var pl: Dictionary = players[j]
			var mine := int(pl.pid) == Net.my_pid
			var r := _make_racer(Game.board_def(str(pl.board)), str(pl.get("rider", "oobi")), human_slots[j], mine, j % 2 if teams else -1, str(pl.name) if not mine else Game.save.name)
			if mine:
				humans.append(r)
			else:
				r.remote = true
				remote_humans.append(r)
			r.pid = int(pl.pid)
			by_pid[int(pl.pid)] = r
			host_order.append(r)
			if ref_stats.is_empty() or r.st.max_speed < ref_stats.max_speed:
				ref_stats = r.st
			made += 1
	else:
		var r := _make_racer(Game.board_def(Game.save.board), Game.save.rider, human_slots[0], true, 0 if teams else -1, Game.save.name)
		humans.append(r)
		ref_stats = r.st
		made = 1
	var ai_i := 0
	for slot in total:
		if slot in human_slots:
			continue
		var sp: Dictionary = specs[ai_i]
		var team := -1
		if teams:
			team = (made + ai_i) % 2 if online else (0 if ai_i < 3 else 1)
		var r := _make_racer(Game.board_def(sp.board), str(sp.get("rider", "oobi")), slot, false, team, sp.name)
		r.skill = float(sp.skill)
		r.offset = float(sp.offset)
		r.ref = ref_stats
		r.remote = online and not is_host
		host_order.append(r)
		ai_i += 1
	if online:
		Net.message.connect(_on_net)
	items_on = Game.items and mode in ["race", "team"]
	if items_on:
		for r in racers:
			r.k.no_gauge = true
		items = preload("res://scripts/race_items.gd").new()
		add_child(items)
		items.setup(self)
	_place_coins()
	_make_views()
	if DisplayServer.is_touchscreen_available():
		touchpad = preload("res://scripts/touchpad.gd").new()
		$UI.add_child(touchpad)
		Controls.touch["on"] = true
	_make_pause()
	for r in racers:
		_show(r, 0.0, 0.016)
	Sound.music(str(def.get("music", "race")))
	Sound.engine_on(1, true)

func _make_racer(bdef: Dictionary, rider: String, slot: int, human: bool, team: int, name: String) -> Dictionary:
	var g := Rules.grid_slot(trk, slot)
	var k := Rules.new_board(g.pos, g.yaw, g.h)
	var node := BoardView.new()
	add_child(node)
	var tag_col: Color = TEAM_COLORS[team] if team >= 0 else (Color(1.0, 0.85, 0.25) if human else Color.from_string(Game.rider_def(rider).color, Color.WHITE))
	node.setup(bdef, rider, name, tag_col)
	node.snow = str(def.get("theme", "")) == "snow"
	var r := {
		"k": k, "st": Rules.board_stats(bdef), "def": bdef, "node": node, "human": human, "rider": rider,
		"name": name, "color": tag_col, "skill": 1.0, "offset": 0.0, "ref": {}, "team": team,
		"hint": -1, "dist": Rules.locate(trk, k.pos).s - trk.length, "finish": -1.0, "place": slot + 1,
		"coins": 0, "prev": {}, "start_press": -1.0, "wrong": 0.0, "steer": 0.0,
		"lap": 1, "remote": false, "net": {}, "pid": -1, "gone": false, "plan": {}, "fall_t": -1.0, "g": {"h": g.h, "kind": "road", "ramp_t": -1.0},
	}
	racers.append(r)
	return r

func _place_coins() -> void:
	var groups := 7
	for gi in groups:
		var s0: float = trk.length * (gi + 0.35) / groups
		var side: float = rng.randf_range(-0.55, 0.55) * trk.half_width
		for c in 5:
			var s: float = s0 + c * 3.0
			if not Rules.zone_at(trk, s).is_empty():
				continue
			var pa := Rules.point_at(trk, s)
			var p: Vector2 = pa.pos + (pa.nrm as Vector2) * side
			var holder := Node3D.new()
			holder.position = Vector3(p.x, 1.0 + float(pa.h), p.y)
			var mi := MeshInstance3D.new()
			mi.mesh = view.kit_mesh("coin-gold")
			mi.scale = Vector3.ONE * 0.75
			holder.add_child(mi)
			add_child(holder)
			coins.append({"pos": p, "node": holder, "away": 0.0, "h": float(pa.h)})

func _make_views() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(svc)
	var sv := SubViewport.new()
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 500.0
	sv.add_child(cam)
	cam.current = true
	var h: Dictionary = humans[0]
	var hud := Hud.new()
	hud.race = self
	hud.racer = h
	svc.add_child(hud)
	huds.append(hud)
	h["hud"] = hud
	cams.append({"cam": cam, "yaw": h.k.yaw, "shake": 0.0, "racer": h, "h": float(h.k.alt)})

func _make_pause() -> void:
	pause_menu = preload("res://scripts/pause_menu.gd").new()
	pause_menu.race = self
	$UI.add_child(pause_menu)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_P):
		if state != "end":
			pause_menu.open()
			get_viewport().set_input_as_handled()

func _physics_process(dt: float) -> void:
	if state == "count":
		_countdown(dt)
	elif state in ["run", "end"]:
		clock += dt
		_drive(dt)
	for r in racers:
		_show(r, r.steer, dt)
	_coins(dt)
	_cameras(dt)
	if online:
		_net_tick(dt)
	var h: Dictionary = humans[0]
	var k: Dictionary = h.k
	Sound.engine(1, absf(Rules.speed_of(k)) / maxf(1.0, h.st.max_speed), Rules.boosting(k), 1)
	Sound.skid(1, k.slide and state != "count", clampf(absf(float(k.slip)) / 0.35, 0.3, 1.0), 1)
	if _wait_remote > 0.0 and end_wait < 0.0:
		_wait_remote -= dt
		if _wait_remote <= 0.0 or _remotes_done() or not Net.connected():
			_wait_remote = 0.0
			state = "end"
			end_wait = 2.0
	if end_wait >= 0.0:
		end_wait -= dt
		if end_wait < 0.0:
			_finish()

func _countdown(dt: float) -> void:
	var before := count_left
	count_left -= dt
	var n := int(ceil(count_left))
	if n < _last_beep and n >= 1 and n <= 3:
		_last_beep = n
		Sound.play("beep")
	var h: Dictionary = humans[0]
	var c := Controls.read()
	var up: bool = c.throttle > 0.0
	if up and not h.prev.get("up", false):
		h.start_press = count_left
	h.prev.up = up
	if before > 0.0 and count_left <= 0.0:
		state = "run"
		clock = 0.0
		Sound.play("go")
		for r in racers:
			var boost := 0.0
			if r.human:
				if h.prev.get("up", false):
					boost = Rules.start_boost(r.start_press)
			elif not r.remote and rng.randf() < r.skill * 0.7:
				boost = 1.0
			if boost > 0.0:
				r.k.dash_t = 1.0
				if r.human:
					r.hud.pop("출발 부스터!", Color(0.5, 1.0, 0.6))
					Sound.play("dash")

## 공중에서 최근 누른 방향키 ("LRU" 처럼)
func cmd_text(r: Dictionary) -> String:
	var out := ""
	for c in r.get("cmd", []):
		out += str(c[0])
	return out.right(3)

## 사람 입력: 누른 순간만 점프·묘기·부스터
func _human_input(r: Dictionary) -> Dictionary:
	var c := Controls.read()
	var p: Dictionary = r.prev
	var tap := func(key: String) -> bool: return bool(c[key]) and not bool(p.get(key, false))
	# 묘기 커맨드: 공중에서 누른 방향키를 모아 두었다가 S·D·F와 합친다
	var k: Dictionary = r.k
	var cmd: Array = r.get_or_add("cmd", [])
	if k.air:
		for d in ["U", "D", "L", "R"]:
			if tap.call(d):
				cmd.append([d, clock])
	else:
		cmd.clear()
	while not cmd.is_empty() and clock - float(cmd[0][1]) > Rules.CMD_WINDOW:
		cmd.pop_front()
	var trick := ""
	var tkey := ""
	if tap.call("gb"): tkey = "s"
	elif tap.call("t360"): tkey = "d"
	elif tap.call("t720"): tkey = "f"
	if tkey != "":
		trick = Rules.trick_for(tkey, cmd_text(r))
		cmd.clear()
	var inp := {"throttle": c.throttle, "steer": c.steer, "slide": c.slide, "jump": tap.call("jump"), "trick": trick, "use_boost": tap.call("boost")}
	r.prev = c.duplicate()
	r.prev.up = c.throttle > 0.0
	# 막 누른 키는 화면 아래 버튼에 불이 들어오게
	if r.has("hud"):
		for key in ["jump", "gb", "t360", "t720"]:
			if c[key]:
				r.hud.key_flash(key)
	return inp

func _drive(dt: float) -> void:
	var lead_human := -INF
	for h in humans:
		lead_human = maxf(lead_human, h.dist)
	for rh in remote_humans:
		lead_human = maxf(lead_human, rh.dist)
	for r in racers:
		var k: Dictionary = r.k
		if r.remote:
			_follow_net(r, dt)
			continue
		if r.fall_t >= 0.0:
			r.fall_t -= dt
			k.vy -= Rules.GRAVITY * dt
			k.alt += k.vy * dt
			k.pos = (k.pos as Vector2) + (k.vel as Vector2) * dt * 0.5
			if r.fall_t < 0.0:
				_respawn(r)
			continue
		var loc := Rules.locate(trk, k.pos, r.hint, float(k.alt))
		r.hint = loc.i
		var g := Rules.ground_at(trk, loc)
		r.g = g
		var inp: Dictionary
		var st: Dictionary = r.st
		if r.human and r.finish < 0.0 and not autopilot:
			inp = _human_input(r)
			if items_on and inp.use_boost:
				items.use(r)
				inp.use_boost = false
		else:
			inp = Rules.ai_input(k, trk, line, loc, g, r.skill, r.offset, rng.randf(), r.plan, st)
			if not r.human:
				var behind: float = lead_human - r.dist if humans.size() > 0 else 0.0
				st = Rules.ai_stats(r.ref if not r.ref.is_empty() else r.st, r.skill, behind)
				st.gauge_gain = r.st.gauge_gain
				st.boost_time = r.st.boost_time
				st.trick_speed = r.st.trick_speed
				st.jump_v = r.st.jump_v
			if r.finish >= 0.0:
				inp.throttle = 0.6 if r.human else inp.throttle
			if items_on and not r.human and not (k.items as Array).is_empty():
				_ai_item(r, loc)
		r.steer = lerpf(r.steer, float(inp.steer), 1.0 - exp(-12.0 * dt))
		Rules.step(k, inp, st, g, dt)
		if not k.fell:
			if Rules.wall_push(trk, k, Rules.locate(trk, k.pos, r.hint, float(k.alt))):
				if absf(Rules.speed_of(k)) > 6.0:
					k.events.append("bump")
	_collide()
	if items_on:
		items.tick(dt)
	for r in racers:
		var k: Dictionary = r.k
		if r.remote:
			k.events.clear()
			continue
		var loc := Rules.locate(trk, k.pos, r.hint, float(k.alt))
		r.hint = loc.i
		var before: float = r.dist
		if r.fall_t < 0.0:
			r.dist = Rules.advance(r.dist, loc.s, trk.length)
		if (k.vel as Vector2).dot(loc.tan) < -3.0:
			r.wrong += dt
		else:
			r.wrong = 0.0
		var lap := Rules.lap_of(r.dist, trk.length)
		if r.finish < 0.0 and r.dist >= trk.length * trk.laps:
			r.finish = clock
			if r.human:
				Sound.play("finish")
				r.node.cheer()
				if online:
					Net.send({"y": "fin", "pid": Net.my_pid, "t": clock})
				_check_end()
		elif lap > r.lap and r.human and r.finish < 0.0 and before > 0.0:
			if lap == trk.laps:
				r.hud.say("마지막 바퀴!", Color(1, 0.6, 0.4), 1.8)
				if str(def.get("music", "race")) != "rush":
					Sound.music("rush")
			else:
				r.hud.say("%d 바퀴째" % lap, Color(0.9, 0.95, 1.0))
			Sound.play("lap")
		r.lap = maxi(r.lap, lap)
		if "fell" in k.events:
			r.fall_t = FALL_TIME
		if r.human:
			_events(r)
		k.events.clear()
	var order := Rules.ranking(racers)
	for p in order.size():
		racers[order[p]].place = p + 1
	if state == "run":
		var all_done := true
		for r in racers:
			if r.finish < 0.0:
				all_done = false
		if all_done:
			_check_end()

func _respawn(r: Dictionary) -> void:
	var loc := Rules.locate(trk, r.k.pos, r.hint)
	var rs := Rules.respawn_at(trk, loc.s)
	var keep := {"gauge": r.k.gauge, "boosts": r.k.boosts, "items": r.k.items, "no_gauge": r.k.no_gauge, "points": r.k.points, "tricks": r.k.tricks, "best_judge": r.k.best_judge}
	var k := Rules.new_board(rs.pos, rs.yaw, rs.h)
	for key in keep:
		k[key] = keep[key]
	k.vel = Rules.fwd(rs.yaw) * 8.0
	r.k = k
	r.hint = -1
	r.plan = {}
	r.dist = Rules.advance(r.dist, rs.s, trk.length)
	if r.human:
		r.hud.say("다시 출발!", Color(0.8, 0.95, 1.0), 1.2)

func _events(r: Dictionary) -> void:
	var hud: Hud = r.hud
	var k: Dictionary = r.k
	for e in k.events:
		match e:
			"jump":
				Sound.play("jump")
				if k.jump_judge >= 0:
					hud.judge(k.judge)
					Sound.play("judge%d" % int(k.jump_judge))
			"launch":
				Sound.play("jump", -6.0, 0.9)
			"spring":
				Sound.play("jump", 0.0, 1.35)
				Sound.play("boost", -8.0, 1.6)
				_shake(r, 0.15)
			"ring":
				Sound.play("coin", -2.0, 1.2)
				hud.say("고리 통과!", Color(1.0, 0.9, 0.4), 0.8)
			"trick":
				Sound.play("whoosh", -2.0, randf_range(0.95, 1.08))
			"trick_ok":
				hud.judge(k.judge)
				Sound.play("judge%d" % Rules.JUDGES.find(str(k.judge.word)))
				Sound.play("land", -6.0)
			"fail":
				hud.judge(k.judge)
				Sound.play("miss")
				_shake(r, 0.35)
			"land":
				Sound.play("land", -4.0)
			"stairs":
				Sound.play("bump", -10.0, randf_range(0.9, 1.2))
				_shake(r, 0.1)
			"fell":
				Sound.play("fall")
				hud.say("앗, 떨어졌어요!", Color(1, 0.6, 0.5), 1.4)
			"pad":
				Sound.play("dash")
				hud.flash = 0.6
			"slide":
				Sound.play("slide", -6.0)
			"item_get":
				Sound.play("item")
				var its: Array = k.items
				if not its.is_empty():
					hud.say(Rules.ITEM_NAMES.get(its[its.size() - 1], ""), Color(0.6, 0.9, 1.0), 1.0)
			"spin":
				Sound.play("hit")
				_shake(r, 0.4)
			"shield", "shield_break":
				Sound.play("shield")
			"throw", "drop", "quake":
				Sound.play("throw")
			"boost_gain":
				hud.say("부스터 +1", Color(1.0, 0.75, 0.3))
				Sound.play("gain")
			"boost":
				hud.flash = 1.0
				Sound.play("boost")
				_shake(r, 0.2)
			"bump":
				Sound.play("bump")
				_shake(r, 0.3)

func _shake(r: Dictionary, amount: float) -> void:
	for c in cams:
		if c.racer == r:
			c.shake = maxf(float(c.shake), amount)

## 보드끼리 부딪힘 (높이 차가 크면 안 부딪힌다)
func _collide() -> void:
	var rad := 1.0
	for i in racers.size():
		for j in range(i + 1, racers.size()):
			var a: Dictionary = racers[i].k
			var b: Dictionary = racers[j].k
			if absf(float(a.alt) - float(b.alt)) > 1.6:
				continue
			var d: Vector2 = (b.pos as Vector2) - (a.pos as Vector2)
			var dist := d.length()
			if dist >= rad * 2.0 or dist < 0.001:
				continue
			if racers[i].remote and racers[j].remote:
				continue
			var nrm := d / dist
			var sa := 0.5
			if racers[i].remote:
				sa = 0.0
			elif racers[j].remote:
				sa = 1.0
			var push := rad * 2.0 - dist
			a.pos = (a.pos as Vector2) - nrm * push * sa
			b.pos = (b.pos as Vector2) + nrm * push * (1.0 - sa)
			var rel := ((b.vel as Vector2) - (a.vel as Vector2)).dot(nrm)
			if rel < 0.0:
				var imp := -rel * 1.2
				a.vel = (a.vel as Vector2) - nrm * imp * sa
				b.vel = (b.vel as Vector2) + nrm * imp * (1.0 - sa)
				if imp > 4.0:
					if racers[i].human: a.events.append("bump")
					if racers[j].human: b.events.append("bump")

func _coins(dt: float) -> void:
	for c in coins:
		var node: Node3D = c.node
		node.rotation.y += dt * 3.0
		if c.away > 0.0:
			c.away -= dt
			node.visible = c.away <= 0.0
			continue
		for r in racers:
			if (r.k.pos as Vector2).distance_squared_to(c.pos) < 2.2 * 2.2 and absf(float(r.k.alt) - float(c.h)) < 2.4:
				c.away = 8.0
				node.visible = false
				if r.human and r.finish < 0.0:
					r.coins += Rules.COIN_VALUE
					Sound.play("coin")
				break

func _show(r: Dictionary, steer: float, dt: float) -> void:
	var gh := -999.0
	if r.has("g") and not r.g.is_empty():
		gh = float(r.g.h)
	(r.node as BoardView).show_state(r.k, steer, dt, gh)

## 카메라: 높이 떠서 비스듬히 내려다본다. 길 방향을 부드럽게 따라 돈다
func _cameras(dt: float) -> void:
	for c in cams:
		var r: Dictionary = c.racer
		var k: Dictionary = r.k
		var loc := Rules.locate(trk, k.pos, r.hint, float(k.alt))
		var ahead := Rules.point_at(trk, float(loc.s) + 8.0)
		var t: Vector2 = ahead.tan
		var track_yaw := atan2(t.x, t.y)
		var target_yaw := lerp_angle(track_yaw, float(k.yaw), 0.35)
		if float(k.get("spin_t", 0.0)) > 0.0:
			target_yaw = track_yaw
		var want_rate := wrapf(target_yaw - float(c.yaw), -PI, PI) * 2.6
		c.rate = lerpf(float(c.get("rate", 0.0)), want_rate, 1.0 - exp(-6.0 * dt))
		c.yaw = float(c.yaw) + float(c.rate) * dt
		var p: Vector2 = k.pos
		var f := Rules.fwd(c.yaw)
		var spd := absf(Rules.speed_of(k))
		c.spd = lerpf(float(c.get("spd", 0.0)), spd, 1.0 - exp(-2.0 * dt))
		# 공중이면 땅 높이를 따라간다 (점프할 때 화면이 덜 흔들리게)
		var base_h: float = float(r.g.h) if r.has("g") and float(r.g.get("h", 0.0)) > -5.0 else float(loc.h)
		var want_h := lerpf(float(k.alt), base_h, 0.6) if k.air else float(k.alt)
		if r.fall_t >= 0.0:
			want_h = float(loc.h)
		c.h = lerpf(float(c.h), want_h, 1.0 - exp(-4.0 * dt))
		var back := 7.6 + float(c.spd) * 0.05
		var up := 9.4 + float(c.spd) * 0.03
		var pos := Vector3(p.x - f.x * back, up + float(c.h), p.y - f.y * back)
		var cam: Camera3D = c.cam
		if c.shake > 0.0:
			c.shake = maxf(0.0, c.shake - dt)
			pos += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * c.shake * 0.5
		cam.position = pos
		cam.look_at(Vector3(p.x + f.x * 4.0, 0.9 + float(c.h), p.y + f.y * 4.0), Vector3.UP)
		var want := 52.0 + (8.0 if k.boost_t > 0.0 else (4.0 if k.dash_t > 0.0 else 0.0))
		c.fov = lerpf(float(c.get("fov", 52.0)), want, 1.0 - exp(-2.2 * dt))
		cam.fov = c.fov

func _check_end() -> void:
	if end_wait >= 0.0 or state == "end":
		return
	var humans_done := true
	for h in humans:
		if h.finish < 0.0:
			humans_done = false
	if online and humans_done and not _remotes_done() and Net.connected():
		if _wait_remote < 0.0:
			_wait_remote = 25.0
			humans[0].hud.say("친구를 기다리는 중…", Color(0.8, 0.9, 1.0), 3.0)
		humans_done = false
	var all_done := true
	for r in racers:
		if r.finish < 0.0:
			all_done = false
	if humans_done or all_done:
		state = "end"
		end_wait = 3.5 if not all_done else 2.5

func _finish() -> void:
	for r in racers:
		if r.finish < 0.0:
			var left: float = trk.length * trk.laps - r.dist
			r.finish = clock + left / maxf(10.0, absf(Rules.speed_of(r.k)) * 0.9)
	var order := Rules.ranking(racers)
	var table := []
	var team_places := [[], []]
	for p in order.size():
		var r: Dictionary = racers[order[p]]
		r.place = p + 1
		table.append({"name": r.name, "time": r.finish, "human": r.human, "place": p + 1, "board": r.def.name, "color": r.color, "team": r.team, "rider": r.rider})
		if r.team >= 0:
			team_places[r.team].append(p + 1)
	var h: Dictionary = humans[0]
	var reward := Rules.reward(h.place, racers.size(), mode)
	var players := [{"name": h.name, "place": h.place, "time": h.finish, "reward": reward, "coins": h.coins,
		"points": int(h.k.points), "tricks": int(h.k.tricks), "best_judge": int(h.k.best_judge)}]
	var result := {"mode": mode, "track": def.id, "track_name": def.name, "players": players, "table": table, "racers": racers.size(), "items": items_on}
	if teams:
		var s0 := Rules.team_score(team_places[0])
		var s1 := Rules.team_score(team_places[1])
		result.team_scores = [s0, s1]
		result.team_win = (s0 > s1 and h.team == 0) or (s1 > s0 and h.team == 1)
		result.my_team = h.team
	Sound.engine_on(1, false)
	Sound.skid(1, false)
	Controls.touch.clear()
	done.emit(result)

func leave() -> void:
	if online:
		Net.send({"y": "bye", "pid": Net.my_pid})
	Sound.engine_on(1, false)
	Sound.skid(1, false)
	Controls.touch.clear()
	quit_race.emit()

# ─────────── 온라인 ───────────

## 상태를 짧은 배열로: x, z, vx, vz, yaw, 표시(1 공중, 2 부스터, 4 대시, 8 슬라이드, 16 비틀, 32 빙글), 높이, 묘기 돎, 거리, 도착 시간, 핸들, 묘기 이름, 구르기
func _pack(r: Dictionary) -> Array:
	var k: Dictionary = r.k
	var f := (1 if k.air else 0) | (2 if k.boost_t > 0.0 else 0) | (4 if k.dash_t > 0.0 else 0) | (8 if k.slide else 0) | (16 if k.stumble_t > 0.0 else 0) | (32 if k.spin_t > 0.0 else 0)
	return [snappedf(k.pos.x, 0.01), snappedf(k.pos.y, 0.01), snappedf(k.vel.x, 0.01), snappedf(k.vel.y, 0.01),
		snappedf(k.yaw, 0.001), f, snappedf(float(k.alt), 0.01), snappedf(float(k.spin), 0.01), snappedf(r.dist, 0.01), snappedf(r.finish, 0.001), snappedf(r.steer, 0.01), str(k.trick), snappedf(float(k.flip), 0.01)]

func _apply(r: Dictionary, a: Array) -> void:
	if a.size() < 12:
		return
	r.net = {"pos": Vector2(a[0], a[1]), "vel": Vector2(a[2], a[3]), "yaw": float(a[4]), "alt": float(a[6]), "age": 0.0}
	var k: Dictionary = r.k
	var f := int(a[5])
	k.air = f & 1 != 0
	k.boost_t = 0.5 if f & 2 != 0 else 0.0
	k.dash_t = 0.5 if f & 4 != 0 else 0.0
	k.slide = f & 8 != 0
	k.stumble_t = 0.3 if f & 16 != 0 else 0.0
	k.spin_t = 0.3 if f & 32 != 0 else 0.0
	k.spin = float(a[7])
	r.dist = float(a[8])
	if r.finish < 0.0 and float(a[9]) >= 0.0:
		r.finish = float(a[9])
	r.steer = float(a[10])
	k.trick = str(a[11])
	k.flip = float(a[12]) if a.size() > 12 else 0.0
	if absf((k.pos as Vector2).distance_to(r.net.pos)) > 12.0:
		k.pos = r.net.pos
		k.yaw = r.net.yaw
		k.alt = r.net.alt

func _follow_net(r: Dictionary, dt: float) -> void:
	if r.net.is_empty():
		return
	var k: Dictionary = r.k
	r.net.age = minf(float(r.net.age) + dt, 0.4)
	var want: Vector2 = r.net.pos + r.net.vel * float(r.net.age)
	k.vel = r.net.vel
	k.pos = (k.pos as Vector2).lerp(want, 1.0 - exp(-12.0 * dt))
	k.yaw = lerp_angle(float(k.yaw), float(r.net.yaw), 1.0 - exp(-12.0 * dt))
	k.alt = lerpf(float(k.alt), float(r.net.alt), 1.0 - exp(-14.0 * dt))
	var loc := Rules.locate(trk, k.pos, r.hint, float(k.alt))
	r.hint = loc.i
	r.g = Rules.ground_at(trk, loc)

func _remotes_done() -> bool:
	for rh in remote_humans:
		if rh.finish < 0.0 and not rh.get("gone", false):
			return false
	return true

func _net_tick(dt: float) -> void:
	if not Net.connected():
		if not _lost_said and not humans.is_empty():
			_lost_said = true
			humans[0].hud.say("연결이 끊겼어요", Color(1, 0.5, 0.4), 4.0)
			for rh in remote_humans:
				rh.gone = true
			if state == "end" or humans[0].finish >= 0.0:
				_check_end()
		return
	_send_t -= dt
	if _send_t > 0.0:
		return
	_send_t = 0.05
	if is_host:
		var arr := []
		for r in host_order:
			arr.append(_pack(r))
		Net.send({"y": "s", "c": snappedf(clock, 0.01), "k": arr}, true)
	else:
		Net.send({"y": "s", "c": snappedf(clock, 0.01), "k": [_pack(humans[0])]}, true)

func _on_net(m: Dictionary) -> void:
	match m.get("y"):
		"s":
			var arr: Array = m.get("k", [])
			if is_host:
				var r: Dictionary = by_pid.get(int(m.get("from", -1)), {})
				if not r.is_empty() and r.remote and arr.size() > 0:
					_apply(r, arr[0])
			else:
				for i in mini(arr.size(), host_order.size()):
					if host_order[i].remote:
						_apply(host_order[i], arr[i])
		"fin":
			var pid := int(m.get("pid", m.get("from", -1)))
			var rf: Dictionary = by_pid.get(pid, {})
			if not rf.is_empty() and rf.remote and rf.finish < 0.0:
				rf.finish = float(m.t)
			if is_host:
				Net.send({"y": "fin", "pid": pid, "t": m.t}, false, -1, int(m.get("from", -1)))
			_check_end()
		"bye", "left":
			var pid2 := int(m.get("pid", m.get("from", -1)))
			var rb: Dictionary = by_pid.get(pid2, {})
			if not rb.is_empty() and rb.remote:
				rb.gone = true
				if not humans.is_empty():
					humans[0].hud.say("%s 나갔어요" % rb.name, Color(1, 0.6, 0.4), 3.0)
			if is_host and m.get("y") == "bye":
				Net.send({"y": "left", "pid": pid2}, false, -1, pid2)
			_check_end()

func _ai_item(r: Dictionary, loc: Dictionary) -> void:
	var ahead := INF
	var behind := INF
	for o in racers:
		if o == r:
			continue
		var d: float = o.dist - r.dist
		if d > 0.0:
			ahead = minf(ahead, d)
		else:
			behind = minf(behind, -d)
	var bend := 0.0
	for o2 in [4, 8, 12]:
		bend = maxf(bend, absf(float(trk.curv[(int(loc.i) + o2) % trk.n])) * 30.0)
	var it: String = (r.k.items as Array)[0]
	if Rules.ai_use_item(it, r.place, ahead, behind, bend < 0.3, items.threatened(r), rng.randf()):
		items.use(r)
