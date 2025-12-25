extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var v_folder_label := $MainMenu/VBox/Margin2/Label
onready var v_join_button := $MainMenu/VBox/Center/VButtons/JoinBox/Join
onready var v_host_ip_box := $MainMenu/VBox/Center/VButtons/JoinBox/HostIp
onready var refresh_button := get_node("%RefreshButton")

var roomSelect = preload("res://src/wc/menus/JoinRoom.tscn")

var http_request: HTTPRequest = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	v_host_ip_box.text = ""
	v_join_button.disabled = true

	fetch_list_rooms()
		
	v_join_button.connect('pressed', self, 'on_button_pressed', ["Join"])
	v_join_button.connect('mouse_entered', v_join_button, 'grab_focus')
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")


func fetch_list_rooms():
	var rooms_list = get_node("%Rooms")
	for child in rooms_list.get_children():
		child.queue_free()
	get_node("%RoomsListHeader").text = "Fetching Rooms - Please wait..."	
	refresh_button.visible = false
	var list_rooms_url = cfc.game_settings.get('lobby_server', {}).get('list_rooms_url', '')
	var server = cfc.game_settings.get('lobby_server', {}).get('server', '')

	if server and list_rooms_url:
		http_request = HTTPRequest.new()
		http_request.set_timeout(10.0)
		add_child(http_request)	
		http_request.connect("request_completed", self, "_check_rooms_list")
		http_request.request(server + list_rooms_url)
	else:
		signal_server_error()

func retrieve_server_rooms_list(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		return ""

	var content = body.get_string_from_utf8()

	var json_result:JSONParseResult = JSON.parse(content)
	if (json_result.error != OK):
		return ""
		

	var results = json_result.result
	if ! typeof(results) == TYPE_ARRAY:
		return ""
				
	return results

func _check_rooms_list(result, response_code, headers, body):
	var results = retrieve_server_rooms_list(result, response_code, headers, body)
	http_request.queue_free()
	refresh_button.visible = true	
	if results and typeof(results) == TYPE_ARRAY:
		var rooms_list = get_node("%Rooms")
		get_node("%RoomsListHeader").text = "MULTIPLAYER ROOMS"		
		for result in results:
			var new_room = roomSelect.instance()
			new_room.setup(result["room_name"], self)
			rooms_list.add_child(new_room)
		show_buttons()
		if CFConst.DEBUG_AUTO_START_MULTIPLAYER:
			var room_name = rooms_list.get_child(0).room_name
			request_join_room(room_name)

	else:
		signal_server_error()


func request_join_room(room_name):
	disable_rooms(true)
	var join_room_url = cfc.game_settings.get('lobby_server', {}).get('join_room_url', '')
	var server = cfc.game_settings.get('lobby_server', {}).get('server', '')

	if server and join_room_url:
		http_request = HTTPRequest.new()
		http_request.set_timeout(10.0)
		add_child(http_request)	
		http_request.connect("request_completed", self, "_join_room")
		
		join_room_url = join_room_url.replace("__ROOM_NAME__", room_name)
		http_request.request(server + join_room_url)
	else:
		signal_server_error()

func join_room_process_request(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		return ""

	var content = body.get_string_from_utf8()

	var json_result:JSONParseResult = JSON.parse(content)
	if (json_result.error != OK):
		return ""
		

	var results = json_result.result
	if ! typeof(results) == TYPE_DICTIONARY:
		return ""
				
	return results

func disable_rooms(disabled=false):
	var rooms_list = get_node("%Rooms")
	for child in rooms_list.get_children():
		child.set_disabled(disabled)

func show_buttons():
	var my_ip = "192.168.1.3"
	v_host_ip_box.text = my_ip
	v_join_button.disabled = false
	refresh_button.visible = true

func signal_server_error(error = ""):
	var text = error if error else "Failed to get rooms list, please use Direct IP"
	get_node("%RoomsListHeader").text = text		
	show_buttons()
	disable_rooms(false)
	
func _join_room(result, response_code, headers, body):
	var error = ""
	var results = join_room_process_request(result, response_code, headers, body)
	if results and typeof(results) == TYPE_DICTIONARY:
		var my_ip = results.get("ip", "")
		if my_ip:
			join_game(my_ip)
			return
		else:
			error = results.get("error", "")
	
	signal_server_error(error)
		
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


func _on_RefreshButton_pressed():
	fetch_list_rooms()
	pass # Replace with function body.
