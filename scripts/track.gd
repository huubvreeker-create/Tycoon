extends Node2D
class_name Track
##
## A single race venue. Phase 1 builds an oval Path2D procedurally,
## spawns a fleet of karts that loop around it, and renders a neon
## asphalt surface via _draw().
##
## Future phases will add: customer queue, race scheduling, payouts,
## upgrade slots, dirty/maintenance state.
##

@export var track_id: String = "local_track"
@export var venue_name: String = "Hometown Indoor"
@export var initial_kart_count: int = 5

# Visual tuning
@export var asphalt_width: float = 64.0
@export var asphalt_color: Color = Color(0.13, 0.14, 0.20)
@export var rumble_color: Color = Color(0.95, 0.25, 0.35)
@export var racing_line_color: Color = Color(0.13, 0.83, 0.96)

# Track geometry
@export var track_center: Vector2 = Vector2(640, 400)
@export var track_radius_x: float = 380.0
@export var track_radius_y: float = 200.0
@export var path_segments: int = 48

const KART_SCENE: PackedScene = preload("res://scenes/kart.tscn")

var path: Path2D
var karts: Array[Node] = []


func _ready() -> void:
	_build_path()
	_spawn_initial_karts()
	queue_redraw()


func _build_path() -> void:
	path = Path2D.new()
	path.name = "RacePath"
	var curve := Curve2D.new()
	for i in range(path_segments):
		var t := float(i) / float(path_segments) * TAU
		var p := track_center + Vector2(
			cos(t) * track_radius_x,
			sin(t) * track_radius_y
		)
		curve.add_point(p)
	# Close the loop by repeating the first point.
	curve.add_point(curve.get_point_position(0))
	path.curve = curve
	add_child(path)


func _spawn_initial_karts() -> void:
	var palette := [
		Color(0.96, 0.27, 0.36),  # red
		Color(0.99, 0.75, 0.18),  # yellow
		Color(0.13, 0.83, 0.96),  # cyan
		Color(0.55, 0.92, 0.38),  # green
		Color(0.86, 0.42, 0.98),  # magenta
	]
	for i in range(initial_kart_count):
		var kart := KART_SCENE.instantiate()
		kart.kart_color = palette[i % palette.size()]
		kart.speed = 140.0 + randf_range(-20.0, 30.0)
		path.add_child(kart)
		# Stagger their starting positions on the track.
		kart.progress = float(i) * 60.0
		karts.append(kart)


# --- Rendering --------------------------------------------------------------
func _draw() -> void:
	if path == null or path.curve == null:
		return
	var pts := path.curve.get_baked_points()
	if pts.size() < 2:
		return

	# Outer rumble strip (neon)
	draw_polyline(pts, rumble_color, asphalt_width + 10.0, true)
	# Asphalt surface
	draw_polyline(pts, asphalt_color, asphalt_width, true)
	# Dashed racing line down the middle
	_draw_dashed_polyline(pts, racing_line_color, 2.0, 18.0, 14.0)
	# Start / finish line
	_draw_start_line(pts)


func _draw_dashed_polyline(
	pts: PackedVector2Array,
	color: Color,
	width: float,
	dash_length: float,
	gap_length: float
) -> void:
	var distance_carry := 0.0
	var drawing := true
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len <= 0.001:
			continue
		var dir := seg / seg_len
		var traveled := 0.0
		while traveled < seg_len:
			var target := dash_length if drawing else gap_length
			var remaining := target - distance_carry
			var step: float = min(remaining, seg_len - traveled)
			if drawing:
				var p1 := a + dir * traveled
				var p2 := a + dir * (traveled + step)
				draw_line(p1, p2, color, width, true)
			traveled += step
			distance_carry += step
			if distance_carry >= target:
				distance_carry = 0.0
				drawing = not drawing


func _draw_start_line(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var p := pts[0]
	var next: Vector2 = pts[1]
	var dir: Vector2 = (next - p).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var half := asphalt_width * 0.5
	var a := p + perp * half
	var b := p - perp * half
	# Checker pattern: alternating black/white squares along the line.
	var squares := 8
	for i in range(squares):
		var t1 := float(i) / float(squares)
		var t2 := float(i + 1) / float(squares)
		var s1 := a.lerp(b, t1)
		var s2 := a.lerp(b, t2)
		var col := Color.WHITE if (i % 2 == 0) else Color(0.05, 0.05, 0.08)
		draw_line(s1, s2, col, 6.0)
