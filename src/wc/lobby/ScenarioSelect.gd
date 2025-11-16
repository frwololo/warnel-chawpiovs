extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var scenario_picture: TextureRect = get_node("%ScenarioPicture")
onready var scenario_name: Label = get_node("%ScenarioName")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var scenario_id
var villain_id
var _rotation = 0

func get_texture():
	if scenario_picture and scenario_picture.texture:
		return scenario_picture.texture
	return null

func get_text():
	if scenario_name and scenario_name.text:
		return scenario_name.text
	return ""
	
func _process(_delta:float):
	if scenario_picture and !scenario_picture.texture:
		var display_name = cfc.get_card_name_by_id(scenario_id)
		var villains = ScenarioDeckData.get_villains_from_scheme(scenario_id)
		var picture_card_id = scenario_id
		var img
		if (villains):
			var villain = villains[0]
			display_name = villain["shortname"]
			picture_card_id = villain["_code"]
			img = cfc.get_villain_portrait(picture_card_id)
			_rotation = 0
		else:
			img = cfc.get_scheme_portrait(picture_card_id)
			_rotation = 90
		scenario_name.set_text(display_name)
		 
		if (img):
			var imgtex = ImageTexture.new()
			imgtex.create_from_image(img)	
			scenario_picture.texture = imgtex
			scenario_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			
	scenario_picture.rect_size = Vector2(200,200)	
	scenario_picture.rect_pivot_offset = scenario_picture.rect_size / 2
	scenario_picture.rect_rotation = _rotation
	#scenario_name.rect_position = Vector2(0, 210)
func _ready():
	pass
	

func load_scenario(_scenario_id):
	scenario_id = _scenario_id
	var villains = ScenarioDeckData.get_villains_from_scheme(scenario_id)
	if (villains):
		var villain = villains[0]
		villain_id = villain["_code"]

func _on_ScenarioSelect_gui_input(event):
	if (not cfc.is_game_master()):
		return	
			
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			lobby.scenario_select(scenario_id)


func _on_ScenarioPicture_mouse_entered():
	lobby.show_preview(villain_id)
	pass # Replace with function body.


func _on_ScenarioPicture_mouse_exited():
	lobby.hide_preview(villain_id)
	pass # Replace with function body.
