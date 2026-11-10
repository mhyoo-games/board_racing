class_name Controls
extends RefCounted
## 사람이 누르는 키를 입력으로. 키보드·게임패드·화면 버튼(터치).
##
## 키보드: ↑ 가속 / ↓ 브레이크 / ←→ 회전 / Shift 슬라이드 / Space·Ctrl 부스터
##         A 점프 / S 그랩(GB) / D 360 / F 720
## 게임패드: 왼쪽 스틱·십자키 / RT 가속 / LT 브레이크 / RB 슬라이드 / LB 부스터 / A 점프 / X GB / Y 360 / B 720

static var touch := {}       # 화면 버튼: left, right, brake, slide, boost, jump, gb, 360, 720

static func _k(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)

static func _pad(dev: int, b: JoyButton) -> bool:
	return Input.is_joy_button_pressed(dev, b)

static func _axis(dev: int, a: JoyAxis) -> float:
	return Input.get_joy_axis(dev, a)

## 돌려주는 것: {throttle, steer, slide, boost, jump, gb, t360, t720} (누르고 있는지)
static func read() -> Dictionary:
	var up := _k(KEY_UP)
	var down := _k(KEY_DOWN)
	var left := _k(KEY_LEFT)
	var right := _k(KEY_RIGHT)
	var slide := _k(KEY_SHIFT)
	var boost := _k(KEY_CTRL) or _k(KEY_SPACE)
	var jump := _k(KEY_A)
	var gb := _k(KEY_S)
	var t360 := _k(KEY_D)
	var t720 := _k(KEY_F)
	var steer_axis := 0.0
	for d in Input.get_connected_joypads():
		var ax := _axis(d, JOY_AXIS_LEFT_X)
		if absf(ax) > 0.2:
			steer_axis = ax
		left = left or _pad(d, JOY_BUTTON_DPAD_LEFT)
		right = right or _pad(d, JOY_BUTTON_DPAD_RIGHT)
		up = up or _axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or _pad(d, JOY_BUTTON_DPAD_UP)
		down = down or _axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.4 or _pad(d, JOY_BUTTON_DPAD_DOWN)
		slide = slide or _pad(d, JOY_BUTTON_RIGHT_SHOULDER)
		boost = boost or _pad(d, JOY_BUTTON_LEFT_SHOULDER)
		jump = jump or _pad(d, JOY_BUTTON_A)
		gb = gb or _pad(d, JOY_BUTTON_X)
		t360 = t360 or _pad(d, JOY_BUTTON_Y)
		t720 = t720 or _pad(d, JOY_BUTTON_B)
	# 화면 버튼. 터치로 하면 가속은 저절로
	if touch.get("on", false):
		up = up or not touch.get("brake", false)
		down = down or touch.get("brake", false)
		left = left or touch.get("left", false)
		right = right or touch.get("right", false)
		slide = slide or touch.get("slide", false)
		boost = boost or touch.get("boost", false)
		jump = jump or touch.get("jump", false)
		gb = gb or touch.get("gb", false)
		t360 = t360 or touch.get("360", false)
		t720 = t720 or touch.get("720", false)
	var steer := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	if steer_axis != 0.0:
		steer = steer_axis
	var thr := (1.0 if up else 0.0) - (1.0 if down else 0.0)
	return {"throttle": thr, "steer": steer, "slide": slide, "boost": boost, "jump": jump, "gb": gb, "t360": t360, "t720": t720}
