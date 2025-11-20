extends Node

var coins: int = 0
signal coins_changed(new_value: int)

func add_coins(amount: int) -> void:
	coins += amount
	print("Coins:", coins)
	emit_signal("coins_changed", coins)
	
