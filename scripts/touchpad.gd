extends Control
## 휴대폰 화면 버튼 (여러 손가락 동시에). 왼쪽: ◀ ▶, 오른쪽: 점프·묘기 셋·부스터·슬라이드. 가속은 저절로.

var touches := {}   # index → 위치

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _buttons() -> Dictionary:
	var s := size
	var r := minf(s.y * 0.11, 78.0)
	var y := s.y - r * 1.35
	return {
		"left": [Vector2(r * 1.35, y), r],
		"right": [Vector2(r * 3.6, y), r],
		"jump": [Vector2(s.x - r * 1.4, y), r * 1.1],
		"gb": [Vector2(s.x - r * 3.6, y + r * 0.2), r * 0.8],
		"360": [Vector2(s.x - r * 1.8, y - r * 2.2), r * 0.8],
		"720": [Vector2(s.x - r * 3.8, y - r * 1.8), r * 0.8],
		"boost": [Vector2(s.x - r * 5.6, y + r * 0.2), r * 0.8],
		"slide": [Vector2(r * 2.45, y - r * 2.1), r * 0.75],
		"brake": [Vector2(r * 4.9, y - r * 1.9), r * 0.6],
	}

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position
		else:
			touches.erase(e.index)
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
	else:
		return
	var b := _buttons()
	for name in b:
		Controls.touch[name] = false
	for p in touches.values():
		for name in b:
			if p.distance_to(b[name][0]) < b[name][1] * 1.1:
				Controls.touch[name] = true
	Controls.touch["on"] = true
	queue_redraw()

func _draw() -> void:
	var labels := {"left": "◀", "right": "▶", "jump": "점프", "gb": "GB", "360": "360", "720": "720", "boost": "부스터", "slide": "슬라이드", "brake": "브레이크"}
	var b := _buttons()
	for name in b:
		var on: bool = Controls.touch.get(name, false)
		draw_circle(b[name][0], b[name][1], Color(1, 1, 1, 0.32 if on else 0.15))
		draw_arc(b[name][0], b[name][1], 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
		var fs := int(b[name][1] * (0.7 if name in ["left", "right"] else 0.36))
		var w := Game.font_bold.get_string_size(labels[name], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(Game.font_bold, b[name][0] + Vector2(-w * 0.5, fs * 0.35), labels[name], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
