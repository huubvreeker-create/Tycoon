extends Node
##
## Tracks money in / out. Single source of truth for cash.
## Other systems should call add_revenue() / log_expense() / try_spend()
## rather than mutating cash directly.
##

# TEMPORARY for testing — bumped from 5_000 so the player can buy
# everything immediately to inspect the visual result. Revert to
# 5_000 once playtesting is done.
const STARTING_CASH: int = 5_000_000

var cash: int = STARTING_CASH

# Per-day ledger so the day-end summary can show totals.
var revenue_today: int = 0
var expenses_today: int = 0


func _ready() -> void:
	EventBus.day_ended.connect(_on_day_ended)


func add_revenue(label: String, amount: int) -> void:
	if amount <= 0:
		return
	cash += amount
	revenue_today += amount
	EventBus.revenue_logged.emit(label, amount)
	EventBus.cash_changed.emit(cash)


func log_expense(label: String, amount: int) -> void:
	if amount <= 0:
		return
	cash -= amount
	expenses_today += amount
	EventBus.expense_logged.emit(label, amount)
	EventBus.cash_changed.emit(cash)


## Attempt a discretionary purchase. Returns true on success.
func try_spend(label: String, amount: int) -> bool:
	if cash < amount:
		return false
	log_expense(label, amount)
	return true


func profit_today() -> int:
	return revenue_today - expenses_today


func _on_day_ended(_summary: Dictionary) -> void:
	# Credit passive facility income before resetting the ledger.
	var passive := Facilities.total_daily_passive_income()
	if passive > 0:
		add_revenue("Passive income", passive)
	revenue_today = 0
	expenses_today = 0
