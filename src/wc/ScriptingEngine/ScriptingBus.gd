# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCScriptingBus
extends Node

# Base framework signals (moved from src/core/ScriptingBus.gd)
# Emitted whenever a card is rotated
# warning-ignore:unused_signal
signal card_rotated(card,details)
# Emitted whenever a card flips up/down
# warning-ignore:unused_signal
signal card_flipped(card,details)
# Emitted whenever a card is viewed while face-down
# warning-ignore:unused_signal
signal card_viewed(card,details)
# Emited whenever a card is moved to the board
# warning-ignore:unused_signal
signal card_moved_to_board(card,details)
# Emited whenever a card is moved to a pile
# warning-ignore:unused_signal
signal card_moved_to_pile(card,details)
# Emited whenever a card is moved to a hand
# warning-ignore:unused_signal
signal card_moved_to_hand(card,details)
# Emited whenever a card's tokens are modified
# warning-ignore:unused_signal
signal card_token_modified(card,details)
# Emited whenever a card attaches to another
# warning-ignore:unused_signal
signal card_attached(card,details)
# Emited whenever a card unattaches from another
# warning-ignore:unused_signal
signal card_unattached(card,details)
# Emited whenever a card properties are modified
# warning-ignore:unused_signal
signal card_properties_modified(card,details)
# Emited whenever a new card has finished being added to the gane through the scripting engine
# warning-ignore:unused_signal
signal card_spawned(card,details)
# Emited whenever a card is targeted by another card.
# This signal is not fired by this card directly like all the others,
# but instead by the card doing the targeting.
# warning-ignore:unused_signal
signal card_targeted(card,details)
# warning-ignore:unused_signal
signal counter_modified(card,details)
# warning-ignore:unused_signal
signal shuffle_completed(card_container,details)

# warning-ignore:unused_signal
signal selection_window_opened(selection_window, details)
# warning-ignore:unused_signal
signal optional_window_opened(optional_window, details)
# warning-ignore:unused_signal
signal optional_window_closed(optional_window, details)

# warning-ignore:unused_signal
signal initiated_targeting(card)
# warning-ignore:unused_signal
signal target_selected(owner, details)

# warning-ignore:unused_signal
signal about_to_reveal(encounter, details)

# This signal is not triggerring init_scripting_event()
# It is used to trigger the execute_scripts functions on the various scriptable objects
signal scripting_event_about_to_trigger(trigger_card, trigger, details)
signal scripting_event_triggered(trigger_card, trigger, details)

# Game-specific signals
# Emited whenever the card is played manually or via card effect.
# Since a card might be "played" from any source and to many possible targets
# we use a specialized signal to trigger effects which fire after playing cards
# warning-ignore:unused_signal
signal card_played(card,details)
# warning-ignore:unused_signal
signal card_removed(card,details)
# warning-ignore:unused_signal
signal card_selected(selection_window, details)
# warning-ignore:unused_signal
signal selection_window_canceled(selection_window, details)
# warning-ignore:unused_signal
signal setup_complete()

# warning-ignore:unused_signal
signal interrupt(card, details)
# warning-ignore:unused_signal
signal card_damaged(card,details)

#Game Phases
# warning-ignore:unused_signal
signal step_about_to_start(details)
# warning-ignore:unused_signal
signal step_started(details)
# warning-ignore:unused_signal
signal step_about_to_end(details)
# warning-ignore:unused_signal
signal step_ended(details)

#GUI and game Interface signals
# warning-ignore:unused_signal
signal current_playing_hero_changed(details) #before, after

# warning-ignore:unused_signal
signal all_clients_game_loaded(details) #status Dict for all players

# warning-ignore:unused_signal
signal manapool_modified(details)

# warning-ignore:unused_signal
signal enemy_initiates_attack(card,details)
# warning-ignore:unused_signal
signal enemy_initiates_scheme(card,details)
# warning-ignore:unused_signal
signal enemy_attack_happened (card,details)
# warning-ignore:unused_signal
signal enemy_scheme_happened (card,details)

# warning-ignore:unused_signal
signal villain_step_one_threat_added(card, details)

# warning-ignore:unused_signal
signal thwarted (card,details)
# warning-ignore:unused_signal
signal character_dies(card, details)
# warning-ignore:unused_signal
signal round_ended()
# warning-ignore:unused_signal
signal phase_ended(details)
# warning-ignore:unused_signal
signal stack_event_deleted(event)

#todo should be dynamic?
# warning-ignore:unused_signal
signal minion_moved_to_board(card,details)
# warning-ignore:unused_signal
signal main_scheme_moved_to_board(card,details)
# warning-ignore:unused_signal
signal player_scheme_moved_to_board(card,details)
# warning-ignore:unused_signal
signal side_scheme_moved_to_board(card,details)
# warning-ignore:unused_signal
signal villain_moved_to_board(card,details)
# warning-ignore:unused_signal
signal hero_moved_to_board(card,details)
# warning-ignore:unused_signal
signal alter_ego_moved_to_board(card,details)
# warning-ignore:unused_signal
signal ally_moved_to_board(card,details)
# warning-ignore:unused_signal
signal upgrade_moved_to_board(card,details)
# warning-ignore:unused_signal
signal support_moved_to_board(card,details)
# warning-ignore:unused_signal
signal attachment_moved_to_board(card,details)
# warning-ignore:unused_signal
signal treachery_moved_to_board(card,details)
# warning-ignore:unused_signal
signal obligation_moved_to_board(card,details)
# warning-ignore:unused_signal
signal environment_moved_to_board(card,details)

# warning-ignore:unused_signal
signal card_defeated(card,details)

# warning-ignore:unused_signal
signal identity_changed_form(card, details)

# warning-ignore:unused_signal
signal attack_happened(card, details)
# warning-ignore:unused_signal
signal basic_attack_happened(card, details)
# warning-ignore:unused_signal
signal defense_happened(card, details)

#todo should be dynamic?

# looking for this signal in the code ? Triggered typically by type + "_died"
# warning-ignore:unused_signal
signal minion_died(card,details)
# warning-ignore:unused_signal
signal enemy_died(card,details)
# warning-ignore:unused_signal
signal ally_died(card,details)
# warning-ignore:unused_signal
signal hero_died(card,details)
# warning-ignore:unused_signal
signal alter_ego_died(card,details)

# Base framework functionality (moved from src/core/ScriptingBus.gd)
func _ready():
	for s in get_signal_list():
		if s.name == "scripting_event_triggered":
			continue
		if s.name == "scripting_event_about_to_trigger":
			continue
		if s.args.size() == 2:
			# warning-ignore:return_value_discarded
			connect(s.name, self, "init_scripting_event", [s.name])
		elif s.args.size() == 1:
			# This means the signal has no details being sent by defult, so we connect it using a dummy dictionary instead
			connect(s.name, self, "init_scripting_event", [{}, s.name])
		elif s.args.size() == 0:
			# This means the signal sends no args by default, so we just provide dummy vars
			connect(s.name, self, "init_scripting_event", [null, {}, s.name])

func init_scripting_event(trigger_object: Card = null, details: Dictionary = {}, trigger: String = '') -> void:
	if trigger == '':
		push_error("WARN: scripting event received with empty trigger name")
		return
	# We use Godot groups to ask every card to check if they
	# have [ScriptingEngine] triggers for this signal.
	#
	# I don't know why, but if I use simply call_group(), this will
	# not execute on a "self" subject
	# when the trigger card has a grid_autoplacement set, and the player
	# drags the card on the grid itself. If the player drags the card
	# To an empty spot, it works fine
	# It also fails to execute if I use any other flag than GROUP_CALL_UNIQUE
#	for card in cfc.get_tree().get_nodes_in_group("cards"):
#		card.execute_scripts(trigger_object,trigger,details)
#	# If we need other objects than cards to trigger scripts via signals
#	# add them to the 'scriptables' group ang ensure they have
#	# an "execute_scripts" function
#	for card in cfc.get_tree().get_nodes_in_group("scriptables"):
#		card.execute_scripts(trigger_object,trigger,details)
#		cfc.get_tree().call_group_flags(SceneTree.GROUP_CALL_UNIQUE  ,"cards",
#				"execute_scripts",trigger_card,trigger,details)

	#cleanup manually paid stuff before propagating trigger
	if (details.has("network_prepaid")):
		details.erase("network_prepaid")

	#fire a first "pre" event for engine abilities that need to trigger before cards
	emit_signal("scripting_event_about_to_trigger", trigger_object, trigger, details)

	#then fire the actual event
	emit_signal("scripting_event_triggered", trigger_object, trigger, details)
