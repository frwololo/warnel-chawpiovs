# Concentric circles growing and fading around a point, then gone:
# a remote player's click (ClickCue)
extends Node2D

const DURATION := 0.5 #seconds
const WAVES := 3
#delay between two waves, as a fraction of DURATION
const WAVE_DELAY := 0.2
const MAX_RADIUS := 28.0
const WIDTH := 2.5

var color := Color.white
var _time := 0.0

func _process(delta):
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	update()

func _draw():
	var wave_duration = DURATION * (1.0 - WAVE_DELAY * (WAVES - 1))
	for wave in range(WAVES):
		var t = (_time - wave * WAVE_DELAY * DURATION) / wave_duration
		if t <= 0.0 or t >= 1.0:
			continue
		var wave_color = color
		wave_color.a = 1.0 - t
		draw_arc(Vector2(0, 0), MAX_RADIUS * t, 0, TAU, 32, wave_color, WIDTH, true)
