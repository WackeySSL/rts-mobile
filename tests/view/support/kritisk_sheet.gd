extends IsoSheetDef
## A sheet with the field P163 adds to `IsoSheetDef` (`anim_kritisk`, default false: hide), so the
## suites of P159 can say what the `Anim` does at KRITISK before the generator writes it. A file of
## its own because an inner class may not extend a script. Not a test suite.
## TODO(P163): delete this file once `IsoSheetDef.anim_kritisk` exists (redeclaring it is a parse
## error); `damage_rig.gd` then sets the real field.

var anim_kritisk: bool = false
