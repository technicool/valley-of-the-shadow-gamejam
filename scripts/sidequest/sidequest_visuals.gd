class_name SidequestVisuals
extends RefCounted
## Tiny helper for generating flat-color placeholder textures without needing image assets.

static func make_color_texture(color: Color, size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
