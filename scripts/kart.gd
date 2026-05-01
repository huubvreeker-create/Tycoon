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
var halo_mesh: MeshInstance3D
var wheel_meshes: Array[MeshInstance3D] = []
var click_area: Area3D
var body_material: StandardMaterial3D

var _flash_time: float = 0.0
var _flash_color: Color = Color.WHITE


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
		var t := clamp(_flash_time / 0.6, 0.0, 1.0)
		body_material.emission_enabled = true
		body_material.emission = _flash_color
		body_material.emission_energy_multiplier = t * 2.0
		if _flash_time <= 0.0:
			body_material.emission_enabled = racing
			body_material.emission_energy_multiplier = 0.6 if racing else 0.0


func tier() -> int:
	return clamp((level - 1) / LEVELS_PER_TIER + 1, 1, 4)


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
	level = clamp(new_level, 1, 100)
	_apply_visuals()


func flash_finish(satisfaction: float) -> void:
	_flash_time = 0.6
	_flash_color = Color(0.55, 0.92, 0.38) if satisfaction >= 0.6 else Color(0.96, 0.27, 0.36)


func flash_spawn() -> void:
	_flash_time = 0.6
	_flash_color = Color.WHITE


# --- Construction ----------------------------------------------------------
func _build_meshes() -> void:
	# PathFollow3D with ROTATION_Y: local -Z points forward along path.
	# Body: 1.0 m wide (X), 0.28 m tall (Y), 1.6 m long (Z along path).
	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Body"
	var body := BoxMesh.new()
	body.size = Vector3(1.0, 0.28, 1.6)
	body_mesh.mesh = body
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = kart_color
	body_material.metallic = 0.2
	body_material.roughness = 0.5
	body_mesh.material_override = body_material
	body_mesh.position = Vector3(0, 0.38, 0)
	add_child(body_mesh)

	# Cockpit: sits toward the rear (+Z side) above the body.
	cockpit_mesh = MeshInstance3D.new()
	cockpit_mesh.name = "Cockpit"
	var cockpit := BoxMesh.new()
	cockpit.size = Vector3(0.55, 0.25, 0.65)
	cockpit_mesh.mesh = cockpit
	var cockpit_mat := StandardMaterial3D.new()
	cockpit_mat.albedo_color = kart_color.darkened(0.45)
	cockpit_mat.roughness = 0.6
	cockpit_mesh.material_override = cockpit_mat
	cockpit_mesh.position = Vector3(0, 0.63, 0.22)
	add_child(cockpit_mesh)

	# Rear spoiler (visible tier 2+).
	spoiler_mesh = MeshInstance3D.new()
	spoiler_mesh.name = "Spoiler"
	var spoiler := BoxMesh.new()
	spoiler.size = Vector3(0.85, 0.30, 0.14)
	spoiler_mesh.mesh = spoiler
	var spoiler_mat := StandardMaterial3D.new()
	spoiler_mat.albedo_color = kart_color.darkened(0.2)
	spoiler_mesh.material_override = spoiler_mat
	spoiler_mesh.position = Vector3(0, 0.64, 0.78)
	add_child(spoiler_mesh)

	# Halo (tier 4): flat ring above cockpit.
	halo_mesh = MeshInstance3D.new()
	halo_mesh.name = "Halo"
	var halo := TorusMesh.new()
	halo.inner_radius = 0.28
	halo.outer_radius = 0.34
	halo_mesh.mesh = halo
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = kart_color.lightened(0.45)
	halo_mat.emission_enabled = true
	halo_mat.emission = kart_color.lightened(0.5)
	halo_mat.emission_energy_multiplier = 1.2
	halo_mesh.material_override = halo_mat
	halo_mesh.position = Vector3(0, 1.0, 0.22)
	halo_mesh.rotation = Vector3(deg_to_rad(90), 0, 0)
	add_child(halo_mesh)

	# Wheels: CylinderMesh with axis along X (rotated 90° around Z).
	# Front axle at Z=-0.58, rear at Z=+0.58; left/right at X=±0.56.
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.10)
	wheel_mat.roughness = 0.8
	for offset: Vector3 in [
		Vector3( 0.56, 0.20,  0.58),
		Vector3( 0.56, 0.20, -0.58),
		Vector3(-0.56, 0.20,  0.58),
		Vector3(-0.56, 0.20, -0.58),
	]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.20
		cyl.bottom_radius = 0.20
		cyl.height = 0.14
		wheel.mesh = cyl
		wheel.material_override = wheel_mat
		wheel.position = offset
		# Rotate around Z so the cylinder axis (Y) lies along X (wheel axle).
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
	shape.size = Vector3(1.4, 1.2, 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, 0.6, 0)
	click_area.add_child(collider)


func _apply_visuals() -> void:
	if body_material == null:
		return
	body_material.albedo_color = kart_color
	var t := tier()
	spoiler_mesh.visible = t >= 2
	halo_mesh.visible = t >= 4
	body_material.metallic = 0.2 + (t - 1) * 0.12
	body_material.roughness = 0.5 - (t - 1) * 0.07


func _refresh_emission() -> void:
	if body_material == null:
		return
	body_material.emission_enabled = racing
	body_material.emission = kart_color.lightened(0.4)
	body_material.emission_energy_multiplier = 0.6 if racing else 0.0
