extends PathFollow3D
class_name Kart

const IDLE_SPEED_BASE: float = 6.0
const RACING_SPEED_BASE: float = 14.0
const PER_LEVEL_SPEED_BONUS: float = 0.18
const LEVELS_PER_TIER: int = 25

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
const _BODY_SIZE := {
	1: Vector3(0.95, 0.28, 1.4),   # kid kart — squat
	2: Vector3(1.00, 0.30, 1.7),   # sport kart
	3: Vector3(0.95, 0.26, 2.6),   # pro race car — narrower, longer
	4: Vector3(0.85, 0.20, 3.8),   # F1 — very narrow, very long, low
}
const _BODY_Y := { 1: 0.36, 2: 0.40, 3: 0.34, 4: 0.28 }

const _COCKPIT_SIZE := {
	1: Vector3(0.50, 0.26, 0.55),
	2: Vector3(0.55, 0.30, 0.65),
	3: Vector3(0.55, 0.32, 0.75),
	4: Vector3(0.50, 0.32, 0.70),  # enclosed F1 cell
}
const _COCKPIT_OFFSET := {
	1: Vector3(0, 0.55, 0.15),
	2: Vector3(0, 0.62, 0.20),
	3: Vector3(0, 0.62, 0.40),
	4: Vector3(0, 0.55, 0.55),
}

const _SPOILER_SIZE := {
	1: Vector3.ZERO,
	2: Vector3(0.85, 0.28, 0.14),
	3: Vector3(1.05, 0.42, 0.18),
	4: Vector3(1.30, 0.55, 0.22),  # huge F1 wing
}
const _SPOILER_OFFSET := {
	1: Vector3.ZERO,
	2: Vector3(0, 0.65, 0.80),
	3: Vector3(0, 0.78, 1.15),
	4: Vector3(0, 0.95, 1.70),
}

const _FRONT_WING_SIZE := {
	1: Vector3.ZERO,
	2: Vector3.ZERO,
	3: Vector3(1.05, 0.10, 0.30),
	4: Vector3(1.40, 0.10, 0.45),
}
const _FRONT_WING_OFFSET := {
	1: Vector3.ZERO,
	2: Vector3.ZERO,
	3: Vector3(0, 0.18, -1.20),
	4: Vector3(0, 0.14, -1.85),
}

const _WHEEL_RADIUS := { 1: 0.18, 2: 0.20, 3: 0.25, 4: 0.32 }
const _WHEEL_HEIGHT := { 1: 0.14, 2: 0.16, 3: 0.18, 4: 0.22 }
const _WHEEL_X := { 1: 0.55, 2: 0.60, 3: 0.65, 4: 0.72 }
const _WHEEL_Z := { 1: 0.55, 2: 0.65, 3: 0.95, 4: 1.45 }

const _BEACON_SIZE := {
	1: Vector3(0.45, 0.45, 0.45),
	2: Vector3(0.40, 0.35, 0.40),
	3: Vector3(0.30, 0.20, 0.30),  # smaller — F1-ish camera fairing
	4: Vector3(0.25, 0.12, 0.25),
}
const _BEACON_Y := { 1: 1.10, 2: 1.10, 3: 0.90, 4: 0.75 }


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
	@warning_ignore("integer_division")
	return clampi((level - 1) / LEVELS_PER_TIER + 1, 1, 4)


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
	var prev_tier: int = tier()
	level = clampi(new_level, 1, 100)
	_apply_visuals()
	# Wheels need to be re-laid out when their dimensions change at a
	# tier rollover; rebuild them in place.
	if prev_tier != tier():
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
	var t: int = tier()
	var radius: float = _WHEEL_RADIUS[t]
	var height: float = _WHEEL_HEIGHT[t]
	var ox: float = _WHEEL_X[t]
	var oz: float = _WHEEL_Z[t]
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

	# --- Body ---
	(body_mesh.mesh as BoxMesh).size = _BODY_SIZE[t]
	body_mesh.position = Vector3(0, _BODY_Y[t], 0)
	body_material.albedo_color = kart_color
	body_material.metallic = 0.20 + (t - 1) * 0.12
	body_material.roughness = 0.50 - (t - 1) * 0.08

	# --- Cockpit ---
	(cockpit_mesh.mesh as BoxMesh).size = _COCKPIT_SIZE[t]
	cockpit_mesh.position = _COCKPIT_OFFSET[t]
	cockpit_material.albedo_color = kart_color.darkened(0.45)

	# --- Rear spoiler ---
	if t >= 2:
		spoiler_mesh.visible = true
		(spoiler_mesh.mesh as BoxMesh).size = _SPOILER_SIZE[t]
		spoiler_mesh.position = _SPOILER_OFFSET[t]
		spoiler_material.albedo_color = kart_color.darkened(0.2)
	else:
		spoiler_mesh.visible = false

	# --- Front wing (F1 territory) ---
	if t >= 3:
		front_wing_mesh.visible = true
		(front_wing_mesh.mesh as BoxMesh).size = _FRONT_WING_SIZE[t]
		front_wing_mesh.position = _FRONT_WING_OFFSET[t]
		front_wing_material.albedo_color = kart_color.darkened(0.15)
	else:
		front_wing_mesh.visible = false

	# --- Halo (tier 4 only) ---
	if t >= 4:
		halo_mesh.visible = true
		halo_mesh.position = _COCKPIT_OFFSET[t] + Vector3(0, 0.45, 0)
	else:
		halo_mesh.visible = false

	# --- Beacon (always-on glow) ---
	(beacon_mesh.mesh as BoxMesh).size = _BEACON_SIZE[t]
	beacon_mesh.position = Vector3(0, _BEACON_Y[t], 0)
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
