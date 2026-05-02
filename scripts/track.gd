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

# --- 10-tier progression -----------------------------------------------------
# Each entry in TIER_LEVEL_CAPS is the cumulative track_level at which the
# tier ENDS. Tier 1 covers track_level 1..25, tier 2 covers 26..50, etc.
# Earlier tiers are 25 levels each; mid tiers 50; the final F1 tier is 100
# so endgame progression has a long tail.
const TIER_COUNT: int = 10
const TIER_LEVEL_CAPS: Array[int] = [25, 50, 75, 100, 150, 200, 250, 300, 350, 450]

# Tier-driven data tables (1-indexed via tier number).
const TIER_NAMES := {
	 1: "Backyard Track",
	 2: "Hometown Indoor",
	 3: "Local Karting Club",
	 4: "Regional Race Center",
	 5: "Provincial Circuit",
	 6: "National Karting Circuit",
	 7: "Continental Race Center",
	 8: "International Grand Prix",
	 9: "World Championship Track",
	10: "Formula 1 World Circuit",
}
# Tier 10 = real F1 grid size of 22 cars. Tiers grow gradually so each
# upgrade actually unlocks one or two extra slots.
const TIER_KART_CAPACITY := {
	1: 5, 2: 7, 3: 9, 4: 11, 5: 13, 6: 15, 7: 17, 8: 19, 9: 20, 10: 22
}
const TIER_RACE_DURATION := {
	1: 6.0, 2: 7.0, 3: 8.0, 4: 9.0, 5: 10.0,
	6: 11.0, 7: 12.0, 8: 13.0, 9: 14.5, 10: 16.0
}
# --- Fixed venue geometry (unchanged across tiers) ---------------------------
# A real F1 circuit has an iconic main straight that doesn't change
# between seasons — the pit lane connects to it, the start-finish
# tower sits on it, the grandstands face it. We use the same idea:
# the start/finish straight on the +Z side is FIXED across all tiers.
# Only the south loop (the rest of the circuit) grows and gains
# corners as the player tiers up.
const STRAIGHT_HALF: float = 18.0      # half-length of main straight (= 36 m total — comfortably fits 14 garages with margin)
const STRAIGHT_Z: float = 9.0          # z-coord of the straight (north of origin)

# Per-tier south LOOP. Loop endpoints on the north side are at
# (±loop_rx, STRAIGHT_Z); loop dips south to (0, STRAIGHT_Z -
# loop_depth) at its apex. The loop GROWS DRAMATICALLY per tier —
# tier 1 is already a small kart loop, tier 10 is a full F1-scale
# circuit. Each tier adds at least 4 m of loop_rx and depth so the
# extra corners have real space to spread out into.
const TIER_LOOP_RX := {
	1: 22.0, 2: 26.0, 3: 31.0, 4: 37.0, 5: 44.0,
	6: 52.0, 7: 60.0, 8: 68.0, 9: 76.0, 10: 84.0
}
const TIER_LOOP_DEPTH := {
	1: 14.0, 2: 19.0, 3: 25.0, 4: 32.0, 5: 40.0,
	6: 48.0, 7: 57.0, 8: 66.0, 9: 76.0, 10: 88.0
}
# Backwards-compat aliases. Both maps duplicate the loop tables —
# TIER_TRACK_RX = horizontal half-extent (sets X-side facility
# positioning); TIER_TRACK_RZ = south extent (sets -Z facilities).
# The new asymmetric helpers (north_extent_z / south_extent_z) on
# the API expose the proper north/south extents separately.
const TIER_TRACK_RX := {
	1: 22.0, 2: 26.0, 3: 31.0, 4: 37.0, 5: 44.0,
	6: 52.0, 7: 60.0, 8: 68.0, 9: 76.0, 10: 84.0
}
const TIER_TRACK_RZ := {
	1: 14.0, 2: 19.0, 3: 25.0, 4: 32.0, 5: 40.0,
	6: 48.0, 7: 57.0, 8: 66.0, 9: 76.0, 10: 88.0
}

const TIER_ASPHALT_WIDTH := {
	1: 3.4, 2: 3.8, 3: 4.2, 4: 4.6, 5: 5.0,
	6: 5.4, 7: 5.8, 8: 6.2, 9: 6.6, 10: 7.0
}
## Per-tier south-LOOP recipes. The base loop is a half-oval from
## (+loop_rx, STRAIGHT_Z) curving south to (0, STRAIGHT_Z - loop_depth)
## back to (-loop_rx, STRAIGHT_Z). Each tier layers extra features:
##
##   chicanes: {start, end, amp, lobes}
##     Perpendicular sin-wave displacement of `lobes` cycles across
##     ψ ∈ [start, end] (ψ ∈ [0, π] = east end → south apex → west end).
##   kinks: {center, half_width, indent}
##     Smooth INWARD pull centred at ψ_center over ±half_width.
##
## Design rule: each tier KEEPS all of the previous tier's corners and
## ADDS 1-3 new ones in a fresh part of the loop. By tier 10 the loop
## has accumulated all the corners the player has built — like a real
## F1 circuit that's gained sections over the years.
##
## Amplitudes scale with track size — by tier 10 chicanes sweep 6-7 m
## off the racing line, and kinks indent 7-8 m, so each corner is
## clearly visible from the tycoon top-down view.
const TIER_LAYOUT := {
	# Tier 1 — backyard track: smooth half-oval, no extra corners.
	1: { "chicanes": [], "kinks": [] },
	# Tier 2 — adds a single EAST-side entry chicane. Asymmetric (off
	# the south apex) so the layout stops looking like a pure oval
	# the moment tier 2 unlocks.
	2: {
		"chicanes": [
			{"start": 0.20 * PI, "end": 0.40 * PI, "amp": 3.5, "lobes": 1},
		],
		"kinks": []
	},
	# Tier 3 — adds a TIGHT east-entry hairpin kink. Sharp corner
	# right at the start of the loop, distinct character from the
	# wider chicane.
	3: {
		"chicanes": [
			{"start": 0.20 * PI, "end": 0.40 * PI, "amp": 3.8, "lobes": 1},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 4.0},
		]
	},
	# Tier 4 — adds a long SWEEPING WEST-side bend on the opposite
	# arc. Single-lobe chicane but with bigger amplitude — feels
	# different from the east entry chicane (sweep, not flick).
	4: {
		"chicanes": [
			{"start": 0.20 * PI, "end": 0.40 * PI, "amp": 4.0, "lobes": 1},
			{"start": 0.62 * PI, "end": 0.82 * PI, "amp": 4.8, "lobes": 1},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 4.2},
		]
	},
	# Tier 5 — adds a sharp CENTRAL apex pinch. Very narrow kink at
	# π/2, distinctly different geometry from any chicane (acts like
	# a single-corner detour right at the south apex).
	5: {
		"chicanes": [
			{"start": 0.20 * PI, "end": 0.40 * PI, "amp": 4.2, "lobes": 1},
			{"start": 0.62 * PI, "end": 0.82 * PI, "amp": 5.0, "lobes": 1},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 4.5},
			{"center": 0.50 * PI, "half_width": 0.05 * PI, "indent": 4.2},
		]
	},
	# Tier 6 — adds a mirror WEST-side hairpin, finally balancing
	# the east hairpin from tier 3.
	6: {
		"chicanes": [
			{"start": 0.20 * PI, "end": 0.40 * PI, "amp": 4.5, "lobes": 1},
			{"start": 0.62 * PI, "end": 0.82 * PI, "amp": 5.2, "lobes": 1},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 5.0},
			{"center": 0.50 * PI, "half_width": 0.05 * PI, "indent": 4.5},
			{"center": 0.90 * PI, "half_width": 0.08 * PI, "indent": 5.0},
		]
	},
	# Tier 7 — east entry chicane upgraded to a DOUBLE-S section.
	# The single sweeping bend is replaced with a rapid S-S, real
	# change of character on that arc (was a flowing curve, now
	# a technical complex).
	7: {
		"chicanes": [
			{"start": 0.18 * PI, "end": 0.42 * PI, "amp": 5.0, "lobes": 2},
			{"start": 0.62 * PI, "end": 0.82 * PI, "amp": 5.2, "lobes": 1},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 5.2},
			{"center": 0.50 * PI, "half_width": 0.05 * PI, "indent": 4.7},
			{"center": 0.90 * PI, "half_width": 0.08 * PI, "indent": 5.2},
		]
	},
	# Tier 8 — adds a TECHNICAL south-central chicane between the
	# east and west sections. Wedged into the gap, distinct from
	# both flanking chicanes.
	8: {
		"chicanes": [
			{"start": 0.18 * PI, "end": 0.40 * PI, "amp": 5.3, "lobes": 2},
			{"start": 0.43 * PI, "end": 0.57 * PI, "amp": 4.0, "lobes": 1},
			{"start": 0.62 * PI, "end": 0.82 * PI, "amp": 5.5, "lobes": 1},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 5.5},
			{"center": 0.90 * PI, "half_width": 0.08 * PI, "indent": 5.5},
		]
	},
	# Tier 9 — west sweeper now ALSO upgraded to a double-S, plus a
	# fresh central Eau-Rouge-style mid-apex kink. Both arcs now
	# have rapid S-S complexes.
	9: {
		"chicanes": [
			{"start": 0.18 * PI, "end": 0.40 * PI, "amp": 5.5, "lobes": 2},
			{"start": 0.43 * PI, "end": 0.57 * PI, "amp": 4.5, "lobes": 1},
			{"start": 0.60 * PI, "end": 0.82 * PI, "amp": 5.5, "lobes": 2},
		],
		"kinks": [
			{"center": 0.10 * PI, "half_width": 0.08 * PI, "indent": 6.0},
			{"center": 0.50 * PI, "half_width": 0.04 * PI, "indent": 4.8},
			{"center": 0.90 * PI, "half_width": 0.08 * PI, "indent": 6.0},
		]
	},
	# Tier 10 — full F1: adds a "BUS-STOP" chicane right before the
	# west exit (single lobe, sharp pinch). Six distinct sections
	# across the lap, each with its own character.
	10: {
		"chicanes": [
			{"start": 0.16 * PI, "end": 0.40 * PI, "amp": 6.0, "lobes": 2},
			{"start": 0.42 * PI, "end": 0.55 * PI, "amp": 4.8, "lobes": 1},
			{"start": 0.55 * PI, "end": 0.78 * PI, "amp": 6.0, "lobes": 2},
			{"start": 0.80 * PI, "end": 0.90 * PI, "amp": 4.5, "lobes": 1},
		],
		"kinks": [
			{"center": 0.08 * PI, "half_width": 0.07 * PI, "indent": 6.5},
			{"center": 0.50 * PI, "half_width": 0.04 * PI, "indent": 5.0},
			{"center": 0.92 * PI, "half_width": 0.07 * PI, "indent": 6.5},
		]
	},
}

# TIER_WAVE_AMP — the maximum OUTWARD displacement of any feature in
# the tier's layout. Used by facility positioning so buildings,
# sponsors and lights always sit clear of the wobbliest chicane.
const TIER_WAVE_AMP := {
	1: 0.0, 2: 3.5, 3: 3.8, 4: 4.8, 5: 5.0,
	6: 5.2, 7: 5.5, 8: 5.8, 9: 6.2, 10: 6.5
}
# Legacy — no longer drives the curve shape; kept so external code
# referencing it still gets a sensible value.
const TIER_WAVE_FREQ := {
	1: 0, 2: 1, 3: 1, 4: 2, 5: 3,
	6: 3, 7: 4, 8: 5, 9: 6, 10: 7
}
const TIER_RIBBON_COLOR := {
	1: Color(0.40, 0.65, 1.00),
	2: Color(0.13, 0.83, 0.96),
	3: Color(0.55, 0.92, 0.38),
	4: Color(0.99, 0.75, 0.18),
	5: Color(1.00, 0.55, 0.20),
	6: Color(0.96, 0.27, 0.36),
	7: Color(0.86, 0.42, 0.98),
	8: Color(0.50, 0.30, 0.95),
	9: Color(1.00, 0.30, 0.55),
   10: Color(0.95, 0.95, 0.95),
}
const TIER_RUMBLE_COLOR := {
	1: Color(0.96, 0.27, 0.36),
	2: Color(0.96, 0.27, 0.36),
	3: Color(0.96, 0.27, 0.36),
	4: Color(0.96, 0.30, 0.30),
	5: Color(1.00, 0.35, 0.30),
	6: Color(1.00, 0.40, 0.20),
	7: Color(1.00, 0.30, 0.40),
	8: Color(1.00, 0.30, 0.55),
	9: Color(1.00, 0.20, 0.50),
   10: Color(1.00, 0.10, 0.30),
}
# Asphalt darkens as you climb tiers — but kept light enough to read
# as friendly cartoon grey rather than black hole. Tier 1 is the
# brightest "go-kart parking" grey, tier 10 the deepest race-track grey.
const TIER_ASPHALT_COLOR := {
	1: Color(0.50, 0.52, 0.56),
	2: Color(0.46, 0.48, 0.52),
	3: Color(0.42, 0.44, 0.48),
	4: Color(0.38, 0.40, 0.44),
	5: Color(0.34, 0.36, 0.40),
	6: Color(0.30, 0.32, 0.36),
	7: Color(0.27, 0.29, 0.33),
	8: Color(0.24, 0.26, 0.30),
	9: Color(0.21, 0.23, 0.26),
   10: Color(0.18, 0.19, 0.22),
}

# Level-based progression. MAX_LEVEL is the cumulative cap across all
# 10 tiers; reaching it costs ~10^22 to fully clear.
const MAX_LEVEL: int = 450

# Cost growth — base costs are higher than before so the early game
# isn't a sprint. Player needs to actually grind a few customer cycles
# before each upgrade. End-game cumulative still reaches the
# multi-quintillion range thanks to compounding 1.10 growth per level.
const TRACK_UPGRADE_BASE_COST: float = 200.0
const TRACK_UPGRADE_GROWTH: float = 1.08
const KART_UPGRADE_BASE_COST: float = 80.0
const KART_UPGRADE_GROWTH: float = 1.08
const BUY_KART_BASE_COST: float = 800.0
const BUY_KART_LEVEL_FACTOR: float = 50.0
const BUY_KART_FLEET_GROWTH: float = 1.18

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
var start_finish_root: Node3D

var karts: Array = []                 # plain Array (typed Array[Kart] could swallow appends silently on some Godot builds)
var queue: Array[Customer] = []
var racing: Array[Customer] = []

var _arrival_timer: float = 0.0


# ---------------------------------------------------------------------------
func _ready() -> void:
	# If returning from a load, restore track levels and kart count BEFORE
	# constructing visuals so we build the right tier from the start.
	if SaveManager.has_pending_track_state():
		var s := SaveManager.consume_pending_track_state()
		track_level       = int(s.get("track_level", 1))
		kart_level        = int(s.get("kart_level", 1))
		initial_kart_count = int(s.get("kart_count", initial_kart_count))
	# Safety net: a venue with no karts can't earn anything and locks the
	# player out, so always start with at least the default fleet size.
	if initial_kart_count <= 0:
		initial_kart_count = 5
	SaveManager.track = self
	add_to_group("track")
	_build_ground()
	_build_path()
	_build_asphalt()
	_build_click_area()
	_build_start_finish()
	for i in range(initial_kart_count):
		_add_kart_node(true)
	print("[Track] Spawned %d karts on Tier %d Lvl %d" % [karts.size(), track_tier(), track_level])
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
	for i in range(TIER_LEVEL_CAPS.size()):
		if track_level <= TIER_LEVEL_CAPS[i]:
			return i + 1
	return TIER_COUNT


func kart_tier() -> int:
	for i in range(TIER_LEVEL_CAPS.size()):
		if kart_level <= TIER_LEVEL_CAPS[i]:
			return i + 1
	return TIER_COUNT


func _tier_floor(tier: int) -> int:
	# Last level of the tier BELOW `tier` — i.e., one less than the
	# first level OF this tier.
	if tier <= 1:
		return 0
	return TIER_LEVEL_CAPS[tier - 2]


func track_level_in_tier() -> int:
	return track_level - _tier_floor(track_tier())


func kart_level_in_tier() -> int:
	return kart_level - _tier_floor(kart_tier())


func levels_in_current_track_tier() -> int:
	var t: int = track_tier()
	return TIER_LEVEL_CAPS[t - 1] - _tier_floor(t)


func levels_in_current_kart_tier() -> int:
	var t: int = kart_tier()
	return TIER_LEVEL_CAPS[t - 1] - _tier_floor(t)


# Track geometry is DISCRETE per tier — only changes at tier rollover,
# not on every per-level upgrade. The "current_*" wrappers exist so
# callers don't have to reach into the tier tables themselves.
func current_rx() -> float:
	# East-west half-extent of the loop (also of the full track,
	# since the north straight is centred at x=0 and the loop fans
	# out to ±loop_rx on each side).
	return float(TIER_LOOP_RX[track_tier()])

func current_rz() -> float:
	# Total Z extent: from STRAIGHT_Z (north) down to STRAIGHT_Z -
	# loop_depth (south). For backwards-compat callers that just need
	# a "size" value, return the loop depth (south-side extent which
	# is what most facility positioning cares about).
	return float(TIER_LOOP_DEPTH[track_tier()])

# Asymmetric Z extents — pit lane / marketing tower live on the
# +Z side at a small offset, while plaza / grandstand / lounge sit
# south at a much larger offset that grows per tier.
func north_extent_z(margin: float = 0.0) -> float:
	# Z coord of the asphalt's outer (+Z) edge along the main straight.
	return STRAIGHT_Z + current_asphalt_width() * 0.5 + RUMBLE_INSET + margin

func south_extent_z(margin: float = 0.0) -> float:
	# ABSOLUTE distance from origin to the asphalt's outer (-Z) edge
	# at the loop's south apex. Returned as a positive number — south-
	# side facilities sit at z = -south_extent_z(margin).
	return float(TIER_LOOP_DEPTH[track_tier()]) - STRAIGHT_Z \
		+ current_asphalt_width() * 0.5 + current_wave_amp() + RUMBLE_INSET + margin

func current_asphalt_width() -> float:
	return float(TIER_ASPHALT_WIDTH[track_tier()])

func current_wave_amp() -> float:
	return float(TIER_WAVE_AMP[track_tier()])

func current_wave_freq() -> int:
	return TIER_WAVE_FREQ[track_tier()]

func current_race_duration() -> float:
	return float(TIER_RACE_DURATION[track_tier()])


func venue_name() -> String:
	return TIER_NAMES[track_tier()]


func kart_capacity() -> int:
	# Capacity is purely tier-driven: 5 at tier 1 → 22 at tier 10 (the
	# real F1 grid size). Each tier upgrade unlocks 1-2 new slots so
	# the player feels the bump immediately on tier-up.
	return TIER_KART_CAPACITY[track_tier()]


func can_upgrade_track() -> bool:
	# Track upgrade is BLOCKED if any kart component is more than
	# 50 levels behind the track. Forces the player to keep their
	# fleet's subsystems within range of the venue's tier — no more
	# track-level-364 with brakes-level-5 imbalances. The first 50
	# track levels have no component requirement so the early game
	# never feels stuck.
	if track_level >= MAX_LEVEL:
		return false
	var required_min_component: int = maxi(0, track_level - 50)
	if KartComponents.min_component_level() < required_min_component:
		return false
	return true


func track_upgrade_block_reason() -> String:
	# Human-readable reason if can_upgrade_track() returned false.
	# UI can surface this so the player knows what to upgrade.
	if track_level >= MAX_LEVEL:
		return "Track at MAX level"
	var required_min_component: int = maxi(0, track_level - 50)
	var weakest: int = KartComponents.min_component_level()
	if weakest < required_min_component:
		return "Karts need upgrades — weakest component must reach lvl %d (now %d)" % [
			required_min_component, weakest
		]
	return ""


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
	return int(round(per_kart * maxi(karts.size(), 1)))


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
		# Tier rollover — full visual rebuild (size, colour, chicanes,
		# garages, grandstands all snap to the new tier's recipe).
		_rebuild_for_new_tier()
		EventBus.track_tier_changed.emit(new_tier, venue_name())
	# NOTE: same-tier upgrades intentionally do NOT change the track
	# geometry — only the tier rollover changes the look of the venue.
	# Per-level upgrades only buy stat improvements (cost, capacity).
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
	for k: Kart in karts:
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
	for k: Kart in karts:
		var p: Node = k.get_parent()
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
	if start_finish_root:
		start_finish_root.queue_free()
	_build_ground()
	_build_path()
	_build_asphalt()
	_build_click_area()
	_build_start_finish()
	for k: Kart in karts:
		var prev_progress: float = k.progress
		path.add_child(k)
		k.progress = prev_progress


func _build_ground() -> void:
	# Big green grass plane covering the whole venue + surrounding
	# space. Scales generously so we don't have to re-build it for
	# every tier.
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	var size: float = 240.0
	plane.size = Vector2(size, size)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.48, 0.22)  # natural grass
	mat.metallic = 0.0
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = Vector3(0, -ASPHALT_DEPTH * 0.5 - 0.01, 0)
	add_child(ground)


func _build_path() -> void:
	path = Path3D.new()
	path.name = "RacePath"
	add_child(path)
	path.curve = _make_layout_curve(track_tier())


# Sample the per-tier layout into a closed Curve3D with PATH_SEGMENTS
# points. Each tier's recipe in TIER_LAYOUT defines a unique shape:
# pure oval, single chicane, double chicane, hairpin-style kinks,
# multi-S-bend complex, etc.
func _make_layout_curve(tier: int) -> Curve3D:
	var curve := Curve3D.new()
	for i in range(PATH_SEGMENTS):
		var t: float = float(i) / float(PATH_SEGMENTS) * TAU
		curve.add_point(_layout_curve_point(t, tier))
	# Close the loop by adding a final point coincident with the first.
	curve.add_point(curve.get_point_position(0))
	return curve


# Public wrapper — sample the CURRENT tier's track centreline at the
# given parameter. The parameter t ∈ [0, TAU) is split into:
#   t ∈ [0, π]: south LOOP (varies per tier)
#   t ∈ [π, TAU]: north STRAIGHT (FIXED across all tiers)
func track_curve_point(t: float) -> Vector3:
	return _layout_curve_point(t, track_tier())


# Public wrapper — outward-pointing unit normal of the BASE half-oval
# at parameter t. Used for offsetting parallel structures from the
# track's smooth central line rather than from the wobbly racing
# line, so the parallel road stays clean.
func oval_normal(t: float) -> Vector2:
	var loop_rx: float = float(TIER_LOOP_RX[track_tier()])
	var loop_depth: float = float(TIER_LOOP_DEPTH[track_tier()])
	if t >= 0.0 and t <= PI:
		# South loop — outward normal of the half-ellipse below z=STRAIGHT_Z.
		var psi: float = t  # ψ goes 0..π across the loop
		# Loop point is at (loop_rx * cos(ψ), STRAIGHT_Z - loop_depth * sin(ψ))
		# but flipped so ψ=0 → east end, ψ=π → west end.
		# Outward normal: (loop_depth * cos(ψ), -loop_rx * sin(ψ))
		var n := Vector2(loop_depth * cos(psi), -loop_rx * sin(psi))
		if n.length() < 0.001:
			return Vector2(1.0, 0.0)
		return n.normalized()
	else:
		# North straight — outward normal points +Z everywhere.
		return Vector2(0.0, 1.0)


# Public wrapper — the smooth IDEAL CENTRELINE point at parameter t
# (no chicanes, no kinks applied). Used as the reference for
# parallel offsets (pit lane).
func oval_point(t: float) -> Vector3:
	var loop_rx: float = float(TIER_LOOP_RX[track_tier()])
	var loop_depth: float = float(TIER_LOOP_DEPTH[track_tier()])
	if t >= 0.0 and t <= PI:
		# South loop — half-ellipse from east end (+loop_rx, STRAIGHT_Z)
		# at ψ=0 going through south apex (0, STRAIGHT_Z - loop_depth)
		# at ψ=π/2 to west end (-loop_rx, STRAIGHT_Z) at ψ=π.
		var psi: float = t
		return Vector3(loop_rx * cos(psi), 0.0,
			STRAIGHT_Z - loop_depth * sin(psi))
	else:
		# North straight: linear from west end (-loop_rx, STRAIGHT_Z)
		# at t=π back to east end (+loop_rx, STRAIGHT_Z) at t=TAU.
		var frac: float = (t - PI) / PI  # 0..1
		var x: float = lerpf(-loop_rx, loop_rx, frac)
		return Vector3(x, 0.0, STRAIGHT_Z)


# Compute a single point on the tier's track curve. The track is
# composed of a FIXED north straight (t ∈ [π, TAU]) plus a per-tier
# south loop (t ∈ [0, π]) with chicane / kink features.
#
# Chicanes and kinks ONLY apply to the loop section — the north
# straight stays perfectly straight on every tier so the pit lane,
# pit wall, garages and start-finish line keep a stable home across
# all upgrades.
func _layout_curve_point(t: float, tier: int) -> Vector3:
	# Wrap t into [0, TAU).
	t = fposmod(t, TAU)

	if t > PI:
		# North straight — pure linear interpolation, no features.
		var loop_rx: float = float(TIER_LOOP_RX[tier])
		var frac: float = (t - PI) / PI
		var x: float = lerpf(-loop_rx, loop_rx, frac)
		return Vector3(x, 0.0, STRAIGHT_Z)

	# South loop — base half-ellipse + chicanes + kinks.
	var loop_rx_b: float = float(TIER_LOOP_RX[tier])
	var loop_depth: float = float(TIER_LOOP_DEPTH[tier])
	var psi: float = t
	var base_x: float = loop_rx_b * cos(psi)
	var base_z: float = STRAIGHT_Z - loop_depth * sin(psi)
	# Outward normal of the half-ellipse (points away from oval centre).
	var nrm := Vector2(loop_depth * cos(psi), -loop_rx_b * sin(psi))
	if nrm.length() < 0.001:
		nrm = Vector2(1.0, 0.0)
	nrm = nrm.normalized()

	var layout: Dictionary = TIER_LAYOUT[tier]
	var dx: float = 0.0
	var dz: float = 0.0

	# Chicanes — perpendicular sin-wave wiggles in [start, end] ⊆ [0,π].
	var chicanes: Array = layout.get("chicanes", [])
	for c: Dictionary in chicanes:
		var c_start: float = float(c.start)
		var c_end: float = float(c.end)
		if psi < c_start or psi > c_end:
			continue
		var local_t: float = (psi - c_start) / (c_end - c_start)
		var lobes: int = int(c.get("lobes", 1))
		var fade: float = sin(local_t * PI)        # smooth join at edges
		var wave: float = sin(local_t * TAU * float(lobes))
		var amp: float = float(c.amp)
		var displacement: float = wave * fade * amp
		dx += nrm.x * displacement
		dz += nrm.y * displacement

	# Kinks — smooth INWARD pull centred at ψ_center over ±half_width.
	var kinks: Array = layout.get("kinks", [])
	for k: Dictionary in kinks:
		var k_center: float = float(k.center)
		var k_hw: float = float(k.half_width)
		var k_indent: float = float(k.indent)
		var dt_k: float = absf(psi - k_center)
		if dt_k > k_hw:
			continue
		var bell: float = 0.5 * (1.0 + cos(dt_k / k_hw * PI))
		dx -= nrm.x * k_indent * bell
		dz -= nrm.y * k_indent * bell

	return Vector3(base_x + dx, 0.0, base_z + dz)


func _build_asphalt() -> void:
	var t_tier: int = track_tier()
	var w: float = current_asphalt_width()
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
	ribbon_material.albedo_color = TIER_ASPHALT_COLOR[t_tier]
	ribbon_material.metallic = 0.05
	ribbon_material.roughness = 0.85
	asphalt_csg.material_override = ribbon_material
	add_child(asphalt_csg)


func _build_click_area() -> void:
	# A flat box covering the track footprint so any click on the
	# asphalt forwards to the track-upgrade popup. Sized to the
	# asymmetric venue: width = full east-west extent of the loop,
	# depth = STRAIGHT_Z (north edge) to STRAIGHT_Z - loop_depth
	# (south edge).
	click_area = Area3D.new()
	click_area.name = "TrackClick"
	click_area.collision_layer = 1
	click_area.collision_mask = 1
	click_area.add_to_group("track_clickable")
	click_area.set_meta("kind", "track")
	add_child(click_area)
	click_collider = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var t_tier: int = track_tier()
	var loop_rx: float = float(TIER_LOOP_RX[t_tier])
	var loop_depth: float = float(TIER_LOOP_DEPTH[t_tier])
	shape.size = Vector3(loop_rx * 2.3, 0.4, loop_depth * 1.15)
	click_collider.shape = shape
	# Centred between the north straight (z=STRAIGHT_Z) and the south
	# loop apex (z=STRAIGHT_Z - loop_depth) — i.e. at z = STRAIGHT_Z -
	# loop_depth/2.
	click_collider.position = Vector3(0, 0.05, STRAIGHT_Z - loop_depth * 0.5)
	click_area.add_child(click_collider)


func _build_start_finish() -> void:
	# Start/finish line painted across the FIXED north straight in
	# world coords — same place across every tier, like a real F1
	# circuit's iconic start gantry. Cars travel west→east on the
	# straight (parameter t increases through [π, TAU] which maps x
	# from -loop_rx to +loop_rx).
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	start_finish_root = Node3D.new()
	start_finish_root.name = "StartFinish"
	add_child(start_finish_root)

	var t_tier: int = track_tier()
	var w: float = TIER_ASPHALT_WIDTH[t_tier]
	# Centre of the fixed straight: x=0, z=STRAIGHT_Z. Tangent points
	# +X (east, racing direction). Across-track axis is ±Z.
	var line_centre: Vector3 = Vector3(0.0, 0.0, STRAIGHT_Z)
	var tangent: Vector3 = Vector3(1.0, 0.0, 0.0)
	# perp_south points -Z, into the loop.
	var perp_south: Vector3 = Vector3(0.0, 0.0, -1.0)
	# perp_north points +Z, toward the pit lane / outside.
	var perp_north: Vector3 = Vector3(0.0, 0.0, 1.0)

	# Checkered finish line — two rows of alternating black/white
	# squares spanning the asphalt width.
	var checker_count: int = 8
	var checker_total_w: float = w * 0.95
	var checker_w: float = checker_total_w / float(checker_count)
	var checker_l: float = 0.55
	var rows: int = 2
	for row in range(rows):
		var along_offset: float = -checker_l * float(rows) * 0.5 \
			+ (float(row) + 0.5) * checker_l
		for i in range(checker_count):
			var is_white: bool = ((i + row) % 2 == 0)
			var across_offset: float = -checker_total_w * 0.5 \
				+ (float(i) + 0.5) * checker_w
			var c_pos: Vector3 = line_centre \
				+ tangent * along_offset \
				+ perp_south * across_offset \
				+ Vector3(0, 0.07, 0)
			var c := MeshInstance3D.new()
			var cbm := BoxMesh.new()
			cbm.size = Vector3(checker_l * 0.96, 0.06, checker_w * 0.94)
			c.mesh = cbm
			var cmat := StandardMaterial3D.new()
			if is_white:
				cmat.albedo_color = Color(0.96, 0.97, 1.0)
				cmat.emission_enabled = true
				cmat.emission = Color(0.96, 0.97, 1.0)
				cmat.emission_energy_multiplier = 0.45
			else:
				cmat.albedo_color = Color(0.05, 0.05, 0.07)
				cmat.roughness = 0.9
			c.material_override = cmat
			c.position = c_pos
			start_finish_root.add_child(c)

	# Podium pillar on the inside of the straight (south side), so the
	# start gantry doesn't conflict with the pit lane up north.
	var podium := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(0.4, 1.6, 0.4)
	podium.mesh = pbm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.96, 0.97, 1.0)
	pmat.emission_enabled = true
	pmat.emission = Color(0.96, 0.97, 1.0)
	pmat.emission_energy_multiplier = 0.5
	podium.material_override = pmat
	podium.position = line_centre + perp_south * (w * 0.55 + 0.4) \
		+ Vector3(0, 0.8, 0)
	start_finish_root.add_child(podium)

	# Starting-grid markers BEHIND the finish line (i.e. WEST, towards
	# -X), alternating sides north/south of the straight centreline.
	# The straight is perfectly straight so we can place them
	# directly in world coords — no curve sampling needed.
	var grid_count: int = kart_capacity()
	var spacing: float = 1.6
	var loop_rx: float = float(TIER_LOOP_RX[t_tier])
	for i in range(grid_count):
		var back_distance: float = float(i / 2 + 1) * spacing
		var side_sign: float = -1.0 if (i % 2 == 0) else 1.0
		var marker_x: float = -back_distance
		# If we'd run off the west end of the straight, wrap onto the
		# loop's west side instead — keeps grid clear at small tiers.
		if marker_x < -loop_rx + 0.5:
			break
		var marker_pos: Vector3 = Vector3(marker_x, 0.06,
			STRAIGHT_Z + side_sign * w * 0.22)
		var marker := MeshInstance3D.new()
		var mbm := BoxMesh.new()
		mbm.size = Vector3(0.6, 0.05, 0.30)
		marker.mesh = mbm
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = Color(0.92, 0.92, 0.95)
		mmat.emission_enabled = true
		mmat.emission = Color(0.92, 0.92, 0.95)
		mmat.emission_energy_multiplier = 0.45
		marker.material_override = mmat
		marker.position = marker_pos
		start_finish_root.add_child(marker)
	# Suppress unused-variable warning for perp_north (kept for future use).
	if perp_north.length() > 0.0:
		pass


func _add_kart_node(initial_spawn: bool) -> void:
	# 1. Instantiate the kart scene. Use a plain Node first; some Godot
	#    builds were strict about the typed assignment and silently
	#    dropped the kart when the runtime type-check fired.
	var instance: Node = KART_SCENE.instantiate()
	if instance == null:
		push_error("[Track] KART_SCENE.instantiate() returned null")
		return
	# 2. Cast to Kart explicitly so we can detect a missing script.
	var kart := instance as Kart
	if kart == null:
		push_error("[Track] Instantiated kart is not a Kart (is the script attached to res://scenes/kart.tscn?)")
		instance.queue_free()
		return
	# 3. Verify the path exists before parenting.
	if path == null or not is_instance_valid(path):
		push_error("[Track] No valid path to attach kart to")
		kart.queue_free()
		return
	# 4. Configure colour + level BEFORE add_child so they're visible
	#    in the kart's first _ready frame.
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
	# 5. Parent under the path (this triggers Kart._ready).
	path.add_child(kart)
	# 6. Spread starting progress so the initial fleet doesn't pile up
	#    on top of itself on the first curve point.
	kart.progress = float(karts.size()) * 4.0
	# 7. Track the live instance.
	karts.append(kart)
	print("[Track] Kart added — fleet size now %d" % karts.size())
	if not initial_spawn:
		kart.flash_spawn()


# --- Customer simulation ---------------------------------------------------
func _tick_arrivals(delta: float) -> void:
	# HARD CAP: parking lot caps simultaneous visitors. If the lot is
	# full, no new cars / customers can arrive until somebody finishes
	# their race and leaves.
	var visitor_count: int = queue.size() + racing.size()
	if visitor_count >= Facilities.parking_visitor_capacity():
		return
	var base_interval: float = maxf(1.6, 4.0 - GameManager.reputation * 0.02)
	# Marketing staff + Marketing Tower + daily events scale the arrival
	# interval (more rate = shorter interval = faster arrivals).
	var rate: float = Staff.marketing_arrival_multiplier() \
		* Facilities.marketing_arrival_multiplier() \
		* DailyEvents.arrival_multiplier_today
	var interval: float = base_interval / maxf(rate, 0.1)
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
	var protection := Staff.receptionist_walkout_protection()
	for c in queue:
		c.tick_queue(delta)
		if c.is_out_of_patience():
			# Receptionists win some customers back from leaving.
			if randf() < protection:
				c.wait_time *= 0.5
				continue
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
	for k: Kart in karts:
		if not k.is_busy():
			return k
	return null


func _start_race(c: Customer, kart: Kart) -> void:
	c.assigned_kart = kart
	var base_duration: float = current_race_duration()
	c.race_time_left = maxf(3.0, base_duration - Facilities.pit_lane_race_time_reduction())
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
	# Apply engine, lighting and daily-event revenue multipliers.
	var multiplied := int(round(payment
		* KartComponents.engine_revenue_multiplier()
		* Facilities.lighting_revenue_multiplier()
		* DailyEvents.revenue_multiplier_today))
	EconomyManager.add_revenue("Ticket", multiplied)
	# Cafeteria bonus: extra spend per visiting customer.
	var cafe_bonus := int(Facilities.cafeteria_revenue_per_customer())
	if cafe_bonus > 0:
		EconomyManager.add_revenue("Cafeteria", cafe_bonus)
	# Reputation: base + suit bonus + lounge bonus + grandstand bonus per race.
	var rep := c.reputation_delta() \
		+ KartComponents.suit_reputation_bonus() \
		+ Facilities.lounge_reputation_per_race() \
		+ Facilities.grandstand_reputation_per_race()
	GameManager.add_reputation(rep)
	EventBus.race_finished.emit(track_id, multiplied)
	EventBus.customer_left.emit(c.id, c.satisfaction)
	if kart:
		kart.flash_finish(c.satisfaction)
	GameManager.set_active_customers(queue.size() + racing.size())


func _register_walkout(c: Customer) -> void:
	GameManager.add_reputation(-1)
	EventBus.customer_left.emit(c.id, 0.0)


func _on_day_ended(_summary: Dictionary) -> void:
	var base_maintenance := karts.size() * (5 + kart_tier() * 5)
	var maintenance := int(round(base_maintenance
		* KartComponents.chassis_maintenance_multiplier()
		* Facilities.pit_lane_maintenance_multiplier()
		* Staff.mechanic_maintenance_multiplier()
		* DailyEvents.maintenance_multiplier_today))
	EconomyManager.log_expense("Maintenance", maintenance)
