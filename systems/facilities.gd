extends Node
##
## Purchasable venue facilities. Each starts at level 0 (not built).
## Building costs more than upgrading; all effects scale with level.
##

const MAX_LEVEL: int = 20
const COST_GROWTH: float = 1.12

const _BUILD_COST := {
	"cafeteria":     500.0,
	"pit_lane":      800.0,
	"lounge":       1000.0,
	"merch_shop":    600.0,
	"sponsor_boards":400.0,
	"lighting":      700.0,
}

const _NAMES := {
	"cafeteria":      "Cafeteria",
	"pit_lane":       "Pit Lane / Garage",
	"lounge":         "VIP Lounge",
	"merch_shop":     "Merch Shop",
	"sponsor_boards": "Sponsor Boards",
	"lighting":       "Lighting Rigs",
}

const _DESCRIPTIONS := {
	"cafeteria":      "Food revenue per customer + satisfaction",
	"pit_lane":       "Faster races + lower maintenance",
	"lounge":         "VIP multiplier + reputation per race",
	"merch_shop":     "Passive daily income",
	"sponsor_boards": "Sponsor revenue every day",
	"lighting":       "Night atmosphere + revenue multiplier",
}

var cafeteria_level:      int = 0
var pit_lane_level:       int = 0
var lounge_level:         int = 0
var merch_shop_level:     int = 0
var sponsor_boards_level: int = 0
var lighting_level:       int = 0


# --- Effects ----------------------------------------------------------------
func cafeteria_revenue_per_customer() -> float:
	return cafeteria_level * 3.0

func cafeteria_satisfaction_bonus() -> float:
	return cafeteria_level * 0.005

func pit_lane_race_time_reduction() -> float:
	return pit_lane_level * 0.25

func pit_lane_maintenance_multiplier() -> float:
	return maxf(0.25, 1.0 - pit_lane_level * 0.04)

func lounge_satisfaction_bonus() -> float:
	return lounge_level * 0.012

func lounge_reputation_per_race() -> int:
	# +1 reputation per race for every 4 lounge levels (level 4 = 1, 8 = 2, ...)
	@warning_ignore("integer_division")
	return lounge_level / 4

func merch_daily_income() -> int:
	return merch_shop_level * 50

func sponsor_daily_income() -> int:
	return sponsor_boards_level * 30

func lighting_revenue_multiplier() -> float:
	return 1.0 + lighting_level * 0.008

func total_daily_passive_income() -> int:
	return merch_daily_income() + sponsor_daily_income()


# --- API --------------------------------------------------------------------
func facility_names() -> Array[String]:
	return ["cafeteria", "pit_lane", "lounge", "merch_shop", "sponsor_boards", "lighting"]

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
	return 0

func can_upgrade(facility: String) -> bool:
	return get_level(facility) < MAX_LEVEL

func upgrade_cost(facility: String) -> int:
	var lv := get_level(facility)
	if lv >= MAX_LEVEL:
		return -1
	return int(round(_BUILD_COST.get(facility, 500.0) * pow(COST_GROWTH, lv)))

func upgrade(facility: String) -> bool:
	if not can_upgrade(facility):
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
	return ""
