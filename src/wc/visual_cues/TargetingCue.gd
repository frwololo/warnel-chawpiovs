# Shows the targeting arrows of the other players: while a player is
# choosing a target (the arrow from a card follows their mouse), the other
# clients draw the same arrow, from the same card, towards where that
# player points (see CueAnchors.gd for how positions are sent)
extends "res://src/wc/visual_cues/VisualCue.gd"

const CueAnchors = preload("res://src/wc/visual_cues/CueAnchors.gd")
const TargetingArrowScene = preload("res://src/core/Card/TargetingArrow.tscn")

#how fast the arrow's end follows the received position
const FOLLOW_SPEED := 15.0
#picture of the card the arrow starts from, when this client does not show
#that card (in the other player's hand): as a fraction of a card's size
#on the board, like the cards shown with the cursors
const CARD_PREVIEW_SCALE := 0.6

#card whose targeting arrow the local player is using
var _local_card = null

#peer id -> {"arrow": TargetingArrow, "card": source card,
# "target": Vector2, "end": Vector2, "last_msec": int}
var _remote := {}

func _init():
	cue_type = "targeting"
	send_interval_msec = 66
	stale_after_msec = 3000

func _ready():
	# warning-ignore:return_value_discarded
	scripting_bus.connect("initiated_targeting", self, "_on_initiated_targeting")

func _on_initiated_targeting(card):
	_local_card = card

#{"s": guid of the card the arrow starts from, "col": arrow color,
# "txt": arrow label, anchor of where it points (CueAnchors)}
#or {"off": 1} when not targeting
func sample():
	var arrow = _local_arrow()
	if !arrow:
		_local_card = null
		return {"off": 1}
	var board = cfc.NMAP.get("board")
	if !board or !board.mouse_pointer:
		return null
	#same as TargetingArrow._process
	var pointing_to
	if gamepadHandler.is_mouse_input():
		pointing_to = board.mouse_pointer.determine_global_mouse_pos()
	else:
		pointing_to = gamepadHandler.get_approx_position()
	var hovered = null
	if arrow._potential_targets:
		hovered = arrow._potential_targets.back()
	var data = CueAnchors.encode(pointing_to, hovered)
	data["h"] = gameData.get_current_local_hero_id()
	data["s"] = _local_card.get_guid()
	data["col"] = arrow.default_color.to_html()
	if arrow.label.visible:
		data["txt"] = arrow.label.text
	return data

#the local player's targeting arrow, if it follows their mouse right now
func _local_arrow():
	if !is_instance_valid(_local_card) or !("targeting_arrow" in _local_card):
		return null
	var arrow = _local_card.targeting_arrow
	if !is_instance_valid(arrow) or !arrow.is_targeting:
		return null
	#an arrow with a fixed destination is a display, not someone choosing
	if arrow._stored_destination:
		return null
	if arrow.display_mode != arrow.DISPLAY_MODE.NORMAL:
		return null
	return arrow

func apply(peer_id: int, data: Dictionary) -> void:
	if data.has("off"):
		forget_peer(peer_id)
		return
	var card = guidMaster.get_object_by_guid(str(data.get("s", "")))
	if !is_instance_valid(card) or !card.is_inside_tree():
		forget_peer(peer_id)
		return

	var remote = _remote.get(peer_id, {})
	if remote and remote["card"] != card:
		forget_peer(peer_id)
		remote = {}
	var target = CueAnchors.decode(data, int(data.get("h", 0)))
	if typeof(target) != TYPE_VECTOR2:
		#pointing somewhere this client cannot show: keep the last position
		if !remote:
			return
		target = remote["target"]
	if !remote:
		remote = {"arrow": _new_arrow(card), "card": card, "end": target}
		_remote[peer_id] = remote
		remote["preview"] = _new_preview(card)
		#before the arrow's first _process: without a destination it
		#would point at this client's mouse
		remote["arrow"].set_destination(target)
		remote["arrow"].global_position = _arrow_origin(card, int(data.get("h", 0)))
	remote["target"] = target
	remote["hero_id"] = int(data.get("h", 0))
	remote["last_msec"] = OS.get_ticks_msec()

	var arrow = remote["arrow"]
	var color = Color(str(data.get("col", CFConst.TARGETTING_ARROW_COLOUR.to_html())))
	if arrow.default_color != color:
		arrow.set_arrow_color(color)
	var text = str(data.get("txt", ""))
	if arrow.label.text != text:
		arrow.set_text(text)

#a TargetingArrow drawing from card, here instead of in the card: it is
#not rotated with the card, and the card's own arrow stays free
func _new_arrow(card):
	var arrow = TargetingArrowScene.instance()
	add_child(arrow)
	#TargetingArrow draws from its owner_object (set to its parent in _ready)
	arrow.owner_object = card
	arrow.z_index_owner_object = card
	#nothing to target here: no highlights, no area detection
	arrow.set_valid_targets([])
	arrow.is_targeting = true
	arrow.show_me()
	arrow.get_node("ArrowHead/Area2D").monitoring = false
	arrow.get_node("ArrowHead/Area2D").monitorable = false
	#above the cards, below the cursors
	arrow.z_as_relative = false
	arrow.z_index = VisualServer.CANVAS_ITEM_Z_MAX - 2
	return arrow

#the card's picture, shown where the arrow starts when the card itself is
#not shown here. Below the arrow
func _new_preview(card):
	var preview = Sprite.new()
	preview.visible = false
	preview.z_as_relative = false
	preview.z_index = VisualServer.CANVAS_ITEM_Z_MAX - 3
	#a card in the other player's hand is shown (not secret in this game)
	var texture = card.get_art_texture(true)
	if texture:
		preview.texture = texture
		var size = CFConst.CARD_SIZE * CARD_PREVIEW_SCALE * cfc.hardcoded_positions_modifier.x
		preview.scale = size / texture.get_size()
	add_child(preview)
	return preview

func _process(delta):
	var now = OS.get_ticks_msec()
	for peer_id in _remote.keys():
		var remote = _remote[peer_id]
		var card = remote["card"]
		if !is_instance_valid(card) or now - remote["last_msec"] > stale_after_msec:
			forget_peer(peer_id)
			continue
		var arrow = remote["arrow"]
		#the card can move (or be focused)
		arrow.global_position = _arrow_origin(card, remote.get("hero_id", 0))
		var preview = remote.get("preview")
		if is_instance_valid(preview):
			preview.visible = !_is_card_shown(card) and preview.texture != null
			#centered on where the arrow starts (TargetingArrow: from its
			#position + half the card's size)
			preview.global_position = arrow.global_position + card.card_size / 2 * card.scale
		remote["end"] = remote["end"].linear_interpolate(remote["target"], min(1.0, delta * FOLLOW_SPEED))
		arrow.set_destination(remote["end"])

#where to draw the arrow from: the card, or, when this client does not
#show it (in the other player's hand), the bottom of their hero zone, where
#their cursor is shown when they look at their hand.
#TargetingArrow starts at its position + half the card's size
func _arrow_origin(card, hero_id: int) -> Vector2:
	if _is_card_shown(card):
		return card.global_position
	var start = CueAnchors.decode({"a": "hand", "x": 0.5}, hero_id)
	if typeof(start) != TYPE_VECTOR2:
		return card.global_position
	return start - card.card_size / 2 * card.scale

func _is_card_shown(card) -> bool:
	return card.is_visible_in_tree() and get_viewport_rect().has_point(card.global_position)

func forget_peer(peer_id: int) -> void:
	var remote = _remote.get(peer_id)
	if remote and is_instance_valid(remote["arrow"]):
		remote["arrow"].queue_free()
	if remote and is_instance_valid(remote.get("preview")):
		remote["preview"].queue_free()
	_remote.erase(peer_id)

func forget_all() -> void:
	for peer_id in _remote.keys():
		forget_peer(peer_id)
