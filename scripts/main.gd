extends Node2D
## «3 часа ночи»: a Suika-like about intrusive thoughts. Score is sleep minutes counted from 03:00.

const Data = preload("res://scripts/thought_data.gd")
const ThoughtScript = preload("res://scripts/thought.gd")
const Sfx = preload("res://scripts/sfx.gd")

enum State { TITLE, PLAY, OVER }

const WIDTH := 720.0
const BOX_LEFT := 56.0
const BOX_RIGHT := 664.0
const WALL := 80.0
const BREATHE_R := 70.0
const DROP_COOLDOWN := 0.45
const DANGER_LIMIT := 2.3
const ALARM_MINUTES := 240
const BREATH_TIME_SCALE := 0.35
const COMBO_WINDOW_MS := 1100
const MAX_COMBO := 3
const SAVE_PATH := "user://save.cfg"

const SKY_TOP := Color("0b0d1f")
const SKY_BOTTOM := Color("1b1640")
const CALM_TOP := Color("0c2a33")
const CALM_BOTTOM := Color("15404a")
const TEXT := Color("e8ecff")
const DIM := Color(0.8, 0.85, 1.0, 0.6)
const CALM := Color("8ee3ef")
const DANGER := Color("ff5d6c")

var state := State.TITLE
var view_h := 1280.0
var box_top := 360.0
var box_bottom := 1065.0
var drop_y := 300.0
var clock_y := 150.0
var breathe_center := Vector2(360, 1180)

var thoughts: Node2D
var walls: StaticBody2D
var camera: Camera2D
var overlay: Node2D
var sfx: Node

var aim_x := WIDTH / 2.0
var aim_touch := -1
var breathe_touch := -1
var held_tier := 0
var held_phrase := ""
var held_pop := 1.0
var next_tier := 0
var next_phrase := ""
var cooldown := 0.0
## A tap during the cooldown is remembered and dropped as soon as it ends.
var drop_queued := false
var queued_x := 0.0

var score := 0
var best := 0
var new_best := false
var max_tier_seen := 0
var combo := 0
var last_merge_ms := 0
var danger_t := 0.0
var alarm_done := false
var milestones_done := {}
var wake_line := ""

var breath := 1.0
var breathing := false
var calm := 0.0
var shake := 0.0
var over_t := 0.0
var time_s := 0.0

var stars := []
var particles := []
var floaters := []
var toasts: Array[String] = []
var toast_t := 0.0

var _last_ms := 0
var _autoplay_left := 0.0
var _shot_path := ""
var _bot_t := 0.0
var _bot_stack := false


func _ready() -> void:
	randomize()
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera)
	camera.make_current()

	walls = StaticBody2D.new()
	var wall_mat := PhysicsMaterial.new()
	wall_mat.friction = 0.4
	walls.physics_material_override = wall_mat
	add_child(walls)

	thoughts = Node2D.new()
	add_child(thoughts)

	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = Node2D.new()
	layer.add_child(overlay)
	overlay.draw.connect(_draw_overlay)

	sfx = Sfx.new()
	add_child(sfx)

	for i in 80:
		stars.append({"x": randf() * WIDTH, "y": randf(), "s": randf_range(0.8, 2.4), "ph": randf() * TAU})

	best = _load_best()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_roll_next()
	_take_next()
	_last_ms = Time.get_ticks_msec()
	_parse_dev_args()


# --- Layout -------------------------------------------------------------------

func _layout() -> void:
	view_h = maxf(get_viewport().get_visible_rect().size.y, 1280.0)
	box_bottom = view_h - 215.0
	var h := clampf(view_h - 215.0 - 375.0, 680.0, 930.0)
	box_top = box_bottom - h
	drop_y = box_top - 64.0
	clock_y = maxf(box_top - 215.0, 120.0)
	breathe_center = Vector2(WIDTH / 2.0, box_bottom + 112.0)

	for c in walls.get_children():
		c.queue_free()
	var tall := box_bottom - box_top + 700.0
	_add_wall(Rect2(BOX_LEFT - WALL, box_bottom - tall, WALL, tall + WALL))
	_add_wall(Rect2(BOX_RIGHT, box_bottom - tall, WALL, tall + WALL))
	_add_wall(Rect2(BOX_LEFT - WALL, box_bottom, BOX_RIGHT - BOX_LEFT + WALL * 2.0, WALL))


func _add_wall(rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = rect.get_center()
	walls.add_child(cs)


# --- Game flow ------------------------------------------------------------------

func _start_game() -> void:
	for c in thoughts.get_children():
		c.queue_free()
	state = State.PLAY
	score = 0
	new_best = false
	max_tier_seen = 0
	combo = 0
	danger_t = 0.0
	alarm_done = false
	milestones_done = {}
	breath = 1.0
	cooldown = 0.3
	drop_queued = false
	Engine.time_scale = 1.0
	particles.clear()
	floaters.clear()
	toasts.clear()
	toast_t = 0.0
	_roll_next()
	_take_next()
	if best == 0:
		_toast("Одинаковые мысли сливаются")
		_toast("Зажми «дыши», чтобы замедлить время")


func _game_over() -> void:
	state = State.OVER
	over_t = 0.0
	Engine.time_scale = 1.0
	aim_touch = -1
	breathe_touch = -1
	for c in thoughts.get_children():
		c.set_deferred("freeze", true)
	if score > best:
		best = score
		new_best = true
		_save_best()
	wake_line = Data.WAKE_LINES.pick_random()
	shake = 18.0
	sfx.play_over()


func _roll_next() -> void:
	var cap := mini(Data.SPAWN_WEIGHTS.size() - 1, maxi(max_tier_seen, 2))
	var total := 0.0
	for i in cap + 1:
		total += Data.SPAWN_WEIGHTS[i]
	var r := randf() * total
	var t := 0
	while t < cap and r >= Data.SPAWN_WEIGHTS[t]:
		r -= Data.SPAWN_WEIGHTS[t]
		t += 1
	next_tier = t
	next_phrase = Data.random_phrase(t)


func _take_next() -> void:
	held_tier = next_tier
	held_phrase = next_phrase
	held_pop = 0.0
	_roll_next()


func _drop() -> void:
	if state != State.PLAY:
		return
	if cooldown > 0.0:
		drop_queued = true
		queued_x = aim_x
		return
	# A hair of jitter so identical drops never balance in a perfect column.
	var x := _held_x() + randf_range(-1.5, 1.5)
	_spawn_thought(held_tier, Vector2(x, drop_y), Vector2(0, 150), 0.9, held_phrase)
	sfx.play_drop()
	cooldown = DROP_COOLDOWN
	_take_next()


func _held_x() -> float:
	var r: float = Data.RADII[held_tier]
	return clampf(aim_x, BOX_LEFT + r + 2.0, BOX_RIGHT - r - 2.0)


func _spawn_thought(t: int, pos: Vector2, vel: Vector2, from_scale: float, text := "") -> void:
	var th := ThoughtScript.new()
	th.setup(t, text if text != "" else Data.random_phrase(t), from_scale)
	th.position = pos
	th.linear_velocity = vel
	th.twin_touched.connect(_on_twins)
	thoughts.add_child(th)


func _on_twins(a: ThoughtScript, b: ThoughtScript) -> void:
	if a.merging or b.merging or state != State.PLAY:
		return
	a.merging = true
	b.merging = true
	_merge.call_deferred(a, b)


func _merge(a: ThoughtScript, b: ThoughtScript) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or state != State.PLAY:
		return
	var t: int = a.tier
	var mid := (a.global_position + b.global_position) * 0.5
	var vel := (a.linear_velocity + b.linear_velocity) * 0.5
	a.queue_free()
	b.queue_free()

	var now := Time.get_ticks_msec()
	combo = mini(combo + 1, MAX_COMBO) if now - last_merge_ms < COMBO_WINDOW_MS else 1
	last_merge_ms = now
	var label := "×%d" % combo if combo > 1 else ""

	if t >= Data.MAX_TIER:
		# Two existential horrors cancel each other out.
		_burst(mid, Color.WHITE, 70, 600.0)
		shake = 28.0
		_add_score(60 * combo, mid, "ГЛУБОКИЙ СОН")
		sfx.play_big()
		return

	var nt := t + 1
	_spawn_thought(nt, mid, vel + Vector2(0, -80), 0.55)
	_burst(mid, Data.COLORS[nt], 8 + nt * 3, 170.0 + nt * 30.0)
	shake = maxf(shake, 1.5 + nt * 1.4)
	_add_score(Data.points_for(nt) * combo, mid, label)
	sfx.play_merge(nt)
	if nt > max_tier_seen:
		max_tier_seen = nt
		if nt >= 4:
			_toast("Новый уровень тревоги: %d из 11" % (nt + 1))


func _add_score(points: int, at: Vector2, label := "") -> void:
	score += points
	var text := "+%d" % points
	if label != "":
		text += " " + label
	floaters.append({"p": at, "t": 0.0, "text": text, "big": points >= 20})
	for m in Data.MILESTONES:
		if score >= m and not milestones_done.has(m):
			milestones_done[m] = true
			_toast(Data.MILESTONES[m])
	if score >= ALARM_MINUTES and not alarm_done:
		alarm_done = true
		_toast("07:00 — БУДИЛЬНИК! Ты дожил до утра")
		_toast("Можно поспать ещё. Рекорд ждёт")
		sfx.play_alarm()
		for i in 5:
			_burst(Vector2(randf_range(100, 620), randf_range(box_top, box_top + 300)), Data.COLORS.pick_random(), 20, 420.0)


func _toast(text: String) -> void:
	toasts.append(text)


# --- Frame update ---------------------------------------------------------------

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real := minf((now - _last_ms) / 1000.0, 0.1)
	_last_ms = now
	time_s += real

	_update_breath(real)
	if state == State.PLAY:
		cooldown = maxf(cooldown - real * Engine.time_scale, 0.0)
		if drop_queued and cooldown <= 0.0:
			drop_queued = false
			aim_x = queued_x
			_drop()
		held_pop = minf(held_pop + real * 5.0, 1.0)
		_check_danger(real * Engine.time_scale)
		_dissolve_small(real)
	elif state == State.OVER:
		over_t += real
	_update_fx(real)
	_run_dev(real)

	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	shake = move_toward(shake, 0.0, real * 45.0)
	queue_redraw()
	overlay.queue_redraw()


func _update_breath(real: float) -> void:
	breathing = state == State.PLAY and breathe_touch != -1 and breath > 0.0
	if breathing:
		breath = maxf(breath - real * 0.3, 0.0)
	else:
		breath = minf(breath + real * 0.09, 1.0)
	var target := BREATH_TIME_SCALE if breathing else 1.0
	Engine.time_scale = move_toward(Engine.time_scale, target, real * 3.0)
	calm = move_toward(calm, 1.0 if breathing else 0.0, real * 2.5)


## While breathing, the smallest thoughts melt away.
func _dissolve_small(real: float) -> void:
	for t: ThoughtScript in thoughts.get_children():
		if t.merging:
			continue
		if breathing and t.tier == 0 and t.age > 0.3:
			t.dissolve += real * 0.75
			if t.dissolve >= 1.0:
				t.merging = true
				_burst(t.global_position, Data.COLORS[0], 12, 140.0)
				_add_score(1, t.global_position, "отпустил")
				sfx.play_let_go()
				t.queue_free()
		elif t.dissolve > 0.0:
			t.dissolve = maxf(t.dissolve - real * 1.5, 0.0)


func _check_danger(dt: float) -> void:
	var over_line := false
	for t: ThoughtScript in thoughts.get_children():
		if t.merging or t.age < 1.0:
			continue
		if t.global_position.y - t.radius < box_top:
			over_line = true
			break
	if over_line:
		var before := danger_t
		danger_t += dt
		if int(before * 3.0) != int(danger_t * 3.0):
			sfx.play_tick()
		if danger_t >= DANGER_LIMIT:
			_game_over()
	else:
		danger_t = maxf(danger_t - dt * 2.0, 0.0)


func _burst(at: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		particles.append({
			"p": at,
			"v": Vector2.from_angle(randf() * TAU) * randf_range(0.25, 1.0) * speed,
			"t": 0.0,
			"life": randf_range(0.4, 0.95),
			"c": color,
			"s": randf_range(3.0, 8.0),
		})


func _update_fx(real: float) -> void:
	var drag := pow(0.08, real)
	for p in particles:
		p["t"] += real
		p["v"] = p["v"] * drag + Vector2(0, 420.0 * real)
		p["p"] += p["v"] * real
	particles = particles.filter(func(p): return p["t"] < p["life"])
	for f in floaters:
		f["t"] += real
		f["p"] += Vector2(0, -70.0 * real)
	floaters = floaters.filter(func(f): return f["t"] < 1.2)
	if not toasts.is_empty():
		toast_t += real
		if toast_t > 2.6:
			toast_t = 0.0
			toasts.pop_front()


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p := overlay.make_canvas_position_local(event.position)
		if event.pressed:
			_on_press(event.index, p)
		else:
			_on_release(event.index, p)
	elif event is InputEventScreenDrag:
		if event.index == aim_touch:
			aim_x = overlay.make_canvas_position_local(event.position).x


func _on_press(index: int, p: Vector2) -> void:
	sfx.unlock()
	if state == State.TITLE:
		_start_game()
		return
	if state == State.OVER:
		if over_t > 0.9:
			_start_game()
		return
	if p.distance_to(breathe_center) < BREATHE_R + 34.0:
		breathe_touch = index
	elif aim_touch == -1:
		aim_touch = index
		aim_x = p.x


func _on_release(index: int, p: Vector2) -> void:
	if index == breathe_touch:
		breathe_touch = -1
	if index == aim_touch:
		aim_touch = -1
		aim_x = p.x
		_drop()


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	var top_c := SKY_TOP.lerp(CALM_TOP, calm)
	var bot_c := SKY_BOTTOM.lerp(CALM_BOTTOM, calm)
	draw_polygon(
		PackedVector2Array([Vector2(-60, -60), Vector2(WIDTH + 60, -60), Vector2(WIDTH + 60, view_h + 60), Vector2(-60, view_h + 60)]),
		PackedColorArray([top_c, top_c, bot_c, bot_c]))

	for s in stars:
		var a: float = 0.3 + 0.35 * sin(time_s * 1.2 + s["ph"])
		draw_circle(Vector2(s["x"], s["y"] * (box_top - 30.0)), s["s"], Color(1, 1, 1, a))

	# A sleepy full moon that the player is trying to imitate.
	var moon := Vector2(92, clock_y - 6.0)
	var moon_ink := Color("c9b77a")
	draw_circle(moon, 40.0, Color("fff1c1"))
	draw_circle(moon + Vector2(-14, 16), 7.0, Color("f3e3a8"))
	draw_circle(moon + Vector2(16, 10), 5.0, Color("f3e3a8"))
	for side in [-1.0, 1.0]:
		draw_arc(moon + Vector2(13.0 * side, -6), 7.0, 0.15, PI - 0.15, 12, moon_ink, 3.0, true)
	var z_font := ThoughtScript.bold_font()
	for i in 3:
		var k := fmod(time_s * 0.35 + i / 3.0, 1.0)
		var zp := moon + Vector2(34 + k * 34, -26 - k * 48)
		draw_string(z_font, zp, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 + k * 14), Color(1, 1, 1, 0.55 * (1.0 - k)))

	var rect := Rect2(BOX_LEFT, box_top, BOX_RIGHT - BOX_LEFT, box_bottom - box_top)
	draw_rect(rect, Color(1, 1, 1, 0.035 + 0.03 * calm))
	var edge := Color(0.75, 0.8, 1.0, 0.35)
	draw_line(Vector2(BOX_LEFT, box_top - 20), Vector2(BOX_LEFT, box_bottom), edge, 5.0, true)
	draw_line(Vector2(BOX_RIGHT, box_top - 20), Vector2(BOX_RIGHT, box_bottom), edge, 5.0, true)
	draw_line(Vector2(BOX_LEFT - 2, box_bottom), Vector2(BOX_RIGHT + 2, box_bottom), edge, 5.0, true)

	var line_c := Color(1, 1, 1, 0.16)
	if danger_t > 0.0:
		line_c = Color(DANGER, 0.45 + 0.5 * absf(sin(time_s * 12.0)))
	draw_dashed_line(Vector2(BOX_LEFT, box_top), Vector2(BOX_RIGHT, box_top), line_c, 3.0, 14.0)


func _draw_overlay() -> void:
	var o := overlay
	_text(o, _clock(score), Vector2(WIDTH / 2.0, clock_y), 112, TEXT)
	var sub := "спи до 07:00"
	if best > 0:
		sub = "рекорд: до %s" % _clock(best)
	_text(o, sub, Vector2(WIDTH / 2.0, clock_y + 66.0), 24, DIM)

	if state == State.PLAY:
		_draw_held(o)
		_draw_breathe(o)
		if danger_t > 0.0:
			_text(o, "сейчас проснёшься!", Vector2(WIDTH / 2.0, box_top + 38.0), 30,
					Color(DANGER, 0.6 + 0.4 * absf(sin(time_s * 10.0))))

	for p in particles:
		var k: float = 1.0 - p["t"] / p["life"]
		var col: Color = p["c"]
		col.a = k
		o.draw_circle(p["p"], p["s"] * k, col)
	for f in floaters:
		var k: float = 1.0 - f["t"] / 1.2
		_text(o, f["text"], f["p"], 40 if f["big"] else 28, Color(1, 1, 1, k))

	if not toasts.is_empty():
		var a := clampf(minf(toast_t * 5.0, (2.6 - toast_t) * 4.0), 0.0, 1.0)
		var at := Vector2(WIDTH / 2.0, box_top + 100.0)
		var pill := Rect2(at.x - 300, at.y - 34, 600, 68)
		o.draw_rect(pill, Color(0.05, 0.05, 0.12, 0.75 * a))
		_text(o, toasts[0], at, 28, Color(TEXT, a), 580.0)

	if state == State.TITLE:
		_draw_title(o)
	elif state == State.OVER:
		_draw_over(o)


func _draw_held(o: CanvasItem) -> void:
	var x := _held_x()
	var r: float = Data.RADII[held_tier]
	o.draw_dashed_line(Vector2(x, drop_y + r), Vector2(x, box_bottom), Color(1, 1, 1, 0.1), 2.0, 10.0)
	var s := lerpf(0.3, 1.0, Data.ease_out_back(held_pop))
	_paint(o, Vector2(x, drop_y), held_tier, held_phrase, s, 0.55 if cooldown > 0.0 else 1.0)

	var nx := WIDTH - 82.0
	_text(o, "дальше", Vector2(nx, clock_y - 52.0), 20, DIM)
	_paint(o, Vector2(nx, clock_y + 4.0), next_tier, next_phrase, 0.75, 0.9)


func _draw_breathe(o: CanvasItem) -> void:
	var c := breathe_center
	var pulse := 1.0 + (0.08 * sin(time_s * TAU / 4.0) if breathing else 0.0)
	o.draw_circle(c, BREATHE_R * pulse, Color(CALM, 0.12 + 0.25 * calm))
	o.draw_arc(c, BREATHE_R + 12.0, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 8.0, true)
	if breath > 0.0:
		o.draw_arc(c, BREATHE_R + 12.0, -PI / 2.0, -PI / 2.0 + TAU * breath, 64, CALM, 8.0, true)
	var label := "дыши"
	if breathing:
		label = "вдох…" if fmod(time_s, 4.0) < 2.0 else "выдох…"
	elif breath < 0.15:
		label = "…"
	_text(o, label, c, 30, TEXT)


func _draw_title(o: CanvasItem) -> void:
	o.draw_rect(Rect2(0, 0, WIDTH, view_h), Color(0.02, 0.02, 0.07, 0.6))
	var y := view_h * 0.3
	_text(o, "3 часа ночи", Vector2(WIDTH / 2.0, y), 86, TEXT)
	_text(o, "игра про мысли, которые не дают уснуть", Vector2(WIDTH / 2.0, y + 76.0), 26, DIM)
	_paint(o, Vector2(WIDTH / 2.0 - 120.0, y + 210.0), 1, "утюг?", 1.3)
	_paint(o, Vector2(WIDTH / 2.0, y + 210.0), 1, "утюг?", 1.3)
	_text(o, "=", Vector2(WIDTH / 2.0 + 75.0, y + 210.0), 48, TEXT)
	_paint(o, Vector2(WIDTH / 2.0 + 170.0, y + 210.0), 2, "а дедлайн?", 1.1)
	var rules := "Одинаковые мысли сливаются в мысли побольше.\nНе дай им переполнить голову.\nЗажми «дыши» — время замедлится, а мелкие мысли растворятся.\nПродержись до 07:00."
	_text(o, rules, Vector2(WIDTH / 2.0, y + 400.0), 26, Color(TEXT, 0.85), 600.0)
	var blink := 0.45 + 0.55 * absf(sin(time_s * 2.2))
	_text(o, "коснись, чтобы закрыть глаза", Vector2(WIDTH / 2.0, y + 560.0), 32, Color(CALM, blink))


func _draw_over(o: CanvasItem) -> void:
	var a := clampf(over_t * 2.5, 0.0, 1.0)
	o.draw_rect(Rect2(0, 0, WIDTH, view_h), Color(0.02, 0.02, 0.07, 0.72 * a))
	var y := view_h * 0.32
	_text(o, "Ты проснулся", Vector2(WIDTH / 2.0, y), 76, Color(TEXT, a))
	_text(o, "в %s" % _clock(score), Vector2(WIDTH / 2.0, y + 90.0), 52, Color(DANGER, a))
	_text(o, "проспал: %s" % _duration(score), Vector2(WIDTH / 2.0, y + 160.0), 32, Color(TEXT, a * 0.9))
	if new_best:
		_text(o, "Новый рекорд сна!", Vector2(WIDTH / 2.0, y + 220.0), 34, Color(CALM, a))
	else:
		_text(o, "рекорд: %s" % _duration(best), Vector2(WIDTH / 2.0, y + 220.0), 26, Color(DIM, a * DIM.a))
	_text(o, wake_line, Vector2(WIDTH / 2.0, y + 320.0), 28, Color(TEXT, a * 0.75), 600.0)
	if over_t > 0.9:
		var blink := 0.45 + 0.55 * absf(sin(time_s * 2.2))
		_text(o, "коснись, чтобы попробовать снова", Vector2(WIDTH / 2.0, y + 460.0), 30, Color(CALM, blink))


func _paint(ci: CanvasItem, at: Vector2, t: int, text: String, s: float, alpha := 1.0) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(s, s))
	ThoughtScript.paint(ci, t, text, false, alpha)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text(ci: CanvasItem, s: String, center: Vector2, size: int, color: Color, width := 680.0) -> void:
	var font := ThoughtScript.bold_font()
	var sz := font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, width, size)
	var pos := Vector2(center.x - width / 2.0, center.y - sz.y / 2.0 + font.get_ascent(size))
	ci.draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size, -1, color)


func _clock(minutes: int) -> String:
	var total := 3 * 60 + minutes
	return "%02d:%02d" % [(total / 60) % 24, total % 60]


func _duration(minutes: int) -> String:
	return "%d ч %02d мин" % [minutes / 60, minutes % 60]


# --- Save -----------------------------------------------------------------------

func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return int(cfg.get_value("game", "best", 0))
	return 0


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.save(SAVE_PATH)


# --- Dev: bot autoplay + screenshot (`-- --autoplay=20 --shot=path.png`) ---------

func _parse_dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoplay="):
			_autoplay_left = arg.get_slice("=", 1).to_float()
		elif arg == "--stack":
			_bot_stack = true
		elif arg.begins_with("--shot="):
			_shot_path = arg.get_slice("=", 1)
	if _autoplay_left > 0.0:
		_start_game()


func _run_dev(real: float) -> void:
	if _autoplay_left <= 0.0:
		return
	_autoplay_left -= real
	_bot_t += real
	if state == State.PLAY and _bot_t > 0.55:
		_bot_t = 0.0
		aim_x = WIDTH / 2.0 if _bot_stack else randf_range(BOX_LEFT, BOX_RIGHT)
		_drop()
	breathe_touch = 99 if fmod(time_s, 6.0) < 1.0 else -1
	if _autoplay_left <= 0.0:
		print("autoplay done: state=%s score=%d thoughts=%d max_tier=%d" % [State.keys()[state], score, thoughts.get_child_count(), max_tier_seen])
		if _shot_path != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot_path)
			print("shot saved: ", _shot_path)
		get_tree().quit()
