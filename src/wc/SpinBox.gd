extends SpinBox


onready var _tween = $Tween

# Hold the node which owns this node.
onready var owner_node = get_parent().get_parent().get_parent()

var _is_active :=true
var _initialized := false


func _ready() -> void:
	pass

func init_plus_minus_mode(_value, _min_value, _max_value):
	min_value = _min_value
	max_value = _max_value
	value = _value
	set_active(true)
	get_parent().visible = true




# Changes the hosted button node mouse filters
#
# * When set to false, buttons cannot receive inputs anymore
#    (this is useful when a card is in hand or a pile)
# * When set to true, buttons can receive inputs again
func set_active(value = true) -> void:
	if (_is_active == value) and _initialized:
		return
	_initialized = true
	_is_active = value
#	var button_filter := 1
#
#	if not value or owner_node.highlight.modulate == CFConst.TARGET_HOVER_COLOUR:
#		button_filter = 2
#	# We do a comparison first, to make sure we avoid unnecessary operations
#	for button in get_children():
#		if button as Button and button.mouse_filter != button_filter:
#			button.mouse_filter = button_filter
	# When we deactivate the buttons, we ensure they're hidden
	set_alpha(int(value))
	if (value):
		get_parent().show()
	else:
		get_parent().hide()



# Allows the component to appear gracefully
func set_alpha(value := 1) -> void:
	if value != modulate.a and not _tween.is_active():
		_tween.remove_all()
		_tween.interpolate_property(
				self,'modulate:a',
				modulate.a, value, 0.25,
				Tween.TRANS_SINE, Tween.EASE_IN)
		_tween.start()
