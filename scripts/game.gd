extends Node
## 저장·보드 목록·트랙 목록·지금 고른 경주 설정 (자동 로드 Game)

const SAVE_PATH := "user://board_racing_save.json"

var boards: Array = []
var riders: Array = []
var tracks: Array = []
var save: Dictionary = {}
var font: Font
var font_bold: Font

## 다음 경주 설정
var mode := "race"        # race(개인전) / team(팀전) / time(혼자 타임어택) / online(친구와 온라인)
var track_id := "sprout_hill"
var items := false        # 아이템전 (아니면 스피드전)
var last_result: Dictionary = {}
var online_setup: Dictionary = {}   ## 온라인 경주 설정 (방장이 만들어 보냄)

func _ready() -> void:
	var bj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boards.json"))
	boards = bj.boards
	riders = bj.riders
	tracks = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks.json")).tracks
	font = load("res://assets/fonts/Galmuri11.ttf")
	font_bold = load("res://assets/fonts/Galmuri11-Bold.ttf")
	load_save()
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 20
	get_tree().root.theme = th

func board_ids() -> Array:
	return boards.map(func(b): return b.id)

func board_def(id: String) -> Dictionary:
	for b in boards:
		if b.id == id:
			return b
	return boards[0]

func rider_def(id: String) -> Dictionary:
	for r in riders:
		if r.id == id:
			return r
	return riders[0]

func track_def(id: String) -> Dictionary:
	for t in tracks:
		if t.id == id:
			return t
	return tracks[0]

func level() -> int:
	return int(Rules.level_info(int(save.exp)).level)

func load_save() -> void:
	var raw: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		raw = FileAccess.get_file_as_string(SAVE_PATH)
	save = Rules.parse_save(raw, board_ids())

func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
		f.close()

func try_buy(id: String) -> bool:
	var b := board_def(id)
	if not Rules.can_buy(save, b):
		return false
	save = Rules.buy(save, b)
	write_save()
	_gear_changed()
	return true

func choose_board(id: String) -> void:
	if id in save.owned:
		save.board = id
		write_save()
		_gear_changed()

func choose_rider(id: String) -> void:
	if id in Rules.RIDERS:
		save.rider = id
		write_save()
		_gear_changed()

func set_name_text(t: String) -> void:
	var n := Rules.clean_name(t)
	if n != "":
		save.name = n
		write_save()

func _gear_changed() -> void:
	if Net.role in ["host", "guest"]:
		Net.my_gear_changed()

func best_of(track: String) -> float:
	return float(save.best.get(track, -1.0))

## 아직 없는 희귀 보드
func rare_missing() -> Array:
	var out := []
	for b in boards:
		if b.get("rare", false) and not (b.id in save.owned):
			out.append(b.id)
	return out

## 경주 끝: 돈·경험치·기록·행운 상자를 저장하고 결과에 적어 넣는다
func finish_race(result: Dictionary) -> void:
	last_result = result
	var p: Dictionary = result.players[0] if result.players.size() > 0 else {}
	if p.is_empty():
		return
	var lv_before := level()
	var coins := int(p.reward) + int(p.coins)
	if result.mode == "time" and float(p.time) > 0.0:
		var t: float = p.time
		var b := best_of(result.track)
		if b <= 0.0 or t < b:
			save.best[result.track] = t
		var old := str(save.medals.get(result.track, ""))
		var med := Rules.medal(t, float(Game.track_def(result.track).get("par", 0.0)))
		coins += Rules.time_reward(old, med, b <= 0.0)
		if Rules.MEDAL_RANK[med] > Rules.MEDAL_RANK[old]:
			save.medals[result.track] = med
		result.medal = med
	if result.get("team_win", false):
		coins += 30
	# 행운 상자
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var luck := Rules.lucky_roll(rng.randf(), rng.randf(), rare_missing(), int(p.place))
	match str(luck.kind):
		"board":
			save.owned.append(luck.board)
		"lucky":
			coins *= int(luck.amount)
		_:
			coins += int(luck.amount)
	result.luck = luck
	var xp := Rules.exp_gain(int(p.place), int(result.racers), int(p.points), str(result.mode))
	save.exp = int(save.exp) + xp
	save.coins = int(save.coins) + coins
	save.races = int(save.races) + 1
	if int(p.place) == 1 and int(result.racers) > 1:
		save.wins = int(save.wins) + 1
	result.total = coins
	result.exp = xp
	result.level_up = level() > lv_before
	write_save()
