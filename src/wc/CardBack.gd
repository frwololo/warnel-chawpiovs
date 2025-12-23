extends CardBackGlow

var font_scaled : float = 1
onready var art := $Art
onready var art2 := $TextureRect2
var art_filename = ""

func _ready() -> void:
	viewed_node = $Viewed
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
# Since we have a label on top of our image, we use this to scale the label
# as well
# We don't care about the viewed icon, since it will never be visible
# in the viewport focus.
func scale_to(scale_multiplier: float) -> void:	
	if font_scaled != scale_multiplier:
		var label : Label = $Label
		label.rect_min_size *= scale_multiplier
		# We need to adjust the Viewed Container
		# a bit more to make the text land in the middle
#		$"VBoxContainer/CenterContainer".rect_min_size *= scale_multiplier * 1.5
		var label_font : Font = label.get("custom_fonts/font").duplicate()
		label_font.size *= scale_multiplier
		label.set("custom_fonts/font", label_font)
		font_scaled = scale_multiplier
#		art.rect_scale = Vector2(scale_multiplier, scale_multiplier )
#		art2.rect_scale = Vector2(scale_multiplier, scale_multiplier )
		
	
func set_card_art(filename) -> void:
	art_filename = filename		
	art.texture = cfc.get_external_texture(art_filename)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# In case the generic art has been modulated, we switch it back to normal colour
	art.self_modulate = Color(1,1,1)
	
	#since we're setting a specific cart, we disable the default stuff
	$TextureRect2.visible = false
	$Label.visible = false
	stop_card_back_animation()
