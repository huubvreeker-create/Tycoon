extends Node3D
##
## Mobile-first camera rig.
##   - one-finger drag      → pan the venue
##   - two-finger pinch     → zoom (camera distance)
##   - one-finger tap       → emits `tapped(screen_pos)` for clicks
##
## Desktop testing works via Godot's built-in mouse→touch emulation
## (configured in project.godot).
##
## Hierarchy (this script lives on Rig):
##   Rig (this script)         — translates in world XZ to pan
##     Pitch (Node3D)          — fixed downward tilt
##       Camera3D              — pulled back along +Z by zoom_distance
##

signal tapped(screen_pos: Vector2)

@export var pan_speed: float = 0.05
# `min_zoom` / `max_zoom` are the ORTHOGONAL camera `size` bounds (the
# vertical world span the camera shows). Pinch grows / shrinks them.
# max_zoom must be wide enough for tier 10's full track (loop_rx=80
# gives 160 m horizontal track extent — camera vertical span 240
# easily fits that with a margin once portrait aspect ratio is
# applied).
@export var min_zoom: float = 22.0
@export var max_zoom: float = 240.0
@export var initial_zoom: float = 60.0
@export var pitch_degrees: float = -55.0
# Yaw the rig so the track's longer X axis runs down the portrait
# viewport — uses the screen height for the wider track dimension.
@export var yaw_degrees: float = 90.0
# Pan bounds — match the world-border rectangle in facility_visuals.gd
# (-160..+130 east-west, -160..+55 north-south). Symmetric pan_bounds
# is a fallback for callers / tools that read it; the per-axis limits
# are what _pan_with_relative actually clamps to.
@export var pan_bounds: float = 160.0
@export var pan_min_x: float = -160.0
@export var pan_max_x: float =  130.0
@export var pan_min_z: float = -160.0
@export var pan_max_z: float =   55.0
@export var tap_threshold_px: float = 14.0

@onready var pitch_node: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D

# Active touches keyed by index → current screen position.
var _touches: Dictionary = {}
# Per-touch accumulated drag distance, used to discriminate tap vs pan.
var _drag_distances: Dictionary = {}
# Pinch state (only meaningful while two touches are down).
var _pinch_initial_distance: float = 0.0
var _pinch_initial_zoom: float = 0.0

var _zoom_distance: float = 32.0


func _ready() -> void:
	_zoom_distance = initial_zoom
	rotation = Vector3(0, deg_to_rad(yaw_degrees), 0)
	pitch_node.rotation = Vector3(deg_to_rad(pitch_degrees), 0, 0)
	# Orthogonal projection — no perspective foreshortening, the
	# closest and farthest edges of the track render at the same
	# scale (classic tycoon top-down look).
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Sit the camera reasonably far back so its near/far frustum
	# comfortably encloses the venue at every zoom level.
	camera.position = Vector3(0, 0, 60.0)
	_apply_zoom()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


# ---------------------------------------------------------------------------
# Touch lifecycle
# ---------------------------------------------------------------------------
func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		_drag_distances[event.index] = 0.0
		if _touches.size() == 2:
			_begin_pinch()
	else:
		# Touch released
		var was_short_press: bool = (
			_drag_distances.get(event.index, 0.0) < tap_threshold_px
			and _touches.size() == 1
		)
		_touches.erase(event.index)
		_drag_distances.erase(event.index)
		# Reset pinch state when we drop below 2 fingers.
		if _touches.size() < 2:
			_pinch_initial_distance = 0.0
		# Fire a tap if it was a short single-finger press.
		if was_short_press:
			tapped.emit(event.position)


func _handle_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	_drag_distances[event.index] = _drag_distances.get(event.index, 0.0) + event.relative.length()
	if _touches.size() == 1:
		_pan_with_relative(event.relative)
	elif _touches.size() == 2:
		_apply_pinch()


# ---------------------------------------------------------------------------
# Pan
# ---------------------------------------------------------------------------
func _pan_with_relative(relative: Vector2) -> void:
	# Drag-to-pan: dragging finger right moves world right (under finger).
	# In orthogonal mode pan should match world-units-per-pixel exactly,
	# so scale by zoom-size / viewport-height.
	var vp_height: float = float(get_viewport().get_visible_rect().size.y)
	if vp_height <= 0.0:
		vp_height = 1280.0
	var px_to_world: float = _zoom_distance / vp_height
	var local := Vector3(-relative.x, 0, -relative.y) * px_to_world
	var world_offset := global_transform.basis * local
	var new_pos := position + Vector3(world_offset.x, 0, world_offset.z)
	new_pos.x = clampf(new_pos.x, pan_min_x, pan_max_x)
	new_pos.z = clampf(new_pos.z, pan_min_z, pan_max_z)
	position = new_pos


# ---------------------------------------------------------------------------
# Pinch zoom
# ---------------------------------------------------------------------------
func _begin_pinch() -> void:
	var positions: Array = _touches.values()
	if positions.size() < 2:
		return
	_pinch_initial_distance = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
	_pinch_initial_zoom = _zoom_distance


func _apply_pinch() -> void:
	if _pinch_initial_distance <= 0.0:
		_begin_pinch()
		return
	var positions: Array = _touches.values()
	if positions.size() < 2:
		return
	var current := (positions[0] as Vector2).distance_to(positions[1] as Vector2)
	if current <= 0.0:
		return
	# Spreading fingers apart → smaller zoom_distance (zoom in).
	var ratio := _pinch_initial_distance / current
	_zoom_distance = clampf(_pinch_initial_zoom * ratio, min_zoom, max_zoom)
	_apply_zoom()


func _apply_zoom() -> void:
	# In orthogonal mode `size` is the visible vertical world span.
	camera.size = _zoom_distance
