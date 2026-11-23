extends Node2D


var phase_headers = [
	"Player Turn",
	"Threat",
	"Vilain activates",
	"Encounters"
]

var phase_data = []

#width of the threat phase (it has a single icon, see do_preload)
const THREAT_PHASE_MIN_WIDTH := 100
var all_phase_icons = []
var active_icon = null
var all_phase_headers = []
var loaded = false

#the icon's scene: PhaseBarIcon.new() would only create its script, without
#the Texture1, Texture2... child nodes the script looks for
const PhaseBarIconScene = preload("res://src/wc/board/PhaseBarIcon.tscn")

onready var phases:HBoxContainer = get_node("%Phases")
# Called when the node enters the scene tree for the first time.

func _ready():
	scripting_bus.connect("would_reveal", self, "_encounter_would_reveal")	
	scripting_bus.connect("step_about_to_start", self, "_game_step_about_to_start")	
	scripting_bus.connect("step_ended", self, "_step_ended")
	scripting_bus.connect("hero_phase_status_changed", self, "_hero_phase_status_changed")
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
		
	for phase in PhaseBarIcon.Mode.size():
		var header = phase_headers[phase]
		var phase_info = VBoxContainer.new()
		#the Phases HBoxContainer shares its width between the phase_info
		#boxes that have SIZE_EXPAND. The threat phase has a single icon:
		#no SIZE_EXPAND, it only takes its minimum width (its header's or
		#its icon's)
		phase_info.rect_min_size.x = THREAT_PHASE_MIN_WIDTH
		if phase == PhaseBarIcon.Mode.THREAT:
			phase_info.size_flags_horizontal = Control.SIZE_FILL
		else:
			phase_info.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND

		#header		
		var label = Label.new()
		label.text = header.to_upper() 
		phase_info.add_child(label)
		all_phase_headers.append(label)
		
		#contents
		var phase_contents = HBoxContainer.new()
		
		match phase:
			PhaseBarIcon.Mode.PLAYER_TURN:
				phase_contents.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
				
				for i in gameData.get_team_size():
					var hero_id = i+1
					var icon = PhaseBarIconScene.instance()
					icon.setup(PhaseBarIcon.Mode.PLAYER_TURN, hero_id)
					phase_contents.add_child(icon)
					all_phase_icons.append(icon)
					
			PhaseBarIcon.Mode.THREAT:
				#(inside a VBoxContainer, only the vertical flags change the
				#box's height: the horizontal ones only fill or not its width)
				phase_contents.size_flags_horizontal = Control.SIZE_FILL

				var threat_icon = PhaseBarIconScene.instance()
				threat_icon.setup(PhaseBarIcon.Mode.THREAT)
				phase_contents.add_child(threat_icon)
				all_phase_icons.append(threat_icon)
			PhaseBarIcon.Mode.VILLAIN_ACTIVATES:	
				phase_contents.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND

				for i in gameData.get_team_size():
					var hero_id = i+1
					var icon = PhaseBarIconScene.instance()
					icon.setup(PhaseBarIcon.Mode.VILLAIN_ACTIVATES, hero_id)
					phase_contents.add_child(icon)
					all_phase_icons.append(icon)
			PhaseBarIcon.Mode.ENCOUNTER:
				phase_contents.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND

				for i in gameData.get_team_size():
					var hero_id = i+1
					var icon = PhaseBarIconScene.instance()
					icon.setup(PhaseBarIcon.Mode.ENCOUNTER, hero_id)
					phase_contents.add_child(icon)			
					all_phase_icons.append(icon)
		phase_info.add_child(phase_contents)
		
		
		phases.add_child(phase_info)
	loaded = true

var game_step_matches = {
	CFConst.PHASE_STEP.PLAYER_TURN: PhaseBarIcon.Mode.PLAYER_TURN,
	CFConst.PHASE_STEP.VILLAIN_THREAT: PhaseBarIcon.Mode.THREAT,	
	CFConst.PHASE_STEP.VILLAIN_ACTIVATES: PhaseBarIcon.Mode.VILLAIN_ACTIVATES,
	CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER: PhaseBarIcon.Mode.ENCOUNTER,	
}

var one_hero_per_step = [
	PhaseBarIcon.Mode.VILLAIN_ACTIVATES,
	PhaseBarIcon.Mode.ENCOUNTER	
]
	
func _game_step_about_to_start(_trigger_object, details:Dictionary):
	var current_step = details["step"]
	get_node("%LabelRound").text = "Round " + str(gameData.current_round)
	if game_step_matches.has(current_step):
		var header_index = game_step_matches[current_step]
		for i in all_phase_headers.size():
			var header = all_phase_headers[i]
			if i == header_index:
				header.remove_color_override("font_color")
			else:
				header.add_color_override("font_color", Color(0.3, 0.3, 0.3))
		for icon in all_phase_icons:
			if icon.mode == header_index:
				if header_index in one_hero_per_step:
					var current_target_hero = gameData.get_villain_current_hero_target()
					if current_target_hero == icon.hero_id:
						set_active_icon(icon)
					else:
						icon.set_inactive()
				else:
					set_active_icon(icon)
			else:
				icon.set_inactive()

func set_active_icon(icon):
	icon.set_active()
	active_icon = icon
	get_node("%LabelDesc").text = "Currently: " + icon.get_desc_text()
	
func _step_ended(_trigger_object, details:Dictionary):
	var current_step = details["step"]
	if game_step_matches.has(current_step):
		var header_index = game_step_matches[current_step]
		for icon in all_phase_icons:
			if icon.mode <= header_index:
					icon.set_completed()

	if current_step == CFConst.PHASE_STEP.ROUND_END:
		for icon in all_phase_icons:
				icon.reset()				

func _encounter_would_reveal(_card, _details):
	if gameData.phaseContainer.current_step != CFConst.PHASE_STEP.VILLAIN_REVEAL_ENCOUNTER:
		return	
	for icon in all_phase_icons:
		if icon.mode != PhaseBarIcon.Mode.ENCOUNTER:
			continue
		var current_target_hero = gameData.get_villain_current_hero_target()
		if current_target_hero == icon.hero_id:
			set_active_icon(icon)
		else:
			icon.set_inactive()
				
func _hero_phase_status_changed(details: Dictionary):
	if gameData.phaseContainer.current_step != CFConst.PHASE_STEP.PLAYER_TURN:
		return
		
	var hero_id = details["hero_id"]
	var finished = (details["after"] == HeroPhase.State.FINISHED)

	for icon in all_phase_icons:
		if icon.mode != PhaseBarIcon.Mode.PLAYER_TURN:
			continue
		if icon.hero_id != hero_id:
			continue
		if finished:
			icon.set_completed()
		else:
			set_active_icon(icon)
	#e.g. find the PLAYER_TURN icon for hero_id and call set_completed() / set_active()
