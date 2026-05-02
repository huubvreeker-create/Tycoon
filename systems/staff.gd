extends Node
##
## Staff hiring system. Five roles, capped at MAX_PER_ROLE each.
## Hiring is a one-time cost; salaries are debited daily on day_ended.
## Each role has a different effect on the simulation.
##

const MAX_PER_ROLE: int = 8
const HIRE_COST_GROWTH: float = 1.35

# Track-tier required to hire each role. Mirrors the facility lock
# system so the player can't fill out the entire roster on day one
# — staff progresses alongside venue progression.
const _REQUIRED_TRACK_TIER := {
	"mechanic":     1,
	"janitor":      1,
	"receptionist": 2,
	"instructor":   3,
	"marketing":    4,
}

# Each role also has a tier-scaled HEADCOUNT cap on top of the global
# MAX_PER_ROLE — even at higher tiers you can't stack 8 instructors
# at tier 1. Caps grow as the venue grows.
const _MAX_PER_TIER := {
	1: 1, 2: 2, 3: 3, 4: 4, 5: 5,
	6: 6, 7: 6, 8: 7, 9: 7, 10: 8,
}

const _BASE_HIRE_COST := {
	"mechanic":    1200,
	"receptionist": 900,
	"marketing":   1800,
	"instructor":  1500,
	"janitor":      600,
}

const _DAILY_SALARY := {
	"mechanic":     80,
	"receptionist": 60,
	"marketing":   100,
	"instructor":   90,
	"janitor":      50,
}

const _NAMES := {
	"mechanic":     "Mechanic",
	"receptionist": "Receptionist",
	"marketing":    "Marketing Manager",
	"instructor":   "Race Instructor",
	"janitor":      "Janitor",
}

const _DESCRIPTIONS := {
	"mechanic":     "-8% maintenance per mechanic",
	"receptionist": "Keeps customers in queue (less walkouts)",
	"marketing":    "+10% customer arrivals per manager",
	"instructor":   "+1.5% satisfaction per instructor",
	"janitor":      "+1 reputation per day per janitor",
}

var counts := {
	"mechanic":     0,
	"receptionist": 0,
	"marketing":    0,
	"instructor":   0,
	"janitor":      0,
}


func _ready() -> void:
	EventBus.day_ended.connect(_on_day_ended)


# --- Effects ----------------------------------------------------------------
func mechanic_maintenance_multiplier() -> float:
	return maxf(0.30, 1.0 - counts.mechanic * 0.08)

func receptionist_walkout_protection() -> float:
	# 0.0 → 1.0; multiplied against walkout chance.
	return clampf(counts.receptionist * 0.10, 0.0, 0.6)

func marketing_arrival_multiplier() -> float:
	return 1.0 + counts.marketing * 0.10

func instructor_satisfaction_bonus() -> float:
	return counts.instructor * 0.015

func janitor_reputation_per_day() -> int:
	return counts.janitor

func total_daily_salaries() -> int:
	var total := 0
	for role: String in counts.keys():
		total += counts[role] * _DAILY_SALARY[role]
	return total


# --- API --------------------------------------------------------------------
func role_names() -> Array[String]:
	return ["mechanic", "receptionist", "marketing", "instructor", "janitor"]

func display_name(role: String) -> String:
	return _NAMES.get(role, role)

func description(role: String) -> String:
	return _DESCRIPTIONS.get(role, "")

func get_count(role: String) -> int:
	return counts.get(role, 0)

func required_track_tier(role: String) -> int:
	return _REQUIRED_TRACK_TIER.get(role, 1)

func is_unlocked(role: String, current_track_tier: int) -> bool:
	return current_track_tier >= required_track_tier(role)

func current_role_cap(role: String) -> int:
	# Tier-scaled cap, never exceeding the global MAX_PER_ROLE.
	if SaveManager.track == null:
		return MAX_PER_ROLE
	var t: int = SaveManager.track.track_tier()
	var per_tier: int = int(_MAX_PER_TIER.get(t, MAX_PER_ROLE))
	return mini(MAX_PER_ROLE, per_tier)

func can_hire(role: String) -> bool:
	# Need both: role must be unlocked at current tier AND current
	# count below the tier-scaled cap.
	if SaveManager.track != null:
		var t: int = SaveManager.track.track_tier()
		if not is_unlocked(role, t):
			return false
	return get_count(role) < current_role_cap(role)

func hire_cost(role: String) -> int:
	var current := get_count(role)
	if current >= MAX_PER_ROLE:
		return -1
	return int(round(_BASE_HIRE_COST.get(role, 300) * pow(HIRE_COST_GROWTH, current)))

func daily_salary(role: String) -> int:
	return _DAILY_SALARY.get(role, 0)

func hire(role: String) -> bool:
	if not can_hire(role):
		return false
	var cost := hire_cost(role)
	if not EconomyManager.try_spend("Hire " + display_name(role), cost):
		return false
	counts[role] = counts.get(role, 0) + 1
	EventBus.staff_hired.emit(role)
	return true

func effect_text(role: String) -> String:
	match role:
		"mechanic":
			return "%.0f%% maintenance cost" % [mechanic_maintenance_multiplier() * 100.0]
		"receptionist":
			return "%.0f%% walkout protection" % [receptionist_walkout_protection() * 100.0]
		"marketing":
			return "+%.0f%% customer arrivals" % [(marketing_arrival_multiplier() - 1.0) * 100.0]
		"instructor":
			return "+%.1f%% satisfaction" % [instructor_satisfaction_bonus() * 100.0]
		"janitor":
			return "+%d reputation/day" % [janitor_reputation_per_day()]
	return ""


func _on_day_ended(_summary: Dictionary) -> void:
	var salaries := total_daily_salaries()
	if salaries > 0:
		EconomyManager.log_expense("Salaries", salaries)
	var rep_bonus := janitor_reputation_per_day()
	if rep_bonus > 0:
		GameManager.add_reputation(rep_bonus)
