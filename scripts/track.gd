extends Node2D
class_name Track
##
## A single race venue. Owns:
## - the procedural Path2D + asphalt rendering (tiered)
## - the kart fleet
## - the customer queue + race scheduling
## - revenue / maintenance hooks
##
## Phase 1: track + karts.
## Phase 2: day clock-driven maintenance, ticket revenue.
## Phase 3: customer simulation (this file orchestrates queue + races).
## Phase 4: upgradeable tiers (track + karts + buy kart) — wired here.
##

# --- Configuration ----------------------------------------------------------
@export var track_id: String = "local_track"
@export var initial_kart_count: int = 5
@export var track_center: Vector2 = Vector2(560, 380)

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
const TIER_TRACK_RX := { 1: 360.0, 2: 400.0, 3: 440.0, 4: 480.0 }
const TIER_TRACK_RY := { 1: 200.0, 2: 220.0, 3: 240.0, 4: 260.0 }
const TIER_ASPHALT_WIDTH := { 1: 60.0, 2: 70.0, 3: 80.0, 4: 92.0 }
const TIER_WAVE_FREQ := { 1: 0, 2: 3, 3: 5, 4: 7 }
const TIER_WAVE_AMP := { 1: 0.0, 2: 26.0, 3: 34.0, 4: 42.0 }
const TIER_TRACK_COLOR := {
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

# Level-based progression: 100 levels total, every LEVELS_PER_TIER
# levels you cross a visible tier boundary (new venue name, new
# track shape, new kart silhouette). Per-level upgrades give small
# mechanical buffs (capacity, kart speed) so each click matters
# without instantly transforming the game.
const MAX_LEVEL: int = 100
const LEVELS_PER_TIER: int = 25  # → tiers 1..4 land at lvl 1, 26, 51, 76

# Upgrade pricing — exponential scaling per level. Numbers tuned so
# that the early-game starting cash (€5k) buys you ~15-20 first
# upgrades, while reaching the highest tier takes a real grind.
const TRACK_UPGRADE_BASE_COST: float = 250.0
const TRACK_UPGRADE_GROWTH: float = 1.075
const KART_UPGRADE_BASE_COST: float = 50.0       # multiplied by kart count
const KART_UPGRADE_GROWTH: float = 1.075
const BUY_KART_BASE_COST: float = 200.0
const BUY_KART_LEVEL_FACTOR: float = 80.0
const BUY_KART_FLEET_GROWTH: float = 1.06

# --- State ------------------------------------------------------------------
var track_level: int = 1
var kart_level: int = 1

var path: Path2D
var karts: Array[Kart] = []
var queue: Array[Customer] = []
var racing: Array[Customer] = []  # currently on a kart
var leaving_flash: Array = []     # [{pos: Vector2, color: Color, life: float}]

const ASPHALT_BG_COLOR: Color = Color(0.13, 0.14, 0.20)
const PATH_SEGMENTS: int = 96

# Customer arrival pacing.
var _arrival_timer: float = 0.0
var _arrival_interval: float = 4.0


# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_path()
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
	_tick_flashes(delta)
	queue_redraw()  # queue dots + flashes update each frame


# --- Public API (used by upgrade panel) -------------------------------------
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
	# Capacity grows steadily so each level matters: roughly +1 kart
	# every 6 levels on top of the tier baseline.
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
	# Climbs with track investment AND fleet size, so late-game karts
	# aren't trivially cheap relative to ticket revenue.
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
	# Crossing a tier boundary: rebuild the path + announce visually.
	if new_tier != prev_tier:
		_build_path()
		EventBus.track_tier_changed.emit(new_tier, venue_name())
	EventBus.track_level_changed.emit(track_level, new_tier)
	EventBus.kart_count_changed.emit(karts.size(), kart_capacity())
	queue_redraw()
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
	# Push new level to every kart so speed scales every upgrade,
	# while visuals only refresh on tier crossings (handled in Kart).
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


# --- Path / kart construction ----------------------------------------------
func _build_path() -> void:
	# Detach any existing karts from the old path BEFORE freeing it,
	# otherwise re-parenting them to the new path throws "already has parent".
	if path:
		for k in karts:
			var current_parent := k.get_parent()
			if current_parent != null:
				current_parent.remove_child(k)
		path.queue_free()
	path = Path2D.new()
	path.name = "RacePath"
	add_child(path)
	# Render path under HUD/UI siblings.
	move_child(path, 0)
	var curve := Curve2D.new()
	var t_tier: int = track_tier()
	var rx: float = TIER_TRACK_RX[t_tier]
	var ry: float = TIER_TRACK_RY[t_tier]
	var freq: int = TIER_WAVE_FREQ[t_tier]
	var amp: float = TIER_WAVE_AMP[t_tier]
	for i in range(PATH_SEGMENTS):
		var t := float(i) / float(PATH_SEGMENTS) * TAU
		var base_x := cos(t) * rx
		var base_y := sin(t) * ry
		# Outward perpendicular wobble: makes Tier 2-4 feel like a real circuit.
		var n := Vector2(cos(t) / rx, sin(t) / ry).normalized()
		var wobble := 0.0
		if freq > 0:
			wobble = sin(t * freq) * amp
		var p := track_center + Vector2(base_x, base_y) + n * wobble
		curve.add_point(p)
	# Close the loop.
	curve.add_point(curve.get_point_position(0))
	path.curve = curve
	# Re-attach existing karts (now parentless) to the new path,
	# preserving their progress so the race continues smoothly.
	for k in karts:
		var prev_progress := k.progress
		path.add_child(k)
		k.progress = prev_progress


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
	# Stagger starting positions so they don't stack.
	var slot := karts.size()
	kart.progress = float(slot) * 70.0
	karts.append(kart)
	if not initial_spawn:
		# Briefly highlight the new kart visually via flash on its position.
		var flash := { "pos": kart.global_position, "color": Color.WHITE, "life": 0.6 }
		leaving_flash.append(flash)


# --- Customer simulation ---------------------------------------------------
func _tick_arrivals(delta: float) -> void:
	# Arrival pace scales down with reputation (more famous = busier).
	_arrival_interval = max(1.6, 4.0 - GameManager.reputation * 0.02)
	_arrival_timer += delta
	if _arrival_timer >= _arrival_interval:
		_arrival_timer = 0.0
		_spawn_customer()


func _spawn_customer() -> void:
	var c := Customer.new(GameManager.reputation)
	queue.append(c)
	EventBus.customer_arrived.emit(c.id)
	EventBus.queue_changed.emit(queue.size())
	GameManager.set_active_customers(queue.size() + racing.size())


func _tick_queue(delta: float) -> void:
	# Patience tick + free-kart pairing.
	var leavers: Array[Customer] = []
	for c in queue:
		c.tick_queue(delta)
		if c.is_out_of_patience():
			leavers.append(c)
	for c in leavers:
		queue.erase(c)
		_register_walkout(c)

	# Try to put queued customers onto idle karts.
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
	# Compute outcome.
	c.compute_satisfaction(track_tier(), kart_tier(), GameManager.ticket_price)
	var payment := c.compute_payment(GameManager.ticket_price)
	EconomyManager.add_revenue("Ticket", payment)
	GameManager.add_reputation(c.reputation_delta())
	EventBus.race_finished.emit(track_id, payment)
	EventBus.customer_left.emit(c.id, c.satisfaction)
	# Visual flash where the kart is.
	if kart:
		var col := Color(0.55, 0.92, 0.38) if c.satisfaction >= 0.6 else Color(0.96, 0.27, 0.36)
		leaving_flash.append({
			"pos": kart.global_position,
			"color": col,
			"life": 0.7,
		})
	GameManager.set_active_customers(queue.size() + racing.size())


func _register_walkout(c: Customer) -> void:
	# Angry walkout: small reputation hit, no payment.
	GameManager.add_reputation(-1)
	EventBus.customer_left.emit(c.id, 0.0)
	leaving_flash.append({
		"pos": _queue_dot_position(0),
		"color": Color(0.96, 0.27, 0.36),
		"life": 0.5,
	})


func _tick_flashes(delta: float) -> void:
	for f in leaving_flash:
		f.life -= delta
	leaving_flash = leaving_flash.filter(func(f): return f.life > 0.0)


# --- Day-end maintenance ---------------------------------------------------
func _on_day_ended(_summary: Dictionary) -> void:
	# Maintenance scales gently with both fleet size and tier so it
	# never overwhelms early-game profits.
	var maintenance := karts.size() * (5 + kart_tier() * 5)
	EconomyManager.log_expense("Maintenance", maintenance)


# --- Rendering --------------------------------------------------------------
func _draw() -> void:
	if path == null or path.curve == null:
		push_warning("Track: path or curve missing in _draw()")
		return
	var pts := path.curve.get_baked_points()
	if pts.size() < 2:
		push_warning("Track: curve produced no baked points")
		return

	var t_tier: int = track_tier()
	var rumble: Color = TIER_RUMBLE_COLOR[t_tier]
	var ribbon: Color = TIER_TRACK_COLOR[t_tier]
	var asphalt_w: float = TIER_ASPHALT_WIDTH[t_tier]

	# Outer rumble strip (drawn first, slightly wider).
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], rumble, asphalt_w + 8.0, false)
	# Asphalt surface.
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], ASPHALT_BG_COLOR, asphalt_w, false)
	# Tier-colored racing line down the middle (dashed).
	_draw_dashed_polyline(pts, ribbon, 2.0, 18.0, 14.0)
	# Start / finish line.
	_draw_start_line(pts, asphalt_w)
	# Customer queue dots and flashes.
	_draw_queue_dots()
	_draw_flashes()
	# Tier banner in upper-left of the track.
	_draw_tier_banner()


func _draw_dashed_polyline(
	pts: PackedVector2Array,
	color: Color,
	width: float,
	dash_length: float,
	gap_length: float
) -> void:
	var distance_carry := 0.0
	var drawing := true
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len <= 0.001:
			continue
		var dir := seg / seg_len
		var traveled := 0.0
		while traveled < seg_len:
			var target := dash_length if drawing else gap_length
			var remaining := target - distance_carry
			var step: float = min(remaining, seg_len - traveled)
			if drawing:
				var p1 := a + dir * traveled
				var p2 := a + dir * (traveled + step)
				draw_line(p1, p2, color, width, true)
			traveled += step
			distance_carry += step
			if distance_carry >= target:
				distance_carry = 0.0
				drawing = not drawing


func _draw_start_line(pts: PackedVector2Array, asphalt_w: float) -> void:
	if pts.size() < 2:
		return
	var p := pts[0]
	var next: Vector2 = pts[1]
	var dir: Vector2 = (next - p).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var half := asphalt_w * 0.5
	var a := p + perp * half
	var b := p - perp * half
	var squares := 8
	for i in range(squares):
		var t1 := float(i) / float(squares)
		var t2 := float(i + 1) / float(squares)
		var s1 := a.lerp(b, t1)
		var s2 := a.lerp(b, t2)
		var col := Color.WHITE if (i % 2 == 0) else Color(0.05, 0.05, 0.08)
		draw_line(s1, s2, col, 6.0)


func _queue_dot_position(index: int) -> Vector2:
	# Queue rendered as a vertical column to the left of the track center.
	var rx: float = TIER_TRACK_RX[track_tier()]
	var origin := track_center + Vector2(-rx - 80.0, -120.0)
	return origin + Vector2(0, index * 14.0)


func _draw_queue_dots() -> void:
	# Header text + colored circles for each waiting customer.
	var header_pos := _queue_dot_position(0) + Vector2(-12, -20)
	draw_string(
		ThemeDB.fallback_font,
		header_pos,
		"QUEUE  %d" % queue.size(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(0.7, 0.78, 0.92, 0.9)
	)
	for i in range(queue.size()):
		var c: Customer = queue[i]
		var pos := _queue_dot_position(i)
		# Color shifts from green → yellow → red as patience drains.
		var ratio: float = clamp(c.wait_time / c.patience, 0.0, 1.0)
		var col := Color(0.55, 0.92, 0.38).lerp(Color(0.96, 0.27, 0.36), ratio)
		draw_circle(pos, 5.0, col)
		draw_arc(pos, 6.5, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.5, true)


func _draw_flashes() -> void:
	for f in leaving_flash:
		var alpha: float = clamp(f.life / 0.7, 0.0, 1.0)
		var col: Color = f.color
		col.a = alpha
		draw_circle(f.pos, 18.0 * (1.0 - alpha) + 8.0, col)


func _draw_tier_banner() -> void:
	var t_tier: int = track_tier()
	var rx: float = TIER_TRACK_RX[t_tier]
	var ry: float = TIER_TRACK_RY[t_tier]
	var pos := track_center + Vector2(-rx, -ry - 36.0)
	var ribbon: Color = TIER_TRACK_COLOR[t_tier]
	draw_rect(Rect2(pos, Vector2(220, 24)), Color(0.05, 0.06, 0.10, 0.85))
	draw_rect(Rect2(pos, Vector2(4, 24)), ribbon)
	draw_string(
		ThemeDB.fallback_font,
		pos + Vector2(12, 17),
		"TIER %d  Lvl %d/%d  %s" % [t_tier, track_level, MAX_LEVEL, venue_name()],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.95, 0.97, 1.0)
	)
