extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var v_folder_label := $MainMenu/VBox/Margin2/Label
onready var v_join_button := $MainMenu/VBox/Center/VButtons/JoinBox/Join
onready var v_host_ip_box := $MainMenu/VBox/Center/VButtons/JoinBox/HostIp

var http_request: HTTPRequest = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	v_host_ip_box.text = ""
	v_join_button.disabled = true
	http_request = HTTPRequest.new()
	add_child(http_request)	
	http_request.connect("request_completed", self, "_check_server_ip")
	http_request.request(CFConst.SIGNAL_SERVER_GET_HOST_URL)
		
	v_join_button.connect('pressed', self, 'on_button_pressed', ["Join"])
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")

func retrieve_server_ip(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		return ""

	var content = body.get_string_from_utf8()

	var json_result:JSONParseResult = JSON.parse(content)
	if (json_result.error != OK):
		return ""
		

	var results = json_result.result
	if ! typeof(results) == TYPE_DICTIONARY:
		return ""
				
	var ip  = results.get("server_ip", "")
	return ip

func _check_server_ip(result, response_code, headers, body):
	var my_ip = retrieve_server_ip(result, response_code, headers, body)
	if !my_ip:
		my_ip = "192.168.1.3"
	v_host_ip_box.text = my_ip
	v_join_button.disabled = false



func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"Join":
			join_game(v_host_ip_box.text)
		"Cancel":
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

func join_game(ip_address : String):
	var next_scene_params = {
		"host_ip" : ip_address,
		} 
	cfc.set_next_scene_params(next_scene_params)
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/MultiplayerLobby.tscn')
	
func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x
