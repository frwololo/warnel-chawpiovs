extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var hero_id

func _ready():
	pass
	

func load_hero(_hero_id):
	hero_id = _hero_id
	var hero_name = cfc.idx_card_id_to_name[hero_id]
	get_node("%HeroName").set_text(hero_name)
	var hero_picture: TextureRect = get_node("%HeroPicture")
	var img = cfc.get_hero_portrait(hero_id)
	if (img):
		var imgtex = ImageTexture.new()
		imgtex.create_from_image(img)	
		hero_picture.texture = imgtex
		hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


func _on_HeroSelect_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			lobby.request_hero_slot(hero_id)
