extends CardFront

onready var art := $Art
var art_filename:= ""
var text_enabled = false

var color_texture = null
var grayscale_texture = null

func _process(delta:float):
	_handle_horizontal_card()

func _handle_horizontal_card():
	if !text_enabled:
		return
	_card_text = find_node("CardText")
	if card_owner._horizontal:
		_card_text.rect_rotation = -90
		_card_text.rect_position.y = self.rect_size.y
		_card_text.rect_min_size = Vector2(self.rect_min_size.y - 4, self.rect_min_size.x - 4) 
		_card_text.rect_size = _card_text.rect_min_size

func setup_text_mode():
	text_enabled = true
	_card_text = find_node("CardText")
	_handle_horizontal_card()
	
#	# Map your card text label layout here. We use this when scaling
#	# The card or filling up its text
	card_labels["Name"] = find_node("Name")
	card_labels["type_name"] = find_node("type_name")
	card_labels["faction_name"] = find_node("faction_name")	
	card_labels["text"] = find_node("text")					
	#card_labels["Type"] = find_node("Type")
#	card_labels["Abilities"] = find_node("Abilities")
	card_labels["Cost"] = find_node("Cost")
	if !card_owner.properties.has("Cost") or card_owner.properties["Cost"] == null:
		find_node("HBCost").visible = false
#
#	# These set te max size of each label. This is used to calculate how much
#	# To shrink the font when it doesn't fit in the rect.
	card_label_min_sizes["Name"] = Vector2(CFConst.CARD_SIZE.x - 4, 19)
#	card_label_min_sizes["Abilities"] = Vector2(CFConst.CARD_SIZE.x - 4, 120)
	card_label_min_sizes["Cost"] = Vector2(16,16)

	# This is not strictly necessary, but it allows us to change
	# the card label sizes without editing the scene
	for l in card_label_min_sizes:
		card_labels[l].rect_min_size = card_label_min_sizes[l]

	# This stores the maximum size for each label, when the card is at its
	# standard size.
	# This is multiplied when the card is resized in the viewport.
	for label in card_labels:
		match label:
			"Cost","Power":
				original_font_sizes[label] = 15
			"Requirements":
				original_font_sizes[label] = 11
			"Abilities":
				original_font_sizes[label] = 25
			_:
				original_font_sizes[label] = 16
	
	var res_node = find_node("Resources")
	res_node.text = ""
	var resources_mana = card_owner.get_printed_resource_value_as_mana()
	if resources_mana:
		res_node.text = resources_mana.to_short_text()
	if (!res_node.text) and card_owner.properties.has("threat") and ! card_owner.properties["threat"] == null:
		res_node.text = str(card_owner.properties["threat"])
	if !res_node.text:
		res_node.visible = false
		
	card_labels["text"].text = 	card_owner.properties.get("text", "")
	card_labels["text"].bbcode_text = card_labels["text"].text 


func set_card_art(filename) -> void:
	art_filename = filename		
	var texture = cfc.get_external_texture(art_filename)
	if texture:
		color_texture = texture
		art.texture = texture
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# In case the generic art has been modulated, we switch it back to normal colour
		art.self_modulate = Color(1,1,1)
		if CFConst.PERFORMANCE_HACKS:
			remove_child($Margin)
			text_enabled = false
	else:
		art_filename = "-"
		setup_text_mode()
		card_owner.refresh_card_front()

func to_grayscale():
	if !color_texture:
		return
	if !grayscale_texture:
		grayscale_texture = WCUtils.to_grayscale(color_texture)
	art.texture = grayscale_texture

func to_color():
	if !color_texture:
		return
	art.texture = color_texture	

func set_label_text(node: Label, value, scale: float = 1):
	if !text_enabled:
		return
	.set_label_text(node, value, scale)
	
func get_card_label_font(label: Label) -> Font:
	if !text_enabled:
		return null
	return .get_card_label_font(label)
	
func set_card_label_font(label: Label, font: Font) -> void:
	if !text_enabled:
		return
	label.add_font_override("font", font)	

func scale_to(scale_multiplier: float) -> void:
	if !text_enabled:
		return	
	.scale_to(scale_multiplier)

func set_rich_label_text(node: RichTextLabel, value: String, is_resize := false, scale : float = 1):
	if !text_enabled:
		return	
	.set_rich_label_text(node, value, is_resize, scale)
