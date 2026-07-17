# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCCard
extends Card

const _SPINBOX_SCENE_FILE = CFConst.PATH_CUSTOM + "cards/SpinPanel.tscn"
const _SPINBOX_SCENE = preload(_SPINBOX_SCENE_FILE)

#this is emitted from front_card_container
# warning-ignore:unused_signal
signal card_texture_changed(card)

var has_focus = false

# -1 uninitialized, 0 Villain, any positive value: hero
var _owner_hero_id  := -1
var _controller_hero_id  := -1 setget set_controller_hero_id, get_controller_hero_id

var _check_play_costs_cache: Dictionary = {}
var _cache_resource_value: = {}
var _cache_refresh_needed:= false
var _cached_all_traits = null
var _script_alter_cache := {}

var _on_ready_load_from_json:Dictionary = {}

#marvel champions specific variables
var _is_exhausted:= false
var _is_boost:=false
var _is_inactive_attachment:= false

#an array of ManaCost variables representing everything that's been used to pay for this card
var _last_paid_with := []
var _last_cost: ManaCost = null
var last_overpay
var my_last_target = null

var extra_scripts := {}
var extra_script_uid := 0
var script_variables = {}

# The node with number manipulation box on this card
var spinbox = null
#healthbar on top of characters, allies, villains, etc...
var healthbar
var info_icon
var side_icons
var _unused_nodes_detached:= false

var _removed_control_nodes:= []

var hints:= []

#activity script tied to a villain/minion attacking or scheming
#might be used for other stuff eventually
var activity_script
#status of this card as an encounter (see GameData)
var encounter_status = gameData.EncounterStatus.NONE

# Setter for canonical_name
# Also changes the card label and the node name
func set_card_name(value : String, set_label := true) -> void:
	.set_card_name(value, set_label)
	name += "-" + guidMaster.get_guid(self) #a unique identifier that will also work for network calls	
	if name.ends_with("guid_unknown"):
		name +=  " - " + str(get_owner_hero_id())


func warning():
	if card_front:
		card_front.warning()

func hint (text, color, details = {}):
	var position = details.get("position", "")
	var pos_x = 50
	var pos_y = 50
	match position:
		"bottom_right":
			pos_x = 100
			pos_y = 200
		_:
			pos_x += (randi() % 100) - 50
			pos_y += (randi() % 100) - 50
		
	var _hint_label = Label.new()
	var _hint= Node2D.new()
	var _hint_control= Control.new()
	_hint.add_child(_hint_control)
	_hint_label.text = text
	var dynamic_font = cfc.get_font("res://fonts/Bangers-Regular.ttf", 32)	
	_hint_label.add_font_override("font", dynamic_font)	
	_hint_label.add_color_override("font_color", color)
	var dir_x = randf() * 10 
	var dir_y = randf() * 10
	
	var settings = {
		"hint_node": _hint,
		"hint_control": _hint_control,
		"lifetime": details.get("lifetime", 1.0),
		"direction": Vector2(dir_x, dir_y),
		"sound": "hint_" + text.to_lower().replace("!", "") + "*"
	}
	hints.append(settings)
	var _hint_label_shadow = _hint_label.duplicate(DUPLICATE_USE_INSTANCING)
	_hint_label_shadow.add_color_override("font_color", Color8(0,0,0,150))
	_hint_control.add_child(_hint_label_shadow)	
	_hint_control.add_child(_hint_label)
	_hint_label_shadow.rect_position = _hint_label.rect_position + Vector2(10, 10)
	$Control.add_child(_hint)
	_hint.z_as_relative = false
	_hint.z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL
	_hint_control.rect_position = Vector2(pos_x, pos_y)

func add_extra_script(script_definition, allowed_hero_id = 0):
	extra_script_uid+= 1
	extra_scripts[extra_script_uid] = {
		"script_definition" : script_definition
	}
	if allowed_hero_id:
		extra_scripts[extra_script_uid]["controller_id"] = allowed_hero_id
		
	check_ghost_card()
	register_signals()
	
	scripting_bus.emit_signal("card_script_added", self, extra_scripts[extra_script_uid])
	return extra_script_uid

func remove_extra_script(script_uid):
	var details = extra_scripts.get(extra_script_uid, {})
	extra_scripts.erase(script_uid)
	check_ghost_card()
	scripting_bus.emit_signal("card_script_removed", self, details)
	return extra_script_uid

func set_is_inactive_attachment(value:=true):
	self._is_inactive_attachment = value

	#removing the card from this group will prevent
	#triggering alterants
	if value and self.is_in_group("cards"):
		self.remove_from_group("cards") 
	if !value and !self.is_in_group("cards"):
		self.add_to_group("cards")

func set_is_boost(value:=true):
	self._is_boost = value
	
#	#removing the card from this group will prevent
#	#triggering incorrect interrupts
	if value and self.is_in_group("cards"):
		self.remove_from_group("cards")
		self.add_to_group("scriptables")
	if !value and !self.is_in_group("cards"):
		self.add_to_group("cards")
		self.remove_from_group("scriptables")


func get_alterants_key():
	if is_boost():
		if is_faceup:
			return "boost_alterants"
		return ""
	return SP.KEY_ALTERANTS
	
func is_boost():
	return self._is_boost

func is_inactive_attachment():
	#last minute check
	if !self.current_host_card:
		return false
		
	return self._is_inactive_attachment

#what to do when I'm an attachement and my host is removed from the table
func host_is_gone(former_host):
	# Attachments typically go to their discard
	discard()

func init_owner_hero_id(hero_id:int):
	if _owner_hero_id >=0: #already initialized
		return
	if (hero_id == -1):
		var _error = 1		
	_owner_hero_id = hero_id
	
func get_owner_hero_id() -> int:
	return _owner_hero_id	

func set_controller_hero_id(hero_id:int):
	_controller_hero_id = hero_id		
	update_hero_groups()

func queue_refresh_cache():
	_cache_refresh_needed = true

#refresh cache for all data
func refresh_cache(forced=false):
	if !forced and ! _cache_refresh_needed:
		return
		
		
	for i in gameData.get_team_size():
		var hero_id = i+1
		_check_play_costs_cache[hero_id] = CFConst.CostsState.CACHE_INVALID
	check_death()
	_cache_resource_value = {}
	_state_exec_cache = ""
	side_icons.update_state(true)
	tokens.refresh_display()
	_cache_refresh_needed = false
	_cached_all_traits = null
	_script_alter_cache = {}

func get_all_traits() -> Dictionary:
	if _cached_all_traits == null:
		for trait in cfc.all_traits:
			var trait_property = "trait_" + trait
			if get_property(trait_property, 0, true):
				_cached_all_traits[trait] = true
	
	return _cached_all_traits

func considered_in_play()-> bool:
	if is_boost():
		return false
	var type = get_property("type_code", "")
	if type in ["treachery", "event"]:
		return false
	return true



static func is_character_type(type_code)-> bool:
	return type_code in ["villain", "hero", "alter_ego", "ally", "minion"]

func is_card_type(type_code):
	var result = cfc.ov_utils.compare_string_properties({
		"type_code": type_code}, self, "type_code", "eq")	
	return result

func _stack_event_deleted(event):
	match event.get_first_task_name():
		"card_dies":
			var scripts = event.get_tasks()
			if scripts:
				var script = scripts[0]
				if script.subjects and script.subjects[0] == self:
					_died_signal_sent = false

var _died_signal_sent = false
func check_death(script = null) -> bool:
	if _died_signal_sent:
		return true
	#if no script is passed, this is an automated check (during _process), we only perform
	#it for character cards that are on the board, and with an empty stack to avoid a race condition
	if !script:
		if !is_character():
			return false
		if !is_onboard():
			return false
		if !gameData.theStack.is_idle():
			return false
	
	if get_property("cannot_leave_play", 0, true):
		return false
		
	var total_damage:int =  tokens.get_token_count("damage")
	var health = get_property("health", null)
	
	#things that don't have health cannot die
	if health == null:
		return false

	if total_damage < health:
		return false

	
	var excess_damage = total_damage - health
	
	var tags = []
	var trigger_details = {}
	var trigger_card = self
		
	if script:
		tags = [script.script_name, "Scripted"] + script.get_property(SP.KEY_TAGS)	
		trigger_card = script.trigger_object
		trigger_details = script.trigger_details.duplicate(true)
		trigger_details["source"] = guidMaster.get_guid(script.owner)
	
		#if the damage comes from an "attack", ensure the source is properly categorized as
		#the hero (or villain) owner rather than the event card itself
		if ("attack" in tags):
			var owner = WCScriptingEngine.get_actual_action_source_from_script(script)	
			trigger_details["secondary_source"] = trigger_details["source"]
			trigger_details["source"] = guidMaster.get_guid(owner)
			trigger_details["actual_source"] = guidMaster.get_guid(owner)

	var card_dies_definition = {
		"name": "card_dies",
		"tags": tags,
		"excess_damage": excess_damage
	}
	for param in ["source", "secondary_source", "actual_source"]:
		if trigger_details.has(param):
			card_dies_definition[param] = trigger_details[param]
	#force changing the trigger here. Might not be the best idea but it's useful for UI display
	trigger_details["trigger_type"] = "card_dies"	
	trigger_details["excess_damage"] = excess_damage
	var card_dies_script:ScriptTask = ScriptTask.new(self, card_dies_definition, trigger_card, trigger_details)
	card_dies_script.set_subjects(self)
	var task_event = SimplifiedStackScript.new(card_dies_script)
	gameData.theStack.add_script(task_event)
	
	#TODO this might need to move to another place, there are other ways a card could leave play than dying
	scripting_bus.emit_signal_on_stack("card_leaves_play", self, {})
	
	_died_signal_sent = true
	return true
	
func get_controller_hero_id() -> int:
	return _controller_hero_id	

func get_controller_hero_card():
	return gameData.get_identity_card(_controller_hero_id)	

func get_action_character():
	var action_character = self
	if !is_character():
		action_character = get_controller_hero_card()
	return action_character	
	
func get_controller_player_network_id() -> int:
	var player_data:PlayerData = gameData.get_hero_owner(get_controller_hero_id())
	if (!player_data):
		return 0 #TODO error handling? This shouldn't happen
	return player_data.get_network_id()	
	
func get_controller_player_id() -> int:
	var player_data:PlayerData = gameData.get_hero_owner(get_controller_hero_id())
	if (!player_data):
		return 0 #TODO error handling? This shouldn't happen
	return player_data.get_id()		

func _runtime_properties_setup():
	_horizontal = self.get_property("_horizontal", false)
	
	var base_threat = self.get_property("base_threat",0)
	var base_threat_fixed = get_property("base_threat_fixed", true)
	if base_threat and !base_threat_fixed:
		base_threat *= gameData.team.size()
		properties["base_threat"] = base_threat

	var health = get_property("health",0)
	var health_per_hero = get_property("health_per_hero", false)
	if health and health_per_hero:
		health *= gameData.team.size()
		properties["health"] = health
		
	var threat = get_property("threat",0)
	var threat_fixed = get_property("threat_fixed", true)
	if threat and !threat_fixed:
		threat *= gameData.team.size()
		properties["threat"] = threat		

func get_display_name(force_canonical = false):
	if is_faceup:
		return canonical_name
	var shortname =  get_property("shortname", "---")
	return shortname

func get_duplicate(refresh_variables = true):
	var duplicate = .get_duplicate(refresh_variables)
	duplicate._hide_spinbox()
	return _duplicate

#reloads content of the card from a nw card_id
#this function reloads all properties
#and cleans up temporary variables from the older card
func load_from_card_id(card_id):
	var previous_id = canonical_id
	canonical_name = cfc.card_definitions[card_id]["Name"]
	canonical_id = card_id	

	#reload properties from new id
	properties = {}
	var read_properties = cfc.card_definitions.get(canonical_id, {})
	for property in read_properties.keys():
		# warning-ignore:return_value_discarded
		modify_property(
				property,
				read_properties[property],
				false,
				["Init"])
				
	_init_card_name()
	#force reload card art
	set_card_art(true)
	_runtime_properties_setup()
	_cached_printed_text = { "_initialized": false}
	update_groups()
	side_icons.set_icons()
	_duplicate = null
	CFScriptUtils.add_update_alterant_super_cache_object(self)
	scripting_bus.emit_signal("card_reloaded", self, {"before_id": previous_id })
	
func setup() -> void:
	register_signals()
	.setup()
	_runtime_properties_setup()
	update_groups()
	init_token_drawer()	
	position_ui_elements()
	_ready_load_from_json()
	
	gameData.connect("game_state_changed", self, "_game_state_changed")
	scripting_bus.connect("step_about_to_start", self, "_game_step_about_to_start")	

	scripting_bus.connect("card_token_modified", self, "_card_token_modified")

	scripting_bus.connect("card_moved_to_hand", self, "_card_moved")
	scripting_bus.connect("card_moved_to_pile", self, "_card_moved")
	scripting_bus.connect("card_moved_to_board", self, "_card_moved")		
	scripting_bus.connect("card_properties_modified", self, "_card_properties_modified")		

	cfc.connect("cache_cleared", self, "_cfc_cache_cleared")
	scripting_bus.connect("stack_event_deleted", self, "_stack_event_deleted")
	
	scripting_bus.connect("card_selected", self, "_window_selection_confirmed")
	scripting_bus.connect("current_playing_hero_changed", self, "_current_playing_hero_changed")
	
	attachment_mode = AttachmentMode.ATTACH_BEHIND
	
	#this prevents moving cards around. A bit annoying but avoids weird double click envents leading to a drag and drop
	disable_dragging_from_board = true	
	disable_dropping_to_cardcontainers = true


func _current_playing_hero_changed (trigger_details: Dictionary = {}):
	if CFConst.PERFORMANCE_HACKS:
		if _controller_hero_id == gameData.get_current_local_hero_id():
			set_process_recursive(true)

#		scripting_bus.emit_signal(
#				"card_properties_modified",
#				self,
#				{
#					"property_name": property,
#					"new_property_value": value,
#					"previous_property_value": previous_value,
#					"tags": tags
#				}
#		)	
func _card_properties_modified(owner_card, details):
	if owner_card == self and details.get("property_name", "") == "type_code":
		var previous_value = details.get("previous_property_value", "")
		var new_value = details.get("new_property_value", "")
		if new_value in ["villain", "minion"] and new_value != previous_value  and "emit_signal" in details["tags"]:
			scripts = SetScripts_All.get_enemy_scripts()
		update_groups()
		update_hero_groups()
	queue_refresh_cache()
		
#		scripting_bus.emit_signal(
#				"card_token_modified",
#				owner_card,
#				{SP.TRIGGER_TOKEN_NAME: token.get_token_name(),
#				SP.TRIGGER_PREV_COUNT: prev_value,
#				SP.TRIGGER_NEW_COUNT: new_value,
#				"tags": tags})
func _card_token_modified(owner_card, details):
	if owner_card != self:
		return
	if details[SP.TRIGGER_TOKEN_NAME] == "damage":
		#display_health()
		pass
	if details[SP.TRIGGER_TOKEN_NAME] == "threat":
		display_threat()

#("card_moved_to_hand",
#					self,
#					 {
#						"destination": targetHost.name,
#						"source": parentHost.name,
#						"tags": tags
#					}
#			)

func _card_moved(owner_card, details):
	if owner_card != self:
		return
	display_debug(canonical_name + " moved from " + details["source"] + " to " + details["destination"])

func display_threat():
	if !healthbar:
		return
	if get_state_exec() != "board":
		healthbar.set_visible(false)
		return

	var type_code = get_property("type_code", 0)
	if !(type_code in ["main_scheme"]):
		return

	var total_threat = get_property("threat", 0)
	if !total_threat:
		return
	var current_threat = self.tokens.get_token_count("threat")
	healthbar.set_threat(total_threat, current_threat)
	pass
	
func display_health():
	if !healthbar:
		return
	if get_state_exec() != "board":
		healthbar.set_visible(false)
		return

	var type_code = get_property("type_code", 0)
	if !(type_code in ["hero", "alter_ego", "villain"]):
		return

	var total_health = get_property("health", 0)
	if !total_health:
		return
	var total_damage = self.tokens.get_token_count("damage")
	var remaining_health = total_health-total_damage
	if remaining_health<0:
		remaining_health= 0
	healthbar.set_health(total_health, remaining_health)
	pass

func position_ui_elements():
	if _horizontal:
		#reposition the token drawer for horizontal cards
		tokens.set_is_horizontal()

func execute_before_scripts(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	return execute_scripts(trigger_card, "before_" + trigger, trigger_details, run_type) 

func _class_specific_ready():
	._class_specific_ready()
	healthbar = $Control/HealthPanel/healthbar
	info_icon = get_node("%info_icon")
	side_icons = get_node("%SideIcons")
	#deactivate collision support for performance
	if CFConst.PERFORMANCE_HACKS:
		self.monitoring = false
		$Debug.queue_free()
		$Control/ManipulationButtons.queue_free()
		buttons = null

func get_spinbox():
	if !spinbox:
		var spinbox_panel = _SPINBOX_SCENE.instance()
		$Control.add_child(spinbox_panel)
		spinbox = spinbox_panel.get_node("SpinBox")

	_show_spinbox()
	return spinbox		

func _hide_spinbox():
	if !spinbox:
		return
	spinbox.get_parent().visible = false
		
func _show_spinbox():
	if !spinbox:
		return
	spinbox.get_parent().visible = true

func _ready():
	scripting_bus.connect("scripting_event_about_to_trigger", self, "execute_before_scripts")

#
# Keyboard/Gamepad focus related functions
#
func reorganize_attachments_focus_mode():
	var previous_control:Control = self.get_focus_control()
	previous_control.focus_neighbour_left = ""
	previous_control.focus_neighbour_right = ""
	previous_control.focus_neighbour_bottom = ""
	previous_control.focus_neighbour_top = ""		
	for card in attachments:
		var control = card.get_focus_control()
		control.focus_neighbour_left = ""
		control.focus_neighbour_right = ""
		control.focus_neighbour_bottom = ""
		control.focus_neighbour_top = ""		
		if previous_control:
			#attachments are slightly below, slightly to the right of each other
			control.focus_neighbour_left = previous_control.get_path()	
			control.focus_neighbour_top = control.focus_neighbour_left			
			previous_control.focus_neighbour_right = control.get_path()
			previous_control.focus_neighbour_bottom = previous_control.focus_neighbour_right
		previous_control = control

func _on_Control_focus_entered():	
	#doing the focus thing only for non mouse inputs
	if !gamepadHandler.is_mouse_input():
		gain_focus()
	
func _on_Control_focus_exited():
	lose_focus()

func grab_focus():
	_control.grab_focus()

func get_focus_control():
	return _control

func gain_focus():
	has_focus = true
	
	#TODO this is a lame attempt to make it clearer which card is being 
	#currently selected. Doesn"t work so well tbh..
	if !gamepadHandler.is_mouse_input():
		if get_state_exec()!= "hand":
			if card_front and card_front.art:
				card_front.art.self_modulate = CFConst.FOCUS_CARD_MODULATE
				card_front.art.self_modulate.a = 1.0
	.gain_focus()
	
func lose_focus():
	has_focus = false
#	if card_front and card_front.art:
#		card_front.art.set_material(null)
	if card_front and card_front.art:
		card_front.art.self_modulate = Color(1.0,1.0,1.0,1.0)
	.lose_focus()
	
func enable_focus_mode():
	_control.focus_mode = Control.FOCUS_ALL
	set_control_mouse_filters(true)

func disable_focus_mode():
	_control.focus_mode = Control.FOCUS_NONE
	set_control_mouse_filters(false)
#
# User Interface/Input functions
#

func _class_specific_input(event) -> void:
	if event is InputEventMouseButton and not event.is_pressed():
		if targeting_arrow and targeting_arrow.is_targeting:
			if event.get_button_index() == 2: #todo have a cancel button on screen instead
				targeting_arrow.cancel_targeting()
			else:
				targeting_arrow.complete_targeting()
		if  event.get_button_index() == 1:
			# On depressed left mouse click anywhere on the board
			# We stop all attempts at dragging this card
			# We cannot do this in gui_input, because some thing
			# like the targetting arrow, will trigger dragging
			# because the click depress will not trigger on the card for some reason
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			$Control.set_default_cursor_shape(Input.CURSOR_ARROW)
			cfc.card_drag_ongoing = null
	elif event is InputEvent:
		if targeting_arrow and targeting_arrow.is_targeting:
			if gamepadHandler.is_ui_accept_pressed(event):
				targeting_arrow.complete_targeting()
			elif gamepadHandler.is_ui_cancel_pressed(event):
				targeting_arrow.cancel_targeting()		

	

func _class_specific_process(delta):
	if !CFConst.PERFORMANCE_HACKS:
		if cfc._debug and not get_parent().is_in_group("piles"):
			var stateslist = [
				"IN_HAND",
				"FOCUSED_IN_HAND",
				"MOVING_TO_CONTAINER",
				"REORGANIZING",
				"PUSHED_ASIDE",
				"DRAGGED",
				"DROPPING_TO_BOARD",
				"ON_PLAY_BOARD",
				"FOCUSED_ON_BOARD",
				"IN_PILE",
				"VIEWED_IN_PILE",
				"IN_POPUP",
				"FOCUSED_IN_POPUP",
				"VIEWPORT_FOCUS",
				"PREVIEW",
				"DECKBUILDER_GRID",
				"MOVING_TO_SPAWN_DESTINATION",
			]	
			$Debug.visible = true
			$Debug/Panel/V/id.text = "ID:  " + str(self)
			$Debug/Panel/V/state.text = "STATE: " + stateslist[state]
			$Debug/Panel/V/index.text = "INDEX: " + str(get_index())
			$Debug/Panel/V/parent.text = "PARENT: " + str(get_parent().name)
			if !get_owner_hero_id():
				var traits = ""
				var separator = "/"
				for trait in cfc.all_traits:
					var value = get_property("trait_" + trait, 0, true)
					if value:
						traits += trait +"(" + str(value) +")" + separator
				$Debug/Panel/V/misc.text = "TRAITS: " + str(traits)
			$Debug.rect_scale = Vector2(2.0, 2.0)
		else:
			$Debug.visible = false	
	if $Tween.is_active() and not cfc.ut: # Debug code for catch potential Tween deadlocks
		_tween_stuck_time += delta
		if _tween_stuck_time > 5 and int(fmod(_tween_stuck_time,3)) == 2 :
			print_debug("Tween Stuck for ",_tween_stuck_time,
					"seconds. Reports leftover runtime: ",$Tween.get_runtime ( ))
			$Tween.remove_all()
			_tween_stuck_time = 0
	else:
		_tween_stuck_time = 0
	_process_card_state()
	pass
		

func _process(delta) -> void:
	if cfc.game_paused:
		return

	refresh_cache()

	if info_icon and info_icon.visible:
		info_icon.modulate.a -= delta
		if info_icon.modulate.a < 0.01:
			info_icon.visible = false

	#hints
	var hints_to_erase = []
	var stop = false
	for _hint_data in hints:
		var hint_node = _hint_data.get("hint_node", null)
		if hint_node:
			hint_node.visible = false
		
	for _hint_data in hints:
		if stop:
			break
		var hint_node = _hint_data.get("hint_node", null)
		var hint_object = _hint_data.get("hint_control", null)		
		if hint_node:
			var sound_emitted = _hint_data.get("sound_emitted", false)
			if !sound_emitted:
				_hint_data["sound_emitted"] = true
				var sound = _hint_data.get("sound", "")
				if sound:
					gameData.play_sfx(sound)
			
			hint_node.visible = true
			hint_object.modulate.a -= delta / 3
			hint_object.rect_scale += Vector2(delta *3, delta *3)
			hint_object.rect_position+= _hint_data.get("direction") * delta
		if self._is_exhausted or self._horizontal:
			hint_object.rect_rotation = -90
		var lifetime = _hint_data.get("lifetime", 0)
		lifetime -= delta
		if lifetime < 0.2 or hint_object.modulate.a <=0.2:
			stop = false
		else:
			stop = true
		if lifetime < 0 or hint_object.modulate.a <=0:
			hints_to_erase.append(_hint_data)
		_hint_data["lifetime"] = lifetime
	for data in hints_to_erase:
		$Control.remove_child(data["hint_node"])
		data["hint_node"].queue_free()
		hints.erase(data)
	hints_to_erase = []
	
	
	if (cfc.is_modal_event_ongoing()):
		return
	if (gameData.is_targeting_ongoing()):
		return
		
	display_play_highlight()	


func display_play_highlight():
	if not gameData.is_game_started():
		return

	var can_play = check_play_costs()
	if (can_play == CFConst.CostsState.OK):
		#if modal menu is displayed we don't want to mess up those cards highlights
		var colour = can_play
		if !gamepadHandler.is_mouse_input():
			colour = CFConst.CostsState.OK_NO_MOUSE
		if gameData.is_interrupt_mode():
			colour = CFConst.CostsState.OK_INTERRUPT
		set_target_highlight(colour)
		if has_focus and !gamepadHandler.is_mouse_input():
			set_target_highlight(CFConst.FOCUS_COLOUR_ACTIVE)			
	else:
		#pass
		clear_highlight()
		#card with focus overrides previous highlight color	
		if has_focus and !gamepadHandler.is_mouse_input():
			set_target_highlight(CFConst.FOCUS_COLOUR_INACTIVE)		

func set_target_highlight(colour):
	highlight.set_target_highlight(colour)


#flush caches and states when game state changes
func _game_state_changed(_details:Dictionary):
	queue_refresh_cache()	
	display_health()

func _cfc_cache_cleared():
	queue_refresh_cache()

#reset some variables at new turn
func _game_step_about_to_start(_trigger_object, details:Dictionary):
	var current_step = details["step"]
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			if is_instance_valid(tokens):
				if get_property("type_code") in ["hero", "alter_ego"]:
					self.tokens.mod_token("__can_change_form", 1)
	return	
	

func get_card_back_code() -> String:
	var back_code = get_property("back_card_code")

	if !back_code:
		var type_code = get_property("type_code")	
		if type_code == "hero":
			#multiple hero modes sometimes don't have the matching back card, e.g. Ant-Man giant form
			var alter_ego_data = cfc.get_alter_ego_data(canonical_id)
			back_code = alter_ego_data["_code"]
	
	return back_code
	

func get_art_filename(force_if_facedown: = true):
	if force_if_facedown or is_faceup:
		if cfc.get_setting("disable_card_images"):
			return ""
		var card_code = get_property("_code")
		return cfc.get_img_filename(card_code)		

	return ("res://assets/card_backs/generic_back.png")

func get_art_texture(force_if_facedown: = true):
	return cfc.get_card_texture(self, force_if_facedown)

func get_cropped_art_texture(force_if_facedown = true):
	return cfc.get_cropped_card_texture(self, force_if_facedown)

func set_card_art(forced=false):
	if card_front.art_filename and !forced:
		return
	var filename = get_art_filename()
	card_front.set_card_art(filename)

# Determines which play position (board, pile or hand)
# a script should look for to find card scripts
# based on the card's state.
#
# Returns either "board", "hand", "pile" or "NONE".
var _state_exec_cache := ""

func set_state(value: int) -> void:
	if state == CardState.DRAGGED:
		pass
	var prev_state = state
	state = value
	if prev_state != state:
		emit_signal("state_changed", self, prev_state, state)
		
		_state_exec_cache = ""

func get_state_exec() -> String:
	#return get_state_exec_no_cache()
	
	# I can't cache CardState.MOVING_TO_CONTAINER:
	#I've seen cases where it keeps that state while moving between multiple places,
	#which makes the cached value stale
	
	if !_state_exec_cache or state == CardState.MOVING_TO_CONTAINER:
		 _state_exec_cache = get_state_exec_no_cache()
	return _state_exec_cache
	
func get_state_exec_no_cache() -> String:	
	var state_exec := "NONE"
	# We don't check according to the parent name
	# as that can change.
	# Might consier checking on the parent class if this gets too complicated.
	match state:
		CardState.ON_PLAY_BOARD,\
				CardState.FOCUSED_ON_BOARD,\
				CardState.DROPPING_TO_BOARD:
			# cards that have a type_code 'i.e faceup cards and facedown cards with modifiers)
			#are allowed to run scripts
			if get_property("type_code", ""):
				state_exec = "board"
		CardState.IN_HAND,\
				CardState.FOCUSED_IN_HAND,\
				CardState.REORGANIZING,\
				CardState.PUSHED_ASIDE:
			state_exec = "hand"
		CardState.IN_POPUP,\
				CardState.FOCUSED_IN_POPUP,\
				CardState.IN_PILE,\
				CardState.VIEWED_IN_PILE:
			state_exec = "pile"
		CardState.MOVING_TO_CONTAINER:
			if get_parent() and get_parent().is_in_group("hands"):
				state_exec = "hand"
			else:
				state_exec = "pile"
	return(state_exec)

#adds our card to group names matching its type and hero owner
# e.g. "allies2" means allies belonging to hero 2
# 0 is valid and represents the villain
func update_hero_groups():
	var type_code = properties.get("type_code", "")
	
	var all_groups:Array = CFConst.ALL_TYPE_GROUPS
	for group in all_groups:
		for i in range (gameData.team.size() + 1):
			var hero_group = group + str(i)
			if self.is_in_group(hero_group):
				self.remove_from_group(hero_group)	
	
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	
	for group in groups:
		if group == "play_area" and !self.is_onboard():
			continue
		for i in range (gameData.team.size() + 1):
			var hero_group = group + str(i)
			if self.get_controller_hero_id() == i:
				self.add_to_group(hero_group)

func update_groups() -> void :
	var type_code = properties.get("type_code", "")

	var all_groups:Array = CFConst.ALL_TYPE_GROUPS
	for group in all_groups:
		if self.is_in_group(group):
			self.remove_from_group(group)	
			
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	for group in groups:
		if group == "play_area" and !self.is_onboard():
			continue		
		self.add_to_group(group)

func remove_attachment(card):
	attachments.erase(card)
	reorganize_attachments_focus_mode()

func attach_to_host(
			host: Card,
			is_following_previous_host = false,
			tags := ["Manual"]) -> void:
				
	var alterants_cache_refresh_needed = true
					
	if "as_boost" in tags:
		alterants_cache_refresh_needed = false
		set_is_boost(true)
	else:
		if self.is_boost():
			set_is_boost(false)

	if "as_inactive_attachment" in tags:
		alterants_cache_refresh_needed = true
		set_is_inactive_attachment(true)

	if alterants_cache_refresh_needed:
		cfc.flush_cache()

	.attach_to_host(host, is_following_previous_host, tags)
	host.reorganize_attachments_focus_mode()
	if "as_boost" in tags:			
		set_is_faceup(false)
		
func common_post_move_scripts(new_host: String, old_host: String, _move_tags: Array) -> void:
	#change controller as needed
	var new_grid = get_grid_name()
	var new_hero_id = 0
	if (new_grid):
		new_hero_id = gameData.get_grid_controller_hero_id(new_grid)
	else:
		#attempt for piles/containers
		new_hero_id = gameData.get_grid_controller_hero_id(new_host)
	
	if (new_hero_id or (self.get_controller_hero_id() < 0) ): #only change if we were able to establish an owner, or if uninitialized
		self.set_controller_hero_id(new_hero_id)
	
	
	#init owner once and only once, if not already done
	init_owner_hero_id(new_hero_id)

	update_groups()
	update_hero_groups()		
	
	#display_health()
	display_threat()
	
	#cached data and flag updates for new zone
	match new_host.to_lower():
		"board":
			if !is_faceup:
				get_card_back().start_card_back_animation()
		_:
			_is_exhausted = false
			#reset some cache data
			_died_signal_sent = false
			#if the card moves to anything else than the board
			#it loses its boost status
			set_is_boost(false) 
			set_is_inactive_attachment(false)

	if CFConst.PERFORMANCE_HACKS:
		set_process_recursive(true)
		if ! get_state_exec() in ["pile"]:
			reattach_removed_nodes()						
		else:
			detach_unused_nodes()
			

	set_is_viewed(false)
	
	#determine if this card can be selected with a controller	
	cfc.NMAP.board.update_card_focus(self, {"new_host" : new_host, "old_host": old_host} )

func detach_unused_nodes():
	if _unused_nodes_detached:
		return
	var to_remove = [tokens, healthbar.get_parent(),  info_icon]
	
	for node in _control.get_children():
		if node in to_remove:
			_removed_control_nodes.append(node)
	for node in _removed_control_nodes:
		if !is_instance_valid(node):
			continue
		_control.remove_child(node)
	
	if is_instance_valid(targeting_arrow) and !(targeting_arrow.is_targeting):	
		if self.is_a_parent_of(targeting_arrow):
			self.remove_child(targeting_arrow)	

	_unused_nodes_detached = true

func reattach_removed_nodes():
	if !_unused_nodes_detached:
		return	
	
	for node in _removed_control_nodes:
		if !is_instance_valid(node):
			continue		
		if !_control.is_a_parent_of(node):			
			_control.add_child(node)
	_removed_control_nodes = []
			
	for node in [targeting_arrow]:
		if !is_instance_valid(node):
			continue 	
		if !self.is_a_parent_of(node):
			self.add_child(node)

	_unused_nodes_detached = false

func set_process_recursive(value, node = self):
	if node.has_method("set_process"):
		node.set_process(value)
	if node.has_method("get_children"):
		for c in node.get_children():
			set_process_recursive(value, c)

			
#Override of the parent's
# Retrieves the value of a property. This should always be used instead of
# properties.get() as it takes into account the temp_properties_modifiers var
# and also checks for alterant scripts
func get_property(property: String, default = null, force_alterant_check = false):
	if not (properties.has(property)) and not force_alterant_check:
		return default
		
	if CFConst.PERFORMANCE_HACKS:
		if !state in [
				CardState.ON_PLAY_BOARD,
				CardState.FOCUSED_ON_BOARD,
				CardState.DROPPING_TO_BOARD,
				CardState.IN_HAND,
				CardState.FOCUSED_IN_HAND,
				CardState.REORGANIZING,
				CardState.PUSHED_ASIDE
		]:
			return properties.get(property, default)	
	return(get_property_and_alterants(property, false, default).value)

func register_signals():
	scripting_bus.unregister_card(self)
	var tmp_scripts = retrieve_all_scripts()
	for trigger in CFConst.OPTIONAL_SIGNALS + CFConst.NO_STACK_BY_DEFAULT_SIGNALS:
		if WCUtils.has_interrupt_or_response (tmp_scripts, trigger):
			scripting_bus.register_card_signal(self, trigger, true)
		else:
			if WCUtils.is_string_in_variant(tmp_scripts, trigger):
				scripting_bus.register_card_signal(self, trigger)
		

#Tries to play the card assuming costs aren't impossible to pay
#Also used for automated tests
func attempt_to_play(user_click:bool = false, origin_event = null):
	#don't try to activate the card if the click was the result of targeting
	if user_click:
		if gameData.is_targeting_ongoing() or gameData.manual_action_happened_too_recently():
			return
		#we already sent a request and should be waiting for full resolution	

		var interaction_authority:UserInteractionAuthority = UserInteractionAuthority.new(self)
		var interaction_authorized = interaction_authority.interaction_authorized()			
		
		if !interaction_authorized or !gameData.theStack.is_player_allowed_to_click(self):
			network_request_rejected()
			return
		
		#gamedata is running some automated clicks from a previous request	
		if gameData.get_sequence_scripts():
			return	
		
	#for manual attempts to play we only allow board or hand
	var state_exec = get_state_exec()
	if user_click and !(state_exec in ["hand", "board"]):
		return false

	if user_click:
		match state_exec:
			"hand":
				GameRecorder.add_entry(GameRecorder.ACTIONS.PLAY, canonical_id, "playing " + canonical_name)
			_:
				GameRecorder.add_entry(GameRecorder.ACTIONS.ACTIVATE, canonical_id, "activating " + canonical_name)
				

	var details = {}
	if origin_event:
		details["origin_event"] = origin_event
	
	if _get_extra_scripts("manual_override"):
		return execute_scripts(self,"manual_override", details)
	
	match state_exec:
		"hand":
			if check_play_costs() == CFConst.CostsState.IMPOSSIBLE:
				return false
			#unique rule - Move to check costs ?
			var already_in_play = cfc.NMAP.board.unique_card_in_play(self)
			if already_in_play:
				return false	


	cfc.card_drag_ongoing = null
	#tells gamedata that a manual action just happened
	gameData.restart_manual_action_stopwatch()
	execute_scripts(self,"manual",details)


func network_request_rejected():
	if info_icon:
		info_icon.visible = true
		info_icon.modulate = Color(1,1,1,1)

func find_interrupt_script(trigger_card, trigger_details):
	#select valid scripts that match the current trigger
	for trigger_name in  ["interrupt_" + trigger_details.get("event_name", ""), "interrupt"]:
		var card_scripts = retrieve_filtered_scripts(trigger_card, trigger_name, trigger_details)
		if card_scripts:
			var state_scripts = get_state_scripts(card_scripts, trigger_card, trigger_details)
			if state_scripts:
				return {
					"card_scripts": card_scripts,
					"state_scripts": state_scripts,
					"trigger": trigger_name
				}
	return {}
	
#returns true if this card has some ability that can interrupt
#the current action (and if hero_id is the one who can play it)
func can_interrupt(
		hero_id,
		trigger_card: WCCard = self,
		trigger_details: Dictionary = {}) -> int:
	if cfc.game_paused:
		return CFConst.CanInterrupt.NO
	# Just in case the card is displayed outside the main game
	# and somehow its script is triggered.
	if not cfc.NMAP.has('board'):
		return CFConst.CanInterrupt.NO
	
	var _debug = false
	if canonical_name == "She-Hulk" and trigger_card:
		if trigger_details["event_name"] == "identity_changed_form":
			_debug = true

	if (_debug):
		display_debug("{interrupt} Hero:" + str(hero_id) + " Checks for " + canonical_name + " vs " + trigger_details.get("event_name") + " - " + trigger_card.canonical_name)		

	var interrupt_data = find_interrupt_script(trigger_card, trigger_details)
	if !interrupt_data:
		return CFConst.CanInterrupt.NO	
	#select valid scripts that match the current trigger
	var card_scripts = interrupt_data["card_scripts"]
	var state_scripts = interrupt_data["state_scripts"]
			
	if (_debug):
		display_debug("card_scripts: " + to_json(card_scripts))

	if (_debug):
		display_debug("state_scripts: " + to_json(state_scripts))	
	if (!state_scripts):
		if (_debug):
			display_debug("no state scripts found")
		return CFConst.CanInterrupt.NO
	
	#card has potential interrupts. Last we check if I'm the player who can play them
	var may_interrupt =  CFConst.CanInterrupt.NO


	if gameData.can_hero_play_this_ability(hero_id,self):
		if card_scripts.get("is_optional_" + get_state_exec()):
			#optional interrupts need to check costs
			if check_play_costs_no_cache(hero_id, _debug) == CFConst.CostsState.IMPOSSIBLE:
				if (_debug):
					display_debug("allowed to interrupt but can't pay cost")
				return CFConst.CanInterrupt.NO			
			may_interrupt =  CFConst.CanInterrupt.MAY
		else:
			may_interrupt =  CFConst.CanInterrupt.MUST
	else:
		if (_debug):
			display_debug("not allowed to inbterrupt according to can_hero_play_this_ability")
		pass
	if (may_interrupt != CFConst.CanInterrupt.NO and canonical_name == "Spider-Man"):
		display_debug("can interrupt " + trigger_card.canonical_name + ". Details: " + to_json(trigger_details))

	if (_debug):
		display_debug("{interrupt} END OF CHECKS for " + canonical_name + " vs " + trigger_details.get("event_name") + " - " + trigger_card.canonical_name)		


	return may_interrupt


func execute_scripts_no_stack(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	var new_trigger_details = trigger_details
	new_trigger_details["use_stack"] = false
	return execute_scripts(trigger_card, trigger, new_trigger_details, run_type)	


func retrieve_altered_scripts(trigger: String, filters := {}):	
	var alterant_cache_key = {
		"trigger": trigger,
		"filters": filters,
	}.hash()	
	
	if _script_alter_cache.has(alterant_cache_key):
		return _script_alter_cache[alterant_cache_key]

	var scriptables_array :Array = CFScriptUtils.game_has_script_alterants(trigger).keys()
		
	#remove duplicates
	var unique:= {}
	for key in scriptables_array:
		unique[key] = true
	scriptables_array = unique.keys()
	
	var result = {}
		
	for obj in scriptables_array:			
		var obj_scripts = obj.retrieve_scripts("script_alterants")
		if !obj_scripts:
			continue
		# We select which scripts to run from the card, based on it state
		var state_scripts = obj.retrieve_current_state_scripts(obj_scripts)
			
		for script in state_scripts:
			if not SP.filter_trigger(
				script,
				self,
				obj,
				{}):
				continue
			#this card is considered a valid target for alteration by obj
			result = WCUtils.merge_dict(result, script.get("script", {}), true)
		
	result = result.get(trigger, {})
	_script_alter_cache[alterant_cache_key] = result
	return 	_script_alter_cache[alterant_cache_key]

func retrieve_scripts(trigger: String, filters := {}) -> Dictionary:
	if self.is_onboard() && self.get_property("blank_abilities", 0, true):
		return {}
	
	var result = .retrieve_scripts(trigger, filters)
	
	if CFScriptUtils.game_has_script_alterants(trigger):
		var altered_results = retrieve_altered_scripts(trigger, filters)
		if altered_results:
			result = WCUtils.merge_dict(result, altered_results.duplicate(), true)
	
	if !result:
		return result
	
	if result.get("scripts_exist_but_not_for_your_use_case", false):
		return {}

	#Induced Panic blanks all triggered abilities
	#we mimic that by only surfacing default "game rule" abilities when a card is impacted
	#notably, alterants has to be ignored as it is not a triggered ability
	#Some other cards also "blank" a text box and we use the same logic for now
	#More things we ignore when a "text box is blank" are bean counting macros
	#for now those are "once_per_phase" and "once_per_round" which add important tokens to the card,
	#but there might be more
	#Warning, I had an infinite loop in alterants engine here when calling get_property before checking for alterants
	var macro_name = result.get("macro_name", "")
	var force_even_if_blank = (macro_name in ["once_per_phase", "once_per_round"]) or (trigger in ["alterants"])
	if !force_even_if_blank:	
		if self.get_property("blank_printed_trigger_abilities", 0, true) or self.get_property("blank_printed_text_box", 0, true):
				var found_scripts = _get_extra_scripts(trigger, filters)
				if found_scripts:
					return found_scripts
				var base_scripts = SetScripts_All.get_scripts({}, self.canonical_id)
				return base_scripts.get(trigger, {}).duplicate(true)
	return result


func retrieve_script_by_path(path:String):
	var found_scripts = get_instance_runtime_scripts()
	if !found_scripts:
		# This retrieves all the script from the card, stored in cfc
		# The seeks in them the specific trigger we're using in this
		# execution
		found_scripts = cfc.set_scripts.get(canonical_id,{}).duplicate(true)	
	var nodes = path.split("/")
	for node in nodes:
		
		found_scripts = found_scripts.get(node, {})
	
	return found_scripts

#returns true if no condition is set for a script,
#or if the condition is met in the current game state,
#false if the condition is not met
#example:
#					"condition_board":{
#						"func_name": "current_activation_status",
#						"func_params": {
#							"undefended": true
#						}
#					},	
func script_passes_condition(card_scripts, key, trigger_card, trigger_details = {}):
	if typeof(card_scripts) != TYPE_DICTIONARY:
		return true
	
	var condition = card_scripts.get("condition_" + key, {})
	if !condition:
		return true
		
	var func_name = condition.get("func_name", "")
	if !func_name:
		return true
		
	var func_params = condition.get("func_params", {})
	var check = cfc.ov_utils.dummy_func_name_run(self, trigger_card, func_name, func_params, trigger_details)
	return check

func retrieve_filtered_scripts(trigger_card,trigger, trigger_details):
	# I use this spot to add a breakpoint when testing script behaviour
	# especially on filters
	if _debugger_hook:
		pass

	if trigger == CFConst.SCRIPT_BREAKPOINT_TRIGGER_NAME and canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME:
		pass	

	var card_scripts = retrieve_scripts(trigger)		
	# We check the trigger against the filter defined
	# If it does not match, then we don't pass any scripts for this trigger.
	if !card_scripts:
		return card_scripts
		
	if not SP.filter_trigger(
			card_scripts,
			trigger_card,
			self,
			trigger_details):
		card_scripts.clear()
		return card_scripts
	
	
	#additional filter check for interrupts/responses
	if not cfc.ov_utils.filter_trigger(
			trigger,
			card_scripts,
			trigger_card,
			self,
			trigger_details):
		card_scripts.clear()
		return card_scripts
	
	var to_erase = []

	for key in card_scripts:
		if !script_passes_condition(card_scripts, key, trigger_card, trigger_details):
			to_erase.append(key)
			to_erase.append("condition_" + key)		
	for key in to_erase:
		card_scripts.erase(key)
		
	return card_scripts


#a quick check fnction for performance to return early in execute_scripts
func get_potential_scripts(trigger):
	var card_scripts = retrieve_scripts(trigger)
	if !card_scripts:
		return false
	var state_scripts = retrieve_current_state_scripts(card_scripts)
	return state_scripts

#returns true if something is going on that prevents execution of card scripts
func script_exec_temporarily_blocked(run_type) -> bool:
	if cfc.game_paused: 
		return true
	#background cost check is awlays acceptable
	#in particular, we don't want to block/delay can_interrupt checks!
	if run_type == CFInt.RunType.BACKGROUND_COST_CHECK:
		return false
		
	if cfc.is_modal_event_ongoing():
		return true
	if gameData.is_targeting_ongoing():
		return true
		
	
	return false

	
# Executes the tasks defined in the card's scripts in order.
#
# Returns a [ScriptingEngine] object but that it not statically typed
# As it causes the parser think there's a cyclic dependency.

	# there is a bug in the original engine that will create duplicate card
	# in selectionWindow.gd. These cards should get triggered but they do
	# There has to be a better way to fix this (see their attempted fix in ScriptingBus)
	# but I'm not sure for now
func execute_scripts(
		trigger_card: Card = self,
		trigger: String = "manual",
		orig_trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):

#	if (trigger == "receive_damage") and canonical_name == "Arm Block":# and run_type == CFInt.RunType.BACKGROUND_COST_CHECK:
#		var _tmp = 1

	if script_exec_temporarily_blocked(run_type):
		if get_parent() and !("tree_" in trigger): #dirty check to avoid crashes
			if get_potential_scripts(trigger):
				gameData.add_script_to_execute(self, trigger_card, trigger, orig_trigger_details, run_type)
			return null
		else:
			return null

	# Just in case the card is displayed outside the main game
	# and somehow its script is triggered.
	if not cfc.NMAP.has('board'):
		return null

	
	var _debug = orig_trigger_details.get("_debug", false)
			
	#temporary bug fix: prevent uninitalized cards from running scripts
	#these cards are duplicates that shouldn't exist?
	if (get_owner_hero_id() == -1):
		return null
	
	var can_i_run = can_execute_scripts()
	if typeof(can_i_run) == TYPE_BOOL:
		if !can_i_run:
			return null
	else:
		if !(trigger in (can_i_run)):
			#if this trigger doesn't match, we try one above, this is for specific
			#cases where a card calls a script within another e.g. execute_scripts for a boost
			# e.g. For Whom the Bell Tolls
			var parent_script = orig_trigger_details.get("parent_script", null)
			if !parent_script:
				return null
			var parent_trigger = parent_script.trigger
			if !(parent_trigger in (can_i_run)):
				return null

	#Force execute some previously selected scripts, bypassing the rest of the process
	var exec_config = orig_trigger_details.get("exec_config", {})
	var state_scripts_dict = orig_trigger_details.get("state_scripts_dict", {})
	if state_scripts_dict:
		#erase the variables to avoid re_running them
		orig_trigger_details.erase("exec_config")
		orig_trigger_details.erase("state_scripts_dict")
		return choose_and_execute_scripts(state_scripts_dict, trigger_card, trigger, orig_trigger_details, run_type, exec_config)

	#last minute swap for hero vs alter ego reveals
	if trigger == "reveal":
		var hero_id_to_check = gameData.get_villain_current_hero_target()
		var identity_card = gameData.get_identity_card(hero_id_to_check)
		var specific_trigger = "reveal_alter_ego" if identity_card.is_alter_ego_form() else "reveal_hero"
		var specific_reveal = cfc.set_scripts.get(canonical_id,{}).get(specific_trigger,{})
		if specific_reveal:
			trigger = specific_trigger		
				
	if _debug:
		display_debug("executing scripts :" +trigger_card.canonical_name + "-'"+ to_json(orig_trigger_details))	


	
	#if set to false we'll skip the (potential) optional confirmation
	#this is useful e.g. in interrupt mode where we have a better UI
	var show_optional_confirmation_menu = true

	var force_user_interaction_required = false
	if trigger == "manual":
		force_user_interaction_required = true
		if gameData.is_forced_interrupt_mode():
			force_user_interaction_required = false

	orig_trigger_details["trigger_type"] = trigger
#	orig_trigger_details.erase("is_interrupt_or_response")
		
	#we're playing a card manually but in interrupt mode.
	#What we want to do here is play the optional triggered effect instead
	if (trigger == "manual" and gameData.is_interrupt_mode()):
		#TODO very flaky code, how to fix?
		if (canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME):
			var _tmp =1
		var interrupted_event_data = gameData.theStack.get_current_interrupted_event()
		trigger_card = interrupted_event_data["event_object"].owner #this is geting gross, how to clear that?
		if (!trigger_card):
#			return null	
			trigger_card = self	
		var interrupt_script_data = find_interrupt_script(trigger_card, interrupted_event_data)
		trigger = interrupt_script_data["trigger"] if interrupt_script_data else ""
		if (!trigger):
			return null
		orig_trigger_details.merge(gameData.theStack.get_current_interrupted_event(), true)
		#network_prepaid causing trouble as usual...
		orig_trigger_details.erase("network_prepaid")
		if (!orig_trigger_details):
			return null

		#skip optional confirmation menu for interrupts,
		#we have a different gui signal
		if get_state_exec()	in ["hand", "board"]:
			show_optional_confirmation_menu = false	
		orig_trigger_details["is_interrupt_or_response"] = true

	if ! get_potential_scripts(trigger):
		return null

	#from this point we work on a copy of the passed trigger_details,
	#to avoid modifying the original ones
	var trigger_details = orig_trigger_details.duplicate()

	var checksum = trigger
	if trigger_card:
		checksum += " - " + trigger_card.canonical_name
	if _debug:
		cfc.LOG("reached step 1 for: " + checksum  )	
	#var only_cost_check = is_dry_run(run_type)
		
#	var cost_check_mode = \
#		CFInt.RunType.BACKGROUND_COST_CHECK if run_type == CFInt.RunType.BACKGROUND_COST_CHECK \
#		else CFInt.RunType.COST_CHECK
	
	common_pre_execution_scripts(trigger_card, trigger, trigger_details)
	
	#select valid scripts that match the current trigger
	var card_scripts = retrieve_filtered_scripts(trigger_card, trigger, trigger_details)
	
	#tells the game engine to not display this event prominently to the users
	if card_scripts.get("_silent", false):
		trigger_details["_silent"] = true
	
	for key in ["macro_name", "display_section"]:
		if card_scripts.has(key):
			trigger_details[key] = card_scripts[key]
	
	trigger_details["_display_name"] = card_scripts.get("display_name", trigger_details.get("_display_name", ""))

	var script_is_optional = card_scripts.get("is_optional_" + get_state_exec(), false) or  card_scripts.get("is_optional_all", false)

	show_optional_confirmation_menu = show_optional_confirmation_menu and script_is_optional		

	exec_config = {
		"show_optional_confirmation_menu" : show_optional_confirmation_menu,
		"checksum": checksum,
		"force_user_interaction_required": force_user_interaction_required
	}

	# We select which scripts to run from the card, based on it state	
	state_scripts_dict = get_state_scripts_dict(card_scripts, trigger_card, trigger_details, exec_config)

	#delete this to avoid sending "script_executed" over and over
	#trigger_details["action_name_id"] = ""
	trigger_details["action_name_id"] = card_scripts.get("action_name_id","")
		
	var rules = state_scripts_dict.get("rules", {})

	var sceng = null
	if rules.get("for_each_player", false):
		rules.erase("for_each_player")
		for i in gameData.get_team_size():
			var hero_id = i+1
			
			if rules.get("exclude_first_player", false):
				if hero_id == gameData.first_player_hero_id():
					rules.erase("exclude_first_player")
					continue
					
			var hero_triggers = trigger_details.duplicate()
			hero_triggers["override_hero_id"] = hero_id
			hero_triggers["state_scripts_dict"] = state_scripts_dict.duplicate()
			hero_triggers["exec_config"] = exec_config.duplicate()
			gameData.add_script_to_execute(self, trigger_card, trigger, hero_triggers, run_type)
		#kickstart the process to return a sceng object if possible
		gameData.execute_priority_scripts()	
	else:	
		sceng = choose_and_execute_scripts(state_scripts_dict, trigger_card, trigger, trigger_details, run_type, exec_config)
		if sceng is GDScriptFunctionState: # Still working.
			if !trigger in ["manual", "manual_override"]:
				var origin_event = trigger_details.get("origin_event", null)
				gameData.theAnnouncer.choices_menu(self, trigger, origin_event, cfc.get_modal_menu())			
			
			sceng = yield(sceng, "completed")
	return sceng
	
func choose_and_execute_scripts(state_scripts_dict, trigger_card, trigger, trigger_details, run_type, exec_config = {}):	
	var state_scripts = state_scripts_dict["state_scripts"]
	if !state_scripts:
		return null
		
	var rules = state_scripts_dict.get("rules", {})



	var show_optional_confirmation_menu = exec_config.get("show_optional_confirmation_menu", false)
	var checksum = exec_config.get("checksum", "")
	var force_user_interaction_required = exec_config.get("force_user_interaction_required", false)	
	#Check if this script is exected from remote (another online player has been paying for the cost)
	var is_network_call = trigger_details.has("network_prepaid") #TODO MOVE OUTSIDE OF Core
	var origin_event = trigger_details.get("origin_event", null)
	
	#semaphores
	cfc.add_ongoing_process(self, "core_execute_scripts")
	
	var action_name = state_scripts_dict["action_name"]


	var _debug = trigger_details.get("_debug", false)

	var interaction_authority:UserInteractionAuthority = UserInteractionAuthority.new(self, trigger_card, trigger, trigger_details, run_type)
	var interaction_authorized = interaction_authority.interaction_authorized()	
	var interacting_hero = interaction_authority.authorized_hero_id()
	if _debug:
		cfc.LOG("reached step 2 for: " + checksum + ". InteractionAuthority says " + to_json(interaction_authority.compute_authority())  )
	

	# Here we check for confirmation of optional trigger effects
	# There should be an SP.KEY_IS_OPTIONAL definition per state
	# E.g. if board scripts are optional, but hand scripts are not
	# Then you'd include an "is_optional_board" key at the same level as "board"
	# Here we check for confirmation of optional trigger effects
	# There should be an SP.KEY_IS_OPTIONAL definition per state
	# E.g. if board scripts are optional, but hand scripts are not
	# Then you'd include an "is_optional_board" key at the same level as "board"

	if show_optional_confirmation_menu:
		if typeof(state_scripts) == TYPE_ARRAY:
			for script in state_scripts:
				#if the script is targeted, we have an option to cancel there
				if script.get("subject") in ["target", "boardseek"]:
					show_optional_confirmation_menu = false
	if show_optional_confirmation_menu and !is_network_call:
		if !interaction_authorized:
			cfc.remove_ongoing_process(self, "core_execute_scripts")
			gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "pending interaction because of optional dialog")		
			return null

		gameData.select_current_playing_hero(interacting_hero)
		force_user_interaction_required = true	
		
		var confirm_return = cfc.ov_utils.confirm(
			self,
			{
				"is_optional_" + get_state_exec() : true,
				"announcer_data": {
					"origin_event": origin_event,
					"interacting_hero": interacting_hero
				}
			},
			canonical_name,
			trigger,
			get_state_exec())
		if confirm_return is GDScriptFunctionState: # Still working.			
			confirm_return = yield(confirm_return, "completed")
			# If the player chooses not to play an optional cost
			# We consider the whole cost dry run unsuccesful
			if not confirm_return:
				if origin_event and trigger_details.get("is_interrupt_or_response", false):
					gameData.theStack.pass_interrupt_for_card(origin_event, self)
				gameData.theStack.resume_operations_to_all(checksum)
				state_scripts = []
	
	# If the state_scripts return a dictionary entry
	# it means it's a multiple choice between two scripts
	if typeof(state_scripts) == TYPE_DICTIONARY:	
		var selected_key = ""
		if run_type == CFInt.RunType.BACKGROUND_COST_CHECK:
			selected_key = state_scripts.keys()[0]
			#TODO need to help check costs here as well?
		else:
			if !interaction_authorized:
				gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "not authorized to multiple choice " + to_json(state_scripts))
				cfc.remove_ongoing_process(self, "core_execute_scripts")
				return null	
			force_user_interaction_required = true				
			gameData.select_current_playing_hero(interacting_hero)
			cfc.game_paused = true
			
			#enrich display title as needed
			var msg_suffixes = rules.get("choice_msg_suffix", [])
			if typeof(msg_suffixes) == TYPE_STRING:
				msg_suffixes = [msg_suffixes]
			var msg_suffix = ""	
			if msg_suffixes:
				for msg_fragment in msg_suffixes:
					msg_suffix += compute_message_fragment(msg_fragment, trigger_details)
			var title_reference = canonical_name
			if msg_suffix:
				title_reference += " " + msg_suffix
				
			var choices_menu = _CARD_CHOICES_SCENE.instance()
			cfc.add_modal_menu(choices_menu)
			choices_menu.prep(title_reference,state_scripts, rules)
#			if trigger != "manual":
#				gameData.theAnnouncer.choices_menu(self, origin_event, choices_menu, interacting_hero)			
			# We have to wait until the player has finished selecting an option
			yield(choices_menu,"id_pressed")
			# If the player just closed the pop-up without choosing
			# an option, we don't execute anything
			selected_key = choices_menu.selected_key if choices_menu.id_selected else ""
			# Garbage cleanup
			cfc.remove_modal_menu(choices_menu)
			choices_menu.queue_free()
			cfc.game_paused = false
			if !selected_key:
				gameData.theStack.resume_operations_to_all(checksum)
		if selected_key:
			state_scripts = state_scripts[selected_key]
			action_name = selected_key
			trigger_details["action_name_id"] = action_name.to_lower().replace(" ", "_")
		else: 
			state_scripts = []

	# To avoid unnecessary operations
	# we evoke the ScriptingEngine only if we have something to execute
	# We do not statically type it as this causes a circular reference
	var sceng = null
	var shortname = properties.get("shortname", canonical_name)
	if len(state_scripts):
		if ! trigger_details.get("action_name_id", ""):
			trigger_details["action_name_id"] = action_name
		if action_name:
			action_name = shortname + "(" + action_name + ")"
		else:
			action_name = shortname
		action_name = action_name + " - " + trigger
		action_name =  trigger_details.get("_display_name", action_name) #override		
		
		var next_step_config = {
			"trigger": trigger,
			"checksum": checksum,
			"rules": rules,
			"action_name": action_name,
			"force_user_interaction_required": force_user_interaction_required,
			"interaction_authority": interaction_authority,
		}
		sceng = execute_chosen_script(state_scripts, trigger_card, trigger_details, run_type, next_step_config)
		if sceng is GDScriptFunctionState && sceng.is_valid():		
			yield(sceng,"completed")
		
	cfc.remove_ongoing_process(self, "core_execute_scripts")	
	emit_signal("scripts_executed", self, sceng, trigger)
	return(sceng)

func execute_chosen_script(state_scripts, trigger_card,  trigger_details, run_type, exec_config: = {} ):
	var sceng = null
	is_executing_scripts = true

	var rules = exec_config.get("rules",{})
	var trigger = exec_config.get("trigger", "")
	var checksum = exec_config.get("checksum", "")
	var action_name = exec_config.get("action_name", "")
	var force_user_interaction_required = exec_config.get("force_user_interaction_required", false)
	var interaction_authority = exec_config.get("interaction_authority", null)
	
	var cost_check_mode = \
		CFInt.RunType.BACKGROUND_COST_CHECK if run_type == CFInt.RunType.BACKGROUND_COST_CHECK \
		else CFInt.RunType.COST_CHECK

	#Check if this script is exected from remote (another online player has been paying for the cost)
	var is_network_call = trigger_details.has("network_prepaid") #TODO MOVE OUTSIDE OF Core

	var only_cost_check = is_dry_run(run_type)

	#if optional tags are passed, merge them with this invocation
	if trigger_details.has("additional_tags"):
		var tags = trigger_details["additional_tags"]
		for t in state_scripts:
			t["tags"] = t.get("tags", []) + tags

	if trigger_details.has("additional_script_definition"):
		var additional_def = trigger_details["additional_script_definition"]
		for t in state_scripts:
			for def in additional_def:
				t[def] = additional_def[def]
			
	# This evocation of the ScriptingEngine, checks the card for
	# cost-defined tasks, and performs a dry-run on them
	# to ascertain whether they can all be paid,
	# before executing the card script.
	sceng = cfc.scripting_engine.new(
			state_scripts,
			self,
			trigger_card,
			trigger_details)

	sceng.add_rules(rules)				
			
	common_pre_run(sceng)
	
	# 1) Client A selects payments for ability locally
	# In case the script involves targetting, we need to wait on further
	# execution until targetting has completed
	var sceng_return = sceng.execute(cost_check_mode)
	#if not sceng.all_tasks_completed:
	if sceng_return is GDScriptFunctionState && sceng_return.is_valid():		
		yield(sceng_return,"completed")
	
	# If the dry-run of the ScriptingEngine returns that all
	# costs can be paid, then we proceed with the actual run
	# we add the script to the server stack for execution
	if (!is_network_call and not only_cost_check):
		if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER:
			gameData.theStack.set_pending_network_interaction(interaction_authority,  checksum, "not authorized to pay cost")
			cfc.remove_ongoing_process(self, "core_execute_scripts")
			return sceng			
		if (sceng.can_all_costs_be_paid or sceng.has_else_condition()):
			#1.5) We run the script in "prime" mode again to choose targets
			# for all tasks that aren't costs but still need targets
			# (is_cost = false and needs_subject = false)
			sceng_return = sceng.execute(CFInt.RunType.PRIME_ONLY)
			#if not sceng.all_tasks_completed:
			if sceng_return is GDScriptFunctionState && sceng_return.is_valid():				
				yield(sceng_return,"completed")
			
			if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER:
				gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "not authorized to prime")
				cfc.remove_ongoing_process(self, "core_execute_scripts")
				return sceng
			if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.DONE_INTERACTION_NOT_REQUIRED:
				if force_user_interaction_required:
					sceng.user_interaction_status = CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER
			
			
			# 2) Once done with payment, Client A sends ability + payment information to all clients (including itself)
			# 3) That data is added to all clients stacks

			if trigger_details.get("use_stack", true):
				var func_return = add_script_to_stack(sceng, run_type, trigger, trigger_details, action_name, checksum)
				while func_return is GDScriptFunctionState && func_return.is_valid():
					func_return = func_return.resume()
			else:
				sceng_return = sceng.execute(run_type)
				while sceng_return is GDScriptFunctionState && sceng_return.is_valid():
					sceng_return = sceng_return.resume()	

		else:
			#cleanup after cost failure
			if sceng and sceng.network_prepaid:
				for prepaid_data in sceng.network_prepaid:
					var prepaid_subjects = prepaid_data["subjects"]
					for card in prepaid_subjects:
						if card as Card:
							card.remove_resource_lock()
	is_executing_scripts = false
	return sceng

func add_script_to_stack(sceng, run_type, trigger, trigger_details, action_name, checksum):
	gameData.theStack.create_and_add_script(sceng, run_type, trigger, trigger_details, action_name, checksum) 
	
	return


# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
	if !cfc.NMAP.has("board"):
		return
		
	cfc.add_ongoing_process(self, "_on_Card_gui_input_" + canonical_name)

	if event is InputEventMouseButton:	
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
				and not are_hovered_manipulation_buttons() \
				and not tokens.are_hovered():

			if event.doubleclick and (get_state_exec() == "hand"):
				attempt_to_play(true)
			# If it's a long click it might be because
			# they want to drag the card

			if state in [CardState.FOCUSED_IN_HAND]:
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
					z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
					for attachment in self.attachments:
						attachment.z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL

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
						attempt_to_play(true)
					else :	
						move_to(destination)
					_focus_completed = false
				_:
					if state != CardState.FOCUSED_IN_HAND:
						attempt_to_play(true)
		else:
			_process_more_card_inputs(event)
	elif event is InputEvent:
		if event.is_action_pressed("ui_accept"):
			attempt_to_play(true)
			
	cfc.remove_ongoing_process(self, "_on_Card_gui_input_"  + canonical_name)	

func compute_message_fragment(message_data, trigger_details):
	var script = trigger_details.get("event_object", null)
	match typeof(message_data):
		TYPE_STRING:
			if message_data.begins_with("trigger_details_"):
				var property = message_data.replace("trigger_details_", "")
				return str(trigger_details.get(property))				
			return message_data
		TYPE_INT, TYPE_REAL:
			return str(message_data)
		TYPE_DICTIONARY:
			var func_name = message_data.get("func_name", "")
			var func_params = message_data.get("func_params", "")
			var result = self.call(func_name, func_params, script)
			return str(result)
# Game specific code and/or shortcuts
func readyme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
	
	if get_property("cannot_ready", 0, true):
		return CFConst.ReturnCode.FAILED
	
	if current_host_card and (is_inactive_attachment() or !is_faceup):
		#we won't ready inactive/facedown attachments
		#this is a cosmetic thing to avoid them switching to 90 degrees at the beginning of phase
		return CFConst.ReturnCode.FAILED
	
	var rot = 0
	if CFConst.OPTIONS.get("enable_fuzzy_rotations", false):
		if (is_exhausted()):			
			rot = randi() % 11 - 5
			tags = tags + ["force"]
	
	if !check :
		_set_target_rotation(rot)
		
	if 	!is_exhausted()	and not toggle:
		return CFConst.ReturnCode.OK		
			
	var retcode = set_card_rotation(rot, toggle, start_tween, check, tags)
	if !check and retcode != CFConst.ReturnCode.FAILED:
		var before = _is_exhausted
		_is_exhausted = false
		if before:
			scripting_bus.emit_signal_on_stack("card_readied", self, {})
	return retcode
	
func exhaustme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
				
	var rot = 90	
	if CFConst.OPTIONS.get("enable_fuzzy_rotations",false):
		if (!is_exhausted()):			
			rot = randi() % 16 + 80
			tags = tags + ["force"]
	
	if !check:
		_set_target_rotation(rot)
			
	if 	is_exhausted()	and not toggle:
		return CFConst.ReturnCode.OK		
					
	var retcode = set_card_rotation(rot, toggle, start_tween, check, tags)
	if !check and retcode != CFConst.ReturnCode.FAILED:
		_is_exhausted = true
		scripting_bus.emit_signal_on_stack("card_exhausted", self, {})
	return retcode	
	
func add_threat(threat : int):
	tokens.mod_token("threat",threat)

func get_current_threat():
	return tokens.get_token_count("threat")

func check_scheme_defeat(script):
	if get_current_threat() <= 0:
	#card.die(script)
		if get_property("cannot_leave_play", 0, true):
			return

		if get_property("permanent", 0):
			var set_code = get_property("card_set_code", "")
			var owner_set_code = script.owner.get_property("card_set_code", "")
			if set_code != owner_set_code:
				return 

		var tags = script.get_property(SP.KEY_TAGS)
		var trigger_details = script.trigger_details.duplicate(true)
		trigger_details["source"] = guidMaster.get_guid(script.owner)
				
		#if the threat removal comes from a "thwart", ensure the source is properly categorized as
		#the character owner rather than the event card itself
		if ("thwart" in tags):
			var owner = WCScriptingEngine.get_actual_action_source_from_script(script)	
			trigger_details["secondary_source"] = trigger_details["source"]
			trigger_details["source"] = guidMaster.get_guid(owner)
			trigger_details["actual_source"] = guidMaster.get_guid(owner)
			
		var card_dies_definition = {
			"name": "card_dies",
			"tags": ["remove_threat", "Scripted"] + tags
		}
		
		for param in ["source", "secondary_source", "actual_source"]:
			if trigger_details.has(param):
				card_dies_definition[param] = trigger_details[param]
			
		var card_dies_script:ScriptTask = ScriptTask.new(self, card_dies_definition, script.trigger_object, trigger_details)
		card_dies_script.set_subjects(self)

		var task_event = SimplifiedStackScript.new( card_dies_script)
		gameData.theStack.add_script(task_event)


func remove_threat(modification: int, script = null) -> int:	
	var action_owner = null
	if script:
		action_owner = script.owner
		var type = action_owner.get_property("type_code", "")
		if !type in CFConst.CONSIDERED_AS_ACTION_OWNER:
			action_owner = WCScriptingEngine._get_identity_from_script(script)
	
	var bypass_crisis = action_owner.get_property("bypass_crisis", 0, true) if action_owner else 0
	bypass_crisis = bypass_crisis or (script and script.has_tag("bypass_crisis"))
	#Crisis special case: can't remove threat from main scheme
	if "main_scheme" == properties.get("type_code", "false"):
		var all_cards:Array = cfc.NMAP.board.get_all_cards()
		#some main schemes such as countdown to oblivion give themselves crisis,
		#so it's ok to include the card itself in there
		for card in all_cards:
			#we add all acceleration tokens	
			var crisis = card.get_property("scheme_crisis", 0, true)
			if crisis:
				if !self in card.get_active_main_schemes(): #last verification to make sure that the crisis card considers this main scheme as an active main scheme
					crisis = false
			if crisis:
				if bypass_crisis:
					scripting_bus.emit_signal_on_stack("bypass_crisis_happened", action_owner, {"target": card})
					card.hint("Bypassed!", Color8(50, 200, 50))
					self.hint("Bypassed!", Color8(50, 200, 50))				
				else:
					card.hint("Crisis!", Color8(200, 50, 50))
					self.hint("Crisis!", Color8(200, 50, 50))
					return CFConst.ReturnCode.FAILED
	
	if get_property("cannot_remove_threat", 0, true):
		self.hint("Protected!", Color8(200, 50, 50))
		return CFConst.ReturnCode.FAILED
					
	var token_name = "threat"
	var current_tokens = tokens.get_token_count(token_name)
	if current_tokens - modification <= 0:
		modification = current_tokens
	var result = tokens.mod_token(token_name,-modification)
	
	var new_amount = tokens.get_token_count(token_name)
	if current_tokens > 0 and !new_amount:	
		var signal_details = {}
		if script:	
			signal_details = {
				"source":  script.owner,
				"tags": script.get_property(SP.KEY_TAGS)	
			}
		scripting_bus.emit_signal("last_threat_removed", self, signal_details)		
	return result

func discard():	
	#move to correct pile
	var hero_owner_id = get_owner_hero_id()
	if (!hero_owner_id):
		self.move_to(cfc.NMAP["discard_villain"])
	else:
		var destination = "discard" + str(hero_owner_id)
		self.move_to(cfc.NMAP[destination])

	#cleanup some variables
	set_is_boost(false)
	set_is_inactive_attachment(false)

func can_attack():
	var atk = get_property("attack", null)
	if atk == null:
		return false

	if get_property("cannot_attack", false):
		return false
	
	return get_property("can_attack", false)

#returns the amount of healing that could happen for a given heal value
func can_heal(value):
	var current_damage = tokens.get_token_count("damage")
	return min(value, current_damage)	

func heal(value, set_to_mod = false):
	if set_to_mod:
		var health = get_property("health", 0)
		return tokens.mod_token("damage",health-value, true)
	else:
		var current_damage = tokens.get_token_count("damage")			
		var heal_value = min(value, current_damage)
		return tokens.mod_token("damage",-heal_value)


func common_pre_execution_scripts(_trigger_card, _trigger: String, _trigger_details: Dictionary) -> void:
	match _trigger:
		"enemy_attack":
			gameData.compute_potential_defenders(gameData.get_current_activity_hero_target(), _trigger_card)

#checks if a character can defend for the "normal" defender selection step
func can_defend(hero_id = 0):
	if is_exhausted() : return false

	var type_code = get_property("type_code", "")
	if type_code != "hero" and type_code != "ally": return false
	
	var controller_hero_id = get_controller_hero_id()
	if controller_hero_id <= 0:
		return false
	
	if hero_id:
		if controller_hero_id != hero_id:
			return false

	if get_property("cannot_defend", 0, true):
		return false
	
	return true

func post_death_move():
	var card = self
	var type = card.get_property("type_code", "")
	var owner_hero_id = card.get_owner_hero_id()
	
	var victory_property = card.get_property("victory", null)
	if victory_property != null:
		gameData.move_to_victory(card)
	else:
		if owner_hero_id > 0:
			card.move_to(cfc.NMAP["discard" + str(owner_hero_id)])
		else:
			if type in ["ally"]:
				card.move_to(cfc.NMAP["discard" + str(card.get_controller_hero_id())])
			else:
				card.move_to(cfc.NMAP["discard_villain"])	

func die(script):
	var type_code = properties.get("type_code", "")
	if !script.trigger_details:
		script.trigger_details = {}
#	var trigger_details = script.trigger_details.duplicate() if script.trigger_details else []
	if !script.trigger_details.get("tags", []):
		script.trigger_details["tags"] = []
	script.trigger_details["tags"] += script.get_property("tags", [])
#	if script and !script.trigger_details.get("tags", []):
#		script.trigger_details["tags"] = script.get_property("tags", [])
	match type_code:
		"hero", "alter_ego":
			gameData.hero_died(self, script)
		"ally", "minion":
			gameData.character_died(self, script)
		"side_scheme", "player_side_scheme":
			post_death_move()
#			move_to(cfc.NMAP["discard_villain"])	
		"villain":
			gameData.villain_died(self, script)
		_:
			self.discard()

	scripting_bus.emit_signal_on_stack("card_defeated", self, script.trigger_details)			
	#scripting_bus.emit_signal("card_defeated", self, trigger_details)			
	return CFConst.ReturnCode.OK		

var _cached_state = -1
func _process_card_state() -> void:
	
	#if state hasn't changed and we're on a low fps machine,
	#reduce calls to this function
	if _cached_state == state:
		if CFConst.PERFORMANCE_HACKS:
			if state in [CardState.IN_PILE]:
				if _controller_hero_id: 
					if _controller_hero_id != gameData.get_current_local_hero_id():
						set_process_recursive(false)
						return
				else:
					if get_parent().name.to_lower() in ["set_aside", "removed_from_game", "tmp_pile1", "tmp_pile2" , "tmp_pile3"  ]:
						set_process_recursive(false)
						return		
		if cfc.throttle_process_for_performance():
			return
	

	_cached_state = state	
	._process_card_state()

	#TODO bug?
	#sometimes the card reports being "faceup" while actually showing the back
	#this is a fix for that
	if _card_back_container.visible == is_faceup:
		is_faceup = !is_faceup
		set_is_faceup(!is_faceup, true)
	match state:
		CardState.ON_PLAY_BOARD:
			#horizontal cards are always forced to horizontal
			#does that need to change eventually ?	
			#note: setting tweening to false otherwise it causes issues with
			#tweening never ending
			if _horizontal and not _is_boost:
				set_card_rotation(90, false, false)
	
		




#checks executable scripts for cards in discard pile,
#and attempts to create a "ghost" card in hand if needed
func check_ghost_card():
	for i in range(gameData.get_team_size()):
		cfc.NMAP["ghosthand" + str(i+1)].check_ghost_card(self)
	
# This function can be overriden by any class extending Card, in order to provide
# a way of checking if a card can be played before dragging it out of the hand.
#
# This method will be called while the card is being focused by the player
# If it returns true, the card will be highlighted as normal and the player
# will be able to drag it out of the hand
#
# If it returns false, the card will be highlighted with a red tint, and the
# player will not be able to drag it out of the hand.
func check_play_costs_no_cache(hero_id = 0, _debug = false)-> Color:
	if !hero_id:
		hero_id = gameData.get_current_local_hero_id()
	_check_play_costs_cache[hero_id] = CFConst.CostsState.CACHE_INVALID
	return check_play_costs({"hero_id" : hero_id}, _debug)

	
func check_play_costs(params:Dictionary = {}, _debug = false) -> Color:
	#return .check_play_costs();
	var hero_id = params.get("hero_id", gameData.get_current_local_hero_id())

	if (_check_play_costs_cache.get(hero_id,CFConst.CostsState.CACHE_INVALID) != CFConst.CostsState.CACHE_INVALID):
		return _check_play_costs_cache[hero_id]
	
	_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE

	#skip if card is not in hand and not on board. TODO: will have to take into account cards than can be played from other places
	var state_exec = get_state_exec()

	if !(state_exec in ["hand", "board"]):
		return _check_play_costs_cache[hero_id]
	
	var trigger_details = {
		"for_hero_id": hero_id,
		"_debug": _debug
	}
		
	var sceng = execute_scripts(self,"manual",trigger_details,CFInt.RunType.BACKGROUND_COST_CHECK)

	if (!sceng): #TODO is this an error?
		_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE	
		return _check_play_costs_cache[hero_id]
		
	while sceng is GDScriptFunctionState && sceng.is_valid(): # Still working.
		sceng = sceng.resume()
		#sceng = yield(sceng, "completed")

	if (!sceng): #TODO is this an error?
		_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE	
		return _check_play_costs_cache[hero_id]
	
	if (sceng.can_all_costs_be_paid):
		_check_play_costs_cache[hero_id] = CFConst.CostsState.OK


	return _check_play_costs_cache[hero_id]


# This function can be overriden by any class extending Card, in order to provide
# a way of running special functions on an extended scripting engine.
#
# It is called after the scripting engine is initiated, but before it's run
# the first time
#
# Used to hijack the scripts at runtime if needed
func common_pre_run(sceng) -> void:
	var trigger_details = sceng.trigger_details
	
	var controller_hero_id = trigger_details.get("override_controller_id", self.get_controller_hero_id())
	
	var rules = sceng.additional_rules
	var scripts_queue: Array = sceng.scripts_queue
	var new_queue: Array = []
	var temp_queue: Array = []
	
	var zones = ["hand"] + CFConst.HERO_GRID_SETUP.keys() + cfc.NMAP.board.heroes_extra_deck_names()
		
				
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition
		var scripts = [script]
		if script_definition.get("for_each_player", false):	
			scripts = []
			for i in gameData.get_team_size():
				var hero_id = i+1

				if script_definition.get("exclude_first_player", false):
					if hero_id == gameData.first_player_hero_id():
						script_definition.erase("exclude_first_player")
						continue
				
				var new_script_definition = script_definition.duplicate(true)
				new_script_definition.erase("for_each_player")
				for v in zones: #["hand", "encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
					new_script_definition = WCUtils.search_and_replace(new_script_definition, v, v+str(hero_id), true)	

				var new_script = ScriptTask.new(script.owner, new_script_definition, script.trigger_object, script.trigger_details)
				scripts.append(new_script)
		for _script in scripts:
			temp_queue.append(_script)
	
	scripts_queue = temp_queue	

	var pay_resource_index = 0
	
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition			
		var replacements = {}
		for v in zones:
			replacements[v + "_first_player"] = v+str(gameData.first_player_hero_id())
		#first player explcitely mentioned
		script_definition = WCUtils.search_and_replace_multi(script_definition, replacements , true)	
		replacements = {}
		
		if (controller_hero_id <=0 ):
			var card_type = task.owner.get_property("type_code")
			if card_type in ["scheme", "main_scheme", "minion", "side_scheme", "treachery"]:
				pass
			else:
				cfc.LOG("error controller hero id is not set for script:" + task.script_name )
		else:
			#var current_hero_id = gameData.get_current_hero_id()
			for v in zones:
				#TODO move to const
				replacements[v] = v+str(controller_hero_id)


				#any_discard, etc gets replaced with ["discard1","discard2"] 
				var team_size = gameData.get_team_size()
				var any_container_def = []
				for i in range (team_size):
					any_container_def.append(v + str(i+1))
				if any_container_def.size() == 1:
					any_container_def = any_container_def[0]
				replacements["any_" + v] = any_container_def	
			script_definition = WCUtils.search_and_replace_multi(script_definition, replacements , true)	
	
		#put back the modified script			
		script.script_definition = script_definition
				
		match script_definition["name"]:
			# To pay for cards:
			"pay_cost",\
			"pay_regular_cost":
				var new_script = pay_regular_cost_replacement(script, trigger_details)
				if (new_script) :
					pay_resource_index+= 1
					new_script["_pay_resource_index"] = pay_resource_index
					script.script_definition = new_script
					script.script_name = script.get_property("name") #TODO something cleaner? Maybe part of the script itself?
					new_queue.append(script)
			"indirect_damage":
				var subject = get_param_subject(script.script_definition, script)
				var new_script = subject.indirect_damage_replacement(script_definition, trigger_details)
				if (new_script) :
					script.script_definition = new_script
					script.script_name = script.get_property("name") #TODO something cleaner? Maybe part of the script itself?
					new_queue.append(script)					
			"end_phase_discard":
				#end phase discard is either optional, or forced if we're above max_hand_size
				var hero = script.owner
				var max_hand_size = hero.get_max_hand_size()
				var hero_id = hero.get_controller_hero_id()
				var hand:Hand = cfc.NMAP["hand" + str(hero_id)]
				var current_hand_size = hand.get_card_count()
				var min_to_discard = 0
				if (current_hand_size > max_hand_size):
					min_to_discard = current_hand_size - max_hand_size
				script.script_name = "discard"
				script.script_definition["name"] = script.script_name
				if (min_to_discard > 0):
					script.script_definition["selection_optional"] = false
					script.script_definition["selection_count"] = min_to_discard

				new_queue.append(script)
			"enemy_attack":
				var attacker = script.owner
				if attacker.activity_script and attacker.activity_script.subjects:
					#erase subject selection if we already have a defender
					#this bypasses the set defenders step + bypasses some interactionStatus verification 
					script.script_definition.erase("subject")
					script.script_definition.erase(SP.KEY_NEEDS_SELECTION)
					
				var modifiers = attacker.retrieve_scripts("modifiers")
				var defense_selection_modifier = modifiers.get("defense_selection", "")
				match defense_selection_modifier:
					#TODO this is split with GameData.compute_potential_defenders(), need a cleaner, centralized place
					"my_allies_if_able":
						var defenders = cfc.get_tree().get_nodes_in_group("group_defenders")
						var found_ally = false
						for c in defenders:
							if c.get_property("type_code") == "ally":
								found_ally = true
								break
						if found_ally:
							script.script_definition[SP.KEY_SELECTION_TYPE] = "equal"
							script.script_definition[SP.KEY_SELECTION_OPTIONAL] = false
				new_queue.append(script)
			"change_form":
				if script_definition.has("form_family") or script_definition.has("form_name"):
					var new_script = change_form_script_replacement(script_definition, trigger_details)
					if (new_script) :
						script.script_definition = new_script
						script.script_name = script.get_property("name") #TODO something cleaner? Maybe part of the script itself?
						new_queue.append(script)	
				else:
					new_queue.append(task)
			"remove_threat":
				if !script_definition.has("source"):
					var source = script.get_property("source", script.owner)

					var source_character = WCScriptingEngine.get_actual_action_source_from_script(script)
					script.script_definition["source"] = source
					script.script_definition["actual_source"] = source_character		
				new_queue.append(script)														
			_:
				new_queue.append(task)
	
	#if script is marked as forced, 
	#we force selections to be non-optional
	# see Tests/test_1p_drang_blind_side.json
	if rules.get("forced", false):
		for task in new_queue:
			var script: ScriptTask = task
			var script_definition = script.script_definition
			if script_definition.get("needs_selection", false):
				script_definition[SP.KEY_SELECTION_OPTIONAL] = false
	
	sceng.scripts_queue = new_queue	

func change_form_script_replacement(script_definition: Dictionary, trigger_details) -> Dictionary:	
	#var owner_hero_id = trigger_details.get("override_controller_id", self.get_owner_hero_id())

	var family = script_definition.get("form_family", "")
	var new_form = script_definition.get("form_name", "")
	if !family and new_form:
		var new_form_card = cfc.NMAP.board.find_card_by_name(new_form, false, true)
		family = new_form_card.get_property("form_family", "")
			
	if !family:
		return {}
	
	#get list of cards we can change to
	var available_forms = []
	for card in cfc.NMAP["set_aside"].get_all_cards():
		var card_family = card.get_property("form_family", "")
		if  card_family == family:
			available_forms.append(card)	
	
	#if we can't switch to anything, we fail
	if !available_forms:
		return {}
	
	#get current form if any
#	var current_form = cfc.NMAP.board.find_card_by_property("form_family", family, owner_hero_id)
			

	var change_form_script = []
	#a new form is provided, we want to change to that
	if new_form:
		# if we want to switch to a form that isn't available
		# (possibly because we're already in that form), we fail
		var new_form_available = false
		for card in available_forms:
			if card.canonical_name.to_lower() == new_form.to_lower():
				new_form_available = true
				break
		if !new_form_available:
			return {}
		
		#new form is available, we return the script
		change_form_script = {
			"name": "change_secondary_form",
			"src_container": "set_aside",
			"subject": "tutor",
			"subject_count": 1,
			"filter_state_tutor": [
				{
					"filter_properties": {
						"Name": new_form
					}
				},
			]
		}
			
	#no new form is provided, leave user the choice
	else:
		change_form_script = {
			"name": "change_secondary_form",
			"src_container": "set_aside",
			"subject": "tutor",
			"subject_count": "all",
			"selection_count": 1,
			"selection_type": "equal",
			"needs_selection": true,
			"filter_state_tutor": [
				{
					"filter_properties": {
						"form_family": family
					}
				},
			]
		}

	return change_form_script

#TODO cleanup, probably doesn't need to be a replacement
func indirect_damage_replacement(script_definition: Dictionary, trigger_details) -> Dictionary:	
	var controller_hero_id = trigger_details.get("override_controller_id", self.get_controller_hero_id())

	# For cards owned by the Villain, owner_hero_id is zero.
	# we set it to the current playing hero, meaning the currently active user
	# can pay the cost
	#TODO how does it work in Multiplayer?
	if (!controller_hero_id):
		controller_hero_id = gameData.get_current_local_hero_id()
	
	if script_definition.get("all_players", false):
		controller_hero_id = ""
			
	var filter_state_seek = script_definition.get("filter_state_seek", {})
	
	var amount = script_definition.get("amount", 1)
	
	
	#Note: amount in this case is actually set into selection_count, 
	# due to how "assign_" works in selectionwindow			
	var result  =	WCScriptingEngine.indirect_damage_script_definition (amount, controller_hero_id, filter_state_seek)	
	
	result = WCUtils.merge_dict(script_definition, result, true)

	return result	

		

#TODO cleanup, probably doesn't need to be a replacement
func pay_regular_cost_replacement(script, trigger_details) -> Dictionary:	
	var owner_hero_id = trigger_details.get("override_controller_id", self.get_owner_hero_id())
	var script_definition = script.script_definition
	# For cards owned by the Villain, owner_hero_id is zero.
	# we set it to the current playing hero, meaning the currently active user
	# can pay the cost
	#TODO how does it work in Multiplayer?
	if (!owner_hero_id):
		owner_hero_id = gameData.get_current_local_hero_id()
			
	var manacost:ManaCost = ManaCost.new()
	var cost = script_definition["cost"]
	var is_optional = script_definition.get(SP.KEY_SELECTION_OPTIONAL, true)
	#precompute cost replacement macros
	if (typeof(cost) == TYPE_STRING):
		var subject = self
		match cost:
			"subject_cost":
				subject = get_param_subject(script_definition, script)
				if !subject:
					var _error = 1
					subject = self			
		cost = subject.get_property("override_play_cost", subject.get_property("cost"))
		if subject.get_property("cost_per_player", false):
			cost = cost * gameData.get_team_size()
						
	var selection_additional_constraints = null

	if (typeof(cost) == TYPE_DICTIONARY):
		for key in cost:
			if ManaCost.get_resource_from_keyword(key) != -1:
				var _tmp = script.retrieve_integer_subproperty(key, cost)
				cost[key] = _tmp
		manacost.init_from_dictionary(cost)
		selection_additional_constraints = {
			"func_name": "can_pay_as_resource",
			"using": "all_selection",
			"func_params": cost 
		}
	else:
		manacost.init_from_expression(cost) #TODO better name?
	
	var hero_ids = [owner_hero_id]
	if self.get_property("alliance", 0, true):
		hero_ids = []
		for i in gameData.get_team_size():
			var hero_id = i+1
			hero_ids.append(hero_id)
				
	var resource_container_names = ["hand", "identity","allies","upgrade_support"]
	var resource_containers = []
	for v in resource_container_names:
		for h in hero_ids:
			resource_containers.append(v + str(h) )
			
	var result  ={
				"name": "pay_as_resource",
				"is_cost": true,
				"subject": "index",
				"subject_count": "all",
				"subject_index": "top",
				SP.KEY_NEEDS_SELECTION: true,
				SP.KEY_SELECTION_COUNT: manacost.converted_mana_cost(), 
				SP.KEY_SELECTION_TYPE: "min",
				SP.KEY_SELECTION_OPTIONAL: is_optional,
				SP.KEY_SELECTION_IGNORE_SELF: true,
				"selection_what_to_count": "get_resource_value_as_int",
				"selection_additional_constraints": selection_additional_constraints,
				"src_container": resource_containers
			}		

	var alternative_payment = retrieve_scripts(script_definition["name"] + "_alternative")
	if alternative_payment:
		result["alternative_ok"] = alternative_payment

	return result	

func to_grayscale():
	if card_front:
		card_front.to_grayscale()

func to_color():
	if card_front:
		card_front.to_color()

#
#Marvel Champions Specific functionality
#



func get_associated_villain():
	var sceng = _get_script_sceng("associated_villain")
	if sceng:		
		var sceng_return = sceng.execute(CFInt.RunType.PRIME_ONLY)
		#if not sceng.all_tasks_completed:
		if sceng_return is GDScriptFunctionState && sceng_return.is_valid():				
			yield(sceng_return,"completed")	
		for potential_villain in sceng.all_subjects_so_far:
			var type_code = potential_villain.get_property("type_code")
			if type_code == "villain":
				return potential_villain
		
	return gameData.get_villain()

#easy access functions for tokens that are either 1 or 0

func enable_token(token_name, value:bool):
	if value:
		tokens.mod_token(token_name, 1)
	else:
		tokens.mod_token(token_name, 0, true)	


func get_max_tokens(token_name) -> int:
	if token_name in ["stunned", "confused"]:
		if self.get_property("steady", 0, true):
			return 2

	var max_tokens = self.get_property("max_tokens_" + token_name, 0, true)
	if max_tokens:
		return max_tokens
	
	if CFConst.DEFAULT_TOKEN_MAX_VALUE.has(token_name):
		return CFConst.DEFAULT_TOKEN_MAX_VALUE[token_name]
	
	return 0

func set_stunned(value:bool = true):
	enable_token("stunned", value)

func remove_stun():
	set_stunned(false)

func set_confused(value:bool = true):
	enable_token("confused", value)

func remove_confused():
	set_confused(false)

func can_change_form(voluntary:= false, to_card_id = "") -> bool:
	if self.get_property("cannot_change_form", 0, true):
		return false
	
	#cannot change to alter ego" restriction
	var expected_form = "alter_ego"
	if self.is_alter_ego_form():
		expected_form = "hero"
	if to_card_id:
		var card_data = cfc.get_card_by_id(to_card_id)
		expected_form = card_data["type_code"]		
	if expected_form == "alter_ego":
		if self.get_property("cannot_change_to_alter_ego", 0, true):
			return false	
		
	if voluntary:
		return self.tokens.get_token_count("__can_change_form") > 0
	return true

func changed_form(details):
	var before = details.get("before")
	#in general, after and before are different, but this isn't always the case
	#e.g. Ant-Man can switchbetween giant and tiny hero forms
	var after = "alter_ego" if self.is_alter_ego_form() else "hero"		
	scripting_bus.emit_signal_on_stack("identity_changed_form", self, {"before": before , "after" : after })	


func flip_doublesided_card(to_card_id = ""):
	if !self.is_onboard({"include_zones" : ["encounters_reveal"]}):
		return false
	var new_card = cfc.NMAP.board.flip_doublesided_card(self, to_card_id)

	if !new_card:
		var _error = 1
		return false

		
	return true

func change_form(voluntary = true, to_card_id = "") -> bool:
	if to_card_id == self.canonical_id:
		return false
	#players have one voluntary change form per turn
	#we check for that
	if !can_change_form(voluntary, to_card_id):	
		return false
	if (voluntary):
		self.tokens.mod_token("__can_change_form", 0, true)

	return flip_doublesided_card(to_card_id)
	

#a way to copy all modifications of this card to another card
#used e.g. when flipping card
func export_modifiers():
	var result = {
		"tokens" : tokens.export_to_json(),
		"exhausted" : self.is_exhausted(),
		"inactive_attachment": self.is_inactive_attachment()
	}
	return result

#changes data of the card based on a dictionary
#this is different from loading from json because
# 1) it only impacts some variables, not all,
# 2) it doesn't reset to a default value if the modifier isn't set
func import_modifiers(modifiers:Dictionary, keep_existing = false):
	var token_data = modifiers.get("tokens", {})
	if token_data:
		tokens.load_from_json(token_data, keep_existing)
	
	if modifiers.has("exhausted"):
		if modifiers["exhausted"]:
			exhaustme()
		else:
			readyme()
			
	if modifiers.has("inactive_attachment"):
		self.set_is_inactive_attachment(modifiers["inactive_attachment"])	
	
func is_onboard(params = {}):
	if state in [
		CardState.ON_PLAY_BOARD,
		CardState.FOCUSED_ON_BOARD, 
		CardState.DROPPING_TO_BOARD
	]:
		return true

	if !params:
		return false
	
	var include_zones = params.get("include_zones", [])
	if include_zones:
		var parent = get_parent()
		if !parent:
			return false
		var container_name = parent.name.to_lower()	
		for zone in include_zones:
			if container_name.begins_with(zone):
				return true
		
	return false
func is_onboard_facedown():
	return !is_faceup and is_onboard()

var _hidden_properties = {}
func set_is_faceup(
			value: bool,
			instant := false,
			check := false,
			tags := ["Manual"]) -> int:
	var _before = is_faceup			
	var retcode = .set_is_faceup(value, instant, check, tags)
	var _after = is_faceup
	
#issues with facedown cards if I do this?	
#	if _before == _after:
#		return retcode
	
	if check:
		return retcode
		
	if value:
		#initiate the card art if it's the first time we're setting this faceup
		set_card_art()
			
	#we remove all of the card's properties as long as it's facedown on the board,
	#to avoid triggering any weird things
	if is_onboard_facedown():
		if !_hidden_properties:
			_hidden_properties = properties
			properties = {}
			#a few variables we still need to avoid a crash:
			for property in ["_code", "code"]:
				properties[property] = _hidden_properties.get(property, "")
	else:
		if _hidden_properties:
			var temp_properties = properties
			properties = _hidden_properties
			
			for property in temp_properties:
				if property in ["_code", "code"]:
					continue
				scripting_bus.emit_signal(
						"card_properties_modified",
						self,
						{
							"property_name": property,
							"new_property_value": properties.get(property),
							"previous_property_value": temp_properties[property],
							"tags": ["Scripted", "set_is_faceup"]
						}
				)				
			if scripts:
				cfc.LOG("removing extra scripts from card " + canonical_name + " as we turn it faceup")
				scripts = {}				
			
			_hidden_properties = {}

	if _before != _after and is_onboard() and !is_boost():
		cfc.flush_cache()
	
	return retcode	
		
	
func copy_modifiers_to(to_card:WCCard):
	var modifiers = export_modifiers()
	to_card.import_modifiers(modifiers)

func draw_boost_card(src_container = ""):
	if !src_container:
		src_container = "deck_villain"
	var villain_deck:Pile = cfc.NMAP.get(src_container, null)
	if !villain_deck:
		return	
	var boost_card:Card = villain_deck.get_top_card()
	if boost_card:
#		boost_card.set_is_boost(true)
		boost_card.attach_to_host(self, false, ["as_boost"]) #,false, ["facedown"])
#		boost_card.set_is_faceup(false)

func draw_boost_cards(action_type):
	var amount = self.get_property("boost_cards_per_" + action_type, 1)
	for i in amount:
		draw_boost_card()
	#TODO if pile empty...need to reshuffle ?

#returns an array of allowed triggers,
# or "true" if all scripts allowed
func can_execute_scripts():
	#checks for cases where we don't want to execute scripts on this card	
	if self.is_boost():
		return ['boost']
	#if it's tucked under another card in most cases we don't want to execute, but there are execptions	
	if self.is_inactive_attachment():
		return false
	return true

func get_boost_cards(flip_status:int = CFConst.FLIP_STATUS.BOTH):
	var results = []
	for card in self.attachments:
		if (!card.is_boost()):
			continue
		if (card.is_faceup and flip_status == CFConst.FLIP_STATUS.FACEDOWN):
			continue
		if (!card.is_faceup and flip_status == CFConst.FLIP_STATUS.FACEUP):
			continue			
		results.append(card)

	return results	 

func next_boost_card_to_reveal():
	var boost_card = null
	for card in self.attachments:
		if (!card.is_boost()):
			continue
		if (card.is_faceup):
			continue
		boost_card = card
		break
	return boost_card

#returns extra scripts
func _get_extra_scripts(trigger:String = "", filters:= {}, do_merge = false) -> Dictionary:
	#if we have no extra scripts we stick with parent behavior
	if !extra_scripts:
		return .get_instance_runtime_scripts(trigger)
		
	#if we have extra scripts, we'll do a merge of extra scripts
	#with the cards script, then retrieve from the merged dictionary
	var merged_scripts:Dictionary = .get_instance_runtime_scripts()
	if !merged_scripts and do_merge:
		merged_scripts = cfc.set_scripts.get(canonical_id,{}).duplicate(true)
	
	#additional scripts to merge with what we found
	var requesting_hero_id = filters.get("requesting_hero_id", 0) 
	for key in extra_scripts:
		var extra_script = extra_scripts[key]["script_definition"]
		var controller_id = extra_scripts[key].get("controller_id", 0)
		if requesting_hero_id and controller_id and (requesting_hero_id != controller_id):
			continue
		merged_scripts = WCUtils.merge_dict(merged_scripts, extra_script, true)

	var found_scripts = {}
	match trigger:
		"":
			found_scripts = merged_scripts.duplicate(true)
		_:
			found_scripts = merged_scripts.get(trigger,{}).duplicate(true)
	
	return found_scripts

#returns scripts specific to this instance
func get_instance_runtime_scripts(trigger:String = "", filters:={}) -> Dictionary:
	return _get_extra_scripts(trigger, filters, true)



func set_activity_script(script):
	activity_script = script
	if script:
		gameData.set_latest_activity_script(script)

# For boost cards to know who's calling them
var _current_activation_details = null
func set_current_activation(script):
	if _current_activation_details:
		var _error = 1
	_current_activation_details = script

func get_current_activation_details():
	return _current_activation_details
	
func remove_current_activation(script):	
	if _current_activation_details != script:
		var _error = 1
	_current_activation_details = null

#returns a list of active main schemes **from this card's perspective**
#typically it contains only one element, but in some cases (e.g. Tower defense)
# it might be multiple entries
# Also see Venom Goblin Scenario in Sinister Motives which has multiple main schemes
func get_active_main_schemes():
	var scenario = gameData.scenario
	if !self.is_encounter():
		return [gameData.get_main_scheme()]
	var setting = scenario.get_setting("encounter_requests_main_scheme", "")
	match setting:
		"all_main_schemes":
			return gameData.get_main_schemes()
		_:
			return [gameData.get_main_scheme()]
			

#############################
#FUNCTIONS USED DIRECTLY BY JSON SCRIPTS
# These might not be always directly called by the code but instead
# called as part of json script processing (through a .call run)
#############################

func is_attached(params := {}, script:ScriptObject= null) -> bool:
	var subject = get_param_subject(params, script)
	if !subject:
		return false
			
	if subject.current_host_card:
		return true
	return false

func is_character(params := {}, script:ScriptObject= null) -> bool:
	var subject = get_param_subject(params, script)
	if !subject:
		return false
			
	var type_code = subject.get_property("type_code", "")
	return is_character_type(type_code)

func is_ready(params := {}, script:ScriptObject= null) :
	var subject = get_param_subject(params, script)
	if !subject:
		return 0
			
	return !subject._is_exhausted

func is_exhausted(params := {}, script:ScriptObject= null):
	var subject = get_param_subject(params, script)
	if !subject:
		return 0
			
	return subject._is_exhausted

func is_token_status(params := {}, script:ScriptObject= null) -> int:
	var token_name = params.get("status_name", "")
	if !token_name:
		return 0

	var subject = get_param_subject(params, script)
	if !subject:
		return 0
	
	var forced_status = subject.get_property("force_" + token_name, 0)
	if forced_status:
		return 1
	
	#if a card gains stalwart, we remove its stunned and confused tokens immediately
	#I found that the easiest way to do it is to do it any time we check for the stunned/confused status
	if token_name in ["stunned", "confused"]:
		if subject.get_property("stalwart", 0, true):
			subject.tokens.mod_token(token_name, 0, true)			
	
	var trigger_value = subject.get_max_tokens(token_name)

	#if there is no max, we consider the trigger to be at 1
	if !trigger_value:
		trigger_value = 1

	var result = subject.tokens.get_token_count(token_name)

	if result >= trigger_value:
		return 1
	
	return 0
	 
	
func is_stunned(params := {}, script:ScriptObject= null) -> int:
	params["status_name"] = "stunned"
	return is_token_status(params, script)

func is_confused(params := {}, script:ScriptObject= null) -> int:
	params["status_name"] = "confused"
	return is_token_status(params, script)

func check_validity(params, script:ScriptObject= null) -> int:
	var subject = get_param_subject(params, script)
	if !subject:
		return 0
	if SP.check_validity(subject, params):
		return 1	
	return 0 

func get_stage_level(params = {}, script:ScriptObject  = null) -> int:
	var subject = get_param_subject(params, script)
						
	if !subject:
		return 0	
	
	return subject.get_property("stage_int", 0)
	
func count_attachments(params = {}, script:ScriptObject = null) -> int:
	var subjects =  get_param_subjects(params, script)	
				
	if !subjects:
		return 0	
	
	var ret := 0
	
	if params.get("filter_state_attachment", []):
		for card in subjects:
			for attachment in card.attachments:
				var script_owner = self
				if script:
					script_owner = script.owner 
				if SP.check_validity(attachment, params, "attachment", script_owner):
					ret+= 1
	else:
		for card in subjects:
			ret += card.attachments.size()
	return(ret)

func is_hero_form(params = {}, script:ScriptObject = null) -> bool:
	var subject = get_param_subject(params, script)
					
	if !subject:
		return false	
	
	if "hero" == subject.properties.get("type_code", ""):
		return true
	return false
	
func is_alter_ego_form(params = {}, script:ScriptObject = null) -> bool:
	var subject = get_param_subject(params, script)

	if !subject:
		return false
		
	if "alter_ego" == subject.properties.get("type_code", ""):
		return true
	return false

func is_defending(params = {}, script:ScriptObject = null) -> bool:
	var subject = get_param_subject(params, script)

	if !subject:
		return false
		
	var current_defender = gameData.get_attack_defender()
	if !current_defender:
		return false
		
	return current_defender == subject

func get_script_bool_property(params, script:ScriptObject = null) -> bool:
	var property = params.get("property", "")
	if !property:
		return false
	return script.get_property(property, false)

func get_param_subject(params, script:ScriptObject = null):
	var subject = self
	if script and params.get("subject", ""):
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		subject = subjects[0] if subjects else null
	return subject	

func get_param_subjects(params, script:ScriptObject = null):
	var subjects = [self]
	if script and params.get("subject", ""):
		var new_subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		return new_subjects
	return subjects		

func is_first_player(params = {}, script:ScriptObject = null):
	var subject = get_param_subject(params, script)
	if !subject:
		return false
		
	var controller_id = subject.get_controller_hero_id()
	if controller_id == gameData.first_player_hero_id():
		return 1
	return 0

func is_player_card(params = {}, script:ScriptObject = null):
	var subject = get_param_subject(params, script)
	if !subject:
		return false
		
	var type = subject.get_property("type_code", "")
	return type in CFConst.PLAYER_CARD_TYPES

func is_encounter(params = {}, script:ScriptObject = null):
	var subject = get_param_subject(params, script)
	if !subject:
		return false
		
	var type = subject.get_property("type_code", "")
	return type in CFConst.ENCOUNTER_CARD_TYPES

func count_unique_property_value(params, script:ScriptObject = null) -> int:
	var subjects = get_param_subjects(params, script)
	
	var property = params.get("property", "")
	if !property:
		return 0
	var count = {}
	for subject in subjects:
		var value = subject.get_property(property, 0)
		if !value:
			continue
		count[value] = 1
		
	return count.size()

func count_engaged_minions(params, script:ScriptObject= null) -> int:
	var subject = get_param_subject(params, script)
	
	if !subject:
		return 0
	
	var controller_hero_id = subject.get_controller_hero_id()
	if controller_hero_id <1:
		return 0
	var my_cards = get_tree().get_nodes_in_group("enemies" + str(controller_hero_id))
	var count = 0
	for card in my_cards:
		if card.get_property("type_code", "") == "minion":
			count +=1
	return count

func count_most_common(params, script:ScriptObject= null) -> int:
	var subjects = get_param_subjects(params, script)
	
	if !subjects:
		return 0
	
	var counts = {}
	var max_value = 0
	var property = params.get("property", "")
	if not property:
		return 0
			
	for card in subjects:
		var value = card.get_property(property, "")
		if value:
			if !counts.has(value):
				counts[value] = 0
			counts[value]+= 1
			if counts[value] > max_value:
				max_value = counts[value]
				
	return max_value
	
func get_subject_int_property(params, script:ScriptObject= null) -> int:
	var subjects = get_param_subjects(params, script)
	
	var property = params.get("property", "")
	var expected_value = params.get("property_value", "")
	if !property:
		return 0
	var count = 0
	for subject in subjects:
		var value = subject.get_property(property, 0)
		if expected_value:
			if typeof(value) != typeof(expected_value):
				value = 0
			elif value != expected_value:
				value = 0
			else:
				value = 1	
		if typeof(value) != TYPE_INT:
			if value:
				value = 1
			else:
				value = 0
		count+= value
	return count


func get_subject_int_variable(params, script:ScriptObject= null) -> int:
	var subject = get_param_subject(params, script)
	if !subject:
		return 0
	
	var var_name = params.get("variable", "")
	var result = subject.script_variables.get(var_name, 0)
	if typeof(result) in [TYPE_INT, TYPE_REAL]:
		return result

	#for non numbers, we return a "bool" int equivalent
	if result:
		return 1
	return 0

func get_trigger_details_property(params, script:ScriptObject= null) -> int:
	if !script:
		return 0
	
	var trigger_details = script.trigger_details	
	var property = params.get("property", "")
	var expected_value = params.get("property_value", "")
	if !property:
		return 0
	if !expected_value:
		return 0		

	var value = trigger_details.get(property, null)
	if value == expected_value:
		return 1
	return 0
	
func get_subject_int_printed_property(params, script:ScriptObject = null) -> int:
	var subject = get_param_subject(params, script)
	
	if !subject:
		return 0
	
	var property = params.get("property", "")
	if !property:
		return 0
		
	var id = subject.get_property("_code", "")
	if !id:
		return 0
		
	var card_data = cfc.get_card_by_id(id)
	var result = card_data.get(property, 0)
	if typeof(result) == TYPE_BOOL:
		if result:
			result = 1
		else:
			result = 0
	return int(result)

func get_scenario_option_value(params, script:ScriptObject = null) -> int:
	if !params.has("option_name"):
		return 0
	var result = gameData.scenario.get_scenario_option(params["option_name"])
	return result

func count_cards(params, script:ScriptObject = null) -> int:
	var subjects = get_param_subjects(params, script)
	
	if !subjects:
		return 0
	
	return subjects.size()


func count_tokens(params, script:ScriptObject = null) -> int:
	var subjects = get_param_subjects(params, script)
	
	if !subjects:
		return 0
		
	var token_names = params.get("token_name", [])
	if typeof(token_names) == TYPE_STRING:
		token_names = [token_names]
	
	var count = 0
	for subject in subjects:
		for token_name in token_names:
			count+= subject.tokens.get_token_count(token_name)
	
	return count

func precompute_value(params, script:ScriptObject = null):
	if params.get("subject", "") != "interrupted_event":
		#unsupported for now
		return 0	

	var task = script

	if (!task):	
		return 0

	var find_by_name = 	params.get("func_find_in_definition","")
	if !find_by_name:
		return 0
		
	var path:Array = WCUtils.find_string_in_variant(task.script_definition,find_by_name )
	if path.size() <2:
		return 0
	path.pop_back()
	path.pop_back()
	var root = task.script_definition
	var to_request = ""
	for i in path.size():
		if i == path.size() -1:
			to_request = path[i]
		else:
			var subkey = path[i]
			root = root[subkey]
	
	var result = task.get_property(to_request, null, null, root)
	return result


#returns true if this card (or script subject)'s property contains specified text
func property_contains(params, script:ScriptObject = null) -> int:
	var subjects = get_param_subjects(params, script)
	if !subjects:
		return 0
		
	var and_or =  params.get("and_or", "or")
	var values = params.get("value", [])
	if typeof (values) == TYPE_STRING:
		values = [values]

	var property = params.get("property", "")
	if !property:
		return 0
	


	if !values:
		return 0
		
	for subject in subjects:
		var text = subject.get_property(property, "", true)
		text = text.to_lower()
		for value in values:
			value = value.to_lower()
			if and_or == "or":
				if value in text:
					return 1
			else:
				if !value in text:
					return 0
	if and_or =="or":
		return 0
	return 1

#returns true if this card (or script subject) has a given trait
func has_trait(params, script:ScriptObject = null) -> int:
	var subjects = get_param_subjects(params, script)
	if !subjects:
		return 0
		
	var and_or = "or"

	var traits = []
	match typeof(params):
		TYPE_DICTIONARY:
			and_or = params.get("and_or", and_or)
			traits = params.get("trait", "")
		TYPE_STRING:
			traits = params
		_:
			return 0

	if typeof(traits) == TYPE_STRING:
		traits = [traits]

	if !traits:
		return 0
	for subject in subjects:
		for trait in traits:
			trait = "trait_" + trait
			if and_or == "or":
				if subject.get_property(trait, 0, true):
					return 1
			else:
				if !subject.get_property(trait, 0, true):
					return 0
	if and_or == "or":
		return 0
	return 1

func count_trait(params, script:ScriptObject = null) -> int:	
	var subjects = get_param_subjects(params, script)
	if !subjects:
		return 0
	
			
	var traits = []
	match typeof(params):
		TYPE_DICTIONARY:
			traits = params.get("trait", "")
		TYPE_STRING:
			traits = params
		_:
			return 0

	if typeof(traits) == TYPE_STRING:
		traits = [traits]

	if !traits:
		return 0
		
	var count = 0
	for subject in subjects:
		for trait in traits:
			trait = "trait_" + trait
			if subject.get_property(trait, 0, true):
				count += 1
	return count

func identity_has_trait(params, script:ScriptTask = null) -> bool:
	var hero = get_controller_hero_card()
	return hero.has_trait(params)	

func get_hero_id(params, script:ScriptTask = null) -> int:
	var hero_name = params.get("card_name")
	if !hero_name:
		return 1 #default to avoid crashes

	var hero_card = cfc.NMAP.board.find_card_by_name(hero_name, true)
	if !hero_card:
		return 1 #default to avoid crashes
	
	return hero_card.get_controller_hero_id()	

func count_different_aspects(params, script:ScriptObject = null) -> int:
	var subjects = get_param_subjects(params, script)
	if !subjects:
		return 0
	var aspects = {}
	for subject in subjects:
		var aspect = subject.get_property("faction_code", "")
		if aspect in CFConst.ASPECTS:
			if not aspects.has(aspect):
				aspects[aspect] = 0
			aspects[aspect] += 1
	
	return aspects.size()
			
		
func get_aspect_name(params, script:ScriptTask = null) -> String:
	var subject = self
	
	if script and params.has("subject"):
		subject = null
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		if subjects:
			subject = subjects[0]
			
	if !subject:
		return ""
	
	var aspect = subject.get_property("faction_code", "").to_lower()
	if !(aspect in CFConst.ASPECTS):
		return ""
	return aspect

func card_is_in_play(params, script:ScriptTask = null) -> bool:
	var card_name = params.get("card_name", "")
	if !card_name:
		return false
	var card = cfc.NMAP.board.find_card_by_name(card_name)
	if !card:
		return false
	return true

func get_interrupted_event_property(params:Dictionary, _script:ScriptTask = null) -> int:
#	var script = get_current_activation_details()
	var event = gameData.theStack.get_current_interrupted_event()
	if !event:
		return 0
	var property = params.get("property", "")
	if !property:
		return 0
	
	var value = event.get(property, 0)
	return value


func current_activation_status(params:Dictionary, _script:ScriptTask = null) -> bool:
#	var script = get_current_activation_details()
	var script = gameData.get_latest_activity_script()
	if !script:
		return false
	var expected_activation_type = params.get("type", "")	
	var undefended = params.get("undefended", null)
	if null != undefended:
		expected_activation_type = "attack"
	
	match expected_activation_type:
		"attack":
			if not script.script_name in ["enemy_attack"]:
				return false
		"scheme":
			if not script.script_name in ["commit_scheme"]:
				return false
		"":
			pass			
		_:
			return false	
	
	if null != undefended:
		if undefended and script.subjects:
			if !script.has_tag("undefended"):
				return false
		if !undefended and !scripts.subjects:
			return false
			
	return true				 	

#returns true if this card was paid for with (at least) resources described by params
#e.g if you paid 3 physical plus 1 mental for a card, 
#it would say true to {"mental": 1}, to {"physical" : 2}, or to {"mental" :1, "physical": 1}
#but false to {"mental": 2}, or {"mental": 1, "wild": 1} 
func paid_with_includes(params:Dictionary, script:ScriptTask = null) -> int:
	var subject = get_param_subject(params, script)
	if !subject:
		return 0
		
	var paid_with = ManaPool.new()
	for data in subject._last_paid_with:
		var resource = data.get("resource", "")
		paid_with.add_manacost(resource)

	var compared_to = ManaCost.new()
	compared_to.init_from_dictionary(params)
	
	var result = paid_with.can_pay_total_cost(compared_to)
	if !result:
		return 0
	
	if !params.has("filter_state_source"):
		#no additional checks and we passed the rest
		return 1
	
	for data in subject._last_paid_with:
		var source = data["source"]
		var owner = script.owner if script else subject
		if SP.check_validity(source, params, "source", owner):
			return 1
	
	return 0
	
func get_overpaid_amount(params:Dictionary, script:ScriptTask = null) -> int:
	if ! _last_cost:
		_last_cost = ManaCost.new()

	var paid_with = ManaPool.new()
	for data in _last_paid_with:
		var resource = data.get("resource", "")
		paid_with.add_manacost(resource)
		
	var remaining_mana = paid_with.can_pay_total_cost(_last_cost)
	var result = 0
	
	var resource_type = params.get("resource", "")
	if resource_type:
		result = remaining_mana.get_resource(resource_type)
		if resource_type != "wild":
			result += remaining_mana.get_resource("WILD")
			
	else:
		result = remaining_mana.converted_mana_cost()
	return result
	
func count_paid_resources(params:Dictionary, script:ScriptTask = null) -> bool:
	var paid_with = ManaPool.new()
	for data in _last_paid_with:
		var resource = data["resource"]
		paid_with.add_manacost(resource)

	var cost_filters = params.get("filters", {})
	if cost_filters:
		paid_with.filter(cost_filters)

	return paid_with.converted_mana_cost()
	

func count_printed_resources(params:Dictionary, script) -> int:
	var mana = ManaCost.new()
	var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)	

	while subjects is GDScriptFunctionState && subjects.is_valid():
		subjects = subjects.resume()	
	if !subjects:
		cfc.LOG("error retrieving subjects for " + to_json(params))
		return 0
		
	for subject in subjects:
		var printed_resource = subject.get_printed_resource_value_as_mana()
		mana.add_manacost(printed_resource)
	var count = 0
	if params.has("resource_type"):
		count = mana.get_resource(params["resource_type"])
	else:
		count = mana.converted_mana_cost()
	return count
	
func count_boost_icons(params:Dictionary, script) -> int:
	var subjects = get_param_subjects(params, script)
	if !subjects:
		return 0
	var count = 0
	
	var count_star_icons = params.get("count_star_icons", false)
		
	for subject in subjects:
		var boost_icons = subject.get_property("boost", 0)
		count+= boost_icons
		if count_star_icons:
			var star = 1 if subject.get_property("boost_star", false) else 0
			count += star

	return count	

func count_resource_types(params:Dictionary, script) -> int:
	var mana = ManaCost.new()
	var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)	
	for subject in subjects:
		var printed_resource = subject.get_printed_resource_value_as_mana()
		mana.add_manacost(printed_resource)
	var count = mana.count_resource_types()
	return count
	
func get_sustained_damage(params:Dictionary = {}, script = null) -> int:
	var subject = get_param_subject(params, script)
	if !subject:
		return 0
		
	return subject.tokens.get_token_count("damage")

#returns how much damage this card can sustain before reaching zero life
# returns 0 if <= 0
func get_remaining_damage(params:Dictionary = {}, script = null) -> int:
	var subject = get_param_subject(params, script)
	
	if !subject:
		return 0
	
	var current_damage = subject.tokens.get_token_count("damage")
	var health = subject.get_property("health", 0)
	var diff = health - current_damage
	if diff <= 0:
		return 0
	return diff	

#
# RESOURCE FUNCTIONS
#

func set_last_paid_with(manacost_array:Array, expected_cost = null):
	_last_paid_with = manacost_array
	_last_cost = expected_cost
#	scripting_bus.emit_signal(
#			"card_selected",
#			self,
#			{"selected_cards": selected_cards}
#	)

#resource lock
#checks to see if a given card is being used a payment, in which case
#it is locked from being used in other scripts ( etc...)
var _locked_for_resource = null

#checks to see if a given card is being used a payment, in which case
#it is locked from being used in other scripts *as a subject*
var _lockable_for_subject = true

#script can either be a script object (in which case its owner will be computed)
#or a dict script definition (in which case the owner object also needs to be passed as parameter)			
func script_signature(script, owner = null):
	var definition := {}
	if typeof(script) == TYPE_DICTIONARY:
		definition = {
			"owner": owner,
			"definition": script
		}		
	else:			
		definition = {
			"owner": script.owner,
			"definition": script.script_definition
		}
	var signature = WCUtils.ordered_hash(definition)
	return signature

func remove_resource_lock():
	_locked_for_resource = null

#script can either be a script object (in which case its owner will be computed)
#or a dict script definition (in which case the owner object also needs to be passed as parameter)			
func set_resource_lock(script, owner = null):
	var signature = script_signature(script, owner)
	_locked_for_resource = signature

func is_subject_locked_as_resource(script,owner = null):
	return is_resource_locked(script, owner, true)
#script can either be a script object (in which case its owner will be computed)
#or a dict script definition (in which case the owner object also needs to be passed as parameter)				
func is_resource_locked(script, owner = null, only_check_subject = false):
	if !_locked_for_resource:
		return false
	
	if !script:
		return false
	
	var script_definition = script
	if typeof(script_definition) != TYPE_DICTIONARY:
		script_definition = script.script_definition
			
	if script_definition.has("network_prepaid"):
		return false
		
	var signature = script_signature(script, owner)
	if _locked_for_resource != signature:
		if only_check_subject:
			return _lockable_for_subject 
		return true
	
	return false
	
func _window_selection_confirmed(window, details):
	var selected_cards = details.get("selected_cards", [])
	if !self in selected_cards:
		return
	var script = window.my_script
	if !script:
		return
	if script.script_name == "pay_as_resource":
		set_resource_lock(script)

func pay_as_resource(script):
	if is_resource_locked(script):
		return null
		
	cfc.add_ongoing_process(self, "pay_as_resource")

	#generate a summary of resources generated
	var result_mana = get_resource_value_as_mana(script)


	#reload and re_run the script from scratch, up to execution
	#var exe_sceng = self.execute_scripts(self, "resource", {})	
	#below is a convoluted way to force execute the sript locally without going through the network stack,
	#specifically for payments
	#two reasons for that:
	#1) spare a network trip
	#2) because of the Network delay, I suspect I've seen bugs where the payment is processed
	# after the card is played, leading to desync between the players
	var delegate = {}
	var hero_id = 0
	var owner_card = script.owner
	if owner_card:
		hero_id = owner_card.get_controller_hero_id()
	else:
		owner_card = self
	if hero_id:
		delegate = {"for_hero_id" : hero_id}
	var exe_sceng = self.execute_scripts_no_stack(owner_card, "resource", delegate)				
	while exe_sceng is GDScriptFunctionState && exe_sceng.is_valid():
		exe_sceng  = exe_sceng.resume()	

	var state_exec = get_state_exec()
	if state_exec == "hand":	
		self.discard()

	
	remove_resource_lock()
	
	cfc.remove_ongoing_process(self, "pay_as_resource")
	var trigger_details = script.trigger_details.duplicate()
	trigger_details.erase("network_prepaid")
	scripting_bus.emit_signal_on_stack("paid_as_resource", self, trigger_details)
	return result_mana

func _get_resource_sceng(script = null):	
	return _get_script_sceng( "resource", script)

func _get_script_sceng(trigger, script = null, run_bg_cost_check = true):
	#var my_state = _state if _state else get_state_exec()
	var trigger_card = script.owner if script else self
	var trigger_details = {}
	var card_scripts = retrieve_filtered_scripts(trigger_card, trigger, trigger_details)	
	var state_scripts = get_state_scripts(card_scripts, trigger_card, trigger_details)
	
	if !state_scripts:
		return null
	
	var sceng = cfc.scripting_engine.new(
		state_scripts,
			self,
			trigger_card,
			trigger_details)	
	
	if run_bg_cost_check:		
		common_pre_run(sceng)
		
		var func_return = sceng.execute(CFInt.RunType.BACKGROUND_COST_CHECK)
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()			
	
	return sceng

#computes how much resources this card would generate as part of a payment
#this uses its "resource" script in priority (for card that have either special resource abilities,
#or cards that modify their resource based on some scripted conditions - e.g. The Power of Justice
func get_resource_value_as_mana(script):
	if is_resource_locked(script):
		return null
		
	var cache_key = {
		"owner": script.owner
	}.hash()
	
	if _cache_resource_value.has(cache_key):
		return _cache_resource_value[cache_key]

		
	var my_state = get_state_exec()
	var sceng:ScriptingEngine = _get_resource_sceng(script)
	var result_mana:ManaCost = ManaCost.new()
	
	_lockable_for_subject = true
	
	if sceng:		
		if (sceng.can_all_costs_be_paid):
			
			#alternate means of payment (i.e. not discarding from hand) do not discard, by default, and therefore can be subjects
			_lockable_for_subject = false			
			#But there are exceptions where the payment involves discarding, moving, etc...
			#which would invalidate it as a subject
			for script in sceng.scripts_queue:
				if script.script_name in ["discard", "move_to_container"]:
					_lockable_for_subject = true
					 
			# run in precompute mode to try and calculate how much resources this would give us
			var func_return = sceng.execute(CFInt.RunType.PRECOMPUTE)
			while func_return is GDScriptFunctionState && func_return.is_valid():
				func_return = func_return.resume()
				
			var results = sceng.get_precompute_objects()
			if (results):
				for result in results:
					if result as ManaCost:
						result_mana.add_manacost(result)
				_cache_resource_value[cache_key] = result_mana		
				return _cache_resource_value[cache_key]			
	
	#if the compute didn't get through, we return the regular printed value
	if (my_state) == "hand":
#		if (canonical_name == "The Power of Justice" and get_state_exec() == "hand"):
#			var _tmp = 1	
		_cache_resource_value[cache_key]  = get_printed_resource_value_as_mana({}, script)	
		return _cache_resource_value[cache_key]
	
	_cache_resource_value[cache_key] = null
	return _cache_resource_value[cache_key]

func get_resource_value_as_int(script):
#	if (canonical_name == "The Power of Justice" and get_state_exec() == "hand"):
#		var _tmp = 1
	var result_mana:ManaCost = get_resource_value_as_mana(script)
	
	if !result_mana:		
		return 0
	
	return result_mana.converted_mana_cost()
		

func merge_params_with_override(func_name, trigger, params):
	var function_override = gameData.theGameObserver.get_function_override(func_name, trigger)
	if !function_override:
		return params
	
	var additional_params = function_override.get("additional_params", {})
	for key in additional_params:
		params[key] = additional_params[key]	
	
	return params

func get_printed_resource_value_as_mana(params:Dictionary = {}, script= null):
	var subject = get_param_subject(params, script)
	
	#TODO we might have to do something more generic eventually for this
	params = merge_params_with_override("get_printed_resource_value_as_mana", subject, params)
				
	var resource_dict = {}
	for resource_name in ManaCost.RESOURCE_TEXT:
		var lc_name = resource_name.to_lower()
		var value = get_property("resource_" + lc_name, 0)
		var modifiers = params.get("per_resource_modifier", {}).get(lc_name, "")
		if modifiers:
			var multiplier = modifiers.get("multiplier", 1)
			value = value * multiplier
		if value:
			resource_dict[lc_name] = value
	var resource_mana = ManaCost.new()
	resource_mana.init_from_dictionary(resource_dict)
	return resource_mana

func get_printed_resource_value_as_int(script):
	var total = 0
	for resource_name in ManaCost.RESOURCE_TEXT:
		var lc_name = resource_name.to_lower()
		total += get_property("resource_" + lc_name, 0)
	return total

#
# OTHER FUNCTIONS
#

func display_debug(msg):
	gameData.display_debug("(WCCard - " + canonical_name +") " + msg)



func get_remaining_threat():
	var current_threat = self.tokens.get_token_count("threat")
	return current_threat

#used for some scripts
func get_remaining_indirect_damage():
	return get_remaining_damage()

# "assign_any_damage" in scripts
#assigning "any" damage means we can go over the limit.
#As such, remaining is always non zero	
func get_remaining_any_damage():
	return 666	
	
func get_max_hand_size():
	var max_hand_size = get_property("max_hand_size", 0)
	var hand_size =  get_property("hand_size", 0)

	if max_hand_size:
		hand_size = min(max_hand_size, hand_size)
		
	return hand_size

func init_token_drawer():
	#set token drawer to disable manipulation buttons
	tokens.show_manipulation_buttons = false

func get_keywords () -> Dictionary:
	return get_property("keywords", {})

func get_keyword(name):
	var keywords:Dictionary = get_keywords ()
	return keywords.get(name.to_lower(), false)
	
func get_unique_name() -> String:
	var subname = get_property("subname")
	if !subname:
		subname = ""		
	return canonical_name + " - " + subname

#used for save/load	
func export_to_json():
	var owner_hero_id = self.get_owner_hero_id()
	var card_id = self.properties.get("_code")
	var tokens_to_json = self.tokens.export_to_json()
	var card_description = {
		"card" : canonical_name + " #" + card_id,
		"owner_hero_id": owner_hero_id,
	}
	if is_exhausted():
		card_description["exhausted"] = true
	if is_inactive_attachment():
		card_description["inactive_attachment"] = true		
	if is_viewed:
		card_description["is_viewed"] = true
	
	if (tokens_to_json):
		card_description["tokens"] = tokens_to_json
	
	if (self.current_host_card):
		card_description["host"] = current_host_card.properties.get("_code")
		
	if self.encounter_status != gameData.EncounterStatus.NONE:
		card_description["encounter_status"] = self.encounter_status

	if is_onboard_facedown():
		card_description["facedown_properties"] = self.properties
	
	return card_description

func load_from_json(card_description):
	if (tokens):
		_ready_load_from_json(card_description)
	else:
		_on_ready_load_from_json = card_description
	return self

func _ready_load_from_json(card_description: Dictionary = {}):
	if (!card_description):
		card_description = _on_ready_load_from_json
	if !card_description:
		return self

	#owner_id and card_id should already be done or this card wouldn't exist
	var tokens_to_json = card_description.get("tokens", {})
	if (tokens_to_json):
		tokens.load_from_json(tokens_to_json)


	var exhausted = card_description.get("exhausted", false)
	if exhausted:
		# 2nd paramters set to false: 
		# we don't start the tween here to give time for the card to arrive on board
		exhaustme(false, false) 
	else:
		readyme()

	var inactive_attachment = card_description.get("inactive_attachment", false)
	set_is_inactive_attachment(inactive_attachment)

	var viewed = card_description.get("is_viewed", false)
	if viewed:
		set_is_viewed(true)
	else:
		set_is_viewed(false)
			
	self.encounter_status = int(card_description.get("encounter_status", gameData.EncounterStatus.NONE))

	var facedown_properties = card_description.get("facedown_properties", {})
	if facedown_properties:
		set_is_faceup(false, true)
		for property in facedown_properties:
			if property in ["code", "_code"]:
				continue
			self.modify_property(
					property,
					facedown_properties[property],
					false,
					["Init", "emit_signal"])
		cfc.flush_cache()
	else:
		if state in[CardState.ON_PLAY_BOARD, CardState.IN_HAND]:
			set_is_faceup(true, true)

	#we don't handle the attachment/host content here, it is don by the board loading, after all cards are loaded

	return self



func get_global_center():
	var xy = get_global_position()
	var card_scale = scale
	var real_card_size = card_size
	if state in [CardState.IN_PILE, CardState.VIEWED_IN_PILE]:
		var parent = get_parent()
		if parent:
			card_scale = parent.scale
			real_card_size = parent.card_size
	if _placement_slot:
		card_scale = _placement_slot.get_scale_modifier()
	var center = (xy + real_card_size/2 * card_scale)
	return center

func serialize_to_json():
	return export_to_json()

var _cached_printed_text = { "_initialized": false}
func get_printed_text(section = ""):
	var section_l = section.to_lower()
	if !section:
		return get_property("text","")


	if !_cached_printed_text["_initialized"]:
		var full_text:String = get_property("text", "")
		
		#remove boost text delimiter
		full_text = full_text.replace("\n[hr /]\n*", "\n")
		full_text = full_text.trim_prefix(" ")
		full_text = full_text.trim_suffix(" ")	
		
		var cr_paragraphs = full_text.split("\n")
			
		var pre_paragraphs = full_text.split("[b]")
		var paragraphs:Array = []


		for j in pre_paragraphs.size():
			pre_paragraphs[j] = pre_paragraphs[j].trim_prefix(" ")
			pre_paragraphs[j]  = pre_paragraphs[j].trim_suffix(" ")
			pre_paragraphs[j]  = pre_paragraphs[j].replace("\"","")

		#address the case where triggers start with [i]something[/i] -
		var i = 1
		var processed_paragraphs = []
		var prefixes = [""]
		for paragraph in pre_paragraphs:
			if paragraph.ends_with("-"):
				var pos = paragraph.find_last("[i]")
				if pos < 0: 
					pos = 0
				if i < pre_paragraphs.size():
					prefixes.append(paragraph.substr(pos))
					paragraph = paragraph.replace(prefixes[i], "")
			elif paragraph.begins_with("[i]"):
				var end_pos = paragraph.find("-")
				if end_pos >= 0:
					prefixes[i-1] = paragraph.substr(0, end_pos + 1)
					paragraph = paragraph.replace(prefixes[i-1], "")				
			else:
				prefixes.append("")
			processed_paragraphs.append({"paragraph": paragraph})				
			i+= 1	
		for j in processed_paragraphs.size():
			processed_paragraphs[j]["prefix"] = prefixes[j]
			
		pre_paragraphs = processed_paragraphs
		#some lines contain "[b]" which are not actually section names
		#so we need to make sure that sections actually also are delimited by a 
		# carriage return somewhere (or beginning/end of card text)
		#this is what this piece of code attempts to do
		#example:
		#"Permanent. Setup\n* [b]Forced Response[/b]: After attached villain activates against you, resolve the [b]Special[/b] ability of each [i]infinity stone[/i] in play. Otherwise, put the top card of the [i]infinity stone[/i] deck into play."
		var previous = {}
		for paragraph_data in pre_paragraphs:
			var paragraph = paragraph_data["paragraph"]
			paragraph = paragraph.trim_prefix(" ")
			paragraph = paragraph.trim_suffix(" ")
			var previous_str = previous.get("paragraph", "")			
			if previous_str:
				if !"\n" in previous_str:					
					previous["paragraph"] = previous_str + "[b]" +  paragraph
					previous["prefix"]= previous["prefix"] + paragraph_data["prefix"]
				else:
					previous_str = previous_str.strip_edges()
					previous_str = previous_str.trim_prefix("*")
					previous_str = previous_str.trim_suffix("*")	
					paragraphs.append({"prefix": previous["prefix"], "paragraph": previous_str.strip_edges()})
					previous = paragraph_data
			else:
				previous = paragraph_data
		if previous.get("paragraph", ""):
			var previous_str = previous["paragraph"]
			previous_str = previous_str.strip_edges()
			previous_str = previous_str.trim_prefix("*")
			previous_str = previous_str.trim_suffix("*")				
			paragraphs.append({"prefix": previous["prefix"], "paragraph": previous_str.strip_edges()})


		i = 0
		for paragraph_data in paragraphs:
			var paragraph = paragraph_data["paragraph"]
			var prefix = paragraph_data["prefix"]
			if !paragraph:
				continue
			var paragraph_l:String = paragraph.to_lower()
			if prefix:
				var _tmp = 1
			var pref_and_paragraph = prefix + paragraph
			var position = paragraph.findn("[/b]")
			if position == -1:
				var found_keyword = false
				if i == 0: #first line might be the traits and keywords line
					for keyword in CFConst.AUTO_KEYWORDS.keys():
						if paragraph_l.begins_with(keyword):
							_cached_printed_text["keywords"] = pref_and_paragraph
							found_keyword = true
							break
				if !found_keyword:
					if !_cached_printed_text.has("generic"):
						 _cached_printed_text["generic"] = ""
					else:
						_cached_printed_text["multiple_generic"] = true
					_cached_printed_text["generic"] += pref_and_paragraph
			else:
				var paragraph_name = paragraph_l.substr(0, position)
				#due to some typos, some sections have the ":" inside the bold, others don't
				#e.g. <b>When Revealed:</b> and <b>When Revealed</b>: are both possible occurrences
				paragraph_name = paragraph_name.replace(":", "")
				paragraph_name = cfc.remove_bbcode(paragraph_name)				
				paragraph_name = paragraph_name.strip_edges() 
				if !_cached_printed_text.has(paragraph_name):
						_cached_printed_text[paragraph_name] = ""
				else:
					_cached_printed_text["multiple_" + paragraph_name] = true
					paragraph_name = paragraph_name + "2"
					_cached_printed_text[paragraph_name] = ""
				var bold = "" if paragraph.begins_with("[b]") else "[b]"	
				_cached_printed_text[paragraph_name] += prefix + bold + paragraph
			i+= 1		

		_cached_printed_text["_initialized"] = true
		_cached_printed_text["all"] = full_text
		_cached_printed_text["all_excluding_keywords"] = full_text
		if _cached_printed_text.has("keywords"):
			_cached_printed_text["all_excluding_keywords"] = full_text.replace(_cached_printed_text["keywords"], "")

		for paragraph in cr_paragraphs:
			var words = paragraph.split(" ")
			if words:
				var first_word = words[0]
				first_word = first_word.to_lower()+ "..."
				_cached_printed_text[first_word] = paragraph

	if _cached_printed_text.has(section_l):
		return _cached_printed_text[section_l]
	return ""


func queue_free():
	reattach_removed_nodes()
	scripting_bus.unregister_card(self)
	.queue_free()
