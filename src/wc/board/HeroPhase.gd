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
onready var selected := $ColorRect
# Declare member variables here. Examples:
# var a = 2
# var b = "text"

# Called when the node enters the scene tree for the first time.
func _ready():
	selected.visible = false
	update_picture()
	scripting_bus.connect("current_playing_hero_changed", self, "_current_playing_hero_changed")
	gameData.connect("game_state_changed", self, "_game_state_changed")
	_update_labels()
	pass # Replace with function body.

func _process(_delta):
	if (gameData.get_current_hero_id() == hero_index):
		selected.visible = true
	else:
		selected.visible = false

func init_hero(_hero_index):
	hero_index = _hero_index

	
func update_picture():	
	var hero_deck_data = gameData.get_team_member(hero_index)["hero_data"]
 
	var img = cfc.get_hero_portrait(hero_deck_data.hero_id)
	if (img):
		var imgtex = ImageTexture.new()
		imgtex.create_from_image(img)
		imgtex.set_size_override(face_size)
		color_tex = imgtex
		grayscale_tex = WCUtils.to_grayscale(color_tex)
		grayscale_tex.set_size_override(face_size)
		heroNode.texture = imgtex
		heroNode.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

#We keep a lot of logic outside of this GUI function to allow for automated tests		
func _on_HeroPhase_gui_input(event):	
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			heroPhase_action()

func can_hero_phase_action() -> bool:
	if (hero_index == gameData.get_current_hero_id()):
		#special case: cannot switch my status from inactive to active outside of main player phase
		if (current_state == State.FINISHED) and (get_parent().current_step != CFConst.PHASE_STEP.PLAYER_TURN):
			return false
	return true	

func heroPhase_action() -> bool:
	if !can_hero_phase_action():
		return false	
	if (hero_index == gameData.get_current_hero_id()):
		rpc("switch_status")
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
		
	match current_state:
		State.ACTIVE:
			heroNode.texture = color_tex
		State.FINISHED:
			if (gameData.is_interrupt_mode()):
				gameData.interrupt_player_pressed_pass(self.hero_index)			
			heroNode.texture = grayscale_tex	
	_update_labels()
	get_parent().check_end_of_player_phase()
				
func _current_playing_hero_changed (_trigger_details: Dictionary = {}):
	var new_hero_index = gameData.get_current_hero_id()
	if (new_hero_index == hero_index) and (current_state == State.FINISHED):
		rpc("switch_status") #This also calls update_labels
	else:		
		_update_labels()
			

func get_label_text():
	return label.text

func _update_labels():
	var new_hero_index = gameData.get_current_hero_id()
	if (gameData.can_i_play_this_hero(hero_index)):
		if (new_hero_index == hero_index):
			if (gameData.is_interrupt_mode()):
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

func _game_state_changed(_details:Dictionary):
	_update_labels()
