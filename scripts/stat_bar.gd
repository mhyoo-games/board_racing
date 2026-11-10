class_name StatBar
extends Control
## 능력치 막대 (0..1)

var value := 0.5

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.14, 0.7))
	var c := Color(0.4, 0.78, 1.0).lerp(Color(1.0, 0.78, 0.25), value)
	draw_rect(Rect2(Vector2(2, 2), Vector2((size.x - 4) * value, size.y - 4)), c)
	for i in range(1, 10):
		var x := size.x * i / 10.0
		draw_line(Vector2(x, 2), Vector2(x, size.y - 2), Color(0, 0, 0, 0.25), 1.0)
