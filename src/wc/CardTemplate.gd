class_name WCCard
extends Card

var owner_hero_id  := 0 setget set_owner_hero_id, get_owner_hero_id
var controller_hero_id  := 0 setget set_controller_hero_id, get_controller_hero_id

func set_owner_hero_id(hero_id:int):
	owner_hero_id = hero_id
	
func get_owner_hero_id() -> int:
	return owner_hero_id	

func set_controller_hero_id(hero_id:int):
	controller_hero_id = hero_id
	
func get_controller_hero_id() -> int:
	return controller_hero_id	

func setup() -> void:
	.setup()
	_init_groups()	
	set_card_art()

func set_card_art():
	var filename = cfc.get_img_filename(get_property("_code"))
	if (filename):
		card_front.set_card_art(filename)


func _init_groups() -> void :
	var type_code = properties.get("type_code", "")
	
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	
	for group in groups:
		self.add_to_group(group)
		
func common_post_move_scripts(new_host: String, old_host: String, move_tags: Array) -> void:
	#change controller as needed
	var new_grid = get_grid_name()
	var new_hero_id = 0
	if (new_grid):
		new_hero_id = gameData.get_grid_owner_hero_id(new_grid)
	else:
		#attempt for piles/containers
		new_hero_id = gameData.get_grid_owner_hero_id(new_host)
	self.set_controller_hero_id(new_hero_id)
	
	#init owner once and only once, if not already done
	if (not self.get_owner_hero_id()):
		self.set_owner_hero_id(new_hero_id)		
		
		
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
					if (destination == cfc.NMAP.board) and (parentHost.is_in_group("hands")):
						move_to(parentHost)
						if (check_play_costs() != CFConst.CostsState.IMPOSSIBLE):
							cfc.card_drag_ongoing = null
							execute_scripts()
					else :	
						move_to(destination)
					_focus_completed = false
		else:
			_process_more_card_inputs(event)
		

# Game specific code and/or shortcuts
func readyme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
	var retcode = set_card_rotation(0, toggle, start_tween, check, tags)
	return retcode
	
func exhaustme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
	var retcode = set_card_rotation(90, toggle, start_tween, check, tags)
	return retcode	

func is_ready() :
	return get_card_rotation() == 0

func is_exhausted():
	return (not is_ready())	
	
func add_threat(threat : int):
	tokens.mod_token("threat",threat)	

func common_pre_execution_scripts(_trigger: String, _trigger_details: Dictionary) -> void:
	match _trigger:
		"automated_enemy_attack":
			gameData.compute_potential_defenders()

func can_defend():
	if is_exhausted() : return false

	var type_code = properties.type_code
	if type_code != "hero" and type_code != "ally": return false
	
	return true

func die():
	var type_code = properties.get("type_code", "")
	match type_code:
		"hero":
			gameData.hero_died(self)
		"ally":
			move_to(cfc.NMAP["discard1"]) #TODO per hero
		"minion":
			move_to(cfc.NMAP["discard_villain"])	
		"villain":
			gameData.villain_died(self)
			
	return CFConst.ReturnCode.OK		

# This function can be overriden by any class extending Card, in order to provide
# a way of running special functions on an extended scripting engine.
#
# It is called after the scripting engine is initiated, but before it's run
# the first time
#
# Used to hijack the scripts at runtime if needed
# Current use case: check manapool before asking to pay for cards
func common_pre_run(_sceng) -> void:
	var scripts_queue: Array = _sceng.scripts_queue
	var new_queue: Array = []
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition
		
		var current_hero_id = gameData.get_current_hero_id()
		for v in ["hand", "encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
			#TODO move to const
			WCUtils.search_and_replace(script_definition, v, v+str(self.owner_hero_id), true)
	
		
		match script_definition["name"]:
			# To pay for cards: We check if the manapool has some mana
			# If so, use that in "priority" and reduce the actual cost of the card
			# We then replace the "pay" trigger with a combination of
			# 1) discard the appropriate number of cards from hand (minored by what's available in manapool)
			# 2) empty the manapool
			"pay_regular_cost":
				var additional_task := ScriptTask.new(
					script.owner,
					{"name": "pay_from_manapool"}, #TODO more advanced
					script.trigger_object,
					script.trigger_details)
				new_queue.append(additional_task)
					
				var new_script = pay_regular_cost_replacement(script_definition)
				if (new_script) :
					script.script_definition = new_script
					script.script_name = script.get_property("name") #TODO something cleaner? Maybe part of the script itself?
					new_queue.append(script)
			_:
				new_queue.append(task)
	_sceng.scripts_queue = new_queue	

func pay_regular_cost_replacement(script_definition: Dictionary) -> Dictionary:	
	var owner_hero_id = self.get_owner_hero_id()	
	var manapool:ManaPool = gameData.get_team_member(owner_hero_id)["manapool"]
	var manacost:ManaCost = ManaCost.new()
	var cost = script_definition["cost"]
	if cost == "card_cost":
		cost = self.get_property("cost")
	manacost.init_from_expression(cost) #TODO better name?
	var missing_mana:ManaCost = manapool.compute_missing(manacost)
	
	var result = {}
	#Manapool not enough, need to discard cards
	if missing_mana.is_negative() :
		# var current_hero_id = gameData.get_current_hero_id()
		#Replace the script with a move condition
		result ={
				"name": "move_card_to_container",
				"is_cost": true,
				"subject": "index",
				"subject_count": "all",
				"subject_index": "top",
				SP.KEY_NEEDS_SELECTION: true,
				SP.KEY_SELECTION_COUNT: -missing_mana.pool[ManaCost.Resource.UNCOLOR], #TODO put real missing cost here
				SP.KEY_SELECTION_TYPE: "equal",
				SP.KEY_SELECTION_OPTIONAL: false,
				SP.KEY_SELECTION_IGNORE_SELF: true,
				"src_container": "hand" + str(owner_hero_id),
				"dest_container": "discard" + str(owner_hero_id),
			}		

	return result	

func get_grid_name():
	if (_placement_slot):
		return _placement_slot.get_grid_name()
	return null	
