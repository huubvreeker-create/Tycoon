extends Node
##
## Global signal hub. Decouples systems so they can communicate
## without direct references. Add signals here as features grow.
##

# --- Economy ----------------------------------------------------------------
signal cash_changed(new_amount: int)
signal expense_logged(label: String, amount: int)
signal revenue_logged(label: String, amount: int)
signal ticket_price_changed(price: int)

# --- Game state -------------------------------------------------------------
signal day_changed(day: int)
signal day_progress_changed(progress: float)  # 0.0 .. 1.0
signal day_ended(summary: Dictionary)
signal reputation_changed(reputation: int)

# --- Customers --------------------------------------------------------------
signal customer_arrived(customer_id: int)
signal customer_left(customer_id: int, satisfaction: float)
signal customer_count_changed(active: int)
signal queue_changed(queue_size: int)

# --- Races ------------------------------------------------------------------
signal race_started(track_id: String, racers: int)
signal race_finished(track_id: String, payout: int)

# --- Karts / track upgrades ------------------------------------------------
signal kart_purchased(kart_id: String)
signal kart_count_changed(count: int, capacity: int)
signal kart_tier_changed(tier: int)
signal track_tier_changed(tier: int, venue_name: String)
# Fine-grained level changes (1..100). Tier signals only fire on
# tier rollovers; level signals fire on every upgrade.
signal track_level_changed(level: int, tier: int)
signal kart_level_changed(level: int, tier: int)

# --- Kart components --------------------------------------------------------
signal kart_component_upgraded(component: String, new_level: int)

# --- Facilities -------------------------------------------------------------
signal facility_upgraded(facility: String, new_level: int)

# --- Daily events -----------------------------------------------------------
signal daily_event_triggered(event: Dictionary)

# --- Save / load ------------------------------------------------------------
signal game_saved(day: int)
signal game_loaded(day: int)

# --- Staff / world events (future) -----------------------------------------
signal staff_hired(role: String)
signal world_event_triggered(event_id: String, payload: Dictionary)
