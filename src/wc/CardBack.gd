extends CardBack

var font_scaled : float = 1
onready var art := $Art
onready var art2 := $TextureRect2
var art_filename = ""


# Used for looping between brighness scales for the Cardback glow
# The multipliers have to be small, as even small changes increase
# brightness a lot
var _pulse_values := [Color(1.05,1.05,1.05),Color(0.9,0.9,0.9)]
# A link to the tween which changes the glow intensity
# For this class, a Tween node called Pulse must exist at the root of the scene.
onready var _tween = $Pulse


func _ready() -> void:
	# warning-ignore:return_value_discarded
	_tween.connect("tween_all_completed", self, "_on_Pulse_completed")
	viewed_node = $Viewed
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

# Reverses the card back pulse and starts it again
func _on_Pulse_completed() -> void:
	# We only pulse the card if it's face-down and on the board
	if not card_owner.is_faceup and card_owner.get_parent() == cfc.NMAP.board:
		_pulse_values.invert()
		start_card_back_animation()
	else:
		stop_card_back_animation()


# Initiates the looping card back pulse
# The pulse increases and decreases the brightness of the glow
func start_card_back_animation():
	_tween.interpolate_property(self,'modulate',
			_pulse_values[0], _pulse_values[1], 2,
			Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	_tween.start()


# Disables the looping card back pulse
func stop_card_back_animation():
	_tween.remove_all()
	modulate = Color(1,1,1)

	
func set_card_art(filename) -> void:
	art_filename = filename		
	art.texture = cfc.get_external_texture(art_filename)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# In case the generic art has been modulated, we switch it back to normal colour
	art.self_modulate = Color(1,1,1)
	
	#since we're setting a specific cart, we disable the default stuff
	$TextureRect2.visible = false
	stop_card_back_animation()
	if CFConst.PERFORMANCE_HACKS:
		remove_child($TextureRect2)
