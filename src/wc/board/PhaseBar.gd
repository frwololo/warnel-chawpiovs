extends Node2D

enum DisplayPhase {
	PLAYER_TURN					#0
	THREAT			#1
	VILLAIN_ACTIVATES		#2
	ENCOUNTERS		#3
}

var phase_headers = [
	"Player Turn",
	"Threat",
	"Vilain activates",
	"Encounters"
]

var phase_data = []

var loaded = false

onready var phases:HBoxContainer = get_node("%Phases")
# Called when the node enters the scene tree for the first time.

func _ready():
	do_preload()
	pass
	
func _process(_delta:float):
	#do_preload()
	pass

func do_preload():
	if loaded:
		return
	if !phases:
		return
		
	for phase in DisplayPhase.size():
		var header = phase_headers[phase]
		var phase_info = VBoxContainer.new()
		phase_info.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND

		#header		
		var label = Label.new()
		label.text = header.to_upper() 
		phase_info.add_child(label)
		
		#contents
		var phase_contents = HBoxContainer.new()
		phase_contents.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
		
		match phase:
			DisplayPhase.PLAYER_TURN:
				for i in gameData.get_team_size():
					var hero_id = i+1
					var icon = PhaseBarIcon.new()
					icon.setup(PhaseBarIcon.Mode.PLAYER_TURN, hero_id)
					phase_contents.add_child(icon)
			DisplayPhase.THREAT:
				var threat_icon = PhaseBarIcon.new()
				threat_icon.setup(PhaseBarIcon.Mode.THREAT)
				phase_contents.add_child(threat_icon)
			DisplayPhase.VILLAIN_ACTIVATES:	
				for i in gameData.get_team_size():
					var hero_id = i+1
					var icon = PhaseBarIcon.new()
					icon.setup(PhaseBarIcon.Mode.VILLAIN_ACTIVATES, hero_id)
					phase_contents.add_child(icon)
			DisplayPhase.ENCOUNTERS:
				for i in gameData.get_team_size():
					var hero_id = i+1
					var icon = PhaseBarIcon.new()
					icon.setup(PhaseBarIcon.Mode.ENCOUNTER, hero_id)
					phase_contents.add_child(icon)			
		
		phase_info.add_child(phase_contents)
		
		
		phases.add_child(phase_info)
	loaded = true
