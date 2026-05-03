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
# Pit-bay team identities are sourced from Track.TEAM_PRIMARY_COLORS
# at build time so the garage doors and the karts always wear the
# same liveries.

@export var track_path: NodePath

var _track: Track
var _root_holders := {}  # facility name → Node3D holder
var _decoration_holder: Node3D
var _customer_holder: Node3D
var _traffic_holder: Node3D
# Per-customer visitor visuals: customer_id (int) → state Dictionary.
# Each visitor owns a car + a person mesh and progresses through the
# arrival → parked → walking_in → queueing → racing → walking_out →
# leaving lifecycle, mirroring the real Customer's logical state.
var _visitors: Dictionary = {}
# Free parking-spot indices — assigned to a visitor on arrival,
# released when they leave. Indices match (row, col) tuples.
var _free_parking_spots: Array = []


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
	# Live customer figures — refreshed on queue_changed so the venue
	# looks busier as more customers arrive. Separate holder so we
	# don't rebuild the static decorations every queue tick.
	_customer_holder = Node3D.new()
	_customer_holder.name = "CustomerHolder"
	add_child(_customer_holder)
	# Animated traffic — visiting cars drive in through the south
	# gate, pause at the parking lot, then drive back out.
	_traffic_holder = Node3D.new()
	_traffic_holder.name = "TrafficHolder"
	add_child(_traffic_holder)
	EventBus.facility_upgraded.connect(_on_facility_upgraded)
	# Track size only changes on tier rollover (per-level upgrades buy
	# stats, not new geometry), so we only need to rebuild facility
	# layout on track_tier_changed.
	EventBus.track_tier_changed.connect(_on_tier_changed.unbind(2))
	# Customer signals drive the visitor visuals — each arriving
	# customer gets a car + a person, each leaving customer drives off.
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.customer_left.connect(_on_customer_left.unbind(2))
	# Defer first build so the track has constructed its path/footprint.
	call_deferred("_rebuild_all")


func _rebuild_all() -> void:
	for facility: String in Facilities.facility_names():
		_rebuild_one(facility)
	_rebuild_decorations()
	_rebuild_parking_spot_pool()


func _rebuild_decorations() -> void:
	for child in _decoration_holder.get_children():
		child.queue_free()
	if _track == null:
		return
	_build_world_borders(_decoration_holder)
	_build_approach_road(_decoration_holder)
	_build_walkways(_decoration_holder)
	_build_ticket_booth(_decoration_holder)
	_build_trees(_decoration_holder)
	_build_decorative_props(_decoration_holder)


func _rebuild_parking_spot_pool() -> void:
	# Compute every (row, col) parking spot the lot currently has and
	# rebuild the free-spot pool from that. Visitors already in the lot
	# keep their assigned spot; new arrivals draw from the freshly
	# computed free pool.
	_free_parking_spots.clear()
	var lvl: int = Facilities.parking_level
	if lvl <= 0:
		return
	var rows: int = clampi(2 + lvl / 6, 2, 12)
	var cols: int = clampi(5 + lvl / 4, 5, 22)
	# Currently-occupied spots — preserved so we don't double-assign
	# them to a new visitor.
	var taken: Dictionary = {}
	for v in _visitors.values():
		var spot: Vector2i = v.get("parking_spot", Vector2i(-1, -1))
		if spot.x >= 0:
			taken[spot] = true
	for r in range(rows):
		for c in range(cols):
			var key: Vector2i = Vector2i(r, c)
			if not taken.has(key):
				_free_parking_spots.append(key)
	_free_parking_spots.shuffle()


func _on_facility_upgraded(facility: String, _level: int) -> void:
	_rebuild_one(facility)
	# The approach road's endpoint sits against the parking lot, so
	# rebuild the static decorations whenever parking is upgraded.
	# Also refresh the parking-spot pool so future arrivals can use
	# any newly-added spots.
	if facility == "parking":
		_rebuild_decorations()
		_rebuild_parking_spot_pool()


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
	# Scaling deliberately gentle so a max-level café stays cafe-sized
	# (~9 m wide, 5 m tall) instead of turning into a stadium concession.
	var w: float = 5.0 + level * 0.04
	var d: float = 4.5 + level * 0.03
	var h: float = 3.0 + level * 0.02
	var patio_d: float = 2.5 + level * 0.04
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

	# Peaked roof on top of the cafeteria — small triangle prism that
	# reads as a real "café" silhouette from above.
	_make_box(parent, Vector3(w * 1.04, 0.20, d * 1.04),
		building_pos + Vector3(0, h * 0.5 + 0.10, 0),
		_CAFETERIA_COLOR.darkened(0.45))
	# Two stripe ridges along the roof for cartoon detail.
	for ridge_z: float in [-d * 0.30, d * 0.30]:
		_make_box(parent, Vector3(w * 1.06, 0.10, 0.18),
			building_pos + Vector3(0, h * 0.5 + 0.25, ridge_z),
			Color(0.95, 0.95, 0.95))

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
	# garage count change with the facility level.
	#
	# The pit-lane SURFACE is built as one continuous CSGPolygon3D
	# extruded along a custom curved Path3D that:
	#
	#   - Starts on the racing line at the loop's east extreme
	#     (+loop_rx, STRAIGHT_Z), heading west.
	#   - Smoothly diverges NORTH over a "merge in" zone.
	#   - Runs straight and parallel to the main straight in the
	#     middle (the parallel section, where the wall + garages live).
	#   - Smoothly converges back over a "merge out" zone.
	#   - Ends on the racing line at the loop's west extreme
	#     (-loop_rx, STRAIGHT_Z).
	#
	# Because the pit centreline COINCIDES with the track centreline at
	# both endpoints and bends away over a smooth curve, the pit asphalt
	# visually FLOWS off the racing line and rejoins it later — no
	# separate diagonal slabs needed, no awkward overlap, exactly like
	# real F1 venues.
	var sh: float = _track.STRAIGHT_HALF
	var straight_z: float = _track.STRAIGHT_Z
	var loop_rx: float = _track.current_rx()
	var asphalt_half: float = _track.current_asphalt_width() * 0.5
	var asphalt_color := Color(0.42, 0.44, 0.48)
	# Pit-lane width is CONSTANT — only the garage count changes with
	# facility level. (Previously the lane grew wider per level which
	# made tier-10 pits absurdly thick.)
	var pit_lane_width: float = 3.4
	# Constant grass gap between pit and track in the parallel section.
	var grass_gap: float = 3.5
	# In the parallel middle section the pit centreline sits at this
	# z offset NORTH of the track centreline. At the merge endpoints
	# the offset is 0 (centrelines coincide).
	var parallel_z_offset: float = asphalt_half + _RUMBLE_INSET_VAL \
		+ grass_gap + pit_lane_width * 0.5

	# Build the curved Path3D in three phases so the parallel section
	# (where wall + garages live) stays the SAME LENGTH across every
	# tier (= 2*sh, equal to the central straight). Only the merge-in
	# and merge-out zones grow with track size — they fan from the
	# pit straight out to the loop's east/west extreme.
	var pit_path := Path3D.new()
	pit_path.name = "PitPath"
	parent.add_child(pit_path)
	var pit_curve := Curve3D.new()
	var pit_centers: Array[Vector3] = []
	var pit_blends: Array[float] = []
	# Number of samples per phase. 32 is enough for a smooth merge
	# curve at any tier.
	const MERGE_SAMPLES: int = 32
	const PARALLEL_SAMPLES: int = 48
	# Phase 1 — merge IN (east end). x: loop_rx → sh, z: STRAIGHT_Z →
	# parallel_pit_z (smoothstep so the curve eases cleanly).
	for i in range(MERGE_SAMPLES):
		var u: float = float(i) / float(MERGE_SAMPLES)
		var x: float = lerpf(loop_rx, sh, u)
		var ease: float = smoothstep(0.0, 1.0, u)
		var z: float = straight_z + parallel_z_offset * ease
		pit_curve.add_point(Vector3(x, 0.0, z))
		pit_centers.append(Vector3(x, 0.0, z))
		pit_blends.append(ease)
	# Phase 2 — parallel section. x: sh → -sh, z: constant.
	for i in range(PARALLEL_SAMPLES + 1):
		var u: float = float(i) / float(PARALLEL_SAMPLES)
		var x: float = lerpf(sh, -sh, u)
		var z: float = straight_z + parallel_z_offset
		pit_curve.add_point(Vector3(x, 0.0, z))
		pit_centers.append(Vector3(x, 0.0, z))
		pit_blends.append(1.0)
	# Phase 3 — merge OUT (west end). x: -sh → -loop_rx, z: parallel
	# back to STRAIGHT_Z.
	for i in range(MERGE_SAMPLES):
		var u: float = float(i + 1) / float(MERGE_SAMPLES)
		var x: float = lerpf(-sh, -loop_rx, u)
		var ease: float = smoothstep(0.0, 1.0, 1.0 - u)
		var z: float = straight_z + parallel_z_offset * ease
		pit_curve.add_point(Vector3(x, 0.0, z))
		pit_centers.append(Vector3(x, 0.0, z))
		pit_blends.append(ease)
	pit_path.curve = pit_curve

	# Pit asphalt — extruded along the FULL curve. The centreline starts
	# on the track centreline at p=0/1 and curves out + back, so the
	# pit asphalt visually fans off the racing line and re-merges.
	var pit_csg := CSGPolygon3D.new()
	pit_csg.name = "PitAsphalt"
	pit_csg.mode = CSGPolygon3D.MODE_PATH
	pit_csg.path_node = pit_path.get_path()
	pit_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	pit_csg.path_interval = 0.5
	pit_csg.path_joined = false
	pit_csg.polygon = PackedVector2Array([
		Vector2(-pit_lane_width * 0.5, 0.045),
		Vector2( pit_lane_width * 0.5, 0.045),
		Vector2( pit_lane_width * 0.5, -0.04),
		Vector2(-pit_lane_width * 0.5, -0.04),
	])
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = asphalt_color
	pit_mat.roughness = 0.85
	pit_csg.material_override = pit_mat
	parent.add_child(pit_csg)

	# Walls + garages live ONLY in the parallel section (blend ≈ 1) so
	# nothing ever clips the racing line at the merges.
	const PARALLEL_BLEND_THRESHOLD: float = 0.95
	var parallel_indices: Array[int] = []
	for i in range(pit_blends.size()):
		if pit_blends[i] >= PARALLEL_BLEND_THRESHOLD:
			parallel_indices.append(i)

	# Pit wall — single straight slab on the south edge of the pit
	# straight. Spans the parallel section only.
	if parallel_indices.size() >= 2:
		var wall_h: float = 0.55
		var first_x: float = pit_centers[parallel_indices[0]].x
		var last_x: float = pit_centers[parallel_indices[parallel_indices.size() - 1]].x
		var wall_len: float = absf(first_x - last_x)
		var wall_center_x: float = (first_x + last_x) * 0.5
		var wall_z: float = straight_z + parallel_z_offset \
			- pit_lane_width * 0.5 + 0.09
		var wall := MeshInstance3D.new()
		wall.name = "PitWall"
		var wall_bm := BoxMesh.new()
		wall_bm.size = Vector3(wall_len, wall_h, 0.18)
		wall.mesh = wall_bm
		var wall_mat := StandardMaterial3D.new()
		wall_mat.albedo_color = Color(0.92, 0.92, 0.95)
		wall.material_override = wall_mat
		wall.position = Vector3(wall_center_x, wall_h * 0.5 + 0.05, wall_z)
		parent.add_child(wall)
		# Cyan accent on top.
		var accent := MeshInstance3D.new()
		accent.name = "PitWallAccent"
		var accent_bm := BoxMesh.new()
		accent_bm.size = Vector3(wall_len, 0.10, 0.22)
		accent.mesh = accent_bm
		var accent_mat := StandardMaterial3D.new()
		accent_mat.albedo_color = _PIT_LANE_COLOR
		accent_mat.emission_enabled = true
		accent_mat.emission = _PIT_LANE_COLOR
		accent_mat.emission_energy_multiplier = 1.4
		accent.material_override = accent_mat
		accent.position = Vector3(wall_center_x, wall_h + 0.10, wall_z)
		parent.add_child(accent)

	# Centre-line dashes along the parallel section only.
	var dash_count: int = 12
	var parallel_pit_z: float = straight_z + parallel_z_offset
	if parallel_indices.size() >= 2:
		var dash_first_x: float = pit_centers[parallel_indices[0]].x
		var dash_last_x: float = pit_centers[parallel_indices[parallel_indices.size() - 1]].x
		for i in range(dash_count):
			var u: float = (float(i) + 0.5) / float(dash_count)
			var dash_x: float = lerpf(dash_first_x, dash_last_x, u)
			var dash := MeshInstance3D.new()
			var dbm := BoxMesh.new()
			dbm.size = Vector3(0.5, 0.06, 0.10)
			dash.mesh = dbm
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = Color(0.85, 0.85, 0.90)
			dash.material_override = dmat
			dash.position = Vector3(dash_x, 0.07, parallel_pit_z)
			parent.add_child(dash)

	# Garage row NORTH of the pit lane. CAP at 10 bays — the user
	# explicitly wants tier 10 to land at exactly 10 garages, not
	# more. Sqrt curve so the player sees new garages quickly in the
	# early game and reaches the 10-bay max around level 50.
	#
	# Bay dimensions are CONSTANT across levels — only the count
	# grows. Real F1 garage bays are uniform; making them inflate
	# with level made high-level pits look cartoony-oversized.
	var bays: int = clampi(1 + roundi(sqrt(float(level)) * 1.27), 1, 10)
	var bay_w: float = 2.4
	var bay_d: float = 3.4
	var bay_h: float = 2.6
	var garage_z: float = parallel_pit_z + pit_lane_width * 0.5 \
		+ bay_d * 0.5 + 0.30
	# Garage row spans the same X range as the pit-wall (parallel
	# section). Falls back to ±sh if the parallel section is degenerate.
	var garage_first_x: float = -sh + bay_w * 0.6
	var garage_last_x: float = sh - bay_w * 0.6
	if parallel_indices.size() >= 2:
		garage_first_x = pit_centers[parallel_indices[0]].x + bay_w * 0.6
		garage_last_x = pit_centers[parallel_indices[parallel_indices.size() - 1]].x - bay_w * 0.6
		# Curve sweeps east → west, so flip if needed for stable ordering.
		if garage_first_x > garage_last_x:
			var tmp := garage_first_x
			garage_first_x = garage_last_x
			garage_last_x = tmp
	for i in range(bays):
		var bay_p: float
		if bays == 1:
			bay_p = 0.5
		else:
			bay_p = float(i) / float(bays - 1)
		var bay_x: float = lerpf(garage_first_x, garage_last_x, bay_p)
		# Pull the team's primary + optional accent from the shared
		# track palette so the garage and the kart pair share livery.
		var team_index: int = i % _track.TEAM_PRIMARY_COLORS.size()
		var team_color: Color = _track.TEAM_PRIMARY_COLORS[team_index]
		var has_accent: bool = _track.team_has_accent(team_index)
		var accent_color: Color = (
			_track.TEAM_ACCENT_COLORS[team_index] if has_accent else team_color
		)
		# Garage body — neutral dark grey so the team doors pop against it.
		var garage := MeshInstance3D.new()
		var gbm := BoxMesh.new()
		gbm.size = Vector3(bay_w * 0.92, bay_h, bay_d)
		garage.mesh = gbm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.22, 0.23, 0.28)
		gmat.metallic = 0.3
		gmat.roughness = 0.6
		garage.material_override = gmat
		garage.position = Vector3(bay_x, bay_h * 0.5, garage_z)
		parent.add_child(garage)
		# Team-coloured door panel facing the pit lane (south face). For
		# split-livery teams (Blue+Red, DarkBlue+White), draw the door
		# as TOP HALF primary + BOTTOM HALF accent.
		var door_z: float = garage_z - bay_d * 0.5 - 0.04
		var door_full_w: float = bay_w * 0.78
		var door_full_h: float = bay_h * 0.75
		if has_accent:
			# Top half = primary, bottom half = accent.
			var door_top := MeshInstance3D.new()
			var dbm_top := BoxMesh.new()
			dbm_top.size = Vector3(door_full_w, door_full_h * 0.5, 0.06)
			door_top.mesh = dbm_top
			var dt_mat := StandardMaterial3D.new()
			dt_mat.albedo_color = team_color
			dt_mat.emission_enabled = true
			dt_mat.emission = team_color
			dt_mat.emission_energy_multiplier = 0.6
			door_top.material_override = dt_mat
			door_top.position = Vector3(bay_x,
				bay_h * 0.4 + door_full_h * 0.25, door_z)
			parent.add_child(door_top)
			var door_bot := MeshInstance3D.new()
			var dbm_bot := BoxMesh.new()
			dbm_bot.size = Vector3(door_full_w, door_full_h * 0.5, 0.06)
			door_bot.mesh = dbm_bot
			var db_mat := StandardMaterial3D.new()
			db_mat.albedo_color = accent_color
			db_mat.emission_enabled = true
			db_mat.emission = accent_color
			db_mat.emission_energy_multiplier = 0.6
			door_bot.material_override = db_mat
			door_bot.position = Vector3(bay_x,
				bay_h * 0.4 - door_full_h * 0.25, door_z)
			parent.add_child(door_bot)
		else:
			var door := MeshInstance3D.new()
			var dbm2 := BoxMesh.new()
			dbm2.size = Vector3(door_full_w, door_full_h, 0.06)
			door.mesh = dbm2
			var door_mat := StandardMaterial3D.new()
			door_mat.albedo_color = team_color
			door_mat.emission_enabled = true
			door_mat.emission = team_color
			door_mat.emission_energy_multiplier = 0.6
			door.material_override = door_mat
			door.position = Vector3(bay_x, bay_h * 0.4, door_z)
			parent.add_child(door)
		# Roof tag block in the team's primary colour above the door.
		_make_box(parent,
			Vector3(bay_w * 0.7, 0.16, 0.18),
			Vector3(bay_x, bay_h + 0.10,
				garage_z - bay_d * 0.5 - 0.06),
			team_color)

	# Paddock — flat asphalt slab behind the garages where teams park
	# their motorhomes. Spans the parallel section's X range. Constant
	# size like the bays themselves.
	var paddock_d: float = 5.5
	var paddock_z: float = garage_z + bay_d * 0.5 + paddock_d * 0.5 + 0.5
	var paddock_w: float = absf(garage_last_x - garage_first_x) + bay_w + 1.0
	var paddock_center_x: float = (garage_first_x + garage_last_x) * 0.5
	var paddock := MeshInstance3D.new()
	paddock.name = "Paddock"
	var paddock_bm := BoxMesh.new()
	paddock_bm.size = Vector3(paddock_w, 0.06, paddock_d)
	paddock.mesh = paddock_bm
	var paddock_mat := StandardMaterial3D.new()
	paddock_mat.albedo_color = Color(0.50, 0.52, 0.55)
	paddock_mat.roughness = 0.9
	paddock.material_override = paddock_mat
	paddock.position = Vector3(paddock_center_x, 0.04, paddock_z)
	parent.add_child(paddock)

	# Click area covers the whole pit complex.
	var click_z_center: float = (parallel_pit_z + paddock_z) * 0.5
	var click_z_size: float = (paddock_z + paddock_d * 0.5) \
		- (parallel_pit_z - pit_lane_width * 0.5) + 1.0
	_add_facility_click_area(parent, "pit_lane",
		Vector3(0, bay_h * 0.5, click_z_center),
		Vector3(2.0 * loop_rx + 4.0, bay_h * 1.8, click_z_size))


func _build_lounge(parent: Node3D, level: int) -> void:
	# VIP tower: narrow footprint, grows TALL with level (more floors)
	# rather than ballooning outward. Real F1 hospitality buildings are
	# slender mid-rises, not stadium blocks.
	var w: float = 5.0 + level * 0.04
	var d: float = 5.0 + level * 0.04
	var floors: int = clampi(2 + level / 8, 2, 14)
	var floor_h: float = 1.4
	var h: float = floor_h * float(floors) + 0.6
	# Sit BEHIND the grandstand AND the spectator concourse plaza on
	# the -Z side. Plaza centre is at _track_outer_z(14) with a depth
	# of 8, so its back edge sits at _track_outer_z(18). Lounge front
	# must clear that → SAFETY = 19 (1 m gap to plaza back).
	const SAFETY: float = 19.0
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

	# Antenna mast + emissive VIP beacon on top of the terrace —
	# tower silhouette reads from anywhere on the venue.
	var mast_h: float = 1.6 + float(level) * 0.02
	_make_box(parent, Vector3(0.16, mast_h, 0.16),
		Vector3(pos.x, ry + rail_h + mast_h * 0.5, pos.z),
		Color(0.20, 0.20, 0.24))
	# Beacon at the top of the mast.
	_make_label_strip(parent, _LOUNGE_COLOR,
		Vector3(pos.x, ry + rail_h + mast_h, pos.z),
		Vector3(0.55, 0.55, 0.55))
	# Big block "VIP" sign band wrapping the top floor — uses an
	# emissive lounge-coloured strip so it glows day or night.
	_make_label_strip(parent, _LOUNGE_COLOR.lightened(0.15),
		Vector3(pos.x, pos.y + h * 0.5 - 0.6, pos.z + d * 0.5 + 0.06),
		Vector3(w * 0.65, 0.45, 0.08))
	_add_facility_click_area(parent, "lounge", pos,
		Vector3(w * 1.1, h * 1.05, d * 1.1))


func _build_merch_shop(parent: Node3D, level: int) -> void:
	# Green kiosk at the +X end of the venue (other end from the
	# cafeteria — we leave +Z free for the pit complex). Scaling
	# kept gentle so a max-level shop stays kiosk-sized (~7-8 m wide).
	var w: float = 3.5 + level * 0.04
	var d: float = 3.0 + level * 0.03
	var h: float = 2.2 + level * 0.02
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
	# Flat roof slab with darker tone — gives the kiosk a clean
	# silhouette and reads as a real building from above.
	_make_box(parent, Vector3(w * 1.06, 0.12, d * 1.06),
		pos + Vector3(0, h * 0.5 + 0.06, 0),
		_MERCH_COLOR.darkened(0.5))
	# Sign band on the side facing the track.
	_make_label_strip(parent, _MERCH_COLOR,
		pos + Vector3(-w * 0.5 - 0.05, h * 0.4, 0),
		Vector3(0.06, 0.30, d * 0.8))
	# Striped awning over the entrance — alternating green / white
	# slabs for the iconic festival-kiosk look.
	var awning_pos: Vector3 = pos + Vector3(-w * 0.5 - w * 0.2, h * 0.55, 0)
	var stripe_count: int = 5
	for i in range(stripe_count):
		var u: float = (float(i) + 0.5) / float(stripe_count)
		var sz: float = lerpf(-d * 0.55, d * 0.55, u)
		var c: Color = _MERCH_COLOR if (i % 2 == 0) else Color(0.95, 0.96, 0.97)
		_make_box(parent, Vector3(w * 0.4, 0.08, d * 0.22),
			awning_pos + Vector3(0, 0, sz),
			c)
	_add_facility_click_area(parent, "merch_shop",
		pos + Vector3(-w * 0.2, 0, 0),
		Vector3(w * 1.6, h * 1.4, d * 1.2))


func _build_sponsor_boards(parent: Node3D, level: int) -> void:
	# Vertical billboards arranged along the OUTSIDE of the south loop.
	# We skip the north straight entirely (pit complex sits there) and
	# the very east/west extremes (cafeteria + merch shop are there).
	# Boards face inward toward the racing line.
	#
	# Capped at 8 boards across the south arc — at higher facility
	# levels each board just gets bigger / brighter rather than
	# multiplying into a wall of signs that overshadows the
	# grandstand.
	var board_count := clampi(2 + level / 6, 2, 8)
	var asphalt_half: float = _track.current_asphalt_width() * 0.5
	var wave_amp: float = _track.current_wave_amp()
	var safe_offset: float = asphalt_half + wave_amp + 1.6
	# Boards grow gently with facility level instead of multiplying —
	# caps the total footprint while still rewarding upgrades. At
	# MAX_LEVEL=100 each board is ~3.4 m wide × 1.7 m tall, billboard-
	# sized, not stadium-sized.
	var w: float = 2.4 + float(level) * 0.01
	var h: float = 1.1 + float(level) * 0.006
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
	# Tall poles + light fixtures arranged around the OUTSIDE of the
	# south loop (and at the east/west extremes). The +Z arc is
	# DELIBERATELY skipped — the pit complex sits there and the pit
	# wall already has its own emissive cyan accent, so dropping a
	# floodlight pole in the middle of the start straight (which
	# is what the old symmetric ring produced) is both ugly and
	# physically wrong.
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
	# Distribute poles across a 3/4 ring spanning the south + east +
	# west arcs only. Arc starts at PI*0.75 (NW corner heading south)
	# and runs clockwise through the south to PI*2.25 (NE corner).
	var arc_start: float = PI * 0.75
	var arc_span: float = PI * 1.5
	var positions: Array[Vector3] = []
	for i in range(pole_count):
		var t: float = arc_start + (float(i) + 0.5) / float(pole_count) * arc_span
		var x: float = cos(t) * ring_x
		var z: float = center_z + sin(t) * ring_z
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
	# venue's at the same facility level. Scaling is restrained so a
	# max-tier max-level main stand caps around 30 m wide × 6 m tall
	# rather than the previous 138 m × 42 m monstrosity.
	var tier_scale: float = 1.0 + (_track.track_tier() - 1) * 0.10

	# Main stand on the spectator side (-Z), opposite the pit complex.
	# Anchor the FRONT (track-facing) edge at -(track_outer + safety)
	# so the bottom row never sits on the rumble strip at any tier.
	var main_w: float = (8.0 + level * 0.15) * tier_scale
	var main_d: float = 2.6 + level * 0.04
	var main_h: float = (1.2 + level * 0.04) * tier_scale
	const MAIN_SAFETY: float = 1.5
	var main_z: float = -_track_outer_z(MAIN_SAFETY) - main_d * 0.5
	_make_grandstand_block(parent, Vector3(0, 0, main_z),
		Vector3(main_w, main_h, main_d), level, false)

	# Side stands at the +X / -X ends from level 7+ (rotated 90°).
	if level >= 7:
		var side_levels: int = level - 6
		var side_w: float = (5.0 + side_levels * 0.12) * tier_scale
		var side_d: float = 2.4 + side_levels * 0.03
		var side_h: float = (1.0 + side_levels * 0.04) * tier_scale
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

	# (The lot's parked cars are now DYNAMIC — they're the visitor
	# vehicles spawned by the customer-traffic system, each tied to a
	# real Customer in the queue. No static decoration cars here.)

	# Click target covering the whole lot.
	_add_facility_click_area(parent, "parking",
		Vector3(center.x, 1.0, center.z),
		Vector3(lot_w + 1.0, 2.0, lot_d + 1.0))


func _build_marketing(parent: Node3D, level: int) -> void:
	# Marketing tower: tall pole with a glowing billboard at the top.
	# Sits at the (+X, -Z) SE corner — north +Z is reserved for the
	# pit complex, so the tower goes opposite the parking lot at the
	# south-east corner of the venue.
	var pole_h: float = 5.5 + float(level) * 0.18
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

	# Billboard (emissive — looks like an LED display). Scaling kept
	# modest so a max-level board lands at ~7×3.6 m, similar to a
	# real F1 trackside LED, not a stadium-sized JumboTron.
	var bw: float = 3.0 + float(level) * 0.04
	var bh: float = 1.8 + float(level) * 0.018
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
	# Centred south of the grandstand by enough margin that the 8 m
	# plaza never clips the grandstand's back row. The grandstand
	# extends out to track_outer + 1.5 + main_d (= up to ~5 m deep at
	# max level, ×1.9 tier_scale at tier 10), so we need at least
	# track_outer + 10 of clearance on the plaza front edge. With
	# plaza_d = 8, hub.z = track_outer + 14 puts the front edge at
	# track_outer + 10 and the back edge at track_outer + 18.
	return Vector3(0.0, 0.0, -_track_outer_z(14.0))


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
	var lounge_branch := Vector3(0.0, 0.04, -_track_outer_z(18.5))
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
	# Decorative trees scattered AROUND the venue's facilities and
	# OUT TO the world walls. We build a generous ellipse, then for
	# every candidate sample test against:
	#   1. world bounds (skip if it would clip the perimeter wall)
	#   2. facility no-go rectangles (cafeteria, merch shop, parking,
	#      lounge, marketing, pit complex) so trees never sprout
	#      inside a building.
	var loop_depth: float = _track.current_rz()
	var center_z: float = _track.STRAIGHT_Z - loop_depth * 0.5
	var ring_x: float = _track_outer_x(28.0)
	# ring_z must clear: south parking (~south_extent + 38 m at max
	# parking) AND north pit complex (~STRAIGHT_Z + 22). Take the
	# larger of the two distances from the ring centre.
	var south_clearance: float = (_track.south_extent_z(0.0) + 42.0) \
		- absf(center_z)
	var north_clearance: float = (_track.STRAIGHT_Z + 28.0) - center_z
	var ring_z: float = maxf(loop_depth * 0.5 + 30.0,
		maxf(south_clearance, north_clearance))

	# Build facility no-go rectangles (axis-aligned, world coords).
	# Tested with a small inflate so trees don't graze building corners.
	var no_go: Array[Rect2] = _facility_exclusion_rects()

	var rng := RandomNumberGenerator.new()
	rng.seed = 19370 + int(_track.track_tier())
	var tree_target: int = 32
	var attempts: int = 0
	var placed: int = 0
	while placed < tree_target and attempts < tree_target * 4:
		attempts += 1
		var t: float = rng.randf_range(0.0, TAU)
		var jitter_r: float = rng.randf_range(0.0, 8.0)
		var x: float = cos(t) * (ring_x + jitter_r)
		var z: float = center_z + sin(t) * (ring_z + jitter_r)
		# Clip to world bounds (with a small margin so trees don't
		# poke through the perimeter wall).
		if x < _WORLD_WEST + 4.0 or x > _WORLD_EAST - 4.0:
			continue
		if z < _WORLD_SOUTH + 4.0 or z > _WORLD_NORTH - 4.0:
			continue
		# Reject if inside any facility rectangle.
		var rejected: bool = false
		for r: Rect2 in no_go:
			if r.has_point(Vector2(x, z)):
				rejected = true
				break
		if rejected:
			continue
		var height: float = rng.randf_range(3.5, 5.5)
		_make_tree(parent, Vector3(x, 0.0, z), height, rng)
		placed += 1


func _facility_exclusion_rects() -> Array[Rect2]:
	# Axis-aligned bounding rectangles for every visible facility,
	# inflated by 2 m so trees never sprout right against a wall.
	# Returned in world-XZ coords (Rect2.position = top-left corner,
	# size = width × depth where x=X-axis, y=Z-axis).
	var rects: Array[Rect2] = []
	var inflate: float = 2.0

	# Cafeteria (-X side, all the way out past patio).
	if Facilities.cafeteria_level > 0:
		var c_lvl: int = Facilities.cafeteria_level
		var c_w: float = 5.0 + c_lvl * 0.04
		var c_d: float = 4.5 + c_lvl * 0.03
		var c_patio_d: float = 2.5 + c_lvl * 0.04
		var c_far_x: float = -_track_outer_x(4.0)
		var c_near_x: float = c_far_x - c_w - c_patio_d
		rects.append(Rect2(
			c_near_x - inflate, -c_d * 0.5 - inflate,
			(c_far_x - c_near_x) + inflate * 2,
			c_d + inflate * 2))

	# Merch shop (+X side).
	if Facilities.merch_shop_level > 0:
		var m_lvl: int = Facilities.merch_shop_level
		var m_w: float = 3.5 + m_lvl * 0.04
		var m_d: float = 3.0 + m_lvl * 0.03
		var m_awning: float = m_w * 0.4
		var m_near_x: float = _track_outer_x(4.0)
		var m_far_x: float = m_near_x + m_awning + m_w
		rects.append(Rect2(
			m_near_x - inflate, -m_d * 0.5 - inflate,
			(m_far_x - m_near_x) + inflate * 2,
			m_d + inflate * 2))

	# Lounge (south, behind plaza).
	if Facilities.lounge_level > 0:
		var l_lvl: int = Facilities.lounge_level
		var l_w: float = 5.0 + l_lvl * 0.04
		var l_d: float = 5.0 + l_lvl * 0.04
		var l_z: float = -_track_outer_z(19.0) - l_d * 0.5
		rects.append(Rect2(
			-l_w * 0.5 - inflate, l_z - l_d * 0.5 - inflate,
			l_w + inflate * 2,
			l_d + inflate * 2))

	# Parking lot.
	if Facilities.parking_level > 0:
		var lot_w: float = _parking_lot_width()
		var lot_d: float = _parking_lot_depth()
		var lot_cx: float = -_track_outer_x(5.0) - lot_w * 0.5
		var lot_cz: float = -_track_outer_z(4.0) - lot_d * 0.5
		rects.append(Rect2(
			lot_cx - lot_w * 0.5 - inflate, lot_cz - lot_d * 0.5 - inflate,
			lot_w + inflate * 2,
			lot_d + inflate * 2))

	# Marketing tower (+X / -Z corner).
	if Facilities.marketing_level > 0:
		var mk_pos_x: float = _track_outer_x(3.5)
		var mk_pos_z: float = -_track_outer_z(3.5)
		rects.append(Rect2(
			mk_pos_x - 3.0 - inflate, mk_pos_z - 3.0 - inflate,
			6.0 + inflate * 2,
			6.0 + inflate * 2))

	# Pit complex (north of straight). Always excluded — even the
	# pit lane itself, since cars need to drive there.
	var pit_z: float = _track.STRAIGHT_Z + 4.0    # near edge
	var paddock_far_z: float = _track.STRAIGHT_Z + 22.0  # outer edge
	var pit_half_x: float = _track.STRAIGHT_HALF + 4.0
	rects.append(Rect2(
		-pit_half_x - inflate, pit_z - inflate,
		(pit_half_x * 2) + inflate * 2,
		(paddock_far_z - pit_z) + inflate * 2))

	return rects


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


# ---------------------------------------------------------------------------
# Decorative props — flower beds along the plaza, banners between
# lighting poles, walkway stripes. All small bright touches that
# bring the venue to life without changing any gameplay mechanics.
# ---------------------------------------------------------------------------
const _FLOWER_COLORS: Array[Color] = [
	Color(0.96, 0.27, 0.36),
	Color(0.99, 0.75, 0.18),
	Color(0.86, 0.42, 0.98),
	Color(0.95, 0.95, 0.95),
	Color(1.00, 0.55, 0.20),
]


func _build_decorative_props(parent: Node3D) -> void:
	var hub: Vector3 = _hub_position()
	var plaza_z: float = hub.z
	var plaza_w: float = _track_outer_x(0.0) * 2.0 + 6.0
	var plaza_d: float = 8.0

	# Painted cross-stripes along the plaza front edge — gives the
	# concrete some texture so it doesn't look like a flat slab.
	var stripe_count: int = 9
	for i in range(stripe_count):
		var u: float = (float(i) + 0.5) / float(stripe_count)
		var sx: float = lerpf(-plaza_w * 0.42, plaza_w * 0.42, u)
		_make_box(parent,
			Vector3(0.30, 0.04, plaza_d * 0.92),
			Vector3(sx, 0.085, plaza_z),
			_WALKWAY_COLOR.lightened(0.18))

	# Flower beds along the plaza front edge (between plaza and
	# grandstand walkway). Six small beds with mixed colours.
	var rng := RandomNumberGenerator.new()
	rng.seed = 13371
	var bed_count: int = 8
	for i in range(bed_count):
		var u: float = (float(i) + 0.5) / float(bed_count)
		var bx: float = lerpf(-plaza_w * 0.42, plaza_w * 0.42, u)
		var bz: float = plaza_z + plaza_d * 0.5 + 1.6
		# Skip beds that would sit on the grandstand walkway centre.
		if absf(bx) < 2.5:
			continue
		# Soil base
		_make_box(parent, Vector3(1.6, 0.12, 0.55),
			Vector3(bx, 0.08, bz),
			Color(0.32, 0.22, 0.15))
		# Flower clusters
		for f in range(3):
			var fx: float = bx + lerpf(-0.55, 0.55, (float(f) + 0.5) / 3.0)
			var c: Color = _FLOWER_COLORS[rng.randi() % _FLOWER_COLORS.size()]
			_make_box(parent, Vector3(0.32, 0.18, 0.32),
				Vector3(fx, 0.20, bz),
				c)

	# Banner / bunting strung between two pylons at the south edge of
	# the plaza — angled triangle flags read as "festival" from above.
	var pylon_xs: Array[float] = [-plaza_w * 0.45, plaza_w * 0.45]
	for px: float in pylon_xs:
		_make_box(parent, Vector3(0.12, 3.4, 0.12),
			Vector3(px, 1.7, plaza_z - plaza_d * 0.5 - 0.4),
			Color(0.30, 0.30, 0.34))
	# Bunting flags — a row of small triangles between the two pylons.
	var flag_count: int = 14
	for i in range(flag_count):
		var u: float = (float(i) + 0.5) / float(flag_count)
		var fx: float = lerpf(-plaza_w * 0.45, plaza_w * 0.45, u)
		var c: Color = _FLAG_COLORS[i % _FLAG_COLORS.size()]
		var fy: float = 3.0 + sin(u * PI) * 0.15
		_make_box(parent, Vector3(0.40, 0.30, 0.04),
			Vector3(fx, fy, plaza_z - plaza_d * 0.5 - 0.4),
			c)


# ---------------------------------------------------------------------------
# World borders + approach road
# ---------------------------------------------------------------------------
# The venue sits in a fixed-size playable rectangle bounded by low
# concrete perimeter walls. A gap on the south side lets the
# approach road run from outside the world INTO the venue, ending at
# the parking lot's south edge. Camera pan_bounds are tuned to match.
const _WORLD_WEST: float  = -160.0
const _WORLD_EAST: float  =  130.0
const _WORLD_NORTH: float =   55.0
const _WORLD_SOUTH: float = -160.0
const _WORLD_GATE_X: float = -90.0   # x of the south-edge gate's centre
const _WORLD_GATE_W: float =  10.0


func _build_world_borders(parent: Node3D) -> void:
	var wall_h: float = 1.0
	var wall_color := Color(0.55, 0.56, 0.58)
	var post_color := Color(0.30, 0.30, 0.34)
	var z_span: float = _WORLD_NORTH - _WORLD_SOUTH
	var x_span: float = _WORLD_EAST - _WORLD_WEST
	var center_z: float = (_WORLD_NORTH + _WORLD_SOUTH) * 0.5

	# West wall — full height of the playable rectangle.
	_make_box(parent, Vector3(0.40, wall_h, z_span),
		Vector3(_WORLD_WEST, wall_h * 0.5, center_z),
		wall_color)
	# East wall.
	_make_box(parent, Vector3(0.40, wall_h, z_span),
		Vector3(_WORLD_EAST, wall_h * 0.5, center_z),
		wall_color)
	# North wall.
	_make_box(parent, Vector3(x_span, wall_h, 0.40),
		Vector3((_WORLD_WEST + _WORLD_EAST) * 0.5, wall_h * 0.5, _WORLD_NORTH),
		wall_color)

	# South wall — split into two segments around the gate.
	var west_seg_w: float = (_WORLD_GATE_X - _WORLD_GATE_W * 0.5) - _WORLD_WEST
	var east_seg_w: float = _WORLD_EAST - (_WORLD_GATE_X + _WORLD_GATE_W * 0.5)
	if west_seg_w > 0.1:
		_make_box(parent, Vector3(west_seg_w, wall_h, 0.40),
			Vector3(_WORLD_WEST + west_seg_w * 0.5, wall_h * 0.5, _WORLD_SOUTH),
			wall_color)
	if east_seg_w > 0.1:
		_make_box(parent, Vector3(east_seg_w, wall_h, 0.40),
			Vector3(_WORLD_EAST - east_seg_w * 0.5, wall_h * 0.5, _WORLD_SOUTH),
			wall_color)
	# Gate posts on either side of the gap — taller, dark, so the
	# entrance reads from a distance.
	_make_box(parent, Vector3(0.60, wall_h * 1.5, 0.60),
		Vector3(_WORLD_GATE_X - _WORLD_GATE_W * 0.5, wall_h * 0.75, _WORLD_SOUTH),
		post_color)
	_make_box(parent, Vector3(0.60, wall_h * 1.5, 0.60),
		Vector3(_WORLD_GATE_X + _WORLD_GATE_W * 0.5, wall_h * 0.75, _WORLD_SOUTH),
		post_color)


func _build_approach_road(parent: Node3D) -> void:
	# Wide road from the south-edge gate northward into the parking
	# lot. The road ENTERS through the world wall (extends past the
	# gate by a few metres so it visibly leaves the playable area)
	# and ENDS at the parking lot's south edge.
	var road_w: float = 6.0
	# Outside the south wall — extends beyond the world boundary so
	# the road clearly continues "off-map".
	var off_map: Vector3 = Vector3(_WORLD_GATE_X, 0.04, _WORLD_SOUTH - 6.0)
	# Through the gate, into the world.
	var inside_gate: Vector3 = Vector3(_WORLD_GATE_X, 0.04, _WORLD_SOUTH + 0.6)
	# Parking south edge — south of the lot, in line with the gate.
	# We approximate a fixed point that always sits south of the lot
	# regardless of parking level (lot grows toward the +X side, not
	# south, so its south edge is ~constant relative to track tier).
	var parking_lot_d: float = _parking_lot_depth()
	var parking_south_z: float = -_track_outer_z(4.0) - parking_lot_d - 1.0
	var elbow: Vector3 = Vector3(_WORLD_GATE_X, 0.04, parking_south_z)
	# Final entry point lines up with the parking lot's south-east
	# corner so cars "drive in" from the road into the lot.
	var lot_w: float = _parking_lot_width()
	var parking_entry_x: float = -_track_outer_x(5.0) - lot_w * 0.5 - 1.5
	var parking_entry: Vector3 = Vector3(parking_entry_x, 0.04, parking_south_z)

	# Three road segments: gate → off-map (out), gate → elbow (down
	# into the venue), elbow → parking entry (east into the lot).
	_make_road(parent, off_map, inside_gate, road_w, _ROAD_COLOR)
	_make_road(parent, inside_gate, elbow, road_w, _ROAD_COLOR)
	_make_road(parent, elbow, parking_entry, road_w, _ROAD_COLOR)

	# Yellow centre-line dashes along each segment (skip the first
	# off-map → gate piece since it's mostly outside the camera).
	_paint_road_dashes(parent, inside_gate, elbow, 0.5)
	_paint_road_dashes(parent, elbow, parking_entry, 0.5)


func _paint_road_dashes(parent: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var length: float = dir.length()
	if length < 0.5:
		return
	var dash_count: int = maxi(1, int(length / 2.5))
	var rot_y: float = atan2(-dir.z, dir.x)
	for i in range(dash_count):
		var u: float = (float(i) + 0.5) / float(dash_count)
		var p := a.lerp(b, u)
		var dash := MeshInstance3D.new()
		var dbm := BoxMesh.new()
		dbm.size = Vector3(0.9, 0.06, width)
		dash.mesh = dbm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.95, 0.85, 0.20)
		dmat.emission_enabled = true
		dmat.emission = Color(0.95, 0.85, 0.20)
		dmat.emission_energy_multiplier = 0.6
		dash.material_override = dmat
		dash.position = Vector3(p.x, 0.10, p.z)
		dash.rotation.y = rot_y
		parent.add_child(dash)


# Parking lot dimension helpers — recompute the formulae used inside
# _build_parking() so the approach road can line up with the lot's
# south-east corner regardless of parking level.
func _parking_lot_width() -> float:
	var lvl: int = Facilities.parking_level
	if lvl <= 0:
		return 0.0
	var cols: int = clampi(5 + lvl / 4, 5, 22)
	return float(cols) * 1.6

func _parking_lot_depth() -> float:
	var lvl: int = Facilities.parking_level
	if lvl <= 0:
		return 0.0
	var rows: int = clampi(2 + lvl / 6, 2, 12)
	return float(rows) * 2.8


# ---------------------------------------------------------------------------
# Customer-driven visitor lifecycle
# ---------------------------------------------------------------------------
# Each Customer owns a visitor visual that runs through:
#   arriving → parked_arriving → walking_in → queueing → racing →
#   walking_out → leaving → departed
# A car drives in, parks, person walks out, joins the plaza queue,
# disappears into the kart while racing, reappears at the grandstand
# walkway after the race, walks back, gets in their car, drives out.
const _VISITOR_CAR_SPEED: float = 9.0
# 3.0 m/s — brisk walk, fast enough to cross the tier-10 parking lot
# and reach the plaza inside the customer's patience window.
const _VISITOR_WALK_SPEED: float = 3.0
const _VISITOR_PARK_PAUSE: float = 1.2     # seconds car waits before person exits


func _on_customer_arrived(customer_id: int) -> void:
	if _track == null or _visitors.has(customer_id):
		return
	var path: Array[Vector3] = _arrival_drive_path(customer_id)
	if path.is_empty():
		return
	var car_color := Color.from_hsv(randf(), randf_range(0.45, 0.75),
		randf_range(0.55, 0.85))
	var person_color: Color = _SPECTATOR_SHIRTS[randi() % _SPECTATOR_SHIRTS.size()]
	var car: Node3D = _build_visitor_car(car_color)
	car.position = Vector3(path[0].x, 0.35, path[0].z)
	_visitors[customer_id] = {
		"car": car,
		"car_color": car_color,
		"person": null,
		"person_color": person_color,
		"path": path,
		"idx": 0,
		"progress": 0.0,
		"state": "arriving",
		"wait_until": 0.0,
		# Plaza spot the person will stand on while queueing.
		"plaza_spot": _pick_plaza_spot(),
		# Parking spot key (set by _arrival_drive_path).
		"parking_spot": _last_assigned_spot,
	}


# Buffer for the most recently assigned parking spot — set inside
# _arrival_drive_path so _on_customer_arrived can pin it onto the
# visitor record without recomputing.
var _last_assigned_spot: Vector2i = Vector2i(-1, -1)


func _on_customer_left() -> void:
	# customer_left fires with (customer_id, satisfaction). The signal
	# bind drops both args; we don't need the id because we transition
	# every still-queueing or still-racing visitor whose Customer is
	# no longer in the live track.queue / track.racing arrays. The
	# per-frame _process() catches stragglers anyway.
	pass


func _process(delta: float) -> void:
	if _visitors.is_empty():
		return
	# Build a quick lookup of currently-live customer ids.
	var live_ids: Dictionary = {}
	if _track != null:
		for c: Customer in _track.queue:
			live_ids[c.id] = "queue"
		for c: Customer in _track.racing:
			live_ids[c.id] = "racing"
	# Tick every visitor + flag departures.
	var to_remove: Array = []
	for cid: int in _visitors.keys():
		var v: Dictionary = _visitors[cid]
		# State transitions driven by track state.
		var live_state: String = String(live_ids.get(cid, ""))
		var current_state: String = String(v.get("state", ""))
		if live_state == "racing" and current_state == "queueing":
			v["state"] = "racing"
			var person: Node3D = v.get("person")
			if person and is_instance_valid(person):
				person.visible = false
		elif live_state == "queue" and current_state == "racing":
			# Customer requeued (very rare) — show the person again.
			v["state"] = "queueing"
			var person2: Node3D = v.get("person")
			if person2 and is_instance_valid(person2):
				person2.visible = true
		elif live_state == "" and current_state in [
				"queueing", "racing", "walking_in", "parked_arriving"]:
			# Customer is gone — start the leaving sequence.
			_start_visitor_departure(v)
		_tick_visitor(v, delta)
		if v.get("state", "") == "departed":
			to_remove.append(cid)
	for cid: int in to_remove:
		_despawn_visitor(cid)


func _tick_visitor(v: Dictionary, delta: float) -> void:
	var state: String = String(v.get("state", ""))
	match state:
		"arriving":
			_advance_path(v, delta, _VISITOR_CAR_SPEED, "car")
			if v.get("idx", 0) >= (v.get("path", []) as Array).size() - 1:
				v["state"] = "parked_arriving"
				v["wait_until"] = _now_seconds() + _VISITOR_PARK_PAUSE
		"parked_arriving":
			if _now_seconds() >= float(v.get("wait_until", 0.0)):
				_begin_walk_in(v)
		"walking_in":
			_advance_path(v, delta, _VISITOR_WALK_SPEED, "person")
			if v.get("idx", 0) >= (v.get("path", []) as Array).size() - 1:
				v["state"] = "queueing"
		"queueing":
			pass  # idle on plaza
		"racing":
			pass  # person hidden; kart represents them
		"walking_out":
			_advance_path(v, delta, _VISITOR_WALK_SPEED, "person")
			if v.get("idx", 0) >= (v.get("path", []) as Array).size() - 1:
				_begin_drive_out(v)
		"leaving":
			_advance_path(v, delta, _VISITOR_CAR_SPEED, "car")
			if v.get("idx", 0) >= (v.get("path", []) as Array).size() - 1:
				v["state"] = "departed"
		"departed":
			pass


func _advance_path(v: Dictionary, delta: float, speed: float, target: String) -> void:
	var path: Array = v.get("path", [])
	var idx: int = int(v.get("idx", 0))
	if idx >= path.size() - 1:
		return
	var a: Vector3 = path[idx]
	var b: Vector3 = path[idx + 1]
	var seg: Vector3 = b - a
	var seg_len: float = seg.length()
	if seg_len < 0.01:
		v["idx"] = idx + 1
		v["progress"] = 0.0
		return
	var p_now: float = float(v.get("progress", 0.0)) + speed * delta / seg_len
	var node: Node3D = v.get(target) as Node3D
	if node == null or not is_instance_valid(node):
		return
	if p_now >= 1.0:
		v["progress"] = 0.0
		v["idx"] = idx + 1
		var snap_y: float = (0.35 if target == "car" else 0.0)
		node.position = Vector3(b.x, snap_y, b.z)
		return
	v["progress"] = p_now
	var pos: Vector3 = a.lerp(b, p_now)
	var y_off: float = (0.35 if target == "car" else 0.0)
	if target == "person":
		# Bob slightly while walking.
		y_off = sin(p_now * 12.0) * 0.04
	node.position = Vector3(pos.x, y_off, pos.z)
	# Face direction of motion.
	var dir2 := Vector2(seg.x, seg.z)
	if dir2.length_squared() > 0.0001:
		node.rotation.y = atan2(-dir2.y, dir2.x)


# Lifecycle helpers ---------------------------------------------------------
func _begin_walk_in(v: Dictionary) -> void:
	# Person spawns at the parked car and walks to the plaza spot.
	var car: Node3D = v.get("car") as Node3D
	if car == null:
		v["state"] = "departed"
		return
	var person: Node3D = _build_visitor_person(v.get("person_color", Color.WHITE))
	person.position = Vector3(car.position.x, 0.0, car.position.z)
	v["person"] = person
	v["path"] = _walk_to_plaza_path(car.position, v.get("plaza_spot", Vector3.ZERO))
	v["idx"] = 0
	v["progress"] = 0.0
	v["state"] = "walking_in"


func _start_visitor_departure(v: Dictionary) -> void:
	# Person walks back from plaza (or grandstand area, if they were
	# racing) to the car, then car drives out.
	var car: Node3D = v.get("car") as Node3D
	if car == null:
		v["state"] = "departed"
		return
	var person: Node3D = v.get("person") as Node3D
	# If the person was hidden during racing, reappear at the
	# grandstand walkway entrance to walk back from there.
	if person and not person.visible:
		var hub: Vector3 = _hub_position()
		var grandstand_z: float = -_track_outer_z(1.5)
		person.visible = true
		person.position = Vector3(0.0, 0.0,
			(hub.z + grandstand_z) * 0.5)
	if person == null or not is_instance_valid(person):
		# Edge case — just drive the car out.
		v["path"] = _drive_out_path(car.position)
		v["idx"] = 0
		v["progress"] = 0.0
		v["state"] = "leaving"
		return
	v["path"] = _walk_back_to_car_path(person.position, car.position)
	v["idx"] = 0
	v["progress"] = 0.0
	v["state"] = "walking_out"


func _begin_drive_out(v: Dictionary) -> void:
	# Hide the person (they're "in the car" now) and start the drive
	# out along the reverse approach road.
	var person: Node3D = v.get("person") as Node3D
	if person and is_instance_valid(person):
		person.queue_free()
	v["person"] = null
	var car: Node3D = v.get("car") as Node3D
	if car == null:
		v["state"] = "departed"
		return
	v["path"] = _drive_out_path(car.position)
	v["idx"] = 0
	v["progress"] = 0.0
	v["state"] = "leaving"


func _despawn_visitor(cid: int) -> void:
	var v: Dictionary = _visitors.get(cid, {})
	var car: Node3D = v.get("car") as Node3D
	var person: Node3D = v.get("person") as Node3D
	if car and is_instance_valid(car):
		car.queue_free()
	if person and is_instance_valid(person):
		person.queue_free()
	# Release the parking spot.
	var spot: Vector2i = v.get("parking_spot", Vector2i(-1, -1))
	if spot.x >= 0:
		_free_parking_spots.append(spot)
	_visitors.erase(cid)


# Path builders -------------------------------------------------------------
func _arrival_drive_path(customer_id: int) -> Array[Vector3]:
	# off-map → gate → elbow → lot_entry → assigned parking spot
	var lot_d: float = _parking_lot_depth()
	var lot_w: float = _parking_lot_width()
	if lot_d <= 0.0 or lot_w <= 0.0:
		_last_assigned_spot = Vector2i(-1, -1)
		return []
	# Pick a free parking spot. If pool is empty, refill from current
	# layout (some spots may have been freed since last refresh).
	if _free_parking_spots.is_empty():
		_rebuild_parking_spot_pool()
	if _free_parking_spots.is_empty():
		_last_assigned_spot = Vector2i(-1, -1)
		return []
	var spot: Vector2i = _free_parking_spots.pop_back()
	_last_assigned_spot = spot
	var spot_world: Vector3 = _parking_spot_to_world(spot)
	# Standard waypoints to the lot.
	var parking_south_z: float = -_track_outer_z(4.0) - lot_d - 1.0
	var parking_entry_x: float = -_track_outer_x(5.0) - lot_w * 0.5 - 1.5
	var off_map: Vector3 = Vector3(_WORLD_GATE_X, 0.04, _WORLD_SOUTH - 6.0)
	var inside_gate: Vector3 = Vector3(_WORLD_GATE_X, 0.04, _WORLD_SOUTH + 0.6)
	var elbow: Vector3 = Vector3(_WORLD_GATE_X, 0.04, parking_south_z)
	var lot_entry: Vector3 = Vector3(parking_entry_x, 0.04, parking_south_z)
	# Drive into the lot — first to the spot's column (along x), then
	# up its row (along z).
	var into_lot_x: Vector3 = Vector3(spot_world.x, 0.04, parking_south_z)
	return [off_map, inside_gate, elbow, lot_entry, into_lot_x, spot_world]


func _drive_out_path(from: Vector3) -> Array[Vector3]:
	var lot_d: float = _parking_lot_depth()
	var lot_w: float = _parking_lot_width()
	var parking_south_z: float = -_track_outer_z(4.0) - lot_d - 1.0
	var parking_entry_x: float = -_track_outer_x(5.0) - lot_w * 0.5 - 1.5
	var lot_entry: Vector3 = Vector3(parking_entry_x, 0.04, parking_south_z)
	var off_map: Vector3 = Vector3(_WORLD_GATE_X, 0.04, _WORLD_SOUTH - 6.0)
	var inside_gate: Vector3 = Vector3(_WORLD_GATE_X, 0.04, _WORLD_SOUTH + 0.6)
	var elbow: Vector3 = Vector3(_WORLD_GATE_X, 0.04, parking_south_z)
	# From parking spot → out via lot_entry → elbow → gate → off-map.
	var out_of_lot: Vector3 = Vector3(from.x, 0.04, parking_south_z)
	return [from, out_of_lot, lot_entry, elbow, inside_gate, off_map]


func _walk_to_plaza_path(from: Vector3, plaza_spot: Vector3) -> Array[Vector3]:
	# Walk from the parking spot toward the plaza, with a single
	# elbow at the parking lot's exit so the route looks deliberate.
	var lot_d: float = _parking_lot_depth()
	var lot_w: float = _parking_lot_width()
	var parking_south_z: float = -_track_outer_z(4.0) - lot_d - 1.0
	var parking_entry_x: float = -_track_outer_x(5.0) - lot_w * 0.5 - 1.5
	var lot_exit_walk: Vector3 = Vector3(parking_entry_x + 2.0, 0.0,
		parking_south_z + 2.0)
	return [
		Vector3(from.x, 0.0, from.z),
		lot_exit_walk,
		plaza_spot
	]


func _walk_back_to_car_path(from: Vector3, car_pos: Vector3) -> Array[Vector3]:
	var lot_d: float = _parking_lot_depth()
	var lot_w: float = _parking_lot_width()
	var parking_south_z: float = -_track_outer_z(4.0) - lot_d - 1.0
	var parking_entry_x: float = -_track_outer_x(5.0) - lot_w * 0.5 - 1.5
	var lot_exit_walk: Vector3 = Vector3(parking_entry_x + 2.0, 0.0,
		parking_south_z + 2.0)
	return [
		Vector3(from.x, 0.0, from.z),
		lot_exit_walk,
		Vector3(car_pos.x, 0.0, car_pos.z),
	]


func _parking_spot_to_world(spot: Vector2i) -> Vector3:
	var lvl: int = Facilities.parking_level
	var rows: int = clampi(2 + lvl / 6, 2, 12)
	var cols: int = clampi(5 + lvl / 4, 5, 22)
	var space_w: float = 1.6
	var space_d: float = 2.8
	var lot_w: float = float(cols) * space_w
	var lot_d: float = float(rows) * space_d
	var center_x: float = -_track_outer_x(5.0) - lot_w * 0.5
	var center_z: float = -_track_outer_z(4.0) - lot_d * 0.5
	var car_x: float = center_x - lot_w * 0.5 + float(spot.y) * space_w \
		+ space_w * 0.5
	var car_z: float = center_z - lot_d * 0.5 + float(spot.x) * space_d \
		+ space_d * 0.5
	return Vector3(car_x, 0.04, car_z)


func _pick_plaza_spot() -> Vector3:
	var hub: Vector3 = _hub_position()
	var plaza_z: float = hub.z
	var plaza_w: float = _track_outer_x(0.0) * 2.0 + 6.0
	var plaza_d: float = 8.0
	return Vector3(
		randf_range(-plaza_w * 0.40, plaza_w * 0.40),
		0.0,
		plaza_z + randf_range(-plaza_d * 0.40, plaza_d * 0.40))


# Mesh builders -------------------------------------------------------------
func _build_visitor_car(col: Color) -> Node3D:
	var car_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.55, 3.2)
	car_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.4
	mat.roughness = 0.5
	car_mesh.material_override = mat
	_traffic_holder.add_child(car_mesh)
	# Cabin
	var cabin := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(1.4, 0.45, 1.6)
	cabin.mesh = cbm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.12, 0.14, 0.18)
	cmat.roughness = 0.3
	cabin.material_override = cmat
	cabin.position = Vector3(0, 0.45, 0.1)
	car_mesh.add_child(cabin)
	# Wheels
	for off: Vector3 in [
		Vector3( 0.85, -0.18,  1.10),
		Vector3( 0.85, -0.18, -1.10),
		Vector3(-0.85, -0.18,  1.10),
		Vector3(-0.85, -0.18, -1.10),
	]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.22
		cyl.height = 0.16
		wheel.mesh = cyl
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.10, 0.10, 0.12)
		wmat.roughness = 0.85
		wheel.material_override = wmat
		wheel.position = off
		wheel.rotation = Vector3(0, 0, deg_to_rad(90))
		car_mesh.add_child(wheel)
	return car_mesh


func _build_visitor_person(shirt: Color) -> Node3D:
	var holder := Node3D.new()
	_customer_holder.add_child(holder)
	# Body
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.16
	bm.bottom_radius = 0.20
	bm.height = 0.60
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = shirt
	bmat.roughness = 0.9
	body.material_override = bmat
	body.position = Vector3(0, 0.30, 0)
	holder.add_child(body)
	# Head
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.26
	head.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = _SPECTATOR_SKIN
	hmat.roughness = 0.85
	head.material_override = hmat
	head.position = Vector3(0, 0.74, 0)
	holder.add_child(head)
	return holder


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
