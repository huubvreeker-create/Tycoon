extends CanvasLayer
##
## Top status bar + footer alerts. Subscribes to EventBus and reflects
## current economy / game state. New stats can be added here without
## the systems needing to know about the UI.
##

signal buy_kart_pressed

@export var track_path: NodePath

@onready var venue_label: Label          = %VenueLabel
@onready var cash_label: Label           = %CashLabel
@onready var reputation_label: Label     = %ReputationLabel
@onready var day_label: Label            = %DayLabel
@onready var customers_label: Label      = %CustomersLabel
@onready var queue_label: Label          = %QueueLabel
@onready var day_progress: ProgressBar   = %DayProgress
@onready var ticket_label: Label         = %TicketLabel
@onready var ticket_minus: Button        = %TicketMinusButton
@onready var ticket_plus: Button         = %TicketPlusButton
@onready var buy_kart_button: Button     = %BuyKartButton
@onready var alert_label: Label          = %AlertLabel
@onready var alert_timer: Timer          = %AlertTimer
@onready var event_tag: Label            = %EventTag
@onready var save_button: Button         = %SaveButton
@onready var load_button: Button         = %LoadButton

var _venue_name: String = "Hometown Indoor"
var _track_tier: int = 1
var _track_level: int = 1
var _track: Track


func _ready() -> void:
	_track = get_node_or_null(track_path) as Track
	EventBus.cash_changed.connect(_on_cash_changed)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.day_progress_changed.connect(_on_day_progress_changed)
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.customer_count_changed.connect(_on_customer_count_changed)
	EventBus.queue_changed.connect(_on_queue_changed)
	EventBus.ticket_price_changed.connect(_on_ticket_price_changed)
	EventBus.track_tier_changed.connect(_on_track_tier_changed)
	EventBus.track_level_changed.connect(_on_track_level_changed)
	EventBus.kart_count_changed.connect(_on_kart_count_changed)
	EventBus.daily_event_triggered.connect(_on_daily_event)

	ticket_minus.pressed.connect(func(): GameManager.bump_ticket_price(-GameManager.TICKET_STEP))
	ticket_plus.pressed.connect(func():  GameManager.bump_ticket_price( GameManager.TICKET_STEP))
	buy_kart_button.pressed.connect(_on_buy_kart_pressed)
	alert_timer.timeout.connect(func(): alert_label.text = "")
	save_button.pressed.connect(func(): SaveManager.save_game())
	load_button.pressed.connect(func(): SaveManager.load_game())
	EventBus.game_saved.connect(_on_game_saved)
	load_button.disabled = not SaveManager.has_save_file()

	_refresh_all()
	_refresh_buy_button()

	# If we just came back from SaveManager.load_game(), surface the load
	# confirmation and restore the event tag if an event was active.
	if SaveManager.just_loaded:
		SaveManager.just_loaded = false
		_flash("Loaded Day %d" % GameManager.day, Color(0.13, 0.83, 0.96), 2.5)
		if not DailyEvents.active_event.is_empty():
			_show_event_tag(DailyEvents.active_event)


func _refresh_all() -> void:
	_on_cash_changed(EconomyManager.cash)
	_on_reputation_changed(GameManager.reputation)
	_on_day_changed(GameManager.day)
	_on_customer_count_changed(GameManager.active_customers)
	_on_queue_changed(0)
	_on_ticket_price_changed(GameManager.ticket_price)
	_on_day_progress_changed(GameManager.day_progress())


func _format_cash(amount: int) -> String:
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


func _flash(text: String, color: Color = Color(0.95, 0.97, 1.0), duration: float = 4.0) -> void:
	alert_label.text = text
	alert_label.modulate = color
	alert_timer.stop()
	alert_timer.wait_time = duration
	alert_timer.start()


# --- EventBus handlers ------------------------------------------------------
func _on_cash_changed(amount: int) -> void:
	cash_label.text = "Cash   €%s" % _format_cash(amount)


func _on_reputation_changed(rep: int) -> void:
	reputation_label.text = "Rep   %d" % rep


func _on_day_changed(day: int) -> void:
	day_label.text = "Day   %d" % day


func _on_day_progress_changed(progress: float) -> void:
	day_progress.value = progress * 100.0


func _on_customer_count_changed(count: int) -> void:
	customers_label.text = "Customers   %d" % count


func _on_queue_changed(size: int) -> void:
	queue_label.text = "Queue   %d" % size


func _on_ticket_price_changed(price: int) -> void:
	ticket_label.text = "€%d" % price


func _on_track_tier_changed(tier: int, venue: String) -> void:
	_track_tier = tier
	_venue_name = venue
	_refresh_venue_label()
	_flash(
		"Track upgraded to %s" % venue,
		Color(0.13, 0.83, 0.96)
	)


func _on_track_level_changed(level: int, tier: int) -> void:
	_track_level = level
	_track_tier = tier
	_refresh_venue_label()


func _refresh_venue_label() -> void:
	venue_label.text = "Tier %d  Lvl %d  —  %s" % [_track_tier, _track_level, _venue_name]


func _on_day_ended(summary: Dictionary) -> void:
	# Clear the previous day's event tag here so it's gone before the next
	# day's daily_event_triggered (which fires synchronously from
	# DailyEvents on day_changed) can set a new one.
	if event_tag:
		event_tag.text = ""
		event_tag.visible = false
	var profit_color := Color(0.55, 0.92, 0.38) if summary.profit >= 0 else Color(0.96, 0.27, 0.36)
	_flash(
		"Day %d ended  —  Revenue €%s  |  Costs €%s  |  Profit €%s" % [
			summary.day,
			_format_cash(summary.revenue),
			_format_cash(summary.expenses),
			_format_cash(summary.profit),
		],
		profit_color,
		5.5
	)


func _on_kart_count_changed(_count: int, _capacity: int) -> void:
	_refresh_buy_button()


func _on_daily_event(event: Dictionary) -> void:
	var prefix: String = "GOOD" if event.get("good", false) else "BAD"
	_flash(
		"%s — %s: %s" % [prefix, event.get("title", "Event"), event.get("text", "")],
		event.get("color", Color(0.95, 0.97, 1.0)),
		6.0
	)
	_show_event_tag(event)


func _show_event_tag(event: Dictionary) -> void:
	if event_tag == null:
		return
	event_tag.text = "● %s" % event.get("title", "Event")
	event_tag.add_theme_color_override("font_color", event.get("color", Color(0.95, 0.97, 1.0)))
	event_tag.visible = true


func _on_buy_kart_pressed() -> void:
	# Open the KART tab in the upgrade panel so the player uses the panel flow.
	buy_kart_pressed.emit()


func _on_game_saved(day: int) -> void:
	_flash("Saved at Day %d" % day, Color(0.55, 0.92, 0.38), 2.5)
	if load_button:
		load_button.disabled = false


func _refresh_buy_button() -> void:
	if _track == null:
		buy_kart_button.text = "Buy Kart"
		buy_kart_button.disabled = true
		return
	if _track.can_buy_kart():
		var cost: int = _track.buy_kart_cost()
		buy_kart_button.text = "Karts   €%s" % _format_cash(cost)
		buy_kart_button.disabled = EconomyManager.cash < cost
	else:
		buy_kart_button.text = "Fleet full"
		buy_kart_button.disabled = true


func _process(_delta: float) -> void:
	if _track and _track.can_buy_kart():
		var cost := _track.buy_kart_cost()
		var should_disable := EconomyManager.cash < cost
		if buy_kart_button.disabled != should_disable:
			buy_kart_button.disabled = should_disable
