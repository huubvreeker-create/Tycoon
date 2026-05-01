extends Node2D
##
## Root scene controller. Owns the boot banner and any future
## global game-mode logic. The day clock lives in GameManager,
## customer simulation lives in Track.
##


func _ready() -> void:
	randomize()
	print("[Kart Empire] Booting…")
	print("  Cash:   €%d" % EconomyManager.cash)
	print("  Day:    %d"  % GameManager.day)
	print("  Ticket: €%d" % GameManager.ticket_price)
