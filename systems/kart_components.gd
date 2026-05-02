extends Node
##
## Upgradeable kart component sub-systems.
## Each component has levels 1-50, with exponentially scaling costs and
## concrete mechanical / economic effects used by Track and Customer.
##

const MAX_LEVEL: int = 50
const COST_GROWTH: float = 1.08

const _BASE_COST := {
	"engine":  150.0,
	"tires":   100.0,
	"chassis": 120.0,
	"suit":     80.0,
	"brakes":   90.0,
}

const _NAMES := {
	"engine":  "Engine",
	"tires":   "Tires",
	"chassis": "Chassis",
	"suit":    "Driver Suit",
	"brakes":  "Brakes",
}

const _DESCRIPTIONS := {
	"engine":  "More power → faster races, higher revenue",
	"tires":   "Better grip → higher satisfaction",
	"chassis": "Stiffer frame → lower maintenance cost",
	"suit":    "Pro gear → reputation bonus",
	"brakes":  "Safer stops → fewer walkouts",
}

var engine_level:  int = 1
var tires_level:   int = 1
var chassis_level: int = 1
var suit_level:    int = 1
var brakes_level:  int = 1


# --- Effects ----------------------------------------------------------------
func engine_speed_bonus() -> float:
	return (engine_level - 1) * 0.15

func engine_revenue_multiplier() -> float:
	return 1.0 + (engine_level - 1) * 0.004

func tires_satisfaction_bonus() -> float:
	return (tires_level - 1) * 0.003

func chassis_maintenance_multiplier() -> float:
	return maxf(0.3, 1.0 - (chassis_level - 1) * 0.006)

func suit_reputation_bonus() -> int:
	# +1 reputation per race for every 10 suit levels (level 11 = 1, 21 = 2, ...)
	@warning_ignore("integer_division")
	return (suit_level - 1) / 10

func brakes_patience_bonus() -> float:
	return (brakes_level - 1) * 0.005


# --- API --------------------------------------------------------------------
func component_names() -> Array[String]:
	return ["engine", "tires", "chassis", "suit", "brakes"]

func display_name(component: String) -> String:
	return _NAMES.get(component, component)

func description(component: String) -> String:
	return _DESCRIPTIONS.get(component, "")

func get_level(component: String) -> int:
	match component:
		"engine":  return engine_level
		"tires":   return tires_level
		"chassis": return chassis_level
		"suit":    return suit_level
		"brakes":  return brakes_level
	return 0

func can_upgrade(component: String) -> bool:
	return get_level(component) < MAX_LEVEL

func upgrade_cost(component: String) -> int:
	var lv := get_level(component)
	if lv >= MAX_LEVEL:
		return -1
	return int(round(_BASE_COST.get(component, 100.0) * pow(COST_GROWTH, lv - 1)))

func upgrade(component: String) -> bool:
	if not can_upgrade(component):
		return false
	var cost := upgrade_cost(component)
	if not EconomyManager.try_spend(display_name(component) + " upgrade", cost):
		return false
	match component:
		"engine":  engine_level  += 1
		"tires":   tires_level   += 1
		"chassis": chassis_level += 1
		"suit":    suit_level    += 1
		"brakes":  brakes_level  += 1
	EventBus.kart_component_upgraded.emit(component, get_level(component))
	return true

func effect_text(component: String) -> String:
	match component:
		"engine":
			return "+%.1f m/s speed  ×%.3f revenue" % [
				engine_speed_bonus(), engine_revenue_multiplier()
			]
		"tires":
			return "+%.1f%% satisfaction" % [tires_satisfaction_bonus() * 100.0]
		"chassis":
			return "%.0f%% maintenance cost" % [chassis_maintenance_multiplier() * 100.0]
		"suit":
			return "+%d rep per race" % [suit_reputation_bonus()]
		"brakes":
			return "+%.1f%% customer patience" % [brakes_patience_bonus() * 100.0]
	return ""
