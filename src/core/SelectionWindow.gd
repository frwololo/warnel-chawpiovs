class_name SelectionWindow
extends Container

signal confirmed()

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

#accepted values:
#min: at least x cards
#max: at most x cards
#equal: exactly x cards
#as_much_as_possible: as much as possible (used e.g. for bomb threat)
#display: only for information
#all: need to select all cards, typically order matters
var selection_type: String
var is_selection_optional: bool
var is_cancelled := false
var _card_dupe_map := {}
var what_to_count = null
var selection_additional_constraints = null
var my_script
var card_array
var stored_integer
var hide_ok_on_zero = false
var show_cards_with_zero_value: = false
var can_select_cards_with_zero_value: = false

onready var _card_grid = get_node("%GridContainer")
onready var _tween = get_node("%Tween")
onready var cancel_button = get_node("%cancel")

var _assign_mode := false
var _assign_max_function := ""
var has_been_centered := false
var focus_grabbed = false
var window_title:= ""

#note: this is not _init !
func init(
		params: Dictionary,
		_script: ScriptObject = null,
		_stored_integer: int = 0):

	stored_integer = _stored_integer #a value that may be passed from previous script executions
	my_script = _script

	if _script:
		selection_count = _script.retrieve_integer_property(SP.KEY_SELECTION_COUNT, stored_integer)
	else:
		selection_count = ScriptObject.get_int_value(params.get(SP.KEY_SELECTION_COUNT,0), stored_integer)
	selection_type = params.get(SP.KEY_SELECTION_TYPE, "min")
	is_selection_optional = params.get(SP.KEY_SELECTION_OPTIONAL, false)
	what_to_count = params.get(SP.KEY_SELECTION_WHAT_TO_COUNT, "")
	show_cards_with_zero_value = params.get("selection_show_cards_with_zero_value", false)
	selection_additional_constraints = params.get("selection_additional_constraints", {})
	hide_ok_on_zero = params.get("hide_ok_on_zero", false)	

	if typeof(what_to_count) == TYPE_STRING:
		
		#TODO technically not possible but these modes allow
		#for cards to start at value zero, and otherwise this crashes
		#the game
		can_select_cards_with_zero_value = true
		if what_to_count.begins_with("assign_"):
			_assign_mode = true
			var function_suffix = what_to_count.substr(7)
			_assign_max_function = "get_remaining_" + function_suffix		
			what_to_count = "assign"
		elif what_to_count.begins_with("remove_"):
			_assign_mode = true
			var function_suffix = what_to_count.substr(7)
			_assign_max_function = "get_current_" + function_suffix		
			what_to_count = "assign"		
		
func _ready() -> void:
	# warning-ignore:return_value_discarded
	connect("confirmed", self, "_on_card_selection_confirmed")


func init_default_focus():
	if _card_grid.get_children().size():
		_card_grid.get_children()[0].grab_focus()
	else:
		cfc.default_button_focus(get_node("%buttons"))

func _process(_delta):
	popup_centered()
	var _result = check_ok_button()

var _force_compressed_view = false
func _compute_columns():
	_card_grid.columns = 7
	if cfc.screen_resolution.x > CFConst.LARGE_SCREEN_WIDTH:
		_card_grid.columns = 8
	
	if !card_array:
		return
	
	var counts:= {}
	for card in card_array:
		var parent = card.get_parent()
		var parent_count = counts.get(parent, 0)
		parent_count += 1
		counts[parent] = parent_count
	
	#if we have a big amount of cards, we will try to show them in a compressed way
	var most_kids_per_parent = counts.values().max()
	if cfc.screen_resolution.x < CFConst.LARGE_SCREEN_WIDTH:
		if counts.size() > 2 or\
			((most_kids_per_parent > _card_grid.columns) and counts.size() > 1):
				_force_compressed_view = true
			
	if counts:
		_card_grid.columns =  min (_card_grid.columns, most_kids_per_parent )
	var _tmp =1

# Populates the selection window with duplicates of the possible cards
# Then displays them in a popup for the player to select them.
func initiate_selection(_card_array: Array) -> void:
	if OS.has_feature("debug") and not cfc.is_testing:
		print("DEBUG INFO:SelectionWindow: Initiated Selection")
	
	#only include cards that can actually be used 
	card_array = []
	for card in _card_array:
		if (show_cards_with_zero_value or _assign_mode or get_count([card]) >= 1): #TODO better way for assign mode ?
			card_array.append(card)
	
	_compute_columns()
		

	
	for c in _card_grid.get_children():
		#c.queue_free()
		remove_child(c)
	# We use this to quickly store a copy of a card object to use to get
	# the card sizes for adjusting the size of the popup
	var card_sample: Card
	# for each card that the player needs to select amonst
	# we create a duplicate card inside a Card Grid object
	var current_parent = null
	var current_column = -1
	var previous_card_grid_obj = null
	for card in card_array:
		current_column += 1
		if current_column == _card_grid.columns:
			current_column = 0
		var dupe_selection: Card
		if typeof(card) == TYPE_STRING:
			dupe_selection = cfc.instance_card(card, -20)
		else:
			#add separator for cards from different zones
			if (current_parent and (card.get_parent() != current_parent) and current_column !=0):
				if _force_compressed_view:
					_card_grid.add_child(grid_card_object_scene.instance())
					current_column += 1
				else:
					for _i in range (current_column, _card_grid.columns):
						_card_grid.add_child(grid_card_object_scene.instance())
					current_column = 0
			current_parent = card.get_parent()
			
			dupe_selection = card.get_duplicate()
#			dupe_selection = card.duplicate(DUPLICATE_USE_INSTANCING)
#			# This prevents the card from being scripted with the
#			# signal propagator and other things going via groups
#			dupe_selection.remove_from_group("cards")
#			dupe_selection.canonical_name = card.canonical_name
#			dupe_selection.canonical_id = card.canonical_id
#			dupe_selection.properties = card.properties.duplicate()
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
		if !can_select_cards_with_zero_value and (get_count([card]) <= 0):
			dupe_selection.to_grayscale()
		dupe_selection.ensure_proper()
#		dupe_selection.enable_focus_mode()

		# We connect each card grid's gui input into a call which will handle
		# The selections
		if _assign_mode:
			var max_assign_value = card.call(_assign_max_function)
			var spinbox = dupe_selection.get_spinbox()
			spinbox.init_plus_minus_mode(0, 0, max_assign_value)
			spinbox.connect("value_changed", self, "spinbox_value_changed", [dupe_selection, card])
		card_grid_obj.connect("gui_input", self, "on_selection_gui_input", [dupe_selection, card])
		card_grid_obj.focus_mode = Control.FOCUS_ALL
		if previous_card_grid_obj:
			previous_card_grid_obj.focus_neighbour_right = card_grid_obj.get_path()
			card_grid_obj.focus_neighbour_left = previous_card_grid_obj.get_path()
		previous_card_grid_obj = card_grid_obj
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

	# Spawning all the duplicates is a bit heavy
	# So we delay showing the tween to avoid having it look choppy
	#yield(get_tree().create_timer(0.2), "timeout")
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

func popup_centered():
	if has_been_centered:
		return	
		
	if !$Panel.rect_size:
		return

	var size = $Panel.rect_size * self.rect_scale

	self.rect_position = get_viewport().size/2	- size/2
	has_been_centered = true

	call_deferred("init_default_focus")	

func add_cancel(text) -> Button:
	cancel_button.text = text
	cancel_button.visible = true
	cancel_button.icon = gamepadHandler.get_icon_for_action("ui_cancel")
	return cancel_button

func get_ok():
	return get_node("%ok")
	
func post_initiate_checks():
		
	# If the selection is optional, we allow the player to cancel out
	# of the popup
	if is_selection_optional:
		var button = add_cancel("Cancel")
		# warning-ignore:return_value_discarded
		button.connect("pressed",self, "_on_cancel_pressed")
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
		"all":
			window_title = "Select all cards - order matters"			
	
	if (my_script):
		window_title = cfc.enrich_window_title(self, my_script, window_title)

	get_node("%Title").text = window_title

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
	
	#if current count is zero, we disable it all the time, to make it
	# clear that nothing has been selected
	#clicking on cancel should have the same effect
	if current_count == 0 and hide_ok_on_zero:
		get_ok().disabled = true
	else:
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
			"all":
				if current_count < card_array.size():
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
		var spinbox = card.get_spinbox()
		var remaining = spinbox.max_value
		var currently_assigned = spinbox.value
		if remaining > currently_assigned:
			return true
			
	return false			

var _cache_count_per_card = {}
func get_count(_card_array: Array) -> int:
	if typeof(what_to_count) == TYPE_STRING:
		match what_to_count:
			"assign":
				var total = 0
				for card in card_array: #for "assign" we actually ignore the passed array and use our currently displayed one
					var spinbox = _card_dupe_map[card].get_spinbox()
					total = total + spinbox.value
				return total			
			"":
				return _card_array.size()
			_:
				var total = 0
				var func_name = what_to_count
				for card in _card_array:
					if card and is_instance_valid(card):
						if !_cache_count_per_card.has(card):
							_cache_count_per_card[card] =  card.call(func_name, my_script)
						total = total + _cache_count_per_card[card]
				return total
	elif typeof(what_to_count) == TYPE_DICTIONARY and what_to_count.has("func_name"):
		var params = what_to_count.get("func_params", {})
		var total = 0
		var func_name = what_to_count.get("func_name")
		for card in _card_array:
			if card and is_instance_valid(card):
				if !_cache_count_per_card.has(card):
					_cache_count_per_card[card] = cfc.ov_utils.func_name_run(card, func_name, params, my_script)
				total = total + _cache_count_per_card[card]
		return total
	
	return 0		

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
		
	if selection_type == "all":
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
		var spinbox = dupe_selection.get_spinbox()
		spinbox.value -= diff
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
	if !can_select_cards_with_zero_value:
		if get_count([origin_card]) <= 0:
			return
	if selection_type == "as_much_as_possible":
		var current_total = get_count(card_array)
		var spinbox = dupe_selection.get_spinbox()
		if current_total >= selection_count:
			#we're already at max, go back to zero
			spinbox.set_value(0)
		else:
			spinbox.set_value(spinbox.get_value() + 1)
		return
		
	# Each time a card is clicked, it's selected/unselected
	var grid_card_obj = dupe_selection.get_parent()
	
	if origin_card in selected_cards:
		selected_cards.erase(origin_card)
		dupe_selection.highlight.set_highlight(false)
		grid_card_obj.set_selected(false)
	else:
		selected_cards.append(origin_card)
		dupe_selection.highlight.set_highlight(true)
		grid_card_obj.set_selected(true)
	# We want to avoid the player being able to select more cards than
	# the max, even if the OK button is disabled
	# So whenever they exceed the max, we unselect the first card in the array.
	#TODO should use get_count
	if selection_type in ["equal", "max"]  and selected_cards.size() > selection_count:
		var dupe = _card_dupe_map[selected_cards[0]]
		dupe.highlight.set_highlight(false)
		dupe.get_parent().set_selected(false)
		selected_cards.remove(0)	

# The player can select the cards using a simple left-click.
func on_selection_gui_input(event: InputEvent, dupe_selection: Card, origin_card) -> void:
	if selection_type == 'display':
		return
		
	if event is InputEventMouseButton\
			and event.is_pressed()\
			and event.get_button_index() == 1:		
		card_clicked(dupe_selection, origin_card)
	elif event is InputEvent:
		if event.is_action_pressed("ui_accept"):	
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
					var spinbox = dupe_card.get_spinbox()
					spinbox.value +=1
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
	#_on_card_selection_confirmed()
	scripting_bus.emit_signal(
			"selection_window_canceled",
			self,
			{"selected_cards": selected_cards}
	)	
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

func _on_ok_pressed() -> void:
	emit_signal("confirmed")


func _input(event):	
	if gamepadHandler.is_ui_cancel_pressed(event):
		_on_cancel_pressed()
		return
