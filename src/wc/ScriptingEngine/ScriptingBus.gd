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
signal selection_window_opened(selection_window, details)
# warning-ignore:unused_signal
signal card_selected(selection_window, details)

# warning-ignore:unused_signal
signal setup_complete()

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
