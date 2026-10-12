class_name StumbleConfig
extends MoveConfig

# The original's TdMove_Stumble and TdMove_StumbleHard defaults: nothing of
# their own beyond what the moves declare. [ME:CONFIRMED decompile] No look
# constraint; move and look input are ignored for the whole stumble.

func _init() -> void:
	allows_turn = false
