extends GuideCardFit
## A `GuideCardFit` that counts the layouts it is asked for (plan row P593b-1b). Not a test suite.
## A file of its own, since an inner class with a script base is not allowed.

var count: int = 0


func fit(
	width: float, max_height: float, dp: float, mirror: bool, settings: GuideSettingsDef
) -> Vector2:
	count += 1
	return super(width, max_height, dp, mirror, settings)
