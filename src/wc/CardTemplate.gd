class_name WCCard
extends Card


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


func setup() -> void:
	.setup()
	set_card_art()

func set_card_art():
	var filename = cfc.get_img_filename(get_property("_code"))
	if (filename):
		card_front.set_card_art(filename)
		
		
# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
	if event is InputEventMouseButton and cfc.NMAP.has("board"):
		# because of https://github.com/godotengine/godot/issues/44138
		# we need to double check that the card which is receiving the
		# gui input, is actually the one with the highest index.
		# We use our mouse pointer which is tracking this info.
		if cfc.NMAP.board.mouse_pointer.current_focused_card \
				and self != cfc.NMAP.board.mouse_pointer.current_focused_card:
			cfc.NMAP.board.mouse_pointer.current_focused_card._on_Card_gui_input(event)
		# If the player left clicks, we need to see if it's a double-click
		# or a long click
		elif event.is_pressed() \
				and event.get_button_index() == 1 \
				and not buttons.are_hovered() \
				and not tokens.are_hovered():
			# If it's a double-click, then it's not a card drag
			# But rather it's script execution
			if event.doubleclick\
					and ((check_play_costs() != CFConst.CostsState.IMPOSSIBLE
					and get_state_exec() == "hand")
					or get_state_exec() == "board"):
				cfc.card_drag_ongoing = null
				execute_scripts()
			# If it's a long click it might be because
			# they want to drag the card
			else:
				if state in [CardState.FOCUSED_IN_HAND,
						CardState.FOCUSED_ON_BOARD,
						CardState.FOCUSED_IN_POPUP]:
					# But first we check if the player does a long-press.
					# We don't want to start dragging the card immediately.
					cfc.card_drag_ongoing = self
					# We need to wait a bit to make sure the other card has a chance
					# to go through their scripts
					yield(get_tree().create_timer(0.1), "timeout")
					# If this variable is still set to true,
					# it means the mouse-button is still pressed
					# We also check if another card is already selected for dragging,
					# to prevent from picking 2 cards at the same time.
					if cfc.card_drag_ongoing == self:
						if state == CardState.FOCUSED_IN_HAND\
								and  _has_targeting_cost_hand_script()\
								and check_play_costs() != CFConst.CostsState.IMPOSSIBLE:
							cfc.card_drag_ongoing = null
							var _sceng = execute_scripts()
						elif state == CardState.FOCUSED_IN_HAND\
								and (disable_dragging_from_hand
								or check_play_costs() == CFConst.CostsState.IMPOSSIBLE):
							cfc.card_drag_ongoing = null
						elif state == CardState.FOCUSED_ON_BOARD \
								and disable_dragging_from_board:
							cfc.card_drag_ongoing = null
						elif state == CardState.FOCUSED_IN_POPUP \
								and disable_dragging_from_pile:
							cfc.card_drag_ongoing = null
						else:
							# While the mouse is kept pressed, we tell the engine
							# that a card is being dragged
							_start_dragging(event.position)
		# If the mouse button was released we drop the dragged card
		# This also means a card clicked once won't try to immediately drag
		elif not event.is_pressed() and event.get_button_index() == 1:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			$Control.set_default_cursor_shape(Input.CURSOR_ARROW)
			cfc.card_drag_ongoing = null
			match state:
				CardState.DRAGGED:
					# if the card was being dragged, it's index is very high
					# to always draw above other objects
					# We need to reset it to the default of 0
					z_index = 0
					for attachment in self.attachments:
						attachment.z_index = 0

					var destination = cfc.NMAP.board
					if potential_container:
						destination = potential_container
						potential_container.highlight.set_highlight(false)
					
					#TODO
					#NOTE ERWAN
					#Modified here so that drag to board mimics the effect of a double click	
					var parentHost = get_parent()
					if (destination == cfc.NMAP.board) and (parentHost == cfc.NMAP.hand):
						move_to(cfc.NMAP.hand)
						if (check_play_costs() != CFConst.CostsState.IMPOSSIBLE):
							cfc.card_drag_ongoing = null
							execute_scripts()
					else :	
						move_to(destination)
					_focus_completed = false
		else:
			_process_more_card_inputs(event)
		
