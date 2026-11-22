# Shows where the other players click (left button): waves of concentric
# circles, in the player's color
extends "res://src/wc/visual_cues/VisualCue.gd"

const CueAnchors = preload("res://src/wc/visual_cues/CueAnchors.gd")
const ClickRipple = preload("res://src/wc/visual_cues/ClickRipple.gd")

#a click is sent at each sample for this long (a few times: one lost packet
#does not lose it), then nothing until the next click. Not longer: a click
#shown late would be confusing
const SEND_FOR_MSEC := 200

var _click_count := 0
var _click_data := {}
var _click_msec := -100000

#peer id -> last click number shown
var _shown_clicks := {}

func _init():
	cue_type = "click"
	send_interval_msec = 50
	resend_unchanged = true

func _input(event):
	if !(event is InputEventMouseButton) or !event.pressed or event.button_index != BUTTON_LEFT:
		return
	var board = cfc.NMAP.get("board")
	if !board or !board.mouse_pointer or board.mouse_pointer.is_disabled:
		return
	_click_count += 1
	_click_msec = OS.get_ticks_msec()
	#where it was clicked, not where the mouse is when it is sent
	_click_data = CueAnchors.encode(board.mouse_pointer.determine_global_mouse_pos(),
			board.mouse_pointer.current_focused_card)
	_click_data["h"] = gameData.get_current_local_hero_id()
	_click_data["n"] = _click_count

#{anchor of the click (CueAnchors), "h": hero, "n": click number}
func sample():
	if OS.get_ticks_msec() - _click_msec > SEND_FOR_MSEC:
		return null
	return _click_data

func apply(peer_id: int, data: Dictionary) -> void:
	var click_number = int(data.get("n", 0))
	#the same click, sent again
	if click_number <= _shown_clicks.get(peer_id, 0):
		return
	_shown_clicks[peer_id] = click_number
	var click_position = CueAnchors.decode(data, int(data.get("h", 0)))
	if typeof(click_position) != TYPE_VECTOR2:
		return
	var ripple = ClickRipple.new()
	ripple.color = player_color(peer_id)
	ripple.position = click_position
	add_child(ripple)

func forget_peer(peer_id: int) -> void:
	_shown_clicks.erase(peer_id)

func forget_all() -> void:
	_shown_clicks = {}
	for ripple in get_children():
		ripple.queue_free()
