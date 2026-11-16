extends FakeAdBackend
## P405 test double: a fake that counts destroy_banner (which the fake otherwise folds into
## hide_banner). Its own file: an inner class may not extend a script class.

var destroyed: int = 0


func destroy_banner() -> void:
	destroyed += 1
	super()
