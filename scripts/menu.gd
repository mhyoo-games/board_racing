extends Control
## 처음 화면·트랙 고르기·보드 상점·캐릭터·결과·조작 방법·친구와 온라인

var bg: Node3D
var screen := "title"
var shop_pick := ""
var _luck_t := 0.0
var _luck_label: Label
var _luck_text := ""

const MODE_TITLES := {"race": "개인전 — 컴퓨터 7명과", "team": "팀전 — 4 대 4 (빨강팀 · 파랑팀)", "time": "타임어택 — 메달 따기"}
const MEDAL_TEXT := {"gold": "금메달", "silver": "은메달", "bronze": "동메달", "": "메달 없음"}
const MEDAL_COLOR := {"gold": Color(1.0, 0.85, 0.25), "silver": Color(0.85, 0.9, 0.95), "bronze": Color(0.9, 0.6, 0.35), "": Color(0.7, 0.75, 0.85)}
const STAT_NAMES := {"speed": "최고 속도", "accel": "가속", "handling": "핸들링", "jump": "점프", "trick": "묘기·게이지", "boost": "부스터"}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("title")

func show_screen(s: String) -> void:
	screen = s
	for c in get_children():
		c.queue_free()
	_luck_label = null
	if bg:
		bg.frame(s in ["shop", "riders"])
		var bid: String = Game.save.board if shop_pick == "" or s != "shop" else shop_pick
		bg.show_board(bid, "" if s == "shop" else Game.save.rider)
	match s:
		"title": _title()
		"tracks": _tracks()
		"online": _online()
		"shop": _shop()
		"riders": _riders()
		"results": _results()
		"help": _help()

func _pin(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_BOTTOM_RIGHT else Control.GROW_DIRECTION_END

## 오른쪽 위: 이름·레벨·경험치·코인
func _profile() -> void:
	var p := UI.panel(Color(0.06, 0.14, 0.34, 0.82))
	_pin(p, Control.PRESET_TOP_RIGHT, -360, 16, -20, 120)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	p.add_child(col)
	var li := Rules.level_info(int(Game.save.exp))
	var top := HBoxContainer.new()
	top.add_child(UI.label("Lv.%d" % int(li.level), 26, UI.GOLD, true))
	var nm := UI.label("  " + str(Game.save.name), 24, UI.CREAM, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(UI.label("● %d" % int(Game.save.coins), 24, UI.GOLD, true))
	col.add_child(top)
	var bar := StatBar.new()
	bar.value = float(li.into) / maxf(1.0, float(li.need))
	bar.custom_minimum_size = Vector2(300, 14)
	col.add_child(bar)
	col.add_child(UI.label("경험치 %d / %d" % [int(li.into), int(li.need)], 15, Color(0.85, 0.92, 1.0)))
	add_child(p)

func _column(x := 60.0, y := 0.0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.position = Vector2(x, y)
	add_child(v)
	return v

func _focus_first(v: Control) -> void:
	for c in v.find_children("*", "Button", true, false):
		if not (c as Button).disabled:
			(c as Button).call_deferred("grab_focus")
			return

func _main() -> Node:
	return get_tree().get_first_node_in_group("main")

# ───────── 처음 화면

func _title() -> void:
	_profile()
	var v := _column(64, 26)
	v.add_theme_constant_override("separation", 8)
	v.add_child(UI.label("바람보드 레이싱", 78, Color(1.0, 0.95, 0.55), true))
	v.add_child(UI.label("점프하고, 묘기 부리고, 하늘을 달려요!", 24, UI.CREAM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	v.add_child(UI.button("개인전", func(): _pick_mode("race"), 340))
	v.add_child(UI.button("팀전 (4 대 4)", func(): _pick_mode("team"), 340))
	v.add_child(UI.button("타임어택 (메달)", func(): _pick_mode("time"), 340))
	v.add_child(UI.button("친구와 온라인 (최대 8명)", func(): Game.mode = "online"; show_screen("online"), 340))
	v.add_child(UI.button("보드 상점", func(): shop_pick = ""; show_screen("shop"), 340))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UI.button("캐릭터", func(): show_screen("riders"), 165, 24))
	row.add_child(UI.button("조작 방법", func(): show_screen("help"), 165, 24))
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	var snd := UI.button("소리: " + ("끔" if Sound.muted else "켬"), func(): pass, 165, 22)
	snd.custom_minimum_size.y = 46
	snd.pressed.connect(func():
		Sound.set_muted(not Sound.muted)
		snd.text = "소리: " + ("끔" if Sound.muted else "켬"))
	row2.add_child(snd)
	var lic := UI.button("라이선스", _licenses, 165, 22)
	lic.custom_minimum_size.y = 46
	row2.add_child(lic)
	v.add_child(row2)
	var b := Game.board_def(Game.save.board)
	var info := UI.label("타는 보드: " + b.name + "   ·   " + Game.rider_def(Game.save.rider).name, 24, UI.CREAM, true)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(info)
	_pin(info, Control.PRESET_BOTTOM_RIGHT, -560, -64, -30, -26)
	_focus_first(v)

## 만든 것들·라이선스 (Godot 엔진·글꼴·그림)
func _licenses() -> void:
	var l: Control = preload("res://scripts/licenses.gd").new()
	l.credits = [
		"바람보드 레이싱 — 유민혁 (minhyuk94)",
		"게임 엔진: Godot Engine (MIT 라이선스) — godotengine.org/license",
		"캐릭터·나무·동전 등: Kenney Platformer Kit (CC0 1.0) — kenney.nl",
		"글꼴: 갈무리 Galmuri (SIL Open Font License 1.1) — github.com/quiple/galmuri",
		"효과음·곡·보드·길·점프대: 코드로 새로 만듦",
		"친구와 온라인: 처음 연결 정보만 공개 메시지 중계 ntfy.sh를 거침",
	]
	l.font_size = 18
	l.closed.connect(func(): _focus_first(self))
	add_child(l)

func _pick_mode(m: String) -> void:
	Game.mode = m
	show_screen("tracks")

# ───────── 트랙 고르기

func _tracks() -> void:
	_profile()
	var v := _column(44, 22)
	v.add_theme_constant_override("separation", 10)
	v.add_child(UI.label(MODE_TITLES.get(Game.mode, ""), 34, Color(1.0, 0.95, 0.55), true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1190, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(grid)
	var first: Button = null
	for t in Game.tracks:
		var p := UI.panel()
		p.custom_minimum_size = Vector2(380, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		p.add_child(col)
		var head := HBoxContainer.new()
		head.add_child(UI.label(t.name, 24, UI.CREAM, true))
		head.add_child(UI.label("  " + "★".repeat(int(t.level)) + "  %d바퀴" % int(t.laps), 16, UI.GOLD))
		col.add_child(head)
		var map := TrackMap.new()
		map.def = t
		map.custom_minimum_size = Vector2(330, 92)
		col.add_child(map)
		var d := UI.label(str(t.get("about", "")), 15, Color(0.9, 0.95, 1.0))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(330, 40)
		col.add_child(d)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if Game.mode == "time":
			var med := str(Game.save.medals.get(t.id, ""))
			var info := UI.label("%s  %s" % [MEDAL_TEXT[med], Rules.time_text(Game.best_of(t.id))], 16, MEDAL_COLOR[med], true)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
		else:
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sp)
		var go := UI.button("달리기", func(): _go(t.id), 130, 20)
		go.custom_minimum_size.y = 42
		row.add_child(go)
		col.add_child(row)
		if first == null:
			first = go
		grid.add_child(p)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	bottom.add_child(UI.button("← 뒤로", func(): show_screen("title"), 180))
	if Game.mode in ["race", "team"]:
		var ib := UI.button("", func(): pass, 300)
		var upd := func(): ib.text = "경기 방식: " + ("아이템전" if Game.items else "스피드전")
		upd.call()
		ib.pressed.connect(func():
			Game.items = not Game.items
			upd.call())
		bottom.add_child(ib)
	bottom.add_child(UI.button("보드 바꾸기", func(): shop_pick = ""; show_screen("shop"), 220))
	if first:
		first.call_deferred("grab_focus")

func _go(id: String) -> void:
	Game.track_id = id
	_main().start_race()

# ───────── 보드 상점

func _shop() -> void:
	_profile()
	var cur: String = Game.save.board
	if shop_pick == "":
		shop_pick = cur
	bg.show_board(shop_pick, "")
	var v := _column(44, 24)
	v.add_theme_constant_override("separation", 8)
	v.add_child(UI.label("보드 상점", 42, Color(1.0, 0.95, 0.55), true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(380, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var first: Button = null
	var lv := Game.level()
	for b in Game.boards:
		var owned: bool = b.id in Game.save.owned
		var tag := ""
		if b.id == cur:
			tag = "  ★ 타는 중"
		elif owned:
			tag = "  가짐"
		elif b.get("rare", false):
			tag = "  행운 상자"
		elif lv < int(b.level):
			tag = "  Lv.%d부터" % int(b.level)
		else:
			tag = "  ● %d" % int(b.price)
		var btn := UI.button(b.name + tag, func(): shop_pick = b.id; show_screen("shop"), 350, 21)
		btn.custom_minimum_size.y = 44
		if b.id == shop_pick:
			btn.add_theme_stylebox_override("normal", UI.box(Color(1.0, 0.92, 0.6), 18, UI.SKY, 4))
			first = btn
		list.add_child(btn)
	var b2 := Game.board_def(shop_pick)
	var p := UI.panel()
	p.custom_minimum_size = Vector2(470, 0)
	add_child(p)
	_pin(p, Control.PRESET_BOTTOM_RIGHT, -480, -400, -20, -16)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	p.add_child(col)
	var head := HBoxContainer.new()
	head.add_child(UI.label(b2.name, 34, UI.CREAM, true))
	if b2.get("rare", false):
		head.add_child(UI.label("  희귀", 22, Color(1.0, 0.6, 0.9), true))
	col.add_child(head)
	var d := UI.label(str(b2.about), 18, Color(0.9, 0.95, 1.0))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(420, 0)
	col.add_child(d)
	for s in STAT_NAMES:
		var r := HBoxContainer.new()
		var l := UI.label(STAT_NAMES[s], 19, UI.CREAM)
		l.custom_minimum_size = Vector2(120, 0)
		r.add_child(l)
		var bar := StatBar.new()
		bar.value = float(b2.stats[s]) / 10.0
		bar.custom_minimum_size = Vector2(290, 20)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(bar)
		col.add_child(r)
	var owned2: bool = b2.id in Game.save.owned
	var act: Button
	if owned2:
		act = UI.button("이 보드 타기" if b2.id != cur else "타는 중", func():
			Game.choose_board(b2.id)
			show_screen("shop"), 420)
		act.disabled = b2.id == cur
	elif b2.get("rare", false):
		act = UI.button("경주 뒤 행운 상자에서만 나와요", func(): pass, 420, 20)
		act.disabled = true
	elif lv < int(b2.level):
		act = UI.button("레벨 %d이 되면 살 수 있어요" % int(b2.level), func(): pass, 420, 20)
		act.disabled = true
	else:
		act = UI.button("사기  ● %d" % int(b2.price), func():
			if Game.try_buy(b2.id):
				Sound.play("buy")
				show_screen("shop")
			else:
				Sound.play("nope"), 420)
		if int(Game.save.coins) < int(b2.price):
			act.text = "코인이 모자라요 (● %d)" % int(b2.price)
			act.disabled = true
	col.add_child(act)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(UI.button("← 뒤로", func(): show_screen("online" if Game.mode == "online" and Net.role != "" else "title"), 160))
	bottom.add_child(UI.button("캐릭터", func(): show_screen("riders"), 160))
	if first:
		first.call_deferred("grab_focus")

# ───────── 캐릭터·이름

func _riders() -> void:
	_profile()
	var v := _column(44, 24)
	v.add_child(UI.label("캐릭터 고르기", 42, Color(1.0, 0.95, 0.55), true))
	var first: Button = null
	for r in Game.riders:
		var mine: bool = r.id == Game.save.rider
		var b := UI.button(r.name + ("  ★" if mine else ""), func():
			Game.choose_rider(r.id)
			bg.show_board(Game.save.board, r.id)
			show_screen("riders"), 300)
		b.add_theme_color_override("font_color", Color.from_string(r.color, UI.INK).darkened(0.35))
		if mine:
			b.add_theme_stylebox_override("normal", UI.box(Color(1.0, 0.92, 0.6), 18, UI.SKY, 4))
			first = b
		v.add_child(b)
	v.add_child(UI.label("이름 (8글자까지)", 22, UI.CREAM, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var le := LineEdit.new()
	le.text = str(Game.save.name)
	le.max_length = 8
	le.custom_minimum_size = Vector2(220, 52)
	le.add_theme_font_size_override("font_size", 24)
	le.add_theme_stylebox_override("normal", UI.box(Color(1, 1, 1, 0.95), 14, UI.SKY, 3))
	le.add_theme_color_override("font_color", UI.INK)
	row.add_child(le)
	row.add_child(UI.button("바꾸기", func():
		Game.set_name_text(le.text)
		Sound.play("gain")
		show_screen("riders"), 140, 22))
	v.add_child(row)
	v.add_child(UI.button("← 뒤로", func(): show_screen("title"), 200))
	if first:
		first.call_deferred("grab_focus")

# ───────── 결과

func _results() -> void:
	var r: Dictionary = Game.last_result
	if r.is_empty():
		show_screen("title")
		return
	_profile()
	var v := _column(44, 18)
	v.add_theme_constant_override("separation", 8)
	var title: String = r.track_name + " — 결과"
	if r.get("items", false):
		title += " (아이템전)"
	v.add_child(UI.label(title, 38, Color(1.0, 0.95, 0.55), true))
	if r.has("team_scores"):
		var ts: Array = r.team_scores
		var win := "무승부!" if ts[0] == ts[1] else ("빨강팀 승리!" if ts[0] > ts[1] else "파랑팀 승리!")
		v.add_child(UI.label("빨강팀 %d점 : 파랑팀 %d점   %s" % [ts[0], ts[1], win], 28, Color(1.0, 0.75, 0.5) if r.get("team_win", false) else UI.CREAM, true))
	var p := UI.panel()
	v.add_child(p)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 2)
	p.add_child(grid)
	for h in ["순위", "이름", "보드", "시간"]:
		grid.add_child(UI.label(h, 19, Color(0.8, 0.9, 1.0), true))
	for row in r.table:
		var c: Color = Color(1.0, 0.9, 0.35) if row.human else UI.CREAM
		if int(row.get("team", -1)) >= 0 and not row.human:
			c = [Color(1.0, 0.65, 0.65), Color(0.65, 0.8, 1.0)][int(row.team)]
		grid.add_child(UI.label("%d" % row.place, 22, c, row.human))
		grid.add_child(UI.label(row.name, 22, c, row.human))
		grid.add_child(UI.label(row.board, 20, c))
		grid.add_child(UI.label(Rules.time_text(row.time), 20, c))
	var pl: Dictionary = r.players[0]
	var txt := "%s  %s" % [pl.name, ("%d등" % pl.place) if r.racers > 1 else Rules.time_text(pl.time)]
	txt += "   보상 ● %d   주운 코인 ● %d" % [pl.reward, pl.coins]
	if r.get("team_win", false):
		txt += "   팀 승리 ● 30"
	v.add_child(UI.label(txt, 24, UI.GOLD, true))
	var best := int(pl.get("best_judge", -1))
	v.add_child(UI.label("묘기 %d번 · 점수 %d%s   경험치 +%d%s" % [int(pl.tricks), int(pl.points), ("  (최고 " + Rules.JUDGES[best] + ")") if best >= 0 else "", int(r.get("exp", 0)), "   레벨 업!" if r.get("level_up", false) else ""], 21, Color(0.8, 0.95, 1.0), true))
	if r.mode == "time":
		var med := str(r.get("medal", ""))
		v.add_child(UI.label("%s   최고 기록 %s" % [MEDAL_TEXT[med], Rules.time_text(Game.best_of(r.track))], 24, MEDAL_COLOR[med], true))
	# 행운 상자: 잠깐 뒤에 열린다
	var luck: Dictionary = r.get("luck", {})
	_luck_text = ""
	match str(luck.get("kind", "")):
		"board": _luck_text = "행운 상자: 희귀 보드 ‘%s’ 를 얻었어요!!" % Game.board_def(str(luck.board)).name
		"lucky": _luck_text = "행운 상자: 대박! 받은 코인 %d배!  (모두 ● %d)" % [int(luck.amount), int(r.get("total", 0))]
		"pouch": _luck_text = "행운 상자: 코인 주머니 ● %d" % int(luck.amount)
		"coins": _luck_text = "행운 상자: 코인 ● %d" % int(luck.amount)
	_luck_label = UI.label("행운 상자를 여는 중…", 26, Color(1.0, 0.75, 0.95), true)
	v.add_child(_luck_label)
	_luck_t = 1.2
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	v.add_child(row2)
	if r.mode == "online":
		row2.add_child(UI.button("대기실로", func(): show_screen("online"), 220))
	else:
		row2.add_child(UI.button("다시 달리기", func(): _main().start_race(), 220))
		row2.add_child(UI.button("다른 트랙", func(): show_screen("tracks"), 190))
	row2.add_child(UI.button("보드 상점", func(): shop_pick = ""; show_screen("shop"), 190))
	row2.add_child(UI.button("처음 화면", func(): show_screen("title"), 180))
	_focus_first(row2)
	if r.get("level_up", false):
		Sound.play("levelup")

func _process(dt: float) -> void:
	if _luck_label and _luck_t > 0.0:
		_luck_t -= dt
		if _luck_t <= 0.0:
			_luck_label.text = _luck_text
			Sound.play("lucky")
			if _luck_text.find("희귀") >= 0 or _luck_text.find("대박") >= 0:
				_luck_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))

# ───────── 조작 방법

func _help() -> void:
	var v := _column(54, 18)
	v.add_child(UI.label("조작 방법", 40, Color(1.0, 0.95, 0.55), true))
	var p := UI.panel()
	v.add_child(p)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1140, 500)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var lines := [
		["달리기", "↑ 가속 / ↓ 브레이크 / ← → 방향 / Shift 슬라이드(급회전) / Space·Ctrl 부스터"],
		["A 점프", "땅에서 누르면 폴짝. 점프대(나무 오르막) 위에서 누르면 높이 날아요. 끝(노란 칸)에 가까울수록 GOOD → NICE → EXCELLENT, 더 높이 뛰어요"],
		["S · D · F 묘기", "공중에서 S 그랩(GB), D 360(한 바퀴), F 720(두 바퀴). 땅에 닿기 전에 끝나야 성공! 못 끝내면 MISS로 비틀거려요"],
		["묘기 커맨드", "공중에서 방향키를 먼저 누르고 S·D·F: ↑S 앞잡기 · ↓S 뒤잡기 · ←→S 날개 펴기 / ↑D 앞구르기 · ↓D 뒤구르기 · ←→D 꽈배기 / ↑F 두 바퀴 앞구르기 · ↓F 두 바퀴 뒤구르기 · ←→F 1080 · ↓↑F 회오리. 커맨드 묘기가 점수가 더 커요"],
		["판정", "묘기가 끝나고 바로 땅에 닿을수록(아슬아슬할수록) 좋은 판정: GOOD < NICE < EXCELLENT. 화면 아래 줄이 ‘땅까지 남은 시간’이에요"],
		["이어 하기", "묘기 중에 다음 묘기를 눌러 두면 끊김 없이 이어져요. 한 번 점프에 많이 이을수록 점수가 크게 늘어요(2연속 ×1.25, 3연속 ×1.5 …). 큰 점프대·스프링 발판이면 오래 떠 있어요"],
		["점프대 · 스프링 · 고리", "작은 점프대는 짧게, 큰 점프대(빨강·하양)는 높이 떠요. 파란 스프링 발판은 밟기만 해도 튕겨 올라요. 공중의 고리를 지나가면 게이지가 차요"],
		["게이지·부스터", "묘기·점프 판정·슬라이드로 게이지가 차요. 가득 차면 부스터 +1 (두 개까지). EXCELLENT로 착지하면 살짝 빨라져요"],
		["계단·얼음", "계단은 덜컹덜컹 느려요 — 점프로 넘으세요. 얼음은 미끄러워요"],
		["부스터 발판", "길 위 반짝이는 주황 화살표를 지나면 빨라져요"],
		["낭떠러지", "구름 섬에서는 점프대 끝에서 뛰어 건너요. 떨어지면 조금 뒤에서 다시 출발"],
		["출발 부스터", "출발 신호 ‘1’이 꺼지기 직전에 ↑를 누르면 빨리 튀어 나가요"],
		["팀전", "4 대 4. 들어온 순위대로 점수(1등 10점 … 8등 1점)를 모아 많은 팀이 이겨요"],
		["아이템전", "? 상자를 지나면 아이템(두 칸), Space로 써요: 부스터·물풍선(앞으로)·끈끈이(뒤에)·먹구름(바로 앞 사람)·비눗방울(한 번 막음)·쿵쿵(앞의 모두를 흔듦, 공중이면 피함)"],
		["레벨·상점", "경주하면 경험치와 코인. 레벨이 오르면 더 좋은 보드를 살 수 있어요. 희귀 보드는 경주 뒤 행운 상자에서만!"],
		["게임패드", "스틱 방향 / RT 가속 / LT 브레이크 / RB 슬라이드 / LB 부스터 / A 점프 / X GB / Y 360 / B 720"],
		["휴대폰", "◀ ▶ 방향, 점프·GB·360·720·부스터·슬라이드 버튼 (가속은 저절로)"],
		["멈춤", "Esc 또는 P"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	for l in lines:
		grid.add_child(UI.label(l[0], 19, UI.GOLD, true))
		var d := UI.label(l[1], 18, UI.CREAM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(920, 0)
		grid.add_child(d)
	var back := UI.button("← 뒤로", func(): show_screen("title"), 200)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	back.call_deferred("grab_focus")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and screen != "title" and screen != "online":
		show_screen("title")
		get_viewport().set_input_as_handled()

# ───────── 친구와 온라인

var _box_in: CodeBox
var _online_track := ""
var _online_bots := true
var _online_teams := false

func _ready_online() -> void:
	if not Net.changed.is_connected(_net_changed):
		Net.changed.connect(_net_changed)

func _net_changed() -> void:
	if screen == "online" and is_inside_tree():
		show_screen("online")

func _online() -> void:
	_ready_online()
	_profile()
	var v := _column(54, 30)
	v.add_theme_constant_override("separation", 12)
	v.add_child(UI.label("친구와 온라인", 44, Color(1.0, 0.95, 0.55), true))
	var p := UI.panel()
	p.custom_minimum_size = Vector2(900, 0)
	v.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)
	var say := func(t: String, c := UI.CREAM, size := 22) -> Label:
		var l := UI.label(t, size, c)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(840, 0)
		col.add_child(l)
		return l
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var add_box := func(readonly: bool, ph: String) -> CodeBox:
		var b := CodeBox.new()
		b.readonly = readonly
		b.placeholder = ph
		b.custom_minimum_size = Vector2(840, 120)
		col.add_child(b)
		return b
	var st := Net.status
	if Net.error_text != "":
		say.call(Net.error_text, Color(1.0, 0.6, 0.5))
	if st in ["idle", "error", "closed"] and Net.role == "":
		say.call("방장이 방을 만들면 6자리 방 코드가 나와요. 친구들에게 그 코드만 알려 주면 돼요. 방장 포함 8명까지! (연결 정보는 공개 중계 ntfy.sh를 거쳐 자동으로 주고받아요)")
		if st == "closed":
			say.call("친구와 연결이 끊겼어요.", Color(1.0, 0.6, 0.5))
		row.add_child(UI.button("방 만들기", func(): Net.host_room(), 260))
		row.add_child(UI.button("방 들어가기", func(): Net.error_text = ""; Net.role = "join"; show_screen("online"), 260))
		col.add_child(row)
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 12)
		r2.add_child(UI.button("긴 코드로 방 만들기", func(): Net.host(), 300, 20))
		r2.add_child(UI.button("긴 코드로 들어가기", func(): Net.error_text = ""; Net.role = "longjoin"; show_screen("online"), 300, 20))
		say.call("방 코드가 안 될 때(막힌 네트워크)는 긴 코드를 메신저로 주고받아 둘이 연결할 수 있어요.", Color(0.85, 0.9, 1.0), 18)
		col.add_child(r2)
	elif Net.role == "join":
		say.call("방장에게 받은 6자리 방 코드를 넣으세요.")
		_box_in = add_box.call(false, "예: K7MP2Q")
		_box_in.custom_minimum_size = Vector2(320, 64)
		row.add_child(UI.button("붙여넣기", func(): _box_in.paste(), 180))
		row.add_child(UI.button("들어가기", func(): Net.join_room(_box_in.get_text()), 200))
		col.add_child(row)
		_box_in.call_deferred("focus")
	elif Net.role == "longjoin":
		say.call("① 친구에게 받은 긴 초대 코드를 아래에 붙여 넣으세요.")
		_box_in = add_box.call(false, "BR1- 로 시작하는 초대 코드")
		row.add_child(UI.button("붙여넣기", func(): _box_in.paste(), 180))
		row.add_child(UI.button("확인", func():
			if not Net.join(_box_in.get_text()):
				Net.role = "longjoin"
				show_screen("online"), 180))
		col.add_child(row)
	elif st == "room" and Net.role == "host":
		Net.locked = false
		if Net.mode == "room":
			var top := HBoxContainer.new()
			top.add_theme_constant_override("separation", 18)
			top.add_child(UI.label("방 코드", 26, UI.CREAM))
			top.add_child(UI.label(Net.room, 64, UI.GOLD, true))
			var copybox: CodeBox = CodeBox.new()
			copybox.readonly = true
			copybox.custom_minimum_size = Vector2(1, 1)
			copybox.modulate.a = 0.0
			top.add_child(copybox)
			copybox.set_text(Net.room)
			var cb := UI.button("복사", func(): copybox.copy(), 120, 20)
			cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(cb)
			col.add_child(top)
			say.call("친구들(최대 %d명)에게 이 코드를 알려 주세요. 넣으면 저절로 들어와요." % (Net.MAX_PLAYERS - 1), Color(0.85, 0.9, 1.0), 18)
		_roster_list(say)
		_host_controls(col)
	elif st == "finding":
		say.call("방 %s 을(를) 찾는 중이에요…" % Net.room)
	elif st == "connecting" and Net.mode == "room":
		say.call("방장에게 연결하는 중이에요…")
	elif st == "making":
		say.call("연결 코드를 만드는 중이에요…")
	elif st == "code" and Net.role == "host":
		say.call("① 이 초대 코드를 복사해서 친구에게 보내세요.")
		var mine: CodeBox = add_box.call(true, "")
		mine.custom_minimum_size.y = 90
		mine.set_text(Net.my_code)
		var r1 := HBoxContainer.new()
		r1.add_child(UI.button("초대 코드 복사", func(): mine.copy(), 260))
		col.add_child(r1)
		say.call("② 친구가 보낸 답장 코드를 붙여 넣고 ‘연결’을 누르세요.")
		_box_in = add_box.call(false, "BR1- 로 시작하는 답장 코드")
		_box_in.custom_minimum_size.y = 90
		row.add_child(UI.button("붙여넣기", func(): _box_in.paste(), 180))
		row.add_child(UI.button("연결", func(): Net.accept(_box_in.get_text()), 180))
		col.add_child(row)
	elif st == "connecting" and Net.role == "guest" and Net.my_code != "":
		say.call("② 이 답장 코드를 복사해서 방장에게 보내세요. 방장이 넣으면 연결돼요.")
		var mine2: CodeBox = add_box.call(true, "")
		mine2.set_text(Net.my_code)
		row.add_child(UI.button("답장 코드 복사", func(): mine2.copy(), 260))
		col.add_child(row)
		say.call("연결을 기다리는 중…", Color(0.8, 0.9, 1.0))
	elif st == "connecting":
		say.call("연결하는 중이에요…")
	elif st == "connected":
		say.call("들어왔어요! 방 %s" % Net.room if Net.room != "" else "연결됐어요!", Color(0.6, 1.0, 0.6), 28)
		_roster_list(say)
		say.call("방장이 트랙을 고르고 출발하면 바로 시작해요.", Color(0.8, 0.9, 1.0))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(UI.button("← 처음 화면", func():
		if not Net.connected():
			Net.reset()
		show_screen("title"), 220))
	if st == "connected" or (st == "room" and Net.role == "host"):
		bottom.add_child(UI.button("보드 바꾸기", func(): shop_pick = ""; show_screen("shop"), 220))
	if Net.role != "":
		bottom.add_child(UI.button("연결 끊고 처음부터", func(): Net.reset(); show_screen("online"), 280))
	if not OS.has_feature("web") and not Net.available():
		say.call("(PC판에서는 온라인 연결이 안 돼요. 웹에서 해 주세요.)", Color(1.0, 0.7, 0.5), 18)
	_focus_first(col)

func _roster_list(say: Callable) -> void:
	var list: Array = Net.roster.duplicate()
	list.sort_custom(func(x, y): return int(x.pid) < int(y.pid))
	say.call("참가자 %d / %d" % [list.size(), Net.MAX_PLAYERS], UI.GOLD, 20)
	var names := []
	for e in list:
		names.append("%s%s · %s" % [e.name, " (나)" if int(e.pid) == Net.my_pid else "", Game.board_def(str(e.get("board", Rules.START_BOARD))).name])
	say.call("   ".join(names), UI.CREAM, 19)

func _host_controls(col: VBoxContainer) -> void:
	if _online_track == "":
		_online_track = Game.tracks[0].id
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for t in Game.tracks:
		var b := UI.button(("★ " if t.id == _online_track else "") + t.name, func(): _online_track = t.id; show_screen("online"), 270, 19)
		b.custom_minimum_size.y = 42
		grid.add_child(b)
	col.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var n := Net.roster.size()
	row.add_child(UI.button("빈자리 컴퓨터: " + ("채움" if _online_bots else "없음"), func(): _online_bots = not _online_bots; show_screen("online"), 280, 20))
	row.add_child(UI.button("팀전: " + ("켬" if _online_teams else "끔"), func(): _online_teams = not _online_teams; show_screen("online"), 170, 20))
	var go := UI.button("출발!" if n >= 2 else "친구를 기다리는 중", _online_go, 250)
	go.disabled = n < 2
	row.add_child(go)
	col.add_child(row)

func _online_go() -> void:
	if Net.roster.size() < 2:
		return
	var r := RandomNumberGenerator.new()
	r.randomize()
	var def := Game.track_def(_online_track)
	var players: Array = []
	for e in Net.roster:
		var bid := str(e.get("board", Rules.START_BOARD))
		players.append({"pid": int(e.pid), "board": bid if bid in Game.board_ids() else Rules.START_BOARD, "rider": str(e.get("rider", "oobi")), "name": str(e.name)})
	players.sort_custom(func(x, y): return int(x.pid) < int(y.pid))
	var setup := {
		"track": _online_track, "players": players, "teams": _online_teams,
		"ai": bake_ai(Net.MAX_PLAYERS - players.size() if _online_bots else 0, int(def.level), r),
	}
	Game.online_setup = setup
	Game.mode = "online"
	Game.track_id = _online_track
	Net.locked = true
	Net.send({"y": "go", "setup": setup})
	_main().start_race()

func bake_ai(n: int, level: int, r: RandomNumberGenerator) -> Array:
	return preload("res://scripts/race.gd").make_ai_specs(n, level, r)
