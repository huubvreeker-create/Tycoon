extends Control
##
## Upgrade popup — appears anchored to the screen position of the
## clicked 3D object. Two variants:
##   - "track":   shows track level + Upgrade Track button
##   - "kart":    shows kart level + Upgrade Karts button
## Closing happens by pressing X, Upgrade, or by clicking elsewhere.
##

signal closed

@onready var title: Label                = %Title
@onready var subtitle: Label             = %Subtitle
@onready var progress_bar: ProgressBar   = %Progress
@onready var stats_label: Label          = %StatsLabel
@onready var upgrade_button: Button      = %UpgradeButton
@onready var close_button: Button        = %CloseButton

var _track: Track
var _kind: String = ""


func _ready() -> void:
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	close_button.pressed.connect(_close)
	# Refresh on any state change so cost/level always look right.
	EventBus.cash_changed.connect(_refresh.unbind(1))
	EventBus.track_level_changed.connect(_refresh.unbind(2))
	EventBus.kart_level_changed.connect(_refresh.unbind(2))
	EventBus.track_tier_changed.connect(_refresh.unbind(2))
	EventBus.kart_tier_changed.connect(_refresh.unbind(1))
	EventBus.kart_count_changed.connect(_refresh.unbind(2))
	visible = false


## Show the popup for the given kind ("track" or "kart"), positioned
## near `screen_pos`. The host (Main) keeps the popup on-screen.
func open_for(kind: String, track_ref: Track, screen_pos: Vector2) -> void:
	_kind = kind
	_track = track_ref
	_refresh()
	visible = true
	# Position the popup so it doesn't run off the edges. The popup
	# is sized via custom_minimum_size; use the viewport as bounds.
	var vp := get_viewport_rect().size
	var popup_size := custom_minimum_size
	if popup_size == Vector2.ZERO:
		popup_size = Vector2(280, 200)
	var x := clamp(screen_pos.x - popup_size.x * 0.5, 16, vp.x - popup_size.x - 16)
	var y := clamp(screen_pos.y - popup_size.y - 24, 100, vp.y - popup_size.y - 16)
	position = Vector2(x, y)


func _close() -> void:
	visible = false
	closed.emit()


func _refresh() -> void:
	if not visible or _track == null:
		return
	if _kind == "track":
		_refresh_track()
	elif _kind == "kart":
		_refresh_kart()


func _refresh_track() -> void:
	var tier: int = _track.track_tier()
	var lvl_in_tier: int = _track.track_level_in_tier()
	title.text = "Track  —  %s" % _track.venue_name()
	subtitle.text = "Tier %d   Lvl %d / %d" % [
		tier, _track.track_level, _track.MAX_LEVEL
	]
	progress_bar.max_value = float(_track.LEVELS_PER_TIER)
	progress_bar.value = float(lvl_in_tier)
	stats_label.text = "Capacity   %d karts\nRace duration   %.1f s" % [
		_track.kart_capacity(),
		_track.TIER_RACE_DURATION[tier],
	]
	if _track.can_upgrade_track():
		var cost: int = _track.track_upgrade_cost()
		upgrade_button.text = "Upgrade Track   €%s" % _format_cash(cost)
		upgrade_button.disabled = EconomyManager.cash < cost
	else:
		upgrade_button.text = "MAX LEVEL"
		upgrade_button.disabled = true


func _refresh_kart() -> void:
	var tier: int = _track.kart_tier()
	var lvl_in_tier: int = _track.kart_level_in_tier()
	title.text = "Kart Fleet"
	subtitle.text = "Tier %d   Lvl %d / %d" % [
		tier, _track.kart_level, _track.MAX_LEVEL
	]
	progress_bar.max_value = float(_track.LEVELS_PER_TIER)
	progress_bar.value = float(lvl_in_tier)
	stats_label.text = "Karts owned   %d / %d\nNext tier visual change at Lvl %d" % [
		_track.karts.size(), _track.kart_capacity(),
		((tier) * _track.LEVELS_PER_TIER) + 1
	]
	if _track.can_upgrade_karts():
		var cost: int = _track.kart_upgrade_cost()
		upgrade_button.text = "Upgrade Karts   €%s" % _format_cash(cost)
		upgrade_button.disabled = EconomyManager.cash < cost
	else:
		upgrade_button.text = "MAX LEVEL"
		upgrade_button.disabled = true


func _on_upgrade_pressed() -> void:
	if _track == null:
		return
	if _kind == "track":
		_track.upgrade_track()
	elif _kind == "kart":
		_track.upgrade_karts()
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
