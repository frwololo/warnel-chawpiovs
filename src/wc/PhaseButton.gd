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
	update_text()

#TODO - Actually verify with server what happens:
#- Ask server to update phase
#- Server tells us phase has changed
#- Update information
func _button_pressed():
	if (current_step == PHASE_STEP.ROUND_END):
		current_step = PHASE_STEP.PLAYER_TURN
	else:
		current_step+=1
	update_text()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
