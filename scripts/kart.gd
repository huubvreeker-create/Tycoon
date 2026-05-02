extends PathFollow3D
class_name Kart

const IDLE_SPEED_BASE: float = 6.0
const RACING_SPEED_BASE: float = 14.0
const PER_LEVEL_SPEED_BONUS: float = 0.04
# Cumulative level caps mirroring Track.TIER_LEVEL_CAPS so the kart
# visual tier (1-10) advances at the same milestones as the track.
const TIER_LEVEL_CAPS: Array[int] = [25, 50, 75, 100, 150, 200, 250, 300, 350, 450]

@export var kart_color: Color = Color(0.96, 0.27, 0.36)

var level: int = 1
var racing: bool = false

var body_mesh: MeshInstance3D
var cockpit_mesh: MeshInstance3D
var spoiler_mesh: MeshInstance3D
var front_wing_mesh: MeshInstance3D
var halo_mesh: MeshInstance3D
var beacon_mesh: MeshInstance3D
var wheel_meshes: Array[MeshInstance3D] = []
var click_area: Area3D
var body_material: StandardMaterial3D
var cockpit_material: StandardMaterial3D
var spoiler_material: StandardMaterial3D
var front_wing_material: StandardMaterial3D
var beacon_material: StandardMaterial3D
var wheel_material: StandardMaterial3D

# Tier-specific extras — created once, shown / hidden per tier.
var side_pod_left: MeshInstance3D
var side_pod_right: MeshInstance3D
var side_pod_material: StandardMaterial3D
var engine_block: MeshInstance3D
var engine_material: StandardMaterial3D
var steering_column: MeshInstance3D
var steering_material: StandardMaterial3D
var nose_cone: MeshInstance3D
var nose_material: StandardMaterial3D

var _flash_time: float = 0.0
var _flash_color: Color = Color.WHITE


# ---------------------------------------------------------------------------
# Tier-specific visual recipes. Each entry is the look at that tier.
# Progression intent:
#   Tier 1  – mini kart (open chassis platform, side pods, exposed seat)
#   Tier 2  – cadet kart (slightly bigger pods + small spoiler)
#   Tier 3  – shifter kart (longer wheelbase, taller engine block)
#   Tier 4  – superkart (front nose appears, bigger spoiler)
#   Tier 5  – junior open-wheel (no engine block, dedicated front wing)
#   Tier 6  – F4-style regional formula
#   Tier 7  – IndyCar (longer, oval-track aero, no halo)
#   Tier 8  – F3 (halo appears, modern formula proportions)
#   Tier 9  – F2 (bigger wings, F1-adjacent silhouette)
#   Tier 10 – F1 (full spec, longest body, biggest wings)
# ---------------------------------------------------------------------------

# Body chassis. Tier 1-3 are kart-thin platforms; tier 4 starts to grow
# into an open-wheel monocoque; tier 7-10 stretches into a full
# formula-car body.
const _BODY_SIZE := {
	 1: Vector3(0.70, 0.08, 1.05),
	 2: Vector3(0.72, 0.10, 1.30),
	 3: Vector3(0.75, 0.12, 1.65),
	 4: Vector3(0.82, 0.16, 2.10),
	 5: Vector3(0.90, 0.20, 2.55),
	 6: Vector3(0.90, 0.22, 2.90),
	 7: Vector3(0.88, 0.22, 3.30),
	 8: Vector3(0.85, 0.20, 3.55),
	 9: Vector3(0.82, 0.18, 3.85),
	10: Vector3(0.80, 0.16, 4.20),
}
const _BODY_Y := {
	1: 0.18, 2: 0.20, 3: 0.22, 4: 0.26, 5: 0.30,
	6: 0.30, 7: 0.28, 8: 0.26, 9: 0.24, 10: 0.22
}

const _COCKPIT_SIZE := {
	 1: Vector3(0.38, 0.20, 0.42),
	 2: Vector3(0.42, 0.22, 0.48),
	 3: Vector3(0.45, 0.24, 0.55),
	 4: Vector3(0.50, 0.28, 0.62),
	 5: Vector3(0.55, 0.32, 0.72),
	 6: Vector3(0.55, 0.32, 0.78),
	 7: Vector3(0.55, 0.32, 0.78),
	 8: Vector3(0.52, 0.32, 0.75),
	 9: Vector3(0.50, 0.32, 0.72),
	10: Vector3(0.48, 0.30, 0.68),
}
const _COCKPIT_OFFSET := {
	 1: Vector3(0, 0.36, 0.05),
	 2: Vector3(0, 0.40, 0.10),
	 3: Vector3(0, 0.46, 0.18),
	 4: Vector3(0, 0.50, 0.28),
	 5: Vector3(0, 0.55, 0.38),
	 6: Vector3(0, 0.58, 0.46),
	 7: Vector3(0, 0.56, 0.52),
	 8: Vector3(0, 0.54, 0.58),
	 9: Vector3(0, 0.52, 0.62),
	10: Vector3(0, 0.50, 0.65),
}

# Side pods — mini-kart fairings on tier 1-3, then aerodynamic body
# panels on tier 4+. ALL tiers have them so the silhouette never goes
# back to a bare box.
const _SIDE_POD_SIZE := {
	 1: Vector3(0.20, 0.16, 0.80),
	 2: Vector3(0.22, 0.18, 0.95),
	 3: Vector3(0.24, 0.20, 1.15),
	 4: Vector3(0.26, 0.22, 1.45),
	 5: Vector3(0.28, 0.24, 1.75),
	 6: Vector3(0.30, 0.26, 1.95),
	 7: Vector3(0.30, 0.26, 2.15),
	 8: Vector3(0.28, 0.26, 2.35),
	 9: Vector3(0.28, 0.26, 2.55),
	10: Vector3(0.28, 0.24, 2.75),
}
const _SIDE_POD_X := {
	1: 0.42, 2: 0.44, 3: 0.46, 4: 0.50, 5: 0.55,
	6: 0.58, 7: 0.60, 8: 0.62, 9: 0.64, 10: 0.66
}
const _SIDE_POD_Y := {
	1: 0.20, 2: 0.22, 3: 0.24, 4: 0.30, 5: 0.34,
	6: 0.34, 7: 0.32, 8: 0.30, 9: 0.28, 10: 0.26
}

# Exposed engine block — small, visible only on tier 1-4 (real karts +
# superkart). Disappears once we move into formula-style rear bodywork.
const _ENGINE_VISIBLE_TIERS: int = 4
const _ENGINE_SIZE := {
	1: Vector3(0.30, 0.28, 0.38),
	2: Vector3(0.32, 0.30, 0.45),
	3: Vector3(0.34, 0.32, 0.52),
	4: Vector3(0.30, 0.28, 0.50),
}
const _ENGINE_OFFSET := {
	1: Vector3(0.32, 0.30, 0.40),
	2: Vector3(0.34, 0.32, 0.50),
	3: Vector3(0.34, 0.34, 0.65),
	4: Vector3(0.32, 0.34, 0.80),
}

# Steering column — thin cylinder rising from the cockpit floor on
# tier 1-3 only (real karts have an exposed steering shaft).
const _STEERING_VISIBLE_TIERS: int = 3
const _STEERING_HEIGHT := {1: 0.40, 2: 0.42, 3: 0.42}

# Nose cone — appears on tier 4 (superkart) onwards.
const _NOSE_VISIBLE_FROM_TIER: int = 4
const _NOSE_SIZE := {
	 4: Vector3(0.34, 0.10, 0.55),
	 5: Vector3(0.40, 0.10, 0.70),
	 6: Vector3(0.45, 0.12, 0.85),
	 7: Vector3(0.55, 0.14, 1.05),
	 8: Vector3(0.55, 0.14, 1.18),
	 9: Vector3(0.55, 0.14, 1.30),
	10: Vector3(0.55, 0.14, 1.50),
}
const _NOSE_OFFSET := {
	 4: Vector3(0, 0.18, -0.85),
	 5: Vector3(0, 0.18, -1.00),
	 6: Vector3(0, 0.18, -1.15),
	 7: Vector3(0, 0.18, -1.30),
	 8: Vector3(0, 0.18, -1.40),
	 9: Vector3(0, 0.18, -1.50),
	10: Vector3(0, 0.18, -1.65),
}

# Rear spoilers / wings appear on tier 2; front wings on tier 5
# (replacing the bare nose cone). Halo arrives at tier 8 (F3+).
const _SPOILER_VISIBLE_FROM_TIER: int = 2
const _FRONT_WING_VISIBLE_FROM_TIER: int = 5
const _HALO_VISIBLE_FROM_TIER: int = 8

const _SPOILER_SIZE := {
	 2: Vector3(0.70, 0.18, 0.10),
	 3: Vector3(0.80, 0.24, 0.12),
	 4: Vector3(0.95, 0.32, 0.16),
	 5: Vector3(1.05, 0.40, 0.18),
	 6: Vector3(1.15, 0.46, 0.20),
	 7: Vector3(1.20, 0.50, 0.20),
	 8: Vector3(1.25, 0.54, 0.22),
	 9: Vector3(1.30, 0.58, 0.22),
	10: Vector3(1.35, 0.62, 0.22),
}
const _SPOILER_OFFSET := {
	 2: Vector3(0, 0.55, 0.55),
	 3: Vector3(0, 0.62, 0.78),
	 4: Vector3(0, 0.72, 1.00),
	 5: Vector3(0, 0.82, 1.20),
	 6: Vector3(0, 0.88, 1.40),
	 7: Vector3(0, 0.92, 1.55),
	 8: Vector3(0, 0.95, 1.65),
	 9: Vector3(0, 1.00, 1.78),
	10: Vector3(0, 1.05, 1.95),
}

const _FRONT_WING_SIZE := {
	 5: Vector3(1.05, 0.10, 0.30),
	 6: Vector3(1.15, 0.10, 0.34),
	 7: Vector3(1.20, 0.10, 0.38),
	 8: Vector3(1.25, 0.10, 0.40),
	 9: Vector3(1.32, 0.10, 0.42),
	10: Vector3(1.45, 0.10, 0.50),
}
const _FRONT_WING_OFFSET := {
	 5: Vector3(0, 0.14, -1.32),
	 6: Vector3(0, 0.14, -1.50),
	 7: Vector3(0, 0.14, -1.65),
	 8: Vector3(0, 0.14, -1.78),
	 9: Vector3(0, 0.14, -1.90),
	10: Vector3(0, 0.13, -2.10),
}

const _WHEEL_RADIUS := {
	1: 0.16, 2: 0.18, 3: 0.20, 4: 0.22, 5: 0.25,
	6: 0.27, 7: 0.29, 8: 0.30, 9: 0.31, 10: 0.34
}
const _WHEEL_HEIGHT := {
	1: 0.13, 2: 0.14, 3: 0.15, 4: 0.16, 5: 0.18,
	6: 0.19, 7: 0.20, 8: 0.21, 9: 0.22, 10: 0.24
}
const _WHEEL_X := {
	1: 0.50, 2: 0.54, 3: 0.58, 4: 0.62, 5: 0.66,
	6: 0.68, 7: 0.70, 8: 0.72, 9: 0.73, 10: 0.74
}
const _WHEEL_Z := {
	1: 0.45, 2: 0.55, 3: 0.72, 4: 0.90, 5: 1.05,
	6: 1.18, 7: 1.30, 8: 1.40, 9: 1.50, 10: 1.65
}

const _BEACON_SIZE := {
	 1: Vector3(0.30, 0.30, 0.30),
	 2: Vector3(0.30, 0.28, 0.30),
	 3: Vector3(0.32, 0.24, 0.32),
	 4: Vector3(0.30, 0.20, 0.30),
	 5: Vector3(0.28, 0.18, 0.28),
	 6: Vector3(0.26, 0.16, 0.26),
	 7: Vector3(0.24, 0.14, 0.24),
	 8: Vector3(0.22, 0.12, 0.22),
	 9: Vector3(0.20, 0.11, 0.20),
	10: Vector3(0.18, 0.10, 0.18),
}
const _BEACON_Y := {
	1: 0.42, 2: 0.46, 3: 0.55, 4: 0.65, 5: 0.78,
	6: 0.84, 7: 0.82, 8: 0.78, 9: 0.74, 10: 0.70
}


func _ready() -> void:
	loop = true
	rotation_mode = PathFollow3D.ROTATION_Y
	_build_meshes()
	_build_click_area()
	_apply_visuals()


func _process(delta: float) -> void:
	progress += current_speed() * delta
	if _flash_time > 0.0:
		_flash_time -= delta
		var t: float = clampf(_flash_time / 0.6, 0.0, 1.0)
		body_material.emission_enabled = true
		body_material.emission = _flash_color
		body_material.emission_energy_multiplier = t * 2.0
		if _flash_time <= 0.0:
			body_material.emission_enabled = true
			body_material.emission = kart_color
			body_material.emission_energy_multiplier = 0.6 if racing else 0.4


func tier() -> int:
	for i in range(TIER_LEVEL_CAPS.size()):
		if level <= TIER_LEVEL_CAPS[i]:
			return i + 1
	return TIER_LEVEL_CAPS.size()


# Fraction (0..1) of progress through the current tier — used to
# interpolate every dimension toward the next tier so the kart morphs
# continuously per upgrade instead of snapping at tier boundaries.
func _tier_progress() -> float:
	var t: int = tier()
	if t >= TIER_LEVEL_CAPS.size():
		return 0.0
	var prev_cap: int = 0 if t == 1 else TIER_LEVEL_CAPS[t - 2]
	var current_cap: int = TIER_LEVEL_CAPS[t - 1]
	var span: int = current_cap - prev_cap
	if span <= 1:
		return 0.0
	return float(level - prev_cap - 1) / float(span - 1)


func _lerp_v3_table(table: Dictionary) -> Vector3:
	var t: int = tier()
	if not table.has(t):
		return Vector3.ZERO
	var base_v: Vector3 = table[t]
	if not table.has(t + 1):
		return base_v
	var next_v: Vector3 = table[t + 1]
	return base_v.lerp(next_v, _tier_progress())


func _lerp_f_table(table: Dictionary) -> float:
	var t: int = tier()
	if not table.has(t):
		return 0.0
	var base_v: float = float(table[t])
	if not table.has(t + 1):
		return base_v
	var next_v: float = float(table[t + 1])
	return lerpf(base_v, next_v, _tier_progress())


func current_speed() -> float:
	var base := RACING_SPEED_BASE if racing else IDLE_SPEED_BASE
	var component_bonus := KartComponents.engine_speed_bonus()
	return base + (level - 1) * PER_LEVEL_SPEED_BONUS + component_bonus


func is_busy() -> bool:
	return racing


func set_racing(active: bool) -> void:
	if racing == active:
		return
	racing = active
	_refresh_emission()


func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, 450)
	_apply_visuals()
	# Wheels interpolate every level too, so rebuild in place each
	# upgrade so radius / spacing nudge alongside the body.
	if body_material != null:
		_rebuild_wheels()


func flash_finish(satisfaction: float) -> void:
	_flash_time = 0.6
	_flash_color = Color(0.55, 0.92, 0.38) if satisfaction >= 0.6 else Color(0.96, 0.27, 0.36)


func flash_spawn() -> void:
	_flash_time = 0.6
	_flash_color = Color.WHITE


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
func _build_meshes() -> void:
	body_material = _make_body_material()
	cockpit_material = _make_simple_material(kart_color.darkened(0.45), 0.6)
	spoiler_material = _make_simple_material(kart_color.darkened(0.2), 0.5)
	front_wing_material = _make_simple_material(kart_color.darkened(0.15), 0.45)
	beacon_material = _make_emissive_material(kart_color.lightened(0.25), kart_color, 1.6)
	wheel_material = _make_simple_material(Color(0.08, 0.08, 0.10), 0.8)
	side_pod_material = _make_simple_material(kart_color, 0.45)
	engine_material = _make_simple_material(Color(0.18, 0.18, 0.20), 0.7)
	steering_material = _make_simple_material(Color(0.12, 0.12, 0.14), 0.7)
	nose_material = _make_simple_material(kart_color.darkened(0.10), 0.45)

	body_mesh = _make_box_mesh("Body", Vector3.ONE, body_material)
	cockpit_mesh = _make_box_mesh("Cockpit", Vector3.ONE, cockpit_material)
	spoiler_mesh = _make_box_mesh("Spoiler", Vector3.ONE, spoiler_material)
	front_wing_mesh = _make_box_mesh("FrontWing", Vector3.ONE, front_wing_material)
	beacon_mesh = _make_box_mesh("Beacon", Vector3.ONE, beacon_material)
	side_pod_left = _make_box_mesh("SidePodLeft", Vector3.ONE, side_pod_material)
	side_pod_right = _make_box_mesh("SidePodRight", Vector3.ONE, side_pod_material)
	engine_block = _make_box_mesh("EngineBlock", Vector3.ONE, engine_material)
	nose_cone = _make_box_mesh("NoseCone", Vector3.ONE, nose_material)

	# Steering column — thin angled cylinder on tier 1-3 only.
	steering_column = MeshInstance3D.new()
	steering_column.name = "SteeringColumn"
	var sc := CylinderMesh.new()
	sc.top_radius = 0.018
	sc.bottom_radius = 0.022
	sc.height = 0.40
	steering_column.mesh = sc
	steering_column.material_override = steering_material
	# Tilted slightly forward so it looks like a real kart steering shaft.
	steering_column.rotation = Vector3(deg_to_rad(15), 0, 0)
	add_child(steering_column)

	# Halo — torus around the cockpit, formula-tier cosmetic only.
	halo_mesh = MeshInstance3D.new()
	halo_mesh.name = "Halo"
	var halo := TorusMesh.new()
	halo.inner_radius = 0.36
	halo.outer_radius = 0.44
	halo_mesh.mesh = halo
	var halo_mat := _make_emissive_material(kart_color.lightened(0.45), kart_color.lightened(0.5), 1.2)
	halo_mesh.material_override = halo_mat
	halo_mesh.rotation = Vector3(deg_to_rad(90), 0, 0)
	add_child(halo_mesh)

	_rebuild_wheels()


func _rebuild_wheels() -> void:
	for w: MeshInstance3D in wheel_meshes:
		w.queue_free()
	wheel_meshes.clear()
	var radius: float = _lerp_f_table(_WHEEL_RADIUS)
	var height: float = _lerp_f_table(_WHEEL_HEIGHT)
	var ox: float = _lerp_f_table(_WHEEL_X)
	var oz: float = _lerp_f_table(_WHEEL_Z)
	for offset: Vector3 in [
		Vector3( ox, radius,  oz),
		Vector3( ox, radius, -oz),
		Vector3(-ox, radius,  oz),
		Vector3(-ox, radius, -oz),
	]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = height
		wheel.mesh = cyl
		wheel.material_override = wheel_material
		wheel.position = offset
		# Cylinder axis (Y) → X via Z rotation 90°
		wheel.rotation = Vector3(0, 0, deg_to_rad(90))
		add_child(wheel)
		wheel_meshes.append(wheel)


func _build_click_area() -> void:
	click_area = Area3D.new()
	click_area.name = "KartClick"
	click_area.collision_layer = 1
	click_area.collision_mask = 1
	click_area.add_to_group("kart_clickable")
	click_area.set_meta("kind", "kart")
	add_child(click_area)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.6, 4.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, 0.8, 0)
	click_area.add_child(collider)


func _apply_visuals() -> void:
	if body_material == null:
		return
	var t: int = tier()
	var p: float = _tier_progress()

	# --- Body --- continuous lerp between this tier's recipe and next.
	(body_mesh.mesh as BoxMesh).size = _lerp_v3_table(_BODY_SIZE)
	body_mesh.position = Vector3(0, _lerp_f_table(_BODY_Y), 0)
	body_material.albedo_color = kart_color
	body_material.metallic = 0.20 + (float(t) - 1.0 + p) * 0.10
	body_material.roughness = maxf(0.10, 0.50 - (float(t) - 1.0 + p) * 0.06)

	# --- Cockpit ---
	(cockpit_mesh.mesh as BoxMesh).size = _lerp_v3_table(_COCKPIT_SIZE)
	cockpit_mesh.position = _lerp_v3_table(_COCKPIT_OFFSET)
	cockpit_material.albedo_color = kart_color.darkened(0.45)

	# --- Side pods (mini-kart fairings → F1 sidepods, all tiers) ---
	var pod_size: Vector3 = _lerp_v3_table(_SIDE_POD_SIZE)
	var pod_x: float = _lerp_f_table(_SIDE_POD_X)
	var pod_y: float = _lerp_f_table(_SIDE_POD_Y)
	(side_pod_left.mesh as BoxMesh).size = pod_size
	side_pod_left.position = Vector3(-pod_x, pod_y, 0)
	(side_pod_right.mesh as BoxMesh).size = pod_size
	side_pod_right.position = Vector3(pod_x, pod_y, 0)
	side_pod_material.albedo_color = kart_color

	# --- Exposed engine block (mini-kart era only, tiers 1-4) ---
	if t <= _ENGINE_VISIBLE_TIERS:
		engine_block.visible = true
		(engine_block.mesh as BoxMesh).size = _lerp_v3_table(_ENGINE_SIZE)
		engine_block.position = _lerp_v3_table(_ENGINE_OFFSET)
	else:
		engine_block.visible = false

	# --- Steering column (real-kart era only, tiers 1-3) ---
	if t <= _STEERING_VISIBLE_TIERS:
		steering_column.visible = true
		var col_h: float = _lerp_f_table(_STEERING_HEIGHT)
		(steering_column.mesh as CylinderMesh).height = col_h
		# Position the column rising out of the cockpit floor.
		var ck_offset: Vector3 = _lerp_v3_table(_COCKPIT_OFFSET)
		steering_column.position = Vector3(0, ck_offset.y + col_h * 0.5,
			ck_offset.z - 0.15)
	else:
		steering_column.visible = false

	# --- Nose cone (superkart → F1, tiers 4+) ---
	if t >= _NOSE_VISIBLE_FROM_TIER:
		nose_cone.visible = true
		(nose_cone.mesh as BoxMesh).size = _lerp_v3_table(_NOSE_SIZE)
		nose_cone.position = _lerp_v3_table(_NOSE_OFFSET)
		nose_material.albedo_color = kart_color.darkened(0.10)
	else:
		nose_cone.visible = false

	# --- Rear spoiler — from tier 2 ---
	if t >= _SPOILER_VISIBLE_FROM_TIER:
		spoiler_mesh.visible = true
		(spoiler_mesh.mesh as BoxMesh).size = _lerp_v3_table(_SPOILER_SIZE)
		spoiler_mesh.position = _lerp_v3_table(_SPOILER_OFFSET)
		spoiler_material.albedo_color = kart_color.darkened(0.2)
	else:
		spoiler_mesh.visible = false

	# --- Front wing (junior open-wheel onwards, tier 5+) ---
	if t >= _FRONT_WING_VISIBLE_FROM_TIER:
		front_wing_mesh.visible = true
		(front_wing_mesh.mesh as BoxMesh).size = _lerp_v3_table(_FRONT_WING_SIZE)
		front_wing_mesh.position = _lerp_v3_table(_FRONT_WING_OFFSET)
		front_wing_material.albedo_color = kart_color.darkened(0.15)
	else:
		front_wing_mesh.visible = false

	# --- Halo (F3+ safety device, tier 8+) ---
	if t >= _HALO_VISIBLE_FROM_TIER:
		halo_mesh.visible = true
		halo_mesh.position = _lerp_v3_table(_COCKPIT_OFFSET) + Vector3(0, 0.45, 0)
	else:
		halo_mesh.visible = false

	# --- Beacon (always-on glow) ---
	(beacon_mesh.mesh as BoxMesh).size = _lerp_v3_table(_BEACON_SIZE)
	beacon_mesh.position = Vector3(0, _lerp_f_table(_BEACON_Y), 0)
	beacon_material.albedo_color = kart_color.lightened(0.25)
	beacon_material.emission = kart_color


func _refresh_emission() -> void:
	if body_material == null:
		return
	body_material.emission_enabled = true
	body_material.emission = kart_color
	body_material.emission_energy_multiplier = 0.6 if racing else 0.4


# --- Mesh / material helpers ----------------------------------------------
func _make_box_mesh(name_: String, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	return mi


func _make_body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = kart_color
	m.metallic = 0.2
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = kart_color
	m.emission_energy_multiplier = 0.4
	return m


func _make_simple_material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _make_emissive_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m
