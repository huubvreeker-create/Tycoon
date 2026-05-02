extends Node
##
## Purchasable venue facilities. Each starts at level 0 (not built).
## Building costs more than upgrading; all effects scale with level.
##

const MAX_LEVEL: int = 100
const COST_GROWTH: float = 1.10

const _BUILD_COST := {
	"cafeteria":     500.0,
	"pit_lane":      800.0,
	"lounge":       1000.0,
	"merch_shop":    600.0,
	"sponsor_boards":400.0,
	"lighting":      700.0,
	"grandstand":    600.0,
}

# Track-tier required to BUILD or UPGRADE each facility. Locked facilities
# show "Requires Tier X" in the panel until the player upgrades the
# track high enough.
const _REQUIRED_TRACK_TIER := {
	"cafeteria":      1,
	"merch_shop":     2,
	"pit_lane":       2,
	"sponsor_boards": 3,
	"grandstand":     3,
	"lounge":         4,
	"lighting":       5,
}

const _NAMES := {
	"cafeteria":      "Cafeteria",
	"pit_lane":       "Pit Lane / Garage",
	"lounge":         "VIP Lounge",
	"merch_shop":     "Merch Shop",
	"sponsor_boards": "Sponsor Boards",
	"lighting":       "Lighting Rigs",
	"grandstand":     "Grandstands",
}

const _DESCRIPTIONS := {
	"cafeteria":      "Food revenue per customer + satisfaction",
	"pit_lane":       "Faster races + lower maintenance",
	"lounge":         "VIP multiplier + reputation per race",
	"merch_shop":     "Passive daily income",
	"sponsor_boards": "Sponsor revenue every day",
	"lighting":       "Night atmosphere + revenue multiplier",
	"grandstand":     "Spectator income + reputation per race",
}

var cafeteria_level:      int = 0
var pit_lane_level:       int = 0
var lounge_level:         int = 0
var merch_shop_level:     int = 0
var sponsor_boards_level: int = 0
var lighting_level:       int = 0
var grandstand_level:     int = 0


# --- Effects ----------------------------------------------------------------
func cafeteria_revenue_per_customer() -> float:
	# Compounds: doubles every ~30 levels.
	return cafeteria_level * 3.0 * pow(1.025, float(cafeteria_level))

func cafeteria_satisfaction_bonus() -> float:
	return minf(0.30, cafeteria_level * 0.003)

func pit_lane_race_time_reduction() -> float:
	# Soft-capped so races never go below 2s
	return minf(8.0, pit_lane_level * 0.12)

func pit_lane_maintenance_multiplier() -> float:
	return maxf(0.10, 1.0 - pit_lane_level * 0.012)

func lounge_satisfaction_bonus() -> float:
	return minf(0.40, lounge_level * 0.005)

func lounge_reputation_per_race() -> int:
	# +1 reputation per race for every 4 lounge levels.
	@warning_ignore("integer_division")
	return lounge_level / 4

func merch_daily_income() -> int:
	# Compounds — endgame merch shop is a major income source.
	return int(round(50.0 * merch_shop_level * pow(1.04, float(merch_shop_level))))

func sponsor_daily_income() -> int:
	return int(round(30.0 * sponsor_boards_level * pow(1.04, float(sponsor_boards_level))))

func lighting_revenue_multiplier() -> float:
	# Compounds: +1% per level, multiplicative with engine.
	return pow(1.01, float(lighting_level))

func grandstand_daily_income() -> int:
	return int(round(40.0 * grandstand_level * pow(1.04, float(grandstand_level))))

func grandstand_reputation_per_race() -> int:
	@warning_ignore("integer_division")
	return grandstand_level / 5

func total_daily_passive_income() -> int:
	return merch_daily_income() + sponsor_daily_income() + grandstand_daily_income()


# --- API --------------------------------------------------------------------
func facility_names() -> Array[String]:
	return ["cafeteria", "pit_lane", "lounge", "merch_shop", "sponsor_boards", "lighting", "grandstand"]

func display_name(facility: String) -> String:
	return _NAMES.get(facility, facility)

func description(facility: String) -> String:
	return _DESCRIPTIONS.get(facility, "")

func get_level(facility: String) -> int:
	match facility:
		"cafeteria":      return cafeteria_level
		"pit_lane":       return pit_lane_level
		"lounge":         return lounge_level
		"merch_shop":     return merch_shop_level
		"sponsor_boards": return sponsor_boards_level
		"lighting":       return lighting_level
		"grandstand":     return grandstand_level
	return 0

func required_track_tier(facility: String) -> int:
	return _REQUIRED_TRACK_TIER.get(facility, 1)

func is_unlocked(facility: String, current_track_tier: int) -> bool:
	return current_track_tier >= required_track_tier(facility)

func can_upgrade(facility: String) -> bool:
	# NOTE: this only checks the level cap. UI / `upgrade()` callers
	# should additionally check `is_unlocked` against the live track
	# tier — the Facilities autoload doesn't have a Track ref.
	return get_level(facility) < MAX_LEVEL

func upgrade_cost(facility: String) -> int:
	var lv := get_level(facility)
	if lv >= MAX_LEVEL:
		return -1
	return int(round(_BUILD_COST.get(facility, 500.0) * pow(COST_GROWTH, lv)))

func upgrade(facility: String) -> bool:
	if not can_upgrade(facility):
		return false
	# Lock check — refuse if the player hasn't reached the required
	# track tier yet.
	if SaveManager.track != null:
		var current_tier: int = SaveManager.track.track_tier()
		if not is_unlocked(facility, current_tier):
			return false
	var cost := upgrade_cost(facility)
	if not EconomyManager.try_spend(display_name(facility) + " upgrade", cost):
		return false
	match facility:
		"cafeteria":      cafeteria_level      += 1
		"pit_lane":       pit_lane_level       += 1
		"lounge":         lounge_level         += 1
		"merch_shop":     merch_shop_level     += 1
		"sponsor_boards": sponsor_boards_level += 1
		"lighting":       lighting_level       += 1
		"grandstand":     grandstand_level     += 1
	EventBus.facility_upgraded.emit(facility, get_level(facility))
	return true

func effect_text(facility: String) -> String:
	match facility:
		"cafeteria":
			return "+€%.0f/customer  +%.1f%% satisfaction" % [
				cafeteria_revenue_per_customer(),
				cafeteria_satisfaction_bonus() * 100.0
			]
		"pit_lane":
			return "-%.2fs race time  %.0f%% maintenance" % [
				pit_lane_race_time_reduction(),
				pit_lane_maintenance_multiplier() * 100.0
			]
		"lounge":
			return "+%.1f%% satisfaction  +%d rep/race" % [
				lounge_satisfaction_bonus() * 100.0,
				lounge_reputation_per_race()
			]
		"merch_shop":
			return "€%d passive income/day" % [merch_daily_income()]
		"sponsor_boards":
			return "€%d sponsor income/day" % [sponsor_daily_income()]
		"lighting":
			return "+%.1f%% revenue multiplier" % [lighting_revenue_multiplier() * 100.0 - 100.0]
		"grandstand":
			return "€%d/day  +%d rep/race" % [
				grandstand_daily_income(),
				grandstand_reputation_per_race()
			]
	return ""
