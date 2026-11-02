extends RefCounted
## The economy card's tallest height in dp (plan P119b, ADR 0025 sections 2 and 3). Not a suite.
## It is the card with six kinds of consumer (three rows of chips) and the low-power line, the
## content that has to fit under the pill on the shortest screen, 800 x 304 dp (224 dp of room).
## test_economy_card.gd measures the real card against it (within `SPREAD_DP` below it, so the
## number follows the card) at every size and profile, and test_hud_corners.gd places a card of that
## height with every other part at every screen.

const TALLEST_DP: float = 220.0
## How far below `TALLEST_DP` the real tallest card may measure: the text's px rounding differs
## from screen to screen.
const SPREAD_DP: float = 12.0
