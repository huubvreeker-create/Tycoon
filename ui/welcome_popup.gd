extends Control
##
## Welcome-back modal. Shown on cold-start when SaveManager has just
## awarded offline earnings. Displays time-away, the cash awarded,
## and a single COLLECT button to dismiss.
##

@onready var hours_label: Label    = %HoursLabel
@onready var earnings_label: Label = %EarningsLabel
@onready var sub_label: Label      = %SubLabel
@onready var cap_notice: Label     = %CapNotice
@onready var collect_button: Button = %CollectButton


func _ready() -> void:
	collect_button.pressed.connect(_dismiss)
	visible = false
	# Show on cold start if SaveManager has a populated offline summary.
	var summary := SaveManager.consume_offline_summary()
	if summary.get("show", false):
		_show(summary)


func _show(summary: Dictionary) -> void:
	hours_label.text = "You were away for %s" % _format_hours(float(summary.get("hours_credited", 0.0)))
	earnings_label.text = "+ %s" % _format_cash(int(summary.get("earnings", 0)))
	sub_label.text = "while your karts kept racing"
	if summary.get("capped", false):
		cap_notice.text = "(capped at %.0fh — keep playing for full payouts)" % SaveManager.OFFLINE_MAX_HOURS
		cap_notice.visible = true
	else:
		cap_notice.visible = false
	visible = true


func _dismiss() -> void:
	visible = false


func _format_hours(h: float) -> String:
	if h < 1.0:
		var minutes := int(round(h * 60.0))
		return "%d minute%s" % [minutes, "" if minutes == 1 else "s"]
	var whole := int(h)
	var minutes := int(round((h - float(whole)) * 60.0))
	if minutes == 0:
		return "%d hour%s" % [whole, "" if whole == 1 else "s"]
	return "%dh %dm" % [whole, minutes]


func _format_cash(amount: int) -> String:
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
	return "€" + out
