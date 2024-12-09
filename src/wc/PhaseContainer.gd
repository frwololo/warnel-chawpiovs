class_name PhaseContainer
extends VBoxContainer

var phaseLabel
var heroesStatus = []
var heroPhaseScene = preload("res://src/wc/board/HeroPhase.tscn")

#Notes on the phases
#During another player's turn, you can play *actions* (cards or abilities)

enum PHASE {
	PLAYER,
	VILLAIN
}

enum PHASE_STEP {
	PLAYER_TURN,
	PLAYER_DISCARD,
	PLAYER_DRAW,
	PLAYER_READY,
	PLAYER_END,
	VILLAIN_THREAT,
	VILLAIN_ACTIVATES,
	VILLAIN_MINIONS_ACTIVATE,
	VILLAIN_DEAL_ENCOUNTER,
	VILLAIN_REVEAL_ENCOUNTER,
	VILLAIN_PASS_PLAYER_TOKEN,
	VILLAIN_END,
	ROUND_END
}

#TODO Actual names needed here
const StepStrings = [
	"PLAYER_TURN",
	"PLAYER_DISCARD",
	"PLAYER_DRAW",
	"PLAYER_READY",
	"PLAYER_END",
	"VILLAIN_THREAT",
	"VILLAIN_ACTIVATES",
	"VILLAIN_MINIONS_ACTIVATE",
	"VILLAIN_DEAL_ENCOUNTER",
	"VILLAIN_REVEAL_ENCOUNTER",
	"VILLAIN_PASS_PLAYER_TOKEN",
	"VILLAIN_END",
	"ROUND_END"	
]

var current_step = PHASE_STEP.PLAYER_TURN
var current_step_complete:bool = false
var clients_ready_for_next_phase:Dictionary = {}

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

func update_text():
	phaseLabel.text = StepStrings[current_step]

# Called when the node enters the scene tree for the first time.
func _ready():
	gameData.registerPhaseContainer(self)
	scripting_bus.connect("step_started", self, "_step_started")
	scripting_bus.connect("step_ended", self, "_step_ended")
	update_text()
	
	
func _init():
	#create the hero face buttons
	for i in range(gameData.get_team_size()):
		var hero_index = i+1
		var heroButton = heroPhaseScene.instance()
		heroButton.init_hero(hero_index)
		heroButton.name = "HeroButton" + str(hero_index)
		add_child(heroButton)
		heroesStatus.append(heroButton)
			

	phaseLabel = Label.new()
	add_child(phaseLabel)

	

#Moving to next step needs to happen outside of the signal processing to avoid infinite loops or recursive signals
func _process(_delta: float) -> void:
	if (!current_step_complete) :
		return
		
	match current_step:
		PHASE_STEP.PLAYER_TURN:
			return
		PHASE_STEP.PLAYER_DISCARD:
			request_next_phase()
		PHASE_STEP.PLAYER_DRAW:
			request_next_phase()		
		PHASE_STEP.PLAYER_READY:
			request_next_phase()					
		PHASE_STEP.PLAYER_END:
			request_next_phase()
		PHASE_STEP.VILLAIN_THREAT:
			request_next_phase()
		PHASE_STEP.VILLAIN_ACTIVATES:
			request_next_phase()			
		PHASE_STEP.VILLAIN_MINIONS_ACTIVATE:
			request_next_phase()			
		PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			request_next_phase()		
		PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			request_next_phase()			
		PHASE_STEP.VILLAIN_PASS_PLAYER_TOKEN:
			request_next_phase()
		PHASE_STEP.VILLAIN_END:
			request_next_phase()
		PHASE_STEP.ROUND_END:
			request_next_phase()	
	

func check_end_of_player_phase():
	for hero_phase in heroesStatus:
		if hero_phase.current_state == HeroPhase.State.ACTIVE :
			return
	
	#All heroes are ready to move to the next phase
	for hero_phase in heroesStatus:
		hero_phase.switch_status()
		
	_force_go_to_next_phase()
	
#TODO - Actually verify with server what happens:
#- Ask server to update phase
#- Server tells us phase has changed
#- Update information
func _force_go_to_next_phase():
	current_step_complete = true
	request_next_phase()

func _step_ended(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	match step:
		PHASE_STEP.VILLAIN_THREAT:
			#_after_villain_threat()
			pass	

func _step_started(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	current_step_complete = false
	
	match step:
		PHASE_STEP.PLAYER_TURN:
			pass
		PHASE_STEP.PLAYER_DISCARD:
			_player_discard()
		PHASE_STEP.PLAYER_DRAW:
			_player_draw()			
		PHASE_STEP.PLAYER_READY:
			_player_ready()						
		PHASE_STEP.PLAYER_END:
			current_step_complete = true # Do nothing
		PHASE_STEP.VILLAIN_THREAT:
			_villain_threat()
		PHASE_STEP.VILLAIN_ACTIVATES:
			gameData.villain_init_attackers()
			_villain_activates()			
		PHASE_STEP.VILLAIN_MINIONS_ACTIVATE:
			_minions_activate()				
		PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			_deal_encounters()			
		PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			_reveal_encounters()			
		PHASE_STEP.VILLAIN_PASS_PLAYER_TOKEN:
			current_step_complete = true # Do nothing
		PHASE_STEP.VILLAIN_END:
			current_step_complete = true # Do nothing
		PHASE_STEP.ROUND_END:
			_round_end()
	return 0

#returns true if nothing prevents me (player) from *asking* for next phase	
func is_ready_for_next_phase() -> bool :
	if (!current_step_complete) :
		return	false
		
	return true	

mastersync func client_ready_for_next_phase():
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id() 

	clients_ready_for_next_phase[client_id] = 1
	if (clients_ready_for_next_phase.size() == gameData.network_players.size()):
		clients_ready_for_next_phase = {}
		rpc("proceed_to_next_phase")
		
mastersync func client_unready_for_next_phase():
	if (not get_tree().is_network_server()):
		return -1
	var client_id = get_tree().get_rpc_sender_id() 

	if clients_ready_for_next_phase.has(client_id):
		clients_ready_for_next_phase.erase(client_id)

		
func request_next_phase():
	if (!is_ready_for_next_phase()):
		return
	
	rpc_id(1, "client_ready_for_next_phase")
	
func unrequest_next_phase():
	rpc_id(1, "client_unready_for_next_phase")	

	
remotesync func proceed_to_next_phase():	
	scripting_bus.emit_signal("step_about_to_end",  {"step" : current_step})
	scripting_bus.emit_signal("step_ended",  {"step" : current_step})
	if (current_step == PHASE_STEP.ROUND_END):
		current_step = PHASE_STEP.PLAYER_TURN
	elif ((current_step == PHASE_STEP.VILLAIN_MINIONS_ACTIVATE) and gameData.villain_next_target()):
		current_step = PHASE_STEP.VILLAIN_ACTIVATES
	else:
		current_step+=1
	scripting_bus.emit_signal("step_about_to_start",  {"step" : current_step})
	scripting_bus.emit_signal("step_started",  {"step" : current_step})	
	update_text()
	
func _player_discard():
	current_step_complete = true	
	pass

func _player_draw():
	gameData.draw_all_players()
	current_step_complete = true
	pass	
	
func _player_ready():
	gameData.ready_all_player_cards()
	current_step_complete = true	
	pass	
	
func _villain_threat():
	gameData.villain_threat()
	current_step_complete = true
	pass	

func _after_villain_threat():
	gameData.villain_init_attackers()
	current_step_complete = true
	pass
	
func _villain_activates():
	var activated_ok = gameData.enemy_activates()
	if activated_ok is GDScriptFunctionState:
		activated_ok = yield(activated_ok, "completed")
	current_step_complete = true
	pass	
	
func _minions_activate():
	while cfc.game_paused:
		yield(get_tree().create_timer(0.05), "timeout")	
	var activated_ok = CFConst.ReturnCode.OK 
	while activated_ok == CFConst.ReturnCode.OK:
		activated_ok = gameData.enemy_activates()
		if activated_ok is GDScriptFunctionState:
			activated_ok = yield(activated_ok, "completed")
	current_step_complete = true
	pass					

func _deal_encounters():
	gameData.deal_encounters()
	yield(get_tree().create_timer(2), "timeout")
	current_step_complete = true
	pass
	
func _reveal_encounters():
	gameData.reveal_encounters()
	current_step_complete = true
	pass	

func _round_end():
	gameData.end_round()
	current_step_complete = true	
	pass


