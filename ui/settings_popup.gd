extends Control
##
## Mobile settings drawer. Save / Load / Delete-save buttons + a small
## status label. Tapping outside the panel (on the dim background) or
## the Close button hides it.
##

@onready var save_button: Button         = %SaveButton
@onready var load_button: Button         = %LoadButton
@onready var delete_button: Button       = %DeleteSaveButton
@onready var close_button: Button        = %CloseButton
@onready var dim_button: Button          = %DimButton
@onready var status_label: Label         = %StatusLabel


func _ready() -> void:
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	delete_button.pressed.connect(_on_delete)
	close_button.pressed.connect(close)
	dim_button.pressed.connect(close)
	EventBus.game_saved.connect(_on_saved_signal)
	visible = false


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	var has_save := SaveManager.has_save_file()
	load_button.disabled = not has_save
	delete_button.disabled = not has_save
	if has_save:
		status_label.text = "Save file present"
		status_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.38))
	else:
		status_label.text = "No save yet"
		status_label.add_theme_color_override("font_color", Color(0.70, 0.78, 0.92))


func _on_save() -> void:
	if SaveManager.save_game():
		status_label.text = "Saved at Day %d" % GameManager.day
		status_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.38))
		_refresh()
	else:
		status_label.text = "Save failed"
		status_label.add_theme_color_override("font_color", Color(0.96, 0.27, 0.36))


func _on_load() -> void:
	if not SaveManager.load_game():
		status_label.text = "Load failed"
		status_label.add_theme_color_override("font_color", Color(0.96, 0.27, 0.36))
	# On success the scene reloads, so this Control instance is freed.


func _on_delete() -> void:
	if SaveManager.delete_save():
		status_label.text = "Save deleted"
		status_label.add_theme_color_override("font_color", Color(0.99, 0.75, 0.18))
		_refresh()


func _on_saved_signal(_day: int) -> void:
	_refresh()
