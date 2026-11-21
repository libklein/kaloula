@tool
class_name FrogRig
extends Node2D
## Procedural top-down frog: hop, crawl, belly up, turn in place and three idles
## (breathe & blink, toe stretch, catch a mosquito).
## Drawn in code (no textures). The frog faces up (-Y);
## rotate the node to point it somewhere else. Colours live in a FrogPalette.

signal cycle_finished(animation: Anim)
## Emitted when a turn started with turn() is done (the node has been rotated).
signal turn_finished(degrees: float)

## IDLE = sitting, breathing and blinking. STRETCH and CATCH are idle loops too
## (toe stretch, catching a mosquito); all three start and end in the sitting pose.
enum Anim { HOP, CRAWL, BELLY_UP, IDLE, TURN, STRETCH, CATCH }

@export var animation: Anim = Anim.HOP:
	set(v):
		if animation == v:
			return
		var from: Dictionary = _forced_from if _forced_from != null else (_display_pose() if is_inside_tree() else {})
		animation = v
		_turn_once = false
		_restart(from)
## Used by the TURN animation: 90 = quarter turn right, -90 = left, 180 = turn around.
## In a game call turn(degrees) instead; that also rotates the node when it's done.
@export_range(-180.0, 180.0, 1.0) var turn_degrees := 90.0:
	set(v): turn_degrees = v; queue_redraw()
@export var playing := true
@export_range(0.0, 3.0, 0.05) var speed_scale := 1.0
## Seconds to blend the legs when switching between hop, crawl, idle and turn.
@export_range(0.0, 0.5, 0.01) var blend_time := 0.15
## Keep the frog's body centred on the node (planted feet slide back like on a
## treadmill). Turn off to let the frog travel forward on its own, in node space.
## For gameplay keep this on and move the node by `travel_delta` each frame.
@export var in_place := true:
	set(v): in_place = v; queue_redraw()
@export var show_shadow := true:
	set(v): show_shadow = v; queue_redraw()
## Animate in the editor too (handy while picking colours).
@export var preview_in_editor := true
@export var palette: FrogPalette:
	set(v):
		if palette and palette.changed.is_connected(queue_redraw):
			palette.changed.disconnect(queue_redraw)
		palette = v
		if palette and not palette.changed.is_connected(queue_redraw):
			palette.changed.connect(queue_redraw)
		queue_redraw()

## Seconds into the current animation.
var time := 0.0
## How far the frog moved forward during the last frame (rig units).
var travel_delta := 0.0

var _last_cycle := 0
var _last_travel := 0.0
var _base := Transform2D.IDENTITY
var _turn_once := false
var _turn_then: Anim = Anim.IDLE
var _blend_from: Dictionary = {}
var _blend_left := 0.0
var _forced_from = null

const RAD := PI / 180.0
const IDLE_DURATION := 4.0
const STRETCH_DURATION := 4.2
const CATCH_DURATION := 4.8


func _init() -> void:
	if palette == null:
		palette = FrogPalette.new()


## Turn in place by `degrees` (positive = right, negative = left, 180 = around),
## then rotate the node to the new heading and switch to `then`.
func turn(degrees: float, then: Anim = Anim.IDLE) -> void:
	var from: Dictionary = _display_pose() if is_inside_tree() else {}
	turn_degrees = clampf(degrees, -180.0, 180.0)
	if animation != Anim.TURN:
		animation = Anim.TURN
	else:
		_restart(from)
	_turn_once = true
	_turn_then = then if then != Anim.TURN else Anim.IDLE


## True while a turn started with turn() is playing.
func is_turning() -> bool:
	return animation == Anim.TURN and _turn_once


func _restart(from: Dictionary) -> void:
	time = 0.0
	_last_cycle = 0
	_last_travel = 0.0
	travel_delta = 0.0
	if blend_time > 0.0 and from.has("legs") and animation != Anim.BELLY_UP:
		_blend_from = from
		_blend_left = blend_time
	else:
		_blend_from = {}
		_blend_left = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	if not playing:
		travel_delta = 0.0
		# finish any blend even while paused, so the new pose shows up
		if _blend_left > 0.0:
			_blend_left = maxf(0.0, _blend_left - delta)
			queue_redraw()
		return
	var step := delta * speed_scale
	time += step
	_blend_left = maxf(0.0, _blend_left - step)
	if is_turning() and time >= duration():
		_finish_turn()
		return
	var cycle := int(floor(time / duration()))
	if cycle != _last_cycle:
		_last_cycle = cycle
		cycle_finished.emit(animation)
	var travel := get_travel()
	travel_delta = travel - _last_travel
	_last_travel = travel
	queue_redraw()


func _finish_turn() -> void:
	var degrees := turn_degrees
	_turn_once = false
	if not Engine.is_editor_hint():
		rotation = wrapf(rotation + deg_to_rad(degrees), -PI, PI)
	# The turn ends in the sitting pose rotated by `degrees`. Now that the node
	# carries that rotation, continue from the unrotated sitting pose.
	_forced_from = sample_idle(0.0)
	animation = _turn_then
	_forced_from = null
	turn_finished.emit(degrees)


## Length of one loop in seconds.
func duration() -> float:
	match animation:
		Anim.HOP: return HOP_DURATION
		Anim.CRAWL: return CRAWL_DURATION
		Anim.IDLE: return IDLE_DURATION
		Anim.STRETCH: return STRETCH_DURATION
		Anim.CATCH: return CATCH_DURATION
		Anim.TURN: return turn_duration(turn_degrees)
	return BACK_DURATION


## Total forward distance since the animation started (rig units).
func get_travel(at_time: float = NAN) -> float:
	if is_nan(at_time):
		at_time = time
	match animation:
		Anim.HOP:
			var cycle := floorf(at_time / HOP_DURATION)
			var tick: float = _hop_tick(at_time)
			return cycle * HOP_STRIDE + _hop_body.at(tick)[0]
		Anim.CRAWL:
			return at_time / CRAWL_DURATION * CRAWL_STRIDE
	return 0.0


## The pose at a given time (world-space joints, frog moving toward -Y).
func sample(at_time: float = NAN) -> Dictionary:
	if is_nan(at_time):
		at_time = time
	match animation:
		Anim.HOP: return sample_hop(at_time)
		Anim.CRAWL: return sample_crawl(at_time)
		Anim.IDLE, Anim.STRETCH, Anim.CATCH: return sample_idle_loop(animation, at_time)
		Anim.TURN:
			var d := turn_duration(turn_degrees)
			var t := minf(at_time, d) if _turn_once else fposmod(at_time, d)
			return sample_turn(t, turn_degrees)
	return sample_back(at_time)


## The pose as drawn: in node space (in_place applied) and blended after a switch.
func _display_pose() -> Dictionary:
	var p := sample()
	if animation == Anim.BELLY_UP:
		return p
	if in_place:
		var travel := get_travel()
		if travel != 0.0:
			p = _shift(p, Vector2(0.0, travel))
	if _blend_left > 0.0 and blend_time > 0.0 and _blend_from.has("legs"):
		var w := smoothstep(0.0, 1.0, 1.0 - _blend_left / blend_time)
		p = _lerp_pose(_blend_from, p, w)
	return p


func _draw() -> void:
	if palette == null:
		return
	_base = Transform2D.IDENTITY
	var p := _display_pose()
	var yaw: float = p.get("yaw", 0.0)
	if show_shadow and p.has("shadow"):
		var sh: Dictionary = p.shadow
		_set_xf(Transform2D.IDENTITY)
		_ellipse(sh.center, sh.rx, sh.ry, _shadow_color(sh.opacity), sh.angle)
	if animation == Anim.BELLY_UP:
		_draw_back(p)
	else:
		# the snout covers the tongue and the mosquito, so draw them first
		_set_xf(Transform2D.IDENTITY)
		if p.has("tongue"):
			_draw_tongue(p.tongue)
		if p.has("insect"):
			_draw_mosquito(p.insect)
		_draw_topside(p, yaw)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _shadow_color(opacity: float) -> Color:
	var c := palette.shadow
	return Color(c.r, c.g, c.b, clampf(c.a * opacity, 0.0, 1.0))


static func _shift(p: Dictionary, off: Vector2) -> Dictionary:
	var q := p.duplicate()
	q.body = p.body + off
	q.ground_y = float(p.get("ground_y", 0.0)) + off.y
	if p.has("shadow"):
		var sh: Dictionary = p.shadow.duplicate()
		sh.center = sh.center + off
		q.shadow = sh
	if p.has("tongue"):
		q.tongue = {mouth = p.tongue.mouth + off, tip = p.tongue.tip + off, extension = p.tongue.extension}
	if p.has("insect"):
		var ins: Dictionary = p.insect.duplicate()
		ins.pos = ins.pos + off
		q.insect = ins
	var legs: Array = []
	for l: Dictionary in p.legs:
		var m := l.duplicate()
		for key in ["root", "joint", "wrist", "foot"]:
			m[key] = l[key] + off
		var d := PackedVector2Array()
		for v in l.digits:
			d.append(v + off)
		m.digits = d
		legs.append(m)
	q.legs = legs
	return q


static func _lerp_pose(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var q := b.duplicate()
	q.body = (a.body as Vector2).lerp(b.body, w)
	for key in ["width", "length", "lift", "ground_y"]:
		q[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), w)
	q.yaw = lerp_angle(float(a.get("yaw", 0.0)), float(b.get("yaw", 0.0)), w)
	if a.has("shadow") and b.has("shadow"):
		var sa: Dictionary = a.shadow
		var sb: Dictionary = b.shadow
		q.shadow = {center = (sa.center as Vector2).lerp(sb.center, w), rx = lerpf(sa.rx, sb.rx, w),
				ry = lerpf(sa.ry, sb.ry, w), opacity = lerpf(sa.opacity, sb.opacity, w),
				angle = lerp_angle(sa.angle, sb.angle, w)}
	var legs: Array = []
	for i in 4:
		var la: Dictionary = a.legs[i]
		var lb: Dictionary = b.legs[i]
		var hind: bool = lb.hind
		var mirror: float = lb.mirror
		var root: Vector2 = (la.root as Vector2).lerp(lb.root, w)
		var wrist: Vector2 = (la.wrist as Vector2).lerp(lb.wrist, w)
		var digits := PackedVector2Array()
		for k in 3:
			digits.append((la.digits[k] as Vector2).lerp(lb.digits[k], w))
		legs.append({hind = hind, mirror = mirror, root = root, wrist = wrist,
				foot = (la.foot as Vector2).lerp(lb.foot, w), digits = digits,
				joint = _solve_joint(root, wrist, 29.0 if hind else 21.0, 30.0 if hind else 20.0,
						mirror * (1.0 if hind else -1.0))})
	q.legs = legs
	return q


# =============================================================================
# IDLE + TURN (sitting pose = the hop's resting pose)
# =============================================================================

const TURN_ROUND := 0.42        # seconds for all four feet to take one step
const TURN_SWING := 0.30        # part of a round one foot is in the air
const TURN_BODY_WINDOW := 0.45  # the body follows each step over this part of a round
const TURN_MAX_STEP := 45.0     # degrees per footstep


static func turn_steps(degrees: float) -> int:
	return maxi(1, ceili(absf(degrees) / TURN_MAX_STEP))


## Seconds a turn of `degrees` takes (90: about 0.9 s, 180: about 1.8 s).
static func turn_duration(degrees: float) -> float:
	return (turn_steps(degrees) + 0.2) * TURN_ROUND


static func _smoother(u: float) -> float:
	return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))


## Sitting, breathing and blinking (the IDLE loop).
static func sample_idle(seconds: float) -> Dictionary:
	return sample_idle_loop(Anim.IDLE, seconds)


## Turning on the spot: the feet step around one at a time, the body follows.
static func sample_turn(seconds: float, degrees: float) -> Dictionary:
	var n := turn_steps(degrees)
	var step := degrees * RAD / n
	# start of each foot's step within a round, legs ordered [L hind, R hind, L fore, R fore]
	# the front foot on the turning side leads, then the opposite back foot, ...
	var starts: Array = [.25, .75, .5, 0.0] if degrees >= 0.0 else [.75, .25, 0.0, .5]
	var foot_yaw := PackedFloat64Array()
	var arcs := PackedFloat64Array()
	var body_steps := 0.0
	var clock := seconds / TURN_ROUND
	for i in 4:
		var c: float = clock - float(starts[i])
		var k := floorf(c)
		var done := 0.0
		var arc := 0.0
		var body_done := 0.0
		if c > 0.0:
			if k >= n:
				done = n
				body_done = n
			else:
				var u := minf(1.0, (c - k) / TURN_SWING)
				done = k + _smoother(u)
				if u < 1.0:
					arc = pow(sin(PI * u), 2.0)
				body_done = k + _smoother(minf(1.0, (c - k) / TURN_BODY_WINDOW))
		foot_yaw.append(done * step)
		arcs.append(arc)
		body_steps += body_done
	return _seated_pose(body_steps / 4.0 * step, 1.0, foot_yaw, arcs)


## The hop's resting pose with the body turned by `body_yaw` and each foot
## placed around the body at its own yaw. `arcs` (0..1) swing feet that are stepping out and around.
static func _seated_pose(body_yaw: float, length: float, foot_yaw: PackedFloat64Array,
		arcs: PackedFloat64Array) -> Dictionary:
	var width := 1.0 / sqrt(length)
	var legs: Array = []
	var i := 0
	for hind: bool in [true, false]:
		for mirror: float in [1.0, -1.0]:
			var fy: float = foot_yaw[i]
			var arc: float = arcs[i]
			i += 1
			var angle := (194.0 if hind else 228.0) * RAD
			var foot := Vector2(mirror * (-37.0 if hind else -43.0), 28.0 if hind else -32.0) \
					.rotated(fy) * (1.0 + (0.20 if hind else 0.08) * arc)  # stepping foot swings outward
			var foot_len := 16.0 if hind else 10.0
			var wrist := foot - Vector2(mirror * foot_len * cos(angle), foot_len * sin(angle)).rotated(fy)
			var root := Vector2(-mirror * (13.0 if hind else 20.0) * width,
					(23.0 if hind else -11.0) * length).rotated(body_yaw)
			var joint := _solve_joint(root, wrist, 29.0 if hind else 21.0, 30.0 if hind else 20.0,
					mirror * (1.0 if hind else -1.0))
			var digits := PackedVector2Array()
			for k in 3:
				var spread: float = [-.92, 0.0, .92][k] * (1.0 - .25 * arc)
				var reach := (9.5 if k == 1 else 8.0) * (1.0 - .08 * arc)
				digits.append(foot + Vector2(mirror * reach * cos(angle + spread),
						reach * sin(angle + spread)).rotated(fy))
			legs.append({hind = hind, mirror = mirror, root = root, joint = joint, wrist = wrist,
					foot = foot, digits = digits, planted = arc == 0.0})
	return {body = Vector2.ZERO, width = width, length = length, lift = 0.0, ground_y = 0.0,
			yaw = body_yaw, legs = legs,
			shadow = {center = Vector2(1.0, 4.0).rotated(body_yaw), rx = 25.0, ry = 35.0, opacity = 0.14,
					angle = body_yaw}}


# =============================================================================
# IDLE LOOPS: breathe & blink, toe stretch, catch a mosquito
# =============================================================================

const CATCH_CONTACT := 2.52
const CATCH_SWALLOWED := 2.81
const MOSQUITO_LEGS := Color("364346")
const MOSQUITO_BODY := Color("3a4546")
const MOSQUITO_WING := Color("e5f2e3")
const MOSQUITO_WING_EDGE := Color("769a94")

static var _rest_legs: Array = []
static var _blink_track: Track
static var _stretch_track: Track
static var _arrival_track: Track
static var _aim_track: Track
static var _reach_track: Track
static var _gulp_track: Track
static var _captured := PackedFloat64Array()


static func _build_idles() -> void:
	if _blink_track != null:
		return
	_rest_legs = sample_hop(0.0).legs
	_blink_track = Track.new([[0, 0], [.063, 1], [.11, 1], [.24, 0]])
	# seconds, weight on the right forefoot, left-hand reach, toe spread
	_stretch_track = Track.new([
		[0, 0, 0, 0], [.55, 0, 0, 0], [.98, 1, 0, -.12], [1.45, 1, .83, -.43],
		[1.8, .95, 1, .5], [2.05, .93, .99, .55], [2.42, .84, .9, -.1],
		[2.9, .52, .21, -.39], [3.15, .32, 0, 0], [3.58, 0, 0, 0], [4.2, 0, 0, 0],
	])
	# seconds, mosquito x/y, heading in degrees; the last hover is the strike target
	_arrival_track = Track.new([
		[0, 155, -91, -110], [.33, 155, -91, -110], [.72, 97, -83, -74],
		[.99, 73, -97, -37], [1.23, 58, -90, -106], [1.43, 56, -78, -157],
		[1.7, 38, -68, -112], [1.93, 27, -81, -35], [2.17, 32, -88, 34],
		[2.36, 29, -83, -35], [2.52, 28, -84, -71],
	])
	# seconds, body yaw, forward displacement; the haunches stay loaded while aiming
	_aim_track = Track.new([
		[0, 0, 0], [.64, 0, 0], [1.02, .12, .35], [1.4, .315, .8], [1.74, .39, 1.05],
		[2.06, .29, .72], [2.3, .31, -1.4], [2.43, .321, -2.4],
		[2.53, .321, 6.3], [2.59, .319, 5.6], [2.8, .285, 1.3],
		[3.12, .23, -.5], [3.66, .08, .25], [4.18, 0, 0], [4.8, 0, 0],
	])
	_reach_track = Track.new([[0, 0], [2.415, 0], [CATCH_CONTACT, 1], [2.565, 1], [2.67, .68], [CATCH_SWALLOWED, 0]])
	_gulp_track = Track.new([[0, 0], [2.76, 0], [2.92, 1], [3.06, .75], [3.26, 0]])
	_captured = _arrival_track.at(CATCH_CONTACT)


## One of the stationary loops (IDLE, STRETCH or CATCH), built on the hop's resting stance.
static func sample_idle_loop(kind: Anim, seconds: float) -> Dictionary:
	_build_idles()
	var dur := CATCH_DURATION if kind == Anim.CATCH else (STRETCH_DURATION if kind == Anim.STRETCH else IDLE_DURATION)
	var time := seconds - floorf(seconds / dur) * dur
	var phase := time / dur
	var breath := pow((1.0 - cos(TAU * phase * (2.0 if kind == Anim.IDLE else 1.0))) * 0.5, 1.4)
	var weight := 0.0
	var reach := 0.0
	var spread := 0.0
	if kind == Anim.STRETCH:
		var st := _stretch_track.at(time)
		weight = st[0]
		reach = st[1]
		spread = st[2]
	var yaw := -0.12 * reach
	var forward := 0.0
	var gulp := 0.0
	if kind == Anim.CATCH:
		var aim := _aim_track.at(time)
		yaw = aim[0]
		forward = aim[1]
		gulp = _gulp_track.at(time)[0]
	var blink_start := 2.83 if kind == Anim.IDLE else (3.22 if kind == Anim.STRETCH else 2.82)
	var blink: float = _blink_track.at(time - blink_start)[0]
	var swell := breath * (1.0 if kind == Anim.IDLE else 0.36)
	var width := 1.0 + .045 * swell + .032 * gulp
	var length := 1.0 - .016 * swell + .0045 * forward
	var body := Vector2(2.8 * weight + forward * sin(yaw), .65 * swell - forward * cos(yaw))
	var legs: Array = []
	for neutral: Dictionary in _rest_legs:
		var hind: bool = neutral.hind
		var nroot: Vector2 = neutral.root
		var side := signf(nroot.x)
		var root := body + Vector2(nroot.x * width, nroot.y * length).rotated(yaw)
		var foot: Vector2 = neutral.foot
		var wrist: Vector2 = neutral.wrist
		var digits: PackedVector2Array = neutral.digits
		if kind == Anim.STRETCH and not hind and side < 0.0:
			foot = foot + Vector2(-5.0 * reach, -12.0 * reach)
			var angle := (228.0 + 25.0 * reach) * RAD
			wrist = foot - 10.0 * Vector2(cos(angle), sin(angle))
			digits = PackedVector2Array()
			for i in 3:
				var heading: float = angle + [-.92, 0.0, .92][i] * (1.0 + spread)
				var toe_len := (9.5 if i == 1 else 8.0) * (1.0 + .12 * minf(0.0, spread))
				digits.append(foot + toe_len * Vector2(cos(heading), sin(heading)))
		var joint := _solve_joint(root, wrist, 29.0 if hind else 21.0, 30.0 if hind else 20.0,
				-side * (1.0 if hind else -1.0))
		legs.append({hind = hind, mirror = neutral.mirror, root = root, joint = joint, wrist = wrist,
				foot = foot, digits = digits, planted = true})
	var pose := {body = body, width = width, length = length, yaw = yaw, lift = 0.0, ground_y = 0.0,
			legs = legs, blink = blink, throat = swell + 1.7 * gulp,
			shadow = {center = body + Vector2(1.0, 4.0), rx = 25.0 * width, ry = 35.0 * length,
					opacity = 0.14, angle = yaw}}
	if kind == Anim.CATCH:
		var mouth := body + Vector2(0.0, -37.5 * length).rotated(yaw)
		var extension: float = _reach_track.at(time)[0]
		var target := Vector2(_captured[0], _captured[1])
		var tip := mouth + (target - mouth) * extension
		if extension > 0.0:
			pose.tongue = {mouth = mouth, tip = tip, extension = extension}
		if time < CATCH_SWALLOWED:
			var caught := time >= CATCH_CONTACT
			var pos := tip
			var heading: float = _captured[2]
			if not caught:
				var a := _arrival_track.at(time)
				pos = Vector2(a[0], a[1])
				heading = a[2]
			pose.insect = {pos = pos,
					angle = (heading + (65.0 * (1.0 - extension) if caught else 0.0)) * RAD,
					wing = 0.4 * extension if caught else 0.68 + 0.32 * cos(TAU * 13.0 * time),
					size = minf(1.0, extension * 3.0) if caught else 1.0}
	return pose


func _eyelid(center: Vector2, amount: float, color: Color) -> void:
	# the lid slides down over the eye: eye circle clipped to a band from the top
	var eye := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		eye.append(center + Vector2(12.0 * cos(t), 12.0 * sin(t)))
	var top := center.y - 12.0
	var lid := PackedVector2Array([Vector2(center.x - 13.0, top - 1.0), Vector2(center.x + 13.0, top - 1.0),
			Vector2(center.x + 13.0, top + 24.0 * amount), Vector2(center.x - 13.0, top + 24.0 * amount)])
	for part in Geometry2D.intersect_polygons(eye, lid):
		_fill(part, color)


func _draw_tongue(t: Dictionary) -> void:
	var mouth: Vector2 = t.mouth
	var tip: Vector2 = t.tip
	var d := tip - mouth
	var length := d.length()
	if length < 0.1:
		return
	var ux := d / length
	var uy := Vector2(-ux.y, ux.x)
	var bow := 4.0 * sin(PI * float(t.extension))
	var local := PackedVector2Array([Vector2(0, -2.4)])
	local.append_array(_quad(Vector2(0, -2.4), Vector2(.49 * length, bow - .85), Vector2(length, -1.3), 8))
	local.append_array(_quad(Vector2(length, -1.3), Vector2(length + 2.8, 0), Vector2(length, 1.5), 5))
	local.append_array(_quad(Vector2(length, 1.5), Vector2(.49 * length, bow + 1.25), Vector2(0, 2.7), 8))
	var pts := PackedVector2Array()
	for q in local:
		pts.append(mouth + ux * q.x + uy * q.y)
	_fill(pts, palette.tongue)
	var shine := PackedVector2Array()
	for q in _quad(Vector2(0, -.75), Vector2(.54 * length, bow - .5), Vector2(length, -.4), 8, true):
		shine.append(mouth + ux * q.x + uy * q.y)
	_stroke(shine, 0.9, palette.tongue_highlight)


func _draw_mosquito(m: Dictionary) -> void:
	var size: float = m.size
	if size <= 0.01:
		return
	var xf := Transform2D(float(m.angle), Vector2.ONE * size, 0.0, m.pos)
	var wing: float = m.wing
	for side: float in [-1.0, 1.0]:
		_set_xf(xf)
		for leg in [[3.5, -4, 6, -3], [4.5, 1, 7.6, 2], [3.1, 4, 6.2, 7]]:
			_stroke(PackedVector2Array([Vector2.ZERO, Vector2(side * leg[0], leg[1]), Vector2(side * leg[2], leg[3])]),
					0.58, MOSQUITO_LEGS)
		_set_xf(xf.rotated_local(-side * (.34 + .76 * wing)))
		_ellipse(Vector2(0, 2.9), 1.28, 3.6, MOSQUITO_WING)
		var edge := PackedVector2Array()
		for i in 21:
			var t := TAU * i / 20.0
			edge.append(Vector2(1.28 * cos(t), 2.9 + 3.6 * sin(t)))
		draw_polyline(edge, MOSQUITO_WING_EDGE, 0.48, true)
	_set_xf(xf)
	_ellipse(Vector2(0, 1.9), 1.04, 3.35, MOSQUITO_BODY, -.12)
	draw_circle(Vector2(0, -1.65), 1.35, MOSQUITO_BODY, true, -1.0, true)
	_stroke(PackedVector2Array([Vector2(.1, -2.6), Vector2(.5, -5.5)]), 0.58, MOSQUITO_LEGS)
	_set_xf(Transform2D.IDENTITY)


# =============================================================================
# Shared maths
# =============================================================================

## Shape-preserving cubic interpolation (same as the JS `track`).
class Track:
	var xs := PackedFloat64Array()
	var vals: Array = []
	var slopes: Array = []

	func _init(rows: Array) -> void:
		for r in rows:
			xs.append(float(r[0]))
			var v := PackedFloat64Array()
			for j in range(1, r.size()):
				v.append(float(r[j]))
			vals.append(v)
		var n := xs.size()
		for i in n:
			var row: PackedFloat64Array = vals[i]
			var s := PackedFloat64Array()
			for c in row.size():
				if i == 0 or i == n - 1:
					s.append(0.0)
					continue
				var prev_row: PackedFloat64Array = vals[i - 1]
				var next_row: PackedFloat64Array = vals[i + 1]
				var before: float = xs[i] - xs[i - 1]
				var after: float = xs[i + 1] - xs[i]
				var a: float = (row[c] - prev_row[c]) / before
				var b: float = (next_row[c] - row[c]) / after
				if a * b <= 0.0:
					s.append(0.0)
				else:
					s.append(3.0 * (before + after) / ((2.0 * after + before) / a + (after + 2.0 * before) / b))
			slopes.append(s)

	func at(tick: float) -> PackedFloat64Array:
		var i := 0
		while i < xs.size() - 2 and tick > xs[i + 1]:
			i += 1
		var span: float = xs[i + 1] - xs[i]
		var t: float = clampf((tick - xs[i]) / span, 0.0, 1.0)
		var t2 := t * t
		var t3 := t2 * t
		var a: PackedFloat64Array = vals[i]
		var b: PackedFloat64Array = vals[i + 1]
		var sa: PackedFloat64Array = slopes[i]
		var sb: PackedFloat64Array = slopes[i + 1]
		var out := PackedFloat64Array()
		out.resize(a.size())
		for j in a.size():
			out[j] = (2.0 * t3 - 3.0 * t2 + 1.0) * a[j] + (t3 - 2.0 * t2 + t) * span * sa[j] \
					+ (3.0 * t2 - 2.0 * t3) * b[j] + (t3 - t2) * span * sb[j]
		return out


static func _solve_joint(root: Vector2, wrist: Vector2, upper: float, lower: float, bend: float) -> Vector2:
	var d := wrist - root
	var distance := d.length()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var across := bend * sqrt(maxf(0.0, upper * upper - along * along))
	return Vector2(root.x + (along * d.x - across * d.y) / distance,
			root.y + (along * d.y + across * d.x) / distance)


# =============================================================================
# HOP
# =============================================================================

const HOP_DURATION := 1.12
const HOP_STRIDE := 150.0
const HOP_TICKS := 28.0

static var _hop_body: Track
static var _hop_front: Track
static var _hop_front_other: Track
static var _hop_weight: Track
static var _hop_rear: Track
static var _hop_clock: Track


static func _build_hop() -> void:
	if _hop_body != null:
		return
	# tick, forward progress, projected lift, torso length scale
	_hop_body = Track.new([
		[0, 0, 0, 1], [2, 0, 0, 1], [5, -4, 0, .95], [7, -4, 0, .95],
		[9, 12, 1, 1.025], [11, 57, 8, 1.07], [14, 103, 16, 1.035],
		[17, 118, 10, 1.015], [18, 128, 6, 1.025], [19, 140, 2.7, 1.01],
		[20.2, 152.6, .8, .94], [21.1, 153.5, 0, .95], [21.55, 153.3, 0, .95],
		[22.95, 149.8, 0, .97], [24.65, 150.5, 0, 1.008], [26.4, 150, 0, 1], [28, 150, 0, 1],
	])
	var front_keys := [
		[0, -43, -32, 228], [3, -43, -32, 228],
		_air_front(5, -45, 27, 236), _air_front(7, -42, 20, 248),
		_air_front(9, -36, 17, 258), _air_front(11.4, -30, 13, 270),
		_air_front(14, -28, 14, 272), _air_front(15, -29.5, 18, 263),
		_air_front(16.5, -35, 33, 247), _air_front(17.4, -40, 39, 235),
		[18, -43, -182, 228], [28, -43, -182, 228],
	]
	_hop_front = Track.new(front_keys)
	var other: Array = []
	for k in front_keys:
		var row: Array = k.duplicate()
		var t: float = float(row[0])
		row[0] = t + (0.48 if t >= 15.0 and t <= 18.0 else 0.0)
		other.append(row)
	_hop_front_other = Track.new(other)
	_hop_weight = Track.new([[0, 0], [17, 0], [18.35, -1.7], [20.6, -.5], [23.5, 0], [28, 0]])
	_hop_rear = Track.new([
		[0, -37, 28, 194, 194], [7, -37, 28, 194, 194],
		[9, -37, 28, 165, 194], [11, -37, 28, 110, 194],
		_air_rear(11.4, 58.35, 19, 107, 173),
		_air_rear(12, 57.9, 19, 104, 135),
		_air_rear(13.4, 57.4, 16, 103, 108),
		_air_rear(15, 55, 20, 110, 110),
		_air_rear(17, 49, 22, 119, 119),
		_air_rear(18.5, 46, 24, 127, 127), _air_rear(19.35, 37, 28, 154, 154),
		[20.05, -40, -107, 192, 179], [20.6, -38, -117, 222, 190],
		[21.1, -37, -122, 238, 194], [21.55, -37, -122, 223, 194],
		[22.95, -37, -122, 177, 194], [24.65, -37, -122, 200, 194],
		[26.4, -37, -122, 194, 194], [28, -37, -122, 194, 194],
	])
	# playback tick -> pose tick (compress the kick, spread out the recoil)
	_hop_clock = Track.new([
		[0, 0], [1, 2], [4, 5], [5.5, 7], [6.2, 9.4], [7.25, 11.42],
		[10.2, 13.2], [16.7, 16.8], [20.3, 19], [21.5, 20.8],
		[23.3, 22], [27.3, 25], [28, 28],
	])


static func _air_front(tick: float, x: float, forward: float, angle: float) -> Array:
	var b := _hop_body.at(tick)
	return [tick, x, -b[0] - b[1] - forward, angle]


static func _air_rear(tick: float, reach: float, outward: float, ankle_angle: float, fan_angle: float) -> Array:
	var b := _hop_body.at(tick)
	var hip_x := -13.0 / sqrt(b[2])
	var hip_y := -b[0] - b[1] + 23.0 * b[2]
	var a := ankle_angle * RAD
	return [tick, hip_x - reach * sin(outward * RAD) + 16.0 * cos(a),
			hip_y + reach * cos(outward * RAD) + 16.0 * sin(a), ankle_angle, fan_angle]


static func _hop_tick(seconds: float) -> float:
	_build_hop()
	var cycle := floorf(seconds / HOP_DURATION)
	var playback := (seconds / HOP_DURATION - cycle) * HOP_TICKS
	return _hop_clock.at(playback)[0]


static func sample_hop(seconds: float) -> Dictionary:
	_build_hop()
	var cycle := floorf(seconds / HOP_DURATION)
	var tick := _hop_tick(seconds)
	var offset := -cycle * HOP_STRIDE
	var b := _hop_body.at(tick)
	var progress: float = b[0]
	var lift: float = b[1]
	var length: float = b[2]
	var ground_y := offset - progress
	var body := Vector2(_hop_weight.at(tick)[0], ground_y - lift)
	var width := 1.0 / sqrt(length)
	var legs: Array = []
	for hind: bool in [true, false]:
		for mirror: float in [1.0, -1.0]:
			var motion: Track = _hop_rear if hind else (_hop_front if mirror == 1.0 else _hop_front_other)
			var m := motion.at(tick)
			var angle: float = m[2]
			var fan: float = m[3] if m.size() > 3 else angle
			var foot := Vector2(mirror * m[0], offset + m[1])
			var a := angle * RAD
			var foot_len := 16.0 if hind else 10.0
			var wrist := Vector2(foot.x - mirror * foot_len * cos(a), foot.y - foot_len * sin(a))
			var root := Vector2(body.x - mirror * (13.0 if hind else 20.0) * width,
					body.y + (23.0 if hind else -11.0) * length)
			var joint := _solve_joint(root, wrist, 29.0 if hind else 21.0, 30.0 if hind else 20.0,
					mirror * (1.0 if hind else -1.0))
			var digits := PackedVector2Array()
			for i in 3:
				var spread: float = [-.92, 0.0, .92][i]
				var reach := 9.5 if i == 1 else 8.0
				digits.append(Vector2(foot.x + mirror * reach * cos(fan * RAD + spread),
						foot.y + reach * sin(fan * RAD + spread)))
			legs.append({hind = hind, mirror = mirror, root = root, joint = joint, wrist = wrist, foot = foot, digits = digits})
	return {cycle = cycle, tick = tick, ground_y = ground_y, body = body, width = width,
			length = length, lift = lift, yaw = 0.0, legs = legs,
			shadow = {center = Vector2(0.0, ground_y + 8.0), rx = 23.0 - lift * 0.24, ry = 13.0 - lift * 0.12,
					opacity = 0.21 - lift * 0.004, angle = 0.0}}


# =============================================================================
# CRAWL
# =============================================================================

const CRAWL_DURATION := 1.60
const CRAWL_STRIDE := 36.0
const CRAWL_SWING := 0.235
# four-beat walk: each toe fan touches down before the next foot lifts
const CRAWL_FEET := [
	{hind = true, mirror = 1.0, start = .75},
	{hind = true, mirror = -1.0, start = .25},
	{hind = false, mirror = 1.0, start = 0.0},
	{hind = false, mirror = -1.0, start = .50},
]


static func sample_crawl(seconds: float) -> Dictionary:
	var cycles := seconds / CRAWL_DURATION
	var phase := cycles - floorf(cycles)
	var angle := phase * TAU
	var ground_y := -cycles * CRAWL_STRIDE
	var body := Vector2(1.8 * cos(angle), ground_y + .58 * sin(2.0 * angle))
	var yaw := .065 * sin(angle - .3)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var width := 1.025
	var length := .975
	var legs: Array = []
	for f in CRAWL_FEET:
		var hind: bool = f.hind
		var mirror: float = f.mirror
		var start: float = f.start
		var clock := cycles - start
		var step := floorf(clock)
		var foot_phase := clock - step
		var u := minf(1.0, foot_phase / CRAWL_SWING)
		var reach := u * u * u * (10.0 + u * (-15.0 + 6.0 * u))
		var arc := 0.0 if u == 1.0 else pow(sin(PI * u), 2.0)
		var stance_len := CRAWL_STRIDE * (1.0 - CRAWL_SWING)
		var back_y := (36.0 if hind else -25.0) + stance_len / 2.0
		var foot := Vector2(mirror * ((-43.0 if hind else -41.0) + (5.0 if hind else -3.0) * arc),
				back_y - (step + start + reach) * CRAWL_STRIDE)
		var heading := ((192.0 if hind else 222.0) + (-21.0 if hind else 12.0) * arc) * RAD
		var foot_len := 16.0 if hind else 10.0
		var wrist := Vector2(foot.x - mirror * foot_len * cos(heading), foot.y - foot_len * sin(heading))
		var rx := -mirror * (13.0 if hind else 20.0) * width
		var ry := (23.0 if hind else -11.0) * length
		var root := Vector2(body.x + cs * rx - sn * ry, body.y + sn * rx + cs * ry)
		var joint := _solve_joint(root, wrist, 29.0 if hind else 21.0, 30.0 if hind else 20.0,
				mirror * (1.0 if hind else -1.0))
		var digits := PackedVector2Array()
		for i in 3:
			var spread: float = [-.92, 0.0, .92][i]
			var a := heading + spread * (1.0 - .25 * arc)
			var toe_len := (9.5 if i == 1 else 8.0) * (1.0 - .08 * arc)
			digits.append(Vector2(foot.x + mirror * toe_len * cos(a), foot.y + toe_len * sin(a)))
		legs.append({hind = hind, mirror = mirror, root = root, joint = joint, wrist = wrist, foot = foot, digits = digits,
				planted = foot_phase >= CRAWL_SWING})
	return {phase = phase, ground_y = ground_y, body = body, width = width, length = length,
			yaw = yaw, lift = 0.0, legs = legs,
			shadow = {center = body + Vector2(1.0, 3.0), rx = 25.0, ry = 36.0, opacity = 0.12, angle = yaw}}


# =============================================================================
# Drawing: hop + crawl (top side)
# =============================================================================

const TORSO_CURVES := [
	# start point, then cubic segments (c1, c2, end) of the torso outline
	Vector2(301.5, 115),
	[Vector2(331, 115), Vector2(350, 151), Vector2(363, 187)],
	[Vector2(381, 237), Vector2(389, 299), Vector2(380, 349)],
	[Vector2(375, 379), Vector2(359, 404), Vector2(337, 418)],
	[Vector2(315, 434), Vector2(288, 434), Vector2(266, 418)],
	[Vector2(244, 404), Vector2(228, 379), Vector2(223, 351)],
	[Vector2(213, 303), Vector2(221, 239), Vector2(239, 186)],
	[Vector2(251, 149), Vector2(273, 115), Vector2(301.5, 115)],
]
static var _torso_poly: PackedVector2Array


func _draw_topside(p: Dictionary, yaw: float) -> void:
	var pal := palette
	_set_xf(Transform2D.IDENTITY)
	for leg in p.legs:
		var hind: bool = leg.hind
		for toe in leg.digits:
			_round_line(leg.foot, toe, 2.4, pal.feet)
			draw_circle(toe, 2.45, pal.feet, true, -1.0, true)
		_segment(leg.wrist, leg.foot, 2.2, 3.8, 1.8, pal.feet)
		_segment(leg.joint, leg.wrist, 2.4, 4.5 if hind else 2.9, 2.25, pal.hind_shin if hind else pal.front_lower)
		_segment(leg.root, leg.joint, 5.0 if hind else 3.3, 10.3 if hind else 4.8,
				4.2 if hind else 2.5, pal.skin if hind else pal.front_upper)
	var body_xf := Transform2D(0.0, p.body).rotated_local(yaw)
	var throat: float = p.get("throat", 0.0)
	if throat > 0.0:
		# the throat peeks out beside the jaw during a breath or a swallow
		_set_xf(body_xf)
		_ellipse(Vector2(0.0, -23.0), 15.0 + 4.5 * throat, 10.0 + 0.8 * throat, pal.throat)
	var xf := body_xf.scaled_local(Vector2(58.0 * p.width / 164.0, 78.0 * p.length / 314.0)) \
			.translated_local(Vector2(-301.5, -272.0))
	_set_xf(xf)
	var blink: float = p.get("blink", 0.0)
	for x: float in [254.0, 349.0]:
		draw_circle(Vector2(x, 151.0), 12.0, pal.eyes, true, -1.0, true)
		if blink > 0.0:
			_eyelid(Vector2(x, 151.0), blink, pal.eyelids)
	if _torso_poly.is_empty():
		_torso_poly = _path_from_cubics(TORSO_CURVES, 12)
	_fill(_torso_poly, pal.skin)
	_stroke(_quad(Vector2(224, 352), Vector2(234, 389), Vector2(269, 408), 10, true), 2.6, pal.skin_lines)
	_stroke(_quad(Vector2(379, 352), Vector2(369, 389), Vector2(334, 408), 10, true), 2.6, pal.skin_lines)


## Tapered limb segment with a rounded tip, from a to b.
func _segment(a: Vector2, b: Vector2, base: float, thickness: float, tip: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var ux := d / length
	var uy := Vector2(-ux.y, ux.x)
	var local := PackedVector2Array([Vector2(0, -base)])
	local.append_array(_cubic(Vector2(0, -base), Vector2(.2 * length, -thickness),
			Vector2(.74 * length, -thickness), Vector2(length, -tip), 10))
	local.append_array(_quad(Vector2(length, -tip), Vector2(1.12 * length, 0), Vector2(length, tip), 6))
	local.append_array(_cubic(Vector2(length, tip), Vector2(.74 * length, thickness),
			Vector2(.2 * length, thickness), Vector2(0, base), 10))
	var pts := PackedVector2Array()
	for q in local:
		pts.append(a + ux * q.x + uy * q.y)
	_fill(pts, color)


# =============================================================================
# BELLY UP
# =============================================================================

const BACK_DURATION := 3.20
const BACK_MAX_ROLL := 45.0
# fraction, roll, yaw, left arm, right arm, left leg, right leg
const BACK_KEYS := [
	[0.0, -4, -2, .27, .49, .25, .42],
	[.08, -7, -3, .39, .25, .39, .22],
	[.17, 11, 1, .70, .27, .14, .74],
	[.26, -17, -4, .28, .74, .79, .12],
	[.35, 7, 2, .77, .32, .20, .68],
	[.44, -14, -5, .21, .86, .72, .20],
	[.51, -19, -6, .17, .88, .80, .15],
	[.60, 24, 4, .85, .28, .19, .90],
	[.68, 42, 9, .98, .14, .12, .97],
	[.73, 45, 10, .88, .31, .26, .89],
	[.79, 36, 7, .63, .86, .54, .65],
	[.86, -9, -3, .26, .67, .86, .36],
	[.92, 4, 0, .36, .37, .32, .52],
	[1.0, -4, -2, .27, .49, .25, .42],
]
static var _back_tangents: Array = []


static func _build_back() -> void:
	if not _back_tangents.is_empty():
		return
	var last := BACK_KEYS.size() - 1
	for i in BACK_KEYS.size():
		var k := 0 if i == last else i
		var key: Array = BACK_KEYS[k]
		var prev: Array
		if k == 0:
			prev = BACK_KEYS[last - 1].duplicate()
			prev[0] = float(prev[0]) - 1.0
		else:
			prev = BACK_KEYS[k - 1]
		var next: Array = BACK_KEYS[k + 1]
		var t0: float = key[0]
		var dt_prev: float = t0 - float(prev[0])
		var dt_next: float = float(next[0]) - t0
		var tan := PackedFloat64Array()
		for j in range(1, key.size()):
			var v: float = key[j]
			tan.append(((v - float(prev[j])) / dt_prev * dt_next + (float(next[j]) - v) / dt_next * dt_prev) \
					/ (dt_prev + dt_next))
		_back_tangents.append(tan)


static func sample_back(seconds: float) -> Dictionary:
	_build_back()
	var phase := fposmod(seconds / BACK_DURATION, 1.0)
	var i := 0
	while i < BACK_KEYS.size() - 2 and float(BACK_KEYS[i + 1][0]) < phase:
		i += 1
	var a: Array = BACK_KEYS[i]
	var b: Array = BACK_KEYS[i + 1]
	var span: float = float(b[0]) - float(a[0])
	var u: float = (phase - float(a[0])) / span
	var u2 := u * u
	var u3 := u2 * u
	var ta: PackedFloat64Array = _back_tangents[i]
	var tb: PackedFloat64Array = _back_tangents[i + 1]
	var v := PackedFloat64Array()
	for j in range(1, a.size()):
		v.append((2 * u3 - 3 * u2 + 1) * float(a[j]) + (u3 - 2 * u2 + u) * span * ta[j - 1] \
				+ (3 * u2 - 2 * u3) * float(b[j]) + (u3 - u2) * span * tb[j - 1])
	var reach := PackedFloat64Array()
	for j in range(2, 6):
		reach.append(clampf(v[j], 0.0, 1.0))
	var roll := clampf(v[0], -BACK_MAX_ROLL, BACK_MAX_ROLL) * RAD
	var sr := sin(roll)
	return {roll = roll, yaw = v[1] * RAD, reach = reach, body = Vector2.ZERO, lift = 0.0,
			shadow = {center = Vector2(3.0 * sr, 5.0), rx = 25.0 - 6.0 * absf(sr), ry = 35.0, opacity = 0.14,
					angle = v[1] * RAD}}


static func _chain_end(start: Vector3, side: float, length: float, angle: float, elevation: float) -> Vector3:
	var a := angle * RAD
	var e := elevation * RAD
	var distance := length * cos(e)
	return Vector3(start.x + side * distance * cos(a), start.y + distance * sin(a), start.z + length * sin(e))


const BACK_SKIN_CURVES := [
	Vector2(0, -40),
	[Vector2(16, -40), Vector2(27, -18), Vector2(28, 5)],
	[Vector2(31, 31), Vector2(13, 41), Vector2(0, 41)],
	[Vector2(-15, 41), Vector2(-31, 29), Vector2(-28, 5)],
	[Vector2(-26, -17), Vector2(-16, -40), Vector2(0, -40)],
]
const BELLY_CURVES := [
	Vector2(0, -35),
	[Vector2(15, -35), Vector2(24, -16), Vector2(24, 7)],
	[Vector2(24, 28), Vector2(12, 36), Vector2(0, 36)],
	[Vector2(-13, 36), Vector2(-25, 25), Vector2(-24, 6)],
	[Vector2(-23, -15), Vector2(-15, -35), Vector2(0, -35)],
]
static var _back_skin_poly: PackedVector2Array
static var _belly_poly: PackedVector2Array


func _draw_back(p: Dictionary) -> void:
	var pal := palette
	var roll: float = p.roll
	var yaw: float = p.yaw
	var reach: PackedFloat64Array = p.reach
	var c := cos(roll)
	var s := sin(roll)
	var spin := Transform2D(yaw, Vector2.ZERO)
	# shift the centre toward the hip as it takes the frog's weight
	var rock_x := 7.0 * s
	var project := func(q: Vector3) -> Vector3:
		var depth := -q.x * s + q.z * c
		return Vector3(rock_x + q.x * c + q.z * s, q.y - .22 * depth, depth)
	var belly_z := 10.0
	var pieces: Array = []
	for n in 4:
		var hind := n >= 2
		var side := 1.0 if n % 2 == 1 else -1.0
		var k: float = reach[n]
		var root := Vector3(side * (16.0 if hind else 21.0), 20.0 if hind else -12.0, 3.0)
		var joint := _chain_end(root, side, 25, -45 + 94 * k, 12 + 26 * (1 - k)) if hind \
				else _chain_end(root, side, 18, 35 - 54 * k, 14 + 31 * (1 - k))
		var wrist := _chain_end(joint, side, 25, 130 - 80 * k, 32 - 39 * k) if hind \
				else _chain_end(joint, side, 17, -142 + 92 * k, 48 - 55 * k)
		var tip := _chain_end(wrist, side, 12.0 if hind else 8.0,
				(29 + 25 * k) if hind else (-115 + 68 * k), 10 + 17 * (1 - k))
		var pa: Vector3 = project.call(root)
		var pb: Vector3 = project.call(joint)
		var pw: Vector3 = project.call(wrist)
		var pt: Vector3 = project.call(tip)
		var a2 := Vector2(pa.x, pa.y)
		var b2 := Vector2(pb.x, pb.y)
		var w2 := Vector2(pw.x, pw.y)
		var t2 := Vector2(pt.x, pt.y)
		var finger_ends := PackedVector2Array()
		for spread: float in [-40.0, 0.0, 40.0]:
			var finger := _chain_end(tip, side, 9.0 if spread == 0.0 else 7.5,
					((24 + 30 * k) if hind else (-115 + 68 * k)) + spread, 5 + 16 * (1 - k))
			var e: Vector3 = project.call(finger)
			finger_ends.append(Vector2(e.x, e.y))
		var paint_upper := func() -> void:
			_set_xf(spin)
			_tapered(a2, b2, 4.0 if hind else 3.0, 9.0 if hind else 5.0, 4.0 if hind else 3.0, pal.limb_upper)
		var paint_middle := func() -> void:
			_set_xf(spin)
			_tapered(b2, w2, 3.0, 5.0 if hind else 3.5, 2.5, pal.limb_middle)
		var paint_lower := func() -> void:
			_set_xf(spin)
			_tapered(w2, t2, 2.2, 3.5, 2.0, pal.limb_lower)
			for end in finger_ends:
				_round_line(t2, end, 2.0, pal.limb_lower)
				_ellipse(end, 2.45, 2.15, pal.toe_tips)
		pieces.append({depth = (pa.z + pb.z) * .5 - 4.0, paint = paint_upper})
		pieces.append({depth = (pb.z + pw.z) * .5, paint = paint_middle})
		pieces.append({depth = (pw.z + pt.z) * .5 + 1.0, paint = paint_lower})
	var torso: Vector3 = project.call(Vector3(0, 0, belly_z))
	var paint_torso := func() -> void:
		# the width narrows and the far flank rolls into view
		var visible_width := .25 + .75 * c
		var xf := spin * Transform2D(Vector2(visible_width, .22 * s), Vector2(0, 1), Vector2(torso.x, torso.y))
		_set_xf(xf)
		for sd: float in [-1.0, 1.0]:
			_ellipse(Vector2(sd * 17.0, -29.0), 3.8, 4.5, pal.belly_eyes)
		if _back_skin_poly.is_empty():
			_back_skin_poly = _path_from_cubics(BACK_SKIN_CURVES, 12)
			_belly_poly = _path_from_cubics(BELLY_CURVES, 12)
		_fill(_back_skin_poly, pal.back_skin)
		_set_xf(xf.translated_local(Vector2(3.8 * s, 0)))
		_fill(_belly_poly, pal.belly)
		_stroke(_quad(Vector2(-12, -22), Vector2(0, -17), Vector2(12, -22), 8, true), 1.25, pal.belly_lines)
		for spot: Array in [[-17, 10, 1.8], [-14, 16, 1.1], [16, 13, 1.5], [13, 20, 1.05]]:
			_ellipse(Vector2(spot[0], spot[1]), spot[2], float(spot[2]) * .85, pal.belly_spots)
	pieces.append({depth = belly_z * c - 2.0, paint = paint_torso})
	pieces.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.depth < y.depth)
	for piece in pieces:
		piece.paint.call()


## Tapered limb used by the belly-up pose (rounded at both ends).
func _tapered(a: Vector2, b: Vector2, root: float, belly: float, end: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var ux := d / length
	var uy := Vector2(-ux.y, ux.x)
	var local := PackedVector2Array([Vector2(0, -root)])
	local.append_array(_cubic(Vector2(0, -root), Vector2(length * .20, -belly), Vector2(length * .78, -belly),
			Vector2(length, -end), 10))
	local.append_array(_quad(Vector2(length, -end), Vector2(length + end, 0), Vector2(length, end), 6))
	local.append_array(_cubic(Vector2(length, end), Vector2(length * .72, belly), Vector2(length * .19, belly),
			Vector2(0, root), 10))
	var back_cap := _quad(Vector2(0, root), Vector2(-root, 0), Vector2(0, -root), 6)
	back_cap.remove_at(back_cap.size() - 1)  # last point repeats the first
	local.append_array(back_cap)
	var pts := PackedVector2Array()
	for q in local:
		pts.append(a + ux * q.x + uy * q.y)
	_fill(pts, color)


# =============================================================================
# Drawing helpers
# =============================================================================

func _set_xf(xf: Transform2D) -> void:
	draw_set_transform_matrix(_base * xf)


func _fill(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		pts = Geometry2D.convex_hull(pts)
		if pts.size() < 3:
			return
	draw_colored_polygon(pts, color)


func _round_line(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a, b, color, width, true)
	draw_circle(a, width * 0.5, color, true, -1.0, true)
	draw_circle(b, width * 0.5, color, true, -1.0, true)


func _stroke(pts: PackedVector2Array, width: float, color: Color) -> void:
	draw_polyline(pts, color, width, true)
	draw_circle(pts[0], width * 0.5, color, true, -1.0, true)
	draw_circle(pts[pts.size() - 1], width * 0.5, color, true, -1.0, true)


func _ellipse(center: Vector2, rx: float, ry: float, color: Color, angle: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var t := TAU * i / 28.0
		pts.append(center + Vector2(rx * cos(t), ry * sin(t)).rotated(angle))
	draw_colored_polygon(pts, color)


## Points along a cubic Bézier, excluding the start point.
static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, steps + 1):
		out.append(p0.bezier_interpolate(p1, p2, p3, float(i) / steps))
	return out


## Points along a quadratic Bézier, excluding the start point unless asked.
static func _quad(p0: Vector2, p1: Vector2, p2: Vector2, steps: int, include_start := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0 if include_start else 1, steps + 1):
		var t := float(i) / steps
		out.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return out


static func _path_from_cubics(curves: Array, steps: int) -> PackedVector2Array:
	var start: Vector2 = curves[0]
	var pts := PackedVector2Array([start])
	var cur := start
	for i in range(1, curves.size()):
		var c: Array = curves[i]
		pts.append_array(_cubic(cur, c[0], c[1], c[2], steps))
		cur = c[2]
	if pts[pts.size() - 1].is_equal_approx(pts[0]):
		pts.remove_at(pts.size() - 1)
	return pts
