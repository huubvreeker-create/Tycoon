extends Node
##
## Upgradeable kart component sub-systems.
## Each component has levels 1..MAX_LEVEL with exponentially scaling
## costs and concrete mechanical / economic effects used by Track and
## Customer.
##
## Components are GATED by the current track tier — you can only
## upgrade a component up to TIER_LEVEL_CAPS[track_tier - 1]. This
## stops the player from running a tier-10 venue with brakes still
## at level 5: progressing the track forces matching investments in
## the individual kart subsystems.
##

const MAX_LEVEL: int = 450
const COST_GROWTH: float = 1.08

const _BASE_COST := {
	"engine":  350.0,
	"tires":   260.0,
	"chassis": 300.0,
	"suit":    200.0,
	"brakes":  240.0,
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
	return (engine_level - 1) * 0.05

func engine_revenue_multiplier() -> float:
	# Compounds: +1.2% per level → ~3.2× at level 100, 195× at level 450.
	# Tuned to stay slightly behind the 1.08/level cost growth so each
	# tier feels like a marathon — but the marathon never stalls.
	return pow(1.012, float(engine_level - 1))

func tires_satisfaction_bonus() -> float:
	# +0.1% per level, capped at +45% at MAX_LEVEL.
	return minf(0.45, (tires_level - 1) * 0.001)

func chassis_maintenance_multiplier() -> float:
	# Smooth ramp to 30% maintenance cost at MAX_LEVEL.
	return maxf(0.30, 1.0 - (chassis_level - 1) * 0.0016)

func suit_reputation_bonus() -> int:
	# +1 reputation per race for every 25 suit levels (level 26 = 1, 51 = 2, …).
	@warning_ignore("integer_division")
	return (suit_level - 1) / 25

func brakes_patience_bonus() -> float:
	# +0.13% patience per level, capped at +60%.
	return minf(0.60, (brakes_level - 1) * 0.0013)


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


func min_component_level() -> int:
	# Lowest level across all 5 subsystems. Used by Track to gate
	# track upgrades behind balanced component progression.
	return mini(mini(mini(mini(engine_level, tires_level), chassis_level),
		suit_level), brakes_level)

func current_tier_cap() -> int:
	# Component upgrades are capped by the current track tier — you
	# can't field tier-10 brakes on a tier-3 venue. Mirrors the way
	# facilities are gated, but using the level cap of the track's
	# CURRENT tier rather than a flat tier requirement.
	if SaveManager.track == null:
		return MAX_LEVEL
	var t: int = SaveManager.track.track_tier()
	var caps: Array = SaveManager.track.TIER_LEVEL_CAPS
	if t - 1 < 0 or t - 1 >= caps.size():
		return MAX_LEVEL
	return mini(int(caps[t - 1]), MAX_LEVEL)

func can_upgrade(component: String) -> bool:
	return get_level(component) < mini(MAX_LEVEL, current_tier_cap())

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
