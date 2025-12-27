extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var scenario_picture: TextureButton = get_node("%ScenarioPicture")
onready var scenario_name: Label = get_node("%ScenarioName")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var scenario_id
var villain_id
var _rotation = 0

func get_texture():
	if scenario_picture and scenario_picture.texture_normal:
		return scenario_picture.texture_normal
	return null

func get_text():
	if scenario_name and scenario_name.text:
		return scenario_name.text
	return ""

func gain_focus():
	$Panel/VerticalHighlights.visible = true
	$Panel/HorizontalHighlights.visible = true
	$Panel/HorizontalHighlights.rect_size = scenario_picture.rect_size
	#$HorizontalHighlights.rect_position = rect_position
	$Panel/VerticalHighlights.rect_size = scenario_picture.rect_size	
	lobby.show_preview(villain_id)
	
func lose_focus():
	$Panel/VerticalHighlights.visible = false
	$Panel/HorizontalHighlights.visible = false
	lobby.hide_preview(villain_id)
	
	
func _process(_delta:float):
	if scenario_picture and !scenario_picture.texture_normal:
		var display_name = cfc.get_card_name_by_id(scenario_id)
		var villains = ScenarioDeckData.get_villains_from_scheme(scenario_id)
		var picture_card_id = scenario_id
		var texture
		if (villains):
			var villain = villains[0]
			display_name = villain["shortname"]
			picture_card_id = villain["_code"]
			texture = cfc.get_villain_portrait(picture_card_id)
			_rotation = 0
		else:
			texture = cfc.get_scheme_portrait(picture_card_id)
			_rotation = 90
		scenario_name.set_text(display_name)
		 
		if (texture):
			scenario_picture.texture_normal = texture
		resize()	


func resize():

	
	var screen_size = get_viewport().size
	if screen_size.x > 1800:
		scenario_picture.rect_min_size = Vector2(200, 200)
	else:		
		scenario_picture.rect_min_size = Vector2(120, 120)
	
	scenario_picture.rect_size = scenario_picture.rect_min_size	

	scenario_picture.rect_pivot_offset = scenario_picture.rect_size / 2
	scenario_picture.rect_rotation = _rotation
	#scenario_name.rect_position = Vector2(0, 210)		
	
	$Panel/HorizontalHighlights.rect_min_size = scenario_picture.rect_min_size
	$Panel/VerticalHighlights.rect_min_size = scenario_picture.rect_min_size
	$Panel/HorizontalHighlights.rect_size = scenario_picture.rect_size
	$Panel/VerticalHighlights.rect_size = scenario_picture.rect_size

func _ready():
	get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")

func gui_focus_changed(control):
	if control == scenario_picture:
		gain_focus()
	else:
		lose_focus()	

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
			action()

func action():
	lobby.scenario_select(scenario_id)

func _on_ScenarioPicture_mouse_entered():
	lobby.show_preview(villain_id)


func _on_ScenarioPicture_mouse_exited():
	lobby.hide_preview(villain_id)


func _on_ScenarioPicture_pressed():
	action()
