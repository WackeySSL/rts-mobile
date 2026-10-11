class_name FeedbackStyle
extends RefCounted
## What the feedback markers share (STYLE.md "Feedback markers"): a stroke is a dark outline pass
## `OUTLINE_DP` wider than the colour pass, and every motion eases out.

const OUTLINE: Color = Color("1C2127")
const FILL: Color = Color(1.0, 1.0, 1.0, 0.15)  ## The anchor and the box.
const STROKE_DP: float = 3.0
const OUTLINE_DP: float = 2.0


static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.0)
