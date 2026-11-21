@tool
class_name FrogPalette
extends Resource
## All the colours of a FrogRig. Save one as a .tres file to reuse or share a colour scheme.

@export_group("Top side")
## Body, and the thighs of the back legs.
@export var skin := Color("86cfbf"):
	set(v): skin = v; emit_changed()
## The two curved lines along the flanks.
@export var skin_lines := Color("67aaa2"):
	set(v): skin_lines = v; emit_changed()
## Upper front legs.
@export var front_upper := Color("669e99"):
	set(v): front_upper = v; emit_changed()
## Lower front legs.
@export var front_lower := Color("487976"):
	set(v): front_lower = v; emit_changed()
## Lower back legs (shins).
@export var hind_shin := Color("568a88"):
	set(v): hind_shin = v; emit_changed()
## Feet and toes.
@export var feet := Color("385e60"):
	set(v): feet = v; emit_changed()
@export var eyes := Color("24393a"):
	set(v): eyes = v; emit_changed()
## Eyelids when blinking.
@export var eyelids := Color("73b7a7"):
	set(v): eyelids = v; emit_changed()
## Throat pouch, seen beside the jaw when breathing or swallowing.
@export var throat := Color("9dd8bc"):
	set(v): throat = v; emit_changed()
@export var tongue := Color("b35b69"):
	set(v): tongue = v; emit_changed()
@export var tongue_highlight := Color("f19899"):
	set(v): tongue_highlight = v; emit_changed()

@export_group("Belly up")
@export var back_skin := Color("7ab8a9"):
	set(v): back_skin = v; emit_changed()
@export var belly := Color("e2ebc4"):
	set(v): belly = v; emit_changed()
@export var belly_lines := Color("b4cca8"):
	set(v): belly_lines = v; emit_changed()
@export var belly_spots := Color("cbdcb5"):
	set(v): belly_spots = v; emit_changed()
@export var belly_eyes := Color("294844"):
	set(v): belly_eyes = v; emit_changed()
@export var limb_upper := Color("8ecbb7"):
	set(v): limb_upper = v; emit_changed()
@export var limb_middle := Color("6da69b"):
	set(v): limb_middle = v; emit_changed()
@export var limb_lower := Color("537e77"):
	set(v): limb_lower = v; emit_changed()
@export var toe_tips := Color("719786"):
	set(v): toe_tips = v; emit_changed()

@export_group("Shadow")
## Alpha scales how dark the shadow is (1 = original look).
@export var shadow := Color("284e41"):
	set(v): shadow = v; emit_changed()

## Click in the Inspector after changing the skin colours: sets the eyelids, throat
## and the belly-up limb, back and eye colours to matching shades (belly stays as is).
@export_tool_button("Match eyelid, throat and belly-up colours to skin") var match_belly_action := derive_belly_colors


func derive_belly_colors() -> void:
	back_skin = skin.darkened(0.1)
	limb_upper = skin.lerp(Color.WHITE, 0.05)
	limb_middle = front_upper.lerp(hind_shin, 0.5).lightened(0.05)
	limb_lower = hind_shin.darkened(0.08)
	toe_tips = feet.lerp(front_upper, 0.7)
	belly_eyes = eyes
	eyelids = skin.darkened(0.12)
	throat = skin.lerp(Color.WHITE, 0.15)
