# This is a parent class containing the methods for lookup of subjects
# and script properties.
#
# It is typically never instanced directly.
class_name ScriptObject
extends Reference


var interaction_authorized_user_id
var user_interaction_status =  CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET

var user
# Sent when the _init() method has completed
# warning-ignore:unused_signal
signal primed

# Stores the details arg passed the signal to use for filtering
var trigger_details : Dictionary
var trigger: String
# The object which owns this Task
var owner
# The subjects is typically a `Card` object
# in the future might be other things
var subjects := []

# The name of the method to call in the ScriptingEngine
# to implement this task
var script_name: String
# Storage for all details of the task definition
var script_definition : Dictionary
# Used by the ScriptingEngine to know if the task
# has finished processing targetting and optional confirmations
var is_primed := false
# If true if this task is valid to run.
# A task is invalid to run if some filter does not match.
var is_valid := true
# The amount of subjects card the script requested to modify
# We use this to compare against costs during dry_runs
#
# This is typically set during the _find_subjects() call
var requested_subjects: int
# The card which triggered this script.
var trigger_object: Node
# Stores the subjects discovered by the task previous to this one
var prev_subjects := []
var all_prev_subjects := []


var my_stored_integer = null

func set_prev_subjects(subjects):
	if prev_subjects and trigger_details["prev_subjects"]:
		#we've already forced the previous subjects in an earlier step
		return
	prev_subjects = subjects

# prepares the properties needed by the script to function.
func _init(_owner, script: Dictionary,  _trigger_object = null, 	_trigger_details := {}) -> void:
	# We store the card which executes this task
	owner = _owner
	if _trigger_details.has("trigger_type"):
		trigger = _trigger_details["trigger_type"]
	else:
		trigger = ""
		
	if _trigger_details.has("prev_subjects"):
		set_prev_subjects(_trigger_details["prev_subjects"])
		
	trigger_details = _trigger_details
	# We store all the task properties in our own dictionary
	script_definition = script
	trigger_object = _trigger_object
	user_interaction_status =  CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET
	parse_replacements()

# Returns the specified property of the string.
# Also sets appropriate defaults when then property has not beend defined.
# A default value can also be passed directly, which is useful when
# ScriptingEngine has been extended by custom tasks.
#
# property can also compute an if/then/else dictionary
func get_property(property: String, default = null, subscript_definition = null, root = null):
	if default == null:
		default = SP.get_default(property)
#	var found_value = lookup_script_property(script_definition.get(property,default))
	
	var result = ""
	if (subscript_definition != null):
			#used for recursive calls of if/then/else
		result = subscript_definition
	elif root!= null:
		result = root.get(property,default)
	else:
		result = script_definition.get(property,default)
	
	#if then else special case. Todo could this maybe go into a more generic location to work on all script variables ?
	if (typeof (result) == TYPE_DICTIONARY):
		if result.has("if"):
			var _if = result["if"]
			var func_name = _if["func_name"]
			var params = _if.get("func_params", {})
			var if_check_result = owner.call(func_name, params, self)
			if (if_check_result):
				return get_property(property, default, result["then"], root)
			else:
				return get_property(property, default, result["else"], root)
		elif result.has("func_name"):
			var params = result.get("func_params", {})
			result = cfc.ov_utils.func_name_run(self.owner, result["func_name"], params, self)
			
	return result
	
func get_sub_property(property: String, root, default = null):
	return get_property(property, default, null, root)	
#
#
#func lookup_script_property(found_value):
#	if typeof(found_value) == TYPE_DICTIONARY and found_value.has("lookup_property"):
#		var lookup_property = found_value.get("lookup_property")
#		var value_key = found_value.get("value_key")
#		var default_value = found_value.get("default")
#		var owner_name = owner.name
#		if "canonical_name" in owner:
#			owner_name = owner.canonical_name
#		var value = cfc.card_definitions[owner.canonical_name]\
#				.get(lookup_property, {}).get(value_key, default_value)
#		if found_value.get("is_inverted"):
#			value *= 1
#		return(value)
#	return(found_value)

#TODO MULTIPLAYER_MODIFICATION
#TODO move this outside of core classes
func _network_prepaid():
	var prepayment = get_property("network_prepaid", null)
	if null == prepayment:
		return null
	#prepayment should be an array of GUID
	var result = []
	for uid in prepayment:
		result.append(guidMaster.get_object_by_guid(uid))
		
	return result
	
# Figures out what the subjects of this script is supposed to be.
#
# Returns a Card object if subjects is defined, else returns null.
func _find_subjects(stored_integer := 0, run_type:int = CFInt.RunType.NORMAL) -> Array:
	#TODO MULTIPLAYER_MODIFICATION
	var prepaid = _network_prepaid()
	if (null != prepaid):
		user_interaction_status =  CFConst.USER_INTERACTION_STATUS.DONE_NETWORK_PREPAID
		subjects = prepaid
		return prepaid

	var result = _local_find_subjects(stored_integer, run_type)

	if result is GDScriptFunctionState: # Still working.
		result = yield(result, "completed")	
	
	subjects = result
	return subjects

#runs "find_subjects" locally, does not store the result
#this allows to run a "find subjects" activity within
#the context of this scrpt, without impacting it
#useful for sub scripts	
func _local_find_subjects(stored_integer := 0, run_type:int = CFInt.RunType.NORMAL, overrides:Dictionary = {}):
	cfc.add_ongoing_process(self, "_local_find_subjects")		
	var subjects_array := []

	var interaction_authority:UserInteractionAuthority = UserInteractionAuthority.new(owner, trigger_object, trigger, trigger_details, run_type)
	var interaction_authorized = interaction_authority.interaction_authorized()
	
	for key in overrides:
		self.script_definition[key] = overrides[key]
	
#	var subject = overrides.get("subject", get_property(SP.KEY_SUBJECT))
	var subject = get_property(SP.KEY_SUBJECT)
	
	#replace targeting with selection (optional)
	if CFConst.OPTIONS.get("replace_targetting_with_selection", false):
		if subject == SP.KEY_SUBJECT_V_TARGET:
			script_definition[SP.KEY_SUBJECT] = SP.KEY_SUBJECT_V_BOARDSEEK
			script_definition[SP.KEY_SELECTION_TYPE] = "equal" 
			script_definition[SP.KEY_SELECTION_COUNT] = 1
			script_definition[SP.KEY_NEEDS_SELECTION] = true
			script_definition[SP.KEY_SUBJECT_COUNT] = "all"
			script_definition["filter_state_seek"] = script_definition["filter_state_subject"]	
	# See SP.KEY_SUBJECT doc
	match subject:
		# Ever task retrieves the subjects used in the previous task.
		# if the value "previous" is given to the "subjects" key,
		# it simple reuses the same ones.
		SP.KEY_SUBJECT_V_PREVIOUS:
			if get_property(SP.KEY_FILTER_EACH_REVIOUS_SUBJECT):
				# We still check all previous subjects to check that they match the filters
				# If not, we remove them from the subject list
				for c in prev_subjects:
					if SP.check_validity(c, script_definition, "subject", owner):
						subjects_array.append(c)
				if subjects_array.size() == 0:
					is_valid = false
			# With this approach, if any of the previous subjects doesn't
			# match the filter, the whole task is considered invalid.
			# But the subjects lists remains intact
			else:
				subjects_array = prev_subjects
				for c in subjects_array:
					if not SP.check_validity(c, script_definition, "subject", owner):
						is_valid = false
		SP.KEY_SUBJECT_V_ALL_PREVIOUS:
			if get_property(SP.KEY_FILTER_EACH_REVIOUS_SUBJECT):
				# We still check all previous subjects to check that they match the filters
				# If not, we remove them from the subject list
				for c in all_prev_subjects:
					if SP.check_validity(c, script_definition, "subject", owner):
						subjects_array.append(c)
				if subjects_array.size() == 0:
					is_valid = false
			# With this approach, if any of the previous subjects doesn't
			# match the filter, the whole task is considered invalid.
			# But the subjects lists remains intact
			else:
				subjects_array = all_prev_subjects
				for c in subjects_array:
					if not SP.check_validity(c, script_definition, "subject", owner):
						is_valid = false						
		SP.KEY_SUBJECT_V_TARGET:
			if !interaction_authorized:
				user_interaction_status = CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER
				cfc.remove_ongoing_process(self, "_local_find_subjects")
				return []
			var c = null
			if (run_type == CFInt.RunType.BACKGROUND_COST_CHECK):
				c = _dry_run_card_targeting(script_definition)
			else:
				

				c = _initiate_card_targeting()
				if c is GDScriptFunctionState && c.is_valid(): # Still working.
					c = yield(c, "completed")
			# If the target is null, it means the player pointed at nothing
			if c:
				is_valid = SP.check_validity(c, script_definition, "subject", owner)
				subjects_array.append(c)
			else:
				# If the script required a target and it didn't find any
				# we consider it invalid
				is_valid = false
			user_interaction_status = CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER	
		SP.KEY_SUBJECT_V_BOARDSEEK:
			subjects_array = _boardseek_subjects(stored_integer)
		SP.KEY_SUBJECT_V_TUTOR:
			subjects_array = _tutor_subjects(stored_integer)
		SP.KEY_SUBJECT_V_INDEX:
			subjects_array = _index_seek_subjects(stored_integer)
		SP.KEY_SUBJECT_V_TRIGGER:
			# We check, just to make sure we didn't mess up
			if trigger_object:
				is_valid = SP.check_validity(trigger_object, script_definition, "subject", owner)
				subjects_array.append(trigger_object)
			else:
				print_debug("WARNING: Subject: trigger requested, but no trigger card passed")
		SP.KEY_SUBJECT_V_SELF:
			is_valid = SP.check_validity(owner, script_definition, "subject", owner)
			subjects_array.append(owner)
		_:
			var subjects_result = cfc.ov_utils.get_subjects(self, 
					get_property(SP.KEY_SUBJECT), stored_integer, run_type, trigger_details)
			if typeof(subjects_result) == TYPE_DICTIONARY:
				subjects_array = subjects_result["subjects"]
				var to_store = subjects_result.get("stored_integer", null)
				if to_store != null:
					 self.my_stored_integer = to_store
			else:
				subjects_array = subjects_result
			for c in subjects_array:
				if not SP.check_validity(c, script_definition, "subject", owner):
					is_valid = false
	if get_property(SP.KEY_NEEDS_SELECTION):
		if !interaction_authorized:
			user_interaction_status = CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER
			cfc.remove_ongoing_process(self, "_local_find_subjects")
			return []	
		if get_property(SP.KEY_SELECTION_IGNORE_SELF):
			subjects_array.erase(owner)
		var select_return = cfc.ov_utils.select_card(
				subjects_array,  script_definition, cfc.NMAP.board, self, run_type, stored_integer)
		# In case the owner card is still focused (say because script was triggered
		# on double-click and card was not moved
		# Then we need to ensure it's unfocused
		# Otherwise its z-index will make it draw on top of the popup.
		if owner as Card:
			if owner.state in [Card.CardState.FOCUSED_IN_HAND]:
				# We also reorganize the whole hand to avoid it getting
				# stuck like this.
				for c in owner.get_parent().get_all_cards():
					c.interruptTweening()
					c.reorganize_self()
		if select_return is GDScriptFunctionState: # Still working.
			select_return = yield(select_return, "completed")
		# If the return is not an array, it means that the selection
		# was cancelled (either because there were not enough cards
		# or because the player pressed cancel
		# in which case we consider the task invalid
		if typeof(select_return) == TYPE_ARRAY:
			subjects_array = select_return
		else:
			is_valid = false
			subjects_array = []
		user_interaction_status = CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER	
	
	#all other use cases are handled above. If our user_interaction_status is still unset,
	#it means no interaction was required
	if user_interaction_status ==  CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET:
		user_interaction_status =  CFConst.USER_INTERACTION_STATUS.DONE_INTERACTION_NOT_REQUIRED

	var to_exclude = get_property("subject_exclude", null)
	if to_exclude:
		var exclude_result = cfc.ov_utils.get_subjects(self, to_exclude, stored_integer, run_type, trigger_details)
		if typeof(exclude_result) == TYPE_ARRAY:
			for exclude in exclude_result:
				subjects_array.erase(exclude)
				
	cfc.remove_ongoing_process(self, "_local_find_subjects")
	return(subjects_array)


func _boardseek_subjects(stored_integer: int) -> Array:
	var subjects_array := []
	var subject_count = get_property(SP.KEY_SUBJECT_COUNT)
	if SP.VALUE_PER in str(subject_count):
		subject_count = count_per(
				get_property(SP.KEY_SUBJECT_COUNT),
				owner,
				get_property(get_property(SP.KEY_SUBJECT_COUNT)))
	elif str(subject_count) == SP.KEY_SUBJECT_COUNT_V_ALL:
		# When the value is set to -1, the seek will retrieve as many
		# cards as it can find, since the subject_count will
		# never be 0
		subject_count = -1
	# If the script requests a number of subjects equal to a
	# player-inputed number, we retrieve the integer
	# stored from the previous ask_integer task.
	elif str(subject_count) == SP.VALUE_RETRIEVE_INTEGER:
		subject_count = stored_integer
		if get_property(SP.KEY_IS_INVERTED):
			subject_count *= -1
	requested_subjects = int(subject_count)
	var subject_list := sort_subjects(cfc.NMAP.board.get_all_scriptables())
	for c in subject_list:
		if SP.check_validity(c, script_definition, "seek", owner):
			subjects_array.append(c)
			subject_count -= 1
			if subject_count == 0:
				break
	if requested_subjects > 0\
			and subjects_array.size() < requested_subjects:
		is_valid = false
	return(subjects_array)

func get_all_cards_from_containers(container_names) -> Array:
	var all_cards = []
	if (typeof(container_names) != TYPE_ARRAY):
		container_names = [container_names]
	
	for container_name in container_names:
		var container = cfc.NMAP.get(container_name, null)
		if !container:
			container = cfc.NMAP.board.get_grid(container_name)
		if container:
			all_cards += container.get_all_cards()
	
	return all_cards

func get_all_containers(container_names) -> Array:
	var result = []
	if (typeof(container_names) != TYPE_ARRAY):
		container_names = [container_names]
		
	for container_name in container_names:
		var container = cfc.NMAP.get(container_name, null)
		if container:
			result.append(container)
		else: #if it's not a pile, it might be a grid
			var grid = cfc.NMAP.board.get_grid(container_name)
			if grid:
				result.append(grid)
	return result


func _tutor_subjects(stored_integer: int) -> Array:
	var subjects_array := []
	# When we're tutoring for a subjects, we expect a
	# source CardContainer to have been provided.
	var subject_count = get_property(SP.KEY_SUBJECT_COUNT)
	if (owner.canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME ):
		var _tmp = 1
	if SP.VALUE_PER in str(subject_count):
		subject_count = count_per(
				get_property(SP.KEY_SUBJECT_COUNT),
				owner,
				get_property(get_property(SP.KEY_SUBJECT_COUNT)))
	elif str(subject_count) == SP.KEY_SUBJECT_COUNT_V_ALL:
		subject_count = -1
	elif str(subject_count) == SP.VALUE_RETRIEVE_INTEGER:
		subject_count = stored_integer
		if get_property(SP.KEY_IS_INVERTED):
			subject_count *= -1
	requested_subjects = subject_count
	var src_container = get_property(SP.KEY_SRC_CONTAINER)
	var subject_list := get_all_cards_from_containers(src_container)
	subject_list = sort_subjects(subject_list)
	for c in subject_list:
		if SP.check_validity(c, script_definition, "tutor", owner):
			subjects_array.append(c)
			subject_count -= 1
			if subject_count == 0:
				break
	if requested_subjects > 0:
		if get_property(SP.KEY_UP_TO):
			if subjects_array.size() < 1:
				is_valid = false
		else:
			if subjects_array.size() < requested_subjects:
				is_valid = false
	return(subjects_array)


func _index_seek_subjects(stored_integer: int) -> Array:
	var subjects_array := []
	# When we're seeking for index, we expect a
	# source CardContainer to have been provided.
	var src_container_names = get_property(SP.KEY_SRC_CONTAINER)
	#var src_containers:Array = get_all_containers(src_container_names)
	#var first_container: CardContainer = src_containers[0]
	var all_cards = get_all_cards_from_containers(src_container_names)
	var index = get_property(SP.KEY_SUBJECT_INDEX)
	if str(index) == SP.KEY_SUBJECT_INDEX_V_TOP:
		# We use the CardContainer functions, inctead of the Piles ones
		# to allow this value to be used on Hand classes as well
		#index = first_container.get_card_index(first_container.get_last_card())
		index = all_cards.size() - 1
	elif str(index) == SP.KEY_SUBJECT_INDEX_V_BOTTOM:
		#index = first_container.get_card_index(first_container.get_first_card())
		index = 0
	elif str(index) == SP.KEY_SUBJECT_INDEX_V_RANDOM:
		if (all_cards):
			index = CFUtils.randi() % (all_cards.size())
		else:
			index = -1
	elif str(index) == SP.VALUE_RETRIEVE_INTEGER:
		index = stored_integer
		if get_property(SP.KEY_IS_INVERTED):
			index *= -1
	# Just to prevent typos since we don't enforce integers on index
	elif not str(index).is_valid_integer():
		index = 0
	
	var subject_count = get_property(SP.KEY_SUBJECT_COUNT)
	# If the subject count is ALL, we retrieve as many cards as
	# possible after the specified index
	if SP.VALUE_PER in str(subject_count):
		subject_count = count_per(
				get_property(SP.KEY_SUBJECT_COUNT),
				owner,
				get_property(get_property(SP.KEY_SUBJECT_COUNT)))
	elif str(subject_count) == SP.KEY_SUBJECT_COUNT_V_ALL:
		# This variable is used to only retrieve as many cards
		# Up to the maximum that exist below the specified index
		var adjust_count = index
		# If we're searching from the "top", then the card will
		# have the last index. In that case the maximum would be
		# the whole deck
		# we have to ensure the value is a string, as KEY_SUBJECT_INDEX
		# can contain either integers of strings
		if str(get_property(SP.KEY_SUBJECT_INDEX)) == SP.KEY_SUBJECT_INDEX_V_TOP:
			adjust_count = 0
		subject_count = all_cards.size() - adjust_count
	elif str(subject_count) == SP.VALUE_RETRIEVE_INTEGER:
		subject_count = stored_integer
		if get_property(SP.KEY_IS_INVERTED):
			subject_count *= -1
	requested_subjects = subject_count
	
	#bail if the index is invalid
	if index ==-1:
		if requested_subjects > 0:
			if get_property(SP.KEY_IS_COST):
				is_valid = false
		return []
	
	# If KEY_SUBJECT_COUNT is more than 1, we seek a number
	# of cards from this index equal to the amount
	for iter in range(subject_count):
		# Specifically when retrieving cards from the bottom
		# we move up the pile, instead of down.
		# This is useful for effects which mention something like:
		# "...the last X cards from the deck"
		if str(get_property(SP.KEY_SUBJECT_INDEX)) != SP.KEY_SUBJECT_INDEX_V_TOP:
			if index + iter >  all_cards.size():
				break
			subjects_array.append(all_cards[index + iter])
		# When retrieving cards from any other index,
		# we always move down the pile from the starting index point.
		else:
			if index - iter < 0:
				break
			subjects_array.append(all_cards[index - iter])
	if requested_subjects > 0\
			and subjects_array.size() < requested_subjects:
		if get_property(SP.KEY_IS_COST):
			is_valid = false
		else:
			requested_subjects = subjects_array.size()
	return(subjects_array)


#Tries to find an arbitrary valid target for an ability (for cost check purposes)
#return the first we find on the board if we find one, null otherwise
func _dry_run_card_targeting(_script_definition):
	var all_cards = cfc.NMAP.board.get_all_cards()
	#TODO also check cards in piles ?
	for c in all_cards:
		var _is_valid = SP.check_validity(c, _script_definition, "subject", owner)
		if (_is_valid):
			return c
	return null

# Handles initiation of target seeking.
# and yields until it's found.
#
# Returns a Card object.
func _initiate_card_targeting() -> Card:
	cfc.add_ongoing_process(self, owner.canonical_name)
	# We wait a centisecond, to prevent the card's _input function from seeing
	# The double-click which started the script and immediately triggerring
	# the target completion
	yield(owner.get_tree().create_timer(0.1), "timeout")
	var all_cards = cfc.NMAP.board.get_all_cards()
	var valid_targets = []
	#TODO also check cards in piles ?
	for c in all_cards:
		var _is_valid = SP.check_validity(c, script_definition, "subject", owner)
		if (_is_valid):
			valid_targets.append(c)
	
	var target = null		
	if (valid_targets):			
		owner.targeting_arrow.initiate_targeting(valid_targets, self.script_definition)
		# We wait until the targetting has been completed to continue
		yield(owner.targeting_arrow,"target_selected")
		target = owner.targeting_arrow.target_object
		owner.targeting_arrow.target_object = null
		#owner_card.target_object = null
	

	cfc.remove_ongoing_process(self, owner.canonical_name)	
	return(target)


# Handles looking for intensifiers of a current effect via the board state
#
# Returns the amount of things the script is trying to count.
static func count_per(
			per_seek: String,
			script_owner: Card,
			per_definitions: Dictionary,
			_trigger_object = null) -> int:
	var per_msg := perMessage.new(
			per_seek,
			script_owner,
			per_definitions,
			_trigger_object)
	return(per_msg.found_things)


func retrieve_integer_subproperty(property, root, stored_integer:int = 0):
	return retrieve_integer_property(property, stored_integer,root)
	
func retrieve_integer_property(property, stored_integer:int = 0,root = null):
	var value = get_property(property, null, null, root)
	if !value:
		return 0
		
	if SP.VALUE_PER in str(value):
		value = count_per(
				value,
				owner,
				get_property(value))
	elif str(value) ==  SP.KEY_COUNT_PREVIOUS_SUBJECTS:
		value = self.prev_subjects.size()
	else:
		value = get_int_value (value, stored_integer)

	var plus_value = retrieve_integer_property("plus_" + property, stored_integer, root )
	if plus_value:
		value += plus_value		
	
	var max_value = retrieve_integer_property("max_" + property, stored_integer, root)
	if max_value:
		value = min(value, max_value)

	var min_value = retrieve_integer_property("min_" + property, stored_integer, root)
	if min_value:
		value = max(value, min_value)			
		
	return value	

static func get_int_value (value, retrieved_integer):
	if typeof(value) == TYPE_STRING and value == SP.VALUE_RETRIEVE_INTEGER:
		return retrieved_integer
	if typeof(value) == TYPE_INT:
		return value
	return int(value)

# Sorts the subjects list
# according to the directives in the following three keys
# * [KEY_SORT_BY](ScriptProperties#KEY_SORT_BY)
# * [KEY_SORT_NAME](ScriptProperties#KEY_SORT_NAME)
# * [KEY_SORT_DESCENDING](ScriptProperties#KEY_SORT_DESCENDING)
func sort_subjects(subject_list: Array) -> Array:
	var sorted_subjects := []
	var sort_by : String = get_property(SP.KEY_SORT_BY)
	if sort_by == "node_index":
		sorted_subjects = subject_list.duplicate()
	elif sort_by == "random":
		sorted_subjects = subject_list.duplicate()
		CFUtils.shuffle_array(sorted_subjects)
	# If the player forgot to fill in the SORT_NAME, we don't change the sort.
	# But we put out a warning instead
	elif not get_property(SP.KEY_SORT_NAME):
		print_debug("Warning: sort_by " + sort_by + ' requested '\
				+ 'but key ' + SP.KEY_SORT_NAME + ' is missing!')
	else:
		# I don't know if it's going to be a token name
		# or a property name, so I name the variable accordingly.
		var thing : String = get_property(SP.KEY_SORT_NAME)
		var sorting_list := []
		if sort_by == "property":
			for c in subject_list:
				# We create a list of dictionaries
				# because we cannot tell the sort_custom()
				# method what to search for
				sorting_list.append({
					"card": c,
					"value": c.get_property(thing)
				})
		if sort_by == "token":
			for c in subject_list:
				sorting_list.append({
					"card": c,
					"value": c.tokens.get_token_count(thing)
				})
		sorting_list.sort_custom(CFUtils,'sort_by_card_field')
		# Once we've sorted the items, we put just the card objects
		# in a new list, which we return to the player.
		for d in sorting_list:
			sorted_subjects.append(d.card)
	# If we want a descending list, we invert the subject list
	if get_property(SP.KEY_SORT_DESCENDING):
		sorted_subjects.invert()
	return(sorted_subjects)


# Goes through the provided scripts and replaces certain keyword values
# with variables retireved from specified location.
#
# This allows us for example to filter cards sought based on the properties
# of the card running the script.
func parse_replacements() -> void:
	# We need a deep copy because of all the nested dictionaries
	var wip_definitions := script_definition.duplicate(true)
	for key in wip_definitions:
		# We have to go through all the state filters
		# Because they have variable names
		if SP.FILTER_STATE in key:
			var state_filters_array : Array =  wip_definitions[key]
			for state_filters in state_filters_array:
				for filter in state_filters:
					# This branch checks for replacements for
					# filter_properties
					# We have to go to each dictionary for filter_properties
					# filters and check all values if they contain a
					# relevant keyword
					if SP.FILTER_PROPERTIES in filter:
						var property_filters = state_filters[filter]
						for property in property_filters:
							if str(property_filters[property]) in\
									[SP.VALUE_COMPARE_WITH_OWNER,
									SP.VALUE_COMPARE_WITH_TRIGGER]:
								var card: Card
								if str(property_filters[property]) ==\
										SP.VALUE_COMPARE_WITH_OWNER:
									card = owner
								else:
									card = trigger_object
								# Card name is always grabbed from
								# Card.canonical_name
								if property == "Name":
									property_filters[property] =\
											card.canonical_name
								else:
									property_filters[property] =\
											card.get_property(property)
					# This branch checks for replacements for
					# filter_tokens
					# We have to go to each dictionary for filter_tokens
					# filters and check all values if they contain a
					# relevant keyword
					if SP.FILTER_TOKENS in filter:
						var token_filters_array = state_filters[filter]
						for token_filters in token_filters_array:
							if str(token_filters.get(SP.FILTER_COUNT)) in\
									[SP.VALUE_COMPARE_WITH_OWNER,
									SP.VALUE_COMPARE_WITH_TRIGGER]:
								var card: Card
								if str(token_filters.get(SP.FILTER_COUNT)) ==\
										SP.VALUE_COMPARE_WITH_OWNER:
									card = owner
								else:
									card = trigger_object
								var owner_token_count :=\
										card.tokens.get_token_count(
										token_filters["filter_" + SP.KEY_TOKEN_NAME])
								token_filters[SP.FILTER_COUNT] =\
										owner_token_count
					if SP.FILTER_DEGREES in filter:
						if str(state_filters[filter]) == SP.VALUE_COMPARE_WITH_OWNER:
							var card: Card = owner
							state_filters[filter] = card.card_rotation
						if str(state_filters[filter]) == SP.VALUE_COMPARE_WITH_TRIGGER:
							var card: Card = trigger_object
							state_filters[filter] = card.card_rotation
					if SP.FILTER_FACEUP in filter:
						if str(state_filters[filter]) == SP.VALUE_COMPARE_WITH_OWNER:
							var card: Card = owner
							state_filters[filter] = card.is_faceup
						if str(state_filters[filter]) == SP.VALUE_COMPARE_WITH_TRIGGER:
							var card: Card = trigger_object
							state_filters[filter] = card.is_faceup
					if SP.FILTER_PARENT in filter:
						if str(state_filters[filter]) == SP.VALUE_COMPARE_WITH_OWNER:
							var card: Card = owner
							state_filters[filter] = card.get_parent()
						if str(state_filters[filter]) == SP.VALUE_COMPARE_WITH_TRIGGER:
							var card: Card = trigger_object
							state_filters[filter] = card.get_parent()
	script_definition = wip_definitions

func serialize_to_json() -> Dictionary:
	var result = {}
	
	result["owner"] = cfc.serialize_object(owner)

	
	result["subjects"] = []
	for subject in subjects:
		result["subjects"].append(cfc.serialize_object(subject))
	
	result["script_name"] = script_name
# Storage for all details of the task definition
	result ["script_definition"] = script_definition
# Used by the ScriptingEngine to know if the task
# has finished processing targetting and optional confirmations
	result["is_primed"] = is_primed
# If true if this task is valid to run.
# A task is invalid to run if some filter does not match.
	result["is_valid"] = is_valid

	result["requested_subjects"] = requested_subjects


	result["trigger_object"] = cfc.serialize_object(trigger_object)

	result["prev_subjects"] = []
	for subject in prev_subjects:
		result["prev_subjects"].append(cfc.serialize_object(subject))

	result["all_prev_subjects"] = []
	for subject in all_prev_subjects:
		result["all_prev_subjects"].append(cfc.serialize_object(subject))
		
	
	return result
