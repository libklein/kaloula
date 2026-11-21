extends Node2D
## The player frog on the tile grid.
## Up: hop one tile forward (hold to keep hopping). Shift + Up: crawl one tile.
## Left/right: turn 90°. Down: turn around. Space: flip onto its back / back up.
## Left alone, it breathes and blinks, and now and then stretches its toes or
## catches a mosquito. Moves only land on cells of `map` that have a tile.

## Tile map the frog moves on. Its tile size sets how far one hop goes.
@export var map: TileMapLayer
## Playback speed of the frog's animations.
@export_range(0.25, 3.0, 0.05) var speed := 1.0
## Crawling is slow; this speeds it up (one tile takes about 6.7 s / crawl_speed).
@export_range(0.5, 5.0, 0.1) var crawl_speed := 2.5
## Seconds of sitting still before a random stretch or mosquito catch (min, max).
@export var fidget_after := Vector2(5.0, 10.0)

@onready var rig: FrogRig = $Rig

enum Move { NONE, HOP, CRAWL }

var _cell := Vector2i.ZERO
var _target := Vector2i.ZERO
var _move := Move.NONE
var _hops_done := 0
var _still := 0.0
var _next_fidget := 0.0


func _ready() -> void:
	if map:
		# one hop of the rig = one tile
		var tile := float(map.tile_set.tile_size.x)
		rig.scale = Vector2.ONE * tile / FrogRig.HOP_STRIDE
		_cell = map.local_to_map(position)
		position = map.map_to_local(_cell)
	rig.speed_scale = speed
	rig.animation = FrogRig.Anim.IDLE
	rig.cycle_finished.connect(_on_cycle_finished)
	_next_fidget = randf_range(fidget_after.x, fidget_after.y)


func _process(delta: float) -> void:
	match _move:
		Move.HOP:
			# follow the rig's own travel so planted feet stay put on the ground
			var travel := rig.get_travel() - _hops_done * FrogRig.HOP_STRIDE
			position = _center(_cell) + _forward() * travel * rig.scale.y
			return
		Move.CRAWL:
			var travel := minf(rig.get_travel(), FrogRig.HOP_STRIDE)
			position = _center(_cell) + _forward() * travel * rig.scale.y
			if travel >= FrogRig.HOP_STRIDE:
				_arrive()
			return
	if rig.is_turning():
		return
	if Input.is_action_just_pressed("ui_accept"):
		_set_idle(FrogRig.Anim.BELLY_UP if rig.animation != FrogRig.Anim.BELLY_UP else FrogRig.Anim.IDLE)
		return
	if rig.animation == FrogRig.Anim.BELLY_UP:
		return  # stuck on its back until Space
	if Input.is_action_pressed("ui_up"):
		_try_move(Move.CRAWL if Input.is_key_pressed(KEY_SHIFT) else Move.HOP)
	elif Input.is_action_pressed("ui_left"):
		rig.turn(-90.0)
	elif Input.is_action_pressed("ui_right"):
		rig.turn(90.0)
	elif Input.is_action_pressed("ui_down"):
		rig.turn(180.0)
	elif rig.animation == FrogRig.Anim.IDLE:
		_still += delta
		if _still >= _next_fidget:
			rig.animation = [FrogRig.Anim.STRETCH, FrogRig.Anim.CATCH].pick_random()


## Grid direction the frog is facing.
func facing() -> Vector2i:
	return Vector2i(_forward().round())


## Grid cell the frog is on (or leaving, mid-move).
func cell() -> Vector2i:
	return _cell


func can_enter(c: Vector2i) -> bool:
	return map == null or map.get_cell_source_id(c) != -1


func _forward() -> Vector2:
	return Vector2.UP.rotated(rig.rotation)


func _try_move(kind: Move) -> void:
	var target := _cell + facing()
	if not can_enter(target):
		return
	_target = target
	_hops_done = 0
	_move = kind
	rig.speed_scale = speed * (crawl_speed if kind == Move.CRAWL else 1.0)
	rig.animation = FrogRig.Anim.HOP if kind == Move.HOP else FrogRig.Anim.CRAWL


func _on_cycle_finished(anim: FrogRig.Anim) -> void:
	match anim:
		FrogRig.Anim.HOP:
			if _move != Move.HOP:
				return
			_cell = _target
			_hops_done += 1
			var next := _cell + facing()
			if Input.is_action_pressed("ui_up") and not Input.is_key_pressed(KEY_SHIFT) and can_enter(next):
				_target = next  # keep hopping without stopping
			else:
				_arrive()
		FrogRig.Anim.STRETCH, FrogRig.Anim.CATCH:
			_set_idle(FrogRig.Anim.IDLE)  # fidgets play once


func _arrive() -> void:
	_cell = _target
	_move = Move.NONE
	position = _center(_cell)
	_set_idle(FrogRig.Anim.IDLE)


func _set_idle(anim: FrogRig.Anim) -> void:
	rig.speed_scale = speed
	rig.animation = anim
	_still = 0.0
	_next_fidget = randf_range(fidget_after.x, fidget_after.y)


func _center(c: Vector2i) -> Vector2:
	return map.map_to_local(c) if map else Vector2(c) * FrogRig.HOP_STRIDE * rig.scale.y
