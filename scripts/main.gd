extends Node3D
##
## Root scene controller for the 3D venue. Handles:
##   - boot banner
##   - left-click raycasting from camera to 3D objects
##   - opening the right upgrade popup (kart vs. track)
##   - closing the popup when clicking on the background
##
## All view rotation/pan/zoom lives on the CameraRig.
##

@onready var camera: Camera3D       = $CameraRig/Pitch/Camera3D
@onready var track: Track           = $Track
@onready var upgrade_popup          = $PopupHost/UpgradePopup
@onready var hud                    = $HUD


func _ready() -> void:
	randomize()
	print("[Kart Empire] 3D scene booting…")
	print("  Cash:   €%d" % EconomyManager.cash)
	print("  Day:    %d"  % GameManager.day)
	print("  Ticket: €%d" % GameManager.ticket_price)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)


func _handle_left_click(mouse_pos: Vector2) -> void:
	# Cast a ray from the camera through the mouse and look for an
	# Area3D in either of the two clickable groups.
	var from := camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		# Click on empty space dismisses any open popup.
		upgrade_popup.visible = false
		return
	var collider: Object = hit.get("collider")
	if collider == null:
		upgrade_popup.visible = false
		return
	var kind: Variant = collider.get_meta("kind", "")
	match kind:
		"kart":
			upgrade_popup.open_for("kart", track, mouse_pos)
		"track":
			upgrade_popup.open_for("track", track, mouse_pos)
		_:
			upgrade_popup.visible = false
