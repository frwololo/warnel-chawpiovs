class_name WCScriptTask
extends ScriptTask

# This is used to track all the previous subjects so far.
var all_prev_subjects := []

# User interaction status (moved from src/core ScriptObject modifications)
var user_interaction_status = CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET

# Additional variables from src/core ScriptObject modifications
var interaction_authorized_user_id
var user
var trigger: String
var my_stored_integer = null

# prepares the script_definition needed by the task to function.
func _init(owner,
		script: Dictionary,
		_trigger_object,
		_trigger_details).(owner, script, _trigger_object, _trigger_details) -> void:
	# Initialize trigger from trigger_details (moved from src/core ScriptObject modifications)
	if _trigger_details.has("trigger_type"):
		trigger = _trigger_details["trigger_type"]
	else:
		trigger = ""

# Keep track of all the previous subjects so far.
func store_all_prev_subjects(_all_prev_subjects):
	all_prev_subjects = _all_prev_subjects

# Override get_property to support root parameter and if/then/else logic
# (moved from src/core modifications)
func get_property(property: String, default = null, subscript_definition = null, root = null):
	if default == null:
		default = SP.get_default(property)

	var result = ""
	if (subscript_definition != null):
		#used for recursive calls of if/then/else
		result = subscript_definition
	elif root != null:
		result = root.get(property, default)
	else:
		result = script_definition.get(property, default)

	#if then else special case. Todo could this maybe go into a more generic location to work on all script variables ?
	if (typeof(result) == TYPE_DICTIONARY):
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

# Network prepaid functionality (moved from src/core modifications)
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

# Override _find_subjects to add run_type parameter and network support
# (moved from src/core modifications)
func _find_subjects(stored_integer := 0, run_type: int = CFInt.RunType.NORMAL) -> Array:
	#TODO MULTIPLAYER_MODIFICATION
	var prepaid = _network_prepaid()
	if (null != prepaid):
		user_interaction_status = CFConst.USER_INTERACTION_STATUS.DONE_NETWORK_PREPAID
		subjects = prepaid
		return prepaid

	var result = _local_find_subjects(stored_integer, run_type)

	if result is GDScriptFunctionState: # Still working.
		result = yield(result, "completed")

	subjects = result
	return subjects

#runs "find_subjects" locally, does not store the result
#this allows to run a "find subjects" activity within
#the context of this script, without impacting it
#useful for sub scripts
func _local_find_subjects(stored_integer := 0, run_type: int = CFInt.RunType.NORMAL, overrides: Dictionary = {}):
	cfc.add_ongoing_process(self, "_local_find_subjects")
	var subjects_array := []

	var interaction_authority: UserInteractionAuthority = UserInteractionAuthority.new(owner, trigger_object, trigger, trigger_details, run_type)
	var interaction_authorized = interaction_authority.interaction_authorized()

	for key in overrides:
		self.script_definition[key] = overrides[key]

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
		# Every task retrieves the subjects used in the previous task.
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
				subjects_array, script_definition, cfc.NMAP.board, self, run_type, stored_integer)
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
	if user_interaction_status == CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET:
		user_interaction_status = CFConst.USER_INTERACTION_STATUS.DONE_INTERACTION_NOT_REQUIRED

	var to_exclude = get_property("subject_exclude", null)
	if to_exclude:
		var exclude_result = cfc.ov_utils.get_subjects(self, to_exclude, stored_integer, run_type, trigger_details)
		if typeof(exclude_result) == TYPE_ARRAY:
			for exclude in exclude_result:
				subjects_array.erase(exclude)

	cfc.remove_ongoing_process(self, "_local_find_subjects")
	return(subjects_array)

# Dry run card targeting for background cost checks
func _dry_run_card_targeting(_script_definition):
	var all_cards = cfc.NMAP.board.get_all_cards()
	#TODO also check cards in piles ?
	for c in all_cards:
		var _is_valid = SP.check_validity(c, _script_definition, "subject", owner)
		if (_is_valid):
			return c
	return null

# Override _tutor_subjects to pass owner to check_validity and support multiple containers
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
	var src_container_names = get_property(SP.KEY_SRC_CONTAINER)
	var all_cards = get_all_cards_from_containers(src_container_names)
	var subject_list := sort_subjects(all_cards)
	for c in subject_list:
		if get_property(SP.FILTER_EXCLUDE_SELF) and c == owner:
			continue
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

# Override _index_seek_subjects to pass owner to check_validity and support multiple containers
func _index_seek_subjects(stored_integer: int) -> Array:
	var subjects_array := []
	# When we're seeking for index, we expect a
	# source CardContainer to have been provided.
	var src_container_names = get_property(SP.KEY_SRC_CONTAINER)
	var all_containers = get_all_containers(src_container_names)
	var all_cards = get_all_cards_from_containers(src_container_names)
	var index = get_property(SP.KEY_SUBJECT_INDEX)
	if str(index) == SP.KEY_SUBJECT_INDEX_V_TOP:
		# We use the CardContainer functions, instead of the Piles ones
		# to allow this value to be used on Hand classes as well
		if all_containers.size() > 0:
			index = all_containers[0].get_card_index(all_containers[0].get_last_card())
		else:
			index = 0
	elif str(index) == SP.KEY_SUBJECT_INDEX_V_BOTTOM:
		if all_containers.size() > 0:
			index = all_containers[0].get_card_index(all_containers[0].get_first_card())
		else:
			index = 0
	elif str(index) == SP.KEY_SUBJECT_INDEX_V_RANDOM:
		if all_containers.size() > 0:
			index = all_containers[0].get_card_index(all_containers[0].get_random_card())
		else:
			index = 0
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
	# If KEY_SUBJECT_COUNT is more than 1, we seek a number
	# of cards from this index equal to the amount
	for iter in range(subject_count):
		# Specifically when retrieving cards from the bottom
		# we move up the pile, instead of down.
		# This is useful for effects which mention something like:
		# "...the last X cards from the deck"
		if str(get_property(SP.KEY_SUBJECT_INDEX)) == SP.KEY_SUBJECT_INDEX_V_BOTTOM:
			if all_containers.size() > 0 and index + iter < all_cards.size():
				subjects_array.append(all_cards[index + iter])
		# When retrieving cards from any other index,
		# we always move down the pile from the starting index point.
		else:
			if index - iter >= 0 and index - iter < all_cards.size():
				subjects_array.append(all_cards[index - iter])
	if requested_subjects > 0\
			and subjects_array.size() < requested_subjects:
		if get_property(SP.KEY_IS_COST):
			is_valid = false
		else:
			requested_subjects = subjects_array.size()
	return(subjects_array)

# Helper functions for container operations (moved from src/core modifications)
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

# Override _boardseek_subjects to pass owner to check_validity
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
		if get_property(SP.FILTER_EXCLUDE_SELF) and c == owner:
			continue
		if SP.check_validity(c, script_definition, "seek", owner):
			subjects_array.append(c)
			subject_count -= 1
			if subject_count == 0:
				break
	if requested_subjects > 0\
			and subjects_array.size() < requested_subjects:
		is_valid = false
	return(subjects_array)

# Retrieve integer property with support for plus/min/max modifiers
func retrieve_integer_property(property, stored_integer: int = 0, root = null):
	var value = get_property(property, null, null, root)
	if !value:
		return 0

	if SP.VALUE_PER in str(value):
		value = count_per(
				value,
				owner,
				get_property(value))
	elif str(value) == SP.KEY_COUNT_PREVIOUS_SUBJECTS:
		value = self.prev_subjects.size()
	else:
		value = get_int_value(value, stored_integer)

	var plus_value = retrieve_integer_property("plus_" + property, stored_integer, root)
	if plus_value:
		value += plus_value

	var max_value = retrieve_integer_property("max_" + property, stored_integer, root)
	if max_value:
		value = min(value, max_value)

	var min_value = retrieve_integer_property("min_" + property, stored_integer, root)
	if min_value:
		value = max(value, min_value)

	return value

static func get_int_value(value, retrieved_integer):
	if typeof(value) == TYPE_STRING and value == SP.VALUE_RETRIEVE_INTEGER:
		return retrieved_integer
	if typeof(value) == TYPE_INT:
		return value
	return int(value)
