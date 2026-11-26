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

# fetch_list_rooms() asks two servers at once: the direct IP rooms (lobby
# server, desktop only) and the public online rooms (signaling server)
var _pending_room_lists := 0
var _rooms_found := 0
var _room_list_errors := []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	v_host_ip_box.text = ""
	v_join_button.disabled = true
	if !networkManager.is_enet_available():
		# web builds only join online rooms: from the list, or by room code
		v_host_ip_box.placeholder_text = "Room code"

	networkManager.connect("public_rooms_received", self, "_on_public_rooms_received")
	networkManager.connect("public_rooms_failed", self, "_on_public_rooms_failed")
	fetch_list_rooms()
		
	v_join_button.connect('pressed', self, 'on_button_pressed', ["Join"])
	v_join_button.connect('mouse_entered', v_join_button, 'grab_focus')
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	if cfc.game_settings.get("hide_folder_label", false):
		v_folder_label.text = " "
	else:
		v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")
	resize()
	cfc.default_button_focus(v_buttons)
	_show_kicked_message()

#the lobby sends a kicked player back here with {"kicked": true}
func _show_kicked_message():
	var params = cfc.get_next_scene_params()
	if !params.get("kicked", false):
		return
	cfc.set_next_scene_params({})
	var message = Label.new()
	message.text = "You have been kicked from the game by the host."
	message.align = Label.ALIGN_CENTER
	message.add_color_override("font_color", Color(1, 0.3, 0.3))
	v_buttons.add_child(message)
	v_buttons.move_child(message, 0)

func fetch_list_rooms():
	var rooms_list = get_node("%Rooms")
	for child in rooms_list.get_children():
		child.queue_free()
	get_node("%RoomsListHeader").text = "Fetching Rooms - Please wait..."	
	refresh_button.visible = false
	_pending_room_lists = 0
	_rooms_found = 0
	_room_list_errors = []

	#online rooms (WebRTC)
	if networkManager.is_webrtc_available():
		_pending_room_lists += 1
		networkManager.fetch_public_rooms()

	#direct IP rooms (ENet), desktop only
	if networkManager.is_enet_available():
		var list_rooms_url = cfc.game_settings.get('lobby_server', {}).get('list_rooms_url', '')
		var server = cfc.game_settings.get('lobby_server', {}).get('server', '')
		if server and list_rooms_url:
			_pending_room_lists += 1
			http_request = HTTPRequest.new()
			http_request.set_timeout(10.0)
			add_child(http_request)	
			http_request.connect("request_completed", self, "_check_rooms_list")
			http_request.request(server + list_rooms_url)
		else:
			_room_list_errors.append("direct IP")

	if !_pending_room_lists:
		_room_lists_done()

#called once per list (direct IP, online) when it is received or failed
func _room_list_received(rooms_added: int, error_name: String = "") -> void:
	_rooms_found += rooms_added
	if error_name:
		_room_list_errors.append(error_name)
	_pending_room_lists -= 1
	if _pending_room_lists <= 0:
		_room_lists_done()

func _room_lists_done() -> void:
	refresh_button.visible = true
	var header = get_node("%RoomsListHeader")
	if _rooms_found:
		header.text = "MULTIPLAYER ROOMS"
		var rooms_list = get_node("%Rooms")
		cfc.default_button_focus(rooms_list)
	elif _room_list_errors:
		signal_server_error()
		return
	else:
		header.text = "No rooms right now - enter a room code or an IP address" if networkManager.is_enet_available() \
				else "No rooms right now - enter the room code given by the host"
	show_buttons()

func _on_public_rooms_received(rooms: Array) -> void:
	var rooms_list = get_node("%Rooms")
	for room in rooms:
		var label = room.name if room.name else "Room " + room.room
		label += " (%d/%d)" % [room.players, room.max_players]
		var new_room = roomSelect.instance()
		new_room.setup(label, self, room.room)
		rooms_list.add_child(new_room)
		
		if CFConst.DEBUG_AUTO_START_MULTIPLAYER or gameData.run_auto_tests:
			join_game(room.room)
			break
		
	_room_list_received(rooms.size())

func _on_public_rooms_failed(message: String) -> void:
	cfc.LOG("{network} could not list online rooms: " + message)
	_room_list_received(0, "online")

func retrieve_server_rooms_list(result, _response_code, _headers, body):
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
	if typeof(results) == TYPE_ARRAY:
		var rooms_list = get_node("%Rooms")
		var first_room = null
		for result in results:
			var new_room = roomSelect.instance()
			new_room.setup(result["room_name"], self)
			rooms_list.add_child(new_room)
			if !first_room:
				first_room = new_room
		_room_list_received(results.size())
		if first_room and (CFConst.DEBUG_AUTO_START_MULTIPLAYER or gameData.run_auto_tests):
			request_join_room(first_room.room_name)
	else:
		_room_list_received(0, "direct IP")


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

func join_room_process_request(result, _response_code, _headers, body):
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
#	if networkManager.is_enet_available() and !v_host_ip_box.text:
#		v_host_ip_box.text = "192.168.1.3"
	v_join_button.disabled = false
	refresh_button.visible = true

func signal_server_error(error = ""):
	var text = error
	if !text:
		if networkManager.is_enet_available():
			text = "Failed to get rooms list, please use Direct IP or a room code"
		else:
			text = "Failed to get rooms list, please enter the room code given by the host"
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

# an IP address (direct connection) or an online room code
func join_game(ip_address : String):
	var next_scene_params = {
		"host_ip" : ip_address,
		} 
	if networkManager.looks_like_room_code(ip_address) or !networkManager.is_enet_available():
		next_scene_params = {
			"room_code" : ip_address.strip_edges().to_upper(),
			}
	cfc.set_next_scene_params(next_scene_params)
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/MultiplayerLobby.tscn')
	
func _on_Menu_resized() -> void:
	resize()
	
func resize():
	self.rect_scale =  cfc.hardcoded_positions_modifier


func _on_RefreshButton_pressed():
	fetch_list_rooms()
	pass # Replace with function body.
