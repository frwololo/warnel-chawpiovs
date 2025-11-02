class_name SelectionWindow
extends AcceptDialog


# The path to the GridCardObject scene.
const _GRID_CARD_OBJECT_SCENE_FILE = CFConst.PATH_CORE\
		+ "CardViewer/CVGridCardObject.tscn"
const _GRID_CARD_OBJECT_SCENE = preload(_GRID_CARD_OBJECT_SCENE_FILE)
const _INFO_PANEL_SCENE_FILE = CFConst.PATH_CORE\
		+ "CardViewer/CVInfoPanel.tscn"
const _INFO_PANEL_SCENE = preload(_INFO_PANEL_SCENE_FILE)

export(PackedScene) var grid_card_object_scene := _GRID_CARD_OBJECT_SCENE
export(PackedScene) var info_panel_scene := _INFO_PANEL_SCENE

var selected_cards := []
var selection_count : int
var selection_type: String
var is_selection_optional: bool
var is_cancelled := false
var _card_dupe_map := {}
var what_to_count: String
var selection_additional_constraints = null
var my_script
var card_array
var stored_integer

onready var _card_grid = $GridContainer
onready var _tween = $Tween

var _assign_mode := false
var _assign_max_function := ""

#Not an actual _init!
#this is because caller calls "instance()" and right now 
# I'm too lazy to figure out why I can't give it params
func init(
		params: Dictionary,
		_script: ScriptObject = null,
		_stored_integer: int = 0):

	stored_integer = _stored_integer #a value that may be passed from previous script executions
	my_script = _script

	selection_count = ScriptObject.get_int_value(params.get(SP.KEY_SELECTION_COUNT), stored_integer)
	selection_type = params.get(SP.KEY_SELECTION_TYPE, "min")
	is_selection_optional = params.get(SP.KEY_SELECTION_OPTIONAL, false)
	what_to_count = params.get(SP.KEY_SELECTION_WHAT_TO_COUNT, "")
	selection_additional_constraints = params.get("selection_additional_constraints", {})
		

	if what_to_count.begins_with("assign_"):
		_assign_mode = true
		var function_suffix = what_to_count.substr(7)
		_assign_max_function = "get_remaining_" + function_suffix		
		what_to_count = "assign"
		
func _ready() -> void:
	# warning-ignore:return_value_discarded
	connect("confirmed", self, "_on_card_selection_confirmed")

func _process(_delta):
	var _result = check_ok_button()


func _compute_columns():
	_card_grid.columns = 8
	var counts:= {}
	for card in card_array:
		var parent = card.get_parent()
		var parent_count = counts.get(parent, 0)
		parent_count += 1
		counts[parent] = parent_count
	
	if counts:
		_card_grid.columns =  min (8, counts.values().max())

# Populates the selection window with duplicates of the possible cards
# Then displays them in a popup for the player to select them.
func initiate_selection(_card_array: Array) -> void:
	if OS.has_feature("debug") and not cfc.is_testing:
		print("DEBUG INFO:SelectionWindow: Initiated Selection")
	
	#only include cards that can actually be used 
	card_array = []
	for card in _card_array:
		if ( _assign_mode or get_count([card]) >= 1): #TODO better way for assign mode ?
			card_array.append(card)
	
	_compute_columns()
		
	# We don't allow the player to close the popup with the close button
	# as that will not send the mandatory signal to unpause the game
	get_close_button().visible = false

	
	for c in _card_grid.get_children():
		c.queue_free()
	# We use this to quickly store a copy of a card object to use to get
	# the card sizes for adjusting the size of the popup
	var card_sample: Card
	# for each card that the player needs to select amonst
	# we create a duplicate card inside a Card Grid object
	var current_parent = null
	var current_column = -1
	for card in card_array:
		current_column += 1
		if current_column == _card_grid.columns:
			current_column = 0
		var dupe_selection: Card
		if typeof(card) == TYPE_STRING:
			dupe_selection = cfc.instance_card(card, -20)
		else:
			#add separator for cards from different zones
			if (current_parent and (card.get_parent() != current_parent)):
				for _i in range (current_column, _card_grid.columns):
					_card_grid.add_child(grid_card_object_scene.instance())
				current_column = 0
			current_parent = card.get_parent()
			
			dupe_selection = card.duplicate(DUPLICATE_USE_INSTANCING)
			# This prevents the card from being scripted with the
			# signal propagator and other things going via groups
			dupe_selection.remove_from_group("cards")
			dupe_selection.canonical_name = card.canonical_name
			dupe_selection.canonical_id = card.canonical_id
			dupe_selection.properties = card.properties.duplicate()
		card_sample = dupe_selection
		var card_grid_obj = grid_card_object_scene.instance()
		_card_grid.add_child(card_grid_obj)
		# This is necessary setup for the card grid container
		card_grid_obj.preview_popup.focus_info.info_panel_scene = info_panel_scene
		card_grid_obj.preview_popup.focus_info.setup()
		card_grid_obj.setup(dupe_selection)
		_extra_dupe_ready(dupe_selection, card)
		_card_dupe_map[card] = dupe_selection
		# warning-ignore:return_value_discarded
		dupe_selection.set_is_faceup(true,true)
		dupe_selection.ensure_proper()
		# We connect each card grid's gui input into a call which will handle
		# The selections
		if _assign_mode:
			var max_assign_value = card.call(_assign_max_function)
			dupe_selection.spinbox.init_plus_minus_mode(0, 0, max_assign_value)
			dupe_selection.spinbox.connect("value_changed", self, "spinbox_value_changed", [dupe_selection, card])
		card_grid_obj.connect("gui_input", self, "on_selection_gui_input", [dupe_selection, card])
	# We don't want to show a popup longer than the cards. So the width is based on the lowest
	# between the grid columns or the amount of cards

	post_initiate_checks()

	var shown_columns = min(_card_grid.columns, card_array.size())
	var card_size = CFConst.CARD_SIZE
	var thumbnail_scale = CFConst.THUMBNAIL_SCALE
	if card_sample as Card:
		card_size = card_sample.canonical_size
		thumbnail_scale = card_sample.thumbnail_scale
	var popup_size_x = (card_size.x * thumbnail_scale * shown_columns * cfc.curr_scale)\
			+ _card_grid.get("custom_constants/vseparation") * shown_columns
			
	#TODO There is a bug where the ok button doesn't show up if the length is lower than 600 px
	popup_size_x = max(popup_size_x, 600)		
	# The height will be automatically adjusted based on the amount of cards
	rect_size = Vector2(popup_size_x,0)
	popup_centered_minsize()
	# Spawning all the duplicates is a bit heavy
	# So we delay showing the tween to avoid having it look choppy
	yield(get_tree().create_timer(0.2), "timeout")
	_tween.remove_all()
	# We do a nice alpha-modulate tween
	_tween.interpolate_property(self,'modulate:a',
			0, 1, 0.5,
			Tween.TRANS_SINE, Tween.EASE_IN)
	_tween.start()
	scripting_bus.emit_signal(
			"selection_window_opened",
			self,
			{"card_selection_options": _card_dupe_map.keys()}
	)
	if OS.has_feature("debug") and not cfc.is_testing:
		print("DEBUG INFO:SelectionWindow: Started Card Display with a %s card selection" % [_card_grid.get_child_count()])


func post_initiate_checks():
		
	# If the selection is optional, we allow the player to cancel out
	# of the popup
	if is_selection_optional:
		var cancel_button := add_cancel("Cancel")
		# warning-ignore:return_value_discarded
		cancel_button.connect("pressed",self, "_on_cancel_pressed")
	# If the amount of cards available for the choice are below the requirements
	# We return that the selection was canceled
	if get_count(card_array) < selection_count\
			and selection_type in ["equal", "min"]:
		force_cancel()
		return
	# If the selection count is 0 (e.g. reduced with an alterant)
	# And we're looking for max or equal amount of cards, we return cancelled.
	elif selection_count == 0\
			and selection_type in ["equal", "max"]:
		force_cancel()
		return

	# When we have 0 cards to select from, we consider the selection cancelled
	elif get_count(card_array) == 0\
			and (!_assign_mode): #TODO better check here?
		force_cancel()
		return
		
	if !(check_additional_constraints(card_array)):
		force_cancel()
		return

	# If the amount of cards available for the choice are exactly the requirements
	# And we're looking for equal or minimum amount
	# We immediately return what is there.
	if get_count(card_array) == selection_count\
			and selection_type in ["equal", "min"]:
		selected_cards = card_array
		emit_signal("confirmed")
		return
	
	match selection_type:
		"min":
			window_title = "Select at least " + str(selection_count) + " cards."
		"max":
			window_title = "Select at most " + str(selection_count) + " cards."
		"equal":
			window_title = "Select exactly " + str(selection_count) + " cards."
		"as_much_as_possible":
			window_title = "Assign " + str(selection_count) + " points."
		"display":
			window_title = "Press OK to continue"
	
	if (my_script):
		window_title = cfc.enrich_window_title(self, my_script, window_title)


#example of constraints
#{
#	"func_name": "can_pay_as_resource",
#	"using": "all_selection",
#	"param": cost 
#}
func check_additional_constraints(_cards:Array = selected_cards) -> bool:
	if (!selection_additional_constraints):
		return true	
	
	var send_for_comparison:= []
	match selection_additional_constraints.get("using", "all_selection"):
		"all_selection":
			send_for_comparison = _cards
		_:
			#error, we skip
			return true
	
	var result = cfc.ov_utils.call(selection_additional_constraints["func_name"],selection_additional_constraints["func_params"], send_for_comparison, my_script )
	return result
	
func check_ok_button() -> bool:
	var current_count = get_count(selected_cards)
	# We disable the OK button, if the amount of cards to be
	# chosen do not match our expectations
	match selection_type:
		"min":
			if current_count < selection_count:
				get_ok().disabled = true
			else:
				get_ok().disabled = false
		"equal":
			if current_count != selection_count:
				get_ok().disabled = true
			else:
				get_ok().disabled = false
		"max":
			if current_count > selection_count:
				get_ok().disabled = true
			else:
				get_ok().disabled = false
		"as_much_as_possible":
			if (current_count < selection_count and can_still_select_more()):
				get_ok().disabled = true
			else:
				get_ok().disabled = false
	
	if (!get_ok().disabled):
		if !check_additional_constraints():
			 get_ok().disabled = true
	
	return !(get_ok().disabled)

#function when asked to select "as much as possible"
#to check if we can still select more cards/points based on the constraints
func can_still_select_more() -> bool :
	if (selection_type != "as_much_as_possible"):
		#basically not implemented in other cases
		return true

	var current_count = get_count(card_array)
	if current_count >= selection_count:
		return false
		
	for card in card_array:
		var remaining = card.spinbox.max_value
		var currently_assigned = card.spinbox.value
		if remaining > currently_assigned:
			return true
			
	return false			

func get_count(_card_array: Array) -> int:
	match what_to_count:
		"assign":
			var total = 0
			for card in card_array: #for "assign" we actually ignore the passed array and use our currently displayed one
				total = total + _card_dupe_map[card].spinbox.value
			return total			
		"":
			return _card_array.size()
		_:
			var total = 0
			var func_name = what_to_count
			for card in _card_array:
				total = total + card.call(func_name, my_script)
			return total

#Returns arbitrary (valid) targets for the purpose of cost check
func dry_run(_card_array: Array) -> void:	
			
	if (selection_type in ["display"]): #or is_selection_optional
		force_cancel()
		return
	# If the amount of cards available for the choice are below the requirements
	# We return that the selection was canceled
	if get_count(_card_array) < selection_count\
			and selection_type in ["equal", "min"]:
		force_cancel()
		return
	# If the selection count is 0 (e.g. reduced with an alterant)
	# And we're looking for max or equal amount of cards, we return cancelled.
	if selection_count == 0\
			and selection_type in ["equal", "max"]:
		force_cancel()
		return
	# If the amount of cards available for the choice are exactly the requirements
	# And we're looking for equal or minimum amount
	# We immediately select
	if get_count(_card_array) == selection_count\
			and selection_type in ["equal", "min"]:
		selected_cards = _card_array

	# When we have 0 cards to select from, we consider the selection cancelled
	if get_count(_card_array) == 0\
			and !_assign_mode:
		force_cancel()
		return
	
	if (!selected_cards):	
		#generic case	
		match selection_type:
			"min":
				var total = 0
				var i = 0
				while total < selection_count and i < _card_array.size():
					selected_cards.append(_card_array[i])
					total = get_count(selected_cards)
					i += 1
			"max":
				selected_cards = _card_array.slice(0, 1)
			"equal":
				var total = 0
				var i = 0
				while total < selection_count and i < _card_array.size():
					selected_cards.append(_card_array[i])
					total = get_count(selected_cards)
					i += 1			
					#TODO we might have an error here where we don't get the exact number if we add 2 or more in one step
			"as_much_as_possible":
				var remaining = selection_count
				for card in _card_array:
					var can_assign = card.call(_assign_max_function)
					if can_assign > remaining:
						can_assign = remaining
					remaining -= can_assign
					for _i in range (can_assign):
						selected_cards.append(card)
					if remaining <= 0:
						break	
	
	#we tried our best, we might still be failing
	if (!check_ok_button()):
		#we're not meeting some constraint, try to change the selection
		#todo need to do something much more clever here
		match selection_type:
			"min":
				selected_cards = _card_array
			_:
				#todo
				pass

		if (!check_ok_button()):
			force_cancel()
			return
	emit_signal("confirmed")
	return

# Overridable function for games to extend processing of dupe card
# after adding it to the scene
func _extra_dupe_ready(dupe_selection: Card, _card: Card) -> void:
	dupe_selection.targeting_arrow.visible = false

# integer up_down manipulation buttons
func spinbox_value_changed( new_value,  dupe_selection: Card, origin_card) -> void:
	var current_total = get_count(card_array)
	#we added too much, this is a problem in general. set the value again and let it call us back
	if current_total > selection_count and selection_type in ["max", "equal", "as_much_as_possible"]:
		var diff = current_total - selection_count
		dupe_selection.spinbox.value -= diff
		return
	
	var count = selected_cards.count(origin_card)
	var to_add = new_value - count
	
	if to_add > 0:
		for _i in range(to_add):
			selected_cards.append(origin_card)
	else:
		for _i in range (-to_add):
			selected_cards.erase(origin_card)
		
	
	pass
	
func card_clicked(dupe_selection: Card, origin_card) -> void:
	# Each time a card is clicked, it's selected/unselected
	if origin_card in selected_cards:
		selected_cards.erase(origin_card)
		dupe_selection.highlight.set_highlight(false)
	else:
		selected_cards.append(origin_card)
		dupe_selection.highlight.set_highlight(true)
	# We want to avoid the player being able to select more cards than
	# the max, even if the OK button is disabled
	# So whenever they exceed the max, we unselect the first card in the array.
	if selection_type in ["equal", "max"]  and selected_cards.size() > selection_count:
		_card_dupe_map[selected_cards[0]].highlight.set_highlight(false)
		selected_cards.remove(0)	

# The player can select the cards using a simple left-click.
func on_selection_gui_input(event: InputEvent, dupe_selection: Card, origin_card) -> void:
	if event is InputEventMouseButton\
			and event.is_pressed()\
			and event.get_button_index() == 1\
			and selection_type != 'display':
				
		card_clicked(dupe_selection, origin_card)


#used mostly for testing
func select_cards_by_name(names :Array = []) -> Array:
	var all_choices = _card_dupe_map.keys()
	for name_or_id in names:
		for card in all_choices:
			if (card.canonical_name.to_lower() == name_or_id.to_lower()) \
					or (card.get_property("_code", "").to_lower() == name_or_id.to_lower()):
				var dupe_card = _card_dupe_map[card]
				if _assign_mode:
					dupe_card.spinbox.value +=1
				else:
					card_clicked(dupe_card, card)
					
	if check_ok_button():	
		emit_signal("confirmed")			
	return(selected_cards)


func get_all_card_options() -> Array:
	return(_card_dupe_map.keys())

func force_cancel():
	_on_cancel_pressed()

# Cancels out of the selection window
func _on_cancel_pressed() -> void:
	selected_cards.clear()
	is_cancelled = true
	# The signal is the same, but the calling method, should be checking the
	# is_cancelled bool.
	# This is to be able to yield to only one specific signal.
	emit_signal("confirmed")

func _on_card_selection_confirmed() -> void:
	#TODO 2025-03-01 Bug here, when hitting cancel, this doesn't send the card_selected signal, blocking execution
	# Arguably, it is ok to still send the signal, with an array of 0. 
	#if is_cancelled:
	#	return
	scripting_bus.emit_signal(
			"card_selected",
			self,
			{"selected_cards": selected_cards}
	)
