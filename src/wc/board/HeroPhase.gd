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
	_update_labels()
	pass # Replace with function body.

func _process(delta):
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
		
func _on_HeroPhase_gui_input(event):		
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			if (hero_index == gameData.get_current_hero_id()):
				switch_status()
			else:	
				gameData.select_current_playing_hero(hero_index)


	
func switch_status():
	current_state+=1
	if (current_state > State.FINISHED):
		current_state = State.ACTIVE
	match current_state:
		State.ACTIVE:
			heroNode.texture = color_tex
		State.FINISHED:
			heroNode.texture = grayscale_tex	
	_update_labels()
	get_parent().check_end_of_player_phase()
				
func _current_playing_hero_changed (trigger_details: Dictionary = {}):
	var new_hero_index = gameData.get_current_hero_id()
	if (new_hero_index == hero_index) and (current_state == State.FINISHED):
		switch_status() #This also calls update_labels
	else:		
		_update_labels()
			

func _update_labels():
	var new_hero_index = gameData.get_current_hero_id()
	if (new_hero_index == hero_index):
		label.text = "Finished?"
		if current_state == State.FINISHED:
			label.text = "Ready for Villain"
	else:
		label.text = "Select"
		if current_state == State.FINISHED:
			label.text = "Ready for Villain"		
	pass	
