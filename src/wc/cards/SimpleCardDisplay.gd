class_name SimpleCardDisplay
extends TextureButton

var card_id = ""
var target_size = null

const DEFAULT_SIZE = Vector2(300, 419)

func _ready():
	expand = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	set_card_size(DEFAULT_SIZE)	


func load_card(_card_id):
	card_id = _card_id
	
	if (card_id):
		reload_texture(self)

func card_image_download_complete(_card_id):
	if card_id != _card_id:
		return
	reload_texture()

func reload_texture(callback_owner = null):
	var card_picture = self
	if !card_id:
		return
	
	var art_filename = cfc.get_img_filename(card_id)	
	var img_tex= cfc.get_external_texture(art_filename)
	if img_tex:
		card_picture.texture_normal = img_tex
		resize()
	elif callback_owner:
		gameData.urgent_image_download(card_id, self)

func set_card_size(new_size):
	target_size = new_size
	self.rect_min_size = new_size
	self.rect_size = self.rect_min_size

func resize():
	if target_size:
		set_card_size(target_size)
