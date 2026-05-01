extends PathFollow2D
class_name Kart
##
## A single kart following a Path2D. Two states:
##   - idle:    cruises slowly around the track
##   - racing:  has a customer aboard, runs at full pace
##
## Tier (1..4) drives both speed and visual detail (spoiler, side
## stripes, tier-4 glow). Color is per-instance so the fleet looks
## varied even at the same tier.
##

const IDLE_SPEED_BASE: float = 55.0
const RACING_SPEED_BASE: float = 140.0
const TIER_SPEED_BONUS: float = 25.0   # added per tier above 1

@export var kart_color: Color = Color(0.96, 0.27, 0.36)
@export var body_length: float = 24.0
@export var body_width: float = 12.0

var tier: int = 1
var racing: bool = false


func _ready() -> void:
	loop = true
	rotates = true
	queue_redraw()


func _process(delta: float) -> void:
	progress += current_speed() * delta


func current_speed() -> float:
	var base := RACING_SPEED_BASE if racing else IDLE_SPEED_BASE
	return base + (tier - 1) * TIER_SPEED_BONUS


func is_busy() -> bool:
	return racing


func set_racing(active: bool) -> void:
	if racing == active:
		return
	racing = active
	queue_redraw()


func set_tier(new_tier: int) -> void:
	tier = clamp(new_tier, 1, 4)
	queue_redraw()


func _draw() -> void:
	# Tier 4 gets a soft glow halo behind the body.
	if tier >= 4:
		draw_circle(Vector2.ZERO, body_length * 0.85, Color(1, 1, 1, 0.10))

	# Racing karts get a subtle motion-trail behind them.
	if racing:
		for i in range(3):
			var trail_x := -body_length * 0.5 - 4.0 - i * 5.0
			var alpha: float = 0.25 - i * 0.07
			var col := kart_color
			col.a = alpha
			draw_rect(
				Rect2(trail_x, -body_width * 0.5 + 2, 4, body_width - 4),
				col
			)

	var hl := body_length * 0.5
	var hw := body_width * 0.5

	# Drop shadow.
	draw_rect(
		Rect2(-hl + 1.5, -hw + 2.0, body_length, body_width),
		Color(0, 0, 0, 0.35)
	)

	# Body.
	draw_rect(Rect2(-hl, -hw, body_length, body_width), kart_color)

	# Tier 3+: side stripes (bright accent bands).
	if tier >= 3:
		var stripe := kart_color.lightened(0.45)
		draw_rect(Rect2(-hl + 4, -hw, body_length - 10, 1.5), stripe)
		draw_rect(Rect2(-hl + 4, hw - 1.5, body_length - 10, 1.5), stripe)

	# Cockpit.
	var cockpit_color := kart_color.darkened(0.4)
	draw_rect(
		Rect2(-hl + 5, -hw + 2, body_length - 10, body_width - 4),
		cockpit_color
	)

	# Front bumper highlight.
	draw_rect(Rect2(hl - 3, -hw, 3, body_width), Color(1, 1, 1, 0.85))

	# Tier 2+: rear spoiler (wing behind the body).
	if tier >= 2:
		var spoiler := kart_color.darkened(0.2)
		draw_rect(Rect2(-hl - 3, -hw - 1, 3, body_width + 2), spoiler)
		draw_rect(Rect2(-hl - 4, -hw - 1, 1, body_width + 2), Color(1, 1, 1, 0.6))

	# Wheels (front + rear, top + bottom).
	var wheel_col := Color(0.08, 0.08, 0.10)
	var ww := 4.0
	var wh := 3.0
	for x in [-hl + 2.0, hl - 2.0 - ww]:
		draw_rect(Rect2(x, -hw - 1.5, ww, wh), wheel_col)
		draw_rect(Rect2(x, hw - 1.5, ww, wh), wheel_col)
