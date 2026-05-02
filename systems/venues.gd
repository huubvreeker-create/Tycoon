extends Node
##
## Phase 6 — Empire expansion. Satellite venues unlocked as the player
## climbs the track tiers. Each one is a one-time acquisition that
## becomes a passive income source you can then INVEST in to scale up
## its earnings.
##
## We don't build full Track / Facilities / Staff state for each
## satellite — that would explode the save format and the UI. Instead
## a satellite is just a (name, region, level, daily_income_curve)
## tuple, conceptually equivalent to running a smaller venue under
## the same brand. The active home track stays the player's main
## focus; satellites are passive empire-builders.
##
## Four satellites total, mirroring the README's "Tier 1 → 4 venues":
##   - Coastal Speedway        (unlocks tier 4)
##   - Mountain Pass Circuit   (unlocks tier 6)
##   - Desert Speedplex        (unlocks tier 8)
##   - Arctic Loop World Park  (unlocks tier 10)
##

const MAX_LEVEL: int = 100
const COST_GROWTH: float = 1.10

# Per-venue data — name, region tag, unlock track-tier, base ACQUIRE
# cost (one-time), base income coefficient, income compounding rate.
const _VENUES := [
	{
		"id": "coastal",
		"name": "Coastal Speedway",
		"region": "Coastal Province",
		"unlock_tier": 4,
		"acquire_cost": 5_000_000,
		"base_income": 800,
		"income_growth": 1.05,
		"upgrade_base_cost": 4_000,
		"color_top":    Color(0.30, 0.70, 0.95),
		"color_bottom": Color(0.10, 0.40, 0.65),
	},
	{
		"id": "mountain",
		"name": "Mountain Pass Circuit",
		"region": "Alpine Region",
		"unlock_tier": 6,
		"acquire_cost": 50_000_000,
		"base_income": 2_400,
		"income_growth": 1.06,
		"upgrade_base_cost": 12_000,
		"color_top":    Color(0.65, 0.55, 0.78),
		"color_bottom": Color(0.40, 0.32, 0.55),
	},
	{
		"id": "desert",
		"name": "Desert Speedplex",
		"region": "Desert State",
		"unlock_tier": 8,
		"acquire_cost": 500_000_000,
		"base_income": 7_500,
		"income_growth": 1.07,
		"upgrade_base_cost": 35_000,
		"color_top":    Color(1.00, 0.55, 0.20),
		"color_bottom": Color(0.75, 0.30, 0.10),
	},
	{
		"id": "arctic",
		"name": "Arctic Loop World Park",
		"region": "Polar Frontier",
		"unlock_tier": 10,
		"acquire_cost": 5_000_000_000,
		"base_income": 25_000,
		"income_growth": 1.08,
		"upgrade_base_cost": 100_000,
		"color_top":    Color(0.85, 0.92, 1.00),
		"color_bottom": Color(0.40, 0.65, 0.92),
	},
]

# Per-venue level. 0 = not acquired. 1+ = acquired and producing.
var levels: Dictionary = {
	"coastal":  0,
	"mountain": 0,
	"desert":   0,
	"arctic":   0,
}


func _ready() -> void:
	EventBus.day_ended.connect(_on_day_ended)


# --- Public API ------------------------------------------------------------
func venue_ids() -> Array[String]:
	return ["coastal", "mountain", "desert", "arctic"]

func venue_data(venue_id: String) -> Dictionary:
	for v: Dictionary in _VENUES:
		if v.id == venue_id:
			return v
	return {}

func display_name(venue_id: String) -> String:
	return venue_data(venue_id).get("name", venue_id)

func region(venue_id: String) -> String:
	return venue_data(venue_id).get("region", "")

func unlock_tier(venue_id: String) -> int:
	return int(venue_data(venue_id).get("unlock_tier", 1))

func get_level(venue_id: String) -> int:
	return int(levels.get(venue_id, 0))

func is_unlocked(venue_id: String, current_track_tier: int) -> bool:
	return current_track_tier >= unlock_tier(venue_id)

func is_acquired(venue_id: String) -> bool:
	return get_level(venue_id) >= 1

func acquire_cost(venue_id: String) -> int:
	return int(venue_data(venue_id).get("acquire_cost", 0))

func upgrade_cost(venue_id: String) -> int:
	# After acquisition, each level costs upgrade_base_cost growing
	# 1.10 per level (matches the rest of the economy).
	var lv: int = get_level(venue_id)
	if lv <= 0:
		return acquire_cost(venue_id)
	if lv >= MAX_LEVEL:
		return -1
	var data := venue_data(venue_id)
	var base: float = float(data.get("upgrade_base_cost", 1000))
	return int(round(base * pow(COST_GROWTH, lv)))

func can_upgrade(venue_id: String) -> bool:
	return get_level(venue_id) < MAX_LEVEL

func daily_income_for(venue_id: String) -> int:
	var lv: int = get_level(venue_id)
	if lv <= 0:
		return 0
	var data := venue_data(venue_id)
	var base: float = float(data.get("base_income", 0))
	var growth: float = float(data.get("income_growth", 1.05))
	return int(round(base * float(lv) * pow(growth, float(lv))))

func total_daily_income() -> int:
	var total: int = 0
	for vid: String in venue_ids():
		total += daily_income_for(vid)
	return total

func acquired_count() -> int:
	var count: int = 0
	for vid: String in venue_ids():
		if is_acquired(vid):
			count += 1
	return count


func upgrade(venue_id: String) -> bool:
	# Single entry point — acquires the venue if not yet owned, or
	# upgrades it by 1 level if already owned. Both actions cost.
	if not can_upgrade(venue_id):
		return false
	# Lock check against current track tier.
	if SaveManager.track != null:
		var current_tier: int = SaveManager.track.track_tier()
		if not is_unlocked(venue_id, current_tier):
			return false
	var cost: int = upgrade_cost(venue_id)
	var label: String = display_name(venue_id) + (
		"  ·  Acquire" if get_level(venue_id) == 0 else "  ·  Upgrade"
	)
	if not EconomyManager.try_spend(label, cost):
		return false
	levels[venue_id] = get_level(venue_id) + 1
	EventBus.facility_upgraded.emit("venue:" + venue_id, get_level(venue_id))
	return true


# --- Save / load -----------------------------------------------------------
func to_save_dict() -> Dictionary:
	return {"levels": levels.duplicate()}

func from_save_dict(d: Dictionary) -> void:
	var saved: Dictionary = d.get("levels", {})
	for vid: String in venue_ids():
		levels[vid] = int(saved.get(vid, 0))


# --- Daily tick ------------------------------------------------------------
func _on_day_ended(_summary: Dictionary) -> void:
	var income: int = total_daily_income()
	if income > 0:
		EconomyManager.add_revenue("Empire venues", income)
