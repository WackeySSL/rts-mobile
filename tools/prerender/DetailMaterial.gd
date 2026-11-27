class_name DetailMaterial
extends Resource
## One material of a `_detail.tres` model (ADR 0053 section 5): a name the parts refer to and
## what the bake's one shader (`detail.gdshader`) needs to paint it.

## What the shader does with it: a plain body, the team paint (the key colour the recolour finds),
## running gear (mud, no streaks), glass, an emissive lamp, or cloth.
enum Kind { BODY, TEAM, GEAR, GLASS, LAMP, CLOTH }

@export var id: StringName = &""
@export var base: Color = Color(0.2, 0.2, 0.2)
@export_range(0.0, 1.0) var metallic: float = 0.4
@export_range(0.0, 1.0) var roughness: float = 0.5
@export var kind: Kind = Kind.BODY
