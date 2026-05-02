# Kart Empire

A management / tycoon simulation built in **Godot 4 + GDScript** where you grow a single indoor kart track into a global motorsport empire.

> **Status:** All MVP phases (1-7) complete. Polish (Phase 8) is ongoing.
> The single home venue scales across 10 tiers (Backyard → F1) with a
> fixed pit straight, per-tier south-loop layouts, five kart-component
> subsystems, nine upgradable facilities, five staff roles and four
> empire-expansion satellite venues.

---

## Roadmap (MVP build order)

| Phase | Scope | Status |
| :---: | --- | :---: |
| 1 | Single playable track (10 tiers, F1-style layout) | Done |
| 2 | Economy (day clock, ticket price, costs, passive income) | Done |
| 3 | Customer simulation (queue, satisfaction, walkouts) | Done |
| 4 | Upgrades (track, facility, kart components) | Done |
| 5 | Staff (5 roles, tier-gated headcount caps) | Done |
| 6 | Expansion (4 satellite venues unlocked tier 4 / 6 / 8 / 10) | Done |
| 7 | Events (random daily modifiers) | Done |
| 8 | Polish (visuals, balance, mobile UX) | Ongoing |

---

## Project layout

```
Kart Empire/
├── project.godot          # engine config + autoloads
├── icon.svg
├── scenes/                # gameplay scenes
│   ├── main.tscn          # root scene (loaded on launch)
│   ├── track.tscn         # a single venue
│   └── kart.tscn          # PathFollow2D kart
├── scripts/               # gameplay scripts
│   ├── main.gd
│   ├── track.gd
│   └── kart.gd
├── ui/                    # HUD + future panels
│   ├── hud.tscn
│   └── hud.gd
├── systems/               # autoloaded singletons
│   ├── event_bus.gd       # global signals
│   ├── economy_manager.gd # cash + ledger
│   └── game_manager.gd    # day / reputation / customers
├── data/                  # (Phase 2+) resources for karts, upgrades, events
└── assets/                # (Phase 2+) art + audio
```

### Autoloads

Configured in `project.godot`:

- **EventBus** — pub/sub hub. All cross-system communication goes through here so managers stay decoupled.
- **EconomyManager** — single source of truth for cash. Use `add_revenue()`, `log_expense()`, `try_spend()`.
- **GameManager** — day counter, reputation, active customer count. Phase 2 will tick days from here.

---

## Setup

1. Install **Godot 4.3** (or newer 4.x) from [godotengine.org](https://godotengine.org/).
2. Clone this repo and open the folder in Godot:
   - *Project Manager* → **Import** → select `project.godot`.
3. Press **F5** (or the ▶ button). The first run will ask you to confirm `scenes/main.tscn` as the main scene — accept.

You should see:
- A neon oval track on a dark background with a checkered start/finish line.
- 5 colored karts circulating at slightly different speeds.
- A top status bar showing **Hometown Indoor — Cash €50.000 — Rep 0 — Day 1 — Customers 0**.
- A footer reading *"Kart Empire — Phase 1: Single playable track"*.

---

## Architecture notes

- **Decoupling via EventBus.** Systems never reference each other directly; they emit/listen via `EventBus`. The HUD doesn't know who changed the cash — it just reacts to `cash_changed`.
- **Procedural geometry for now.** The track curve is generated in `track.gd::_build_path()`; the visuals are drawn in `_draw()`. This keeps Phase 1 free of binary `.tres` curve files and easy to tweak.
- **`unique_name_in_owner` for HUD nodes.** The HUD looks up labels via `%CashLabel` etc. so renaming the visual hierarchy doesn't break the script.
- **Modular scenes.** Each venue is a `track.tscn` instance — Phase 6 (expansion) will instance multiple, each with its own economy parameters via `@export`.

---

## Coming up next (Phase 2 — Economy)

- Day clock in `GameManager` (configurable real-time → in-game day length).
- Ticket pricing slider in HUD (binding to a `track.ticket_price` export).
- Per-day maintenance cost = `kart_count × wear_multiplier`.
- Day-end summary popup driven by `EventBus.day_ended`.
- Automatic revenue when karts finish a "session" (timer-based for now, race-based in Phase 3).
