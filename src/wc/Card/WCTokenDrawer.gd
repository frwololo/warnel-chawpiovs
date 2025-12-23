extends TokenDrawer

# Variables and functions moved from src/core TokenDrawer modifications
var max_tokens: Dictionary = {}
var show_manipulation_buttons: bool = true

func set_max(token_name, max_value):
	max_tokens[token_name] = max_value
