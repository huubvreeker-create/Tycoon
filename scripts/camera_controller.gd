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

@export var pan_speed: float = 0.06
@export var min_zoom: float = 14.0
@export var max_zoom: float = 60.0
@export var initial_zoom: float = 32.0
@export var pitch_degrees: float = -55.0
@export var pan_bounds: float = 45.0
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
	pitch_node.rotation = Vector3(deg_to_rad(pitch_degrees), 0, 0)
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
	var local := Vector3(-relative.x, 0, -relative.y) * pan_speed
	# Scale pan with zoom so the world tracks the finger consistently.
	local *= (_zoom_distance / initial_zoom)
	var world_offset := global_transform.basis * local
	var new_pos := position + Vector3(world_offset.x, 0, world_offset.z)
	new_pos.x = clamp(new_pos.x, -pan_bounds, pan_bounds)
	new_pos.z = clamp(new_pos.z, -pan_bounds, pan_bounds)
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
	camera.position = Vector3(0, 0, _zoom_distance)
