class_name OptionsMenu
extends Control

onready var back_button = $MarginContainer/VBoxContainer/BackButton
onready var v_box_container = $MarginContainer/VBoxContainer


signal exit_options_menu

func _ready():
	for option_button in v_box_container.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			
	set_process(false)
			
func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"BackButton":
			# warning-ignore:return_value_discarded
			set_process(false)
			cfc.set_game_paused(false)
			visible = false
			
