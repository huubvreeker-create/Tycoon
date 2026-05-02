extends Node
##
## Persistence layer. Serialises every autoload's state plus the
## current Track's progression to a JSON file at user://savegame.json.
## Autosaves at the end of every day; manual save/load via the HUD or
## F5 / F9 hotkeys.
##
## Loading reloads the current scene; on the way back up, Track reads
## pending_track_state to start at the right tier with the right kart
## count. All other autoloads keep their state across scene reload.
##

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 1

# Set by main.gd / Track at scene-ready time so autosave knows what to capture.
var track: Node = null

# Held between load_game() and the freshly-reloaded scene. Track consumes
# this during its _ready() before building visuals.
var pending_track_state: Dictionary = {}

# Set true by load_game(); the HUD checks it on _ready to flash a
# confirmation and re-display the event tag if one was active.
var just_loaded: bool = false


func _ready() -> void:
	# Defer autosave to the end of the frame so every other day_ended
	# handler (maintenance, salaries, day-end alert) has finished running
	# and the ledger captured by the save reflects the final state.
	EventBus.day_ended.connect(_on_day_ended_autosave)


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
		},
		"staff": Staff.counts.duplicate(),
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
	if data.has("staff"):
		var st: Dictionary = data["staff"]
		for role: String in Staff.role_names():
			Staff.counts[role] = int(st.get(role, 0))
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
# Autosave
# ---------------------------------------------------------------------------
func _on_day_ended_autosave(_summary: Dictionary) -> void:
	# Wait until all other day_ended handlers (maintenance, salaries, etc.)
	# have run before snapshotting state.
	call_deferred("save_game")
