extends Node3D
## 메뉴 뒤 3D 그림: 하늘에 뜬 풀밭 섬 위에서 고른 보드와 캐릭터가 둥실둥실

var board: BoardView
var key := ""
var spin := 0.0
var t := 0.0
var cam: Camera3D
var board_only := false

func _ready() -> void:
	var tv := TrackView.new()
	tv.rng.seed = 5
	tv.trk = {"sky": true}
	tv.theme = "sky"
	tv.th = TrackView.THEMES.sky
	add_child(tv)
	tv._environment(true)
	# 떠 있는 섬
	tv._island(Vector3(0, 0, 0), 6.5)
	# 구름
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var cm := BoardView.mat(Color(1, 1, 1, 0.95), false, true)
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 60.0)
		var p := Vector3(cos(a) * r, rng.randf_range(-22, -6), sin(a) * r - 10.0)
		var c := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(4, 8)
		sm.height = sm.radius
		c.mesh = sm
		c.material_override = cm
		c.position = p
		add_child(c)
	# 섬 위 꾸밈
	var items := [["tree", Vector3(-4.2, 0, -2.5), 2.6], ["tree-pine", Vector3(4.4, 0, -2.0), 2.4], ["flowers", Vector3(-2.5, 0, 2.6), 1.6],
		["flowers-tall", Vector3(3.2, 0, 2.2), 1.6], ["rocks", Vector3(-4.6, 0, 1.2), 1.4], ["flag", Vector3(2.0, 0, -4.2), 2.0], ["grass", Vector3(1.0, 0, 3.6), 1.4]]
	for it in items:
		var mi := MeshInstance3D.new()
		mi.mesh = tv.kit_mesh(it[0])
		mi.position = it[1]
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * float(it[2])
		add_child(mi)
	# 멀리 떠 있는 작은 섬
	for i in 5:
		tv._island(Vector3(-40 + i * 20, rng.randf_range(-6, 8), -45 - rng.randf_range(0, 20)), rng.randf_range(3, 6))
	cam = Camera3D.new()
	cam.fov = 48.0
	add_child(cam)
	cam.current = true
	frame(false)

## wide = 보드를 오른쪽에 두고 왼쪽에 글자 자리를 남긴다
func frame(wide: bool) -> void:
	if wide:
		cam.position = Vector3(0.0, 4.4, 10.8)
		cam.look_at(Vector3(0.0, 0.4, 0), Vector3.UP)
	else:
		cam.position = Vector3(-2.6, 3.8, 8.4)
		cam.look_at(Vector3(-0.6, 1.2, 0), Vector3.UP)

func show_board(id: String, rider := "") -> void:
	var k2 := id + "/" + rider
	if k2 == key:
		return
	key = k2
	if board:
		board.queue_free()
	board = BoardView.new()
	add_child(board)
	board.setup(Game.board_def(id), rider)
	board.scale = Vector3.ONE * (1.35 if rider != "" else 1.55)
	board_only = rider == ""

func _process(dt: float) -> void:
	spin += dt * 0.6
	t += dt
	if board:
		board.rotation.y = spin
		board.position.y = (0.25 if not board_only else 1.2) + sin(t * 1.8) * 0.12
		board.deck.rotation.z = sin(t * 1.3) * 0.08 + (0.35 if board_only else 0.0)
