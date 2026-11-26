class_name TutorialUnitPickDef
extends Resource
## Which unit a `UNIT` anchor points at (ADR 0048 section 13.2, plan row P593b-1): the side, one
## type (or any mobile one) and how to choose among the candidates. Data only, read-only at
## runtime; `GuideUnitAnchor` resolves it.

## Whose unit: the local player's, or any other owner but the neutral one.
## Append only: the values are stored in `data/tutorial/*.tres`.
enum Whose { OWN, ENEMY }

## `NEAREST_CAMERA`: the candidate closest to the camera's centre; `NEWEST`: the highest unit id,
## the one made last. Append only.
enum Pick { NEAREST_CAMERA, NEWEST }

@export var side: Whose = Whose.OWN
## The unit type id; empty: any unit that is not a building.
@export var type_id: StringName = &""
@export var pick: Pick = Pick.NEAREST_CAMERA
