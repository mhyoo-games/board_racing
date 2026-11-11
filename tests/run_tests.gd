extends SceneTree
## godot --headless -s tests/run_tests.gd  (보드 규칙·점프·묘기 판정·트랙·상점·저장이 맞는지 확인)

var fails := 0
var passes := 0
var boards: Array = []
var tracks: Array = []
const DT := 1.0 / 60.0

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		printerr("실패: ", what)

func _init() -> void:
	var bj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boards.json"))
	boards = bj.boards
	tracks = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks.json")).tracks
	_data(bj)
	_riding()
	_jumps()
	_tricks()
	_commands()
	_features()
	_gauge()
	_surfaces()
	_track_geometry()
	_race_rules()
	_shop_and_save()
	_items()
	_net_codes()
	_room_codes()
	_full_laps()
	print("통과 %d, 실패 %d" % [passes, fails])
	quit(1 if fails > 0 else 0)

func board(id: String) -> Dictionary:
	for b in boards:
		if b.id == id: return b
	return {}

func flat() -> Dictionary:
	return {"h": 0.0, "kind": "road", "ramp_t": -1.0, "pad": false}

## 곧은 길에서 n초 달리기
func run(k: Dictionary, st: Dictionary, secs: float, inp := {"throttle": 1.0}, g := {}) -> void:
	var gg := flat() if g.is_empty() else g
	var t := 0.0
	while t < secs:
		Rules.step(k, inp, st, gg, DT)
		t += DT

func _data(bj: Dictionary) -> void:
	var ids := {}
	var last := -1
	for b in boards:
		ok(not ids.has(b.id), "보드 id 겹치지 않음: " + b.id)
		ids[b.id] = true
		for s in ["speed", "accel", "handling", "jump", "trick", "boost"]:
			ok(b.stats.has(s) and b.stats[s] >= 1 and b.stats[s] <= 10, "%s 능력치 %s 1~10" % [b.id, s])
		for c in ["deck", "trim", "glow"]:
			ok(Color.html_is_valid(b.look[c]), b.id + " 색 " + c)
		ok(b.look.tail in ["round", "split", "fork"], b.id + " 꼬리 모양")
		if not b.get("rare", false):
			ok(int(b.price) >= last, "상점 보드는 값 순서대로: " + b.id)
			last = int(b.price)
	ok(board(Rules.START_BOARD).price == 0 and not board(Rules.START_BOARD).get("rare", false), "처음 보드는 공짜")
	ok(boards.filter(func(b): return b.get("rare", false)).size() >= 2, "희귀 보드 둘 이상")
	ok(bj.riders.size() == Rules.RIDERS.size(), "캐릭터 수")
	for r in bj.riders:
		ok(r.id in Rules.RIDERS and FileAccess.file_exists("res://assets/kit/character-%s.glb" % r.id), "캐릭터 그림 " + r.id)
	ok(tracks.size() >= 5, "트랙 다섯 이상")
	for t in tracks:
		ok(t.points.size() >= 8 and t.half_width >= 6.0 and t.laps >= 1, t.id + " 트랙 정의")
		var has_ramp := false
		for z in t.zones:
			ok(z.type in ["ramp", "stairs", "ice", "gap", "pad", "spring", "ring"], t.id + " 구간 종류 " + str(z.type))
			if z.type == "ramp":
				ok(Rules.RAMPS.has(str(z.get("size", "normal"))), t.id + " 점프대 크기")
			has_ramp = has_ramp or z.type == "ramp"
		ok(has_ramp, t.id + " 점프대가 있다")

func _riding() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	var best := Rules.board_stats(board("comet"))
	ok(st.max_speed > 25.0 and best.max_speed > st.max_speed and best.max_speed < 36.0, "최고 속력 범위")
	var k := Rules.new_board(Vector2.ZERO, 0.0)
	run(k, st, 6.0)
	ok(absf(Rules.speed_of(k) - st.max_speed) < 0.6, "곧게 달리면 최고 속력 %.1f" % Rules.speed_of(k))
	ok(absf(k.pos.x) < 0.01 and k.pos.y > 80.0, "앞(+z)으로 간다")
	ok(not k.air and k.alt == 0.0, "땅에 붙어 있다")
	# 오른쪽으로 꺾으면 yaw가 준다
	var y0: float = k.yaw
	run(k, st, 0.5, {"throttle": 1.0, "steer": 1.0})
	ok(k.yaw < y0 - 0.3, "오른쪽 핸들 = yaw 감소")
	# 슬라이드는 더 크게 돈다
	var a := Rules.new_board(Vector2.ZERO, 0.0)
	var b := Rules.new_board(Vector2.ZERO, 0.0)
	a.vel = Vector2(0, 25); b.vel = Vector2(0, 25)
	run(a, st, 0.8, {"throttle": 1.0, "steer": 1.0})
	run(b, st, 0.8, {"throttle": 1.0, "steer": 1.0, "slide": true})
	ok(absf(b.yaw) > absf(a.yaw) * 1.2, "슬라이드는 더 꺾인다 %.2f > %.2f" % [absf(b.yaw), absf(a.yaw)])
	ok(absf(b.slip) > absf(a.slip), "슬라이드는 옆으로 미끄러진다")
	ok(b.gauge > 0.0 and a.gauge == 0.0, "슬라이드로 게이지가 조금 찬다")
	# 출발 부스터
	ok(Rules.start_boost(0.2) > 0.0 and Rules.start_boost(1.0) == 0.0, "출발 부스터 타이밍")

func _jumps() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	# 땅에서 폴짝
	var k := Rules.new_board(Vector2.ZERO, 0.0)
	k.vel = Vector2(0, 20)
	Rules.step(k, {"throttle": 1.0, "jump": true}, st, flat(), DT)
	ok(k.air and k.vy > 4.0 and "jump" in k.events, "점프하면 뜬다")
	var t := 0.0
	var top := 0.0
	while k.air and t < 3.0:
		Rules.step(k, {"throttle": 1.0}, st, flat(), DT)
		top = maxf(top, k.alt)
		t += DT
	ok(not k.air and t > 0.3 and t < 0.7, "땅 점프는 짧다 %.2f초" % t)
	ok(top > 0.5 and top < 2.5, "땅 점프 높이 %.1f" % top)
	ok(Rules.speed_of(k) > 19.0, "공중에서 속도를 거의 안 잃는다")
	# 점프대 판정
	ok(Rules.ramp_judge(0.95) == 2 and Rules.ramp_judge(0.7) == 1 and Rules.ramp_judge(0.2) == 0, "점프대 판정: 끝에 가까울수록 좋다")
	ok(Rules.land_judge(0.05) == 2 and Rules.land_judge(0.2) == 1 and Rules.land_judge(0.6) == 0, "착지 판정: 아슬아슬할수록 좋다")
	# 점프대에서 늦게(끝에서) 뛸수록 높이·멀리
	var airs := []
	for rt in [0.3, 0.7, 0.95, -1.0]:
		var b := Rules.new_board(Vector2.ZERO, 0.0)
		b.vel = Vector2(0, 28)
		var gh := Rules.RAMP_H * maxf(rt, 1.0 if rt < 0.0 else rt)
		b.alt = gh; b.prev_g = gh
		b.gvy = 28.0 * Rules.RAMP_H / Rules.RAMP_LEN
		if rt >= 0.0:
			Rules.step(b, {"throttle": 1.0, "jump": true}, st, {"h": gh, "kind": "road", "ramp_t": rt}, DT)
		else:
			# 안 누르고 끝을 넘으면 땅이 꺼져 그냥 날아간다
			Rules.step(b, {"throttle": 1.0}, st, flat(), DT)
		ok(b.air, "점프대에서 뜬다 (%s)" % rt)
		var tt := 0.0
		while b.air and tt < 4.0:
			Rules.step(b, {"throttle": 1.0}, st, flat(), DT)
			tt += DT
		airs.append(tt)
	ok(airs[2] > airs[1] and airs[1] > airs[0] and airs[0] > airs[3], "끝에서 뛸수록 오래 난다 %s" % [airs])
	ok(airs[2] > 1.1, "EXCELLENT 점프는 720을 할 만큼 길다 %.2f" % airs[2])
	ok(airs[3] > 0.25 and airs[3] < 0.8, "안 누르면 살짝만 뜬다 %.2f" % airs[3])
	var big := Rules.board_stats(board("droplet"))
	ok(big.jump_v > st.jump_v, "점프 능력치가 높으면 더 높이 뛴다")
	ok(absf(Rules.air_left(5.0, 2.0, 0.0) - (5.0 + sqrt(25.0 + 4.0 * Rules.GRAVITY)) / Rules.GRAVITY) < 0.001, "남은 공중 시간 계산")

## 점프대 끝에서 뛰어 묘기를 하고 착지까지
func trick_jump(st: Dictionary, ramp_t: float, tricks: Array, start_after := 0.0) -> Dictionary:
	var b := Rules.new_board(Vector2.ZERO, 0.0)
	b.vel = Vector2(0, 28)
	var gh := Rules.RAMP_H * ramp_t
	b.alt = gh; b.prev_g = gh
	Rules.step(b, {"throttle": 1.0, "jump": true}, st, {"h": gh, "kind": "road", "ramp_t": ramp_t}, DT)
	b.events.clear()
	var t := 0.0
	var queue := tricks.duplicate()
	var evs := []
	while b.air and t < 4.0:
		var tr := ""
		if t >= start_after and b.trick == "" and not queue.is_empty():
			tr = queue.pop_front()
		Rules.step(b, {"throttle": 1.0, "trick": tr}, st, flat(), DT)
		evs.append_array(b.events)
		b.events.clear()
		t += DT
	b.evs = evs
	return b

func _tricks() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	# 넉넉한 묘기는 성공 (GOOD/NICE)
	var a := trick_jump(st, 0.95, ["gb"])
	ok("trick_ok" in a.evs and a.stumble_t == 0.0, "짧은 묘기 성공")
	ok(a.judge.word in ["GOOD", "NICE"] and a.judge.label == "GB", "일찍 끝내면 GOOD/NICE (%s)" % a.judge.word)
	ok(a.gauge > 0.0 and a.combo == 1 and a.tricks == 1, "묘기 성공하면 게이지·콤보")
	# 남은 시간에 꼭 맞게 하면 EXCELLENT
	var left := Rules.air_left(st.jump_v * Rules.JUMP_MULT[2] + 0.0, Rules.RAMP_H * 0.95, 0.0)
	var start := left - Rules.trick_dur("360", st) - 0.06
	var b := trick_jump(st, 0.95, ["360"], start)
	ok(b.judge.get("word", "") == "EXCELLENT", "아슬아슬하게 끝내면 EXCELLENT (%s, 남은 %.2f)" % [b.judge.get("word", ""), left])
	ok(b.dash_t > 0.0, "EXCELLENT 착지는 살짝 부스터")
	ok(b.gauge > a.gauge * 1.5, "EXCELLENT·큰 묘기는 게이지가 더 찬다")
	# 시간이 모자라면 실패
	var c := trick_jump(st, 0.3, ["storm"])
	ok("fail" in c.evs and c.stumble_t > 0.0 and c.judge.word == "MISS", "땅에 닿기 전에 못 끝내면 실패")
	ok(c.combo == 0, "실패하면 콤보가 끊긴다")
	var sp0 := Rules.speed_of(c)
	run(c, st, 0.5)
	ok(Rules.speed_of(c) < sp0, "비틀거리면 느려진다")
	# 이어서 하기
	var d := trick_jump(st, 0.95, ["gb", "360"])
	ok("trick_ok" in d.evs and d.judge.label == "GB + 360", "묘기 이어서 하기 (%s)" % d.judge.get("label", ""))
	# 땅에서는 묘기 안 됨
	var e := Rules.new_board(Vector2.ZERO, 0.0)
	Rules.step(e, {"throttle": 1.0, "trick": "360"}, st, flat(), DT)
	ok(e.trick == "", "땅에서는 묘기를 못 한다")
	# 묘기 능력치가 높으면 빨리 끝난다
	var fast := Rules.board_stats(board("droplet"))
	ok(Rules.trick_dur("720", fast) < Rules.trick_dur("720", st), "묘기 능력치가 높으면 빨리 끝난다")

func air_time(st: Dictionary, ramp_t: float, g := {}) -> float:
	var b := Rules.new_board(Vector2.ZERO, 0.0)
	b.vel = Vector2(0, 28)
	var gh := 0.0
	var gg := {"h": 0.0, "kind": "road", "ramp_t": ramp_t}
	gg.merge(g, true)
	Rules.step(b, {"throttle": 1.0, "jump": true}, st, gg, DT)
	var t := 0.0
	while b.air and t < 6.0:
		Rules.step(b, {"throttle": 1.0}, st, flat(), DT)
		t += DT
	return t

func _commands() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	# 커맨드 고르기
	ok(Rules.trick_for("s", "") == "gb" and Rules.trick_for("d", "") == "360" and Rules.trick_for("f", "") == "720", "그냥 누르면 기본 묘기")
	ok(Rules.trick_for("d", "U") == "front" and Rules.trick_for("d", "D") == "back", "↑D 앞구르기, ↓D 뒤구르기")
	ok(Rules.trick_for("d", "LR") == "screw" and Rules.trick_for("d", "RL") == "screw", "←→D 꽈배기")
	ok(Rules.trick_for("f", "DU") == "storm" and Rules.trick_for("f", "LDU") == "storm", "↓↑F 회오리 (앞에 다른 키가 있어도)")
	ok(Rules.trick_for("f", "U") == "dfront" and Rules.trick_for("f", "UL") == "720", "마지막 키가 맞아야 한다")
	ok(Rules.trick_for("s", "LR") == "wing" and Rules.trick_for("s", "U") == "nose", "S 커맨드")
	for id in Rules.TRICKS:
		var t: Dictionary = Rules.TRICKS[id]
		ok(t.key in ["s", "d", "f"] and t.cmds.size() >= 1 and float(t.dur) > 0.2 and int(t.pts) >= 1, id + " 묘기 자료")
		for c in t.cmds:
			ok(Rules.trick_for(str(t.key), str(c)) == id, "%s 커맨드 %s" % [id, c])
	# 커맨드 묘기는 같은 시간에 점수가 더 크다
	var rate := func(id: String) -> float: return float(Rules.TRICKS[id].pts) / float(Rules.TRICKS[id].dur)
	ok(rate.call("front") > rate.call("360") and rate.call("storm") > rate.call("720"), "커맨드 묘기가 더 이득")
	# 오래 떠 있다
	var t_norm := air_time(st, 0.95)
	ok(t_norm > 1.4, "점프대 EXCELLENT 점프는 1.4초 넘게 뜬다 (오르막 속도 빼고) (%.2f초)" % t_norm)
	ok(air_time(st, 0.95, {"ramp_pow": 1.12}) > t_norm + 0.1, "큰 점프대는 더 오래")
	var hop := air_time(st, -1.0)
	ok(hop > 0.4 and hop < 0.9, "그냥 폴짝은 짧게 (%.2f초)" % hop)
	# 예약해서 이어 하기: 360 하는 중에 앞구르기를 누르면 끝나자마자 이어진다
	var b := Rules.new_board(Vector2.ZERO, 0.0)
	b.vel = Vector2(0, 28)
	b.alt = 1.33; b.prev_g = 1.33
	Rules.step(b, {"throttle": 1.0, "jump": true}, st, {"h": 1.33, "kind": "road", "ramp_t": 0.95}, DT)
	b.vy = 17.0      # 큰 점프대에서 오르막 속도까지 얹은 정도
	Rules.step(b, {"throttle": 1.0, "trick": "360"}, st, flat(), DT)
	Rules.step(b, {"throttle": 1.0, "trick": "front"}, st, flat(), DT)
	ok(b.trick == "360" and b.next == "front", "묘기 중에 누르면 예약")
	var t := 0.0
	var saw := false
	while b.air and t < 4.0:
		Rules.step(b, {"throttle": 1.0, "trick": "gb" if b.trick == "front" and b.next == "" else ""}, st, flat(), DT)
		saw = saw or (b.trick == "front")
		t += DT
	ok(saw and b.judge.get("chain", 0) == 3 and b.stumble_t == 0.0, "세 개 이어 하기 성공 (%s)" % b.judge.get("label", ""))
	ok(b.judge.label == "360 + 앞구르기 + GB", "이은 이름")
	# 구르기 각도
	var c := Rules.new_board(Vector2.ZERO, 0.0)
	c.air = true; c.alt = 5.0; c.vy = 10.0
	Rules.step(c, {"trick": "back"}, st, flat(), DT)
	run(c, st, 0.36, {"throttle": 1.0}, flat())
	ok(c.flip < -0.2 and c.flip > -0.8, "뒤구르기는 뒤로 돈다 (%.2f)" % c.flip)

func _features() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	# 스프링 발판은 저절로 튕긴다
	var b := Rules.new_board(Vector2.ZERO, 0.0)
	b.vel = Vector2(0, 25)
	Rules.step(b, {"throttle": 1.0}, st, {"h": 0.0, "kind": "road", "ramp_t": -1.0, "spring": true}, DT)
	ok(b.air and b.vy > Rules.SPRING_V - 1.0 and "spring" in b.events, "스프링 발판")
	# 공중 고리
	var k := Rules.new_board(Vector2.ZERO, 0.0)
	k.air = true; k.alt = 5.2; k.vy = 0.0
	var g0: float = k.gauge
	var ring := {"h": -20.0, "kind": "gap", "ramp_t": -1.0, "ring": {"i": 0, "y": 6.0, "lat": 0.5, "r": 3.2}}
	Rules.step(k, {"throttle": 1.0}, st, ring, DT)
	ok(k.gauge > g0 and "ring" in k.events, "고리를 지나가면 게이지")
	k.events.clear()
	Rules.step(k, {"throttle": 1.0}, st, ring, DT)
	ok(not ("ring" in k.events), "한 번 점프에 같은 고리는 한 번만")
	var m := Rules.new_board(Vector2.ZERO, 0.0)
	m.air = true; m.alt = 0.5; m.vy = 0.0
	Rules.step(m, {"throttle": 1.0}, st, {"h": -20.0, "kind": "gap", "ramp_t": -1.0, "ring": {"i": 0, "y": 6.0, "lat": 0.0, "r": 3.2}}, DT)
	ok(not ("ring" in m.events), "고리 아래로 지나가면 안 친다")
	# 점프대 크기
	var tr := Rules.build_track({"points": [[0, 0], [0, 200], [100, 200], [100, 0]], "half_width": 7.0, "zones": [
		{"type": "ramp", "at": 0.1, "size": "small"}, {"type": "ramp", "at": 0.3, "size": "big"}, {"type": "spring", "at": 0.5}, {"type": "ring", "at": 0.32, "h": 6}]})
	var sm: Dictionary = tr.zones[0]
	var bg: Dictionary = tr.zones[1]
	ok(float(sm.s1) - float(sm.s0) < float(bg.s1) - float(bg.s0) and float(sm.h) < float(bg.h), "작은·큰 점프대")
	ok(tr.rings.size() == 1 and tr.zones.size() == 3, "고리는 구간과 따로")
	var p := Rules.point_at(tr, float(bg.s1) - 0.5)
	var gl := Rules.ground_at(tr, Rules.locate(tr, p.pos, p.i))
	ok(gl.h > p.h + 2.2 and float(gl.ramp_pow) > 1.05, "큰 점프대 끝은 높다")
	var rp := Rules.point_at(tr, float(tr.rings[0].s))
	ok(Rules.ground_at(tr, Rules.locate(tr, rp.pos, rp.i)).has("ring"), "고리 근처에서 알려 준다")
	var sp := Rules.point_at(tr, float(tr.zones[2].s1) - 1.0)
	ok(Rules.ground_at(tr, Rules.locate(tr, sp.pos, sp.i)).spring, "스프링 구간")

func _gauge() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	var k := Rules.new_board(Vector2.ZERO, 0.0)
	k.gauge = 0.99
	k.gauge += 0.05
	run(k, st, DT)
	ok(k.boosts == 1 and k.gauge < 0.1 and "boost_gain" in k.events, "게이지가 차면 부스터 하나")
	k.boosts = 2
	k.gauge = 1.2
	run(k, st, DT)
	ok(k.boosts == 2, "부스터는 두 개까지")
	k.events.clear()
	run(k, st, 3.0)
	var v0 := Rules.speed_of(k)
	Rules.step(k, {"throttle": 1.0, "use_boost": true}, st, flat(), DT)
	ok(k.boosts == 1 and k.boost_t > 0.0, "부스터 쓰기")
	run(k, st, 0.8)
	ok(Rules.speed_of(k) > v0 * 1.2, "부스터는 빠르다")
	# 판정이 좋을수록·능력치가 높을수록 게이지가 더 찬다
	var lo := Rules.board_stats(board(Rules.START_BOARD))
	var hi := Rules.board_stats(board("comet"))
	var g1: float = trick_jump(lo, 0.95, ["360"]).gauge
	ok(hi.gauge_gain > lo.gauge_gain * 1.3, "좋은 보드는 게이지가 더 빨리 찬다")
	# 묘기 대여섯 번이면 부스터 하나쯤
	ok(g1 > 0.12 and g1 < 0.45, "묘기 한 번 게이지 %.2f" % g1)
	# 부스터 발판
	var p := Rules.new_board(Vector2.ZERO, 0.0)
	p.vel = Vector2(0, 20)
	Rules.step(p, {"throttle": 1.0}, st, {"h": 0.0, "kind": "road", "ramp_t": -1.0, "pad": true}, DT)
	ok(p.dash_t > 0.0 and "pad" in p.events, "부스터 발판")

func _surfaces() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	var stairs := {"h": 0.0, "kind": "stairs", "ramp_t": -1.0}
	var k := Rules.new_board(Vector2.ZERO, 0.0)
	k.vel = Vector2(0, st.max_speed)
	run(k, st, 1.5, {"throttle": 1.0}, stairs)
	ok(Rules.speed_of(k) < st.max_speed * 0.6, "계단은 느리다 %.1f" % Rules.speed_of(k))
	var j := Rules.new_board(Vector2.ZERO, 0.0)
	j.vel = Vector2(0, st.max_speed)
	Rules.step(j, {"throttle": 1.0, "jump": true}, st, stairs, DT)
	var t := 0.0
	while j.air and t < 2.0:
		Rules.step(j, {"throttle": 1.0}, st, stairs, DT)
		t += DT
	ok(Rules.speed_of(j) > st.max_speed * 0.9, "계단 위를 날면 안 느려진다")
	var grass := {"h": 0.0, "kind": "grass", "ramp_t": -1.0}
	var gk := Rules.new_board(Vector2.ZERO, 0.0)
	run(gk, st, 6.0, {"throttle": 1.0}, grass)
	ok(Rules.speed_of(gk) < st.max_speed * 0.65, "풀밭은 느리다")
	# 얼음: 잘 미끄러진다
	var ice := {"h": 0.0, "kind": "ice", "ramp_t": -1.0}
	var ik := Rules.new_board(Vector2.ZERO, 0.0)
	var rk := Rules.new_board(Vector2.ZERO, 0.0)
	ik.vel = Vector2(0, 25); rk.vel = Vector2(0, 25)
	run(ik, st, 0.6, {"throttle": 1.0, "steer": 1.0}, ice)
	run(rk, st, 0.6, {"throttle": 1.0, "steer": 1.0})
	ok(absf(ik.slip) > absf(rk.slip) * 2.0, "얼음에서는 미끄러진다")
	# 낭떠러지: 떨어진다
	var fk := Rules.new_board(Vector2.ZERO, 0.0)
	fk.vel = Vector2(0, 5)
	var gap := {"h": -20.0, "kind": "gap", "ramp_t": -1.0}
	var tt := 0.0
	while not fk.fell and tt < 3.0:
		Rules.step(fk, {"throttle": 1.0}, st, gap, DT)
		tt += DT
	ok(fk.fell and "fell" in fk.events, "낭떠러지에 떨어진다")

func _track_geometry() -> void:
	for def in tracks:
		var tr := Rules.build_track(def)
		ok(tr.n > 100 and absf(tr.length - tr.n * 2.0) < tr.n * 0.2, def.id + " 점 간격 %.0f" % tr.length)
		var loc := Rules.locate(tr, tr.pts[10] + tr.nrm[10] * 3.0)
		ok(absf(loc.lat - 3.0) < 0.3 and absf(loc.i - 10) <= 1, def.id + " 옆 거리 재기")
		var line := Rules.racing_line(tr)
		var mx := 0.0
		for o in line:
			mx = maxf(mx, absf(o))
		ok(mx <= tr.half_width - 2.0 + 0.01, def.id + " 레이싱 라인은 길 안")
		var k := Rules.new_board(tr.pts[20] + tr.nrm[20] * (tr.walls[20] + 4.0), 0.0)
		k.vel = tr.nrm[20] * 10.0
		var l2 := Rules.locate(tr, k.pos)
		ok(Rules.wall_push(tr, k, l2) and absf(Rules.locate(tr, k.pos).lat) < tr.walls[20], def.id + " 울타리")
		for s in 8:
			var g := Rules.grid_slot(tr, s)
			var gl := Rules.locate(tr, g.pos)
			ok(gl.s > tr.length * 0.7 and absf(gl.lat) < tr.half_width, def.id + " 출발 자리 %d" % s)
			ok(Rules.zone_at(tr, gl.s).is_empty(), def.id + " 출발 자리는 평평한 곳 %d" % s)
		# 구간
		for z in tr.zones:
			var mid: float = (float(z.s0) + float(z.s1)) * 0.5
			ok(Rules.zone_at(tr, mid).type == z.type, def.id + " 구간 찾기 " + str(z.type))
			var p := Rules.point_at(tr, mid)
			var gl2 := Rules.ground_at(tr, Rules.locate(tr, p.pos, p.i))
			match str(z.type):
				"ramp": ok(gl2.ramp_t > 0.3 and gl2.ramp_t < 0.7 and gl2.h > p.h + float(z.h) * 0.3, def.id + " 점프대 오르막")
				"spring": ok(gl2.spring, def.id + " 스프링")
				"gap": ok(gl2.kind == "gap" and gl2.h < -5.0, def.id + " 낭떠러지")
				"stairs": ok(gl2.kind == "stairs", def.id + " 계단")
				"ice": ok(gl2.kind == "ice", def.id + " 얼음")
			if str(z.type) == "gap":
				# 낭떠러지 바로 앞은 점프대
				var before := Rules.zone_at(tr, float(z.s0) - 1.0)
				ok(not before.is_empty() and before.type == "ramp", def.id + " 낭떠러지 앞에는 점프대")
		ok(Rules.ground_at(tr, Rules.locate(tr, tr.pts[5] + tr.nrm[5] * (tr.half_width + 2.0))).kind == ("road" if tr.sky else "grass"), def.id + " 길 밖")
		# 떨어지면 다시 시작하는 자리는 평평한 길
		for z in tr.zones:
			if str(z.type) == "gap":
				var rs := Rules.respawn_at(tr, float(z.s0) + 3.0)
				ok(Rules.zone_at(tr, rs.s).is_empty() and fposmod(float(z.s0) - float(rs.s), tr.length) < 40.0, def.id + " 다시 시작 자리")

func _race_rules() -> void:
	ok(is_equal_approx(Rules.advance(95.0, 5.0, 100.0), 105.0), "출발선을 넘으면 거리가 이어진다")
	ok(is_equal_approx(Rules.advance(105.0, 95.0, 100.0), 95.0), "뒤로 가면 줄어든다")
	ok(Rules.lap_of(-2.0, 100.0) == 1 and Rules.lap_of(150.0, 100.0) == 2, "랩")
	var order := Rules.ranking([
		{"dist": 50.0, "finish": -1.0}, {"dist": 300.0, "finish": 62.0},
		{"dist": 80.0, "finish": -1.0}, {"dist": 300.0, "finish": 60.0}])
	ok(order == [3, 1, 2, 0], "순위 %s" % [order])
	ok(Rules.reward(1, 8, "race") > Rules.reward(2, 8, "race") and Rules.reward(8, 8, "race") > 0, "순위 보상")
	ok(Rules.reward(1, 1, "time") == 0, "혼자는 순위 보상 없음")
	ok(Rules.exp_gain(1, 8, 200, "race") > Rules.exp_gain(5, 8, 200, "race") and Rules.exp_gain(5, 8, 400, "race") > Rules.exp_gain(5, 8, 0, "race"), "경험치: 순위·묘기")
	ok(Rules.team_score([1, 4, 5, 8]) == 10 + 5 + 4 + 1, "팀 점수")
	ok(Rules.medal(59.0, 60.0) == "gold" and Rules.medal(66.0, 60.0) == "silver" and Rules.medal(75.0, 60.0) == "bronze" and Rules.medal(90.0, 60.0) == "", "메달")
	ok(Rules.time_reward("", "gold", true) > Rules.time_reward("silver", "gold", false) and Rules.time_reward("gold", "gold", false) == 5, "타임어택 보상")
	ok(Rules.time_text(83.456) == "1:23.46" and Rules.time_text(-1.0) == "--:--.--", "시간 글자")
	var l1 := Rules.level_info(0)
	ok(l1.level == 1 and l1.into == 0 and l1.need == Rules.exp_need(1), "처음 레벨 1")
	var l2 := Rules.level_info(Rules.exp_need(1) + 10)
	ok(l2.level == 2 and l2.into == 10, "경험치가 차면 레벨 2")
	var r := Rules.lucky_roll(0.01, 0.5, ["galaxy", "golden"], 1)
	ok(r.kind == "board" and r.board in ["galaxy", "golden"], "아주 운 좋으면 희귀 보드")
	ok(Rules.lucky_roll(0.01, 0.5, [], 1).kind == "lucky", "희귀 보드를 다 모았으면 다른 상")
	ok(Rules.lucky_roll(0.99, 0.5, ["galaxy"], 1).kind == "coins", "보통은 코인 조금")
	var counts := {"board": 0, "lucky": 0, "pouch": 0, "coins": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 2000:
		counts[Rules.lucky_roll(rng.randf(), rng.randf(), ["galaxy"], 4).kind] += 1
	ok(counts.board > 20 and counts.board < 120 and counts.coins > 1000, "행운 상자 확률 %s" % [counts])

func _shop_and_save() -> void:
	var s := Rules.default_save()
	var sp := board("sprout")
	ok(not Rules.can_buy(s, sp), "돈이 없으면 못 산다")
	s.coins = 2000
	ok(not Rules.can_buy(s, sp), "레벨이 모자라면 못 산다")
	s.exp = 2000
	var s2 := Rules.buy(s, sp)
	ok(s2.coins == 2000 - int(sp.price) and "sprout" in s2.owned and s2.board == "sprout", "사면 돈이 줄고 고른다")
	ok(s.coins == 2000 and not ("sprout" in s.owned), "원래 저장은 그대로")
	ok(not Rules.can_buy(s2, sp), "이미 있으면 다시 못 산다")
	var gx := board("galaxy")
	s2.coins = 99999
	ok(not Rules.can_buy(s2, gx), "희귀 보드는 상점에서 못 산다")
	var ids := boards.map(func(b): return b.id)
	s2.rider = "oopi"
	s2.name = "보드왕"
	s2.medals = {"sprout_hill": "gold"}
	var p := Rules.parse_save(JSON.stringify(s2), ids)
	ok(p.coins == 99999 and p.board == "sprout" and Rules.START_BOARD in p.owned and p.rider == "oopi" and p.name == "보드왕" and p.medals.sprout_hill == "gold" and p.exp == 2000, "저장 읽기")
	ok(Rules.parse_save("망가진{", ids) == Rules.default_save(), "망가진 저장은 처음부터")
	var bad := Rules.parse_save({"coins": -5, "owned": ["ufo", "sprout"], "board": "ufo", "rider": "alien", "best": {"a": "x", "b": 30}, "medals": {"a": "diamond"}, "name": "   "}, ids)
	ok(bad.coins == 0 and bad.owned == [Rules.START_BOARD, "sprout"] and bad.board == Rules.START_BOARD and bad.rider == "oobi" and bad.best == {"b": 30.0} and bad.medals.is_empty() and bad.name == "나", "이상한 값은 걸러 낸다")
	ok(Rules.clean_name("  아주아주긴이름입니다  ") == "아주아주긴이름입", "이름은 8글자까지")

func _items() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := {}
	var last := {}
	for i in 3000:
		var a := Rules.item_roll(1, 8, rng.randf())
		var b := Rules.item_roll(8, 8, rng.randf())
		first[a] = int(first.get(a, 0)) + 1
		last[b] = int(last.get(b, 0)) + 1
	ok(not first.has("cloud") and not first.has("quake"), "1등은 먹구름·쿵쿵이 안 나온다")
	ok(int(last.get("boost", 0)) > int(first.get("boost", 0)), "뒤에 있으면 부스터가 더 나온다")
	var k := Rules.new_board(Vector2.ZERO, 0.0)
	ok(Rules.give_item(k, "goo") and Rules.give_item(k, "boost") and not Rules.give_item(k, "cloud"), "아이템은 두 칸")
	k.shield_t = 2.0
	ok(not Rules.hit(k) and k.shield_t == 0.0, "비눗방울이 한 번 막는다")
	k.vel = Vector2(0, 25)
	ok(Rules.hit(k) and k.spin_t > 0.0, "맞으면 빙글")
	var st := Rules.board_stats(board(Rules.START_BOARD))
	run(k, st, Rules.SPIN_TIME + 0.1)
	ok(k.spin_t == 0.0 and k.vel.length() < 15.0, "빙글 돌고 나면 느려져 있다")

func _net_codes() -> void:
	var sdp := "v=0\r\no=- 46117 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\n" + "a=candidate:1 1 udp 2122260223 192.168.0.2 5000 typ host\r\n".repeat(6)
	var code: String = Rules.net_encode({"t": "offer", "s": sdp}, [["0", 0, "candidate:1 1 udp 1 10.0.0.1 9 typ host"]])
	ok(code.begins_with("BR1-") and code.length() < sdp.length(), "코드는 줄여서 BR1- 로 시작")
	var d: Dictionary = Rules.net_decode("  보낸 글: " + code.insert(30, "\n") + "  ")
	ok(d.get("t") == "offer" and d.get("s") == sdp and d.c.size() == 1, "앞뒤 글자·줄바꿈이 섞여도 읽는다")
	ok(Rules.net_decode("BR1-망가짐").is_empty() and Rules.net_decode("").is_empty(), "망가진 코드는 빈 값")

func _room_codes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var c := Rules.room_new(rng)
	ok(c.length() == 6 and Rules.room_clean(c) == c, "방 코드 6자리")
	ok(Rules.room_clean(" " + c.to_lower().insert(3, "-") + " ") == c, "소문자·하이픈 받아 줌")
	ok(Rules.room_clean("ABC") == "", "짧으면 빈 값")
	var body := '{"id":"1","event":"open"}\n{"id":"2","event":"message","message":"J:ab"}\n{"id":"3","event":"message","message":"O:ab:BR1-xyz"}\n'
	ok(Rules.relay_list(body).size() == 2 and Rules.relay_pick(body, "O:ab:") == "BR1-xyz", "중계 글 읽기")

## 컴퓨터가 모든 트랙을 다 도는지 (점프대에서 뛰고, 묘기하고, 낭떠러지에 자주 안 떨어지는지)
func _full_laps() -> void:
	var st := Rules.board_stats(board(Rules.START_BOARD))
	for def in tracks:
		for skill in [1.0, 0.5]:
			var res := lap_run(def, st, skill, 7)
			var tr: Dictionary = res.tr
			var avg: float = res.t / tr.laps
			print("  %s (실력 %.1f): %.1f초 (한 바퀴 %.1f초) 점프 %d 묘기 %d(EX %d) 실패 %d 떨어짐 %d 벽 %d 부스터 %d 최대 연속 %d 커맨드 %d 고리 %d" % [def.id, skill, res.t, avg, res.jumps, res.ok, res.ex, res.fail, res.fell, res.walls, res.boosts, res.chain, res.cmd, res.ring])
			ok(res.dist >= tr.length * tr.laps, "%s 다 돈다 (실력 %.1f)" % [def.id, skill])
			ok(avg > tr.length / 40.0 and avg < tr.length / 14.0, def.id + " 한 바퀴 시간이 그럴듯하다")
			ok(res.ok >= tr.laps * 2, def.id + " 컴퓨터도 묘기를 한다")
			ok(res.walls < 14 * tr.laps, def.id + " 벽에 자주 안 박는다 (%d)" % res.walls)
			if skill >= 1.0:
				ok(res.fell <= 1, def.id + " 잘하는 컴퓨터는 거의 안 떨어진다 (%d)" % res.fell)
				ok(res.fail <= tr.laps, def.id + " 잘하는 컴퓨터는 묘기 실패가 적다 (%d)" % res.fail)
				ok(res.boosts >= 1, def.id + " 부스터를 쓴다")
				ok(res.chain >= 2, def.id + " 잘하는 컴퓨터는 묘기를 잇는다 (%d)" % res.chain)
				ok(res.cmd >= 1, def.id + " 잘하는 컴퓨터는 커맨드 묘기도 쓴다 (%d)" % res.cmd)

func lap_run(def: Dictionary, st: Dictionary, skill: float, seed: int) -> Dictionary:
	var tr := Rules.build_track(def)
	var line := Rules.racing_line(tr)
	var g0 := Rules.grid_slot(tr, 0)
	var k := Rules.new_board(g0.pos, g0.yaw, g0.h)
	var dist: float = Rules.locate(tr, k.pos).s - tr.length
	var hint := -1
	var t := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var plan := {}
	var r := {"jumps": 0, "ok": 0, "ex": 0, "fail": 0, "fell": 0, "walls": 0, "boosts": 0, "chain": 0, "cmd": 0, "ring": 0}
	var goal: float = tr.length * tr.laps
	var fall_t := -1.0
	while dist < goal and t < 500.0:
		var loc := Rules.locate(tr, k.pos, hint, k.alt)
		hint = loc.i
		if fall_t >= 0.0:
			fall_t -= DT
			if fall_t < 0.0:
				var rs := Rules.respawn_at(tr, loc.s)
				k = Rules.new_board(rs.pos, rs.yaw, rs.h)
				hint = -1
			t += DT
			continue
		var g := Rules.ground_at(tr, loc)
		var inp := Rules.ai_input(k, tr, line, loc, g, skill, 0.0, rng.randf(), plan, st)
		Rules.step(k, inp, st, g, DT)
		for e in k.events:
			match e:
				"jump": r.jumps += 1
				"trick_ok":
					r.ok += 1
					if k.judge.word == "EXCELLENT": r.ex += 1
					r.chain = maxi(int(r.chain), int(k.judge.get("chain", 1)))
					for nm in str(k.judge.label).split(" + "):
						if not (nm in ["GB", "360", "720"]): r.cmd += 1
				"ring": r.ring += 1
				"fail": r.fail += 1
				"boost": r.boosts += 1
				"fell":
					r.fell += 1
					fall_t = 1.0
		k.events.clear()
		var l2 := Rules.locate(tr, k.pos, hint, k.alt)
		if not k.fell and Rules.wall_push(tr, k, l2):
			r.walls += 1
		dist = Rules.advance(dist, Rules.locate(tr, k.pos, hint, k.alt).s, tr.length)
		t += DT
	r.t = t
	r.dist = dist
	r.tr = tr
	return r
