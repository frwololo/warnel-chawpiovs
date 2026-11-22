# A remote player's mouse cursor: an arrow in the player's color, their
# name, and the card they look at in their hand or drag.
# Moves smoothly towards the latest position received, fades out when
# nothing comes or the position cannot be shown on this client.
extends Node2D

#arrow shape, tip at (0, 0)
var _arrow := PoolVector2Array([
	Vector2(0, 0), Vector2(0, 26), Vector2(7, 20),
	Vector2(12, 31), Vector2(17, 29), Vector2(12, 18), Vector2(21, 18)])
const FOLLOW_SPEED := 15.0
const FADE_SPEED := 4.0
#opacity of the arrow and the player's name, 0 to 1 (the card shown with
#the cursor stays opaque)
const CURSOR_ALPHA := 0.6
#card shown with the cursor, as a fraction of a card's size on the board
const CARD_PREVIEW_SCALE := 0.6

var color := Color.white
var stale_after_msec := 3000

var _target = null #Vector2, or null: nothing to show
var _last_update_msec := 0
var _shown_once := false
var _label: Label
var _card_sprite: Sprite
var _card = null

func setup(player_name: String, player_color: Color, stale_msec: int):
	color = player_color
	stale_after_msec = stale_msec
	modulate.a = 0

	_card_sprite = Sprite.new()
	_card_sprite.centered = false
	_card_sprite.visible = false
	_card_sprite.position = Vector2(18, 34)
	add_child(_card_sprite)

	_label = Label.new()
	_label.text = player_name
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.rect_position = Vector2(22, 8)
	_label.add_color_override("font_color", color)
	_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	_label.add_constant_override("shadow_offset_x", 1)
	_label.add_constant_override("shadow_offset_y", 1)
	_label.self_modulate.a = CURSOR_ALPHA
	add_child(_label)

#where to show the cursor (Vector2 in board coordinates), or null.
#in_remote_hand: the player is looking at their own hand, which this client
#does not show: the cursor is placed below their hero zone
func set_target(target, in_remote_hand: bool):
	_last_update_msec = OS.get_ticks_msec()
	_target = target
	if typeof(target) == TYPE_VECTOR2 and !_shown_once:
		position = target
		_shown_once = true
	#the card shown with the cursor goes above it when the cursor is at the
	#bottom of a hero zone (hand), below it otherwise
	if _card_sprite:
		_card_sprite.position = Vector2(18, -_preview_size().y - 4) if in_remote_hand else Vector2(18, 34)

func set_card(card, _dragged: bool):
	if card == _card:
		return
	_card = card
	if !card:
		_card_sprite.visible = false
		return
	#a card in the other player's hand is shown (not secret in this game),
	#a card on the board as this client sees it (face down stays face down)
	var force_if_facedown = card.state in [Card.CardState.IN_HAND, Card.CardState.FOCUSED_IN_HAND]
	var texture = card.get_art_texture(force_if_facedown)
	if !texture:
		_card_sprite.visible = false
		return
	_card_sprite.texture = texture
	var size = _preview_size()
	_card_sprite.scale = size / texture.get_size()
	_card_sprite.visible = true

func _preview_size() -> Vector2:
	return CFConst.CARD_SIZE * CARD_PREVIEW_SCALE * cfc.hardcoded_positions_modifier.x

func _process(delta):
	var stale = OS.get_ticks_msec() - _last_update_msec > stale_after_msec
	var visible_target = typeof(_target) == TYPE_VECTOR2 and !stale
	if visible_target:
		position = position.linear_interpolate(_target, min(1.0, delta * FOLLOW_SPEED))
		modulate.a = min(1.0, modulate.a + delta * FADE_SPEED)
	else:
		modulate.a = max(0.0, modulate.a - delta * FADE_SPEED)

func _draw():
	var arrow_color = color
	arrow_color.a = CURSOR_ALPHA
	draw_colored_polygon(_arrow, arrow_color)
	var outline = Array(_arrow)
	outline.append(_arrow[0])
	draw_polyline(PoolVector2Array(outline), Color(0, 0, 0, 0.8 * CURSOR_ALPHA), 1.5, true)
