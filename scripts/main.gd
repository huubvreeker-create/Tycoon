extends Node2D
##
## Root scene controller. Phase 1 only hosts the Track + HUD and
## prints a startup banner. Later phases will own the day clock,
## customer spawner and event scheduler from here.
##


func _ready() -> void:
	randomize()
	print("[Kart Empire] Phase 1 prototype booting…")
	print("  Cash: €%d" % EconomyManager.cash)
	print("  Day:  %d"  % GameManager.day)
