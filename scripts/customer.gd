class_name Customer extends RefCounted
##
## Lightweight customer data model used by Track. No scene node — the
## Track draws queue / racing customers procedurally. Phase 5 may
## promote this to a Node2D if individual customers need physics.
##

# Bumped from 30 to give visitors enough time to walk from the
# parking lot all the way to the plaza on big-tier venues before
# their patience runs out (max parking lot ↔ plaza walk is ~50 m
# at brisk pace ≈ 17 s, so 60 s leaves a comfortable buffer).
const PATIENCE_BASE: float = 60.0
const SATISFACTION_BASE: float = 0.55

static var _next_id: int = 0

var id: int
var spending_power: float          # 0.7 .. 1.4 multiplier on ticket
var patience: float                # seconds before they leave the queue
var wait_time: float = 0.0
var satisfaction: float = SATISFACTION_BASE
var assigned_kart: Node = null     # Kart node when racing
var race_time_left: float = 0.0


func _init(rep: int = 0) -> void:
	_next_id += 1
	id = _next_id
	spending_power = randf_range(0.75, 1.35)
	# Reputation makes wealthier customers more common (longer patience too).
	patience = PATIENCE_BASE + mini(rep, 200) * 0.05


func tick_queue(delta: float) -> void:
	wait_time += delta


func is_out_of_patience() -> bool:
	return wait_time >= patience


## Compute final satisfaction at end-of-race.
## - track_tier / kart_tier are 1..4
## - ticket_price is the price they paid
func compute_satisfaction(track_tier: int, kart_tier: int, ticket_price: int) -> float:
	var s: float = SATISFACTION_BASE
	s += float(track_tier - 1) * 0.07
	s += float(kart_tier - 1) * 0.07
	# Brakes give extra patience → less wait penalty.
	var effective_patience := patience * (1.0 + KartComponents.brakes_patience_bonus())
	s -= clampf(wait_time / effective_patience, 0.0, 1.0) * 0.45
	s -= float(ticket_price - GameManager.TICKET_DEFAULT) / 200.0
	s += (spending_power - 1.0) * 0.05
	# Component, facility, staff and daily-event bonuses.
	s += KartComponents.tires_satisfaction_bonus()
	s += Facilities.cafeteria_satisfaction_bonus()
	s += Facilities.lounge_satisfaction_bonus()
	s += Staff.instructor_satisfaction_bonus()
	s += DailyEvents.satisfaction_bonus_today
	satisfaction = clampf(s, 0.0, 1.0)
	return satisfaction


## Final amount the customer pays. Always at least 50% of ticket
## (they showed up and rode), scaling up to 130% for happy bigspenders.
func compute_payment(ticket_price: int) -> int:
	var multiplier := 0.5 + satisfaction * 0.6 + (spending_power - 1.0) * 0.2
	return int(round(float(ticket_price) * multiplier))


## Reputation delta when leaving. Happy customers boost rep,
## furious ones hurt it. Mediocre rides do nothing.
func reputation_delta() -> int:
	if satisfaction >= 0.85:
		return 2
	elif satisfaction >= 0.65:
		return 1
	elif satisfaction <= 0.20:
		return -2
	elif satisfaction <= 0.35:
		return -1
	return 0
