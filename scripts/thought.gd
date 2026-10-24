extends RigidBody2D
## One intrusive thought: a physics ball with a face that merges with its twin.

const Data = preload("res://scripts/thought_data.gd")

signal twin_touched(a: RigidBody2D, b: RigidBody2D)

const INK := Color(0.12, 0.1, 0.2)

static var _font: Font
static var _size_cache := {}

var tier := 0
var radius := 26.0
var phrase := ""
var age := 0.0
var merging := false
## 0..1 while the thought is being let go by breathing.
var dissolve := 0.0

var _pop := 1.0
var _pop_from := 0.6
var _blink := 2.0
var _shape: CircleShape2D


func setup(t: int, text: String, from_scale := 0.6) -> void:
	tier = t
	radius = Data.RADII[t]
	phrase = text
	_pop = 0.0
	_pop_from = from_scale
	_blink = randf_range(1.0, 4.0)

	_shape = CircleShape2D.new()
	_shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	add_child(cs)

	mass = 1.0 + t * 0.8
	angular_damp = 2.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.05
	mat.friction = 0.45
	physics_material_override = mat
	contact_monitor = true
	max_contacts_reported = 8


func _physics_process(_delta: float) -> void:
	if merging or dissolve > 0.0:
		return
	for body in get_colliding_bodies():
		var other = body
		if other.get_script() == get_script() and other.tier == tier \
				and not other.merging and other.dissolve <= 0.0:
			twin_touched.emit(self, other)
			return


func _process(delta: float) -> void:
	age += delta
	if _pop < 1.0:
		_pop = minf(_pop + delta * 5.0, 1.0)
	_blink -= delta
	if _blink < -0.14:
		_blink = randf_range(2.0, 5.0)
	_shape.radius = maxf(radius * (1.0 - dissolve), 2.0)
	queue_redraw()


func _draw() -> void:
	var s := lerpf(_pop_from, 1.0, Data.ease_out_back(_pop)) * (1.0 - dissolve)
	# Counter-rotate so the face and text stay upright while the ball rolls.
	draw_set_transform(Vector2.ZERO, -rotation, Vector2(s, s))
	paint(self, tier, phrase, _blink < 0.0, 1.0 - dissolve * 0.5)


## Draws a thought of the given tier centered at the canvas origin, unscaled.
static func paint(ci: CanvasItem, t: int, text: String, eyes_closed := false, alpha := 1.0) -> void:
	var r: float = Data.RADII[t]
	var c: Color = Data.COLORS[t]
	c.a = alpha
	var shadow := c.darkened(0.45)
	shadow.a = alpha * 0.9
	ci.draw_circle(Vector2(0, r * 0.07), r, shadow)
	ci.draw_circle(Vector2.ZERO, r * 0.95, c)
	ci.draw_circle(Vector2(-r * 0.4, -r * 0.45), r * 0.18, Color(1, 1, 1, 0.3 * alpha))

	var ink := Color(INK, alpha)
	var worry := t / float(Data.MAX_TIER)
	var eye_r := maxf(r * 0.1, 2.5)
	var line_w := maxf(r * 0.045, 1.6)
	for side in [-1.0, 1.0]:
		var e := Vector2(r * 0.3 * side, -r * 0.34)
		if eyes_closed:
			ci.draw_line(e - Vector2(eye_r, 0), e + Vector2(eye_r, 0), ink, line_w, true)
		else:
			ci.draw_circle(e, eye_r * (1.0 + worry * 0.45), Color(1, 1, 1, alpha))
			ci.draw_circle(e + Vector2(0, eye_r * 0.2), eye_r * 0.6, ink)
		if t >= 2:
			# Brows tilt up toward the middle as the worry grows.
			var outer := e + Vector2(eye_r * 1.5 * side, -eye_r * (1.7 - worry * 0.5))
			var inner := e + Vector2(-eye_r * 1.1 * side, -eye_r * (1.9 + worry * 1.2))
			ci.draw_line(outer, inner, ink, line_w, true)

	var font := bold_font()
	var fs := _text_size(t, text)
	var w := r * 1.55
	var block := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	var top := r * 0.18 - block.y * 0.5
	ci.draw_multiline_string(font, Vector2(-w * 0.5, top + font.get_ascent(fs)), text,
			HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, ink)


static func bold_font() -> Font:
	if _font == null:
		var v := FontVariation.new()
		v.base_font = ThemeDB.fallback_font
		v.variation_embolden = 0.6
		_font = v
	return _font


static func _text_size(t: int, text: String) -> int:
	var key := "%d|%s" % [t, text]
	if _size_cache.has(key):
		return _size_cache[key]
	var r: float = Data.RADII[t]
	var w := r * 1.55
	var font := bold_font()
	var fs := int(clampf(r * 0.34, 11.0, 38.0))
	while fs > 8:
		var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
		if sz.y <= r * 0.95:
			break
		fs -= 1
	_size_cache[key] = fs
	return fs
