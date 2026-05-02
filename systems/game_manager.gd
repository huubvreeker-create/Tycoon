extends Node
##
## High-level game state: day clock, day counter, reputation,
## active customer count, ticket price.
##
## Phase 2 introduces a real-time day clock that ticks down from
## DAY_LENGTH_SECONDS to zero, then advances the day and emits a
## summary via EventBus.day_ended.
##

const DAY_LENGTH_SECONDS: float = 90.0
const TICKET_MIN: int = 10
const TICKET_MAX: int = 80
const TICKET_STEP: int = 5
const TICKET_DEFAULT: int = 25

var day: int = 1
var reputation: int = 0
var active_customers: int = 0
var ticket_price: int = TICKET_DEFAULT

var _day_time_left: float = DAY_LENGTH_SECONDS
var _running: bool = false


func _ready() -> void:
	# Start the clock automatically; main.gd can pause/resume if needed.
	_running = true
	EventBus.day_progress_changed.emit(day_progress())


func _process(delta: float) -> void:
	if not _running:
		return
	_day_time_left -= delta
	EventBus.day_progress_changed.emit(day_progress())
	if _day_time_left <= 0.0:
		_advance_day()


func day_progress() -> float:
	return clampf(1.0 - (_day_time_left / DAY_LENGTH_SECONDS), 0.0, 1.0)


func _advance_day() -> void:
	var summary := {
		"day": day,
		"revenue": EconomyManager.revenue_today,
		"expenses": EconomyManager.expenses_today,
		"profit": EconomyManager.profit_today(),
	}
	EventBus.day_ended.emit(summary)
	day += 1
	_day_time_left = DAY_LENGTH_SECONDS
	EventBus.day_changed.emit(day)


func add_reputation(amount: int) -> void:
	reputation = maxi(0, reputation + amount)
	EventBus.reputation_changed.emit(reputation)


func set_active_customers(count: int) -> void:
	active_customers = count
	EventBus.customer_count_changed.emit(active_customers)


func set_ticket_price(price: int) -> void:
	ticket_price = clampi(price, TICKET_MIN, TICKET_MAX)
	EventBus.ticket_price_changed.emit(ticket_price)


func bump_ticket_price(delta: int) -> void:
	set_ticket_price(ticket_price + delta)


func pause_clock() -> void:
	_running = false


func resume_clock() -> void:
	_running = true
