# Visual cues of the other players' activity during a multiplayer game:
# where their mouse is, which card they are looking at or dragging...
#
# Each kind of cue is a VisualCue child node (see VisualCue.gd):
#  - sample() returns what this client sends (a small Dictionary), or
#    null for nothing to send
#  - apply() shows what a remote player sent
# To add a kind of cue, write a VisualCue and register_cue() it in _ready.
#
# Cues are not part of the game state: they go with rpc_unreliable and can
# be lost or arrive out of order. Only the latest one counts (a sequence
# number per sender and per cue type), and an unchanged cue is sent again
# every KEEPALIVE_MSEC, so that a lost packet is corrected and receivers
# can tell a quiet player from a gone one.
#
# This node must have the same path on every client (it is created by the
# Board, as "VisualCues").
extends Node2D

const VisualCue = preload("res://src/wc/visual_cues/VisualCue.gd")
const CursorCue = preload("res://src/wc/visual_cues/CursorCue.gd")
const ClickCue = preload("res://src/wc/visual_cues/ClickCue.gd")

const KEEPALIVE_MSEC := 1000

#cue_type -> VisualCue
var cues := {}

var _sent_seq := {} #cue_type -> last sequence number sent
var _sent_hash := {} #cue_type -> hash of the last data sent
var _next_sample_msec := {} #cue_type -> when to sample next
var _next_keepalive_msec := {} #cue_type -> when to send unchanged data again
var _received_seq := {} #peer id -> {cue_type -> last sequence number}

#the other clients have this node only once they have loaded the board
var _all_clients_loaded := false
var _was_enabled := false

func _ready():
	#above the cards and the menus of the board
	z_as_relative = false
	z_index = VisualServer.CANVAS_ITEM_Z_MAX - 1
	# warning-ignore:return_value_discarded
	get_tree().connect("network_peer_disconnected", self, "_on_network_peer_disconnected")
	#all_clients_game_loaded is only emitted on the client that asked for
	#the load (the host). Every client gets step_started once all of them
	#have loaded (GameData.start_phaseContainer, sent to all). The earlier
	#one, when the PhaseContainer is created, comes before this node exists
	# warning-ignore:return_value_discarded
	scripting_bus.connect("all_clients_game_loaded", self, "_on_all_clients_game_loaded")
	# warning-ignore:return_value_discarded
	scripting_bus.connect("step_started", self, "_on_step_started")

	register_cue(CursorCue.new())
	register_cue(ClickCue.new())

func register_cue(cue: VisualCue):
	cues[cue.cue_type] = cue
	add_child(cue)

func is_enabled() -> bool:
	if !_all_clients_loaded:
		return false
	if !gameData.is_multiplayer_game:
		return false
	if gameData.testSuite:
		return false
	if cfc.get_setting("hide_remote_activity"):
		return false
	if !get_tree().network_peer:
		return false
	if !networkManager.can_send():
		return false
	return true

func _process(_delta):
	var enabled = is_enabled()
	if !enabled:
		if _was_enabled:
			for cue in cues.values():
				cue.forget_all()
		_was_enabled = false
		return
	_was_enabled = true

	var now = OS.get_ticks_msec()
	for cue_type in cues:
		var cue: VisualCue = cues[cue_type]
		if now < _next_sample_msec.get(cue_type, 0):
			continue
		_next_sample_msec[cue_type] = now + cue.send_interval_msec

		var data = cue.sample()
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var data_hash = data.hash()
		if data_hash == _sent_hash.get(cue_type) and now < _next_keepalive_msec.get(cue_type, 0) \
				and !cue.resend_unchanged:
			continue
		_sent_hash[cue_type] = data_hash
		_next_keepalive_msec[cue_type] = now + KEEPALIVE_MSEC
		var seq = _sent_seq.get(cue_type, 0) + 1
		_sent_seq[cue_type] = seq
		rpc_unreliable("receive_cue", cue_type, seq, data)

remote func receive_cue(cue_type, seq, data):
	if !is_enabled():
		return
	if typeof(cue_type) != TYPE_STRING or typeof(seq) != TYPE_INT or typeof(data) != TYPE_DICTIONARY:
		return
	var cue: VisualCue = cues.get(cue_type)
	if !cue:
		return
	var sender = get_tree().get_rpc_sender_id()
	var sender_seqs: Dictionary = _received_seq.get(sender, {})
	#late or duplicated: a newer one was already shown
	if seq <= sender_seqs.get(cue_type, 0):
		return
	sender_seqs[cue_type] = seq
	_received_seq[sender] = sender_seqs
	cue.apply(sender, data)

func _on_all_clients_game_loaded(_details = {}):
	_all_clients_loaded = true

func _on_step_started(_card = null, _details = {}):
	_all_clients_loaded = true

func _on_network_peer_disconnected(peer_id):
	_received_seq.erase(peer_id)
	for cue in cues.values():
		cue.forget_peer(peer_id)
