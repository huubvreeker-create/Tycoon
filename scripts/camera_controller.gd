extends Node3D
##
## Tycoon-style isometric camera. Locked tilt (~35° looking down),
## the player can:
##   - drag with right-mouse to pan over the venue
##   - scroll wheel to zoom (camera distance)
##   - drag with middle-mouse to rotate yaw (4-axis style)
##
## Hierarchy expected (this script lives on Rig):
##   Rig (this script)         — translates in world XZ to pan
##     Pitch (Node3D)          — fixed downward tilt
##       Camera3D              — pulled back along +Z by zoom_distance
##

@export var pan_speed: float = 0.04         # world units per pixel
@export var rotate_speed: float = 0.006     # radians per pixel
@export var zoom_speed: float = 1.4         # world units per scroll notch
@export var min_zoom: float = 8.0
@export var max_zoom: float = 45.0
@export var initial_zoom: float = 22.0
@export var pitch_degrees: float = -55.0
@export var pan_bounds: float = 35.0        # symmetric XZ box around origin

@onready var pitch_node: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D

var _zoom_distance: float = 22.0
var _panning: bool = false
var _rotating: bool = false


func _ready() -> void:
	_zoom_distance = initial_zoom
	pitch_node.rotation = Vector3(deg_to_rad(pitch_degrees), 0, 0)
	_apply_zoom()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			_rotating = event.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_apply_zoom_delta(-zoom_speed)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_apply_zoom_delta(zoom_speed)
				get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		# Pan in the rig's local XZ plane so up/down/left/right always
		# match the screen regardless of yaw rotation.
		var local := Vector3(-event.relative.x, 0, -event.relative.y) * pan_speed
		# Scale pan with zoom so it feels consistent at every distance.
		local *= (_zoom_distance / initial_zoom)
		var world_offset := global_transform.basis * local
		var new_pos := position + Vector3(world_offset.x, 0, world_offset.z)
		new_pos.x = clamp(new_pos.x, -pan_bounds, pan_bounds)
		new_pos.z = clamp(new_pos.z, -pan_bounds, pan_bounds)
		position = new_pos
		get_viewport().set_input_as_handled()
	elif _rotating:
		rotation.y -= event.relative.x * rotate_speed
		get_viewport().set_input_as_handled()


func _apply_zoom_delta(delta: float) -> void:
	_zoom_distance = clamp(_zoom_distance + delta, min_zoom, max_zoom)
	_apply_zoom()


func _apply_zoom() -> void:
	# Camera sits up along +Z of the pitch node, the pitch tilts it down.
	camera.position = Vector3(0, 0, _zoom_distance)
