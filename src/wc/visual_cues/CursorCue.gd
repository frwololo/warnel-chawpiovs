# Shows where the other players' mouse is, and the card they look at in
# their hand or drag (see CueAnchors.gd for how positions are sent)
extends "res://src/wc/visual_cues/VisualCue.gd"

const CueAnchors = preload("res://src/wc/visual_cues/CueAnchors.gd")
const RemoteCursor = preload("res://src/wc/visual_cues/RemoteCursor.gd")

#peer id -> RemoteCursor
var _views := {}

func _init():
	cue_type = "cursor"
	send_interval_msec = 66
	stale_after_msec = 3000

#{"a": anchor..., "h": hero this player is looking at,
# "c": guid of the card shown with the cursor, "d": 1 if dragged}
func sample():
	var board = cfc.NMAP.get("board")
	if !board or !board.mouse_pointer:
		return null
	if board.mouse_pointer.is_disabled or !OS.is_window_focused():
		return {"a": "none"}

	var hovered_card = board.mouse_pointer.current_focused_card
	var dragged_card = cfc.card_drag_ongoing
	var data = CueAnchors.encode(board.mouse_pointer.determine_global_mouse_pos(),
			null if is_instance_valid(dragged_card) else hovered_card)
	data["h"] = gameData.get_current_local_hero_id()

	if is_instance_valid(dragged_card):
		data["c"] = dragged_card.get_guid()
		data["d"] = 1
	elif is_instance_valid(hovered_card) and hovered_card.state in CueAnchors.HAND_STATES:
		data["c"] = hovered_card.get_guid()
	return data

func apply(peer_id: int, data: Dictionary) -> void:
	var view = _views.get(peer_id)
	if !is_instance_valid(view):
		view = RemoteCursor.new()
		view.setup(player_name(peer_id), player_color(peer_id), stale_after_msec)
		add_child(view)
		_views[peer_id] = view

	var hero_id = int(data.get("h", 0))
	var target = CueAnchors.decode(data, hero_id)
	view.set_target(target, data.get("a") == "hand")

	var card = null
	if data.has("c"):
		card = guidMaster.get_object_by_guid(str(data["c"]))
	view.set_card(card if is_instance_valid(card) else null, data.has("d"))

func forget_peer(peer_id: int) -> void:
	var view = _views.get(peer_id)
	if is_instance_valid(view):
		view.queue_free()
	_views.erase(peer_id)

func forget_all() -> void:
	for peer_id in _views.keys():
		forget_peer(peer_id)
