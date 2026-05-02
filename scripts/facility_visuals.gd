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
	return _track.current_rx() + _track.current_asphalt_width() * 0.5 \
		+ _track.current_wave_amp() + _RUMBLE_INSET_VAL + margin

func _track_outer_z(margin: float = 0.0) -> float:
	return _track.current_rz() + _track.current_asphalt_width() * 0.5 \
		+ _track.current_wave_amp() + _RUMBLE_INSET_VAL + margin

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
	_make_box(parent, Vector3(w, h, d), building_pos, _CAFETERIA_COLOR.darkened(0.55))

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
	# Pit complex: a SECOND ASPHALT STRIP that follows the same curve
	# as the main track on the +Z side, branching off at one corner,
	# arcing outward, and merging back at the other corner — exactly
	# how a real F1 pit lane comes out of and back into the racing
	# line. Built with two CSGPolygon3D extrusions along a custom
	# Path3D so the shape is genuinely curved (no diagonal stitching).
	var rx := _track_rx()
	var rz := _track_rz()
	var asphalt_color := Color(0.10, 0.11, 0.14)

	# Width grows with facility level; the lane covers the +Z arc of
	# the oval from t_start to t_end (centered at π/2 = top of oval).
	var pit_lane_width: float = 2.6 + float(level) * 0.06
	# Maximum outward offset at the apex of the pit curve. Real F1
	# circuits have at least ~5m of grass between the racing line and
	# the pit wall (Red Bull Ring, Spa, etc.) — anything closer reads
	# as "the pit is on the track". So bump APEX_GAP substantially.
	var wave_amp: float = _track.current_wave_amp()
	var asphalt_outer: float = _track.current_asphalt_width() * 0.5 \
		+ wave_amp + _RUMBLE_INSET_VAL
	var apex_gap: float = 3.5 + wave_amp * 0.5
	var max_offset: float = asphalt_outer + pit_lane_width * 0.5 + apex_gap
	# Arc range covers ~130° centred on the +Z apex (90°). 25°..155° is
	# wide enough that, with our 5% merge ramps, every chicane wave-peak
	# at every tier falls inside the FULL-OFFSET plateau (verified
	# numerically across all 10 tiers / wave frequencies).
	var t_start: float = deg_to_rad(25.0)
	var t_end: float = deg_to_rad(155.0)
	var t_range: float = t_end - t_start
	var segments: int = 64

	# Build the curved Path3D for the pit lane. At each sample we offset
	# the oval point outward by a TRAPEZOIDAL profile (smoothstep ramp
	# in the first 5% / out the last 5%, plateau at the full max_offset
	# in between). This keeps the lane safely outside the asphalt for
	# 90% of the arc and only tapers at the very ends to merge cleanly.
	var pit_path := Path3D.new()
	pit_path.name = "PitPath"
	parent.add_child(pit_path)
	var pit_curve := Curve3D.new()
	var pit_centers: Array[Vector3] = []
	var pit_normals: Array[Vector2] = []
	var pit_t_values: Array[float] = []
	for i in range(segments + 1):
		var p: float = float(i) / float(segments)
		var t: float = t_start + p * t_range
		var oval_pt := Vector3(rx * cos(t), 0.0, rz * sin(t))
		var n := Vector2(rz * cos(t), rx * sin(t)).normalized()
		# Trapezoidal: ramps 0→1 over p∈[0,0.05], plateau at 1, ramps
		# 1→0 over p∈[0.95,1].
		var ramp_in: float = smoothstep(0.0, 0.05, p)
		var ramp_out: float = 1.0 - smoothstep(0.95, 1.0, p)
		var offset_factor: float = ramp_in * ramp_out
		var offset_amt: float = offset_factor * max_offset
		var center := Vector3(
			oval_pt.x + n.x * offset_amt,
			0.0,
			oval_pt.z + n.y * offset_amt)
		pit_curve.add_point(center)
		pit_centers.append(center)
		pit_normals.append(n)
		pit_t_values.append(t)
	pit_path.curve = pit_curve

	# Pit asphalt — extruded along the curve as a CSGPolygon3D, same
	# technique as the main track's asphalt strip.
	var pit_csg := CSGPolygon3D.new()
	pit_csg.name = "PitAsphalt"
	pit_csg.mode = CSGPolygon3D.MODE_PATH
	pit_csg.path_node = pit_path.get_path()
	pit_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	pit_csg.path_interval = 0.5
	pit_csg.path_joined = false
	pit_csg.polygon = PackedVector2Array([
		Vector2(-pit_lane_width * 0.5, 0.06),
		Vector2( pit_lane_width * 0.5, 0.06),
		Vector2( pit_lane_width * 0.5, -0.04),
		Vector2(-pit_lane_width * 0.5, -0.04),
	])
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = asphalt_color
	pit_mat.roughness = 0.85
	pit_csg.material_override = pit_mat
	parent.add_child(pit_csg)

	# Pit wall — a thin strip along the SAME curve, on the inner side
	# (the side facing the track). Built as another CSGPolygon3D so it
	# bends with the curve.
	var wall_h: float = 0.55
	var wall_csg := CSGPolygon3D.new()
	wall_csg.name = "PitWall"
	wall_csg.mode = CSGPolygon3D.MODE_PATH
	wall_csg.path_node = pit_path.get_path()
	wall_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	wall_csg.path_interval = 0.5
	wall_csg.path_joined = false
	# Inner side of pit lane = -X in the path's local frame. The wall is
	# a thin vertical slab there.
	wall_csg.polygon = PackedVector2Array([
		Vector2(-pit_lane_width * 0.5 - 0.18, wall_h),
		Vector2(-pit_lane_width * 0.5,        wall_h),
		Vector2(-pit_lane_width * 0.5,        0.06),
		Vector2(-pit_lane_width * 0.5 - 0.18, 0.06),
	])
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.92, 0.92, 0.95)
	wall_csg.material_override = wall_mat
	parent.add_child(wall_csg)

	# Cyan accent strip on top of the pit wall, also extruded along the curve.
	var accent_csg := CSGPolygon3D.new()
	accent_csg.name = "PitWallAccent"
	accent_csg.mode = CSGPolygon3D.MODE_PATH
	accent_csg.path_node = pit_path.get_path()
	accent_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	accent_csg.path_interval = 0.5
	accent_csg.path_joined = false
	accent_csg.polygon = PackedVector2Array([
		Vector2(-pit_lane_width * 0.5 - 0.20, wall_h + 0.10),
		Vector2(-pit_lane_width * 0.5 + 0.02, wall_h + 0.10),
		Vector2(-pit_lane_width * 0.5 + 0.02, wall_h),
		Vector2(-pit_lane_width * 0.5 - 0.20, wall_h),
	])
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = _PIT_LANE_COLOR
	accent_mat.emission_enabled = true
	accent_mat.emission = _PIT_LANE_COLOR
	accent_mat.emission_energy_multiplier = 1.4
	accent_csg.material_override = accent_mat
	parent.add_child(accent_csg)

	# Centre line dashes along the curve.
	var dash_count: int = 14
	for i in range(dash_count):
		var u: float = (float(i) + 0.5) / float(dash_count)
		var idx: int = clampi(int(u * float(segments)), 0, pit_centers.size() - 1)
		var c: Vector3 = pit_centers[idx]
		var n: Vector2 = pit_normals[idx]
		# Orient the dash along the curve tangent (perpendicular to normal).
		var tangent_dir := Vector2(-n.y, n.x)  # 90° CCW from normal
		var dash := MeshInstance3D.new()
		var dbm := BoxMesh.new()
		dbm.size = Vector3(0.5, 0.10, 0.10)
		dash.mesh = dbm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.85, 0.85, 0.90)
		dash.material_override = dmat
		dash.position = Vector3(c.x, 0.10, c.z)
		dash.rotation.y = atan2(-tangent_dir.y, tangent_dir.x)
		parent.add_child(dash)

	# Garage row on the OUTSIDE of the curve, evenly spaced along the
	# middle 60% of the arc (skip the merge ends). 1 → 11 bays scaling
	# with the pit-lane level.
	var bays: int = clampi(1 + roundi((float(level) - 1.0) * 10.0
		/ float(maxi(Facilities.MAX_LEVEL - 1, 1))), 1, 11)
	var bay_w: float = 2.6
	var bay_d: float = 3.4 + float(level) * 0.05
	var bay_h: float = 2.6 + float(level) * 0.05
	for i in range(bays):
		var p: float
		if bays == 1:
			p = 0.5
		else:
			p = 0.2 + float(i) / float(bays - 1) * 0.6
		var idx: int = clampi(int(p * float(segments)), 0, pit_centers.size() - 1)
		var center: Vector3 = pit_centers[idx]
		var n: Vector2 = pit_normals[idx]
		# Garage centre = pit centre + outward normal * (pit_w/2 + bay_d/2 + small gap)
		var radial_offset: float = pit_lane_width * 0.5 + bay_d * 0.5 + 0.30
		var garage_pos := Vector3(
			center.x + n.x * radial_offset,
			bay_h * 0.5,
			center.z + n.y * radial_offset)
		# Rotation so bay_w (size.x) runs ALONG the curve tangent and
		# bay_d (size.z) runs OUTWARD along the normal.
		var rot_y: float = atan2(float(rz) * cos(pit_t_values[idx]),
			float(rx) * sin(pit_t_values[idx]))
		# Garage body
		var garage := MeshInstance3D.new()
		var gbm := BoxMesh.new()
		gbm.size = Vector3(bay_w * 0.95, bay_h, bay_d)
		garage.mesh = gbm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = _PIT_LANE_COLOR.darkened(0.65)
		gmat.metallic = 0.3
		gmat.roughness = 0.6
		garage.material_override = gmat
		garage.position = garage_pos
		garage.rotation.y = rot_y
		parent.add_child(garage)
		# Open door panel facing the pit lane (-Z in local frame).
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
		door.position = garage_pos + Vector3(-n.x * (bay_d * 0.5 + 0.04), 0, -n.y * (bay_d * 0.5 + 0.04))
		door.position.y = bay_h * 0.4
		door.rotation.y = rot_y
		parent.add_child(door)

	# Paddock area BEHIND the garages — flat asphalt slab where in real
	# F1 the team trucks / motorhomes / equipment sit. Built as a
	# CSGPolygon3D extruded along the same curve, on the outer side.
	var paddock_w: float = 5.5 + float(level) * 0.08
	var paddock_inner: float = pit_lane_width * 0.5 + bay_d + 0.5
	var paddock_csg := CSGPolygon3D.new()
	paddock_csg.name = "Paddock"
	paddock_csg.mode = CSGPolygon3D.MODE_PATH
	paddock_csg.path_node = pit_path.get_path()
	paddock_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	paddock_csg.path_interval = 0.5
	paddock_csg.path_joined = false
	paddock_csg.polygon = PackedVector2Array([
		Vector2(paddock_inner,             0.04),
		Vector2(paddock_inner + paddock_w, 0.04),
		Vector2(paddock_inner + paddock_w, -0.03),
		Vector2(paddock_inner,             -0.03),
	])
	var paddock_mat := StandardMaterial3D.new()
	paddock_mat.albedo_color = Color(0.16, 0.17, 0.20)
	paddock_mat.roughness = 0.9
	paddock_csg.material_override = paddock_mat
	parent.add_child(paddock_csg)

	# Click area: rough bounding box centred on the apex of the pit curve.
	var apex: Vector3 = pit_centers[pit_centers.size() / 2]
	var click_size := Vector3(rx * 1.6, bay_h * 1.8,
		max_offset + bay_d + paddock_w + 4.0)
	_add_facility_click_area(parent, "pit_lane",
		Vector3(0, bay_h * 0.5, apex.z * 0.5),
		click_size)


func _build_lounge(parent: Node3D, level: int) -> void:
	# Multi-storey hospitality block with glass strips on three sides and
	# a roof terrace. Scales taller with level.
	var w: float = 5.0 + level * 0.18
	var d: float = 5.0 + level * 0.18
	var floors: int = clampi(2 + level / 3, 2, 6)
	var floor_h: float = 1.4
	var h: float = floor_h * float(floors) + 0.6
	# Sit BEHIND the grandstand on the -Z spectator side, with enough
	# margin that the grandstand has room between the lounge and track.
	const SAFETY: float = 9.0
	var pos := Vector3(0.0, h * 0.5, -_track_outer_z(SAFETY) - d * 0.5)

	# Main tower
	_make_box(parent, Vector3(w, h, d), pos, _LOUNGE_COLOR.darkened(0.55))

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
	_make_box(parent, Vector3(w, h, d), pos, _MERCH_COLOR.darkened(0.55))
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
	# Vertical billboards arranged around the outside of the rumble strip,
	# but ONLY along the long sides (top and bottom of the oval). The
	# narrow ends (-X cafeteria, +X merch shop) are left clear so they
	# don't visually merge with the buildings parked there.
	var board_count := mini(level * 2, 16)
	# Sit boards outside the actual asphalt extent (track wave amplitude
	# + asphalt half-width + a margin) so the support posts never sit
	# on the rumble strip even on a tier-4 chicane circuit.
	var t_tier: int = _track.track_tier()
	var safe_offset: float = _track.TIER_WAVE_AMP[t_tier] \
		+ _track.TIER_ASPHALT_WIDTH[t_tier] * 0.5 + 1.6
	var rx := _track_rx() + safe_offset
	var rz := _track_rz() + safe_offset
	var w := 2.6
	var h := 1.2
	# Distribute boards along the two long arcs only — angle range
	# 30°..150° (top arc) and 210°..330° (bottom arc), skipping the ends.
	var per_arc: int = maxi(1, board_count / 2)
	var positions: Array[Vector2] = []
	for arc_offset: float in [0.0, PI]:
		for i in range(per_arc):
			# Spread evenly across the 120°-wide arc.
			var local_t: float = (float(i) + 0.5) / float(per_arc)
			var t: float = arc_offset + PI / 6.0 + local_t * (2.0 * PI / 3.0)
			positions.append(Vector2(cos(t) * rx, sin(t) * rz))
	for idx in range(positions.size()):
		var pos2 := positions[idx]
		var x: float = pos2.x
		var z: float = pos2.y
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
		# Rotate the board so its face points toward the track centre.
		var to_centre := Vector3(-x, 0, -z).normalized()
		board.rotation.y = atan2(to_centre.x, to_centre.z)
		parent.add_child(board)
		# Support posts
		_make_box(parent, Vector3(0.10, 0.6, 0.10), Vector3(x, 0.3, z), Color(0.18, 0.18, 0.20))
		# A small click target per board so any tap on a sponsor opens
		# the FACILITY tab.
		_add_facility_click_area(parent, "sponsor_boards",
			Vector3(x, 0.6, z),
			Vector3(w + 0.4, 1.6, 0.6))


func _build_lighting(parent: Node3D, level: int) -> void:
	# Tall poles + light fixtures at corners of the track footprint.
	var t_tier: int = _track.track_tier()
	var safe_offset: float = _track.TIER_WAVE_AMP[t_tier] \
		+ _track.TIER_ASPHALT_WIDTH[t_tier] * 0.5 + 2.0
	var rx := _track_rx() + safe_offset
	var rz := _track_rz() + safe_offset
	var pole_count := mini(4 + (level - 1), 12)
	var pole_height := 6.0 + level * 0.15
	var positions: Array[Vector3] = []
	for i in range(pole_count):
		var t := float(i) / float(pole_count) * TAU + PI * 0.25
		var x := cos(t) * rx
		var z := sin(t) * rz
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
	# Sits at the (+X, +Z) corner, away from cafeteria / merch / pit
	# / lounge / parking. Pole + billboard scale with level.
	var pole_h: float = 5.5 + float(level) * 0.35
	# Anchor against track outer + safety so the pole never sits on
	# the rumble strip at any tier.
	const SAFETY: float = 3.5
	var pos := Vector3(_track_outer_x(SAFETY), 0.0, _track_outer_z(SAFETY))

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
const _TREE_TRUNK    := Color(0.32, 0.22, 0.12)
const _TREE_FOLIAGE  := Color(0.18, 0.45, 0.18)


# Hub position — the venue's "ticket booth" sits here, and every
# walkway radiates from it. Placed south of the track, close enough
# to be a natural funnel point but well clear of the asphalt.
func _hub_position() -> Vector3:
	return Vector3(-_track.current_rx() * 0.4, 0.0, -_track_outer_z(7.0))


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
	# Real F1 venues have a CONCOURSE PLAZA around the spectator
	# entrance, not random spaghetti walkways crossing the venue. So:
	# - One big rectangular concrete plaza at the south of the track
	#   (the spectator entrance side)
	# - One main road from the parking lot to that plaza
	# - One short walkway from the plaza forward to the grandstand
	# That's it — keeps things clean. The cafeteria / merch / lounge /
	# pit complex all already sit on grass within walking distance,
	# we don't need to draw a path to each of them individually
	# (would just clip through buildings).
	var hub: Vector3 = _hub_position()

	# Main concourse plaza — wide concrete slab around the ticket booth.
	var plaza_w: float = 18.0
	var plaza_d: float = 9.0
	var plaza := MeshInstance3D.new()
	plaza.name = "Concourse"
	var pbm := BoxMesh.new()
	pbm.size = Vector3(plaza_w, 0.06, plaza_d)
	plaza.mesh = pbm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = _WALKWAY_COLOR
	pmat.roughness = 0.85
	plaza.material_override = pmat
	plaza.position = Vector3(hub.x, 0.04, hub.z)
	parent.add_child(plaza)

	# Painted edge stripe around the plaza (light accent).
	_make_label_strip(parent, _WALKWAY_COLOR.lightened(0.4),
		Vector3(hub.x, 0.10, hub.z + plaza_d * 0.5 + 0.05),
		Vector3(plaza_w * 0.95, 0.06, 0.10))

	# Main asphalt road from parking lot to the plaza.
	var parking_corner := Vector3(
		-_track_outer_x(5.0) - 8.0,
		0.04,
		-_track_outer_z(4.0) - 4.0)
	_make_road(parent, hub + Vector3(-plaza_w * 0.3, 0, 0),
		parking_corner, 3.0, _ROAD_COLOR)

	# Short walkway from plaza forward to the grandstand entrance.
	var grandstand_entrance := Vector3(0.0, 0.04, -_track_outer_z(1.5))
	_make_road(parent, hub + Vector3(0, 0, plaza_d * 0.5),
		grandstand_entrance, 2.4, _WALKWAY_COLOR)


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
	# Decorative trees scattered just outside the venue's main rectangle
	# so the camera always shows something green rather than a void.
	var rx: float = _track.current_rx()
	var rz: float = _track.current_rz()
	# Place the trees on an ellipse well outside the rumble strip + all
	# facility footprints, with a stable seeded RNG so they don't
	# jitter around each rebuild.
	var ring_x: float = _track_outer_x(18.0)
	var ring_z: float = _track_outer_z(14.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19370 + int(_track.track_tier())
	var tree_count: int = 24
	for i in range(tree_count):
		var t: float = (float(i) + rng.randf_range(-0.1, 0.1)) / float(tree_count) * TAU
		var jitter_r: float = rng.randf_range(0.0, 6.0)
		var x: float = cos(t) * (ring_x + jitter_r)
		var z: float = sin(t) * (ring_z + jitter_r)
		var height: float = rng.randf_range(3.5, 5.5)
		_make_tree(parent, Vector3(x, 0.0, z), height, rng)
	# Suppress unused
	if rx > 0.0 and rz > 0.0:
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
