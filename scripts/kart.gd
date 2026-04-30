extends PathFollow2D
class_name Kart
##
## A single kart following a Path2D. Phase 1 just animates around the track.
## Future phases will add: durability, repair state, prestige tier,
## driver assignment, race result computation.
##

@export var speed: float = 140.0
@export var kart_color: Color = Color(0.96, 0.27, 0.36)
@export var body_length: float = 22.0
@export var body_width: float = 12.0


func _ready() -> void:
	loop = true
	rotates = true
	queue_redraw()


func _process(delta: float) -> void:
	progress += speed * delta


func _draw() -> void:
	var hl := body_length * 0.5
	var hw := body_width * 0.5

	# Shadow
	draw_rect(
		Rect2(-hl + 1.5, -hw + 2.0, body_length, body_width),
		Color(0, 0, 0, 0.35)
	)
	# Body
	draw_rect(Rect2(-hl, -hw, body_length, body_width), kart_color)
	# Cockpit (slightly darker stripe)
	var cockpit_color := kart_color.darkened(0.35)
	draw_rect(
		Rect2(-hl + 4, -hw + 2, body_length - 8, body_width - 4),
		cockpit_color
	)
	# Front bumper highlight
	draw_rect(Rect2(hl - 3, -hw, 3, body_width), Color(1, 1, 1, 0.85))
	# Wheels (front + rear, top + bottom)
	var wheel_col := Color(0.08, 0.08, 0.10)
	var ww := 4.0
	var wh := 3.0
	for x in [-hl + 2.0, hl - 2.0 - ww]:
		draw_rect(Rect2(x, -hw - 1.5, ww, wh), wheel_col)
		draw_rect(Rect2(x, hw - 1.5, ww, wh), wheel_col)
