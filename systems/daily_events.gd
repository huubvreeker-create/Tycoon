extends Node
##
## Random daily events. At the start of each new day there's a chance
## that something happens — could be a cash boost, a reputation hit,
## or a day-long modifier that affects arrivals / maintenance / etc.
##
## Other systems read the *_today modifiers each tick; this autoload
## resets them when the day rolls over.
##

const TRIGGER_CHANCE: float = 0.55

# Day-long modifiers — read by Track / EconomyManager / Customer.
var arrival_multiplier_today: float = 1.0
var maintenance_multiplier_today: float = 1.0
var revenue_multiplier_today: float = 1.0
var satisfaction_bonus_today: float = 0.0

var active_event: Dictionary = {}  # empty when no event today


# Catalogue of possible events.
const _EVENTS: Array[Dictionary] = [
	{
		"id": "influencer",
		"title": "Influencer Visits",
		"text": "A racing influencer films at the track.",
		"color": Color(0.86, 0.42, 0.98),
		"good": true,
		"weight": 1.2,
	},
	{
		"id": "bad_review",
		"title": "Harsh Review",
		"text": "A blogger gives the venue a brutal write-up.",
		"color": Color(0.96, 0.27, 0.36),
		"good": false,
		"weight": 1.0,
	},
	{
		"id": "sponsor_bonus",
		"title": "Sponsor Bonus",
		"text": "A new sponsor wires through a one-off bonus.",
		"color": Color(0.55, 0.92, 0.38),
		"good": true,
		"weight": 1.0,
	},
	{
		"id": "equipment_failure",
		"title": "Equipment Failure",
		"text": "A spare-parts emergency hits the workshop.",
		"color": Color(0.96, 0.27, 0.36),
		"good": false,
		"weight": 1.0,
	},
	{
		"id": "heatwave",
		"title": "Heatwave",
		"text": "Karts overheat — maintenance jumps 50% today.",
		"color": Color(0.99, 0.55, 0.20),
		"good": false,
		"weight": 1.1,
	},
	{
		"id": "local_holiday",
		"title": "Local Holiday",
		"text": "Families pour in — arrivals up 60% today.",
		"color": Color(0.99, 0.75, 0.18),
		"good": true,
		"weight": 1.2,
	},
	{
		"id": "power_outage",
		"title": "Power Outage",
		"text": "Lights flicker — operations crawl all day.",
		"color": Color(0.40, 0.40, 0.55),
		"good": false,
		"weight": 0.9,
	},
	{
		"id": "tv_crew",
		"title": "TV Crew Visit",
		"text": "Local TV films a feature — extra eyes on the venue.",
		"color": Color(0.13, 0.83, 0.96),
		"good": true,
		"weight": 1.0,
	},
	{
		"id": "competitor_strike",
		"title": "Rival Track Closed",
		"text": "Strike at a competing track redirects customers here.",
		"color": Color(0.55, 0.92, 0.38),
		"good": true,
		"weight": 0.9,
	},
	{
		"id": "tax_audit",
		"title": "Tax Audit",
		"text": "Inspectors demand back-tax payment.",
		"color": Color(0.96, 0.27, 0.36),
		"good": false,
		"weight": 0.7,
	},
	{
		"id": "racing_school",
		"title": "Racing School Booking",
		"text": "A racing school books out — guaranteed satisfaction.",
		"color": Color(0.13, 0.83, 0.96),
		"good": true,
		"weight": 0.9,
	},
	{
		"id": "vip_guest",
		"title": "VIP Guest",
		"text": "A celebrity races today — every ticket sells double.",
		"color": Color(0.99, 0.75, 0.18),
		"good": true,
		"weight": 0.7,
	},
]


func _ready() -> void:
	# Trigger after the day flips, not on day_ended (so the modifier is
	# active during the *new* day's simulation).
	EventBus.day_changed.connect(_on_day_changed)


func get_event_by_id(id: String) -> Dictionary:
	for e: Dictionary in _EVENTS:
		if e.id == id:
			return e
	return {}


func _on_day_changed(_day: int) -> void:
	_reset_modifiers()
	if randf() < TRIGGER_CHANCE:
		_roll_event()


func _reset_modifiers() -> void:
	arrival_multiplier_today = 1.0
	maintenance_multiplier_today = 1.0
	revenue_multiplier_today = 1.0
	satisfaction_bonus_today = 0.0
	active_event = {}


func _roll_event() -> void:
	var total_weight := 0.0
	for e: Dictionary in _EVENTS:
		total_weight += float(e.weight)
	var r := randf() * total_weight
	var acc := 0.0
	var chosen: Dictionary = _EVENTS[0]
	for e: Dictionary in _EVENTS:
		acc += float(e.weight)
		if r <= acc:
			chosen = e
			break
	active_event = chosen
	_apply_event(chosen)
	EventBus.daily_event_triggered.emit(chosen)


func _apply_event(event: Dictionary) -> void:
	match event.id:
		"influencer":
			EconomyManager.add_revenue("Influencer tip", 500)
			GameManager.add_reputation(6)
		"bad_review":
			GameManager.add_reputation(-4)
			satisfaction_bonus_today = -0.10
		"sponsor_bonus":
			EconomyManager.add_revenue("Sponsor bonus", randi_range(1000, 3000))
		"equipment_failure":
			EconomyManager.log_expense("Equipment failure", randi_range(500, 1500))
		"heatwave":
			maintenance_multiplier_today = 1.5
		"local_holiday":
			arrival_multiplier_today = 1.6
		"power_outage":
			arrival_multiplier_today = 0.45
			revenue_multiplier_today = 0.85
		"tv_crew":
			EconomyManager.add_revenue("TV appearance", 300)
			GameManager.add_reputation(3)
		"competitor_strike":
			arrival_multiplier_today = 1.5
		"tax_audit":
			EconomyManager.log_expense("Tax audit", 1000)
		"racing_school":
			satisfaction_bonus_today = 0.15
		"vip_guest":
			revenue_multiplier_today = 2.0
