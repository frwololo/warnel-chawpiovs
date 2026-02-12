# This script handles interactions with the token drawer on a Card.
class_name TokenDrawer
extends Node2D

# Used to add new token instances to cards. We have to add the consts
# together before passing to the preload, or the parser complains
const _TOKEN_SCENE_FILE = CFConst.PATH_CORE + "Token.tscn"
const _TOKEN_SCENE = preload(_TOKEN_SCENE_FILE)

# A flag on whether the token drawer is currently open
var is_drawer_open := false setget set_is_drawer_open

onready var _tween : Tween = $Tween
# Stores a reference to the Card that is hosting this node
onready var owner_card = get_parent().get_parent()

#sets a max limit for some tokens
var max_tokens: Dictionary = {}
var _is_horizontal:= false
var show_manipulation_buttons:= true


func _ready() -> void:
	$Drawer/Area2D/CollisionShape2D.shape = \
			$Drawer/Area2D/CollisionShape2D.shape.duplicate()
	# warning-ignore:return_value_discarded
	$Drawer/VBoxContainer.connect("sort_children", self,
			"_on_VBoxContainer_sort_children")


func _process(_delta: float) -> void:
	
	# Every process tick, it will ensure the collsion shape for the
	# drawer is adjusted to its current size
	if cfc.NMAP.has('board') and owner_card.get_parent() == cfc.NMAP.board:
		$Drawer/Area2D.position = $Drawer.rect_size/2
		var shape: RectangleShape2D = $Drawer/Area2D/CollisionShape2D.shape
		# We're extending the area of the drawer a bit, to try and avoid it
		# glitching when moving from card to drawer and back
		shape.extents = $Drawer.rect_size/2 + Vector2(10,0)
		

# Setter for is_drawer_open
# Simply calls token_drawer()
func set_is_drawer_open(value: bool, forced:bool = false) -> void:
	if forced or (is_drawer_open != value):
		token_drawer(value, forced)


# Reveals or Hides the token drawer
#
# The drawer will not appear while another animation is ongoing
# and it will appear only while the card is on the board.
func token_drawer(requested_state := true, forced: bool = false) -> void:
	# I use these vars to avoid writing it all the time and to improve readability

	#TODO this is to prevent
	#the drawer from opening while an animation is ongoing
	#but I feel like this is a hack
	if cfc.is_modal_event_ongoing() and requested_state and not forced:
		return


	var td := $Drawer
	
	#temp variables to accomodate for horizontal mode
	var x = owner_card.card_size.x
	var y = td.rect_position.y
	if (_is_horizontal):
		x = 0
		y = td.rect_position.x


		
	# We want to keep the drawer closed during the flip and movement
	if forced or (not _tween.is_active() and \
			not owner_card._flip_tween.is_active() and \
			not owner_card._tween.is_active()):
		# We don't open the drawer if we don't have any tokens at all
		if requested_state == true and $Drawer/VBoxContainer.get_child_count():
			# To avoid tween deadlocks
			# warning-ignore:return_value_discarded
			_tween.remove_all()
			# warning-ignore:return_value_discarded
			_tween.interpolate_property(
					td,'rect_position', td.rect_position,
					Vector2(x,y),
					0.3, Tween.TRANS_ELASTIC, Tween.EASE_OUT)
			# We make all tokens display names
			for token in $Drawer/VBoxContainer.get_children():
				token.expand()
			# Normally the drawer is invisible. We make it visible now
			$Drawer.self_modulate.a = 1
			is_drawer_open = true
			# warning-ignore:return_value_discarded
			_tween.start()
			# We need to make our tokens appear on top of other cards on the table
			z_index = CFConst.Z_INDEX_BOARD_CARDS_ABOVE
		else:
			var x_modifier = 0
			var y_modifier = 0
			
			if (_is_horizontal):
				y_modifier = 35
			else:
				x_modifier = -35
			# warning-ignore:return_value_discarded
			_tween.remove_all()
			if forced:
				td.rect_position = Vector2(x + x_modifier, y + y_modifier )
			else:
				# warning-ignore:return_value_discarded
				_tween.interpolate_property(
						td,'rect_position', td.rect_position,
						Vector2(x + x_modifier,
						y + y_modifier ),
						0.2, Tween.TRANS_ELASTIC, Tween.EASE_IN)
				# warning-ignore:return_value_discarded
				_tween.start()
				# We want to consider the drawer closed
				# only when the animation finished
				# Otherwise it might start to open immediately again
				yield(_tween, "tween_all_completed")
				# When it's closed, we hide token names
			for token in $Drawer/VBoxContainer.get_children():
				token.retract()
			$Drawer.self_modulate.a = 0
			is_drawer_open = false
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL


# Adds a token to the card
#
# If the token of that name doesn't exist, it creates it according to the config.
#
# If the amount of existing tokens of that type drops to 0 or lower,
# the token node is also removed.
func mod_token(
			token_name : String,
			mod := 1,
			set_to_mod := false,
			check := false,
			tags := ["Manual"]) -> int:
	var retcode : int
	
	#unallowed token names
	if !token_name:
		return CFConst.ReturnCode.FAILED
	if token_name in ["_", "__"]:
		return CFConst.ReturnCode.FAILED
	
	if CFConst.TOKENS_ONLY_ON_BOARD and !"forced" in tags:
		var parent = owner_card.get_parent()
		if parent != cfc.NMAP.board:
			var is_exception = false
			var parent_name:String = parent.name.to_lower()
			for exception in CFConst.TOKENS_ONLY_ON_BOARD_EXCEPTIONS:
				if parent_name.begins_with(exception):
					is_exception = true
					break
			if !is_exception:
				return CFConst.ReturnCode.FAILED
	
	#some properties prevent adding certain tokens
	if mod > 0:
		var prevention_properties = CFConst.TOKENS_INCREASE_PREVENTION_PROPERTIES.get(token_name, [])
		for property in prevention_properties:
			if owner_card.get_property(property, 0, true):
				return CFConst.ReturnCode.FAILED
	
	var token : Token = get_all_tokens().get(token_name, null)
	# If the token does not exist in the card, we add its node
	# and set it to 1
	if not token and mod > 0:
		token = _TOKEN_SCENE.instance()
		token.setup(token_name, self)
		$Drawer/VBoxContainer.add_child(token)
	# If the token node of this name has already been added to the card
	# We just increment it by 1
	if not token and mod == 0:
		retcode = CFConst.ReturnCode.OK
	elif not token and mod < 0:
		retcode = CFConst.ReturnCode.FAILED
	# For cost dry-runs, we don't want to modify the tokens at all.
	# Just check if we could.
	elif check:
		# For a  cost dry run, we can only return FAILED
		# when removing tokens or when trying to add tokens when a max is set and we ago above that max
		if (set_to_mod):
			if (mod <0):
				retcode = CFConst.ReturnCode.FAILED
			else:
				retcode = CFConst.ReturnCode.CHANGED
		else:		
			if mod < 0:
				# If the current tokens are equal or higher, then we can
				# remove the requested amount and therefore return CHANGED.
				if (token.count + mod >= 0):
					retcode = CFConst.ReturnCode.CHANGED
				# If we cannot remove the full amount requested
				# we return FAILED
				else:
					retcode = CFConst.ReturnCode.FAILED
			else:
				retcode = CFConst.ReturnCode.CHANGED
				#fail if we can't add the full amount requested
				if max_tokens.has(token_name) and ((token.count + mod > max_tokens[token_name])):
					retcode = CFConst.ReturnCode.FAILED
					
	else:
		cfc.flush_cache()
		var prev_value = token.count
		# The set_to_mod value means that we want to set the tokens to the
		# exact value specified
		if set_to_mod:
			var value = mod
			if max_tokens.has(token_name):
				value = min(value, max_tokens[token_name])
			token.count = value
		else:
			token.count += mod
			if max_tokens.has(token_name) and token.count > max_tokens[token_name]:
				token.count = max_tokens[token_name]
		# We store the count in a new variable, to be able to use it
		# in the signal even after the token is deinstanced.
		var new_value = token.count
		if token.count == 0:
			token.queue_free()
	# if the drawer has already been opened, we need to make sure
	# the new token name will also appear
		elif is_drawer_open:
			token.expand()
		retcode = CFConst.ReturnCode.CHANGED
		scripting_bus.emit_signal(
				"card_token_modified",
				owner_card,
				{SP.TRIGGER_TOKEN_NAME: token.get_token_name(),
				SP.TRIGGER_PREV_COUNT: prev_value,
				SP.TRIGGER_NEW_COUNT: new_value,
				"tags": tags})
	return(retcode)



# Returns a dictionary of card tokens name on this card.
#
# * Key is the name of the token.
# * Value is the token scene.
func get_all_tokens() -> Dictionary:
	var found_tokens := {}
	for token in $Drawer/VBoxContainer.get_children():
		found_tokens[token.name] = token
	return found_tokens


# Returns the token node of the provided name or null if not found.
func get_token(token_name: String) -> Token:
	return(get_all_tokens().get(token_name,null))


# Returns only the token count if it exists.
# Else it returns 0
func get_token_count(token_name: String) -> int:
	var token: Token = get_token(token_name)
	if not token:
		return(0)
	else:
		return(token.get_count())


# Returns true, when the mouse cursor is over the drawer.
# This is used to retain focus on the card
# while the player is manipulating tokens.
func are_hovered() -> bool:
	var is_hovered = false
	if cfc.NMAP.board.mouse_pointer in $Drawer/Area2D.get_overlapping_areas():
		is_hovered = true
	return(is_hovered)


# Resizes Token Drawer to min size whenever a token is removed completely.
#
# Without this, the token drawer would stay at the highest size it reached.
func _on_VBoxContainer_sort_children() -> void:
	$Drawer/VBoxContainer.rect_size = \
			$Drawer/VBoxContainer.rect_min_size
	# We need to resize it's parent too
	$Drawer.rect_size = \
			$Drawer.rect_min_size

func set_max(token_name, max_value):
	max_tokens[token_name] = max_value

func get_max(token_name):
	if !max_tokens.has(token_name):
		return 0
	return max_tokens[token_name]

func export_to_json():
	var result = {}
	var token_names = get_all_tokens()
	for token_name in token_names:
		if !result:
			result = {}
		result[token_name] = get_token_count(token_name)
	return result

func load_from_json(description:Dictionary, keep_existing = false):
	if keep_existing:
		for token_name in description:
			var value =  description[token_name]
			if (value >0):
				var node = get_token(token_name)
				if node:
					node.queue_free()		
	else:
		for child in $Drawer/VBoxContainer.get_children():
			child.queue_free()	

	var token_names = description.keys()
	for token_name in token_names:
		var value =  description[token_name]
		if (value >0):
			var token = _TOKEN_SCENE.instance()
			token.setup(token_name, self)
			token.count = value
			$Drawer/VBoxContainer.add_child(token)	
	
	token_drawer(false, true)
	return self	

func set_is_horizontal(value:bool = true):
	_is_horizontal = value
	if (_is_horizontal):
		$Drawer.rect_position = Vector2(0, 20)
		$Drawer.rect_rotation = -90
	else:
		$Drawer.rect_position = Vector2(115, 20)
		$Drawer.rect_rotation = 0
	pass
