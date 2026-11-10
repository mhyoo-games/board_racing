class_name Hud
extends Control
## 경주 화면 위: 랩·시간, 순위표, A·S·D·F 단추, 점프대 타이밍 줄, 착지까지 남은 시간, 판정 글자, 게이지, 작은 지도

var race: Node            # race.gd
var racer: Dictionary     # 이 화면의 선수
var msgs: Array = []      # [{text, t, color}]
var pops: Array = []      # 판정 글자 [{word, label, combo, t}]
var flash := 0.0
var keys := {"jump": 0.0, "gb": 0.0, "t360": 0.0, "t720": 0.0}
var map_pts := PackedVector2Array()
var map_rect := Rect2()

const TEAM_COLORS := [Color(1.0, 0.42, 0.42), Color(0.38, 0.62, 1.0)]
const TEAM_NAMES := ["빨강팀", "파랑팀"]
const JUDGE_COLORS := {"GOOD": Color(0.55, 0.9, 1.0), "NICE": Color(0.6, 1.0, 0.45), "EXCELLENT": Color(1.0, 0.85, 0.2), "MISS": Color(1.0, 0.45, 0.45)}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func say(text: String, color := Color(1, 0.95, 0.6), time := 1.3) -> void:
	for m in msgs:
		if m.text == text:
			m.t = time
			return
	msgs.append({"text": text, "t": time, "color": color, "full": time})
	if msgs.size() > 3:
		msgs.pop_front()

## 큰 글자 한 번 (출발 부스터 등)
func pop(text: String, color: Color) -> void:
	pops.append({"word": text, "label": "", "combo": 0, "t": 0.0, "color": color})

func judge(j: Dictionary) -> void:
	if j.is_empty():
		return
	var w := str(j.get("word", ""))
	pops = pops.filter(func(p): return p.t < 0.2)
	pops.append({"word": w + ("!" if w != "MISS" else ""), "label": str(j.get("label", "")), "combo": int(j.get("combo", 0)), "t": 0.0, "color": JUDGE_COLORS.get(w, Color.WHITE)})

func key_flash(key: String) -> void:
	keys[key] = 0.25

func _process(dt: float) -> void:
	for m in msgs:
		m.t -= dt
	msgs = msgs.filter(func(m): return m.t > 0.0)
	for p in pops:
		p.t += dt
	pops = pops.filter(func(p): return p.t < 1.2)
	for k in keys:
		keys[k] = maxf(0.0, float(keys[k]) - dt)
	flash = maxf(0.0, flash - dt * 2.5)
	queue_redraw()

func _txt(s: String, pos: Vector2, size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, bold := true) -> void:
	var f: Font = Game.font_bold if bold else Game.font
	draw_string_outline(f, pos, s, align, width, size, maxi(4, size / 6), Color(0.06, 0.08, 0.14, 0.92))
	draw_string(f, pos, s, align, width, size, color)

func _pill(r: Rect2, c: Color, radius := 12.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, r)

func _draw() -> void:
	if race == null or racer.is_empty():
		return
	var w := size.x
	var h := size.y
	var u := clampf(minf(w / 1280.0, h / 720.0), 0.5, 1.6)
	var k: Dictionary = racer.k
	# ── 위 가운데: 랩·시간
	var laps: int = race.trk.laps
	var lap := mini(Rules.lap_of(racer.dist, race.trk.length), laps)
	var cx := w * 0.5
	_pill(Rect2(cx - 92 * u, 10 * u, 184 * u, 38 * u), Color(0.08, 0.1, 0.18, 0.75), 19 * u)
	_txt("LAP  %d / %d" % [lap, laps], Vector2(cx - 92 * u, 38 * u), int(24 * u), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 184 * u)
	var t: float = racer.finish if racer.finish >= 0.0 else race.clock
	_pill(Rect2(cx - 82 * u, 52 * u, 164 * u, 40 * u), Color(0.02, 0.03, 0.06, 0.85), 6 * u)
	_txt(Rules.time_text(maxf(t, 0.0)), Vector2(cx - 82 * u, 82 * u), int(28 * u), Color(0.7, 1.0, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 164 * u, false)
	if race.mode == "time":
		var best: float = Game.best_of(race.def.id)
		var par: float = float(race.def.get("par", 0.0))
		_txt("기록 " + Rules.time_text(best) + "   금메달 " + Rules.time_text(par), Vector2(cx - 200 * u, 116 * u), int(18 * u), Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 400 * u, false)
	# ── 오른쪽 위: 순위표
	_standings(u, w)
	# ── 왼쪽 위: 내 순위 크게
	var total: int = race.racers.size()
	if total > 1:
		_txt("%d" % racer.place, Vector2(22 * u, 84 * u), int(80 * u), Color(1, 0.86, 0.3) if racer.place == 1 else Color.WHITE)
		_txt(_ord(racer.place), Vector2((24 + (46 if racer.place < 10 else 92)) * u, 84 * u), int(30 * u), Color(0.95, 0.95, 0.95))
	if race.teams:
		_team_bar(u)
	# ── 판정 글자
	_pops(u, w, h)
	# ── 점프대 타이밍 줄 / 착지까지 남은 시간
	_timing(u, w, h, k)
	# ── 아래 왼쪽: A S D F
	_keys(u, h, k)
	# ── 아래 가운데: 게이지·부스터 (아이템전은 아이템 칸)
	if race.items_on:
		_items_ui(u, w, h, k)
	else:
		_gauge(u, w, h, k)
	# ── 오른쪽 아래: 속도 + 작은 지도
	var kmh := int(absf(Rules.speed_of(k)) * Rules.KMH)
	_txt("%d" % kmh, Vector2(w - 330 * u, h - 30 * u), int(52 * u), Color(1, 0.65, 0.25) if Rules.boosting(k) else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 140 * u)
	_txt("km/h", Vector2(w - 186 * u, h - 34 * u), int(18 * u), Color(0.9, 0.9, 0.9))
	_minimap(Rect2(w - 176 * u, h - 176 * u, 164 * u, 164 * u))
	# ── 가운데 글
	var my := h * 0.6
	for m in msgs:
		var a: float = clampf(m.t / 0.3, 0.0, 1.0)
		var c: Color = m.color
		c.a = a
		_txt(m.text, Vector2(0, my), int(34 * u), c, HORIZONTAL_ALIGNMENT_CENTER, w)
		my += 44 * u
	if racer.wrong > 1.2 and racer.finish < 0.0:
		_txt("거꾸로 가고 있어요!", Vector2(0, h * 0.32), int(40 * u), Color(1, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER, w)
	if race.state == "count":
		var n := int(ceil(race.count_left))
		if n <= 3 and n >= 1:
			var s: float = 1.0 + (ceil(race.count_left) - race.count_left) * 0.6
			_txt(str(n), Vector2(0, h * 0.42 + 40 * u * s), int(130 * u * s), Color(1, 0.95, 0.5), HORIZONTAL_ALIGNMENT_CENTER, w)
		elif n > 3:
			_txt("준비!", Vector2(0, h * 0.42), int(70 * u), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, w)
	elif race.clock < 1.0 and race.state == "run":
		_txt("출발!", Vector2(0, h * 0.42), int(110 * u), Color(0.6, 1.0, 0.55, 1.0 - race.clock), HORIZONTAL_ALIGNMENT_CENTER, w)
	if racer.finish >= 0.0:
		_txt("도착! %d등" % racer.place, Vector2(0, h * 0.38), int(70 * u), Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
	if flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.85, 0.5, flash * 0.12))

func _ord(p: int) -> String:
	match p:
		1: return "st"
		2: return "nd"
		3: return "rd"
	return "th"

func _standings(u: float, w: float) -> void:
	var order: Array = race.racers.duplicate()
	order.sort_custom(func(a, b): return int(a.place) < int(b.place))
	var x := w - 214 * u
	var y := 14 * u
	for r in order:
		var me: bool = r == racer
		var bg := Color(1, 0.85, 0.3, 0.85) if me else Color(0.06, 0.08, 0.16, 0.55)
		_pill(Rect2(x, y, 200 * u, 28 * u), bg, 8 * u)
		if int(r.team) >= 0:
			draw_rect(Rect2(x, y, 6 * u, 28 * u), TEAM_COLORS[int(r.team)])
		var tc := Color(0.1, 0.08, 0.05) if me else Color.WHITE
		var pf: Font = Game.font_bold
		draw_string(pf, Vector2(x + 12 * u, y + 21 * u), "%d%s" % [r.place, _ord(r.place)], HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * u), tc)
		var nm: String = r.name
		if r.finish >= 0.0:
			nm += "  ★"
		draw_string(Game.font, Vector2(x + 62 * u, y + 21 * u), nm, HORIZONTAL_ALIGNMENT_LEFT, 132 * u, int(18 * u), tc)
		y += 31 * u

func _team_bar(u: float) -> void:
	var places := [[], []]
	for r in race.racers:
		if int(r.team) >= 0:
			places[int(r.team)].append(int(r.place))
	var s0 := Rules.team_score(places[0])
	var s1 := Rules.team_score(places[1])
	var x := 22.0 * u
	var y := 110.0 * u
	for i in 2:
		_pill(Rect2(x, y + i * 34 * u, 170 * u, 30 * u), Color(TEAM_COLORS[i].r, TEAM_COLORS[i].g, TEAM_COLORS[i].b, 0.8), 8 * u)
		_txt("%s  %d점" % [TEAM_NAMES[i], s0 if i == 0 else s1], Vector2(x + 10 * u, y + i * 34 * u + 22 * u), int(19 * u), Color.WHITE)

func _pops(u: float, w: float, h: float) -> void:
	for p in pops:
		var t: float = p.t
		var s := 1.0 + 0.6 * exp(-t * 12.0)
		var a := clampf((1.2 - t) / 0.3, 0.0, 1.0)
		var c: Color = p.color
		c.a = a
		var y := h * 0.28 - t * 20.0 * u
		if p.label != "":
			_txt(p.label, Vector2(0, y - 62 * u * s), int(30 * u), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		_txt(p.word, Vector2(0, y), int(64 * u * s), c, HORIZONTAL_ALIGNMENT_CENTER, w)
		if int(p.combo) >= 2:
			_txt("콤보 x%d" % int(p.combo), Vector2(0, y + 40 * u), int(26 * u), Color(1, 0.75, 0.4, a), HORIZONTAL_ALIGNMENT_CENTER, w)

## 점프대 위: GOOD/NICE/EXCELLENT 줄과 지금 자리. 공중: 땅까지 남은 시간과 묘기 진행
func _timing(u: float, w: float, h: float, k: Dictionary) -> void:
	var g: Dictionary = racer.get("g", {})
	var bw := 360.0 * u
	var bh := 20.0 * u
	var bx := w * 0.5 - bw * 0.5
	var by := h - (196.0 if race.items_on else 150.0) * u
	var rt := float(g.get("ramp_t", -1.0))
	if rt >= 0.0 and not k.air:
		_pill(Rect2(bx - 6 * u, by - 30 * u, bw + 12 * u, bh + 38 * u), Color(0.05, 0.07, 0.14, 0.7), 10 * u)
		draw_rect(Rect2(bx, by, bw * 0.6, bh), Color(0.45, 0.75, 1.0))
		draw_rect(Rect2(bx + bw * 0.6, by, bw * 0.24, bh), Color(0.55, 1.0, 0.45))
		draw_rect(Rect2(bx + bw * 0.84, by, bw * 0.16, bh), Color(1.0, 0.85, 0.2))
		var cx := bx + bw * rt
		draw_rect(Rect2(cx - 3 * u, by - 6 * u, 6 * u, bh + 12 * u), Color.WHITE)
		_txt("A 점프!", Vector2(bx, by - 8 * u), int(20 * u), Color(1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, bw)
	elif k.air and racer.finish < 0.0:
		var gh: float = float(g.get("h", 0.0))
		if gh < -5.0:
			gh = float(Rules.locate(race.trk, k.pos, racer.hint).h)
		var left := Rules.air_left(float(k.vy), float(k.alt), gh)
		var scale := 1.4
		_pill(Rect2(bx - 6 * u, by - 30 * u, bw + 12 * u, bh + 38 * u), Color(0.05, 0.07, 0.14, 0.6), 10 * u)
		draw_rect(Rect2(bx, by, bw * clampf(left / scale, 0.0, 1.0), bh), Color(0.5, 0.85, 1.0, 0.85))
		if str(k.trick) != "":
			var rem := maxf(0.0, float(k.trick_dur) - float(k.trick_t))
			var col := Color(0.55, 1.0, 0.45) if rem <= left else Color(1.0, 0.45, 0.4)
			draw_rect(Rect2(bx, by + bh * 0.25, bw * clampf(rem / scale, 0.0, 1.0), bh * 0.5), col)
			_txt("묘기 중…", Vector2(bx, by - 8 * u), int(18 * u), col, HORIZONTAL_ALIGNMENT_CENTER, bw)
		else:
			_txt("S · D · F 묘기!" if left > 0.35 else "착지!", Vector2(bx, by - 8 * u), int(18 * u), Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, bw)

func _keys(u: float, h: float, k: Dictionary) -> void:
	var names := [["jump", "A", "점프"], ["gb", "S", "GB"], ["t360", "D", "360"], ["t720", "F", "720"]]
	var x := 16.0 * u
	var y := h - 86.0 * u
	var air: bool = k.air
	var on_ramp := float(racer.get("g", {}).get("ramp_t", -1.0)) >= 0.0
	for i in names.size():
		var key: String = names[i][0]
		var ready := (not air) if i == 0 else (air and str(k.trick) == "")
		var lit: bool = float(keys[key]) > 0.0
		var base := Color(0.15, 0.45, 0.85, 0.85) if ready else Color(0.2, 0.22, 0.3, 0.7)
		if i == 0 and on_ramp and not air:
			base = Color(1.0, 0.75, 0.2, 0.95)
		if lit:
			base = base.lightened(0.45)
		var r := Rect2(x + i * 76 * u, y, 70 * u, 70 * u)
		_pill(r, Color(0.02, 0.03, 0.08, 0.6), 12 * u)
		_pill(r.grow(-4 * u), base, 10 * u)
		draw_string(Game.font_bold, r.position + Vector2(8 * u, 22 * u), names[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * u), Color(1, 1, 1, 0.8))
		_txt(names[i][2], Vector2(r.position.x, r.position.y + 54 * u), int(22 * u if i == 0 else 24 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _gauge(u: float, w: float, h: float, k: Dictionary) -> void:
	var gw := 320.0 * u
	var gh := 22.0 * u
	var gx := w * 0.5 - gw * 0.5
	var gy := h - 48.0 * u
	_pill(Rect2(gx - 4 * u, gy - 4 * u, gw + 8 * u, gh + 8 * u), Color(0.04, 0.05, 0.1, 0.8), 8 * u)
	var g := clampf(float(k.gauge), 0.0, 1.0)
	draw_rect(Rect2(gx, gy, gw * g, gh), Color(0.35, 0.8, 1.0).lerp(Color(1.0, 0.85, 0.25), g))
	_txt("게이지", Vector2(gx, gy - 8 * u), int(16 * u), Color(0.9, 0.95, 1.0))
	for i in Rules.MAX_BOOSTS:
		var r := Rect2(gx + gw + 14 * u + i * 52 * u, gy - 14 * u, 44 * u, 44 * u)
		_pill(r, Color(0.04, 0.05, 0.1, 0.8), 10 * u)
		if i < int(k.boosts):
			_pill(r.grow(-5 * u), Color(1.0, 0.55, 0.2), 8 * u)
			_txt("B", Vector2(r.position.x, r.position.y + 32 * u), int(24 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_txt("Space 부스터", Vector2(gx + gw + 14 * u, gy + gh + 22 * u), int(14 * u), Color(0.85, 0.9, 1.0, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, false)

func _items_ui(u: float, w: float, h: float, k: Dictionary) -> void:
	var its: Array = k.get("items", [])
	var x := w * 0.5 - 70 * u
	var y := h - 92 * u
	for i in Rules.MAX_ITEMS:
		var r := Rect2(x + i * 76 * u, y, 68 * u, 68 * u)
		_pill(r, Color(0.04, 0.05, 0.1, 0.8), 12 * u)
		if i < its.size():
			_pill(r.grow(-5 * u), Color(0.3, 0.6, 1.0) if i == 0 else Color(0.3, 0.45, 0.7), 10 * u)
			_txt(Rules.ITEM_NAMES.get(its[i], "?"), Vector2(r.position.x, r.position.y + 42 * u), int(15 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_txt("Space 아이템", Vector2(x, y - 8 * u), int(16 * u), Color(0.9, 0.95, 1.0))

func _minimap(r: Rect2) -> void:
	var trk: Dictionary = race.trk
	if map_pts.is_empty() or map_rect != r:
		map_rect = r
		var b := Rect2(trk.pts[0], Vector2.ZERO)
		for p in trk.pts:
			b = b.expand(p)
		var sc := minf(r.size.x / b.size.x, r.size.y / b.size.y) * 0.9
		var off := r.position + (r.size - b.size * sc) * 0.5
		map_pts = PackedVector2Array()
		for i in range(0, trk.n, 2):
			map_pts.append(off + ((trk.pts[i] as Vector2) - b.position) * sc)
		map_pts.append(map_pts[0])
		set_meta("b", b)
		set_meta("sc", sc)
		set_meta("off", off)
	_pill(r, Color(0.05, 0.08, 0.15, 0.45), 14)
	draw_polyline(map_pts, Color(0.1, 0.1, 0.15, 0.8), 7.0)
	draw_polyline(map_pts, Color(0.95, 0.85, 0.75), 4.0)
	var b2: Rect2 = get_meta("b")
	var sc2: float = get_meta("sc")
	var off2: Vector2 = get_meta("off")
	for o in race.racers:
		var p: Vector2 = off2 + ((o.k.pos as Vector2) - b2.position) * sc2
		var me: bool = o == racer
		draw_circle(p, 6.0 if me else 4.0, Color(0.1, 0.1, 0.1))
		draw_circle(p, 4.5 if me else 3.0, Color(1, 0.85, 0.2) if me else (o.color as Color))
