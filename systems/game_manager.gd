extends Node
##
## High-level game state: day counter, reputation, active customer count.
## Phase 1 keeps day progression idle; Phase 2 will drive it from a timer.
##

var day: int = 1
var reputation: int = 0
var active_customers: int = 0


func advance_day() -> void:
	var summary := {
		"day": day,
		"revenue": EconomyManager.revenue_today,
		"expenses": EconomyManager.expenses_today,
		"profit": EconomyManager.profit_today(),
	}
	EventBus.day_ended.emit(summary)
	day += 1
	EventBus.day_changed.emit(day)


func add_reputation(amount: int) -> void:
	reputation = max(0, reputation + amount)
	EventBus.reputation_changed.emit(reputation)


func set_active_customers(count: int) -> void:
	active_customers = count
	EventBus.customer_count_changed.emit(active_customers)
