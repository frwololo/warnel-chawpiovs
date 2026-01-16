# This class is not instanced via its name. 
# Rather it is instanced using its path from cfc
# This allows a game to extend it by extending this class
# and then replacing the path in CFConst.PATH_OVERRIDABLE_UTILS 
# with the location of their extended script.
class_name OVUtils
extends Reference

const _CARD_SELECT_SCENE_FILE = CFConst.PATH_CORE + "SelectionWindow.tscn"
const _CARD_SELECT_SCENE = preload(_CARD_SELECT_SCENE_FILE)

# The path to the optional confirm scene. This has to be defined explicitly
# here, in order to use it in its preload, otherwise the parser gives an error
const _OPTIONAL_CONFIRM_SCENE_FILE = CFConst.PATH_CUSTOM + "OptionalConfirmation.tscn"
const _OPTIONAL_CONFIRM_SCENE = preload(_OPTIONAL_CONFIRM_SCENE_FILE)

# Populates the info panels under the card, when it is shown in the
# viewport focus or deckbuilder
func populate_info_panels(card: Card, focus_info: DetailPanels) -> void:
	focus_info.hide_all_info()
	var card_illustration = card.get_property("_illustration")
	if card_illustration:
		focus_info.show_illustration("Illustration by: " + card_illustration)
	else:
		focus_info.hide_illustration()
	for tag in card.get_property("Tags", []):
		if CardConfig.EXPLANATIONS.has(tag):
			focus_info.add_info(tag, CardConfig.EXPLANATIONS[tag])
	var card_keywords = card.get_property("_keywords")
	if card_keywords:
		for keyword in card_keywords:
			if CardConfig.EXPLANATIONS.has(keyword):
				focus_info.add_info(keyword, CardConfig.EXPLANATIONS[keyword])

func get_subjects(_script: ScriptObject, _subject_request, _stored_integer : int = 0,  _run_type:int = CFInt.RunType.NORMAL, _trigger_details := {}) -> Array:
	return([])

func select_card(
		card_list: Array, 
		selection_params: Dictionary,
		parent_node,
		script : ScriptObject = null,
		run_type:int = CFInt.RunType.NORMAL,
		stored_integer: int = 0,
		card_select_scene = _CARD_SELECT_SCENE):
	
	if parent_node == cfc.NMAP.get("board")  and (run_type != CFInt.RunType.BACKGROUND_COST_CHECK):
		cfc.game_paused = true
	var selected_cards
	# This way we can override the card select scene with a custom one
	var selection = card_select_scene.instance()
	selection.init(selection_params, script, stored_integer)

	parent_node.add_child(selection)		
	selection.call_deferred("initiate_selection", card_list)
	# We have to wait until the player has finished selecting their cards
	yield(selection,"confirmed")

	if selection.is_cancelled:
		selected_cards = false
	else:
		selected_cards = selection.selected_cards			
	selection.queue_free()
		
	if parent_node == cfc.NMAP.get("board"):
		cfc.game_paused = false
		
	return(selected_cards)

# Goes through the card pool of the game and checks each card against the provided list of filters
# Then returns all card names matching the filters.
func filter_card_pool(filters_list: Array, card_pool := _get_card_pool()) -> Array:
	var matching_card_defs := []
	for card_name in card_pool:
		var matching_def := true
		# Each filter should be a CardFilter class
		for filter in filters_list:
			if not filter.check_card(card_pool[card_name]):
				matching_def = false
				break
		if matching_def:
			matching_card_defs.append(card_name)
	return(matching_card_defs)


# Overridable function to return the card pool of the game
# Games might decide to change how this is used for their own purposes.
func _get_card_pool() -> Dictionary:
	return(cfc.card_definitions)

func parse_post_prime_replacements(script_task: ScriptObject) -> Dictionary:
	return script_task.script_definition

# Creates a ConfirmationDialog for the player to approve the
# Use of an optional script or task.
func confirm(
		_owner,
		script: Dictionary,
		card_name: String,
		task_name: String,
		type := "task") -> bool:
	cfc.add_ongoing_process(script)		
	var is_accepted := true
	# We do not use SP.KEY_IS_OPTIONAL here to avoid causing cyclical
	# references when calling CFUtils from SP
	if script.get("is_optional_" + type):
		var confirm = _OPTIONAL_CONFIRM_SCENE.instance()
		confirm.prep(card_name,task_name)
		# We have to wait until the player has finished selecting an option
		yield(confirm,"selected")
		# If the player selected "No", we don't execute anything
		if not confirm.is_accepted:
			is_accepted = false
		# Garbage cleanup
		confirm.queue_free()
	cfc.remove_ongoing_process(script)	
	return(is_accepted)

# Additional filter for triggers
func filter_trigger(
		_trigger:String,
		_card_scripts,
		_trigger_card,
		_owner_card,
		_trigger_details) -> bool:
			return true

