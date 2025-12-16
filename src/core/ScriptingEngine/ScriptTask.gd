# This contains information about one specific task requested by the card
# automation
#
# It also contains methods to return properties of the task and to find
# the required objects in the game
class_name ScriptTask
extends ScriptObject


# If true if this task has been confirmed to run by the player
# Only relevant for optional tasks (see [SP].KEY_IS_OPTIONAL)
var is_accepted := true
var is_skipped := false
var is_cost := false
var is_else := false
var needs_subject := false

#if this script generates some object outcome, it will be stored here
var process_result = null


# prepares the script_definition needed by the task to function.
func _init(owner,
		script: Dictionary,
		_trigger_object,
		_trigger_details).(owner, script, _trigger_object, _trigger_details) -> void:
	# The function name to be called gets its own var
	script_name = get_property("name")

	is_cost = get_property(SP.KEY_IS_COST)
	needs_subject = get_property(SP.KEY_NEEDS_SUBJECT)
	is_else = get_property(SP.KEY_IS_ELSE)
	if not SP.filter_trigger(
			script,
			trigger_object,
			owner,
			trigger_details):
		is_skipped = true

#Prime is the act of choosing subjects and valid targets in preparation for the script
func prime(_prev_subjects: Array, run_type: int, sceng_stored_int: int, _all_prev_subjects: Array) -> void:
	# We store the prev_subjects we sent to this task in case we need to
	# refer to them later

	cfc.add_ongoing_process(self)

	var only_cost_check = ((run_type == CFInt.RunType.COST_CHECK) or
		 (run_type == CFInt.RunType.BACKGROUND_COST_CHECK))
	
	set_prev_subjects(_prev_subjects)
	all_prev_subjects = _all_prev_subjects
	if ((!only_cost_check
			and not is_cost and not needs_subject)
			# This is the typical spot we're checking
			# for non-cost optional confirmations.
			# The only time we're testing here during a cost-dry-run
			# is when its an "is_cost" task requiring targeting.
			# We want to avoid targeting and THEN ask for confirmation.
			# Non-targeting is_cost tasks are confirmed in the
			# ScriptingEngine loop
			or (only_cost_check
			and (is_cost or needs_subject)
			and get_property(SP.KEY_SUBJECT) == "target")):
		# If this task has been specified as optional
		# We check if the player confirms it, before looking for targets
		# We check for optional confirmations only during
		# The normal run (i.e. not in a cost dry-run)
		var confirm_return = check_confirm()
		if confirm_return is GDScriptFunctionState: # Still working.
			yield(confirm_return, "completed")
	# If any confirmation is accepted, then we only draw a target
	# if either the card is a cost and we're doing a cost-dry run,
	# or the card is not a cost and we're in the normal run
	if not is_skipped and is_accepted and (!only_cost_check
			or (only_cost_check
			and (is_cost or needs_subject))):
		# We discover which other card this task will affect, if any
		var ret =_find_subjects(sceng_stored_int, run_type)
		if ret is GDScriptFunctionState && ret.is_valid(): # Still working.
			ret = yield(ret, "completed")
	#print_debug(str(subjects), str(cost_dry_run))
	# We emit a signal when done so that our ScriptingEngine
	# knows we're ready to continue
	is_primed = true
	script_definition = cfc.ov_utils.parse_post_prime_replacements(self)	
	cfc.remove_ongoing_process(self)
	emit_signal("primed")
#	print_debug("skipped: " + str(is_skipped) +  " valid: " + str(is_valid))

func check_confirm() -> bool:
	var owner_name = ''
	if is_instance_valid(owner):
		owner_name = owner.canonical_name
	var confirm_return = gameData.confirm(
			owner,
			script_definition,
			owner_name,
			script_name)
	cfc.add_ongoing_process(self)		
	if confirm_return is GDScriptFunctionState: # Still working.
		is_accepted = yield(confirm_return, "completed")
	cfc.remove_ongoing_process(self)	
	return(is_accepted)

func serialize_to_json():
	var result = .serialize_to_json()

# Stores the details arg passed the signal to use for filtering
	result["trigger_details"] = trigger_details
# If true if this task has been confirmed to run by the player
# Only relevant for optional tasks (see [SP].KEY_IS_OPTIONAL)
	result["is_accepted"] = is_accepted
	result["is_skipped"] = is_skipped
	result["is_cost"] = is_cost
	result["is_else"] = is_else
	result["needs_subject"] = needs_subject

#if this script generates some object outcome, it will be stored here
	result["process_result"] = "TODO"
	
	return result
