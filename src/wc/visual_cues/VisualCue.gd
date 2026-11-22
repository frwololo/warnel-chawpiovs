# Base class of a kind of visual cue (see VisualCues.gd).
# Children (the views of the remote players) are drawn above the board, in
# board coordinates.
extends Node2D

#unique name of the cue, sent with each message
var cue_type := ""
#how often sample() is called (and data sent, if it changed)
var send_interval_msec := 100
#a remote player's view fades out when nothing came for this long
var stale_after_msec := 3000
#send what sample() returns at every sample, even unchanged (for short
#lived events sent a few times in a row, so that one lost packet does not
#lose the event). Otherwise unchanged data is only sent again every
#VisualCues.KEEPALIVE_MSEC
var resend_unchanged := false

#what to send to the other players, as a small Dictionary of basic types
#(no objects: cards are sent by guid), or null to send nothing
func sample():
	return null

#show what player peer_id sent
func apply(_peer_id: int, _data: Dictionary) -> void:
	pass

#player peer_id left
func forget_peer(_peer_id: int) -> void:
	pass

#cues were disabled: remove all views
func forget_all() -> void:
	pass

#name and color of a remote player
static func player_name(peer_id: int) -> String:
	var player = gameData.network_players.get(peer_id)
	if player:
		return player.get_name()
	return str(peer_id)

const PLAYER_COLORS = [
	Color("#e74c3c"),
	Color("#3498db"),
	Color("#2ecc71"),
	Color("#f1c40f"),
	Color("#9b59b6"),
	Color("#e67e22"),
]

static func player_color(peer_id: int) -> Color:
	var player = gameData.network_players.get(peer_id)
	var index = player.get_id() if player else peer_id
	return PLAYER_COLORS[int(abs(index)) % PLAYER_COLORS.size()]
