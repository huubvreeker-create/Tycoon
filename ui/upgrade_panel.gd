extends PanelContainer
##
## Right-side upgrade panel. Holds three actions:
##   - Upgrade Track (tier 1 → 4)
##   - Upgrade Karts (tier 1 → 4)
##   - Buy Kart      (until track capacity is reached)
##
## Reads/writes purely through the Track API + EconomyManager so the
## panel can be reused for other venues in Phase 6.
##

@export var track_path: NodePath

@onready var track_tier_label: Label   = %TrackTierLabel
@onready var track_button: Button      = %UpgradeTrackButton
@onready var kart_tier_label: Label    = %KartTierLabel
@onready var kart_button: Button       = %UpgradeKartsButton
@onready var fleet_label: Label        = %FleetLabel
@onready var buy_button: Button        = %BuyKartButton
@onready var hint_label: Label         = %HintLabel

var _track: Track


func _ready() -> void:
	_track = get_node_or_null(track_path) as Track
	if _track == null:
		push_warning("UpgradePanel: track_path not set or not a Track")
		return
	track_button.pressed.connect(_on_upgrade_track_pressed)
	kart_button.pressed.connect(_on_upgrade_karts_pressed)
	buy_button.pressed.connect(_on_buy_kart_pressed)
	EventBus.cash_changed.connect(_on_state_changed.unbind(1))
	EventBus.track_tier_changed.connect(_on_state_changed.unbind(2))
	EventBus.kart_tier_changed.connect(_on_state_changed.unbind(1))
	EventBus.kart_count_changed.connect(_on_state_changed.unbind(2))
	_refresh()


func _on_state_changed() -> void:
	_refresh()


func _refresh() -> void:
	if _track == null:
		return
	# Track row.
	track_tier_label.text = "Track   Tier %d  —  %s" % [
		_track.track_tier,
		_track.venue_name(),
	]
	if _track.can_upgrade_track():
		var cost := _track.track_upgrade_cost()
		track_button.text = "Upgrade Track   €%s" % _format_cash(cost)
		track_button.disabled = EconomyManager.cash < cost
	else:
		track_button.text = "MAX TIER"
		track_button.disabled = true

	# Kart row.
	kart_tier_label.text = "Karts   Tier %d" % _track.kart_tier
	if _track.can_upgrade_karts():
		var k_cost := _track.kart_upgrade_cost()
		kart_button.text = "Upgrade Karts   €%s" % _format_cash(k_cost)
		kart_button.disabled = EconomyManager.cash < k_cost
	else:
		kart_button.text = "MAX TIER"
		kart_button.disabled = true

	# Fleet row.
	fleet_label.text = "Fleet   %d / %d karts" % [
		_track.karts.size(),
		_track.kart_capacity(),
	]
	if _track.can_buy_kart():
		var b_cost := _track.buy_kart_cost()
		buy_button.text = "Buy Kart   €%s" % _format_cash(b_cost)
		buy_button.disabled = EconomyManager.cash < b_cost
		hint_label.text = ""
	else:
		buy_button.text = "Capacity full"
		buy_button.disabled = true
		hint_label.text = "Upgrade the track to expand the fleet."


func _on_upgrade_track_pressed() -> void:
	_track.upgrade_track()
	_refresh()


func _on_upgrade_karts_pressed() -> void:
	_track.upgrade_karts()
	_refresh()


func _on_buy_kart_pressed() -> void:
	_track.buy_kart()
	_refresh()


func _format_cash(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "." + out
	return out
