extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var hero_picture: TextureRect = get_node("%HeroPicture")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var hero_id
var grayscale_tex = null
var color_tex = null

func _ready():
	if color_tex and !hero_picture.texture:
		hero_picture.texture = color_tex
		hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pass
	

func load_hero(_hero_id):
	hero_id = _hero_id
	var hero_name = cfc.get_card_name_by_id(hero_id)
	get_node("%HeroName").set_text(hero_name)

	var img = cfc.get_hero_portrait(hero_id)
	if (img):
		color_tex = ImageTexture.new()
		color_tex.create_from_image(img)	
		grayscale_tex = WCUtils.to_grayscale(color_tex)	



func _on_HeroSelect_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			lobby.request_hero_slot(hero_id)

func enable():
	hero_picture.texture = color_tex

func disable():
	hero_picture.texture = grayscale_tex	

func _on_HeroPicture_mouse_entered():
	lobby.show_preview(hero_id)



func _on_HeroPicture_mouse_exited():
	lobby.hide_preview(hero_id)


