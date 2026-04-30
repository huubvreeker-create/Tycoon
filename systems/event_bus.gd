extends Node
##
## Global signal hub. Decouples systems so they can communicate
## without direct references. Add signals here as features grow.
##

# --- Economy ----------------------------------------------------------------
signal cash_changed(new_amount: int)
signal expense_logged(label: String, amount: int)
signal revenue_logged(label: String, amount: int)

# --- Game state -------------------------------------------------------------
signal day_changed(day: int)
signal day_ended(summary: Dictionary)
signal reputation_changed(reputation: int)

# --- Customers --------------------------------------------------------------
signal customer_arrived(customer_id: int)
signal customer_left(customer_id: int, satisfaction: float)
signal customer_count_changed(active: int)

# --- Races ------------------------------------------------------------------
signal race_started(track_id: String, racers: int)
signal race_finished(track_id: String, payout: int)

# --- Karts / staff / upgrades (placeholders for later phases) ---------------
signal kart_purchased(kart_id: String)
signal kart_repaired(kart_id: String)
signal staff_hired(role: String)
signal upgrade_purchased(upgrade_id: String)

# --- World events -----------------------------------------------------------
signal world_event_triggered(event_id: String, payload: Dictionary)
