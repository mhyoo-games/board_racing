class_name Rules
extends RefCounted
## 화면과 떨어진 게임 규칙(계산)만 모은 곳. 테스트: godot --headless -s tests/run_tests.gd
##
## 좌표: 바닥은 (x, z) 평면을 Vector2(x, z)로 쓴다. yaw = 0 이면 +z 쪽을 본다.
##   앞 = (sin yaw, cos yaw), 오른쪽 = (-cos yaw, sin yaw). 오른쪽으로 꺾으면 yaw가 줄어든다.
## 높이: alt = 보드의 실제 높이(월드 y). 땅 높이(ground_h)는 부르는 쪽이 트랙에서 구해 준다.
##
## 조작: 방향키(↑ 가속, ↓ 브레이크, ←→ 회전), Shift 슬라이드(급회전), Space·Ctrl 부스터
##   A 점프 — 점프대 위에서 누르면 높이 뜬다. 점프대 끝에 가까울수록 좋은 판정 (GOOD < NICE < EXCELLENT)
##   S 그랩 · D 360 · F 720 — 공중 묘기. 땅에 닿기 전에 끝나야 성공, 아슬아슬하게 끝낼수록 좋은 판정
##   묘기·점프 판정으로 게이지가 차고, 다 차면 부스터 하나 (두 개까지)

const KMH := 4.0                 ## 화면에 보이는 속도 = 속력 × KMH
const MAX_BOOSTS := 2
const START_WINDOW := 0.4        ## 출발 직전 이 시간 안에 가속을 누르면 출발 부스터
const STEER_IN := 6.0
const STEER_OUT := 9.0
const GRAVITY := 26.0
const HOP := 0.55                ## 땅에서 점프 = 점프 힘 × 이만큼
const RAMP_LEN := 10.0           ## 점프대 길이(m)
const RAMP_H := 1.4              ## 점프대 끝 높이
const LAND_GRACE := 0.08         ## 묘기가 이만큼 덜 끝났어도 성공으로 쳐 준다
const SLIDE_GRIP := 3.4          ## 슬라이드 중 가는 방향이 코를 따라가는 빠르기
const ICE_GRIP := 2.0
const SLIDE_GAUGE := 0.16        ## 슬라이드로 차는 게이지(초당, 많이 미끄러질 때)
const TRICK_GAUGE := 0.075       ## 묘기 점수 1점당 게이지
const DASH_TIME := 0.7           ## EXCELLENT 착지·발판 부스터 길이
const STUMBLE_TIME := 0.9        ## 묘기 실패하면 비틀거리는 시간

## 묘기: 이름 → {label 화면 글자, dur 걸리는 시간(초), pts 점수, spin 도는 바퀴}
const TRICKS := {
	"gb": {"label": "GB", "dur": 0.38, "pts": 1, "spin": 0.0},
	"360": {"label": "360", "dur": 0.62, "pts": 2, "spin": 1.0},
	"720": {"label": "720", "dur": 1.0, "pts": 4, "spin": 2.0},
}
const JUDGES := ["GOOD", "NICE", "EXCELLENT"]
const JUDGE_MULT := [1.0, 1.45, 2.1]
const JUMP_MULT := [0.82, 1.0, 1.2]      ## 점프대 판정별 점프 힘
const JUMP_GAUGE := [0.03, 0.06, 0.11]

# ────────────────────────── 보드 능력치 ──────────────────────────

const START_BOARD := "breeze"

## 1~10 능력치를 실제 값으로.
static func board_stats(def: Dictionary) -> Dictionary:
	var s: Dictionary = def.get("stats", {})
	var g := func(k: String) -> float: return clampf(float(s.get(k, 5)), 1.0, 10.0)
	return {
		"max_speed": 25.5 + g.call("speed") * 0.85,     # 26.4 ~ 34
		"accel": 12.0 + g.call("accel") * 1.6,          # 13.6 ~ 28
		"turn": 1.65 + g.call("handling") * 0.1,        # 초당 회전(라디안)
		"grip": 9.0 + g.call("handling") * 0.8,
		"jump_v": 9.6 + g.call("jump") * 0.34,          # 점프 힘 (위로 속도)
		"trick_speed": 0.86 + g.call("trick") * 0.03,   # 묘기 빠르기 (1보다 크면 빨리 끝남)
		"gauge_gain": 0.7 + g.call("trick") * 0.06,     # 게이지가 차는 빠르기 (능력치 3 → 0.88, 9 → 1.24)
		"boost_time": 1.6 + g.call("boost") * 0.09,
		"boost_mult": 1.34,
		"weight": 5.0,
	}

## 새 보드 상태
static func new_board(pos: Vector2, yaw: float, alt := 0.0) -> Dictionary:
	return {
		"pos": pos, "vel": Vector2.ZERO, "yaw": yaw, "yaw_rate": 0.0, "steer_s": 0.0,
		"alt": alt, "vy": 0.0, "air": false, "air_t": 0.0, "gvy": 0.0, "prev_g": alt,
		"trick": "", "trick_t": 0.0, "trick_dur": 0.0, "done": [], "since_trick": 0.0, "spin": 0.0,
		"gauge": 0.0, "boosts": 0, "boost_t": 0.0, "dash_t": 0.0, "slide": false, "slip": 0.0,
		"ground": "road", "offroad": false, "stumble_t": 0.0, "combo": 0, "jump_judge": -1,
		"events": [], "judge": {}, "fell": false, "points": 0, "tricks": 0, "best_judge": -1,
		"spin_t": 0.0, "shield_t": 0.0, "items": [], "no_gauge": false,
	}

static func fwd(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))

static func right(yaw: float) -> Vector2:
	return Vector2(-cos(yaw), sin(yaw))

static func speed_of(k: Dictionary) -> float:
	return (k.vel as Vector2).dot(fwd(k.yaw))

static func boosting(k: Dictionary) -> bool:
	return k.boost_t > 0.0 or k.dash_t > 0.0

## 지금 낼 수 있는 최고 속력
static func top_speed(k: Dictionary, st: Dictionary) -> float:
	var top: float = st.max_speed
	if not k.air:
		match str(k.ground):
			"grass":
				top *= 0.88 if boosting(k) else 0.58
			"stairs":
				top *= 0.62 if boosting(k) else 0.46   # 계단은 덜컹덜컹 — 뛰어넘으면 안 느려진다
	if k.boost_t > 0.0:
		top *= st.boost_mult
	elif k.dash_t > 0.0:
		top *= 1.16
	if k.stumble_t > 0.0:
		top *= 0.45
	return top

## 묘기 하나 걸리는 시간
static func trick_dur(name: String, st: Dictionary) -> float:
	return float(TRICKS[name].dur) / float(st.get("trick_speed", 1.0))

## 점프대 판정: 점프대에서 얼마나 갔나(0 처음 ~ 1 끝) → 0 GOOD, 1 NICE, 2 EXCELLENT
static func ramp_judge(ramp_t: float) -> int:
	if ramp_t >= 0.84:
		return 2
	if ramp_t >= 0.6:
		return 1
	return 0

## 착지 판정: 마지막 묘기가 끝나고 땅에 닿기까지 남은 시간(초) → 짧을수록 좋다
static func land_judge(margin: float) -> int:
	if margin < 0.13:
		return 2
	if margin < 0.32:
		return 1
	return 0

## 지금 높이·위로 속도로 땅(ground_h)까지 남은 공중 시간
static func air_left(vy: float, alt: float, ground_h: float) -> float:
	var h := maxf(0.0, alt - ground_h)
	return (vy + sqrt(vy * vy + 2.0 * GRAVITY * h)) / GRAVITY

## 한 프레임. inp = {throttle -1..1, steer -1..1(오른쪽 +), slide bool, jump bool(이번에 누름), trick ""|"gb"|"360"|"720"(이번에 누름), use_boost bool}
## g = 바닥 정보 {h 땅 높이, kind "road"|"grass"|"ice"|"stairs"|"gap", ramp_t -1(점프대 아님)|0..1, pad bool(부스터 발판)}
## 소리·글자용 사건은 k.events 에 쌓는다 (부르는 쪽이 비운다). 판정 글자는 k.judge = {word, label, t}
static func step(k: Dictionary, inp: Dictionary, st: Dictionary, g: Dictionary, dt: float) -> void:
	var gh: float = float(g.get("h", 0.0))
	var kind: String = str(g.get("kind", "road"))
	if float(k.get("spin_t", 0.0)) > 0.0:
		_spin_step(k, gh, dt)
		return
	k.shield_t = maxf(0.0, float(k.get("shield_t", 0.0)) - dt)
	var stumbling: bool = k.stumble_t > 0.0
	var throttle: float = clampf(float(inp.get("throttle", 0.0)), -1.0, 1.0)
	var raw: float = clampf(float(inp.get("steer", 0.0)), -1.0, 1.0)
	if stumbling:
		throttle = minf(throttle, 0.3)
		raw *= 0.3
	# ── 핸들을 부드럽게
	var cur: float = k.steer_s
	var rate := STEER_OUT
	if raw != 0.0 and (cur == 0.0 or signf(raw) == signf(cur)) and absf(raw) > absf(cur):
		rate = STEER_IN
	k.steer_s = move_toward(cur, raw, rate * dt)
	var steer: float = k.steer_s

	var vel: Vector2 = k.vel
	var sp := vel.length()
	var yaw: float = k.yaw
	var va := atan2(vel.x, vel.y) if sp > 0.3 else yaw
	var backward := sp > 0.3 and vel.dot(fwd(yaw)) < 0.0
	if backward:
		sp = -sp
		va = atan2(-vel.x, -vel.y)
	if not k.air:
		k.ground = kind
	k.offroad = (not k.air) and kind == "grass"
	var top := top_speed(k, st)

	# ── 회전
	var on_ice: bool = kind == "ice" and not k.air
	var was_slide: bool = k.slide
	k.slide = bool(inp.get("slide", false)) and absf(raw) > 0.3 and sp > 8.0 and not k.air and not stumbling
	if k.slide and not was_slide:
		k.events.append("slide")
	var low := clampf(absf(sp) / 7.0, 0.35, 1.0)
	var high := 1.0 - 0.2 * clampf(sp / st.max_speed, 0.0, 1.2)
	var target_w: float = -steer * st.turn * low * high * (-1.0 if backward else 1.0)
	var grip: float = st.grip
	if k.slide:
		target_w *= 1.5
		grip = SLIDE_GRIP
	if on_ice:
		target_w *= 0.85
		grip = minf(grip, ICE_GRIP)
	if k.air:
		target_w *= 0.45      # 공중에서는 조금만 돈다 (착지 방향 맞추기)
		grip = 0.0
	k.yaw_rate = lerpf(float(k.yaw_rate), target_w, 1.0 - exp(-10.0 * dt))
	yaw = wrapf(yaw + float(k.yaw_rate) * dt, -PI, PI)
	var slip0 := wrapf(va - yaw, -PI, PI)
	va = yaw + slip0 * exp(-grip * dt)
	var slip := wrapf(va - yaw, -PI, PI)
	var along := cos(slip)

	# ── 가속·감속
	var acc: float = st.accel * (0.55 if on_ice else 1.0)
	if k.air:
		sp = move_toward(sp, minf(sp, top), 2.0 * dt)   # 공중에서는 속도가 거의 그대로
	elif boosting(k) and throttle >= 0.0:
		sp = move_toward(sp, top, 50.0 * dt)
	elif throttle > 0.0:
		if sp < top:
			var curve := 1.0 - 0.5 * clampf(sp / top, 0.0, 1.0)
			sp = minf(top, sp + acc * throttle * curve * maxf(along, 0.2) * dt)
	elif throttle < 0.0:
		if sp > 0.5:
			sp = maxf(0.0, sp - (14.0 if on_ice else 34.0) * dt)
		else:
			sp = maxf(-8.0, sp - 12.0 * dt)
	else:
		sp = move_toward(sp, 0.0, (2.0 if on_ice else 4.5) * dt)
	if sp > top and not k.air:
		sp = move_toward(sp, top, (32.0 if kind in ["grass", "stairs"] else 13.0) * dt)
	if sp > 0.0 and not k.air:
		sp = maxf(0.0, sp - (3.5 if k.slide else 5.0) * absf(sin(slip)) * dt * (sp / 20.0))
	if kind == "stairs" and not k.air and sp > 6.0:
		k.bump_t = float(k.get("bump_t", 0.0)) - dt
		if k.bump_t <= 0.0:
			k.bump_t = 0.22
			k.events.append("stairs")

	# ── 슬라이드 게이지
	if k.slide and absf(slip) > 0.05:
		k.gauge += SLIDE_GAUGE * st.gauge_gain * clampf(absf(slip) / 0.35, 0.2, 1.0) * clampf(sp / 22.0, 0.0, 1.0) * dt

	# ── 부스터 발판
	if bool(g.get("pad", false)) and not k.air:
		if float(k.dash_t) < DASH_TIME * 0.6:
			k.events.append("pad")
		k.dash_t = maxf(k.dash_t, DASH_TIME * 1.3)

	# ── 높이: 점프·공중·착지
	_vertical(k, inp, st, g, dt)

	# ── 게이지가 차면 부스터 하나 (아이템전은 게이지 없음)
	if k.get("no_gauge", false):
		k.gauge = 0.0
	if k.gauge >= 1.0:
		k.gauge -= 1.0
		if k.boosts < MAX_BOOSTS:
			k.boosts += 1
			k.events.append("boost_gain")
		else:
			k.gauge = 0.0
	if inp.get("use_boost", false) and k.boosts > 0 and k.boost_t < 0.3 and not k.get("no_gauge", false) and not stumbling:
		k.boosts -= 1
		k.boost_t = st.boost_time
		k.events.append("boost")

	k.yaw = yaw
	k.vel = fwd(va) * sp
	k.slip = slip
	k.pos = (k.pos as Vector2) + (k.vel as Vector2) * dt
	k.boost_t = maxf(0.0, k.boost_t - dt)
	k.dash_t = maxf(0.0, k.dash_t - dt)
	k.stumble_t = maxf(0.0, k.stumble_t - dt)

static func _vertical(k: Dictionary, inp: Dictionary, st: Dictionary, g: Dictionary, dt: float) -> void:
	var gh: float = float(g.get("h", 0.0))
	var ramp_t: float = float(g.get("ramp_t", -1.0))
	var stumbling: bool = k.stumble_t > 0.0
	if not k.air:
		# 땅이 움직이는 빠르기 (점프대를 오르면 위로)
		var gv: float = (gh - float(k.prev_g)) / maxf(dt, 0.0001)
		k.gvy = lerpf(float(k.gvy), clampf(gv, -30.0, 30.0), 0.5)
		k.prev_g = gh
		if inp.get("jump", false) and not stumbling:
			var mult := HOP
			k.jump_judge = -1
			if ramp_t >= 0.0:
				var j := ramp_judge(ramp_t)
				mult = JUMP_MULT[j]
				k.jump_judge = j
				k.gauge += JUMP_GAUGE[j] * st.gauge_gain
				k.judge = {"word": JUDGES[j], "label": "JUMP", "t": 0.0}
			k.air = true
			k.vy = st.jump_v * mult + maxf(0.0, float(k.gvy))
			k.air_t = 0.0
			k.done = []
			k.since_trick = 0.0
			k.events.append("jump")
		elif gh < float(k.alt) - 0.12:
			# 땅이 꺼졌다 (점프대 끝·낭떠러지): 그대로 날아간다
			k.air = true
			k.vy = maxf(0.0, float(k.gvy))
			k.air_t = 0.0
			k.done = []
			k.since_trick = 0.0
			k.jump_judge = -1
			k.events.append("launch")
		else:
			k.alt = gh
			k.vy = 0.0
			return
	# 공중
	k.air_t += dt
	k.vy -= GRAVITY * dt
	k.alt += k.vy * dt
	# 묘기
	var t_in: String = str(inp.get("trick", ""))
	if k.trick == "" and t_in != "" and TRICKS.has(t_in) and not stumbling:
		k.trick = t_in
		k.trick_t = 0.0
		k.trick_dur = trick_dur(t_in, st)
		k.events.append("trick")
	if k.trick != "":
		k.trick_t += dt
		k.spin = float(TRICKS[k.trick].spin) * clampf(k.trick_t / maxf(k.trick_dur, 0.01), 0.0, 1.0)
		if k.trick_t >= k.trick_dur:
			(k.done as Array).append(k.trick)
			k.trick = ""
			k.trick_t = 0.0
			k.spin = 0.0
			k.since_trick = 0.0
	elif not (k.done as Array).is_empty():
		k.since_trick += dt
	# 땅보다 한참 아래: 낭떠러지로 떨어지는 중 (길 옆면에 걸리지 않고 계속 떨어진다)
	if k.alt < gh - 2.0 or gh < -5.0:
		if k.alt < -6.0 and not k.fell:
			k.fell = true
			k.events.append("fell")
		return
	if k.alt <= gh and k.vy <= 0.0:
		_land(k, st, gh)

## 착지: 묘기가 덜 끝났으면 실패(비틀), 다 끝났으면 판정
static func _land(k: Dictionary, st: Dictionary, gh: float) -> void:
	k.air = false
	k.alt = gh
	k.prev_g = gh
	k.gvy = 0.0
	k.vy = 0.0
	var done: Array = k.done
	if k.trick != "":
		if k.trick_dur - k.trick_t <= LAND_GRACE:
			done.append(k.trick)
			k.since_trick = 0.0
		else:
			# 실패
			k.trick = ""
			k.trick_t = 0.0
			k.spin = 0.0
			k.stumble_t = STUMBLE_TIME
			k.combo = 0
			k.done = []
			k.judge = {"word": "MISS", "label": "", "t": 0.0}
			k.events.append("fail")
			return
	k.trick = ""
	k.trick_t = 0.0
	k.spin = 0.0
	if done.is_empty():
		k.events.append("land")
		return
	var j := land_judge(float(k.since_trick))
	var pts := 0
	var names := []
	for t in done:
		pts += int(TRICKS[t].pts)
		names.append(TRICKS[t].label)
	pts += done.size() - 1                 # 이어서 하면 덤
	k.combo = int(k.combo) + 1
	var combo_mult := 1.0 + 0.1 * minf(float(k.combo) - 1.0, 5.0)
	k.gauge += TRICK_GAUGE * pts * JUDGE_MULT[j] * combo_mult * st.gauge_gain
	k.points = int(k.points) + int(round(pts * JUDGE_MULT[j] * 10.0))
	k.tricks = int(k.tricks) + done.size()
	k.best_judge = maxi(int(k.best_judge), j)
	if j == 2:
		k.dash_t = maxf(k.dash_t, DASH_TIME)
	k.judge = {"word": JUDGES[j], "label": " + ".join(names), "t": 0.0, "combo": k.combo}
	k.events.append("trick_ok")
	k.done = []

## 출발 부스터: 출발(0초)까지 남은 시간이 `left`일 때 가속을 처음 눌렀다면 1, 아니면 0
static func start_boost(left: float) -> float:
	if left >= 0.0 and left <= START_WINDOW:
		return 1.0
	return 0.0

# ────────────────────────── 트랙 ──────────────────────────

static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

const BRIDGE_H := 0.6

## 트랙 정의(tracks.json의 한 항목)로 가운데 선을 `spacing` 간격 점으로 만든다.
## 조절점에 세 번째 값이 있으면 높이. zones(구간, 길이 비율 0..1): ramp(at) 점프대, stairs(from,to) 계단, ice 얼음, gap 낭떠러지, pad(at) 부스터 발판
static func build_track(def: Dictionary, spacing := 2.0) -> Dictionary:
	var ctrl: Array[Vector2] = []
	var ch: Array[float] = []
	for p in def.points:
		ctrl.append(Vector2(p[0], p[1]))
		ch.append(float(p[2]) if p.size() > 2 else 0.0)
	var n := ctrl.size()
	var dense: Array[Vector2] = []
	var dense_h: Array[float] = []
	for i in n:
		for j in 24:
			dense.append(_cr(ctrl[(i - 1 + n) % n], ctrl[i], ctrl[(i + 1) % n], ctrl[(i + 2) % n], j / 24.0))
			dense_h.append(_cr(Vector2(ch[(i - 1 + n) % n], 0), Vector2(ch[i], 0), Vector2(ch[(i + 1) % n], 0), Vector2(ch[(i + 2) % n], 0), j / 24.0).x)
	var total := 0.0
	for i in dense.size():
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
	var count := maxi(16, int(round(total / spacing)))
	var step_len := total / count
	var pts := PackedVector2Array()
	var raw_h := PackedFloat32Array()
	var acc := 0.0
	var want := 0.0
	for i in dense.size():
		var a := dense[i]
		var b := dense[(i + 1) % dense.size()]
		var seg := a.distance_to(b)
		while want <= acc + seg and pts.size() < count:
			var f := (want - acc) / maxf(seg, 0.0001)
			pts.append(a.lerp(b, f))
			raw_h.append(lerpf(dense_h[i], dense_h[(i + 1) % dense.size()], f))
			want += step_len
		acc += seg
	var m := pts.size()
	var hgt := PackedFloat32Array()
	hgt.resize(m)
	for i in m:
		var sum := 0.0
		for o in range(-3, 4):
			sum += raw_h[(i + o + m) % m]
		hgt[i] = maxf(0.0, sum / 7.0)
	var tang := PackedVector2Array()
	var norm := PackedVector2Array()
	var cum := PackedFloat32Array()
	var curv := PackedFloat32Array()
	tang.resize(m); norm.resize(m); cum.resize(m); curv.resize(m)
	var s := 0.0
	for i in m:
		var t := (pts[(i + 1) % m] - pts[(i - 1 + m) % m]).normalized()
		tang[i] = t
		norm[i] = Vector2(-t.y, t.x)
		cum[i] = s
		s += pts[i].distance_to(pts[(i + 1) % m])
	for i in m:
		var a2 := tang[(i - 2 + m) % m]
		var b2 := tang[(i + 2) % m]
		curv[i] = a2.angle_to(b2) / (4.0 * step_len)
	var hw: float = def.get("half_width", 7.0)
	var sky: bool = str(def.get("theme", "")) == "sky"
	var ground_wall: float = hw + float(def.get("verge", 5.0))
	# 구간 (미터로)
	var zones := []
	for z in def.get("zones", []):
		var zt := str(z.type)
		var e := {"type": zt}
		if z.has("len"):
			# at(비율)에서 시작해 len 미터
			e.s0 = float(z.at) * s
			e.s1 = e.s0 + float(z.len)
		elif zt in ["ramp", "pad"]:
			var at := float(z.at) * s
			e.s0 = at - (RAMP_LEN if zt == "ramp" else 2.5)
			e.s1 = at
		else:
			e.s0 = float(z.from) * s
			e.s1 = float(z.to) * s
		zones.append(e)
	var walls := PackedFloat32Array()
	walls.resize(m)
	var bridge := false
	for i in m:
		var edge := hgt[i] > BRIDGE_H or sky
		walls[i] = hw + 0.9 if edge else ground_wall
		bridge = bridge or hgt[i] > BRIDGE_H
	return {
		"pts": pts, "tan": tang, "nrm": norm, "cum": cum, "curv": curv, "length": s, "n": m,
		"half_width": hw, "wall": ground_wall, "laps": int(def.get("laps", 3)),
		"hgt": hgt, "walls": walls, "has_bridge": bridge, "zones": zones, "sky": sky,
	}

## 출발선부터 거리 s 인 가운데 선 위치 {pos, tan, nrm, h, i}
static func point_at(tr: Dictionary, s: float) -> Dictionary:
	var L: float = tr.length
	var x := fposmod(s, L)
	var cum: PackedFloat32Array = tr.cum
	var lo := 0
	var hi: int = tr.n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= x:
			lo = mid
		else:
			hi = mid - 1
	var i := lo
	var j: int = (i + 1) % tr.n
	var seg: float = (cum[j] if j > 0 else L) - cum[i]
	var t := clampf((x - cum[i]) / maxf(seg, 0.001), 0.0, 1.0)
	var p: Vector2 = (tr.pts[i] as Vector2).lerp(tr.pts[j], t)
	return {"pos": p, "tan": tr.tan[i], "nrm": tr.nrm[i], "h": lerpf(height_at(tr, i), height_at(tr, j), t), "i": i}

static func height_at(tr: Dictionary, i: int) -> float:
	return float(tr.hgt[i]) if tr.has("hgt") else 0.0

## 가장 가까운 가운데 선 위치. hint(지난번 번호)가 있으면 그 근처만 본다.
## 돌려주는 것: {i, s(출발선부터 거리), lat(오른쪽 +), point, tan, h, wall}
static func locate(tr: Dictionary, pos: Vector2, hint := -1, y := -1.0) -> Dictionary:
	var pts: PackedVector2Array = tr.pts
	var m: int = tr.n
	var best := -1
	var bd := INF
	if hint >= 0:
		for o in range(-12, 13):
			var j := (hint + o + m) % m
			var d := pts[j].distance_squared_to(pos)
			if d < bd:
				bd = d; best = j
		if bd > 30.0 * 30.0:
			best = -1
	if best < 0:
		bd = INF
		var has_h: bool = y >= 0.0 and tr.has("hgt")
		for j in m:
			var d := pts[j].distance_squared_to(pos)
			if has_h:
				var dh: float = float(tr.hgt[j]) - y
				d += dh * dh * 6.0
			if d < bd:
				bd = d; best = j
	var res := {}
	var bestd := INF
	for seg in [[(best - 1 + m) % m, best], [best, (best + 1) % m]]:
		var a := pts[seg[0]]
		var b := pts[seg[1]]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(pos)
		if d < bestd:
			bestd = d
			var tn := ab.normalized()
			var nn := Vector2(-tn.y, tn.x)
			var s: float = tr.cum[seg[0]] + ab.length() * t
			var h := lerpf(height_at(tr, seg[0]), height_at(tr, seg[1]), t)
			var wl: float = tr.walls[best] if tr.has("walls") else tr.wall
			res = {"i": best, "s": fposmod(s, tr.length), "lat": (pos - q).dot(nn), "point": q, "tan": tn, "h": h, "wall": wl}
	return res

## 거리 s 가 속한 구간 (없으면 빈 값). 출발선을 넘는 구간도 된다
static func zone_at(tr: Dictionary, s: float) -> Dictionary:
	var L: float = tr.length
	for z in tr.get("zones", []):
		var a := fposmod(s - float(z.s0), L)
		if a <= float(z.s1) - float(z.s0):
			return z
	return {}

## 바닥 정보 {h, kind, ramp_t, pad} (step에 넘긴다)
static func ground_at(tr: Dictionary, loc: Dictionary) -> Dictionary:
	var hw: float = tr.half_width
	var lat: float = absf(float(loc.lat))
	var on_road := lat <= hw
	var kind := "road" if on_road else "grass"
	if float(loc.get("wall", tr.wall)) < hw + 1.5:
		kind = "road"   # 다리·하늘 길은 난간까지 다 길
	var h: float = loc.h
	var ramp_t := -1.0
	var pad := false
	var z := zone_at(tr, loc.s)
	if not z.is_empty():
		var t := fposmod(float(loc.s) - float(z.s0), tr.length) / maxf(float(z.s1) - float(z.s0), 0.01)
		match str(z.type):
			"ramp":
				if lat <= hw + 0.5:
					ramp_t = clampf(t, 0.0, 1.0)
					h += RAMP_H * ramp_t
					kind = "road"
			"stairs":
				if lat <= hw + 0.5:
					kind = "stairs"
			"ice":
				if kind == "road":
					kind = "ice"
			"gap":
				kind = "gap"
				h = -20.0
			"pad":
				pad = on_road and lat < hw * 0.6
	return {"h": h, "kind": kind, "ramp_t": ramp_t, "pad": pad}

## 울타리 밖으로 나가면 안으로 밀고 바깥쪽 속도를 없앤다. 부딪혔으면 true
static func wall_push(tr: Dictionary, k: Dictionary, loc: Dictionary, radius := 0.7) -> bool:
	var lim: float = float(loc.get("wall", tr.wall)) - radius
	if absf(loc.lat) <= lim:
		return false
	var tn: Vector2 = loc.tan
	var nn := Vector2(-tn.y, tn.x) * signf(loc.lat)
	k.pos = (loc.point as Vector2) + nn * lim
	var v: Vector2 = k.vel
	var out := v.dot(nn)
	if out > 0.0:
		v -= nn * out * 1.4
	k.vel = v * 0.94
	k.slide = false
	return true

static func advance(prev: float, s: float, length: float) -> float:
	var cur := fposmod(prev, length)
	var d := s - cur
	if d > length * 0.5:
		d -= length
	elif d < -length * 0.5:
		d += length
	return prev + d

static func lap_of(dist: float, length: float) -> int:
	return maxi(1, int(floor(dist / length)) + 1)

## 순위: 들어온 사람은 들어온 시간 순, 나머지는 간 거리 순. 각 항목 {dist, finish(-1이면 아직)}
static func ranking(rs: Array) -> Array:
	var idx := range(rs.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var fa: float = rs[a].finish
		var fb: float = rs[b].finish
		if fa >= 0.0 and fb >= 0.0:
			return fa < fb
		if fa >= 0.0 or fb >= 0.0:
			return fa >= 0.0
		return rs[a].dist > rs[b].dist)
	return idx

## 레이싱 라인: 가운데 선에서 옆으로 얼마나 비킬지(점마다)
static func racing_line(tr: Dictionary, margin := 2.0, iters := 400) -> PackedFloat32Array:
	var m: int = tr.n
	var lim: float = tr.half_width - margin
	var off := PackedFloat32Array()
	off.resize(m)
	var pts: PackedVector2Array = tr.pts
	var nrm: PackedVector2Array = tr.nrm
	for _it in iters:
		for i in m:
			var a := pts[(i - 1 + m) % m] + nrm[(i - 1 + m) % m] * off[(i - 1 + m) % m]
			var b := pts[(i + 1) % m] + nrm[(i + 1) % m] * off[(i + 1) % m]
			var mid := (a + b) * 0.5
			off[i] = clampf((mid - pts[i]).dot(nrm[i]), -lim, lim)
	return off

## 출발 자리: 출발선 뒤로 두 줄씩
static func grid_slot(tr: Dictionary, slot: int) -> Dictionary:
	var row := int(slot / 2.0)
	var side := -1.0 if slot % 2 == 0 else 1.0
	var back := 5.0 + row * 4.2
	var m: int = tr.n
	var i := m - 1
	var s := 0.0
	while s < back and i > 0:
		s += (tr.pts[i] as Vector2).distance_to(tr.pts[(i + 1) % m])
		i -= 1
	var t: Vector2 = tr.tan[i]
	var p: Vector2 = tr.pts[i] + tr.nrm[i] * side * tr.half_width * 0.4
	if slot % 2 == 1:
		p -= t * 2.0
	return {"pos": p, "yaw": atan2(t.x, t.y), "h": height_at(tr, i)}

## 떨어졌을 때 다시 시작할 자리: 지금 구간(낭떠러지) 앞쪽 길 가운데
static func respawn_at(tr: Dictionary, s: float) -> Dictionary:
	var back := s
	var z := zone_at(tr, s)
	if not z.is_empty():
		back = float(z.s0)
	# 바로 앞 점프대 시작보다 조금 앞으로 (다시 뛸 수 있게)
	for zz in tr.get("zones", []):
		if str(zz.type) == "ramp":
			var d := fposmod(back - float(zz.s1), tr.length)
			if d < 30.0:
				back = float(zz.s0) - 14.0
				break
	var p := point_at(tr, back)
	var t: Vector2 = p.tan
	return {"pos": p.pos, "yaw": atan2(t.x, t.y), "h": p.h, "s": fposmod(back, tr.length)}

# ────────────────────────── 컴퓨터 상대 ──────────────────────────

## 컴퓨터가 누를 키. skill 0..1, offset 레이싱 라인에서 비킬 거리, rnd 0..1 난수 (매 프레임 새로)
## plan: 컴퓨터마다 하나씩 들고 있는 기억 {jump_at 점프대 어디서 뛸지}
static func ai_input(k: Dictionary, tr: Dictionary, line: PackedFloat32Array, loc: Dictionary, g: Dictionary, skill: float, offset: float, rnd: float, plan: Dictionary, st: Dictionary = {}) -> Dictionary:
	var m: int = tr.n
	var spd := absf(speed_of(k))
	var look := int(clampf(3.5 + spd * 0.3, 4.0, 14.0))
	var j: int = (loc.i + look) % m
	var lim: float = tr.half_width - 1.0
	var target: Vector2 = tr.pts[j] + tr.nrm[j] * clampf(line[j] + offset, -lim, lim)
	var to := target - (k.pos as Vector2)
	var f := fwd(k.yaw)
	var ang := f.angle_to(to)
	if (k.vel as Vector2).length() > 4.0 and (k.slide or g.kind == "ice"):
		ang = (k.vel as Vector2).normalized().angle_to(to)
	var steer := clampf(ang * 2.4, -1.0, 1.0)
	var bend := 0.0
	for o in [5, 8, 11, 14]:
		bend += float(tr.curv[(loc.i + o) % m])
	bend /= 4.0
	var sharp := absf(bend) * 30.0
	var slide := sharp > 0.6 and spd > 16.0 and absf(steer) > 0.5 and rnd < 0.4 + skill * 0.6
	var throttle := 1.0
	if absf(ang) > 1.2 and spd > 12.0:
		throttle = -1.0
	var hard := 0.0
	for o in [3, 6, 9]:
		hard = maxf(hard, absf(float(tr.curv[(loc.i + o) % m])) * 30.0)
	if hard > 1.3 and spd > 20.0:
		throttle = -1.0
	if spd < 3.0 and absf(ang) > 1.4:
		throttle = -1.0
		steer = -signf(ang)
	# 점프: 점프대에서는 정한 자리에서, 계단 앞에서는 폴짝
	var jump := false
	var ramp_t: float = g.get("ramp_t", -1.0)
	if not k.air:
		if ramp_t >= 0.0:
			if not plan.has("jump_at"):
				plan.jump_at = clampf(0.6 + 0.3 * skill + (rnd - 0.5) * 0.3 * (1.2 - skill), 0.35, 0.92)
			if ramp_t >= float(plan.jump_at):
				jump = true
				plan.erase("jump_at")
		else:
			plan.erase("jump_at")
			var ahead := zone_at(tr, float(loc.s) + spd * 0.35 + 2.0)
			var on_stairs: bool = g.kind == "stairs"
			if not ahead.is_empty() and str(ahead.type) == "stairs" and (not on_stairs and rnd < 0.25 + skill * 0.7 or on_stairs and rnd < 0.05 + skill * 0.3):
				jump = true
	# 공중 묘기: 남은 시간에 맞는 것을 고른다 (서툴면 욕심내다 실패하기도)
	var trick := ""
	if k.air and k.trick == "":
		var left := air_left(k.vy, k.alt, float(g.h) if float(g.h) > -5.0 else float(loc.h))
		var greed := 0.06 + (1.0 - skill) * 0.25 * (rnd - 0.35)
		if not plan.has("tdelay"):
			plan.tdelay = (1.0 - skill) * 0.2 * rnd
		if k.air_t > float(plan.tdelay):
			# 남은 시간에 들어가는 가장 큰 묘기를, 잘하면 끝나자마자 땅에 닿게 기다렸다가 건다
			var slack := 0.05 + (1.0 - skill) * 0.4
			for name in ["720", "360", "gb"]:
				var need := trick_dur(name, st if not st.is_empty() else {"trick_speed": 1.0}) + greed
				if left > need:
					if left - need < slack or k.vy < 0.0 and left - need < slack + 0.15:
						trick = name
					break
	if not k.air:
		plan.erase("tdelay")
	var use: bool = k.boosts > 0 and sharp < 0.25 and not k.air and rnd < 0.02 + skill * 0.05
	return {"throttle": throttle, "steer": steer, "slide": slide, "jump": jump, "trick": trick, "use_boost": use}

## 컴퓨터 실력에 맞춘 능력치 (조금 느리게, 뒤처지면 살짝 따라잡기)
static func ai_stats(st: Dictionary, skill: float, behind: float) -> Dictionary:
	var out := st.duplicate()
	var catch := clampf(behind / 120.0, -0.4, 1.0) * 0.06
	out.max_speed = st.max_speed * (0.88 + 0.1 * skill + catch)
	out.accel = st.accel * (0.9 + 0.1 * skill)
	return out

# ────────────────────────── 돈·경험치·상점·저장 ──────────────────────────

## 순위 보상 (place는 1부터)
static func reward(place: int, racers: int, mode: String) -> int:
	if mode == "time" or racers <= 1:
		return 0
	var table := [100, 76, 60, 48, 40, 32, 26, 20]
	return table[clampi(place - 1, 0, table.size() - 1)]

## 경험치: 순위 + 묘기 점수
static func exp_gain(place: int, racers: int, points: int, mode: String) -> int:
	var base := 30
	if mode != "time" and racers > 1:
		var table := [60, 50, 42, 36, 32, 28, 24, 20]
		base = table[clampi(place - 1, 0, table.size() - 1)]
	return base + int(points / 10.0)

## 레벨 L에서 다음 레벨까지 필요한 경험치
static func exp_need(level: int) -> int:
	return 80 + 40 * level

## 모은 경험치로 {level, into(이번 레벨에서 모은 것), need}
static func level_info(total: int) -> Dictionary:
	var lv := 1
	var left := maxi(0, total)
	while left >= exp_need(lv) and lv < 99:
		left -= exp_need(lv)
		lv += 1
	return {"level": lv, "into": left, "need": exp_need(lv)}

## 팀전 점수 (순위별)
const TEAM_POINTS := [10, 8, 6, 5, 4, 3, 2, 1]

static func team_score(places: Array) -> int:
	var s := 0
	for p in places:
		s += TEAM_POINTS[clampi(int(p) - 1, 0, TEAM_POINTS.size() - 1)]
	return s

## 혼자 타임어택 메달: par = 금메달 기록
static func medal(time: float, par: float) -> String:
	if time <= 0.0 or par <= 0.0:
		return ""
	if time <= par:
		return "gold"
	if time <= par * 1.12:
		return "silver"
	if time <= par * 1.28:
		return "bronze"
	return ""

const MEDAL_RANK := {"": 0, "bronze": 1, "silver": 2, "gold": 3}
const MEDAL_COINS := {"bronze": 30, "silver": 60, "gold": 100}

## 타임어택 보상: 처음 달리면 조금, 더 좋은 메달을 처음 따면 그 메달 값
static func time_reward(old_medal: String, new_medal: String, first: bool) -> int:
	var r := 20 if first else 5
	if MEDAL_RANK[new_medal] > MEDAL_RANK[old_medal]:
		r += int(MEDAL_COINS[new_medal])
	return r

## 경주 뒤 행운 상자: rnd 0..1, rnd2 0..1, rare = 아직 없는 희귀 보드 id 목록
## {kind: "coins"(조금) | "pouch"(주머니) | "lucky"(받은 돈 다섯 배) | "board"(희귀 보드), amount, board}
static func lucky_roll(rnd: float, rnd2: float, rare: Array, place: int) -> Dictionary:
	var board_chance := 0.03 + (0.02 if place == 1 else 0.0)
	if not rare.is_empty() and rnd < board_chance:
		return {"kind": "board", "amount": 0, "board": rare[int(rnd2 * rare.size()) % rare.size()]}
	if rnd < board_chance + 0.06:
		return {"kind": "lucky", "amount": 5, "board": ""}
	if rnd < board_chance + 0.28:
		return {"kind": "pouch", "amount": 40 + int(rnd2 * 9) * 10, "board": ""}
	return {"kind": "coins", "amount": 5 + int(rnd2 * 4) * 5, "board": ""}

const COIN_VALUE := 5

## 살 수 있나: 희귀 보드는 상점에서 못 사고, 레벨이 모자라도 못 산다
static func can_buy(save: Dictionary, board: Dictionary) -> bool:
	if bool(board.get("rare", false)):
		return false
	if level_info(int(save.get("exp", 0))).level < int(board.get("level", 1)):
		return false
	return not (board.id in save.owned) and int(save.coins) >= int(board.price)

static func buy(save: Dictionary, board: Dictionary) -> Dictionary:
	if not can_buy(save, board):
		return save
	var s := save.duplicate(true)
	s.coins = int(s.coins) - int(board.price)
	s.owned.append(board.id)
	s.board = board.id
	return s

const RIDERS := ["oobi", "oodi", "ooli", "oopi", "oozi"]

static func default_save() -> Dictionary:
	return {"v": 1, "coins": 0, "exp": 0, "owned": [START_BOARD], "board": START_BOARD, "rider": "oobi",
		"name": "나", "best": {}, "medals": {}, "races": 0, "wins": 0}

## 저장 값 읽기. 망가졌거나 모자란 값도 받아 준다
static func parse_save(raw: Variant, board_ids: Array) -> Dictionary:
	var s := default_save()
	if typeof(raw) == TYPE_STRING:
		var j := JSON.new()
		raw = j.data if j.parse(raw) == OK else null
	if typeof(raw) != TYPE_DICTIONARY:
		return s
	for key in ["coins", "exp", "races", "wins"]:
		if typeof(raw.get(key)) in [TYPE_INT, TYPE_FLOAT]:
			s[key] = maxi(0, int(raw[key]))
	if typeof(raw.get("owned")) == TYPE_ARRAY:
		for id in raw.owned:
			if id in board_ids and not (id in s.owned):
				s.owned.append(id)
	if raw.get("board") in s.owned:
		s.board = raw.board
	if raw.get("rider") in RIDERS:
		s.rider = raw.rider
	if typeof(raw.get("name")) == TYPE_STRING:
		var nm := clean_name(raw.name)
		if nm != "":
			s.name = nm
	if typeof(raw.get("best")) == TYPE_DICTIONARY:
		for t in raw.best:
			if typeof(raw.best[t]) in [TYPE_INT, TYPE_FLOAT] and float(raw.best[t]) > 0.0:
				s.best[str(t)] = float(raw.best[t])
	if typeof(raw.get("medals")) == TYPE_DICTIONARY:
		for t in raw.medals:
			if raw.medals[t] in ["bronze", "silver", "gold"]:
				s.medals[str(t)] = raw.medals[t]
	return s

## 이름: 앞뒤 공백 빼고 8글자까지
static func clean_name(t: String) -> String:
	var s := t.strip_edges().replace("\n", " ")
	return s.substr(0, 8)

static func time_text(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var sec := t - m * 60.0
	return "%d:%05.2f" % [m, sec]

# ────────────────────────── 온라인 연결 코드 ──────────────────────────

const NET_PREFIX := "BR1-"

static func net_encode(desc: Dictionary, cands: Array) -> String:
	var raw := JSON.stringify({"t": desc.t, "s": desc.s, "c": cands}).to_utf8_buffer()
	return NET_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))

static func net_decode(code: String) -> Dictionary:
	var s := code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	var at := s.find(NET_PREFIX)
	if at < 0:
		return {}
	s = s.substr(at + NET_PREFIX.length())
	var only := ""
	for ch in s:
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["+", "/", "="]:
			only += ch
		else:
			break
	s = only
	if s.length() < 16 or s.length() % 4 != 0:
		return {}
	var bytes := Marshalls.base64_to_raw(s)
	if bytes.is_empty():
		return {}
	var raw := bytes.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return {}
	var j := JSON.new()
	if j.parse(raw.get_string_from_utf8()) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = j.data
	if not (d.has("t") and d.has("s") and d.has("c")) or typeof(d.c) != TYPE_ARRAY:
		return {}
	return d

# ────────────────────────── 방 코드 ──────────────────────────

const ROOM_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_LEN := 6

static func room_new(rng: RandomNumberGenerator) -> String:
	var c := ""
	for i in ROOM_LEN:
		c += ROOM_CHARS[rng.randi_range(0, ROOM_CHARS.length() - 1)]
	return c

static func room_clean(t: String) -> String:
	var out := ""
	for ch in t.to_upper():
		if ch in ROOM_CHARS:
			out += ch
	return out if out.length() == ROOM_LEN else ""

static func relay_list(body: String) -> Array:
	var out := []
	for line in body.split("\n", false):
		var j := JSON.new()
		if j.parse(line) != OK or typeof(j.data) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = j.data
		if str(d.get("event", "message")) != "message":
			continue
		out.append({"id": str(d.get("id", "")), "m": str(d.get("message", ""))})
	return out

static func relay_pick(body: String, prefix: String) -> String:
	var found := ""
	for line in body.split("\n", false):
		var j := JSON.new()
		if j.parse(line) != OK or typeof(j.data) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = j.data
		if str(d.get("event", "message")) != "message":
			continue
		var m := str(d.get("message", ""))
		if m.begins_with(prefix):
			found = m.substr(prefix.length())
	return found

# ────────────────────────── 아이템전 ──────────────────────────
## boost 부스터, balloon 물풍선(앞으로 던짐), goo 끈끈이(뒤에 둠), cloud 먹구름(바로 앞 사람을 쫓아가 벼락),
## shield 비눗방울(한 번 막음), quake 쿵쿵(앞의 모두를 잠깐 흔듦)
const ITEMS := ["boost", "balloon", "goo", "cloud", "shield", "quake"]
const ITEM_NAMES := {"boost": "부스터", "balloon": "물풍선", "goo": "끈끈이", "cloud": "먹구름", "shield": "비눗방울", "quake": "쿵쿵"}
const MAX_ITEMS := 2
const SPIN_TIME := 1.2
const SHIELD_TIME := 6.0

static func item_roll(place: int, racers: int, rnd: float) -> String:
	var back := 0.0 if racers <= 1 else clampf(float(place - 1) / float(racers - 1), 0.0, 1.0)
	var w := {
		"boost": 1.0 + 2.0 * back,
		"balloon": 2.0,
		"goo": 2.2 - 1.6 * back,
		"cloud": 0.2 + 2.4 * back if place > 1 else 0.0,
		"shield": 1.6 - 1.0 * back,
		"quake": 0.0 if back < 0.5 else (back - 0.5) * 2.4,
	}
	var total := 0.0
	for k in ITEMS:
		total += float(w[k])
	var x := rnd * total
	for k in ITEMS:
		x -= float(w[k])
		if x <= 0.0:
			return k
	return "boost"

static func give_item(k: Dictionary, item: String) -> bool:
	var items: Array = k.get("items", [])
	if items.size() >= MAX_ITEMS:
		return false
	items.append(item)
	k.items = items
	return true

## 맞았다: 방패가 있으면 방패만 깨지고, 아니면 빙글빙글
static func hit(k: Dictionary, time := SPIN_TIME) -> bool:
	if float(k.get("shield_t", 0.0)) > 0.0:
		k.shield_t = 0.0
		k.events.append("shield_break")
		return false
	if float(k.get("spin_t", 0.0)) > 0.0:
		return false
	k.spin_t = time
	k.slide = false
	k.boost_t = 0.0
	k.dash_t = 0.0
	k.trick = ""
	k.spin = 0.0
	k.done = []
	k.combo = 0
	k.events.append("spin")
	return true

static func _spin_step(k: Dictionary, gh: float, dt: float) -> void:
	k.spin_t = maxf(0.0, float(k.spin_t) - dt)
	k.yaw = wrapf(float(k.yaw) + 10.0 * dt, -PI, PI)
	k.yaw_rate = 10.0
	var v: Vector2 = k.vel
	v = v.move_toward(Vector2.ZERO, 26.0 * dt) * exp(-0.6 * dt)
	k.vel = v
	k.pos = (k.pos as Vector2) + v * dt
	k.slip = 0.0
	k.steer_s = 0.0
	# 공중이었으면 땅으로
	if k.air:
		k.vy -= GRAVITY * dt
		k.alt += k.vy * dt
		if k.alt <= gh:
			k.air = false
			k.alt = gh
			k.vy = 0.0
	else:
		k.alt = gh
	k.prev_g = gh
	if k.spin_t <= 0.0 and v.length() > 1.0:
		k.yaw = atan2(v.x, v.y)

static func ai_use_item(item: String, place: int, ahead: float, behind: float, straight: bool, threatened: bool, rnd: float) -> bool:
	match item:
		"boost": return straight and rnd < 0.05
		"balloon": return ahead < 45.0 and rnd < 0.08
		"cloud": return place > 1 and rnd < 0.05
		"goo": return behind < 25.0 and rnd < 0.08
		"shield": return threatened or rnd < 0.004
		"quake": return place > 2 and rnd < 0.05
	return false
