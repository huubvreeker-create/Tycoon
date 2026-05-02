extends Node
##
## Purchasable venue facilities. Each starts at level 0 (not built).
## Building costs more than upgrading; all effects scale with level.
##

const MAX_LEVEL: int = 100
const COST_GROWTH: float = 1.08

const _BUILD_COST := {
	"cafeteria":    1500.0,
	"pit_lane":     2400.0,
	"lounge":       3500.0,
	"merch_shop":   1800.0,
	"sponsor_boards":1200.0,
	"lighting":     2200.0,
	"grandstand":   1800.0,
	"parking":      1300.0,
	"marketing":    2000.0,
}

# Track-tier required to BUILD or UPGRADE each facility. Locked facilities
# show "Requires Tier X" in the panel until the player upgrades the
# track high enough.
const _REQUIRED_TRACK_TIER := {
	"pit_lane":       1,
	"cafeteria":      2,
	"merch_shop":     2,
	"parking":        2,
	"sponsor_boards": 3,
	"grandstand":     3,
	"marketing":      3,
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
	"parking":        "Parking Lot",
	"marketing":      "Marketing Tower",
}

const _DESCRIPTIONS := {
	"cafeteria":      "Food revenue per customer + satisfaction",
	"pit_lane":       "Pit revenue + faster races + lower maintenance",
	"lounge":         "VIP fees + satisfaction + reputation per race",
	"merch_shop":     "Passive daily income from merchandise",
	"sponsor_boards": "Sponsor revenue every day",
	"lighting":       "Night-event income + revenue multiplier",
	"grandstand":     "Spectator income + reputation per race",
	"parking":        "Caps simultaneous visitors — full = no new arrivals",
	"marketing":      "Promote the venue → more visitors per day",
}

var cafeteria_level:      int = 0
var pit_lane_level:       int = 0
var lounge_level:         int = 0
var merch_shop_level:     int = 0
var sponsor_boards_level: int = 0
var lighting_level:       int = 0
var grandstand_level:     int = 0
var parking_level:        int = 0
var marketing_level:      int = 0


# --- Effects ----------------------------------------------------------------
func cafeteria_revenue_per_customer() -> float:
	# Compounds: doubles every ~25 levels — late-game cafeteria scales
	# with the customer firehose so it stays relevant.
	return cafeteria_level * 4.0 * pow(1.030, float(cafeteria_level))

func cafeteria_satisfaction_bonus() -> float:
	return minf(0.30, cafeteria_level * 0.003)

func pit_lane_race_time_reduction() -> float:
	# Soft-capped so races never go below 2s
	return minf(8.0, pit_lane_level * 0.12)

func pit_lane_maintenance_multiplier() -> float:
	return maxf(0.10, 1.0 - pit_lane_level * 0.012)

func pit_lane_daily_income() -> int:
	# Pit operations + paddock services bring in steady cash.
	return int(round(60.0 * pit_lane_level * pow(1.05, float(pit_lane_level))))

func lounge_satisfaction_bonus() -> float:
	return minf(0.40, lounge_level * 0.005)

func lounge_reputation_per_race() -> int:
	# +1 reputation per race for every 4 lounge levels.
	@warning_ignore("integer_division")
	return lounge_level / 4

func lounge_daily_income() -> int:
	# VIP membership + corporate hospitality fees — biggest single
	# passive earner once levelled.
	return int(round(120.0 * lounge_level * pow(1.055, float(lounge_level))))

func merch_daily_income() -> int:
	# Compounds — endgame merch shop is a major income source.
	return int(round(75.0 * merch_shop_level * pow(1.05, float(merch_shop_level))))

func sponsor_daily_income() -> int:
	# Each sponsor board upgrade brings in noticeable extra cash even
	# though the on-track count is capped (boards just grow bigger).
	return int(round(50.0 * sponsor_boards_level * pow(1.05, float(sponsor_boards_level))))

func lighting_revenue_multiplier() -> float:
	# Compounds: +1.2% per level, multiplicative with engine.
	return pow(1.012, float(lighting_level))

func lighting_daily_income() -> int:
	# Night-event ticket premium / floodlit extra hours.
	return int(round(40.0 * lighting_level * pow(1.05, float(lighting_level))))

func grandstand_daily_income() -> int:
	return int(round(60.0 * grandstand_level * pow(1.05, float(grandstand_level))))

func grandstand_reputation_per_race() -> int:
	@warning_ignore("integer_division")
	return grandstand_level / 5

func parking_visitor_capacity() -> int:
	# Hard cap on simultaneous visitors at the venue. Free baseline
	# is a small street-parking spot; each level adds 4 more spaces.
	return 12 + parking_level * 4

func marketing_arrival_multiplier() -> float:
	# Each marketing tower level adds +6% to the arrival rate. Stacks
	# multiplicatively with marketing-manager staff.
	return 1.0 + marketing_level * 0.06

func total_daily_passive_income() -> int:
	return merch_daily_income() \
		+ sponsor_daily_income() \
		+ grandstand_daily_income() \
		+ pit_lane_daily_income() \
		+ lounge_daily_income() \
		+ lighting_daily_income()


# --- API --------------------------------------------------------------------
func facility_names() -> Array[String]:
	return ["pit_lane", "cafeteria", "merch_shop", "parking", "sponsor_boards", "grandstand", "marketing", "lounge", "lighting"]

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
		"parking":        return parking_level
		"marketing":      return marketing_level
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
		"parking":        parking_level        += 1
		"marketing":      marketing_level      += 1
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
			return "€%d/day  -%.2fs race  %.0f%% maint." % [
				pit_lane_daily_income(),
				pit_lane_race_time_reduction(),
				pit_lane_maintenance_multiplier() * 100.0
			]
		"lounge":
			return "€%d/day  +%.1f%% sat.  +%d rep/race" % [
				lounge_daily_income(),
				lounge_satisfaction_bonus() * 100.0,
				lounge_reputation_per_race()
			]
		"merch_shop":
			return "€%d passive income/day" % [merch_daily_income()]
		"sponsor_boards":
			return "€%d sponsor income/day" % [sponsor_daily_income()]
		"lighting":
			return "€%d/day  +%.1f%% revenue mult." % [
				lighting_daily_income(),
				lighting_revenue_multiplier() * 100.0 - 100.0
			]
		"grandstand":
			return "€%d/day  +%d rep/race" % [
				grandstand_daily_income(),
				grandstand_reputation_per_race()
			]
		"parking":
			return "%d simultaneous visitors max" % [parking_visitor_capacity()]
		"marketing":
			return "+%.0f%% customer arrivals" % [
				(marketing_arrival_multiplier() - 1.0) * 100.0
			]
	return ""
