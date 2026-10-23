## THE INTRO, ON ITS OWN (for recording a concept with Godot's movie maker, or watching one):
##   godot --path . --write-movie out.png --fixed-fps 60 --resolution 1920x1080 res://scenes/intro/intro_preview.tscn -- --intro B [--backdrop app.png]
## Plays the concept over a backdrop (a screenshot of the app, if given; else a plain app-dark panel) and quits shortly
## after it has faded out.
extends Node

const AFTER := 0.4   # seconds of the "app" after the fade


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var back := TextureRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var bi := args.find("--backdrop")
	if bi >= 0 and bi + 1 < args.size():
		var img := Image.load_from_file(args[bi + 1])
		if img != null:
			back.texture = ImageTexture.create_from_image(img)
	if back.texture == null:
		var panel := ColorRect.new()
		panel.color = IntroArt.BG   # no backdrop: the video ends on the bare dark, the end card alone
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(panel)
	add_child(back)
	var k := KineIntro.make(KineIntro.concept_from(null, args))
	k.finished.connect(func():
		await get_tree().create_timer(AFTER).timeout
		get_tree().quit())
	add_child(k)
