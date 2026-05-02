extends Node3D
class_name FacilityVisuals
##
## Procedurally-built 3D buildings + props that visualise the
## current Facilities levels around the track. Each facility maps to
## one structure; building scales with level. Sponsor boards and
## lighting rigs spawn multiple instances proportional to level.
##
## Re-builds on EventBus.facility_upgraded and on tier changes
## (the track footprint changes per tier so positions move).
##

const _CAFETERIA_COLOR  := Color(0.99, 0.75, 0.18)
const _PIT_LANE_COLOR   := Color(0.13, 0.83, 0.96)
const _LOUNGE_COLOR     := Color(0.86, 0.42, 0.98)
const _MERCH_COLOR      := Color(0.55, 0.92, 0.38)
const _GRANDSTAND_COLOR := Color(0.65, 0.55, 0.78)
const _PARKING_COLOR    := Color(0.40, 0.65, 1.00)
const _MARKETING_COLOR  := Color(1.00, 0.40, 0.20)
const _SPONSOR_COLORS := [
	Color(0.96, 0.27, 0.36),
	Color(0.99, 0.75, 0.18),
	Color(0.13, 0.83, 0.96),
	Color(0.55, 0.92, 0.38),
	Color(0.86, 0.42, 0.98),
	Color(1.00, 0.55, 0.20),
]

@export var track_path: NodePath

var _track: Track
var _root_holders := {}  # facility name → Node3D holder
var _decoration_holder: Node3D


func _ready() -> void:
	_track = get_node_or_null(track_path) as Track
	for facility: String in Facilities.facility_names():
		var holder := Node3D.new()
		holder.name = facility.capitalize() + "Holder"
		add_child(holder)
		_root_holders[facility] = holder
	# Permanent venue decorations (ticket booth + walkway network +
	# trees). Don't depend on facility levels but DO depend on the
	# track tier (positions scale with the track footprint).
	_decoration_holder = Node3D.new()
	_decoration_holder.name = "DecorationHolder"
	add_child(_decoration_holder)
	EventBus.facility_upgraded.connect(_on_facility_upgraded)
	# Track size only changes on tier rollover (per-level upgrades buy
	# stats, not new geometry), so we only need to rebuild facility
	# layout on track_tier_changed.
	EventBus.track_tier_changed.connect(_on_tier_changed.unbind(2))
	# Defer first build so the track has constructed its path/footprint.
	call_deferred("_rebuild_all")


func _rebuild_all() -> void:
	for facility: String in Facilities.facility_names():
		_rebuild_one(facility)
	_rebuild_decorations()


func _rebuild_decorations() -> void:
	for child in _decoration_holder.get_children():
		child.queue_free()
	if _track == null:
		return
	_build_walkways(_decoration_holder)
	_build_ticket_booth(_decoration_holder)
	_build_trees(_decoration_holder)


func _on_facility_upgraded(facility: String, _level: int) -> void:
	_rebuild_one(facility)


func _on_tier_changed() -> void:
	_rebuild_all()


func _rebuild_one(facility: String) -> void:
	if _track == null:
		return
	var holder: Node3D = _root_holders.get(facility)
	if holder == null:
		return
	for child in holder.get_children():
		child.queue_free()
	var level := Facilities.get_level(facility)
	if level <= 0:
		return
	match facility:
		"cafeteria":      _build_cafeteria(holder, level)
		"pit_lane":       _build_pit_lane(holder, level)
		"lounge":         _build_lounge(holder, level)
		"merch_shop":     _build_merch_shop(holder, level)
		"sponsor_boards": _build_sponsor_boards(holder, level)
		"lighting":       _build_lighting(holder, level)
		"grandstand":     _build_grandstand(holder, level)
		"parking":        _build_parking(holder, level)
		"marketing":      _build_marketing(holder, level)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Use the LIVE track radii (which interpolate continuously between
# tiers) so facilities reposition smoothly each upgrade tap.
func _track_rx() -> float:
	return _track.current_rx()

func _track_rz() -> float:
	return _track.current_rz()

# Outer extent of the asphalt (= rumble-strip outer edge) in world units
# along each axis. Uses the live (interpolated) track values so it stays
# in sync with per-level track growth, plus the rumble inset baseline.
const _RUMBLE_INSET_VAL: float = 0.18

func _track_outer_x(margin: float = 0.0) -> float:
	# East-west outer extent. At the loop's east/west extremes the
	# tangent runs south, so the asphalt extends purely in the X
	# direction — no wave_amp budget needed (chicanes / kinks live
	# in the loop's middle, not at its X-extremes).
	return _track.current_rx() + _track.current_asphalt_width() * 0.5 \
		+ _RUMBLE_INSET_VAL + margin

func _track_outer_z(margin: float = 0.0) -> float:
	# SOUTH outer extent (returned as a positive distance from origin).
	# All south-side facilities (plaza, grandstand, lounge, parking,
	# cafeteria, merch) sit at z = -_track_outer_z(safety).
	return _track.south_extent_z(margin)

func _track_outer_north(margin: float = 0.0) -> float:
	# +Z outer extent of the FIXED north straight. Smaller than the
	# south extent because the north side is the straight (no loop).
	# Used for facilities on the +Z side (only the marketing tower —
	# the pit lane positions itself directly).
	return _track.north_extent_z(margin)

func _make_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emissive: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.1
	mat.roughness = 0.6
	if emissive > 0.0:
		mat.emission_enabled = true
		mat.emission = color.lightened(0.4)
		mat.emission_energy_multiplier = emissive
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _make_label_strip(parent: Node3D, color: Color, pos: Vector3, size: Vector3) -> void:
	# Bright accent strip that sits on top of/around a building.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_facility_click_area(parent: Node3D, facility_id: String, center: Vector3, size: Vector3) -> void:
	# Each facility gets a generous Area3D so the player can tap anywhere
	# on or around the building to open the FACILITY tab in the panel.
	# main.gd's tap raycast looks for the meta "kind" == "facility".
	var area := Area3D.new()
	area.name = facility_id.capitalize() + "Click"
	area.collision_layer = 1
	area.collision_mask = 1
	area.set_meta("kind", "facility")
	area.set_meta("facility_id", facility_id)
	parent.add_child(area)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	area.add_child(collider)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func _build_cafeteria(parent: Node3D, level: int) -> void:
	# A real café: main building + covered patio + tables with parasols
	# + signage on the front.  Sits on the LEFT (-X) side of the venue.
	var w: float = 5.0 + level * 0.18
	var d: float = 4.5 + level * 0.16
	var h: float = 3.0 + level * 0.12
	var patio_d: float = 2.5 + level * 0.08
	# The patio extends from the building toward the track. Anchor the
	# patio's near edge at (track outer + safety) so it never clips the
	# rumble strip — works at every tier and every facility level.
	const SAFETY: float = 4.0
	var patio_near_x: float = -_track_outer_x(SAFETY)
	# patio_near_x = patio_pos.x - patio_d * 0.5
	# patio_pos.x  = building_pos.x + w * 0.5 + patio_d * 0.5
	# building_pos.x = patio_near_x - w * 0.5 - patio_d
	var building_pos := Vector3(patio_near_x - w * 0.5 - patio_d, h * 0.5, 0.0)

	# Main building.
	_make_box(parent, Vector3(w, h, d), building_pos, _CAFETERIA_COLOR.darkened(0.15))

	# Lit-up sign band on the side facing the track.
	_make_label_strip(parent, _CAFETERIA_COLOR,
		building_pos + Vector3(w * 0.5 + 0.05, h * 0.25, 0),
		Vector3(0.06, 0.40, d * 0.85))

	# Patio in front of the building (between building and track).
	var patio_pos: Vector3 = building_pos + Vector3(w * 0.5 + patio_d * 0.5, -h * 0.5 + 0.05, 0)
	_make_box(parent, Vector3(patio_d, 0.10, d * 0.95),
		patio_pos, _CAFETERIA_COLOR.darkened(0.7))

	# Awning over the patio (flat panel on supports).
	var awning_h: float = h * 0.85
	_make_box(parent, Vector3(patio_d * 0.95, 0.12, d * 0.9),
		patio_pos + Vector3(0, awning_h - 0.05, 0),
		_CAFETERIA_COLOR)
	# Awning support pillars (the four corners).
	var support_h: float = awning_h - 0.05
	var sx: float = patio_d * 0.42
	var sz: float = d * 0.4
	for support_offset: Vector3 in [
		Vector3( sx, 0,  sz),
		Vector3( sx, 0, -sz),
		Vector3(-sx, 0,  sz),
		Vector3(-sx, 0, -sz),
	]:
		_make_box(parent, Vector3(0.10, support_h, 0.10),
			patio_pos + support_offset + Vector3(0, support_h * 0.5, 0),
			_CAFETERIA_COLOR.darkened(0.6))

	# Tables with parasols on the patio.
	var table_count: int = clampi(2 + level / 4, 2, 5)
	for i in range(table_count):
		var t_norm: float = (float(i) + 0.5) / float(table_count)
		var tz: float = (t_norm - 0.5) * d * 0.75
		var table_floor: Vector3 = patio_pos + Vector3(0, 0.10, tz)
		# Table top
		_make_box(parent, Vector3(0.7, 0.06, 0.7),
			table_floor + Vector3(0, 0.45, 0),
			Color(0.85, 0.85, 0.90))
		# Pole
		_make_box(parent, Vector3(0.06, 1.5, 0.06),
			table_floor + Vector3(0, 0.75, 0),
			Color(0.40, 0.40, 0.45))
		# Parasol (flat slab)
		_make_box(parent, Vector3(1.10, 0.08, 1.10),
			table_floor + Vector3(0, 1.55, 0),
			_CAFETERIA_COLOR.lightened(0.15))

	# Tap target covers building + patio.
	var click_center := Vector3(building_pos.x + (w * 0.5 + patio_d) * 0.5,
		h * 0.5, 0.0)
	_add_facility_click_area(parent, "cafeteria", click_center,
		Vector3(w + patio_d, h * 1.4, d * 1.05))


func _build_pit_lane(parent: Node3D, level: int) -> void:
	# Pit complex aligned to the FIXED north straight. Same position
	# and orientation on every tier — only the building scale and
	# garage count change with the facility level. Geometry is now
	# trivially axis-aligned (no curve sampling) because the main
	# straight itself is straight.
	#
	# World layout (looking down +Y):
	#   Track straight: x ∈ [-loop_rx, +loop_rx], z = STRAIGHT_Z
	#   Pit straight:   x ∈ [-STRAIGHT_HALF, +STRAIGHT_HALF],
	#                   z = STRAIGHT_Z + grass_gap + pit_w/2
	#   Garages + paddock further north of the pit straight
	var sh: float = _track.STRAIGHT_HALF
	var straight_z: float = _track.STRAIGHT_Z
	var asphalt_outer_z: float = straight_z \
		+ _track.current_asphalt_width() * 0.5 + _RUMBLE_INSET_VAL
	var asphalt_color := Color(0.42, 0.44, 0.48)
	var pit_lane_width: float = 2.6 + float(level) * 0.06
	# Grass gap is constant across tiers (no chicane wobble on the
	# straight to budget for) — keeps the pit lane in exactly the
	# same spot every tier.
	var grass_gap: float = 3.5
	var pit_z: float = asphalt_outer_z + grass_gap + pit_lane_width * 0.5

	# Pit asphalt — flat box running the full length of the straight
	# with smooth merge ramps at each end (small triangle wedges
	# fanning back to the track edge so it visually branches off).
	# Implemented as one main slab + two end "ramps" trimmed at the
	# track outer edge.
	var pit_main := MeshInstance3D.new()
	pit_main.name = "PitAsphaltMain"
	var pit_main_bm := BoxMesh.new()
	pit_main_bm.size = Vector3(2.0 * sh, 0.08, pit_lane_width)
	pit_main.mesh = pit_main_bm
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = asphalt_color
	pit_mat.roughness = 0.85
	pit_main.material_override = pit_mat
	pit_main.position = Vector3(0.0, 0.005, pit_z)
	parent.add_child(pit_main)

	# Two merge ramps at the ends — narrow triangles connecting the
	# pit lane back to the track edge so it visibly branches off
	# rather than starting/ending in mid-air.
	var ramp_len: float = 4.0
	for end_sign: float in [-1.0, 1.0]:
		var ramp_outer_x: float = end_sign * (sh + ramp_len)
		var ramp_inner_x: float = end_sign * sh
		# Ramp is a thin slab from (ramp_inner_x, pit_z) tapering toward
		# (ramp_outer_x, asphalt_outer_z + 0.4). Approximate with a
		# rotated narrow box.
		var ramp_a := Vector3(ramp_inner_x, 0.005, pit_z)
		var ramp_b := Vector3(ramp_outer_x, 0.005, asphalt_outer_z + 0.4)
		var ramp_dir := ramp_b - ramp_a
		var ramp_len_actual: float = ramp_dir.length()
		if ramp_len_actual < 0.05:
			continue
		var ramp := MeshInstance3D.new()
		var ramp_bm := BoxMesh.new()
		ramp_bm.size = Vector3(ramp_len_actual + 0.05, 0.08,
			pit_lane_width * 0.7)
		ramp.mesh = ramp_bm
		ramp.material_override = pit_mat
		ramp.position = (ramp_a + ramp_b) * 0.5
		ramp.rotation.y = atan2(-ramp_dir.z, ramp_dir.x)
		parent.add_child(ramp)

	# Pit wall — thin slab on the SOUTH edge of the pit lane (between
	# pit and track). Stretches the length of the main pit straight.
	var wall_h: float = 0.55
	var wall := MeshInstance3D.new()
	wall.name = "PitWall"
	var wall_bm := BoxMesh.new()
	wall_bm.size = Vector3(2.0 * sh, wall_h, 0.18)
	wall.mesh = wall_bm
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.92, 0.92, 0.95)
	wall.material_override = wall_mat
	wall.position = Vector3(0.0, wall_h * 0.5 + 0.05,
		pit_z - pit_lane_width * 0.5 + 0.09)
	parent.add_child(wall)
	# Cyan accent stripe along the top of the wall.
	var accent := MeshInstance3D.new()
	accent.name = "PitWallAccent"
	var accent_bm := BoxMesh.new()
	accent_bm.size = Vector3(2.0 * sh, 0.10, 0.22)
	accent.mesh = accent_bm
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = _PIT_LANE_COLOR
	accent_mat.emission_enabled = true
	accent_mat.emission = _PIT_LANE_COLOR
	accent_mat.emission_energy_multiplier = 1.4
	accent.material_override = accent_mat
	accent.position = Vector3(0.0, wall_h + 0.10,
		pit_z - pit_lane_width * 0.5 + 0.09)
	parent.add_child(accent)

	# Centre-line dashes along the pit straight.
	var dash_count: int = 12
	for i in range(dash_count):
		var u: float = (float(i) + 0.5) / float(dash_count)
		var dash_x: float = lerpf(-sh + 0.4, sh - 0.4, u)
		var dash := MeshInstance3D.new()
		var dbm := BoxMesh.new()
		dbm.size = Vector3(0.5, 0.06, 0.10)
		dash.mesh = dbm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.85, 0.85, 0.90)
		dash.material_override = dmat
		dash.position = Vector3(dash_x, 0.07, pit_z)
		parent.add_child(dash)

	# Garage row NORTH of the pit lane (further from track). 1→11 bays
	# scaling with facility level, evenly spaced along the pit straight.
	var bays: int = clampi(1 + roundi((float(level) - 1.0) * 10.0
		/ float(maxi(Facilities.MAX_LEVEL - 1, 1))), 1, 11)
	var bay_w: float = 2.4
	var bay_d: float = 3.4 + float(level) * 0.05
	var bay_h: float = 2.6 + float(level) * 0.05
	var garage_z: float = pit_z + pit_lane_width * 0.5 + bay_d * 0.5 + 0.30
	for i in range(bays):
		var bay_p: float
		if bays == 1:
			bay_p = 0.5
		else:
			bay_p = float(i) / float(bays - 1)
		var bay_x: float = lerpf(-sh + bay_w * 0.6,
			sh - bay_w * 0.6, bay_p)
		# Garage body
		var garage := MeshInstance3D.new()
		var gbm := BoxMesh.new()
		gbm.size = Vector3(bay_w * 0.92, bay_h, bay_d)
		garage.mesh = gbm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = _PIT_LANE_COLOR.darkened(0.30)
		gmat.metallic = 0.3
		gmat.roughness = 0.6
		garage.material_override = gmat
		garage.position = Vector3(bay_x, bay_h * 0.5, garage_z)
		parent.add_child(garage)
		# Bright door panel facing the pit lane (south face).
		var door := MeshInstance3D.new()
		var dbm2 := BoxMesh.new()
		dbm2.size = Vector3(bay_w * 0.78, bay_h * 0.75, 0.06)
		door.mesh = dbm2
		var door_mat := StandardMaterial3D.new()
		door_mat.albedo_color = _PIT_LANE_COLOR
		door_mat.emission_enabled = true
		door_mat.emission = _PIT_LANE_COLOR
		door_mat.emission_energy_multiplier = 0.6
		door.material_override = door_mat
		door.position = Vector3(bay_x, bay_h * 0.4,
			garage_z - bay_d * 0.5 - 0.04)
		parent.add_child(door)

	# Paddock — flat asphalt slab behind the garages where teams park
	# their motorhomes. Spans the same X range as the pit straight.
	var paddock_d: float = 5.5 + float(level) * 0.08
	var paddock_z: float = garage_z + bay_d * 0.5 + paddock_d * 0.5 + 0.5
	var paddock := MeshInstance3D.new()
	paddock.name = "Paddock"
	var paddock_bm := BoxMesh.new()
	paddock_bm.size = Vector3(2.0 * sh + 1.0, 0.06, paddock_d)
	paddock.mesh = paddock_bm
	var paddock_mat := StandardMaterial3D.new()
	paddock_mat.albedo_color = Color(0.50, 0.52, 0.55)
	paddock_mat.roughness = 0.9
	paddock.material_override = paddock_mat
	paddock.position = Vector3(0.0, 0.04, paddock_z)
	parent.add_child(paddock)

	# Click area covers the whole pit complex.
	var click_z_center: float = (pit_z + paddock_z) * 0.5
	var click_z_size: float = (paddock_z + paddock_d * 0.5) \
		- (pit_z - pit_lane_width * 0.5) + 1.0
	_add_facility_click_area(parent, "pit_lane",
		Vector3(0, bay_h * 0.5, click_z_center),
		Vector3(2.0 * sh + 4.0, bay_h * 1.8, click_z_size))


func _build_lounge(parent: Node3D, level: int) -> void:
	# Multi-storey hospitality block with glass strips on three sides and
	# a roof terrace. Scales taller with level.
	var w: float = 5.0 + level * 0.18
	var d: float = 5.0 + level * 0.18
	var floors: int = clampi(2 + level / 3, 2, 6)
	var floor_h: float = 1.4
	var h: float = floor_h * float(floors) + 0.6
	# Sit BEHIND the grandstand AND the spectator concourse plaza on
	# the -Z side. Plaza centre is at _track_outer_z(9) with a depth
	# of 8, so the lounge front must clear _track_outer_z(14).
	const SAFETY: float = 14.0
	var pos := Vector3(0.0, h * 0.5, -_track_outer_z(SAFETY) - d * 0.5)

	# Main tower
	_make_box(parent, Vector3(w, h, d), pos, _LOUNGE_COLOR.darkened(0.15))

	# Glass strips on each floor (front + both sides).
	var glass_color := _LOUNGE_COLOR.lightened(0.30)
	for f in range(floors):
		var y_local: float = -h * 0.5 + 0.4 + (float(f) + 0.5) * floor_h
		# Front (facing +Z, toward track)
		_make_label_strip(parent, glass_color,
			pos + Vector3(0, y_local, d * 0.5 + 0.03),
			Vector3(w * 0.78, 0.55, 0.06))
		# Right side (+X)
		_make_label_strip(parent, glass_color,
			pos + Vector3(w * 0.5 + 0.03, y_local, 0),
			Vector3(0.06, 0.55, d * 0.78))
		# Left side (-X)
		_make_label_strip(parent, glass_color,
			pos + Vector3(-w * 0.5 - 0.03, y_local, 0),
			Vector3(0.06, 0.55, d * 0.78))

	# Roof terrace — a slightly inset platform with a railing.
	var terrace_y: float = pos.y + h * 0.5 + 0.06
	_make_box(parent, Vector3(w * 0.85, 0.12, d * 0.85),
		Vector3(pos.x, terrace_y, pos.z),
		_LOUNGE_COLOR.darkened(0.3))
	# Railing — four thin walls around the terrace.
	var rail_h: float = 0.45
	var ry: float = terrace_y + rail_h * 0.5 + 0.06
	_make_box(parent, Vector3(w * 0.85, rail_h, 0.05),
		Vector3(pos.x, ry, pos.z + d * 0.42), _LOUNGE_COLOR.lightened(0.2))
	_make_box(parent, Vector3(w * 0.85, rail_h, 0.05),
		Vector3(pos.x, ry, pos.z - d * 0.42), _LOUNGE_COLOR.lightened(0.2))
	_make_box(parent, Vector3(0.05, rail_h, d * 0.85),
		Vector3(pos.x + w * 0.42, ry, pos.z), _LOUNGE_COLOR.lightened(0.2))
	_make_box(parent, Vector3(0.05, rail_h, d * 0.85),
		Vector3(pos.x - w * 0.42, ry, pos.z), _LOUNGE_COLOR.lightened(0.2))

	# VIP beacon on top of the terrace.
	_make_label_strip(parent, _LOUNGE_COLOR,
		Vector3(pos.x, ry + rail_h, pos.z),
		Vector3(0.5, 0.5, 0.5))
	_add_facility_click_area(parent, "lounge", pos,
		Vector3(w * 1.1, h * 1.05, d * 1.1))


func _build_merch_shop(parent: Node3D, level: int) -> void:
	# Green kiosk at the +X end of the venue (other end from the
	# cafeteria — we leave +Z free for the pit complex).
	var w: float = 3.5 + level * 0.18
	var d: float = 3.0 + level * 0.14
	var h: float = 2.2 + level * 0.10
	# Awning extends w*0.4 toward the track from the building's near
	# edge, so anchor that NEAR edge of the awning at track_outer + safety.
	const SAFETY: float = 4.0
	var awning_extent: float = w * 0.4
	# pos.x = building center; building near edge = pos.x - w/2;
	# awning near edge = pos.x - w/2 - awning_extent
	# We want awning near edge = +track_outer + safety
	# => pos.x = track_outer + safety + awning_extent + w/2
	var pos := Vector3(_track_outer_x(SAFETY) + awning_extent + w * 0.5, h * 0.5, 0.0)
	_make_box(parent, Vector3(w, h, d), pos, _MERCH_COLOR.darkened(0.15))
	# Sign band on the side facing the track.
	_make_label_strip(parent, _MERCH_COLOR,
		pos + Vector3(-w * 0.5 - 0.05, h * 0.4, 0),
		Vector3(0.06, 0.30, d * 0.8))
	# Awning over the entrance (extends toward the track, -X).
	_make_box(parent, Vector3(w * 0.4, 0.08, d * 1.15),
		pos + Vector3(-w * 0.5 - w * 0.2, h * 0.55, 0),
		_MERCH_COLOR)
	_add_facility_click_area(parent, "merch_shop",
		pos + Vector3(-w * 0.2, 0, 0),
		Vector3(w * 1.6, h * 1.4, d * 1.2))


func _build_sponsor_boards(parent: Node3D, level: int) -> void:
	# Vertical billboards arranged along the OUTSIDE of the south loop.
	# We skip the north straight entirely (pit complex sits there) and
	# the very east/west extremes (cafeteria + merch shop are there).
	# Boards face inward toward the racing line.
	var board_count := mini(level * 2, 16)
	var asphalt_half: float = _track.current_asphalt_width() * 0.5
	var wave_amp: float = _track.current_wave_amp()
	var safe_offset: float = asphalt_half + wave_amp + 1.6
	var w := 2.6
	var h := 1.2
	for idx in range(board_count):
		# Spread along ψ ∈ [0.10π, 0.90π] of the south loop — centred on
		# the apex but skipping the very corners near the straight.
		var p: float = (float(idx) + 0.5) / float(board_count)
		var psi: float = lerpf(0.10 * PI, 0.90 * PI, p)
		var oval_pt: Vector3 = _track.oval_point(psi)
		var nrm: Vector2 = _track.oval_normal(psi)
		var x: float = oval_pt.x + nrm.x * safe_offset
		var z: float = oval_pt.z + nrm.y * safe_offset
		var color: Color = _SPONSOR_COLORS[idx % _SPONSOR_COLORS.size()]
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, 0.10)
		board.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.5
		mat.roughness = 0.4
		board.material_override = mat
		board.position = Vector3(x, 0.6 + h * 0.5, z)
		# Rotate the board so its face points back toward the racing line.
		board.rotation.y = atan2(-nrm.x, -nrm.y)
		parent.add_child(board)
		# Support post.
		_make_box(parent, Vector3(0.10, 0.6, 0.10),
			Vector3(x, 0.3, z), Color(0.18, 0.18, 0.20))
		# Click target per board so a tap opens the FACILITY tab.
		_add_facility_click_area(parent, "sponsor_boards",
			Vector3(x, 0.6, z),
			Vector3(w + 0.4, 1.6, 0.6))


func _build_lighting(parent: Node3D, level: int) -> void:
	# Tall poles + light fixtures arranged around the track footprint.
	# The track is asymmetric (north straight + south loop), so the
	# lighting ring is centred on the track's geometric centre rather
	# than the world origin. Otherwise +Z poles end up inside the pit
	# complex and -Z poles sit halfway through the south loop.
	var asphalt_half: float = _track.current_asphalt_width() * 0.5
	var wave_amp: float = _track.current_wave_amp()
	var safe_offset: float = asphalt_half + wave_amp + 2.0
	var loop_rx: float = _track_rx()
	var loop_depth: float = _track_rz()
	var center_z: float = _track.STRAIGHT_Z - loop_depth * 0.5
	var ring_x: float = loop_rx + safe_offset
	var ring_z: float = loop_depth * 0.5 + safe_offset
	var pole_count := mini(4 + (level - 1), 12)
	var pole_height := 6.0 + level * 0.15
	var positions: Array[Vector3] = []
	for i in range(pole_count):
		var t := float(i) / float(pole_count) * TAU + PI * 0.25
		var x := cos(t) * ring_x
		var z := center_z + sin(t) * ring_z
		positions.append(Vector3(x, 0, z))
	for p: Vector3 in positions:
		# Pole
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.10
		cyl.bottom_radius = 0.14
		cyl.height = pole_height
		pole.mesh = cyl
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.22, 0.22, 0.26)
		pole_mat.metallic = 0.8
		pole.material_override = pole_mat
		pole.position = p + Vector3(0, pole_height * 0.5, 0)
		parent.add_child(pole)
		# Light fixture (emissive box)
		var fix := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.18, 0.4)
		fix.mesh = bm
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.95, 0.95, 0.65)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.95, 0.6)
		fmat.emission_energy_multiplier = 1.5 + level * 0.12
		fix.material_override = fmat
		fix.position = p + Vector3(0, pole_height + 0.05, 0)
		# Aim slightly toward the centre.
		var to_centre := Vector3(-p.x, 0, -p.z).normalized()
		fix.rotation.y = atan2(to_centre.x, to_centre.z)
		parent.add_child(fix)
		# A festival flag on top of each pole — picks a colour from a
		# bright palette based on the pole index for a colourful skyline.
		var flag_color: Color = _FLAG_COLORS[positions.find(p) % _FLAG_COLORS.size()]
		_add_pole_flag(parent, p + Vector3(0, pole_height + 0.20, 0), flag_color)
		# Click target near the base of each pole.
		_add_facility_click_area(parent, "lighting",
			p + Vector3(0, pole_height * 0.5, 0),
			Vector3(1.2, pole_height + 0.4, 1.2))


func _build_grandstand(parent: Node3D, level: int) -> void:
	# Grandstands grow with the grandstand FACILITY level AND with the
	# track tier — a tier-4 venue's stands are bigger than a tier-1
	# venue's at the same facility level.
	var tier_scale: float = 1.0 + (_track.track_tier() - 1) * 0.30

	# Main stand on the spectator side (-Z), opposite the pit complex.
	# Anchor the FRONT (track-facing) edge at -(track_outer + safety)
	# so the bottom row never sits on the rumble strip at any tier.
	var main_w: float = (8.0 + level * 0.55) * tier_scale
	var main_d: float = 2.6 + level * 0.10
	var main_h: float = (1.2 + level * 0.18) * tier_scale
	const MAIN_SAFETY: float = 1.5
	var main_z: float = -_track_outer_z(MAIN_SAFETY) - main_d * 0.5
	_make_grandstand_block(parent, Vector3(0, 0, main_z),
		Vector3(main_w, main_h, main_d), level, false)

	# Side stands at the +X / -X ends from level 7+ (rotated 90°).
	if level >= 7:
		var side_levels: int = level - 6
		var side_w: float = (5.0 + side_levels * 0.4) * tier_scale
		var side_d: float = 2.4 + side_levels * 0.08
		var side_h: float = (1.0 + side_levels * 0.12) * tier_scale
		const SIDE_SAFETY: float = 1.5
		var side_x_offset: float = _track_outer_x(SIDE_SAFETY) + side_d * 0.5
		# West stand at -X end
		_make_grandstand_block(parent,
			Vector3(-side_x_offset, 0, 0),
			Vector3(side_d, side_h, side_w), side_levels, true)
		# East stand at +X end
		_make_grandstand_block(parent,
			Vector3(side_x_offset, 0, 0),
			Vector3(side_d, side_h, side_w), side_levels, true)

	# One large click area covering the main stand area.
	_add_facility_click_area(parent, "grandstand",
		Vector3(0, main_h * 0.5, main_z),
		Vector3(main_w * 1.1, main_h * 1.4, main_d * 1.4))


func _make_grandstand_block(parent: Node3D, center: Vector3, size: Vector3, level: int, rotated: bool) -> void:
	# `size` is interpreted in the stand's LOCAL frame:
	#   x = width (along the track edge)
	#   y = total stand height
	#   z = depth (front-to-back, away from track)
	# When `rotated == true` we swap x and z so the stand runs along
	# the track's perpendicular axis instead.
	var rows: int = clampi(3 + level / 2, 3, 7)
	var row_depth: float = size.z / float(rows)
	var row_y_step: float = size.y / float(rows)
	# Track is at lower |z| than the grandstand (which sits at center.z
	# more-negative-than the track). So the row CLOSEST to the track is
	# at the most-positive local z, and rows step BACK in -local-z as
	# they go higher. (For the side stands `rotated == true`, the same
	# logic is mapped onto local x via the x/z swap further down.)
	for r in range(rows):
		var row_y: float = 0.20 + (float(r) + 0.5) * row_y_step
		var row_local_z: float = size.z * 0.5 - (float(r) + 0.5) * row_depth
		var row_size: Vector3
		var row_offset: Vector3
		if rotated:
			row_size = Vector3(row_depth * 0.95, row_y_step, size.x)
			row_offset = Vector3(-row_local_z, row_y, 0)
		else:
			row_size = Vector3(size.x, row_y_step, row_depth * 0.95)
			row_offset = Vector3(0, row_y, row_local_z)
		_make_box(parent, row_size, center + row_offset,
			_GRANDSTAND_COLOR.darkened(float(r) * 0.07))

	# Roof over the BACK rows (away from the track). For the unrotated
	# case the back is at -local-z; for rotated, +local-x.
	if level >= 5:
		var roof_thickness: float = 0.18
		var roof_y: float = size.y + 0.85
		var roof_size: Vector3
		var roof_offset: Vector3
		if rotated:
			roof_size = Vector3(size.z * 0.65, roof_thickness, size.x * 1.05)
			roof_offset = Vector3(-size.z * 0.18, roof_y, 0)
		else:
			roof_size = Vector3(size.x * 1.05, roof_thickness, size.z * 0.65)
			roof_offset = Vector3(0, roof_y, -size.z * 0.18)
		_make_box(parent, roof_size, center + roof_offset,
			_GRANDSTAND_COLOR.darkened(0.5))
		# Front edge of the roof (the side facing the track) gets an
		# accent stripe.
		var stripe_size: Vector3
		var stripe_offset: Vector3
		if rotated:
			stripe_size = Vector3(0.04, 0.10, size.x * 1.05)
			stripe_offset = Vector3(-size.z * 0.18 + size.z * 0.32, roof_y - 0.15, 0)
		else:
			stripe_size = Vector3(size.x * 1.05, 0.10, 0.04)
			stripe_offset = Vector3(0, roof_y - 0.15, -size.z * 0.18 + size.z * 0.32)
		_make_label_strip(parent, _GRANDSTAND_COLOR.lightened(0.3),
			center + stripe_offset, stripe_size)


func _build_parking(parent: Node3D, level: int) -> void:
	# A flat asphalt slab outside the venue with painted parking-space
	# lines and a few visiting cars. Sits in the (-X, -Z) corner so it
	# doesn't fight any other facility for space.

	# More rows / cols as the lot is upgraded.
	var rows: int = clampi(2 + level / 6, 2, 12)
	var cols: int = clampi(5 + level / 4, 5, 22)
	var space_w: float = 1.6
	var space_d: float = 2.8
	var lot_w: float = float(cols) * space_w
	var lot_d: float = float(rows) * space_d
	# Anchor against track outer + safety so it never overlaps the
	# track at any tier.
	const SAFETY_X: float = 5.0
	const SAFETY_Z: float = 4.0
	var center := Vector3(
		-_track_outer_x(SAFETY_X) - lot_w * 0.5,
		0.05,
		-_track_outer_z(SAFETY_Z) - lot_d * 0.5
	)

	# Asphalt slab.
	_make_box(parent, Vector3(lot_w, 0.10, lot_d),
		center, Color(0.10, 0.11, 0.14))

	# White line markings — vertical slot dividers.
	for c in range(cols + 1):
		var x: float = center.x - lot_w * 0.5 + float(c) * space_w
		_make_box(parent, Vector3(0.06, 0.04, lot_d * 0.95),
			Vector3(x, 0.12, center.z), Color(0.85, 0.85, 0.90))
	# Horizontal row dividers (just one between each row, plus the back).
	for r in range(rows + 1):
		var z: float = center.z - lot_d * 0.5 + float(r) * space_d
		_make_box(parent, Vector3(lot_w * 0.95, 0.04, 0.06),
			Vector3(center.x, 0.12, z), Color(0.85, 0.85, 0.90))

	# A blue accent strip along the front edge so the lot reads as
	# "parking" colour-wise alongside the other facility colours.
	_make_label_strip(parent, _PARKING_COLOR,
		Vector3(center.x, 0.20, center.z + lot_d * 0.5 + 0.15),
		Vector3(lot_w * 0.4, 0.30, 0.10))

	# Parked cars — about 50% occupancy at the current level. Use a
	# seeded RNG so the layout is stable across rebuilds.
	var max_cars: int = (rows * cols)
	var occupancy: int = mini(level * 3, max_cars / 2 + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = level * 7919 + 13
	var taken := {}
	var attempts: int = 0
	while taken.size() < occupancy and attempts < occupancy * 4:
		attempts += 1
		var r: int = rng.randi() % rows
		var c: int = rng.randi() % cols
		var key: String = "%d_%d" % [r, c]
		if taken.has(key):
			continue
		taken[key] = true
		var car_x: float = center.x - lot_w * 0.5 + float(c) * space_w + space_w * 0.5
		var car_z: float = center.z - lot_d * 0.5 + float(r) * space_d + space_d * 0.5
		var car_color := Color(
			rng.randf_range(0.30, 1.0),
			rng.randf_range(0.30, 1.0),
			rng.randf_range(0.30, 1.0)
		)
		# Car body
		_make_box(parent,
			Vector3(space_w * 0.7, 0.45, space_d * 0.78),
			Vector3(car_x, 0.40, car_z),
			car_color)
		# Windshield (darker top)
		_make_box(parent,
			Vector3(space_w * 0.6, 0.30, space_d * 0.4),
			Vector3(car_x, 0.65, car_z - space_d * 0.05),
			car_color.darkened(0.45))

	# Click target covering the whole lot.
	_add_facility_click_area(parent, "parking",
		Vector3(center.x, 1.0, center.z),
		Vector3(lot_w + 1.0, 2.0, lot_d + 1.0))


func _build_marketing(parent: Node3D, level: int) -> void:
	# Marketing tower: tall pole with a glowing billboard at the top.
	# Sits at the (+X, -Z) SE corner — north +Z is reserved for the
	# pit complex, so the tower goes opposite the parking lot at the
	# south-east corner of the venue.
	var pole_h: float = 5.5 + float(level) * 0.35
	const SAFETY: float = 3.5
	var pos := Vector3(_track_outer_x(SAFETY), 0.0,
		-_track_outer_z(SAFETY))

	# Pole (dark metal)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.30, pole_h, 0.30)
	pole.mesh = pole_mesh
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.18, 0.18, 0.22)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.5
	pole.material_override = pole_mat
	pole.position = pos + Vector3(0, pole_h * 0.5, 0)
	parent.add_child(pole)

	# Billboard (emissive — looks like an LED display).
	var bw: float = 3.0 + float(level) * 0.15
	var bh: float = 1.8 + float(level) * 0.08
	var board := MeshInstance3D.new()
	board.name = "Billboard"
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(bw, bh, 0.20)
	board.mesh = board_mesh
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = _MARKETING_COLOR
	board_mat.emission_enabled = true
	board_mat.emission = _MARKETING_COLOR
	board_mat.emission_energy_multiplier = 1.6 + float(level) * 0.02
	board.material_override = board_mat
	board.position = pos + Vector3(0, pole_h + bh * 0.5, 0)
	# Aim the billboard face toward the centre of the venue so it
	# always reads correctly from above.
	var to_centre: Vector3 = (-pos).normalized()
	board.rotation.y = atan2(to_centre.x, to_centre.z)
	parent.add_child(board)

	# Side panel (a second smaller billboard at 90° on the same pole
	# — gives the tower visual presence at higher levels).
	if level >= 4:
		var side_w: float = bw * 0.65
		var side_h: float = bh * 0.55
		var side := MeshInstance3D.new()
		side.name = "SideBoard"
		var side_mesh := BoxMesh.new()
		side_mesh.size = Vector3(side_w, side_h, 0.18)
		side.mesh = side_mesh
		var side_mat := StandardMaterial3D.new()
		side_mat.albedo_color = _MARKETING_COLOR.lightened(0.25)
		side_mat.emission_enabled = true
		side_mat.emission = _MARKETING_COLOR
		side_mat.emission_energy_multiplier = 1.2
		side.material_override = side_mat
		side.position = pos + Vector3(0, pole_h + bh * 0.4, 0)
		side.rotation.y = atan2(to_centre.x, to_centre.z) + PI * 0.5
		parent.add_child(side)

	# Click target covers the whole tower volume.
	_add_facility_click_area(parent, "marketing",
		pos + Vector3(0, (pole_h + bh) * 0.5, 0),
		Vector3(maxf(bw, 1.0) + 0.6, pole_h + bh + 0.6, maxf(bw, 1.0) + 0.6))


# ---------------------------------------------------------------------------
# Permanent decoration: ticket booth, walkways, trees
# ---------------------------------------------------------------------------
const _WALKWAY_COLOR := Color(0.55, 0.54, 0.50)        # concrete grey
const _ROAD_COLOR    := Color(0.13, 0.14, 0.18)        # asphalt road
const _TICKET_COLOR  := Color(0.95, 0.85, 0.30)        # bright yellow
const _TREE_TRUNK    := Color(0.40, 0.26, 0.14)
const _TREE_FOLIAGE  := Color(0.30, 0.65, 0.28)


# Hub position — the venue's "ticket booth" sits here, and every
# walkway radiates from it. Placed south of the track, close enough
# to be a natural funnel point but well clear of the asphalt.
func _hub_position() -> Vector3:
	# Centred between the grandstand back (~track_outer+4) and the
	# lounge front (~track_outer+14) — leaves room for an 8m-deep
	# concourse plaza without overlapping either neighbour.
	return Vector3(0.0, 0.0, -_track_outer_z(9.0))


func _build_ticket_booth(parent: Node3D) -> void:
	var pos := _hub_position()
	var w: float = 3.4
	var h: float = 3.0
	var d: float = 2.6
	# Booth body
	_make_box(parent, Vector3(w, h, d),
		pos + Vector3(0, h * 0.5, 0),
		Color(0.92, 0.92, 0.95))
	# Roof overhang
	_make_box(parent, Vector3(w * 1.25, 0.18, d * 1.25),
		pos + Vector3(0, h + 0.10, 0),
		_TICKET_COLOR.darkened(0.3))
	# Lit "TICKETS" sign band on the front (track-facing side, +Z).
	_make_label_strip(parent, _TICKET_COLOR,
		pos + Vector3(0, h * 0.7, d * 0.5 + 0.05),
		Vector3(w * 0.85, 0.45, 0.06))
	# Service window — dark slot below the sign.
	_make_box(parent, Vector3(w * 0.5, 0.6, 0.06),
		pos + Vector3(0, h * 0.42, d * 0.5 + 0.04),
		Color(0.10, 0.10, 0.13))
	# Two simple turnstiles in front of the booth on the +Z side.
	for sx: float in [-0.7, 0.7]:
		_make_box(parent, Vector3(0.18, 1.1, 0.18),
			pos + Vector3(sx, 0.55, d * 0.5 + 0.6),
			Color(0.4, 0.4, 0.45))


func _build_walkways(parent: Node3D) -> void:
	# Wide concourse running the full venue width on the spectator side,
	# with short branches to each facility entrance and a proper road
	# out to the parking lot. This way EVERY facility visibly connects
	# to the same network and there are no floating walkway stubs.
	var hub: Vector3 = _hub_position()

	# Plaza spans the venue width (from -X cafeteria to +X merch shop)
	# so it touches the front of every south-side facility.
	var plaza_w: float = _track_outer_x(0.0) * 2.0 + 6.0
	var plaza_d: float = 8.0
	var plaza_z: float = hub.z
	var plaza := MeshInstance3D.new()
	plaza.name = "Concourse"
	var pbm := BoxMesh.new()
	pbm.size = Vector3(plaza_w, 0.06, plaza_d)
	plaza.mesh = pbm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = _WALKWAY_COLOR
	pmat.roughness = 0.85
	plaza.material_override = pmat
	plaza.position = Vector3(0.0, 0.04, plaza_z)
	parent.add_child(plaza)

	# Light accent stripes along the front and back edges of the plaza.
	_make_label_strip(parent, _WALKWAY_COLOR.lightened(0.4),
		Vector3(0.0, 0.10, plaza_z + plaza_d * 0.5 + 0.05),
		Vector3(plaza_w * 0.95, 0.06, 0.10))
	_make_label_strip(parent, _WALKWAY_COLOR.lightened(0.4),
		Vector3(0.0, 0.10, plaza_z - plaza_d * 0.5 - 0.05),
		Vector3(plaza_w * 0.95, 0.06, 0.10))

	# Short walkway from plaza forward to the grandstand entrance.
	var grandstand_entrance := Vector3(0.0, 0.04, -_track_outer_z(1.5))
	_make_road(parent, Vector3(0.0, 0.04, plaza_z + plaza_d * 0.5),
		grandstand_entrance, 3.0, _WALKWAY_COLOR)

	# Branch walkways from the back of the plaza to each south-side
	# facility's footprint, so the whole network reads as connected.
	# Cafeteria sits at -X side: branch goes to its patio edge.
	var cafe_branch := Vector3(-_track_outer_x(2.0), 0.04, plaza_z - plaza_d * 0.5)
	_make_road(parent, Vector3(-plaza_w * 0.45, 0.04, plaza_z - plaza_d * 0.5),
		cafe_branch, 2.2, _WALKWAY_COLOR)
	# Merch shop sits at +X side.
	var merch_branch := Vector3(_track_outer_x(2.0), 0.04, plaza_z - plaza_d * 0.5)
	_make_road(parent, Vector3(plaza_w * 0.45, 0.04, plaza_z - plaza_d * 0.5),
		merch_branch, 2.2, _WALKWAY_COLOR)
	# Lounge sits directly behind the plaza — a short stub from the
	# plaza back-edge meets the lounge entrance.
	var lounge_branch := Vector3(0.0, 0.04, -_track_outer_z(13.5))
	_make_road(parent, Vector3(0.0, 0.04, plaza_z - plaza_d * 0.5),
		lounge_branch, 2.6, _WALKWAY_COLOR)

	# Asphalt road from parking lot to the plaza. Plaza west edge is
	# at x=-plaza_w/2; the parking lot's NE corner is the natural
	# entry point. Two axis-aligned legs joined at a clear elbow so
	# the junction reads as a road, not a diagonal scar.
	var plaza_west := Vector3(-plaza_w * 0.5, 0.04, plaza_z)
	var parking_entry := Vector3(
		-_track_outer_x(5.0),
		0.04,
		-_track_outer_z(4.0))
	var elbow := Vector3(parking_entry.x, 0.04, plaza_z)
	_make_road(parent, plaza_west, elbow, 3.5, _ROAD_COLOR)
	_make_road(parent, elbow, parking_entry, 3.5, _ROAD_COLOR)

	# Spectator crowd CLAMPED to plaza interior only. Three small
	# clusters spread across the plaza width — none stray onto the
	# track-side walkway or onto the rumble strip.
	var crowd_radius: float = minf(plaza_d * 0.30, 2.4)
	_add_spectators(parent,
		Vector3(-plaza_w * 0.30, 0.0, plaza_z), crowd_radius, 6, 4711)
	_add_spectators(parent,
		Vector3( plaza_w * 0.30, 0.0, plaza_z), crowd_radius, 6, 4712)
	_add_spectators(parent,
		Vector3(0.0, 0.0, plaza_z), crowd_radius, 6, 4713)


func _make_road(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	# Single rectangular slab between two points (in the XZ plane).
	var direction := Vector3(b.x - a.x, 0, b.z - a.z)
	var length: float = direction.length()
	if length < 0.05:
		return
	var center := (a + b) * 0.5
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.06, width)
	slab.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	slab.material_override = mat
	slab.position = Vector3(center.x, 0.04, center.z)
	# Long axis (local +X) aligned with direction
	slab.rotation.y = atan2(-direction.z, direction.x)
	parent.add_child(slab)


func _build_trees(parent: Node3D) -> void:
	# Decorative trees scattered around the venue. Like the lighting
	# ring, this is centred on the track's geometric centre so trees
	# don't end up inside the pit complex on the +Z side.
	var loop_rx: float = _track.current_rx()
	var loop_depth: float = _track.current_rz()
	var center_z: float = _track.STRAIGHT_Z - loop_depth * 0.5
	var ring_x: float = _track_outer_x(18.0)
	var ring_z: float = (loop_depth * 0.5) + 14.0 + _track.current_wave_amp()
	var rng := RandomNumberGenerator.new()
	rng.seed = 19370 + int(_track.track_tier())
	var tree_count: int = 24
	for i in range(tree_count):
		var t: float = (float(i) + rng.randf_range(-0.1, 0.1)) / float(tree_count) * TAU
		var jitter_r: float = rng.randf_range(0.0, 6.0)
		var x: float = cos(t) * (ring_x + jitter_r)
		var z: float = center_z + sin(t) * (ring_z + jitter_r)
		var height: float = rng.randf_range(3.5, 5.5)
		_make_tree(parent, Vector3(x, 0.0, z), height, rng)
	# Suppress unused-variable warning for loop_rx (kept for clarity).
	if loop_rx > 0.0:
		pass


func _make_tree(parent: Node3D, base_pos: Vector3, height: float, rng: RandomNumberGenerator) -> void:
	# Trunk: short cylinder
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = height * 0.40
	trunk.mesh = trunk_mesh
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = _TREE_TRUNK
	trunk_mat.roughness = 0.95
	trunk.material_override = trunk_mat
	trunk.position = base_pos + Vector3(0, height * 0.20, 0)
	parent.add_child(trunk)
	# Foliage: cone (cylinder with zero top radius).
	var foliage := MeshInstance3D.new()
	foliage.name = "Foliage"
	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius = 0.05
	foliage_mesh.bottom_radius = height * 0.32
	foliage_mesh.height = height * 0.70
	foliage.mesh = foliage_mesh
	var foliage_mat := StandardMaterial3D.new()
	# Slightly randomise foliage shade so the grove isn't uniform.
	var shade: float = rng.randf_range(-0.06, 0.06)
	foliage_mat.albedo_color = Color(
		clampf(_TREE_FOLIAGE.r + shade, 0.0, 1.0),
		clampf(_TREE_FOLIAGE.g + shade, 0.0, 1.0),
		clampf(_TREE_FOLIAGE.b + shade, 0.0, 1.0),
	)
	foliage_mat.roughness = 0.95
	foliage.material_override = foliage_mat
	foliage.position = base_pos + Vector3(0, height * 0.40 + height * 0.35, 0)
	parent.add_child(foliage)


# ---------------------------------------------------------------------------
# Cartoon-style spectators (small coloured figures clustered around a centre)
# ---------------------------------------------------------------------------
const _SPECTATOR_SHIRTS: Array[Color] = [
	Color(0.95, 0.30, 0.30),  # red
	Color(0.30, 0.55, 0.95),  # blue
	Color(0.95, 0.85, 0.30),  # yellow
	Color(0.45, 0.85, 0.40),  # green
	Color(0.85, 0.45, 0.95),  # purple
	Color(0.95, 0.65, 0.30),  # orange
	Color(0.95, 0.95, 0.95),  # white
	Color(0.20, 0.85, 0.85),  # cyan
]
const _SPECTATOR_SKIN: Color = Color(0.95, 0.78, 0.62)


func _add_spectators(parent: Node3D, center: Vector3, radius: float, count: int, seed_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_id
	for i in range(count):
		var angle: float = rng.randf_range(0.0, TAU)
		var r: float = rng.randf_range(0.3, radius)
		var x: float = center.x + cos(angle) * r
		var z: float = center.z + sin(angle) * r
		var shirt: Color = _SPECTATOR_SHIRTS[rng.randi() % _SPECTATOR_SHIRTS.size()]
		# Body — colored capsule
		var body := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.18
		bm.bottom_radius = 0.22
		bm.height = 0.65
		body.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = shirt
		bmat.roughness = 0.9
		body.material_override = bmat
		body.position = Vector3(x, 0.32, z)
		parent.add_child(body)
		# Head — small skin-coloured sphere
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.14
		hm.height = 0.28
		head.mesh = hm
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = _SPECTATOR_SKIN
		hmat.roughness = 0.85
		head.material_override = hmat
		head.position = Vector3(x, 0.79, z)
		parent.add_child(head)


# ---------------------------------------------------------------------------
# Festival flag — small bright cube on top of a vertical pole.
# ---------------------------------------------------------------------------
const _FLAG_COLORS: Array[Color] = [
	Color(0.95, 0.30, 0.30),
	Color(0.30, 0.55, 0.95),
	Color(0.95, 0.85, 0.30),
	Color(0.45, 0.85, 0.40),
	Color(0.85, 0.45, 0.95),
	Color(0.95, 0.65, 0.30),
]


func _add_pole_flag(parent: Node3D, top_pos: Vector3, color: Color) -> void:
	var flag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.4, 0.04)
	flag.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	flag.material_override = mat
	# Offset so the flag flies to the side of the pole
	flag.position = top_pos + Vector3(0.30, 0.10, 0)
	parent.add_child(flag)
