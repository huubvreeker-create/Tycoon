extends CanvasLayer
##
## Top status bar. Subscribes to EventBus and reflects current
## economy / game state. New stats can be added here without
## the systems needing to know about the UI.
##

@onready var cash_label: Label = %CashLabel
@onready var reputation_label: Label = %ReputationLabel
@onready var day_label: Label = %DayLabel
@onready var customers_label: Label = %CustomersLabel
@onready var venue_label: Label = %VenueLabel


func _ready() -> void:
	EventBus.cash_changed.connect(_on_cash_changed)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.customer_count_changed.connect(_on_customer_count_changed)
	_refresh_all()


func _refresh_all() -> void:
	_on_cash_changed(EconomyManager.cash)
	_on_reputation_changed(GameManager.reputation)
	_on_day_changed(GameManager.day)
	_on_customer_count_changed(GameManager.active_customers)


func _format_cash(amount: int) -> String:
	# Insert thousands separators using a dot (European style: €50.000).
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "." + out
	if amount < 0:
		out = "-" + out
	return out


func _on_cash_changed(amount: int) -> void:
	cash_label.text = "Cash   €%s" % _format_cash(amount)


func _on_reputation_changed(rep: int) -> void:
	reputation_label.text = "Rep   %d" % rep


func _on_day_changed(day: int) -> void:
	day_label.text = "Day   %d" % day


func _on_customer_count_changed(count: int) -> void:
	customers_label.text = "Customers   %d" % count
