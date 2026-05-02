extends Node
##
## Persistence layer. Serialises every autoload's state plus the
## current Track's progression to a JSON file at user://savegame.json.
## Autosaves at the end of every day; manual save/load via the
## Settings popup (cog icon in the HUD top bar).
##
## Loading reloads the current scene; on the way back up, Track reads
## pending_track_state to start at the right tier with the right kart
## count. All other autoloads keep their state across scene reload.
##

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 2
const OFFLINE_MAX_HOURS: float = 12.0      # earnings cap window
const OFFLINE_EFFICIENCY: float = 0.50     # offline rate vs. live rate
const OFFLINE_MIN_SECONDS: float = 30.0    # below this, no welcome popup

# Set by main.gd / Track at scene-ready time so autosave knows what to capture.
var track: Node = null

# Held between load_game() and the freshly-reloaded scene. Track consumes
# this during its _ready() before building visuals.
var pending_track_state: Dictionary = {}

# Set true by load_game(); the HUD checks it on _ready to flash a
# confirmation and re-display the event tag if one was active.
var just_loaded: bool = false

# Populated by _compute_offline_progress on cold start. The welcome
# popup reads this on _ready and clears the .show flag once shown.
var offline_summary: Dictionary = {}


func _ready() -> void:
	EventBus.day_ended.connect(_on_day_ended_autosave)
	# Auto-load any existing save on cold start. This runs BEFORE the main
	# scene is constructed, so Track will pick up pending_track_state and
	# build the right tier from the start.
	if has_save_file():
		_cold_load()


func _notification(what: int) -> void:
	# Save the moment the OS is about to swap the app out so the
	# offline-progress timestamp is fresh when the player returns.
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := _serialize()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Could not open save file for writing.")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	EventBus.game_saved.emit(GameManager.day)
	return true


func load_game() -> bool:
	if not has_save_file():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		push_error("[SaveManager] Save file is not a valid JSON object.")
		return false
	_deserialize(parsed)
	just_loaded = true
	# Reload the scene so the Track and FacilityVisuals rebuild from
	# the freshly-restored autoload state. The new HUD reads
	# `just_loaded` and flashes a confirmation.
	get_tree().reload_current_scene()
	return true


func delete_save() -> bool:
	if not has_save_file():
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	dir.remove("savegame.json")
	return true


func has_pending_track_state() -> bool:
	return not pending_track_state.is_empty()


func consume_pending_track_state() -> Dictionary:
	var s := pending_track_state.duplicate()
	pending_track_state = {}
	return s


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------
func _serialize() -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"save_timestamp": Time.get_unix_time_from_system(),
		"economy": {
			"cash": EconomyManager.cash,
			"revenue_today": EconomyManager.revenue_today,
			"expenses_today": EconomyManager.expenses_today,
		},
		"game": {
			"day": GameManager.day,
			"reputation": GameManager.reputation,
			"ticket_price": GameManager.ticket_price,
			"day_time_left": GameManager._day_time_left,
		},
		"components": {
			"engine":  KartComponents.engine_level,
			"tires":   KartComponents.tires_level,
			"chassis": KartComponents.chassis_level,
			"suit":    KartComponents.suit_level,
			"brakes":  KartComponents.brakes_level,
		},
		"facilities": {
			"cafeteria":      Facilities.cafeteria_level,
			"pit_lane":       Facilities.pit_lane_level,
			"lounge":         Facilities.lounge_level,
			"merch_shop":     Facilities.merch_shop_level,
			"sponsor_boards": Facilities.sponsor_boards_level,
			"lighting":       Facilities.lighting_level,
			"grandstand":     Facilities.grandstand_level,
			"parking":        Facilities.parking_level,
			"marketing":      Facilities.marketing_level,
		},
		"staff": Staff.counts.duplicate(),
		"venues": Venues.to_save_dict(),
		"daily_events": {
			"arrival_multiplier_today":      DailyEvents.arrival_multiplier_today,
			"maintenance_multiplier_today":  DailyEvents.maintenance_multiplier_today,
			"revenue_multiplier_today":      DailyEvents.revenue_multiplier_today,
			"satisfaction_bonus_today":      DailyEvents.satisfaction_bonus_today,
			"active_event":                  DailyEvents.active_event.get("id", ""),
		},
	}
	if track != null:
		data["track"] = {
			"track_level": track.track_level,
			"kart_level":  track.kart_level,
			"kart_count":  track.karts.size(),
		}
	return data


func _deserialize(data: Dictionary) -> void:
	if data.has("economy"):
		var e: Dictionary = data["economy"]
		EconomyManager.cash = int(e.get("cash", EconomyManager.STARTING_CASH))
		EconomyManager.revenue_today = int(e.get("revenue_today", 0))
		EconomyManager.expenses_today = int(e.get("expenses_today", 0))
		EventBus.cash_changed.emit(EconomyManager.cash)
	if data.has("game"):
		var g: Dictionary = data["game"]
		GameManager.day = int(g.get("day", 1))
		GameManager.reputation = int(g.get("reputation", 0))
		GameManager.ticket_price = int(g.get("ticket_price", GameManager.TICKET_DEFAULT))
		GameManager._day_time_left = float(g.get("day_time_left", GameManager.DAY_LENGTH_SECONDS))
	if data.has("components"):
		var c: Dictionary = data["components"]
		KartComponents.engine_level  = int(c.get("engine", 1))
		KartComponents.tires_level   = int(c.get("tires", 1))
		KartComponents.chassis_level = int(c.get("chassis", 1))
		KartComponents.suit_level    = int(c.get("suit", 1))
		KartComponents.brakes_level  = int(c.get("brakes", 1))
	if data.has("facilities"):
		var f: Dictionary = data["facilities"]
		Facilities.cafeteria_level      = int(f.get("cafeteria", 0))
		Facilities.pit_lane_level       = int(f.get("pit_lane", 0))
		Facilities.lounge_level         = int(f.get("lounge", 0))
		Facilities.merch_shop_level     = int(f.get("merch_shop", 0))
		Facilities.sponsor_boards_level = int(f.get("sponsor_boards", 0))
		Facilities.lighting_level       = int(f.get("lighting", 0))
		Facilities.grandstand_level     = int(f.get("grandstand", 0))
		Facilities.parking_level        = int(f.get("parking", 0))
		Facilities.marketing_level      = int(f.get("marketing", 0))
	if data.has("staff"):
		var st: Dictionary = data["staff"]
		for role: String in Staff.role_names():
			Staff.counts[role] = int(st.get(role, 0))
	if data.has("venues"):
		Venues.from_save_dict(data["venues"] as Dictionary)
	if data.has("daily_events"):
		var de: Dictionary = data["daily_events"]
		DailyEvents.arrival_multiplier_today     = float(de.get("arrival_multiplier_today", 1.0))
		DailyEvents.maintenance_multiplier_today = float(de.get("maintenance_multiplier_today", 1.0))
		DailyEvents.revenue_multiplier_today     = float(de.get("revenue_multiplier_today", 1.0))
		DailyEvents.satisfaction_bonus_today     = float(de.get("satisfaction_bonus_today", 0.0))
		var saved_event_id: String = String(de.get("active_event", ""))
		if saved_event_id != "":
			DailyEvents.active_event = DailyEvents.get_event_by_id(saved_event_id)
		else:
			DailyEvents.active_event = {}
	if data.has("track"):
		pending_track_state = (data["track"] as Dictionary).duplicate()


# ---------------------------------------------------------------------------
# Autosave + cold-load + offline progress
# ---------------------------------------------------------------------------
func _on_day_ended_autosave(_summary: Dictionary) -> void:
	# Wait until all other day_ended handlers (maintenance, salaries, etc.)
	# have run before snapshotting state.
	call_deferred("save_game")


func _cold_load() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	_deserialize(data)
	# Rescue: a save with no karts and negative cash is a stuck state
	# (the venue can't earn, expenses keep accruing). Reset the player's
	# cash to the starting bankroll so they can climb out — Track's own
	# spawn safety net will refill the fleet.
	var saved_kart_count: int = int((data.get("track", {}) as Dictionary).get("kart_count", 0))
	if saved_kart_count <= 0 and EconomyManager.cash < EconomyManager.STARTING_CASH:
		EconomyManager.cash = EconomyManager.STARTING_CASH
		EventBus.cash_changed.emit(EconomyManager.cash)
		print("[SaveManager] Detected broken save (0 karts, low cash) — restored starting cash.")
	# Compute offline progress against the SAVED snapshot (the live Track
	# isn't in the scene yet — its _ready runs after this autoload).
	if data.has("save_timestamp") and data.has("track"):
		var elapsed: float = Time.get_unix_time_from_system() - float(data["save_timestamp"])
		if elapsed > OFFLINE_MIN_SECONDS:
			_compute_offline_progress(elapsed, data["track"] as Dictionary)


func _compute_offline_progress(elapsed_seconds: float, track_data: Dictionary) -> void:
	var raw_hours: float = elapsed_seconds / 3600.0
	var capped_hours: float = clampf(raw_hours, 0.0, OFFLINE_MAX_HOURS)
	var capped_seconds: float = capped_hours * 3600.0

	# Estimate the venue's earnings rate per real-time second.
	var passive_per_day: float = float(Facilities.total_daily_passive_income()) \
		+ float(Venues.total_daily_income())
	var kart_count: int = int(track_data.get("kart_count", 5))
	var kart_lvl: int = int(track_data.get("kart_level", 1))
	var track_lvl: int = int(track_data.get("track_level", 1))
	# Rough but sane: each kart turns over a customer every race; bigger
	# tier and higher fleet level means richer customers.
	var ticket_per_day: float = float(kart_count) * (40.0 + kart_lvl * 4.0 + track_lvl * 1.5)
	var per_day_total: float = passive_per_day + ticket_per_day
	var per_second_rate: float = per_day_total / GameManager.DAY_LENGTH_SECONDS
	var earnings: int = int(round(capped_seconds * per_second_rate * OFFLINE_EFFICIENCY))

	if earnings > 0:
		# Bump cash directly so the offline lump sum doesn't pollute the
		# day-revenue ledger or trigger per-event signal storms.
		EconomyManager.cash += earnings
		EventBus.cash_changed.emit(EconomyManager.cash)

	offline_summary = {
		"hours_away":   raw_hours,
		"hours_credited": capped_hours,
		"earnings":     earnings,
		"capped":       raw_hours > OFFLINE_MAX_HOURS,
		"show":         earnings > 0,
	}


func consume_offline_summary() -> Dictionary:
	var s := offline_summary.duplicate()
	offline_summary = {}
	return s


# ---------------------------------------------------------------------------
# Hard reset (used by the Settings popup's "Reset Game" button)
# ---------------------------------------------------------------------------
func reset_to_defaults() -> void:
	# Economy
	EconomyManager.cash = EconomyManager.STARTING_CASH
	EconomyManager.revenue_today = 0
	EconomyManager.expenses_today = 0
	EventBus.cash_changed.emit(EconomyManager.cash)
	# Game state
	GameManager.day = 1
	GameManager.reputation = 0
	GameManager.ticket_price = GameManager.TICKET_DEFAULT
	GameManager._day_time_left = GameManager.DAY_LENGTH_SECONDS
	# Components
	KartComponents.engine_level = 1
	KartComponents.tires_level = 1
	KartComponents.chassis_level = 1
	KartComponents.suit_level = 1
	KartComponents.brakes_level = 1
	# Facilities
	Facilities.cafeteria_level = 0
	Facilities.pit_lane_level = 0
	Facilities.lounge_level = 0
	Facilities.merch_shop_level = 0
	Facilities.sponsor_boards_level = 0
	Facilities.lighting_level = 0
	Facilities.grandstand_level = 0
	Facilities.parking_level = 0
	Facilities.marketing_level = 0
	# Staff
	for role: String in Staff.role_names():
		Staff.counts[role] = 0
	# Empire venues
	for vid: String in Venues.venue_ids():
		Venues.levels[vid] = 0
	# Daily events
	DailyEvents.arrival_multiplier_today = 1.0
	DailyEvents.maintenance_multiplier_today = 1.0
	DailyEvents.revenue_multiplier_today = 1.0
	DailyEvents.satisfaction_bonus_today = 0.0
	DailyEvents.active_event = {}
	# Save manager bookkeeping
	pending_track_state = {}
	just_loaded = false
	offline_summary = {}
