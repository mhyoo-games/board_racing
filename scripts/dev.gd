extends Node
## 개발용 자동 조작: godot -- --dev=<장면> --out=<폴더> 으로 실행하면 화면을 찍고 끝낸다. 평소에는 아무것도 안 함.
## 장면: title, tracks, shop, help, online, race(컴퓨터가 대신 몰기), team, time, items, tour, pause, results

var plan := ""
var out := "/tmp/board_racing"
var track := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dev="):
			plan = a.substr(6)
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--track="):
			track = a.substr(8)
	if plan == "":
		queue_free()
		return
	DirAccess.make_dir_recursive_absolute(out)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var wh := a.substr(7).split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sound.set_muted(true)
	Engine.max_physics_steps_per_frame = 40
	_run()

func shot(n: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("shot(그림 없음) ", n)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func main() -> Node:
	return get_tree().get_first_node_in_group("main")

func _race(mode: String, shots: Array) -> void:
	Game.mode = mode
	if track != "":
		Game.track_id = track
	main().start_race()
	await wait(0.3)
	var r = main().race
	r.autopilot = true
	await wait(1.0)
	await shot(mode + "_count")
	for s in shots:
		# 화면이 느려도 경주 시계 기준으로 찍는다
		while r.state == "count" or r.clock < s:
			await get_tree().process_frame
		await shot("%s_%02d" % [mode, int(s)])

func _run() -> void:
	await wait(1.0)
	match plan:
		"title":
			await shot("title")
		"boards":
			# 보드·캐릭터 가까이 보기
			var root := Node3D.new()
			get_tree().root.add_child(root)
			var tv := TrackView.new()
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-50, -30, 0)
			root.add_child(light)
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.background_color = Color(0.45, 0.7, 0.9)
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_color = Color(0.7, 0.75, 0.85)
			env.environment.ambient_light_energy = 0.5
			root.add_child(env)
			var i := 0
			for b in Game.boards:
				var bv := BoardView.new()
				root.add_child(bv)
				bv.setup(b, Rules.RIDERS[i % 5] if i < 3 else "", b.name)
				bv.position = Vector3((i % 6) * 2.6 - 6.5, 0, (i / 6) * -3.4)
				bv.rotation.y = 0.5
				i += 1
			var cam := Camera3D.new()
			root.add_child(cam)
			cam.position = Vector3(0, 5.5, 6.0)
			cam.look_at(Vector3(0, 0.3, -1.8))
			cam.current = true
			main().menu.visible = false
			main().bg.visible = false
			await wait(1.0)
			await shot("boards")
		"tracks":
			Game.mode = "race"
			main().menu.show_screen("tracks"); await wait(0.5); await shot("tracks")
		"shop":
			Game.save.coins = 1200
			Game.save.exp = 300
			main().menu.show_screen("shop"); await wait(0.6); await shot("shop")
			main().menu.shop_pick = "flame"; main().menu.show_screen("shop"); await wait(0.6); await shot("shop2")
			main().menu.show_screen("riders"); await wait(0.6); await shot("riders")
		"online":
			Game.mode = "online"
			main().menu.show_screen("online"); await wait(0.5); await shot("online")
		"help":
			main().menu.show_screen("help"); await wait(0.4); await shot("help")
		"race":
			await _race("race", [4.0, 7.0, 11.0, 16.0])
		"team":
			await _race("team", [5.0, 12.0])
		"time":
			await _race("time", [5.0])
		"items":
			Game.items = true
			await _race("race", [6.0, 12.0, 18.0, 26.0])
			var it = main().race.items
			print("아이템 통계 ", it.stats, " 날아가는 것 ", it.shots.size(), " 함정 ", it.traps.size(), " 내 아이템 ", main().race.humans[0].k.items)
		"tour":
			await _race("time", [8.0, 16.0, 24.0, 32.0, 40.0])
		"pause":
			await _race("race", [2.0])
			main().race.pause_menu.open()
			await wait(0.5)
			await shot("pause")
		"results":
			Game.mode = "race"
			main().start_race()
			await wait(0.3)
			var r = main().race
			r.autopilot = true
			Engine.time_scale = 4.0
			while is_instance_valid(main().race):
				await wait(1.0)
			Engine.time_scale = 1.0
			await wait(0.6)
			await shot("results")
	get_tree().quit()
