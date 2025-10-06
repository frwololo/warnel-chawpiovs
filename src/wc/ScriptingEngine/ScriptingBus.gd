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
signal setup_complete()

# warning-ignore:unused_signal
signal before_damage(details)
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
signal all_clients_game_loaded(details) #status Dict for all players

# warning-ignore:unused_signal
signal manapool_modified(details)


