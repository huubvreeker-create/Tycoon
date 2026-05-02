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


func _ready() -> void:
	_track = get_node_or_null(track_path) as Track
	for facility: String in Facilities.facility_names():
		var holder := Node3D.new()
		holder.name = facility.capitalize() + "Holder"
		add_child(holder)
		_root_holders[facility] = holder
	EventBus.facility_upgraded.connect(_on_facility_upgraded)
	EventBus.track_tier_changed.connect(_on_tier_changed.unbind(2))
	# Defer first build so the track has constructed its path/footprint.
	call_deferred("_rebuild_all")


func _rebuild_all() -> void:
	for facility: String in Facilities.facility_names():
		_rebuild_one(facility)


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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _track_rx() -> float:
	return _track.TIER_TRACK_RX[_track.track_tier()]

func _track_rz() -> float:
	return _track.TIER_TRACK_RZ[_track.track_tier()]

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


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func _build_cafeteria(parent: Node3D, level: int) -> void:
	# A real café: main building + covered patio + tables with parasols
	# + signage on the front.  Sits on the LEFT (-X) side of the venue.
	var rx := _track_rx()
	var w: float = 6.0 + level * 0.20
	var d: float = 4.5 + level * 0.16
	var h: float = 3.0 + level * 0.12
	var building_pos := Vector3(-rx - 8.0, h * 0.5, 0.0)

	# Main building.
	_make_box(parent, Vector3(w, h, d), building_pos, _CAFETERIA_COLOR.darkened(0.55))

	# Lit-up sign band on the side facing the track.
	_make_label_strip(parent, _CAFETERIA_COLOR,
		building_pos + Vector3(w * 0.5 + 0.05, h * 0.25, 0),
		Vector3(0.06, 0.40, d * 0.85))

	# Patio in front of the building (between building and track).
	var patio_d: float = 3.0 + level * 0.10
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


func _build_pit_lane(parent: Node3D, level: int) -> void:
	# A real pit complex: pit lane (asphalt) parallel to the track's long
	# straight, separated by a pit wall, with a row of garages on the
	# outside and short asphalt connectors merging the pit lane back into
	# the main track at each end. Scales with level.
	var rx := _track_rx()
	var rz := _track_rz()
	var asphalt_color := Color(0.10, 0.11, 0.14)

	# Pit straight runs along the long axis (X) on the +Z side.
	var pit_lane_width: float = 2.6 + level * 0.06
	var pit_lane_length: float = rx * 1.2
	var pit_lane_z: float = rz + 4.0 + pit_lane_width * 0.5
	# Asphalt
	_make_box(parent, Vector3(pit_lane_length, 0.08, pit_lane_width),
		Vector3(0, 0.04, pit_lane_z),
		asphalt_color)
	# Centre line markings (small white dashes along the pit lane).
	var dash_count: int = 8
	for i in range(dash_count):
		var u: float = (float(i) + 0.5) / float(dash_count)
		var dx: float = (u - 0.5) * pit_lane_length * 0.92
		_make_box(parent, Vector3(0.45, 0.10, 0.10),
			Vector3(dx, 0.08, pit_lane_z),
			Color(0.85, 0.85, 0.90))

	# Pit wall — between the pit lane and the main track.
	var wall_h: float = 0.55
	var wall_z: float = pit_lane_z - pit_lane_width * 0.5 - 0.15
	_make_box(parent, Vector3(pit_lane_length * 0.96, wall_h, 0.18),
		Vector3(0, wall_h * 0.5, wall_z),
		Color(0.92, 0.92, 0.95))
	# Wall base accent (cyan stripe along the top of the wall).
	_make_label_strip(parent, _PIT_LANE_COLOR,
		Vector3(0, wall_h + 0.05, wall_z),
		Vector3(pit_lane_length * 0.96, 0.10, 0.20))

	# Garage row on the OUTSIDE of the pit lane (further from the track).
	var bays: int = clampi(level, 1, 8)
	var bay_w: float = 2.6
	var bay_d: float = 3.4 + level * 0.05
	var bay_h: float = 2.6 + level * 0.05
	var total_garages_length: float = bays * bay_w
	var garage_z: float = pit_lane_z + pit_lane_width * 0.5 + bay_d * 0.5 + 0.15
	for i in range(bays):
		var bay_x: float = -total_garages_length * 0.5 + i * bay_w + bay_w * 0.5
		# Garage box
		_make_box(parent, Vector3(bay_w * 0.95, bay_h, bay_d),
			Vector3(bay_x, bay_h * 0.5, garage_z),
			_PIT_LANE_COLOR.darkened(0.65))
		# Open door front (lighter slab on the side facing the pit lane)
		_make_label_strip(parent, _PIT_LANE_COLOR,
			Vector3(bay_x, bay_h * 0.4, garage_z - bay_d * 0.5 - 0.01),
			Vector3(bay_w * 0.78, bay_h * 0.75, 0.05))
		# Bay number plate above the door
		_make_label_strip(parent, _PIT_LANE_COLOR.lightened(0.2),
			Vector3(bay_x, bay_h + 0.10, garage_z - bay_d * 0.5 - 0.01),
			Vector3(bay_w * 0.5, 0.18, 0.04))
	# Garage roof spanning the bays
	_make_box(parent, Vector3(total_garages_length + 0.3, 0.20, bay_d + 0.4),
		Vector3(0, bay_h + 0.10, garage_z),
		_PIT_LANE_COLOR.darkened(0.35))

	# Connector slips at the two ends of the pit straight, visually
	# merging the pit lane back into the main track.
	var connector_length: float = 5.0
	var connector_width: float = pit_lane_width * 0.85
	# Direction is rotated ~30° so it visibly bends toward the track.
	for sign_x: int in [-1, 1]:
		var connector_pos := Vector3(
			float(sign_x) * (pit_lane_length * 0.5 + connector_length * 0.45),
			0.04,
			pit_lane_z * 0.55)
		var connector := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(connector_length, 0.08, connector_width)
		connector.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = asphalt_color
		mat.roughness = 0.85
		connector.material_override = mat
		connector.position = connector_pos
		# Rotate to angle toward the track (around Y axis).
		connector.rotation.y = deg_to_rad(28.0 * float(sign_x))
		parent.add_child(connector)


func _build_lounge(parent: Node3D, level: int) -> void:
	# Multi-storey hospitality block with glass strips on three sides and
	# a roof terrace. Scales taller with level.
	var rz := _track_rz()
	var w: float = 5.0 + level * 0.18
	var d: float = 5.0 + level * 0.18
	var floors: int = clampi(2 + level / 3, 2, 6)
	var floor_h: float = 1.4
	var h: float = floor_h * float(floors) + 0.6
	var pos := Vector3(0.0, h * 0.5, -rz - 7.0 - d * 0.3)

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


func _build_merch_shop(parent: Node3D, level: int) -> void:
	# Green kiosk at the +X end of the venue (other end from the
	# cafeteria — we leave +Z free for the pit complex).
	var rx := _track_rx()
	var w: float = 3.5 + level * 0.18
	var d: float = 3.0 + level * 0.14
	var h: float = 2.2 + level * 0.10
	var pos := Vector3(rx + 5.5 + w * 0.3, h * 0.5, 0.0)
	_make_box(parent, Vector3(w, h, d), pos, _MERCH_COLOR.darkened(0.55))
	# Sign band on the side facing the track.
	_make_label_strip(parent, _MERCH_COLOR,
		pos + Vector3(-w * 0.5 - 0.05, h * 0.4, 0),
		Vector3(0.06, 0.30, d * 0.8))
	# Awning over the entrance (extends toward the track, -X).
	_make_box(parent, Vector3(w * 0.4, 0.08, d * 1.15),
		pos + Vector3(-w * 0.5 - w * 0.2, h * 0.55, 0),
		_MERCH_COLOR)


func _build_sponsor_boards(parent: Node3D, level: int) -> void:
	# Vertical billboards arranged around the outside of the rumble strip.
	var board_count := mini(level * 2, 16)
	var rx := _track_rx() + 1.6
	var rz := _track_rz() + 1.6
	var w := 2.6
	var h := 1.2
	for i in range(board_count):
		var t := float(i) / float(board_count) * TAU
		var x := cos(t) * rx
		var z := sin(t) * rz
		var color: Color = _SPONSOR_COLORS[i % _SPONSOR_COLORS.size()]
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


func _build_lighting(parent: Node3D, level: int) -> void:
	# Tall poles + light fixtures at corners of the track footprint.
	var rx := _track_rx() + 3.0
	var rz := _track_rz() + 3.0
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
