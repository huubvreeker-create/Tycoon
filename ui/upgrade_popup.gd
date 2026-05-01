extends PanelContainer
##
## Right-side upgrade panel. Three tabs: TRACK | KART | FACILITIES.
## Clicking a kart opens the KART tab; clicking the track opens TRACK.
## The FACILITIES tab is always accessible from any starting tab.
##
## Rows are built dynamically; only visible rows are drawn.
##

@onready var title_label: Label        = %TitleLabel
@onready var close_button: Button      = %CloseButton
@onready var tab_track: Button         = %TabTrack
@onready var tab_kart: Button          = %TabKart
@onready var tab_facilities: Button    = %TabFacilities
@onready var tab_staff: Button         = %TabStaff
@onready var upgrade_list: VBoxContainer = %UpgradeList

var _track: Track = null
var _active_tab: String = "track"  # "track" | "kart" | "facilities"

# Cached style boxes loaded once.
var _style_active: StyleBoxFlat
var _style_inactive: StyleBoxFlat
var _style_row: StyleBoxFlat
var _style_progress_bg: StyleBoxFlat
var _style_progress_fill: StyleBoxFlat


func _ready() -> void:
	_build_styles()
	close_button.pressed.connect(func(): visible = false)
	tab_track.pressed.connect(func(): _switch_tab("track"))
	tab_kart.pressed.connect(func(): _switch_tab("kart"))
	tab_facilities.pressed.connect(func(): _switch_tab("facilities"))
	tab_staff.pressed.connect(func(): _switch_tab("staff"))

	EventBus.cash_changed.connect(_refresh.unbind(1))
	EventBus.track_level_changed.connect(_refresh.unbind(2))
	EventBus.kart_level_changed.connect(_refresh.unbind(2))
	EventBus.track_tier_changed.connect(_refresh.unbind(2))
	EventBus.kart_tier_changed.connect(_refresh.unbind(1))
	EventBus.kart_count_changed.connect(_refresh.unbind(2))
	EventBus.kart_component_upgraded.connect(_refresh.unbind(2))
	EventBus.facility_upgraded.connect(_refresh.unbind(2))
	EventBus.staff_hired.connect(_refresh.unbind(1))
	visible = false


func open_for(kind: String, track_ref: Track) -> void:
	_track = track_ref
	var tab := "kart" if kind == "kart" else "track"
	visible = true
	_switch_tab(tab)


func _switch_tab(tab: String) -> void:
	_active_tab = tab
	_update_tab_styles()
	_build_rows()


func _update_tab_styles() -> void:
	for entry: Array in [
		[tab_track, "track"],
		[tab_kart, "kart"],
		[tab_facilities, "facilities"],
		[tab_staff, "staff"],
	]:
		var btn: Button = entry[0]
		var is_active: bool = (_active_tab == entry[1])
		var sb: StyleBoxFlat = _style_active if is_active else _style_inactive
		btn.add_theme_stylebox_override("normal",  sb)
		btn.add_theme_stylebox_override("hover",   sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus",   sb)


func _refresh() -> void:
	if visible:
		_build_rows()


func _build_rows() -> void:
	if _track == null:
		return
	# Clear existing rows.
	for child in upgrade_list.get_children():
		child.queue_free()

	match _active_tab:
		"track":
			title_label.text = "Track Upgrades"
			_add_track_rows()
		"kart":
			title_label.text = "Kart Upgrades"
			_add_kart_rows()
		"facilities":
			title_label.text = "Facilities"
			_add_facility_rows()
		"staff":
			title_label.text = "Staff"
			_add_staff_rows()


# ---------------------------------------------------------------------------
# TRACK TAB
# ---------------------------------------------------------------------------
func _add_track_rows() -> void:
	var tier := _track.track_tier()
	var lvl  := _track.track_level

	_add_section_header("TRACK LEVEL  —  %s" % _track.venue_name())
	_add_upgrade_row(
		Color(0.13, 0.83, 0.96),
		"Track Level",
		"Lvl %d / %d  (Tier %d)" % [lvl, _track.MAX_LEVEL, tier],
		float(_track.track_level_in_tier()),
		float(_track.LEVELS_PER_TIER),
		"Capacity %d karts  |  Race %.1fs" % [
			_track.kart_capacity(),
			_track.TIER_RACE_DURATION[tier]
		],
		_track.can_upgrade_track(),
		_track.track_upgrade_cost(),
		func():
			_track.upgrade_track()
			_build_rows()
	)

	_add_section_header("BUY KARTS")
	var can_buy := _track.can_buy_kart()
	var kart_cost := _track.buy_kart_cost()
	_add_buy_row(
		Color(0.55, 0.92, 0.38),
		"Buy Kart",
		"%d / %d karts" % [_track.karts.size(), _track.kart_capacity()],
		can_buy,
		kart_cost,
		func():
			_track.buy_kart()
			_build_rows()
	)


# ---------------------------------------------------------------------------
# KART TAB
# ---------------------------------------------------------------------------
func _add_kart_rows() -> void:
	var k_tier := _track.kart_tier()
	var k_lvl  := _track.kart_level

	_add_section_header("FLEET LEVEL")
	_add_upgrade_row(
		Color(0.96, 0.27, 0.36),
		"Kart Fleet",
		"Lvl %d / %d  (Tier %d)" % [k_lvl, _track.MAX_LEVEL, k_tier],
		float(_track.kart_level_in_tier()),
		float(_track.LEVELS_PER_TIER),
		"All karts upgraded simultaneously",
		_track.can_upgrade_karts(),
		_track.kart_upgrade_cost(),
		func():
			_track.upgrade_karts()
			_build_rows()
	)

	_add_section_header("COMPONENTS")
	var colors := {
		"engine":  Color(0.99, 0.75, 0.18),
		"tires":   Color(0.55, 0.92, 0.38),
		"chassis": Color(0.40, 0.65, 1.00),
		"suit":    Color(0.86, 0.42, 0.98),
		"brakes":  Color(0.13, 0.83, 0.96),
	}
	for comp: String in KartComponents.component_names():
		var lv := KartComponents.get_level(comp)
		_add_upgrade_row(
			colors.get(comp, Color.WHITE),
			KartComponents.display_name(comp),
			"Lvl %d / %d" % [lv, KartComponents.MAX_LEVEL],
			float((lv - 1) % 10 + 1),
			10.0,
			KartComponents.effect_text(comp),
			KartComponents.can_upgrade(comp),
			KartComponents.upgrade_cost(comp),
			func(c := comp):
				KartComponents.upgrade(c)
				_build_rows()
		)


# ---------------------------------------------------------------------------
# FACILITIES TAB
# ---------------------------------------------------------------------------
func _add_facility_rows() -> void:
	_add_section_header("VENUE FACILITIES")
	var colors := {
		"cafeteria":      Color(0.99, 0.75, 0.18),
		"pit_lane":       Color(0.13, 0.83, 0.96),
		"lounge":         Color(0.86, 0.42, 0.98),
		"merch_shop":     Color(0.55, 0.92, 0.38),
		"sponsor_boards": Color(1.00, 0.55, 0.20),
		"lighting":       Color(0.95, 0.95, 0.60),
	}
	for fac: String in Facilities.facility_names():
		var lv := Facilities.get_level(fac)
		var label := "Lvl %d / %d" % [lv, Facilities.MAX_LEVEL]
		if lv == 0:
			label = "NOT BUILT"
		_add_upgrade_row(
			colors.get(fac, Color.WHITE),
			Facilities.display_name(fac),
			label,
			float(lv),
			float(Facilities.MAX_LEVEL),
			Facilities.effect_text(fac),
			Facilities.can_upgrade(fac),
			Facilities.upgrade_cost(fac),
			func(f := fac):
				Facilities.upgrade(f)
				_build_rows()
		)


# ---------------------------------------------------------------------------
# STAFF TAB
# ---------------------------------------------------------------------------
func _add_staff_rows() -> void:
	_add_section_header("PAYROLL  —  €%d / day" % Staff.total_daily_salaries())
	var colors := {
		"mechanic":     Color(0.13, 0.83, 0.96),
		"receptionist": Color(0.99, 0.75, 0.18),
		"marketing":    Color(0.86, 0.42, 0.98),
		"instructor":   Color(0.55, 0.92, 0.38),
		"janitor":      Color(0.96, 0.27, 0.36),
	}
	for role: String in Staff.role_names():
		var n := Staff.get_count(role)
		var on_hire: Callable = _make_hire_callable(role)
		_add_upgrade_row(
			colors.get(role, Color.WHITE),
			Staff.display_name(role),
			"%d / %d  hired" % [n, Staff.MAX_PER_ROLE],
			float(n),
			float(Staff.MAX_PER_ROLE),
			"%s\n€%d/day each  —  %s" % [
				Staff.description(role),
				Staff.daily_salary(role),
				Staff.effect_text(role),
			],
			Staff.can_hire(role),
			Staff.hire_cost(role),
			on_hire,
			"Hire",
			"FULL TEAM"
		)


func _make_hire_callable(role: String) -> Callable:
	return func():
		Staff.hire(role)
		_build_rows()


# ---------------------------------------------------------------------------
# Row helpers
# ---------------------------------------------------------------------------
func _add_section_header(text: String) -> void:
	var label := Label.new()
	label.text = "  " + text
	label.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85, 0.85))
	label.add_theme_font_size_override("font_size", 11)
	upgrade_list.add_child(label)


func _add_upgrade_row(
		icon_color: Color,
		name_text: String,
		level_text: String,
		bar_value: float,
		bar_max: float,
		detail_text: String,
		can_upg: bool,
		cost: int,
		on_press: Callable,
		verb: String = "Upgrade",
		max_label: String = "MAX LEVEL"
) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_row)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Top row: color dot + name + level label
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vbox.add_child(top)

	var dot := ColorRect.new()
	dot.color = icon_color
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dot)

	var name_lbl := Label.new()
	name_lbl.text = name_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1, 1))
	top.add_child(name_lbl)

	var lvl_lbl := Label.new()
	lvl_lbl.text = level_text
	lvl_lbl.add_theme_font_size_override("font_size", 11)
	lvl_lbl.add_theme_color_override("font_color", Color(0.60, 0.70, 0.90, 0.85))
	top.add_child(lvl_lbl)

	# Progress bar
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 6)
	bar.max_value = bar_max
	bar.value = bar_value
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style_progress_bg)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = icon_color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	vbox.add_child(bar)

	# Detail text
	if detail_text != "":
		var detail := Label.new()
		detail.text = detail_text
		detail.add_theme_font_size_override("font_size", 11)
		detail.add_theme_color_override("font_color", Color(0.65, 0.75, 0.90, 0.80))
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(detail)

	# Upgrade button
	var btn := Button.new()
	if not can_upg:
		btn.text = max_label
		btn.disabled = true
	elif EconomyManager.cash < cost:
		btn.text = "%s  —  €%s" % [verb, _fmt(cost)]
		btn.disabled = true
	else:
		btn.text = "%s  —  €%s" % [verb, _fmt(cost)]
		btn.disabled = false
		btn.pressed.connect(on_press)
	vbox.add_child(btn)

	upgrade_list.add_child(panel)


func _add_buy_row(
		icon_color: Color,
		name_text: String,
		status_text: String,
		can_buy: bool,
		cost: int,
		on_press: Callable
) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_row)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vbox.add_child(top)

	var dot := ColorRect.new()
	dot.color = icon_color
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dot)

	var name_lbl := Label.new()
	name_lbl.text = name_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1, 1))
	top.add_child(name_lbl)

	var status := Label.new()
	status.text = status_text
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color(0.60, 0.70, 0.90, 0.85))
	top.add_child(status)

	var btn := Button.new()
	if not can_buy:
		btn.text = "Fleet at capacity"
		btn.disabled = true
	elif EconomyManager.cash < cost:
		btn.text = "Buy Kart  —  €%s" % _fmt(cost)
		btn.disabled = true
	else:
		btn.text = "Buy Kart  —  €%s" % _fmt(cost)
		btn.disabled = false
		btn.pressed.connect(on_press)
	vbox.add_child(btn)

	upgrade_list.add_child(panel)


# ---------------------------------------------------------------------------
# Style cache
# ---------------------------------------------------------------------------
func _build_styles() -> void:
	_style_active = StyleBoxFlat.new()
	_style_active.bg_color = Color(0.13, 0.83, 0.96, 0.18)
	_style_active.border_width_bottom = 2
	_style_active.border_color = Color(0.13, 0.83, 0.96, 1)
	_style_active.content_margin_left = 12
	_style_active.content_margin_top = 6
	_style_active.content_margin_right = 12
	_style_active.content_margin_bottom = 6

	_style_inactive = StyleBoxFlat.new()
	_style_inactive.bg_color = Color(0.08, 0.09, 0.14, 0)
	_style_inactive.border_width_bottom = 1
	_style_inactive.border_color = Color(0.13, 0.83, 0.96, 0.20)
	_style_inactive.content_margin_left = 12
	_style_inactive.content_margin_top = 6
	_style_inactive.content_margin_right = 12
	_style_inactive.content_margin_bottom = 6

	_style_row = StyleBoxFlat.new()
	_style_row.bg_color = Color(0.09, 0.10, 0.16, 0.80)
	_style_row.corner_radius_top_left = 4
	_style_row.corner_radius_top_right = 4
	_style_row.corner_radius_bottom_left = 4
	_style_row.corner_radius_bottom_right = 4
	_style_row.content_margin_left = 10
	_style_row.content_margin_top = 8
	_style_row.content_margin_right = 10
	_style_row.content_margin_bottom = 8

	_style_progress_bg = StyleBoxFlat.new()
	_style_progress_bg.bg_color = Color(0.10, 0.12, 0.18, 1)
	_style_progress_bg.corner_radius_top_left = 2
	_style_progress_bg.corner_radius_top_right = 2
	_style_progress_bg.corner_radius_bottom_left = 2
	_style_progress_bg.corner_radius_bottom_right = 2


func _fmt(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "." + out
	if amount < 0:
		out = "-" + out
	return out
