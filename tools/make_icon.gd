extends SceneTree
## Builds the Windows icon from icon.svg: assets/icon/thief_of_london.ico (16 to 256 px,
## PNG-compressed, as Windows Vista and later expect) and a 256 px PNG for store pages.
## Run from the project folder:
##   godot --headless --path . --script res://tools/make_icon.gd

const SIZES: Array[int] = [16, 24, 32, 48, 64, 128, 256]
const OUT_DIR := "res://assets/icon"


func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	if svg == "":
		push_error("icon.svg not found")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var pngs: Array[PackedByteArray] = []
	for s in SIZES:
		var img := Image.new()
		var err := img.load_svg_from_string(svg, float(s) / 128.0)
		if err != OK:
			push_error("couldn't render icon.svg")
			quit(1)
			return
		if img.get_width() != s or img.get_height() != s:
			img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		pngs.append(img.save_png_to_buffer())
		if s == 256:
			img.save_png(OUT_DIR + "/thief_of_london_256.png")
	# ICO: a 6-byte header, a 16-byte directory entry per image, then the PNG data.
	var ico := PackedByteArray()
	ico.resize(6 + 16 * SIZES.size())
	ico.encode_u16(0, 0)
	ico.encode_u16(2, 1)
	ico.encode_u16(4, SIZES.size())
	var offset := ico.size()
	for i in SIZES.size():
		var e := 6 + 16 * i
		var s := SIZES[i]
		ico.encode_u8(e, 0 if s >= 256 else s)
		ico.encode_u8(e + 1, 0 if s >= 256 else s)
		ico.encode_u8(e + 2, 0)
		ico.encode_u8(e + 3, 0)
		ico.encode_u16(e + 4, 1)
		ico.encode_u16(e + 6, 32)
		ico.encode_u32(e + 8, pngs[i].size())
		ico.encode_u32(e + 12, offset)
		offset += pngs[i].size()
	for p in pngs:
		ico.append_array(p)
	var f := FileAccess.open(OUT_DIR + "/thief_of_london.ico", FileAccess.WRITE)
	f.store_buffer(ico)
	f.close()
	print("Wrote %s/thief_of_london.ico (%d bytes, %d sizes)" % [OUT_DIR, ico.size(), SIZES.size()])
	quit()
