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
	# Yellow box on the LEFT of the venue, height + footprint scale w/ level.
	var rx := _track_rx()
	var w := 5.0 + level * 0.25
	var d := 4.0 + level * 0.18
	var h := 2.4 + level * 0.18
	var pos := Vector3(-rx - 6.0 - w * 0.3, h * 0.5, 0.0)
	_make_box(parent, Vector3(w, h, d), pos, _CAFETERIA_COLOR.darkened(0.5))
	# Bright sign band at top
	_make_label_strip(parent, _CAFETERIA_COLOR, pos + Vector3(0, h * 0.5 + 0.15, d * 0.5 + 0.05), Vector3(w * 0.85, 0.25, 0.05))
	# Decorative pavilion box
	_make_box(parent, Vector3(w * 0.4, 0.25, d * 1.6), pos + Vector3(0, -h * 0.5 + 0.12, 0), _CAFETERIA_COLOR.darkened(0.7))


func _build_pit_lane(parent: Node3D, level: int) -> void:
	# Long thin garage along the RIGHT of the track. Number of garage bays
	# grows with level; bay material is metallic.
	var rx := _track_rx()
	var rz := _track_rz()
	var bays := mini(level, 8)
	var bay_w := 2.0
	var total_w := bays * bay_w + 0.4
	var d := 3.0 + level * 0.10
	var h := 2.2 + level * 0.05
	var center_x := rx + 5.5 + d * 0.5
	for i in range(bays):
		var x := center_x
		var z := -total_w * 0.5 + i * bay_w + bay_w * 0.5
		_make_box(parent, Vector3(d, h, bay_w * 0.95), Vector3(x, h * 0.5, z), _PIT_LANE_COLOR.darkened(0.65))
		# Door inset (lighter)
		_make_label_strip(parent, _PIT_LANE_COLOR, Vector3(x - d * 0.5 - 0.02, h * 0.4, z), Vector3(0.04, h * 0.7, bay_w * 0.7))
	# Roof line capping all bays
	_make_box(parent, Vector3(d + 0.4, 0.25, total_w + 0.2), Vector3(center_x, h + 0.12, 0), _PIT_LANE_COLOR.darkened(0.4))
	# Suppress unused variable warning
	if rz > 0.0:
		pass


func _build_lounge(parent: Node3D, level: int) -> void:
	# Tall purple tower at the FRONT (-Z) of the venue.
	var rz := _track_rz()
	var w := 4.5 + level * 0.20
	var d := 4.5 + level * 0.20
	var h := 4.0 + level * 0.55  # grows tall
	var pos := Vector3(0.0, h * 0.5, -rz - 6.5 - d * 0.3)
	_make_box(parent, Vector3(w, h, d), pos, _LOUNGE_COLOR.darkened(0.55))
	# Glowing window strips up the side
	for i in range(maxi(2, level / 2)):
		var y := -h * 0.5 + 1.0 + i * 0.9
		if y >= h * 0.5 - 0.4:
			break
		_make_label_strip(parent, _LOUNGE_COLOR.lightened(0.2), pos + Vector3(0, y, d * 0.5 + 0.05), Vector3(w * 0.7, 0.25, 0.05))
	# Crown beacon at the very top
	_make_label_strip(parent, _LOUNGE_COLOR, pos + Vector3(0, h * 0.5 + 0.2, 0), Vector3(0.6, 0.4, 0.6))


func _build_merch_shop(parent: Node3D, level: int) -> void:
	# Green kiosk at the BACK (+Z) of the venue.
	var rz := _track_rz()
	var w := 3.5 + level * 0.18
	var d := 3.0 + level * 0.14
	var h := 2.2 + level * 0.10
	var pos := Vector3(0.0, h * 0.5, rz + 5.5 + d * 0.3)
	_make_box(parent, Vector3(w, h, d), pos, _MERCH_COLOR.darkened(0.55))
	_make_label_strip(parent, _MERCH_COLOR, pos + Vector3(0, h * 0.5 + 0.15, -d * 0.5 - 0.05), Vector3(w * 0.85, 0.25, 0.05))
	# Awning
	_make_box(parent, Vector3(w * 1.15, 0.08, d * 0.4), pos + Vector3(0, h * 0.55, -d * 0.5 - d * 0.2), _MERCH_COLOR)


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
