extends Button

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

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

func update_text():
	self.text = StepStrings[current_step]

# Called when the node enters the scene tree for the first time.
func _ready():
	self.connect("pressed", self, "_button_pressed")
	scripting_bus.connect("step_started", self, "_step_started")
	scripting_bus.connect("step_ended", self, "_step_ended")
	update_text()

#TODO - Actually verify with server what happens:
#- Ask server to update phase
#- Server tells us phase has changed
#- Update information
func _button_pressed():
	request_next_phase()

func _step_ended(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	match step:
		PHASE_STEP.VILLAIN_THREAT:
			_after_villain_threat()

func _step_started(	
		trigger_details: Dictionary = {}):
	var step = trigger_details["step"]
	match step:
		PHASE_STEP.PLAYER_TURN:
			pass
		PHASE_STEP.PLAYER_DISCARD:
			_player_discard()
			request_next_phase()
		PHASE_STEP.PLAYER_DRAW:
			_player_draw()			
			request_next_phase()
		PHASE_STEP.PLAYER_READY:
			_player_ready()			
			request_next_phase()			
		PHASE_STEP.PLAYER_END:
			request_next_phase()
		PHASE_STEP.VILLAIN_THREAT:
			_villain_threat()
			request_next_phase()
		PHASE_STEP.VILLAIN_ACTIVATES:
			_villain_activates()
			request_next_phase()			
		PHASE_STEP.VILLAIN_MINIONS_ACTIVATE:
			_minions_activate()
			request_next_phase()				
		PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			_deal_encounters()
			request_next_phase()			
		PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
			_reveal_encounters()
			request_next_phase()			
		PHASE_STEP.VILLAIN_PASS_PLAYER_TOKEN:
			request_next_phase()
		PHASE_STEP.VILLAIN_END:
			request_next_phase()
		PHASE_STEP.ROUND_END:
			_round_end()
			request_next_phase()
	return 0
	
func request_next_phase():
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
	#TODO
	pass

func _player_draw():
	gameData.draw_all_players()
	#TODO wait until cards drawn
	pass	
	
func _player_ready():
	gameData.ready_all_player_cards()
	pass	
	
func _villain_threat():
	gameData.villain_threat()
	pass	

func _after_villain_threat():
	gameData.villain_init_attackers()
	pass
	
func _villain_activates():
	gameData.enemy_activates()
	pass	
	
func _minions_activate():
	while cfc.game_paused:
		yield(get_tree().create_timer(0.05), "timeout")	
	var activated_ok = CFConst.ReturnCode.OK 
	while activated_ok == CFConst.ReturnCode.OK:
		activated_ok = gameData.enemy_activates()
		while activated_ok is GDScriptFunctionState:
			activated_ok = yield(activated_ok, "completed")
	pass					

func _deal_encounters():
	gameData.deal_encounters()
	yield(get_tree().create_timer(2), "timeout")
	pass
	
func _reveal_encounters():
	gameData.reveal_encounters()
	pass	

func _round_end():
	gameData.end_round()
	pass
