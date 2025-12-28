class_name HeroPhase
extends Control

enum State {
	ACTIVE,
	FINISHED
}

var hero_index
var current_state = State.ACTIVE
var grayscale_tex:Texture
var color_tex:Texture

const face_size := Vector2(100, 100)

onready var heroNode : TextureRect = get_node("%hero")
onready var label := get_node("%Label")
onready var selected :=  get_node("%ColorRect")
onready var ping :=  get_node("%Ping")
onready var first_player :=  get_node("%FirstPlayer")

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

# Called when the node enters the scene tree for the first time.
func _ready():
	selected.visible = false
	update_picture()
	scripting_bus.connect("current_playing_hero_changed", self, "_current_playing_hero_changed")
	gameData.connect("game_state_changed", self, "_game_state_changed")
	gameData.connect("first_player_changed", self, "_first_player_changed")
	
	scripting_bus.connect("card_moved_to_hand", self, "_card_moved_zone")
	scripting_bus.connect("card_moved_to_board", self, "_card_moved_zone")
	scripting_bus.connect("card_moved_to_pile", self, "_card_moved_zone")		
	_update_labels()

	if hero_index == gameData.first_player_hero_id():
		first_player.visible = true
	else:
		first_player.visible = false	
	
	get_node("%VerticalHighlights").self_modulate = CFConst.FOCUS_COLOUR_ACTIVE
	get_node("%HorizontalHighlights").self_modulate = CFConst.FOCUS_COLOUR_ACTIVE
	compute_focus_neighbors()

func _process(_delta):
	if (gameData.get_current_local_hero_id() == hero_index):
		selected.visible = true
	else:
		selected.visible = false
	
	var network_owner = gameData.get_network_id_by_hero_id(hero_index)
	var ping_int = cfc.get_avg_ping(network_owner)
	if ping_int:
		ping.text = str(ping_int) + " ms"
		if ping_int < 100:
			ping.add_color_override("font_color", Color8(50, 255, 50))
		elif ping_int < 200:
			ping.add_color_override("font_color", Color8(220, 150, 50))
		else:
			ping.add_color_override("font_color", Color8(255, 50, 50))
	else:
		var fps = Performance.get_monitor(Performance.TIME_FPS)
		ping.text = str(fps) + " fps"
		if fps > 50:
			ping.add_color_override("font_color", Color8(50, 255, 50))
		elif fps > 30:
			ping.add_color_override("font_color", Color8(220, 150, 50))
		else:
			ping.add_color_override("font_color", Color8(255, 50, 50))		

	if gameData.phaseContainer.current_step == CFConst.PHASE_STEP.PLAYER_TURN:
		match current_state:
			State.ACTIVE:
				heroNode.texture = color_tex
			State.FINISHED:		
				heroNode.texture = grayscale_tex		
	else:			
		if hero_index in gameData.get_currently_playing_hero_ids():
			heroNode.texture = color_tex
		else:
			heroNode.texture = grayscale_tex

	#automated gui activity overrides previous decision
	if gameData.auto_gui_activity_ongoing():
		heroNode.texture = grayscale_tex

func init_hero(_hero_index):
	hero_index = _hero_index

	
func update_picture():	
	var hero_deck_data = gameData.get_team_member(hero_index)["hero_data"]
 
	var imgtex = cfc.get_hero_portrait(hero_deck_data.get_hero_id())
	if (imgtex):
		color_tex = imgtex
		grayscale_tex = WCUtils.to_grayscale(color_tex)
		heroNode.texture = imgtex
		heroNode.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

#We keep a lot of logic outside of this GUI function to allow for automated tests		
func _on_HeroPhase_gui_input(event):	
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			var _result = heroPhase_action()
	elif event is InputEvent:
		if event.is_action_pressed("ui_accept"):
			var _result = heroPhase_action()

func can_hero_phase_action() -> bool:
	if !gameData.theStack.is_player_allowed_to_click():
		return false
	
	if gameData.gui_activity_ongoing():
		return false
	
	if (hero_index == gameData.get_current_local_hero_id()):
		#special case: cannot switch my status from inactive to active outside of main player phase
		if (current_state == State.FINISHED) and (gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN):
			return false
	return true	

var _last_can_hero_pass_msg = ""
func can_hero_pass_warning_msg(string):
	if string == _last_can_hero_pass_msg:
		return
	_last_can_hero_pass_msg = string
	gameData.display_debug(_last_can_hero_pass_msg )
	
func can_hero_pass() -> bool:
	if (hero_index != gameData.get_current_local_hero_id()):
		can_hero_pass_warning_msg("can_hero_pass refused because not local_hero_id")
		return false
		
	if (!gameData.is_interrupt_mode()):
		return false
	
	if !hero_index in (gameData.get_currently_playing_hero_ids()):
		can_hero_pass_warning_msg("can_hero_pass refused because get_currently_playing_hero_ids")
		return false
		
	if !hero_index in (gameData.get_my_heroes()):
		can_hero_pass_warning_msg("can_hero_pass refused because not my hero")		
		return false
		
	if !gameData.theStack.is_player_allowed_to_pass():
		can_hero_pass_warning_msg("can_hero_pass refused because theStack.is_player_allowed_to_pass")		
		return false
	
	return true

func heroPhase_action() -> bool:
	if !can_hero_phase_action():
		return false	
	if (hero_index == gameData.get_current_local_hero_id()):
		if can_hero_pass():
			gameData.interrupt_player_pressed_pass(self.hero_index)		
			#return to default
			cfc.NMAP.board.grab_default_focus()
		
		cfc._rpc(self,"switch_status")
	else:	
		gameData.select_current_playing_hero(hero_index)
	return true
	
remotesync func switch_status(forced_state:int = -1):
	var old_state = current_state
	if (forced_state == -1):
		current_state+=1
	else:
		current_state = forced_state
		
	if (current_state > State.FINISHED):
		current_state = State.ACTIVE
		
	if current_state == old_state:
		#don't do anything if no change
		return
			
	_update_labels()
	var parent = gameData.phaseContainer
	if parent and is_instance_valid(parent):
		parent.check_end_of_player_phase()
				
func _current_playing_hero_changed (trigger_details: Dictionary = {}):
	var new_hero_index = trigger_details["after"]
	if (new_hero_index == hero_index) and (current_state == State.FINISHED):
		cfc._rpc(self,"switch_status") #This also calls update_labels
	else:		
		_update_labels()
			
	compute_focus_neighbors()		

func get_label_text():
	return label.text

func _update_labels():
	var new_hero_index = gameData.get_current_local_hero_id()
	if (gameData.can_i_play_this_hero(hero_index)):
		if (new_hero_index == hero_index):
			if (can_hero_pass()):
				label.text = "PASS"
			else:
				label.text = "Finished?"
		else:
			label.text = "Select"
			if current_state == State.FINISHED:
				label.text = "Ready for Villain"
	else:
		label.text = "Your Friend"
	if current_state == State.FINISHED:
		label.text = "Ready for Villain"
	
	if label.text == "Ready for Villain" and gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN:
		label.text = "--"					

func _game_state_changed(_details:Dictionary):
	_update_labels()

func _first_player_changed(details:Dictionary):
	var new_first_player = details["after"]
	if new_first_player == hero_index:
		first_player.visible = true
	else:
		first_player.visible = false

#
# Game controller related functions
#

func compute_focus_neighbors():
	var target_control = null
	var hero_id = gameData.get_current_local_hero_id()
			
	#but we're trting to get to the rightmost card in the current hand
	var hand_name = "hand" + str(hero_id)	
	if cfc.NMAP.has(hand_name):
		var rightmost_card = cfc.NMAP[hand_name].get_rightmost_card()
		if rightmost_card:
			target_control = rightmost_card.get_focus_control()

	#fallback is hero card
	if !target_control:
		var target_card = gameData.get_identity_card(hero_id)
		if target_card:
			target_control = target_card.get_focus_control()	

		
	if target_control:	
		get_node("%Control").focus_neighbour_left = target_control.get_path()

func _card_moved_zone(_card, details):
	var hero_id = gameData.get_current_local_hero_id()
	var hand_name = "hand" + str(hero_id)
	for k in ["source", "destination"]:
		if details[k].to_lower() == hand_name:
			compute_focus_neighbors()
			return	


func gain_focus():
	if gamepadHandler.is_mouse_input():
		return
	gameData.theAnnouncer.black_cover(gameData.phaseContainer)	
	get_node("%VerticalHighlights").visible = true
	get_node("%HorizontalHighlights").visible = true
	#this is a small picture so we make it brighter than cards when it gains focus
	heroNode.self_modulate = CFConst.FOCUS_CARD_MODULATE * 1.1
	heroNode.self_modulate.a = 1.0	

	
func lose_focus():
	get_node("%VerticalHighlights").visible = false
	get_node("%HorizontalHighlights").visible = false
	heroNode.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	gameData.theAnnouncer.stop_black_cover()
	
func enable_focus_mode():
	get_node("%Control").focus_mode = Control.FOCUS_ALL

func disable_focus_mode():
	get_node("%Control").focus_mode = Control.FOCUS_NONE


func _on_Control_focus_entered():
	gain_focus()


func _on_Control_focus_exited():
	lose_focus()
