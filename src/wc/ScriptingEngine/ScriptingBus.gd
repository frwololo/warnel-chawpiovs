class_name WCScriptingBus
extends ScriptingBus

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

signal card_defeated(card,details)
# warning-ignore:unused_signal

#todo should be dynamic?
# warning-ignore:unused_signal
# looking for this signal in the code ? Triggered typically by type + "_died"
signal minion_died(card,details)
# warning-ignore:unused_signal
signal ally_died(card,details)
# warning-ignore:unused_signal
signal hero_died(card,details)
# warning-ignore:unused_signal
signal alter_ego_died(card,details)
