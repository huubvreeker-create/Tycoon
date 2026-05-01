extends Node3D
class_name Track
##
## A single race venue in 3D. Owns:
## - the Path3D + extruded asphalt mesh (CSGPolygon3D, tier-driven)
## - the kart fleet (PathFollow3D children)
## - the customer queue + race scheduling (logical only, no 3D dots
##   yet — the HUD shows the queue count)
## - revenue / maintenance hooks
## - an Area3D over the asphalt so the player can click the track
##   itself to open the track-upgrade popup
##
## All visual progression is purely procedural: the polygon profile,
## ribbon color, ground footprint and lighting accents are recomputed
## from the current tier whenever the track levels up across a tier
## boundary. Per-level upgrades only nudge mechanical stats so the
## scene doesn't visually flicker on every click.
##

# --- Configuration ----------------------------------------------------------
@export var track_id: String = "local_track"
@export var initial_kart_count: int = 5

const KART_SCENE: PackedScene = preload("res://scenes/kart.tscn")

# Tier-driven data tables (1-indexed via tier number).
const TIER_NAMES := {
	1: "Hometown Indoor",
	2: "Regional Race Center",
	3: "National Circuit",
	4: "International Kart Arena",
}
const TIER_KART_CAPACITY := { 1: 5, 2: 8, 3: 12, 4: 16 }
const TIER_RACE_DURATION := { 1: 7.0, 2: 8.0, 3: 9.5, 4: 11.0 }
# Track footprint (in metres of world space).
const TIER_TRACK_RX := { 1: 14.0, 2: 16.0, 3: 18.0, 4: 20.0 }
const TIER_TRACK_RZ := { 1: 8.0,  2: 9.0,  3: 10.0, 4: 11.0 }
const TIER_ASPHALT_WIDTH := { 1: 2.4, 2: 2.7, 3: 3.0, 4: 3.4 }
const TIER_WAVE_FREQ := { 1: 0, 2: 3, 3: 5, 4: 7 }
const TIER_WAVE_AMP := { 1: 0.0, 2: 1.1, 3: 1.5, 4: 1.8 }
const TIER_RIBBON_COLOR := {
	1: Color(0.13, 0.83, 0.96),
	2: Color(0.55, 0.92, 0.38),
	3: Color(0.99, 0.75, 0.18),
	4: Color(0.86, 0.42, 0.98),
}
const TIER_RUMBLE_COLOR := {
	1: Color(0.96, 0.27, 0.36),
	2: Color(0.96, 0.27, 0.36),
	3: Color(1.00, 0.40, 0.20),
	4: Color(1.00, 0.30, 0.55),
}

# Level-based progression (see balance pass).
const MAX_LEVEL: int = 100
const LEVELS_PER_TIER: int = 25

const TRACK_UPGRADE_BASE_COST: float = 250.0
const TRACK_UPGRADE_GROWTH: float = 1.075
const KART_UPGRADE_BASE_COST: float = 50.0
const KART_UPGRADE_GROWTH: float = 1.075
const BUY_KART_BASE_COST: float = 200.0
const BUY_KART_LEVEL_FACTOR: float = 80.0
const BUY_KART_FLEET_GROWTH: float = 1.06

const PATH_SEGMENTS: int = 96
const ASPHALT_DEPTH: float = 0.12
const RUMBLE_INSET: float = 0.18

# --- State ------------------------------------------------------------------
var track_level: int = 1
var kart_level: int = 1

var path: Path3D
var asphalt_csg: CSGPolygon3D
var rumble_csg: CSGPolygon3D
var ground: MeshInstance3D
var click_area: Area3D
var click_collider: CollisionShape3D
var ribbon_material: StandardMaterial3D
var rumble_material: StandardMaterial3D

var karts: Array[Kart] = []
var queue: Array[Customer] = []
var racing: Array[Customer] = []

var _arrival_timer: float = 0.0


# ---------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("track")
	_build_ground()
	_build_path()
	_build_asphalt()
	_build_click_area()
	for i in range(initial_kart_count):
		_add_kart_node(true)
	_emit_initial_state()
	EventBus.day_ended.connect(_on_day_ended)


func _emit_initial_state() -> void:
	EventBus.track_tier_changed.emit(track_tier(), venue_name())
	EventBus.kart_tier_changed.emit(kart_tier())
	EventBus.track_level_changed.emit(track_level, track_tier())
	EventBus.kart_level_changed.emit(kart_level, kart_tier())
	EventBus.kart_count_changed.emit(karts.size(), kart_capacity())
	EventBus.queue_changed.emit(queue.size())
	GameManager.set_active_customers(queue.size() + racing.size())


func _process(delta: float) -> void:
	_tick_arrivals(delta)
	_tick_queue(delta)
	_tick_races(delta)


# --- Public API (used by upgrade popup) ------------------------------------
func track_tier() -> int:
	return clamp((track_level - 1) / LEVELS_PER_TIER + 1, 1, 4)


func kart_tier() -> int:
	return clamp((kart_level - 1) / LEVELS_PER_TIER + 1, 1, 4)


func track_level_in_tier() -> int:
	return ((track_level - 1) % LEVELS_PER_TIER) + 1


func kart_level_in_tier() -> int:
	return ((kart_level - 1) % LEVELS_PER_TIER) + 1


func venue_name() -> String:
	return TIER_NAMES[track_tier()]


func kart_capacity() -> int:
	return TIER_KART_CAPACITY[track_tier()] + (track_level_in_tier() - 1) / 6


func can_upgrade_track() -> bool:
	return track_level < MAX_LEVEL


func track_upgrade_cost() -> int:
	if not can_upgrade_track():
		return -1
	return int(round(TRACK_UPGRADE_BASE_COST * pow(TRACK_UPGRADE_GROWTH, track_level - 1)))


func can_upgrade_karts() -> bool:
	return kart_level < MAX_LEVEL


func kart_upgrade_cost() -> int:
	if not can_upgrade_karts():
		return -1
	var per_kart: float = KART_UPGRADE_BASE_COST * pow(KART_UPGRADE_GROWTH, kart_level - 1)
	return int(round(per_kart * max(karts.size(), 1)))


func can_buy_kart() -> bool:
	return karts.size() < kart_capacity()


func buy_kart_cost() -> int:
	var base: float = BUY_KART_BASE_COST + BUY_KART_LEVEL_FACTOR * float(track_level)
	return int(round(base * pow(BUY_KART_FLEET_GROWTH, karts.size())))


func upgrade_track() -> bool:
	if not can_upgrade_track():
		return false
	var cost := track_upgrade_cost()
	if not EconomyManager.try_spend("Track upgrade", cost):
		return false
	var prev_tier := track_tier()
	track_level += 1
	var new_tier := track_tier()
	if new_tier != prev_tier:
		_rebuild_for_new_tier()
		EventBus.track_tier_changed.emit(new_tier, venue_name())
	EventBus.track_level_changed.emit(track_level, new_tier)
	EventBus.kart_count_changed.emit(karts.size(), kart_capacity())
	return true


func upgrade_karts() -> bool:
	if not can_upgrade_karts():
		return false
	var cost := kart_upgrade_cost()
	if not EconomyManager.try_spend("Kart upgrade", cost):
		return false
	var prev_tier := kart_tier()
	kart_level += 1
	var new_tier := kart_tier()
	for k in karts:
		k.set_level(kart_level)
	if new_tier != prev_tier:
		EventBus.kart_tier_changed.emit(new_tier)
	EventBus.kart_level_changed.emit(kart_level, new_tier)
	return true


func buy_kart() -> bool:
	if not can_buy_kart():
		return false
	var cost := buy_kart_cost()
	if not EconomyManager.try_spend("Kart purchase", cost):
		return false
	_add_kart_node(false)
	EventBus.kart_count_changed.emit(karts.size(), kart_capacity())
	EventBus.kart_purchased.emit("kart_%d" % karts.size())
	return true


# --- 3D construction -------------------------------------------------------
func _rebuild_for_new_tier() -> void:
	# Detach karts so they don't get freed with the old path.
	for k in karts:
		var p := k.get_parent()
		if p != null:
			p.remove_child(k)
	if path:
		path.queue_free()
	if asphalt_csg:
		asphalt_csg.queue_free()
	if rumble_csg:
		rumble_csg.queue_free()
	if click_area:
		click_area.queue_free()
	if ground:
		ground.queue_free()
	_build_ground()
	_build_path()
	_build_asphalt()
	_build_click_area()
	for k in karts:
		var prev_progress := k.progress
		path.add_child(k)
		k.progress = prev_progress


func _build_ground() -> void:
	# A subtle dark plane under the track to anchor the scene visually.
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	var size: float = TIER_TRACK_RX[track_tier()] * 2.4
	plane.size = Vector2(size, size * 0.7)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.09, 0.13)
	mat.metallic = 0.0
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = Vector3(0, -ASPHALT_DEPTH * 0.5 - 0.01, 0)
	add_child(ground)


func _build_path() -> void:
	path = Path3D.new()
	path.name = "RacePath"
	add_child(path)
	var curve := Curve3D.new()
	var t_tier: int = track_tier()
	var rx: float = TIER_TRACK_RX[t_tier]
	var rz: float = TIER_TRACK_RZ[t_tier]
	var freq: int = TIER_WAVE_FREQ[t_tier]
	var amp: float = TIER_WAVE_AMP[t_tier]
	for i in range(PATH_SEGMENTS):
		var t := float(i) / float(PATH_SEGMENTS) * TAU
		var base_x := cos(t) * rx
		var base_z := sin(t) * rz
		var n := Vector2(cos(t) / rx, sin(t) / rz).normalized()
		var wobble := 0.0
		if freq > 0:
			wobble = sin(t * freq) * amp
		var p := Vector3(base_x + n.x * wobble, 0.0, base_z + n.y * wobble)
		curve.add_point(p)
	# Close the loop by adding a final point coincident with the first.
	curve.add_point(curve.get_point_position(0))
	path.curve = curve


func _build_asphalt() -> void:
	var t_tier: int = track_tier()
	var w: float = TIER_ASPHALT_WIDTH[t_tier]
	var rumble_w: float = w + RUMBLE_INSET * 2.0

	# Outer rumble strip (slightly wider, sits underneath the asphalt).
	rumble_csg = CSGPolygon3D.new()
	rumble_csg.name = "Rumble"
	rumble_csg.mode = CSGPolygon3D.MODE_PATH
	rumble_csg.path_node = path.get_path()
	rumble_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	rumble_csg.path_interval = 0.5
	rumble_csg.path_joined = true
	rumble_csg.polygon = PackedVector2Array([
		Vector2(-rumble_w * 0.5, 0.0),
		Vector2( rumble_w * 0.5, 0.0),
		Vector2( rumble_w * 0.5, -ASPHALT_DEPTH * 0.6),
		Vector2(-rumble_w * 0.5, -ASPHALT_DEPTH * 0.6),
	])
	rumble_material = StandardMaterial3D.new()
	rumble_material.albedo_color = TIER_RUMBLE_COLOR[t_tier]
	rumble_material.roughness = 0.7
	rumble_csg.material_override = rumble_material
	add_child(rumble_csg)

	# Asphalt surface itself.
	asphalt_csg = CSGPolygon3D.new()
	asphalt_csg.name = "Asphalt"
	asphalt_csg.mode = CSGPolygon3D.MODE_PATH
	asphalt_csg.path_node = path.get_path()
	asphalt_csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	asphalt_csg.path_interval = 0.5
	asphalt_csg.path_joined = true
	asphalt_csg.polygon = PackedVector2Array([
		Vector2(-w * 0.5, 0.04),
		Vector2( w * 0.5, 0.04),
		Vector2( w * 0.5, -ASPHALT_DEPTH * 0.5),
		Vector2(-w * 0.5, -ASPHALT_DEPTH * 0.5),
	])
	ribbon_material = StandardMaterial3D.new()
	ribbon_material.albedo_color = Color(0.13, 0.14, 0.20)
	ribbon_material.metallic = 0.05
	ribbon_material.roughness = 0.85
	asphalt_csg.material_override = ribbon_material
	add_child(asphalt_csg)


func _build_click_area() -> void:
	# A flat box covering the track footprint so any click on the
	# asphalt forwards to the track-upgrade popup. Sized generously
	# so the rumble strip + nearby grass also count as "the track".
	click_area = Area3D.new()
	click_area.name = "TrackClick"
	click_area.add_to_group("track_clickable")
	click_area.set_meta("kind", "track")
	add_child(click_area)
	click_collider = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var t_tier: int = track_tier()
	shape.size = Vector3(
		TIER_TRACK_RX[t_tier] * 2.3,
		0.4,
		TIER_TRACK_RZ[t_tier] * 2.3
	)
	click_collider.shape = shape
	click_collider.position = Vector3(0, 0.05, 0)
	click_area.add_child(click_collider)


func _add_kart_node(initial_spawn: bool) -> void:
	var kart: Kart = KART_SCENE.instantiate()
	var palette := [
		Color(0.96, 0.27, 0.36),
		Color(0.99, 0.75, 0.18),
		Color(0.13, 0.83, 0.96),
		Color(0.55, 0.92, 0.38),
		Color(0.86, 0.42, 0.98),
		Color(1.00, 0.55, 0.20),
		Color(0.40, 0.65, 1.00),
		Color(0.95, 0.95, 0.95),
	]
	kart.kart_color = palette[karts.size() % palette.size()]
	kart.set_level(kart_level)
	path.add_child(kart)
	kart.progress = float(karts.size()) * 4.0
	karts.append(kart)
	if not initial_spawn:
		kart.flash_spawn()


# --- Customer simulation ---------------------------------------------------
func _tick_arrivals(delta: float) -> void:
	var interval: float = max(1.6, 4.0 - GameManager.reputation * 0.02)
	_arrival_timer += delta
	if _arrival_timer >= interval:
		_arrival_timer = 0.0
		_spawn_customer()


func _spawn_customer() -> void:
	var c := Customer.new(GameManager.reputation)
	queue.append(c)
	EventBus.customer_arrived.emit(c.id)
	EventBus.queue_changed.emit(queue.size())
	GameManager.set_active_customers(queue.size() + racing.size())


func _tick_queue(delta: float) -> void:
	var leavers: Array[Customer] = []
	for c in queue:
		c.tick_queue(delta)
		if c.is_out_of_patience():
			leavers.append(c)
	for c in leavers:
		queue.erase(c)
		_register_walkout(c)

	while queue.size() > 0:
		var free_kart := _find_free_kart()
		if free_kart == null:
			break
		var c2: Customer = queue.pop_front()
		_start_race(c2, free_kart)
	EventBus.queue_changed.emit(queue.size())
	GameManager.set_active_customers(queue.size() + racing.size())


func _find_free_kart() -> Kart:
	for k in karts:
		if not k.is_busy():
			return k
	return null


func _start_race(c: Customer, kart: Kart) -> void:
	c.assigned_kart = kart
	c.race_time_left = TIER_RACE_DURATION[track_tier()]
	kart.set_racing(true)
	racing.append(c)
	EventBus.race_started.emit(track_id, racing.size())


func _tick_races(delta: float) -> void:
	var finished: Array[Customer] = []
	for c in racing:
		c.race_time_left -= delta
		if c.race_time_left <= 0.0:
			finished.append(c)
	for c in finished:
		_finish_race(c)


func _finish_race(c: Customer) -> void:
	racing.erase(c)
	var kart: Kart = c.assigned_kart
	if kart:
		kart.set_racing(false)
	c.compute_satisfaction(track_tier(), kart_tier(), GameManager.ticket_price)
	var payment := c.compute_payment(GameManager.ticket_price)
	EconomyManager.add_revenue("Ticket", payment)
	GameManager.add_reputation(c.reputation_delta())
	EventBus.race_finished.emit(track_id, payment)
	EventBus.customer_left.emit(c.id, c.satisfaction)
	if kart:
		kart.flash_finish(c.satisfaction)
	GameManager.set_active_customers(queue.size() + racing.size())


func _register_walkout(c: Customer) -> void:
	GameManager.add_reputation(-1)
	EventBus.customer_left.emit(c.id, 0.0)


func _on_day_ended(_summary: Dictionary) -> void:
	var maintenance := karts.size() * (5 + kart_tier() * 5)
	EconomyManager.log_expense("Maintenance", maintenance)
