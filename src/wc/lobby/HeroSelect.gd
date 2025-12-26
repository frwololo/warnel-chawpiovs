extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var hero_picture: TextureButton = get_node("%HeroPicture")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var hero_id
var grayscale_tex = null
var color_tex = null
var available = true

func _ready():
	if color_tex:
		hero_picture.texture_normal = color_tex
		hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")
	pass
	

func grab_focus():
	hero_picture.grab_focus()

func load_hero(_hero_id):
	hero_id = _hero_id
	var hero_name = cfc.get_card_name_by_id(hero_id)
	get_node("%HeroName").set_text(hero_name)

	var texture = cfc.get_hero_portrait(hero_id)
	if (texture):
		color_tex = texture	
		grayscale_tex = WCUtils.to_grayscale(color_tex)	

func gui_focus_changed(control):
	if control == hero_picture:
		gain_focus()
	else:
		lose_focus()

func gain_focus():
	if !gamepadHandler.is_mouse_input():
		$Panel/VerticalHighlights.visible = true
		$Panel/HorizontalHighlights.visible = true
		$Panel/HorizontalHighlights.rect_size = hero_picture.rect_size
		#$HorizontalHighlights.rect_position = rect_position
		$Panel/VerticalHighlights.rect_size = hero_picture.rect_size	
	lobby.show_preview(hero_id)
	
func lose_focus():
	$Panel/VerticalHighlights.visible = false
	$Panel/HorizontalHighlights.visible = false
	lobby.hide_preview(hero_id)
	
func _on_HeroSelect_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			action()

func enable():
	hero_picture.texture_normal = color_tex
	available = true

func disable():
	hero_picture.texture_normal = grayscale_tex	
	available = false

func _on_HeroPicture_mouse_entered():
	gain_focus()



func _on_HeroPicture_mouse_exited():
	lose_focus()


func _on_HeroPicture_pressed():
	action()

func action():
	if available:
		lobby.request_hero_slot(hero_id)
	else:
		lobby.request_release_hero_slot(hero_id)
