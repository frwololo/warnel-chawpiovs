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




func set_active(value = true) -> void:
	if (_is_active == value) and _initialized:
		return
	_initialized = true
	_is_active = value

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
