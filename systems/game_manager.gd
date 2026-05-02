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
# Ticket price is no longer manually controlled — it auto-scales with
# the player's track level so revenue keeps pace with the cost curve.
const TICKET_BASE_PRICE: int = 15
const TICKET_GROWTH: float = 1.07
const TICKET_DEFAULT: int = TICKET_BASE_PRICE

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
	# Re-price the ticket whenever the track levels up.
	EventBus.track_level_changed.connect(_on_track_level_changed)


func _on_track_level_changed(level: int, _tier: int) -> void:
	var new_price: int = compute_ticket_price(level)
	if new_price != ticket_price:
		ticket_price = new_price
		EventBus.ticket_price_changed.emit(ticket_price)


static func compute_ticket_price(track_level: int) -> int:
	return int(round(float(TICKET_BASE_PRICE) * pow(TICKET_GROWTH, float(maxi(track_level, 1) - 1))))


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


func pause_clock() -> void:
	_running = false


func resume_clock() -> void:
	_running = true
