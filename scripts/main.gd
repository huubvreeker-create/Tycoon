extends Node3D
##
## Root scene controller for the 3D venue. Handles:
##   - boot banner
##   - tap-on-3D-object detection (forwarded from CameraRig)
##   - opening the upgrade bottom sheet (kart vs. track)
##   - opening the settings popup from the HUD cog button
##
## All view rotation/pan/zoom lives on the CameraRig (touch-based).
##

@onready var camera: Camera3D     = $CameraRig/Pitch/Camera3D
@onready var camera_rig: Node3D   = $CameraRig
@onready var track: Track         = $Track
@onready var upgrade_popup        = $PopupHost/UpgradePopup
@onready var settings_popup       = $PopupHost/SettingsPopup
@onready var hud                  = $HUD


func _ready() -> void:
	randomize()
	print("[Kart Empire] Mobile build booting…")
	print("  Cash:   €%d" % EconomyManager.cash)
	print("  Day:    %d"  % GameManager.day)
	# CameraRig fires `tapped` for short single-finger presses (no drag).
	camera_rig.tapped.connect(_handle_tap)
	# HUD buttons open the upgrade panel / settings drawer.
	hud.buy_kart_pressed.connect(func(): upgrade_popup.open_for("kart", track))
	hud.tab_requested.connect(func(tab: String): upgrade_popup.open_for(tab, track))
	hud.settings_pressed.connect(func(): settings_popup.open())


func _handle_tap(screen_pos: Vector2) -> void:
	# Cast a ray from the camera through the tap and look for an Area3D in
	# either of the two clickable groups.
	var from := camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider == null:
		return
	var kind: Variant = collider.get_meta("kind", "")
	match kind:
		"kart":
			upgrade_popup.open_for("kart", track)
		"track":
			upgrade_popup.open_for("track", track)
