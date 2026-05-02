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

var _flash_time: float = 0.0
var _flash_color: Color = Color.WHITE


# ---------------------------------------------------------------------------
# Tier-specific visual recipes. Each entry is the look at that tier.
# Vehicles get LONGER / LOWER / NARROWER as they progress (F1 silhouette);
# spoilers + wings get bigger; wheels get larger and more exposed.
# ---------------------------------------------------------------------------
# 10-tier kart silhouettes — gradual evolution from squat kid-kart to
# full F1 over ten visible steps. Body LOWER, NARROWER, LONGER as tier
# climbs; spoilers + front wings appear and grow; wheels get bigger
# and pushed wider apart.
const _BODY_SIZE := {
	 1: Vector3(0.95, 0.30, 1.4),
	 2: Vector3(0.95, 0.30, 1.6),
	 3: Vector3(0.95, 0.28, 1.9),
	 4: Vector3(0.95, 0.28, 2.2),
	 5: Vector3(0.92, 0.26, 2.6),
	 6: Vector3(0.90, 0.24, 2.9),
	 7: Vector3(0.88, 0.22, 3.2),
	 8: Vector3(0.85, 0.22, 3.5),
	 9: Vector3(0.85, 0.20, 3.8),
	10: Vector3(0.82, 0.18, 4.2),
}
const _BODY_Y := {
	1: 0.36, 2: 0.36, 3: 0.34, 4: 0.32, 5: 0.30,
	6: 0.28, 7: 0.26, 8: 0.25, 9: 0.24, 10: 0.22
}

const _COCKPIT_SIZE := {
	 1: Vector3(0.50, 0.26, 0.55),
	 2: Vector3(0.52, 0.28, 0.60),
	 3: Vector3(0.55, 0.30, 0.65),
	 4: Vector3(0.55, 0.30, 0.70),
	 5: Vector3(0.55, 0.32, 0.75),
	 6: Vector3(0.55, 0.32, 0.78),
	 7: Vector3(0.55, 0.32, 0.78),
	 8: Vector3(0.52, 0.32, 0.75),
	 9: Vector3(0.50, 0.32, 0.72),
	10: Vector3(0.48, 0.30, 0.68),
}
const _COCKPIT_OFFSET := {
	 1: Vector3(0, 0.55, 0.15),
	 2: Vector3(0, 0.58, 0.18),
	 3: Vector3(0, 0.60, 0.22),
	 4: Vector3(0, 0.60, 0.30),
	 5: Vector3(0, 0.60, 0.40),
	 6: Vector3(0, 0.58, 0.48),
	 7: Vector3(0, 0.56, 0.55),
	 8: Vector3(0, 0.54, 0.60),
	 9: Vector3(0, 0.52, 0.62),
	10: Vector3(0, 0.50, 0.65),
}

const _SPOILER_SIZE := {
	 1: Vector3.ZERO,
	 2: Vector3(0.75, 0.20, 0.10),
	 3: Vector3(0.85, 0.28, 0.14),
	 4: Vector3(0.95, 0.34, 0.16),
	 5: Vector3(1.05, 0.42, 0.18),
	 6: Vector3(1.15, 0.46, 0.20),
	 7: Vector3(1.20, 0.50, 0.20),
	 8: Vector3(1.25, 0.54, 0.22),
	 9: Vector3(1.30, 0.58, 0.22),
	10: Vector3(1.35, 0.62, 0.22),
}
const _SPOILER_OFFSET := {
	 1: Vector3.ZERO,
	 2: Vector3(0, 0.60, 0.65),
	 3: Vector3(0, 0.65, 0.85),
	 4: Vector3(0, 0.75, 1.00),
	 5: Vector3(0, 0.82, 1.18),
	 6: Vector3(0, 0.88, 1.35),
	 7: Vector3(0, 0.92, 1.50),
	 8: Vector3(0, 0.95, 1.62),
	 9: Vector3(0, 1.00, 1.75),
	10: Vector3(0, 1.05, 1.95),
}

const _FRONT_WING_SIZE := {
	 1: Vector3.ZERO,
	 2: Vector3.ZERO,
	 3: Vector3(0.85, 0.08, 0.22),
	 4: Vector3(0.95, 0.08, 0.26),
	 5: Vector3(1.05, 0.10, 0.30),
	 6: Vector3(1.15, 0.10, 0.34),
	 7: Vector3(1.20, 0.10, 0.38),
	 8: Vector3(1.25, 0.10, 0.40),
	 9: Vector3(1.32, 0.10, 0.42),
	10: Vector3(1.45, 0.10, 0.50),
}
const _FRONT_WING_OFFSET := {
	 1: Vector3.ZERO,
	 2: Vector3.ZERO,
	 3: Vector3(0, 0.18, -1.00),
	 4: Vector3(0, 0.16, -1.15),
	 5: Vector3(0, 0.16, -1.32),
	 6: Vector3(0, 0.15, -1.50),
	 7: Vector3(0, 0.15, -1.65),
	 8: Vector3(0, 0.14, -1.78),
	 9: Vector3(0, 0.14, -1.90),
	10: Vector3(0, 0.13, -2.10),
}

const _WHEEL_RADIUS := {
	1: 0.18, 2: 0.19, 3: 0.21, 4: 0.23, 5: 0.25,
	6: 0.27, 7: 0.29, 8: 0.30, 9: 0.31, 10: 0.34
}
const _WHEEL_HEIGHT := {
	1: 0.14, 2: 0.15, 3: 0.16, 4: 0.17, 5: 0.18,
	6: 0.19, 7: 0.20, 8: 0.21, 9: 0.22, 10: 0.24
}
const _WHEEL_X := {
	1: 0.55, 2: 0.58, 3: 0.61, 4: 0.64, 5: 0.66,
	6: 0.68, 7: 0.70, 8: 0.72, 9: 0.73, 10: 0.74
}
const _WHEEL_Z := {
	1: 0.55, 2: 0.62, 3: 0.78, 4: 0.92, 5: 1.05,
	6: 1.18, 7: 1.30, 8: 1.40, 9: 1.50, 10: 1.65
}

const _BEACON_SIZE := {
	 1: Vector3(0.45, 0.45, 0.45),
	 2: Vector3(0.42, 0.40, 0.42),
	 3: Vector3(0.38, 0.32, 0.38),
	 4: Vector3(0.34, 0.24, 0.34),
	 5: Vector3(0.30, 0.20, 0.30),
	 6: Vector3(0.28, 0.18, 0.28),
	 7: Vector3(0.26, 0.16, 0.26),
	 8: Vector3(0.25, 0.14, 0.25),
	 9: Vector3(0.24, 0.13, 0.24),
	10: Vector3(0.22, 0.11, 0.22),
}
const _BEACON_Y := {
	1: 1.10, 2: 1.08, 3: 1.00, 4: 0.92, 5: 0.85,
	6: 0.80, 7: 0.76, 8: 0.74, 9: 0.72, 10: 0.68
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
	var base_v: Vector3 = table[t]
	if t >= TIER_LEVEL_CAPS.size():
		return base_v
	var next_v: Vector3 = table[t + 1]
	return base_v.lerp(next_v, _tier_progress())


func _lerp_f_table(table: Dictionary) -> float:
	var t: int = tier()
	var base_v: float = float(table[t])
	if t >= TIER_LEVEL_CAPS.size():
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

	body_mesh = _make_box_mesh("Body", Vector3.ONE, body_material)
	cockpit_mesh = _make_box_mesh("Cockpit", Vector3.ONE, cockpit_material)
	spoiler_mesh = _make_box_mesh("Spoiler", Vector3.ONE, spoiler_material)
	front_wing_mesh = _make_box_mesh("FrontWing", Vector3.ONE, front_wing_material)
	beacon_mesh = _make_box_mesh("Beacon", Vector3.ONE, beacon_material)

	# Halo (tier 4 cosmetic) — torus around the cockpit area.
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

	# --- Rear spoiler — appears from tier 2 and grows continuously. ---
	if t >= 2:
		spoiler_mesh.visible = true
		(spoiler_mesh.mesh as BoxMesh).size = _lerp_v3_table(_SPOILER_SIZE)
		spoiler_mesh.position = _lerp_v3_table(_SPOILER_OFFSET)
		spoiler_material.albedo_color = kart_color.darkened(0.2)
	else:
		spoiler_mesh.visible = false

	# --- Front wing (F1 territory) ---
	if t >= 3:
		front_wing_mesh.visible = true
		(front_wing_mesh.mesh as BoxMesh).size = _lerp_v3_table(_FRONT_WING_SIZE)
		front_wing_mesh.position = _lerp_v3_table(_FRONT_WING_OFFSET)
		front_wing_material.albedo_color = kart_color.darkened(0.15)
	else:
		front_wing_mesh.visible = false

	# --- Halo (F1-style safety device) — appears at tier 8 and stays. ---
	if t >= 8:
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
