## RIBBON ICONS (round 9, GATES P5): drawn in code, no image files. Each icon is a few shapes on a 24-unit grid,
## painted WHITE by signed distance (coverage = 0.5 - distance: anti-aliased edges with no supersampling). The theme
## tints them (Button icon_*_color), so a light/dark switch needs no redraw.
class_name Icons

const SIZE := 22

## shape: ["seg", a, b, width] | ["arc", centre, radius, width, from_deg, to_deg] | ["disc", centre, radius]
##        ["ring", centre, radius, width] | ["box", rect(pos, size), width (0 = filled)]
const DRAW := {
	# THE SCENE STRIP: the Scene menu, Fold, and a card's hover tools
	"scene_menu": [["seg", Vector2(4, 7), Vector2(20, 7), 2.2], ["seg", Vector2(4, 12), Vector2(20, 12), 2.2], ["seg", Vector2(4, 17), Vector2(20, 17), 2.2]],
	"fold_down": [["seg", Vector2(5, 9), Vector2(12, 16), 2.4], ["seg", Vector2(19, 9), Vector2(12, 16), 2.4]],
	"card_update": [["seg", Vector2(12, 3), Vector2(12, 14), 2.2], ["seg", Vector2(7, 10), Vector2(12, 15), 2.2], ["seg", Vector2(17, 10), Vector2(12, 15), 2.2], ["box", Rect2(4, 17.5, 16, 3), 1.6]],
	"card_delete": [["seg", Vector2(6, 6), Vector2(18, 18), 2.4], ["seg", Vector2(18, 6), Vector2(6, 18), 2.4]],
	"home": [["seg", Vector2(3, 12), Vector2(12, 4), 2.2], ["seg", Vector2(21, 12), Vector2(12, 4), 2.2], ["box", Rect2(6, 11, 12, 9), 1.8]],
	"open": [["box", Rect2(3, 9, 18, 11), 1.8], ["box", Rect2(3, 5, 8, 4), 1.6]],
	"trash": [["box", Rect2(6.5, 9, 11, 11), 1.8], ["seg", Vector2(4, 6.5), Vector2(20, 6.5), 2.0], ["seg", Vector2(9.5, 4), Vector2(14.5, 4), 2.0], ["seg", Vector2(10.5, 12), Vector2(10.5, 17), 1.4], ["seg", Vector2(13.5, 12), Vector2(13.5, 17), 1.4]],
	"new_scene": [["box", Rect2(5, 3, 14, 18), 1.8], ["seg", Vector2(12, 9), Vector2(12, 16), 2.0], ["seg", Vector2(8.5, 12.5), Vector2(15.5, 12.5), 2.0]],
	"template": [["box", Rect2(3.5, 3.5, 17, 17), 1.6], ["seg", Vector2(3.5, 9.5), Vector2(20.5, 9.5), 1.4], ["seg", Vector2(9.5, 9.5), Vector2(9.5, 20.5), 1.4]],
	"move_l": [["seg", Vector2(15, 5), Vector2(8, 12), 2.4], ["seg", Vector2(8, 12), Vector2(15, 19), 2.4]],
	"move_r": [["seg", Vector2(9, 5), Vector2(16, 12), 2.4], ["seg", Vector2(16, 12), Vector2(9, 19), 2.4]],
	"rename": [["seg", Vector2(5, 19), Vector2(6.5, 14), 2.0], ["seg", Vector2(6.5, 14), Vector2(15, 5.5), 2.6], ["seg", Vector2(15, 5.5), Vector2(18.5, 9), 2.6], ["seg", Vector2(18.5, 9), Vector2(10, 17.5), 2.0], ["seg", Vector2(5, 19), Vector2(10, 17.5), 2.0]],
	# PAGES (docs/PAGES_PLAN.md): the page bar's nine icons
	"page_pose": [["disc", Vector2(12, 4.5), 2.6], ["seg", Vector2(12, 8), Vector2(12, 15), 2.4], ["seg", Vector2(12, 9.5), Vector2(5, 7), 2.0],
		["seg", Vector2(12, 9.5), Vector2(19, 13), 2.0], ["seg", Vector2(12, 15), Vector2(8, 21), 2.0], ["seg", Vector2(12, 15), Vector2(16.5, 21), 2.0]],
	"page_animate": [["box", Rect2(2.5, 14, 19, 6), 1.6], ["seg", Vector2(7, 14), Vector2(7, 20), 1.4], ["seg", Vector2(12, 14), Vector2(12, 20), 1.4],
		["seg", Vector2(17, 14), Vector2(17, 20), 1.4], ["disc", Vector2(5, 7), 1.8], ["disc", Vector2(12, 5), 1.8], ["disc", Vector2(19, 8), 1.8],
		["seg", Vector2(5, 7), Vector2(12, 5), 1.2], ["seg", Vector2(12, 5), Vector2(19, 8), 1.2]],
	"page_stage": [["seg", Vector2(3, 20), Vector2(21, 20), 2.0], ["seg", Vector2(3, 20), Vector2(7, 12), 1.8], ["seg", Vector2(21, 20), Vector2(17, 12), 1.8],
		["seg", Vector2(7, 12), Vector2(17, 12), 1.8], ["seg", Vector2(12, 3), Vector2(12, 9), 1.8], ["disc", Vector2(12, 10), 1.6]],
	"page_check": [["ring", Vector2(12, 12), 9, 1.9], ["seg", Vector2(7.5, 12.5), Vector2(10.8, 16), 2.4], ["seg", Vector2(10.8, 16), Vector2(17, 8.5), 2.4]],
	"page_deliver": [["box", Rect2(3.5, 13, 17, 7), 1.8], ["seg", Vector2(12, 3), Vector2(12, 14), 2.2], ["seg", Vector2(7.5, 9.5), Vector2(12, 14.5), 2.2],
		["seg", Vector2(16.5, 9.5), Vector2(12, 14.5), 2.2]],
	"page_body": [["ring", Vector2(12, 6), 3, 1.8], ["arc", Vector2(12, 17), 7, 1.8, 180, 360], ["seg", Vector2(5, 17), Vector2(5, 21), 1.8], ["seg", Vector2(19, 17), Vector2(19, 21), 1.8]],
	"page_model": [["seg", Vector2(12, 3), Vector2(21, 8), 1.8], ["seg", Vector2(21, 8), Vector2(21, 17), 1.8], ["seg", Vector2(21, 17), Vector2(12, 22), 1.8],
		["seg", Vector2(12, 22), Vector2(3, 17), 1.8], ["seg", Vector2(3, 17), Vector2(3, 8), 1.8], ["seg", Vector2(3, 8), Vector2(12, 3), 1.8],
		["seg", Vector2(12, 12), Vector2(12, 22), 1.4], ["seg", Vector2(12, 12), Vector2(3, 8), 1.4], ["seg", Vector2(12, 12), Vector2(21, 8), 1.4]],
	"page_sculpt": [["disc", Vector2(12, 14), 7], ["arc", Vector2(12, 8), 4, 2, 200, 340], ["seg", Vector2(12, 3), Vector2(12, 6), 2.0]],
	"page_surface": [["box", Rect2(3.5, 3.5, 17, 17), 1.8], ["seg", Vector2(3.5, 12), Vector2(20.5, 12), 1.4], ["seg", Vector2(12, 3.5), Vector2(12, 20.5), 1.4],
		["disc", Vector2(7.7, 7.7), 1.6], ["disc", Vector2(16.3, 16.3), 1.6]],
	"page_build": [["seg", Vector2(3, 11), Vector2(12, 3.5), 1.8], ["seg", Vector2(12, 3.5), Vector2(21, 11), 1.8], ["box", Rect2(5.5, 11, 13, 9.5), 1.8],
		["box", Rect2(10, 14.5, 4, 6), 1.4]],
	# BUILD's ribbon (scripts/build/build_ui.gd): DRAW Room / Wall / Pull, ADD Opening / Floor / Roof / Piece, SAY Words
	"build_room": [["box", Rect2(4, 5, 16, 14), 1.8], ["disc", Vector2(4, 5), 2.2], ["disc", Vector2(20, 5), 2.2], ["disc", Vector2(4, 19), 2.2], ["disc", Vector2(20, 19), 2.2]],
	"build_wall": [["box", Rect2(3, 9, 18, 6), 1.8], ["seg", Vector2(9, 9), Vector2(9, 15), 1.4], ["seg", Vector2(15, 9), Vector2(15, 15), 1.4]],
	"build_pull": [["seg", Vector2(12, 20), Vector2(12, 6), 2.2], ["seg", Vector2(6.5, 11), Vector2(12, 5.5), 2.2], ["seg", Vector2(17.5, 11), Vector2(12, 5.5), 2.2], ["seg", Vector2(5, 21), Vector2(19, 21), 1.8]],
	"build_opening": [["box", Rect2(4, 3.5, 16, 17), 1.8], ["box", Rect2(8.5, 8, 7, 12.5), 0]],
	"build_door": [["box", Rect2(6, 3.5, 12, 17), 1.8], ["disc", Vector2(15, 12.5), 1.4]],
	"build_window": [["box", Rect2(4, 4, 16, 16), 1.8], ["seg", Vector2(12, 4), Vector2(12, 20), 1.4], ["seg", Vector2(4, 12), Vector2(20, 12), 1.4]],
	"build_floor": [["seg", Vector2(12, 4), Vector2(21, 9), 1.8], ["seg", Vector2(21, 9), Vector2(12, 14), 1.8], ["seg", Vector2(12, 14), Vector2(3, 9), 1.8], ["seg", Vector2(3, 9), Vector2(12, 4), 1.8],
		["seg", Vector2(3, 14), Vector2(12, 19), 1.8], ["seg", Vector2(12, 19), Vector2(21, 14), 1.8]],
	"build_roof": [["seg", Vector2(3, 12), Vector2(12, 4), 1.9], ["seg", Vector2(12, 4), Vector2(21, 12), 1.9], ["box", Rect2(6, 12, 12, 8), 1.8]],
	"build_piece": [["seg", Vector2(12, 3), Vector2(20, 7.5), 1.7], ["seg", Vector2(20, 7.5), Vector2(20, 16.5), 1.7], ["seg", Vector2(20, 16.5), Vector2(12, 21), 1.7], ["seg", Vector2(12, 21), Vector2(4, 16.5), 1.7],
		["seg", Vector2(4, 16.5), Vector2(4, 7.5), 1.7], ["seg", Vector2(4, 7.5), Vector2(12, 3), 1.7], ["seg", Vector2(4, 7.5), Vector2(12, 12), 1.5], ["seg", Vector2(20, 7.5), Vector2(12, 12), 1.5], ["seg", Vector2(12, 12), Vector2(12, 21), 1.5]],
	# BUILD > Piece: the picker's big cards (Icons.big) and the rotate arrow
	"piece_stairs": [["seg", Vector2(3, 20), Vector2(3, 16), 2.0], ["seg", Vector2(3, 16), Vector2(8, 16), 2.0], ["seg", Vector2(8, 16), Vector2(8, 12), 2.0], ["seg", Vector2(8, 12), Vector2(13, 12), 2.0],
		["seg", Vector2(13, 12), Vector2(13, 8), 2.0], ["seg", Vector2(13, 8), Vector2(18, 8), 2.0], ["seg", Vector2(18, 8), Vector2(18, 4), 2.0], ["seg", Vector2(18, 4), Vector2(21, 4), 2.0], ["seg", Vector2(3, 20), Vector2(21, 20), 2.0], ["seg", Vector2(21, 4), Vector2(21, 20), 2.0]],
	"piece_stairs_l": [["seg", Vector2(3, 21), Vector2(3, 17), 2.0], ["seg", Vector2(3, 17), Vector2(7, 17), 2.0], ["seg", Vector2(7, 17), Vector2(7, 13), 2.0], ["seg", Vector2(7, 13), Vector2(11, 13), 2.0],
		["box", Rect2(11, 8, 6, 5), 1.8], ["seg", Vector2(17, 9), Vector2(21, 9), 2.0], ["seg", Vector2(17, 9), Vector2(17, 5), 2.0], ["seg", Vector2(21, 9), Vector2(21, 5), 2.0], ["seg", Vector2(3, 21), Vector2(11, 21), 2.0], ["seg", Vector2(11, 13), Vector2(11, 21), 2.0]],
	"piece_table": [["box", Rect2(3, 8, 18, 3), 0], ["seg", Vector2(5.5, 11), Vector2(5.5, 20), 2.2], ["seg", Vector2(18.5, 11), Vector2(18.5, 20), 2.2]],
	"piece_bench": [["box", Rect2(3, 12, 18, 3), 0], ["seg", Vector2(5.5, 15), Vector2(5.5, 20), 2.2], ["seg", Vector2(18.5, 15), Vector2(18.5, 20), 2.2]],
	"piece_crate": [["box", Rect2(4, 5, 16, 15), 1.9], ["seg", Vector2(4, 5), Vector2(20, 20), 1.5], ["seg", Vector2(20, 5), Vector2(4, 20), 1.5]],
	"piece_pillar": [["box", Rect2(8.5, 6, 7, 13), 1.8], ["seg", Vector2(6, 4.5), Vector2(18, 4.5), 2.2], ["seg", Vector2(6, 20.5), Vector2(18, 20.5), 2.2]],
	"piece_fence": [["seg", Vector2(4.5, 5), Vector2(4.5, 20), 2.4], ["seg", Vector2(12, 5), Vector2(12, 20), 2.4], ["seg", Vector2(19.5, 5), Vector2(19.5, 20), 2.4], ["seg", Vector2(3, 9), Vector2(21, 9), 1.8], ["seg", Vector2(3, 15), Vector2(21, 15), 1.8]],
	"piece_ramp": [["seg", Vector2(3, 20), Vector2(21, 20), 2.0], ["seg", Vector2(21, 20), Vector2(21, 6), 2.0], ["seg", Vector2(21, 6), Vector2(3, 20), 2.0]],
	"piece_platform": [["box", Rect2(3, 11, 18, 9), 1.9], ["seg", Vector2(3, 11), Vector2(7, 6.5), 1.6], ["seg", Vector2(21, 11), Vector2(17, 6.5), 1.6], ["seg", Vector2(7, 6.5), Vector2(17, 6.5), 1.6]],
	"piece_rotate": [["arc", Vector2(12, 12), 7.5, 2.2, 40, 330], ["seg", Vector2(17.5, 3.5), Vector2(19.8, 9.2), 2.2], ["seg", Vector2(19.8, 9.2), Vector2(13.6, 8.6), 2.2]],
	"build_blueprint": [["box", Rect2(3, 4, 18, 16), 1.8], ["seg", Vector2(3, 9), Vector2(21, 9), 1.2], ["seg", Vector2(9, 9), Vector2(9, 20), 1.2], ["seg", Vector2(13, 14), Vector2(18, 14), 1.4], ["seg", Vector2(13, 17), Vector2(18, 17), 1.4]],
	# PART workspace (scripts/build/part_ui.gd): SKETCH Line Rectangle Circle Arc Dimension, CREATE Extrude Revolve Mirror, MODIFY Fillet Chamfer, Finish; the timeline's steps
	"part_line": [["seg", Vector2(4, 19), Vector2(20, 5), 2.2], ["disc", Vector2(4, 19), 2.2], ["disc", Vector2(20, 5), 2.2]],
	"part_rectangle": [["box", Rect2(3.5, 6, 17, 12), 1.9]],
	"part_pointy": [["seg", Vector2(3.5, 19), Vector2(20.5, 19), 1.9], ["seg", Vector2(3.5, 19), Vector2(12, 4), 1.9], ["seg", Vector2(12, 4), Vector2(20.5, 19), 1.9]],   # POINTY: the house roof triangle (Easy Part Draw shape)
	"part_circle": [["ring", Vector2(12, 12), 8.5, 1.9]],
	"part_spline": [["seg", Vector2(4, 17), Vector2(9, 7), 2.0], ["seg", Vector2(9, 7), Vector2(15, 17), 2.0], ["seg", Vector2(15, 17), Vector2(20, 7), 2.0], ["disc", Vector2(4, 17), 1.8], ["disc", Vector2(9, 7), 1.8], ["disc", Vector2(15, 17), 1.8], ["disc", Vector2(20, 7), 1.8]],
	"part_arc": [["arc", Vector2(12, 19), 10, 2.0, 215, 325], ["disc", Vector2(4.2, 12.8), 1.8], ["disc", Vector2(19.8, 12.8), 1.8]],
	"part_dimension": [["seg", Vector2(3.5, 7), Vector2(20.5, 7), 1.6], ["seg", Vector2(3.5, 4), Vector2(3.5, 11), 1.5], ["seg", Vector2(20.5, 4), Vector2(20.5, 11), 1.5], ["box", Rect2(4, 13.5, 16, 6), 1.5]],
	"part_extrude": [["box", Rect2(4.5, 10, 12, 10), 1.8], ["seg", Vector2(4.5, 10), Vector2(8.5, 6), 1.7], ["seg", Vector2(16.5, 10), Vector2(20.5, 6), 1.7], ["seg", Vector2(8.5, 6), Vector2(20.5, 6), 1.7], ["seg", Vector2(20.5, 6), Vector2(20.5, 16), 1.7], ["seg", Vector2(16.5, 20), Vector2(20.5, 16), 1.7]],
	"part_revolve": [["arc", Vector2(12, 12), 8, 2.0, 40, 320], ["seg", Vector2(12, 2.5), Vector2(12, 21.5), 1.3], ["seg", Vector2(17.5, 4), Vector2(20, 7.5), 1.8], ["seg", Vector2(20, 7.5), Vector2(15, 8.5), 1.8]],
	"part_loft": [["box", Rect2(3, 4, 6, 6), 1.6], ["box", Rect2(15, 14, 6, 6), 1.6], ["seg", Vector2(3, 4), Vector2(15, 14), 1.4], ["seg", Vector2(9, 4), Vector2(21, 14), 1.4], ["seg", Vector2(9, 10), Vector2(21, 20), 1.4]],
	"part_sweep": [["box", Rect2(2, 15, 7, 7), 1.6], ["seg", Vector2(5.5, 15), Vector2(5.5, 6), 1.4], ["seg", Vector2(5.5, 6), Vector2(19, 6), 1.4], ["seg", Vector2(19, 6), Vector2(19, 20), 1.4]],
	"part_pipe3d": [["box", Rect2(2, 15, 7, 7), 1.6], ["seg", Vector2(5.5, 15), Vector2(5.5, 6), 1.4], ["seg", Vector2(5.5, 6), Vector2(19, 6), 1.4], ["seg", Vector2(19, 6), Vector2(19, 20), 1.4]],   # PIPE THROUGH POINTS (s215): the sweep drawing, a tube along a path
	"part_pattern": [["box", Rect2(2, 9, 5, 5), 1.4], ["box", Rect2(9.5, 9, 5, 5), 1.4], ["box", Rect2(17, 9, 5, 5), 1.4]],   # PATTERN: three copies in a row
	"part_ornament": [["arc", Vector2(13, 9), 6.0, 2.4, 200.0, 520.0], ["seg", Vector2(7, 9), Vector2(6, 18), 2.4], ["seg", Vector2(3, 20), Vector2(20, 20), 1.8], ["disc", Vector2(18, 5), 1.6]],   # s227 ORNAMENT: a curled tail on a base
	"part_canvas": [["box", Rect2(3, 4, 18, 14), 1.6], ["disc", Vector2(16, 8), 1.8], ["seg", Vector2(3, 16), Vector2(9, 10), 1.4], ["seg", Vector2(9, 10), Vector2(13, 14), 1.4], ["seg", Vector2(13, 14), Vector2(21, 8), 1.4]],
	"part_measure": [["seg", Vector2(3, 18), Vector2(21, 6), 1.6], ["disc", Vector2(3, 18), 2.0], ["disc", Vector2(21, 6), 2.0], ["seg", Vector2(7, 14), Vector2(7, 19), 1.2]],
	"part_section": [["box", Rect2(4, 4, 16, 16), 1.6], ["seg", Vector2(2.5, 12), Vector2(21.5, 12), 2.4]],
	"part_offset_plane": [["seg", Vector2(3, 17), Vector2(14, 17), 2.0], ["seg", Vector2(5, 9), Vector2(16, 9), 1.2], ["seg", Vector2(3, 17), Vector2(5, 9), 1.2], ["seg", Vector2(14, 17), Vector2(16, 9), 1.2], ["seg", Vector2(19, 4), Vector2(19, 19), 1.6], ["seg", Vector2(17, 17), Vector2(19, 19), 1.6], ["seg", Vector2(21, 17), Vector2(19, 19), 1.6]],
	"part_plane": [["seg", Vector2(3, 17), Vector2(14, 17), 2.0], ["seg", Vector2(5, 9), Vector2(16, 9), 1.2], ["seg", Vector2(3, 17), Vector2(5, 9), 1.2], ["seg", Vector2(14, 17), Vector2(16, 9), 1.2], ["seg", Vector2(19, 4), Vector2(19, 19), 1.6], ["seg", Vector2(17, 17), Vector2(19, 19), 1.6], ["seg", Vector2(21, 17), Vector2(19, 19), 1.6]],
	"part_mirror": [["seg", Vector2(12, 3), Vector2(12, 21), 1.3], ["seg", Vector2(4, 18), Vector2(9, 6), 1.8], ["seg", Vector2(9, 6), Vector2(9, 18), 1.8], ["seg", Vector2(9, 18), Vector2(4, 18), 1.8], ["seg", Vector2(20, 18), Vector2(15, 6), 1.8], ["seg", Vector2(15, 6), Vector2(15, 18), 1.8], ["seg", Vector2(15, 18), Vector2(20, 18), 1.8]],
	"part_swing": [["seg", Vector2(4, 20), Vector2(20, 20), 1.6], ["seg", Vector2(4, 20), Vector2(4, 4), 1.6], ["seg", Vector2(4, 20), Vector2(15, 7), 1.8]],   # p123driveit: a lid swung open on its hinge
	"part_fillet": [["seg", Vector2(5, 3.5), Vector2(5, 14), 2.0], ["seg", Vector2(5, 14), Vector2(6.3, 17.2), 2.0], ["seg", Vector2(6.3, 17.2), Vector2(9.5, 19), 2.0], ["seg", Vector2(9.5, 19), Vector2(13, 19.5), 2.0], ["seg", Vector2(13, 19.5), Vector2(20.5, 19.5), 2.0]],
	"part_chamfer": [["seg", Vector2(5, 3.5), Vector2(5, 12), 2.0], ["seg", Vector2(5, 12), Vector2(12.5, 19.5), 2.0], ["seg", Vector2(12.5, 19.5), Vector2(20.5, 19.5), 2.0]],
	"part_offset_face": [["box", Rect2(3, 13, 18, 8), 1.8], ["seg", Vector2(12, 10), Vector2(12, 2.5), 1.8], ["seg", Vector2(8.5, 6), Vector2(12, 2.5), 1.8], ["seg", Vector2(15.5, 6), Vector2(12, 2.5), 1.8]],   # OFFSET FACE: a block with its top face pushed up
	"part_draft": [["seg", Vector2(4, 20), Vector2(8, 4), 1.9], ["seg", Vector2(20, 20), Vector2(16, 4), 1.9], ["seg", Vector2(4, 20), Vector2(20, 20), 1.9], ["seg", Vector2(8, 4), Vector2(16, 4), 1.9]],   # DRAFT: a block whose sides lean
	"part_livecut": [["box", Rect2(5, 3, 14, 18), 1.6], ["seg", Vector2(5, 7), Vector2(14, 7), 1.2], ["seg", Vector2(9, 11), Vector2(19, 11), 1.2], ["seg", Vector2(5, 15), Vector2(14, 15), 1.2]],   # p204livinghing: a strip with slots
	"part_hinge": [["box", Rect2(9, 4, 10, 16), 1.8], ["seg", Vector2(3, 4), Vector2(3, 20), 2.6], ["disc", Vector2(3, 4), 2.0], ["disc", Vector2(3, 20), 2.0]],   # HINGE: a leaf turning about its edge
	"part_appearance": [["disc", Vector2(12, 12), 8.0], ["ring", Vector2(12, 12), 8.5, 1.9], ["disc", Vector2(12, 12), 3.0]],   # APPEARANCE: a colour disc with a ring
	"part_filter_all": [["box", Rect2(3, 5, 18, 14), 1.6], ["disc", Vector2(3, 5), 1.8], ["disc", Vector2(21, 5), 1.8], ["disc", Vector2(3, 19), 1.8], ["disc", Vector2(21, 19), 1.8]],   # NROUNDFILTER: every edge of the box (its four corners rounded)
	"part_filter_outside": [["box", Rect2(3, 5, 18, 14), 2.0], ["box", Rect2(8, 9, 8, 6), 1.0]],   # NROUNDFILTER: the outside skin (a box with a thin inner line: the inside is not rounded)
	"part_filter_top": [["seg", Vector2(3, 5), Vector2(21, 5), 3.0], ["box", Rect2(3, 8, 18, 11), 1.4]],   # NROUNDFILTER: the top rim, thick, and the box below it
	"part_stronger": [["box", Rect2(2, 16, 20, 3), 1.6], ["seg", Vector2(6, 16), Vector2(6, 5), 2.4], ["seg", Vector2(12, 16), Vector2(12, 3), 2.4], ["seg", Vector2(18, 16), Vector2(18, 5), 2.4]],   # p038makeitstro: a plate with two ribs standing on it
	"part_split": [["box", Rect2(3, 5, 18, 14), 1.6], ["seg", Vector2(12, 2.5), Vector2(12, 21.5), 1.5]],   # SPLIT: a block cut by a plane
	"part_primitive": [["box", Rect2(3, 10, 10, 10), 1.8], ["ring", Vector2(16.5, 8.5), 4.5, 1.8]],   # s229 PRIMITIVE: a box and a ball, by numbers
	"part_prim": [["box", Rect2(3, 10, 10, 10), 1.8], ["ring", Vector2(16.5, 8.5), 4.5, 1.8]],
	"part_combine": [["box", Rect2(3, 5, 11, 11), 1.6], ["box", Rect2(10, 8, 11, 11), 1.6]],   # COMBINE: two overlapping blocks
	"part_shell": [["box", Rect2(3.5, 3.5, 17, 17), 1.9], ["box", Rect2(7.5, 7.5, 9, 9), 1.2]],   # SHELL: a hollow block
	"part_constrain": [["ring", Vector2(8, 12), 4.2, 1.8], ["ring", Vector2(16, 12), 4.2, 1.8]],   # GAP 9 CONSTRAIN: two linked rings
	"part_horizontal": [["seg", Vector2(3, 12), Vector2(21, 12), 2.0], ["disc", Vector2(3, 12), 1.8], ["disc", Vector2(21, 12), 1.8]],
	"part_vertical": [["seg", Vector2(12, 3), Vector2(12, 21), 2.0], ["disc", Vector2(12, 3), 1.8], ["disc", Vector2(12, 21), 1.8]],
	"part_coincident": [["ring", Vector2(12, 12), 6.0, 1.8], ["disc", Vector2(12, 12), 2.2]],
	"part_parallel": [["seg", Vector2(3, 15), Vector2(16, 6), 1.9], ["seg", Vector2(8, 21), Vector2(21, 12), 1.9]],
	"part_perpendicular": [["seg", Vector2(5, 21), Vector2(5, 3), 1.9], ["seg", Vector2(5, 21), Vector2(21, 21), 1.9]],
	"part_equal": [["seg", Vector2(3, 8), Vector2(21, 8), 2.0], ["seg", Vector2(3, 16), Vector2(21, 16), 2.0]],
	"part_angle": [["seg", Vector2(4, 20), Vector2(21, 5), 1.9], ["seg", Vector2(4, 20), Vector2(21, 20), 1.9], ["arc", Vector2(4, 20), 8, 1.6, 270, 325]],
	"part_remove_constraint": [["seg", Vector2(6, 6), Vector2(18, 18), 2.2], ["seg", Vector2(18, 6), Vector2(6, 18), 2.2]],
	"part_finish": [["seg", Vector2(4.5, 12.5), Vector2(9.5, 17.5), 2.4], ["seg", Vector2(9.5, 17.5), Vector2(19.5, 6.5), 2.4]],
	"part_sketch": [["box", Rect2(4, 5, 16, 14), 1.4], ["seg", Vector2(7, 16), Vector2(17, 8), 2.0], ["disc", Vector2(7, 16), 1.8], ["disc", Vector2(17, 8), 1.8]],
	"part_part": [["seg", Vector2(12, 3), Vector2(21, 8), 1.8], ["seg", Vector2(21, 8), Vector2(21, 17), 1.8], ["seg", Vector2(21, 17), Vector2(12, 22), 1.8], ["seg", Vector2(12, 22), Vector2(3, 17), 1.8], ["seg", Vector2(3, 17), Vector2(3, 8), 1.8], ["seg", Vector2(3, 8), Vector2(12, 3), 1.8], ["seg", Vector2(12, 12), Vector2(12, 22), 1.4], ["seg", Vector2(12, 12), Vector2(3, 8), 1.4], ["seg", Vector2(12, 12), Vector2(21, 8), 1.4]],
	"build_words": [["box", Rect2(3.5, 4, 17, 12), 1.8], ["seg", Vector2(8, 16), Vector2(8, 20.5), 1.8], ["seg", Vector2(8, 20.5), Vector2(12.5, 16), 1.8], ["seg", Vector2(7.5, 8.5), Vector2(16.5, 8.5), 1.5], ["seg", Vector2(7.5, 11.5), Vector2(14, 11.5), 1.5]],
	"shade_wire": [["box", Rect2(4, 4, 16, 16), 1.4], ["seg", Vector2(4, 12), Vector2(20, 12), 1.2], ["seg", Vector2(12, 4), Vector2(12, 20), 1.2]],
	"shade_solid": [["disc", Vector2(12, 12), 8.5]],
	"shade_matcap": [["ring", Vector2(12, 12), 8.5, 1.8], ["disc", Vector2(9, 9), 2.6]],
	"shade_xray": [["ring", Vector2(12, 12), 8.5, 1.4], ["ring", Vector2(12, 12), 4.5, 1.4], ["disc", Vector2(12, 12), 1.4]],
	"shade_sil": [["disc", Vector2(12, 6), 3.0], ["box", Rect2(7, 10, 10, 11), 0.0]],
	"lit_flat": [["box", Rect2(4, 6, 16, 12), 0.0]],
	"lit_top": [["disc", Vector2(12, 5.5), 2.8], ["seg", Vector2(12, 9), Vector2(12, 14), 1.8], ["seg", Vector2(8, 14), Vector2(16, 14), 1.6], ["seg", Vector2(5, 20), Vector2(19, 20), 2.2]],
	"sky": [["seg", Vector2(3, 17), Vector2(21, 17), 1.8], ["arc", Vector2(12, 17), 6, 1.8, 180, 360], ["seg", Vector2(12, 4), Vector2(12, 7), 1.6], ["seg", Vector2(4, 8), Vector2(6.5, 10), 1.6], ["seg", Vector2(20, 8), Vector2(17.5, 10), 1.6]],
	"lit_three": [["disc", Vector2(12, 14), 3.2], ["disc", Vector2(4.5, 6), 2.0], ["disc", Vector2(19.5, 8), 1.4], ["disc", Vector2(12, 3.5), 1.6], ["seg", Vector2(6, 7.2), Vector2(9.6, 11.8), 1.4]],
	"lit_rim": [["ring", Vector2(12, 12), 6.5, 1.6], ["arc", Vector2(12, 12), 9.5, 2.2, 200, 340], ["seg", Vector2(12, 12), Vector2(12, 12.1), 1.0]],
	"lit_noir": [["disc", Vector2(12, 12), 7.5], ["box", Rect2(12, 4.5, 7.5, 15), 0.0], ["seg", Vector2(4, 4), Vector2(8, 8), 1.6]],
	"lit_day": [["disc", Vector2(12, 12), 4.0], ["seg", Vector2(12, 2), Vector2(12, 5), 1.8], ["seg", Vector2(12, 19), Vector2(12, 22), 1.8], ["seg", Vector2(2, 12), Vector2(5, 12), 1.8], ["seg", Vector2(19, 12), Vector2(22, 12), 1.8], ["seg", Vector2(5, 5), Vector2(7, 7), 1.6], ["seg", Vector2(17, 17), Vector2(19, 19), 1.6], ["seg", Vector2(19, 5), Vector2(17, 7), 1.6], ["seg", Vector2(5, 19), Vector2(7, 17), 1.6]],
	"crowd": [["disc", Vector2(6, 6), 2.0], ["disc", Vector2(12, 5), 2.0], ["disc", Vector2(18, 6), 2.0], ["seg", Vector2(6, 9), Vector2(6, 17), 2.0], ["seg", Vector2(12, 8), Vector2(12, 18), 2.0], ["seg", Vector2(18, 9), Vector2(18, 17), 2.0]],
	"reroll": [["arc", Vector2(12, 12), 7.5, 2.2, -60, 210], ["seg", Vector2(19.5, 5), Vector2(18.5, 10), 2.2], ["seg", Vector2(18.5, 10), Vector2(13.5, 9), 2.2], ["disc", Vector2(12, 12), 2.4]],
	"crowd_remove": [["disc", Vector2(12, 5), 2.4], ["seg", Vector2(12, 8), Vector2(12, 16), 2.4], ["seg", Vector2(12, 10), Vector2(5, 15), 2.0], ["seg", Vector2(12, 10), Vector2(19, 15), 2.0], ["seg", Vector2(6, 21), Vector2(18, 21), 2.6]],
	"body_prop": [["seg", Vector2(12, 3), Vector2(12, 21), 1.8], ["seg", Vector2(12, 3), Vector2(8.5, 6.5), 1.8], ["seg", Vector2(12, 3), Vector2(15.5, 6.5), 1.8], ["seg", Vector2(12, 21), Vector2(8.5, 17.5), 1.8], ["seg", Vector2(12, 21), Vector2(15.5, 17.5), 1.8], ["seg", Vector2(17, 8), Vector2(21, 8), 1.6], ["seg", Vector2(17, 16), Vector2(21, 16), 1.6]],
	"archetype": [["ring", Vector2(12, 5), 3, 1.8], ["seg", Vector2(12, 8), Vector2(12, 16), 1.8], ["seg", Vector2(3, 11), Vector2(21, 11), 1.8], ["seg", Vector2(12, 16), Vector2(8, 21), 1.8], ["seg", Vector2(12, 16), Vector2(16, 21), 1.8]],
	"body_nums": [["ring", Vector2(12, 5), 3, 1.8], ["seg", Vector2(12, 8), Vector2(12, 16), 1.8], ["seg", Vector2(12, 16), Vector2(9, 21), 1.8], ["seg", Vector2(12, 16), Vector2(15, 21), 1.8], ["seg", Vector2(19, 4), Vector2(19, 21), 1.6], ["seg", Vector2(17, 4), Vector2(21, 4), 1.6], ["seg", Vector2(17, 21), Vector2(21, 21), 1.6]],
	"mannequin": [["ring", Vector2(12, 5), 3, 1.8], ["box", Rect2(8, 9.5, 8, 6), 1.8], ["seg", Vector2(10, 15.5), Vector2(10, 21), 1.8], ["seg", Vector2(14, 15.5), Vector2(14, 21), 1.8]],
	"reset": [["arc", Vector2(12, 12), 7.5, 2.2, -60, 210], ["seg", Vector2(19.5, 5), Vector2(18.5, 10), 2.2], ["seg", Vector2(18.5, 10), Vector2(13.5, 9), 2.2]],
	"arms": [["disc", Vector2(12, 4.5), 2.6], ["seg", Vector2(12, 8), Vector2(12, 16), 2.4], ["seg", Vector2(12, 9.5), Vector2(5, 15), 2.0],
		["seg", Vector2(12, 9.5), Vector2(19, 15), 2.0], ["seg", Vector2(12, 16), Vector2(8.5, 22), 2.0], ["seg", Vector2(12, 16), Vector2(15.5, 22), 2.0]],
	"mirror": [["seg", Vector2(12, 2), Vector2(12, 6), 1.5], ["seg", Vector2(12, 9), Vector2(12, 15), 1.5], ["seg", Vector2(12, 18), Vector2(12, 22), 1.5],
		["seg", Vector2(9, 6), Vector2(3, 18), 1.8], ["seg", Vector2(3, 18), Vector2(9, 18), 1.8], ["seg", Vector2(9, 18), Vector2(9, 6), 1.8],
		["seg", Vector2(15, 6), Vector2(21, 18), 1.8], ["seg", Vector2(21, 18), Vector2(15, 18), 1.8], ["seg", Vector2(15, 18), Vector2(15, 6), 1.8]],
	"floor": [["seg", Vector2(12, 3), Vector2(12, 14), 2.2], ["seg", Vector2(6.5, 9), Vector2(12, 15), 2.2], ["seg", Vector2(17.5, 9), Vector2(12, 15), 2.2],
		["seg", Vector2(3, 20.5), Vector2(21, 20.5), 2.2]],
	"symmetry": [["seg", Vector2(12, 2), Vector2(12, 6), 1.5], ["seg", Vector2(12, 9), Vector2(12, 15), 1.5], ["seg", Vector2(12, 18), Vector2(12, 22), 1.5],
		["arc", Vector2(12, 12), 8, 2, 200, 340], ["seg", Vector2(4.5, 9.3), Vector2(3, 13), 2], ["seg", Vector2(19.5, 9.3), Vector2(21, 13), 2]],
	"smart": [["seg", Vector2(4, 20), Vector2(12, 12), 2.2], ["seg", Vector2(12, 12), Vector2(20, 5), 1.8], ["seg", Vector2(12, 12), Vector2(19, 18), 1.8],
		["seg", Vector2(15, 4), Vector2(20, 5), 1.8], ["seg", Vector2(19, 9.5), Vector2(20, 5), 1.8]],
	"clip": [["box", Rect2(3, 7, 18, 13), 1.8], ["seg", Vector2(12, 10.5), Vector2(12, 16.5), 2.0], ["seg", Vector2(9, 13.5), Vector2(15, 13.5), 2.0],
		["seg", Vector2(6, 3.5), Vector2(18, 3.5), 1.8]],
	"save": [["box", Rect2(5, 5, 14, 14), 1.8], ["box", Rect2(8, 5, 8, 5), 1.6], ["box", Rect2(8, 13, 8, 6), 1.6]],
	"play": [["seg", Vector2(8, 5), Vector2(8, 19), 2.4], ["seg", Vector2(8, 5), Vector2(19, 12), 2.4], ["seg", Vector2(8, 19), Vector2(19, 12), 2.4],
		["seg", Vector2(10.5, 8.5), Vector2(10.5, 15.5), 3], ["seg", Vector2(13, 10), Vector2(13, 14), 3]],
	"stop": [["box", Rect2(6, 6, 12, 12), 0]],
	"realtime": [["ring", Vector2(12, 12), 9, 2], ["seg", Vector2(12, 12), Vector2(12, 6.5), 2.2], ["seg", Vector2(12, 12), Vector2(16.5, 14.5), 2.2]],
	"frames": [["box", Rect2(2.5, 8, 5, 8), 1.6], ["box", Rect2(9.5, 8, 5, 8), 1.6], ["box", Rect2(16.5, 8, 5, 8), 1.6]],
	"easy": [["ring", Vector2(12, 12), 9, 2], ["disc", Vector2(8.5, 9.5), 1.6], ["disc", Vector2(15.5, 9.5), 1.6], ["arc", Vector2(12, 12), 5, 2, 20, 160]],
	"poselib": [["box", Rect2(2.5, 2.5, 8.5, 8.5), 1.5], ["box", Rect2(13, 2.5, 8.5, 8.5), 1.5], ["box", Rect2(2.5, 13, 8.5, 8.5), 1.5],
		["box", Rect2(13, 13, 8.5, 8.5), 1.5], ["disc", Vector2(6.75, 5.6), 1.3], ["seg", Vector2(6.75, 7), Vector2(6.75, 9.5), 1.3],
		["disc", Vector2(17.25, 5.6), 1.3], ["seg", Vector2(17.25, 7), Vector2(19.5, 8.8), 1.3]],
	"first": [["seg", Vector2(6, 6), Vector2(6, 18), 2.2], ["seg", Vector2(18, 6), Vector2(10, 12), 2.2], ["seg", Vector2(10, 12), Vector2(18, 18), 2.2]],
	"last": [["seg", Vector2(18, 6), Vector2(18, 18), 2.2], ["seg", Vector2(6, 6), Vector2(14, 12), 2.2], ["seg", Vector2(14, 12), Vector2(6, 18), 2.2]],
	"prev": [["seg", Vector2(12, 6), Vector2(6, 12), 2.2], ["seg", Vector2(6, 12), Vector2(12, 18), 2.2], ["seg", Vector2(19, 6), Vector2(13, 12), 2.2],
		["seg", Vector2(13, 12), Vector2(19, 18), 2.2]],
	"next": [["seg", Vector2(12, 6), Vector2(18, 12), 2.2], ["seg", Vector2(18, 12), Vector2(12, 18), 2.2], ["seg", Vector2(5, 6), Vector2(11, 12), 2.2],
		["seg", Vector2(11, 12), Vector2(5, 18), 2.2]],
	"gear": [["ring", Vector2(12, 12), 5.5, 2.2], ["disc", Vector2(12, 12), 1.8], ["seg", Vector2(12, 3), Vector2(12, 6.5), 2.6], ["seg", Vector2(12, 17.5), Vector2(12, 21), 2.6],
		["seg", Vector2(3, 12), Vector2(6.5, 12), 2.6], ["seg", Vector2(17.5, 12), Vector2(21, 12), 2.6], ["seg", Vector2(5.6, 5.6), Vector2(8.1, 8.1), 2.6],
		["seg", Vector2(15.9, 15.9), Vector2(18.4, 18.4), 2.6], ["seg", Vector2(18.4, 5.6), Vector2(15.9, 8.1), 2.6], ["seg", Vector2(8.1, 15.9), Vector2(5.6, 18.4), 2.6]],
	"orbit": [["arc", Vector2(12, 12), 8, 1.8, 200, 520], ["seg", Vector2(19.5, 9), Vector2(20, 14), 1.8], ["seg", Vector2(20, 14), Vector2(16, 12), 1.8], ["disc", Vector2(12, 12), 2.2]],
	"pan": [["seg", Vector2(12, 3), Vector2(12, 21), 1.8], ["seg", Vector2(3, 12), Vector2(21, 12), 1.8], ["seg", Vector2(12, 3), Vector2(9.5, 5.5), 1.8],
		["seg", Vector2(12, 3), Vector2(14.5, 5.5), 1.8], ["seg", Vector2(12, 21), Vector2(9.5, 18.5), 1.8], ["seg", Vector2(12, 21), Vector2(14.5, 18.5), 1.8],
		["seg", Vector2(3, 12), Vector2(5.5, 9.5), 1.8], ["seg", Vector2(3, 12), Vector2(5.5, 14.5), 1.8], ["seg", Vector2(21, 12), Vector2(18.5, 9.5), 1.8],
		["seg", Vector2(21, 12), Vector2(18.5, 14.5), 1.8]],
	"zoom_in": [["ring", Vector2(10, 10), 6.5, 1.8], ["seg", Vector2(15, 15), Vector2(21, 21), 2.4], ["seg", Vector2(7, 10), Vector2(13, 10), 1.8], ["seg", Vector2(10, 7), Vector2(10, 13), 1.8]],
	"zoom_out": [["ring", Vector2(10, 10), 6.5, 1.8], ["seg", Vector2(15, 15), Vector2(21, 21), 2.4], ["seg", Vector2(7, 10), Vector2(13, 10), 1.8]],
	"view_fit": [["box", Rect2(7, 7, 10, 10), 1.8], ["seg", Vector2(3, 8), Vector2(3, 3), 1.8], ["seg", Vector2(3, 3), Vector2(8, 3), 1.8], ["seg", Vector2(16, 3), Vector2(21, 3), 1.8], ["seg", Vector2(21, 3), Vector2(21, 8), 1.8], ["seg", Vector2(3, 16), Vector2(3, 21), 1.8], ["seg", Vector2(3, 21), Vector2(8, 21), 1.8], ["seg", Vector2(16, 21), Vector2(21, 21), 1.8], ["seg", Vector2(21, 16), Vector2(21, 21), 1.8]],   # P107 FITVIEW: the corners of the frame round a box
	"view_front": [["box", Rect2(5, 5, 14, 14), 1.8]],   # P107 FITVIEW: a square face on
	"view_top": [["box", Rect2(3, 9, 18, 6), 1.8]],   # P107 FITVIEW: a flat face, seen from above
	"view_side": [["box", Rect2(8, 3, 8, 18), 1.8]],   # P107 FITVIEW: a tall face, seen from the side
	"view_3q": [["seg", Vector2(4, 8), Vector2(12, 4), 1.8], ["seg", Vector2(12, 4), Vector2(20, 8), 1.8], ["seg", Vector2(4, 8), Vector2(12, 12), 1.8], ["seg", Vector2(12, 12), Vector2(20, 8), 1.8], ["seg", Vector2(12, 12), Vector2(12, 20), 1.8]],   # P107 FITVIEW: a cube's corner
	"fit": [["seg", Vector2(3, 8), Vector2(3, 3), 1.8], ["seg", Vector2(3, 3), Vector2(8, 3), 1.8], ["seg", Vector2(16, 3), Vector2(21, 3), 1.8], ["seg", Vector2(21, 3), Vector2(21, 8), 1.8],
		["seg", Vector2(21, 16), Vector2(21, 21), 1.8], ["seg", Vector2(21, 21), Vector2(16, 21), 1.8], ["seg", Vector2(8, 21), Vector2(3, 21), 1.8], ["seg", Vector2(3, 21), Vector2(3, 16), 1.8],
		["box", Rect2(8.5, 8.5, 7, 7), 1.6]],
	"grid": [["seg", Vector2(3, 8), Vector2(21, 8), 1.4], ["seg", Vector2(3, 16), Vector2(21, 16), 1.4], ["seg", Vector2(8, 3), Vector2(8, 21), 1.4],
		["seg", Vector2(16, 3), Vector2(16, 21), 1.4], ["box", Rect2(3, 3, 18, 18), 1.4]],
	"library": [["box", Rect2(3, 3, 8, 8), 1.6], ["box", Rect2(13, 3, 8, 8), 1.6], ["box", Rect2(3, 13, 8, 8), 1.6], ["box", Rect2(13, 13, 8, 8), 1.6]],   # the object library's four tiles
	"prop": [["box", Rect2(4, 10, 16, 10), 1.8], ["seg", Vector2(4, 10), Vector2(8, 5), 1.6], ["seg", Vector2(20, 10), Vector2(16, 5), 1.6],
		["seg", Vector2(8, 5), Vector2(16, 5), 1.6]],
	"ai": [["box", Rect2(3, 4, 16, 11), 1.8], ["seg", Vector2(7, 15), Vector2(6, 20), 1.8], ["seg", Vector2(6, 20), Vector2(11, 15), 1.8], ["seg", Vector2(7, 9.5), Vector2(15, 9.5), 1.8]],
	"cameras": [["box", Rect2(1, 4, 8, 6), 1.5], ["box", Rect2(1, 12, 8, 6), 1.5], ["box", Rect2(11, 4, 8, 6), 1.5], ["box", Rect2(11, 12, 8, 6), 1.5]],   # ROADMAP 89: several cameras, four small ones
	"video": [["box", Rect2(3, 7, 13, 10), 1.8], ["seg", Vector2(16, 10), Vector2(21, 7), 1.8], ["seg", Vector2(16, 14), Vector2(21, 17), 1.8], ["seg", Vector2(21, 7), Vector2(21, 17), 1.8]],
	"import": [["seg", Vector2(12, 3), Vector2(12, 14), 2.0], ["seg", Vector2(7, 9), Vector2(12, 14), 2.0], ["seg", Vector2(17, 9), Vector2(12, 14), 2.0],
		["seg", Vector2(4, 15), Vector2(4, 20), 1.8], ["seg", Vector2(4, 20), Vector2(20, 20), 1.8], ["seg", Vector2(20, 20), Vector2(20, 15), 1.8]],
	"turn_r": [["arc", Vector2(12, 12), 7.5, 2.0, -60, 210], ["seg", Vector2(19.5, 5), Vector2(18.5, 10), 2.0], ["seg", Vector2(18.5, 10), Vector2(13.5, 9), 2.0]],
	"turn_l": [["arc", Vector2(12, 12), 7.5, 2.0, -30, 240], ["seg", Vector2(4.5, 5), Vector2(5.5, 10), 2.0], ["seg", Vector2(5.5, 10), Vector2(10.5, 9), 2.0]],
	"delete": [["box", Rect2(7, 8, 10, 13), 1.6], ["seg", Vector2(5, 7), Vector2(19, 7), 1.8], ["seg", Vector2(10, 4), Vector2(14, 4), 1.8],
		["seg", Vector2(10, 11), Vector2(10, 18), 1.4], ["seg", Vector2(14, 11), Vector2(14, 18), 1.4]],
	"sit_down": [["disc", Vector2(11, 5), 2.4], ["seg", Vector2(11, 8), Vector2(11, 15), 2.2], ["seg", Vector2(11, 15), Vector2(18, 15), 2.0], ["seg", Vector2(18, 15), Vector2(18, 21), 2.0],
		["seg", Vector2(4, 5), Vector2(4, 15), 1.8], ["seg", Vector2(4, 15), Vector2(1.8, 12.5), 1.8], ["seg", Vector2(4, 15), Vector2(6.2, 12.5), 1.8]],
	"stand_up": [["disc", Vector2(13, 4), 2.4], ["seg", Vector2(13, 7), Vector2(13, 14), 2.2], ["seg", Vector2(13, 14), Vector2(10, 21), 2.0], ["seg", Vector2(13, 14), Vector2(16, 21), 2.0],
		["seg", Vector2(4, 20), Vector2(4, 8), 1.8], ["seg", Vector2(4, 8), Vector2(1.8, 10.5), 1.8], ["seg", Vector2(4, 8), Vector2(6.2, 10.5), 1.8]],
	"get_up": [["seg", Vector2(2, 21), Vector2(22, 21), 1.8], ["disc", Vector2(9, 6), 2.4], ["seg", Vector2(9, 9), Vector2(12, 15), 2.2], ["seg", Vector2(12, 15), Vector2(17, 16), 2.0],
		["seg", Vector2(17, 16), Vector2(17, 20), 2.0], ["seg", Vector2(10, 10), Vector2(13, 17), 1.8], ["seg", Vector2(13, 17), Vector2(13, 20), 1.8]],
	"sit": [["seg", Vector2(7, 3), Vector2(7, 21), 1.8], ["seg", Vector2(7, 13), Vector2(18, 13), 1.8], ["seg", Vector2(18, 13), Vector2(18, 21), 1.8],
		["disc", Vector2(13, 7), 2.4]],
	"step": [["seg", Vector2(3, 20), Vector2(9, 20), 1.8], ["seg", Vector2(9, 20), Vector2(9, 14), 1.8], ["seg", Vector2(9, 14), Vector2(15, 14), 1.8],
		["seg", Vector2(15, 14), Vector2(15, 8), 1.8], ["seg", Vector2(15, 8), Vector2(21, 8), 1.8]],
	"take": [["seg", Vector2(5, 20), Vector2(19, 20), 1.8], ["seg", Vector2(8, 13), Vector2(16, 13), 1.8], ["seg", Vector2(8, 13), Vector2(8, 20), 1.8],
		["seg", Vector2(16, 13), Vector2(16, 20), 1.8], ["seg", Vector2(12, 10), Vector2(12, 3), 1.8], ["seg", Vector2(12, 3), Vector2(9, 6), 1.8], ["seg", Vector2(12, 3), Vector2(15, 6), 1.8]],
	"put": [["seg", Vector2(5, 20), Vector2(19, 20), 1.8], ["seg", Vector2(8, 11), Vector2(16, 11), 1.8], ["seg", Vector2(8, 11), Vector2(8, 17), 1.8],
		["seg", Vector2(16, 11), Vector2(16, 17), 1.8], ["seg", Vector2(8, 17), Vector2(16, 17), 1.8], ["seg", Vector2(12, 2), Vector2(12, 8), 1.8], ["seg", Vector2(12, 8), Vector2(9, 5), 1.8], ["seg", Vector2(12, 8), Vector2(15, 5), 1.8]],
	"air": [["seg", Vector2(2, 21), Vector2(22, 21), 1.8], ["seg", Vector2(4, 19.0), Vector2(6, 12.9), 1.6], ["seg", Vector2(6, 12.9), Vector2(8, 8.5), 1.6], ["seg", Vector2(8, 8.5), Vector2(10, 5.9), 1.6], ["seg", Vector2(10, 5.9), Vector2(12, 5.0), 1.6], ["seg", Vector2(12, 5.0), Vector2(14, 5.9), 1.6], ["seg", Vector2(14, 5.9), Vector2(16, 8.5), 1.6], ["seg", Vector2(16, 8.5), Vector2(18, 12.9), 1.6], ["seg", Vector2(18, 12.9), Vector2(20, 19.0), 1.6]],
	"close": [["seg", Vector2(6, 6), Vector2(18, 18), 2.0], ["seg", Vector2(18, 6), Vector2(6, 18), 2.0]],
	"collision": [["ring", Vector2(9, 12), 6, 1.8], ["ring", Vector2(15, 12), 6, 1.8]],
	"trail": [["disc", Vector2(3, 19), 1.4], ["disc", Vector2(5.5, 13.5), 1.6], ["disc", Vector2(9.5, 8.5), 1.8], ["disc", Vector2(15, 5.5), 2.0], ["disc", Vector2(21, 4.5), 2.4]],
	"nextpose": [["disc", Vector2(7, 7), 2.6], ["seg", Vector2(7, 10), Vector2(7, 19), 1.8], ["ring", Vector2(16, 7), 2.6, 1.3], ["seg", Vector2(16, 10), Vector2(18.5, 19), 1.4], ["seg", Vector2(11, 14), Vector2(14, 14), 1.4]],
	"keep_balance": [["disc", Vector2(13, 4), 2.4], ["seg", Vector2(13, 7), Vector2(10, 14), 1.8], ["seg", Vector2(12, 9), Vector2(21, 8), 1.6], ["seg", Vector2(10, 14), Vector2(7, 20), 1.6], ["seg", Vector2(10, 14), Vector2(14, 20), 1.6], ["seg", Vector2(4, 21), Vector2(17, 21), 1.6]],   # N066: arm out, hips the other way, over the feet
	"red_spots": [["disc", Vector2(12, 4), 2.4], ["seg", Vector2(12, 7), Vector2(12, 15), 1.8], ["seg", Vector2(12, 9), Vector2(6, 13), 1.6], ["seg", Vector2(12, 9), Vector2(18, 13), 1.6], ["seg", Vector2(12, 15), Vector2(8, 21), 1.6], ["seg", Vector2(12, 15), Vector2(16, 21), 1.6], ["ring", Vector2(18, 13), 3.2, 1.6]],   # N074: a body with a ringed spot on the hand
	"ouch": [["ring", Vector2(12, 12), 9, 1.9], ["seg", Vector2(12, 6.5), Vector2(12, 13.5), 2.4], ["disc", Vector2(12, 17.2), 1.5]],   # N064: a ringed "!" (the joint glows when it hurts)
	"balance": [["seg", Vector2(12, 3), Vector2(12, 17), 1.6], ["disc", Vector2(12, 5), 2.6], ["ring", Vector2(12, 19), 9, 1.4], ["seg", Vector2(9, 19), Vector2(15, 19), 1.6]],
	"force": [["seg", Vector2(5, 19), Vector2(12, 11), 1.8], ["seg", Vector2(12, 11), Vector2(19, 5), 1.8], ["disc", Vector2(12, 11), 2.8], ["seg", Vector2(19, 5), Vector2(19, 11), 1.6], ["seg", Vector2(19, 5), Vector2(13, 5), 1.6]],
	"autokey": [["ring", Vector2(12, 12), 8.5, 2.0], ["disc", Vector2(12, 12), 4.5]],
	"weights": [["disc", Vector2(6, 17), 3.4], ["disc", Vector2(12, 12), 4.6], ["ring", Vector2(18, 6), 3.0, 1.4]],
	"onion": [["ring", Vector2(6.5, 12), 4.5, 1.2], ["ring", Vector2(12, 12), 4.5, 1.6], ["disc", Vector2(17.5, 12), 4.5]],
	"spacing": [["seg", Vector2(2, 19), Vector2(22, 19), 1.2], ["disc", Vector2(3, 12), 1.7], ["disc", Vector2(6, 12), 1.7], ["disc", Vector2(9.5, 12), 1.7],
		["disc", Vector2(14.5, 12), 1.7], ["disc", Vector2(21, 12), 1.7]],
	"graph": [["seg", Vector2(3, 3), Vector2(3, 21), 1.5], ["seg", Vector2(3, 21), Vector2(22, 21), 1.5], ["seg", Vector2(5, 17), Vector2(10, 16), 1.8],
		["seg", Vector2(10, 16), Vector2(13, 5), 1.8], ["seg", Vector2(13, 5), Vector2(16, 16), 1.8], ["seg", Vector2(16, 16), Vector2(21, 15), 1.8]],
	"stepped": [["seg", Vector2(3, 20), Vector2(8, 20), 2], ["seg", Vector2(8, 20), Vector2(8, 14), 2], ["seg", Vector2(8, 14), Vector2(14, 14), 2],
		["seg", Vector2(14, 14), Vector2(14, 8), 2], ["seg", Vector2(14, 8), Vector2(21, 8), 2]],
	"holds": [["arc", Vector2(7, 14), 4, 2, 180, 360], ["arc", Vector2(15, 10), 4, 2, 0, 180], ["seg", Vector2(19, 10), Vector2(22, 10), 2], ["seg", Vector2(2, 14), Vector2(3, 14), 2]],
	"tools": [["seg", Vector2(4, 6), Vector2(20, 6), 2], ["seg", Vector2(4, 12), Vector2(20, 12), 2], ["seg", Vector2(4, 18), Vector2(20, 18), 2]],
	"physical": [["seg", Vector2(12, 3), Vector2(12, 14), 2.4], ["seg", Vector2(7, 9), Vector2(12, 14), 2.0], ["seg", Vector2(17, 9), Vector2(12, 14), 2.0], ["seg", Vector2(3, 20), Vector2(21, 20), 2.0]],
	"physical_ok": [["seg", Vector2(3, 20), Vector2(21, 20), 2.0], ["seg", Vector2(6, 11), Vector2(10.5, 15.5), 2.6], ["seg", Vector2(10.5, 15.5), Vector2(19, 4), 2.6]],
	"check": [["seg", Vector2(4, 13), Vector2(9.5, 18.5), 2.6], ["seg", Vector2(9.5, 18.5), Vector2(20, 6), 2.6]],
	"match_timing": [["seg", Vector2(3, 7), Vector2(21, 7), 1.4], ["seg", Vector2(3, 17), Vector2(21, 17), 1.4], ["disc", Vector2(7, 7), 2.2], ["disc", Vector2(14, 7), 2.2], ["disc", Vector2(10, 17), 2.2], ["seg", Vector2(7, 7), Vector2(10, 17), 1.2], ["seg", Vector2(14, 7), Vector2(17, 17), 1.2]],
	"style_dial": [["seg", Vector2(4, 8), Vector2(20, 8), 1.6], ["seg", Vector2(4, 16), Vector2(20, 16), 1.6], ["disc", Vector2(9, 8), 2.6], ["disc", Vector2(15, 16), 2.6]],
	"realism": [["arc", Vector2(12, 15), 8, 2.0, 180, 360], ["seg", Vector2(12, 15), Vector2(17, 8), 2.2], ["disc", Vector2(12, 15), 1.8], ["seg", Vector2(4, 20), Vector2(20, 20), 1.8]],
	"learned": [["ring", Vector2(12, 10), 6, 1.8], ["seg", Vector2(9, 19), Vector2(15, 19), 2.0], ["seg", Vector2(10, 22), Vector2(14, 22), 2.0]],
	"timing": [["ring", Vector2(12, 13), 8, 1.8], ["seg", Vector2(12, 13), Vector2(12, 8), 2.0], ["seg", Vector2(12, 13), Vector2(16, 15), 2.0], ["seg", Vector2(9, 3), Vector2(15, 3), 2.0]],
	"fightbeat": [["seg", Vector2(4, 20), Vector2(4, 5), 2.0], ["seg", Vector2(12, 20), Vector2(12, 5), 2.0], ["seg", Vector2(20, 20), Vector2(20, 5), 2.0], ["ring", Vector2(12, 12), 4, 2.4]],
	"choreo_song": [["seg", Vector2(3, 20), Vector2(3, 14), 2.0], ["seg", Vector2(8, 20), Vector2(8, 6), 2.0], ["seg", Vector2(13, 20), Vector2(13, 11), 2.0], ["seg", Vector2(18, 20), Vector2(18, 3), 2.0], ["ring", Vector2(21, 9), 2, 2.0]],
	"mystyle": [["seg", Vector2(4, 20), Vector2(4, 14), 2.0], ["seg", Vector2(9, 20), Vector2(9, 8), 2.0], ["seg", Vector2(14, 20), Vector2(14, 11), 2.0], ["seg", Vector2(19, 20), Vector2(19, 4), 2.0]],
	"usestyle": [["seg", Vector2(3, 8), Vector2(21, 8), 1.6], ["seg", Vector2(3, 16), Vector2(21, 16), 1.6], ["disc", Vector2(15, 8), 2.6], ["disc", Vector2(9, 16), 2.6], ["seg", Vector2(12, 3), Vector2(12, 6), 1.6]],
	"star_clip": [["seg", Vector2(12, 3), Vector2(15, 10), 1.8], ["seg", Vector2(15, 10), Vector2(22, 10), 1.8], ["seg", Vector2(22, 10), Vector2(16.5, 14.5), 1.8], ["seg", Vector2(16.5, 14.5), Vector2(18.5, 21), 1.8], ["seg", Vector2(18.5, 21), Vector2(12, 17), 1.8], ["seg", Vector2(12, 17), Vector2(5.5, 21), 1.8], ["seg", Vector2(5.5, 21), Vector2(7.5, 14.5), 1.8], ["seg", Vector2(7.5, 14.5), Vector2(2, 10), 1.8], ["seg", Vector2(2, 10), Vector2(9, 10), 1.8], ["seg", Vector2(9, 10), Vector2(12, 3), 1.8]],
	"speed_env": [["seg", Vector2(3, 18), Vector2(12, 18), 2.0], ["seg", Vector2(12, 18), Vector2(19, 6), 2.0], ["seg", Vector2(19, 6), Vector2(21, 11), 2.0], ["seg", Vector2(19, 6), Vector2(14, 7), 2.0], ["seg", Vector2(3, 22), Vector2(21, 22), 1.5]],
	"best_take": [["seg", Vector2(4, 20), Vector2(4, 12), 2.0], ["seg", Vector2(10, 20), Vector2(10, 5), 2.0], ["seg", Vector2(16, 20), Vector2(16, 10), 2.0], ["seg", Vector2(21, 20), Vector2(21, 14), 2.0], ["disc", Vector2(10, 3), 1.8]],
	"best_nudge": [["seg", Vector2(4, 16), Vector2(18, 16), 1.8], ["seg", Vector2(4, 8), Vector2(12, 8), 1.8], ["seg", Vector2(12, 8), Vector2(18, 12), 1.8], ["seg", Vector2(18, 12), Vector2(14, 12), 1.8], ["seg", Vector2(18, 12), Vector2(17, 8), 1.8]],
	"combos": [["disc", Vector2(5, 14), 2.6], ["disc", Vector2(12, 8), 2.6], ["disc", Vector2(19, 14), 2.6], ["seg", Vector2(5, 14), Vector2(12, 8), 1.6], ["seg", Vector2(12, 8), Vector2(19, 14), 1.6]],
	"weapon_weight": [["seg", Vector2(3, 12), Vector2(21, 12), 1.8], ["seg", Vector2(6, 6), Vector2(6, 18), 2.6], ["seg", Vector2(18, 6), Vector2(18, 18), 2.6], ["seg", Vector2(3, 9), Vector2(3, 15), 2.0], ["seg", Vector2(21, 9), Vector2(21, 15), 2.0]],
	"parry": [["seg", Vector2(4, 20), Vector2(15, 5), 2.4], ["seg", Vector2(20, 20), Vector2(9, 5), 2.4], ["arc", Vector2(12, 12), 8.5, 1.6, 200, 340]],
	"rhythm": [["seg", Vector2(3, 18), Vector2(3, 10), 2.0], ["seg", Vector2(8, 18), Vector2(8, 5), 2.0], ["seg", Vector2(14, 18), Vector2(14, 12), 2.0], ["seg", Vector2(21, 18), Vector2(21, 7), 2.0]],
	"sound_cues": [["seg", Vector2(3, 10), Vector2(3, 14), 2.0], ["seg", Vector2(8, 6), Vector2(8, 18), 2.0], ["seg", Vector2(13, 3), Vector2(13, 21), 2.0], ["seg", Vector2(18, 7), Vector2(18, 17), 2.0], ["disc", Vector2(22, 12), 1.5]],
	"momentum": [["disc", Vector2(5, 12), 2.8], ["seg", Vector2(9, 12), Vector2(17, 12), 2.0], ["seg", Vector2(14, 8), Vector2(17, 12), 2.0], ["seg", Vector2(14, 16), Vector2(17, 12), 2.0], ["seg", Vector2(21, 4), Vector2(21, 20), 2.4]],
	"spin": [["ring", Vector2(12, 12), 4, 2.0], ["seg", Vector2(3, 20), Vector2(9, 8), 1.6], ["seg", Vector2(9, 8), Vector2(15, 8), 1.6], ["seg", Vector2(15, 8), Vector2(21, 20), 1.6]],
	"mocapchk": [["disc", Vector2(12, 4), 2.4], ["seg", Vector2(12, 6), Vector2(12, 14), 2.0], ["seg", Vector2(12, 9), Vector2(6, 12), 1.8], ["seg", Vector2(12, 9), Vector2(18, 12), 1.8], ["seg", Vector2(12, 14), Vector2(8, 21), 1.8], ["seg", Vector2(12, 14), Vector2(16, 21), 1.8]],
	"keep": [["seg", Vector2(7, 3), Vector2(17, 3), 2.4], ["seg", Vector2(9, 3), Vector2(9, 13), 2.2], ["seg", Vector2(15, 3), Vector2(15, 13), 2.2], ["seg", Vector2(5, 13), Vector2(19, 13), 2.4], ["seg", Vector2(12, 13), Vector2(12, 21), 2.2]],
	"fatigue": [["seg", Vector2(3, 20), Vector2(21, 20), 2.0], ["seg", Vector2(5, 20), Vector2(5, 15), 3.0], ["seg", Vector2(10, 20), Vector2(10, 11), 3.0], ["seg", Vector2(15, 20), Vector2(15, 7), 3.0], ["seg", Vector2(20, 20), Vector2(20, 3), 3.0]],
	"autoopp": [["ring", Vector2(7, 8), 3.2, 1.8], ["seg", Vector2(7, 11), Vector2(7, 19), 2.0], ["seg", Vector2(17, 5), Vector2(17, 19), 2.0], ["seg", Vector2(11, 12), Vector2(20, 12), 1.6]],
	"precog": [["ring", Vector2(12, 12), 8, 2.0], ["seg", Vector2(12, 12), Vector2(12, 6), 2.0], ["seg", Vector2(12, 12), Vector2(16, 14), 2.0]],
	"keeper": [["seg", Vector2(3, 12), Vector2(21, 12), 2.0], ["seg", Vector2(3, 7), Vector2(3, 17), 2.0], ["seg", Vector2(21, 7), Vector2(21, 17), 2.0], ["disc", Vector2(12, 12), 2.6]],
	"arena": [["seg", Vector2(3, 3), Vector2(21, 3), 2.0], ["seg", Vector2(21, 3), Vector2(21, 21), 2.0], ["seg", Vector2(21, 21), Vector2(3, 21), 2.0], ["seg", Vector2(3, 21), Vector2(3, 3), 2.0], ["disc", Vector2(12, 12), 3.0]],
	"breakfall": [["seg", Vector2(3, 5), Vector2(11, 13), 2.0], ["seg", Vector2(11, 13), Vector2(21, 13), 2.0], ["disc", Vector2(3, 4), 2.6], ["seg", Vector2(3, 20), Vector2(21, 20), 1.6]],
	"recovery": [["seg", Vector2(4, 19), Vector2(10, 19), 2.0], ["seg", Vector2(10, 19), Vector2(10, 11), 2.0], ["seg", Vector2(10, 11), Vector2(7, 5), 2.0], ["ring", Vector2(18, 18), 3.0, 1.8], ["seg", Vector2(11, 15), Vector2(15, 17), 1.6]],
	"reactdir": [["seg", Vector2(3, 18), Vector2(13, 12), 2.0], ["seg", Vector2(13, 12), Vector2(10, 12), 2.0], ["seg", Vector2(13, 12), Vector2(12, 15), 2.0], ["seg", Vector2(21, 6), Vector2(15, 9), 2.0], ["disc", Vector2(13, 12), 2.0]],
	"gaze": [["seg", Vector2(2, 12), Vector2(10, 7), 1.8], ["seg", Vector2(2, 12), Vector2(10, 17), 1.8], ["disc", Vector2(7, 12), 2.2], ["seg", Vector2(11, 12), Vector2(22, 12), 1.8], ["disc", Vector2(21, 12), 2.2]],
	"sellhit": [["seg", Vector2(3, 6), Vector2(15, 6), 2.0], ["seg", Vector2(15, 6), Vector2(15, 18), 2.0], ["seg", Vector2(15, 18), Vector2(3, 18), 2.0], ["seg", Vector2(3, 18), Vector2(3, 6), 2.0], ["disc", Vector2(18, 12), 3.0]],
	"safety": [["seg", Vector2(12, 3), Vector2(20, 7), 2.0], ["seg", Vector2(20, 7), Vector2(19, 15), 2.0], ["seg", Vector2(19, 15), Vector2(12, 21), 2.0], ["seg", Vector2(12, 21), Vector2(5, 15), 2.0], ["seg", Vector2(5, 15), Vector2(4, 7), 2.0], ["seg", Vector2(4, 7), Vector2(12, 3), 2.0], ["seg", Vector2(12, 8), Vector2(12, 14), 2.0], ["disc", Vector2(12, 17), 1.2]],
	"floorplan": [["seg", Vector2(3, 3), Vector2(21, 3), 1.6], ["seg", Vector2(21, 3), Vector2(21, 21), 1.6], ["seg", Vector2(21, 21), Vector2(3, 21), 1.6], ["seg", Vector2(3, 21), Vector2(3, 3), 1.6], ["disc", Vector2(8, 16), 2.4], ["disc", Vector2(14, 10), 2.4], ["seg", Vector2(8, 16), Vector2(14, 10), 1.2], ["seg", Vector2(14, 10), Vector2(19, 6), 1.6]],
	"mycam": [["seg", Vector2(3, 7), Vector2(15, 7), 2.0], ["seg", Vector2(15, 7), Vector2(15, 17), 2.0], ["seg", Vector2(15, 17), Vector2(3, 17), 2.0], ["seg", Vector2(3, 17), Vector2(3, 7), 2.0], ["disc", Vector2(9, 12), 2.2], ["seg", Vector2(18, 5), Vector2(21, 5), 1.6], ["seg", Vector2(18, 19), Vector2(21, 19), 1.6], ["seg", Vector2(19.5, 5), Vector2(19.5, 19), 1.6]],
	"frameit": [["seg", Vector2(4, 8), Vector2(4, 4), 2.0], ["seg", Vector2(4, 4), Vector2(8, 4), 2.0], ["seg", Vector2(16, 4), Vector2(20, 4), 2.0], ["seg", Vector2(20, 4), Vector2(20, 8), 2.0], ["seg", Vector2(20, 16), Vector2(20, 20), 2.0], ["seg", Vector2(20, 20), Vector2(16, 20), 2.0], ["seg", Vector2(8, 20), Vector2(4, 20), 2.0], ["seg", Vector2(4, 20), Vector2(4, 16), 2.0], ["disc", Vector2(12, 12), 2.6]],
	"autocam": [["seg", Vector2(3, 7), Vector2(15, 7), 2.0], ["seg", Vector2(15, 7), Vector2(15, 17), 2.0], ["seg", Vector2(15, 17), Vector2(3, 17), 2.0], ["seg", Vector2(3, 17), Vector2(3, 7), 2.0], ["seg", Vector2(15, 12), Vector2(21, 8), 2.0], ["seg", Vector2(21, 8), Vector2(21, 16), 2.0], ["seg", Vector2(21, 16), Vector2(15, 12), 2.0]],
	"polish": [["seg", Vector2(10, 2), Vector2(10, 18), 1.6], ["seg", Vector2(2, 10), Vector2(18, 10), 1.6], ["seg", Vector2(5, 5), Vector2(15, 15), 1.2],
		["seg", Vector2(15, 5), Vector2(5, 15), 1.2], ["disc", Vector2(19, 19), 1.8]],
	"fix": [["disc", Vector2(12, 14), 4.5], ["arc", Vector2(12, 14), 8, 2, 180, 360], ["seg", Vector2(20, 14), Vector2(17.5, 10.5), 2], ["seg", Vector2(20, 14), Vector2(22.5, 10.5), 2]],
	"dummy": [["disc", Vector2(9, 4.5), 2.4], ["seg", Vector2(9, 8), Vector2(9, 15), 2.2], ["seg", Vector2(9, 15), Vector2(6, 21), 2], ["seg", Vector2(9, 15), Vector2(12, 21), 2],
		["seg", Vector2(9, 10), Vector2(4, 13), 1.8], ["ring", Vector2(17.5, 11), 4, 1.6], ["disc", Vector2(17.5, 11), 1.3]],
	"front": [["box", Rect2(4, 4, 16, 16), 1.6], ["disc", Vector2(12, 12), 3]],
	"right": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(14, 6, 4, 12), 0]],
	"left": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(6, 6, 4, 12), 0]],
	"top": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(6, 6, 12, 4), 0]],
	"back": [["box", Rect2(4, 4, 16, 16), 1.6], ["ring", Vector2(12, 12), 3, 1.4]],
	"big": [["seg", Vector2(3, 3), Vector2(9, 3), 2], ["seg", Vector2(3, 3), Vector2(3, 9), 2], ["seg", Vector2(21, 3), Vector2(15, 3), 2], ["seg", Vector2(21, 3), Vector2(21, 9), 2],
		["seg", Vector2(3, 21), Vector2(9, 21), 2], ["seg", Vector2(3, 21), Vector2(3, 15), 2], ["seg", Vector2(21, 21), Vector2(15, 21), 2], ["seg", Vector2(21, 21), Vector2(21, 15), 2]],
	"auto_theme": [["ring", Vector2(12, 12), 9, 2], ["seg", Vector2(12, 3), Vector2(12, 21), 2.2], ["disc", Vector2(16.5, 12), 4.5]],
	"api": [["seg", Vector2(8, 5), Vector2(3, 12), 2], ["seg", Vector2(3, 12), Vector2(8, 19), 2], ["seg", Vector2(16, 5), Vector2(21, 12), 2], ["seg", Vector2(21, 12), Vector2(16, 19), 2], ["seg", Vector2(13.5, 6), Vector2(10.5, 18), 1.8]],
	"corrective": [["seg", Vector2(4, 20), Vector2(12, 12), 2.2], ["seg", Vector2(12, 12), Vector2(20, 4), 2.2], ["ring", Vector2(12, 12), 4.5, 1.5]],
	"light": [["disc", Vector2(12, 12), 4], ["seg", Vector2(12, 2), Vector2(12, 5), 1.8], ["seg", Vector2(12, 19), Vector2(12, 22), 1.8], ["seg", Vector2(2, 12), Vector2(5, 12), 1.8],
		["seg", Vector2(19, 12), Vector2(22, 12), 1.8], ["seg", Vector2(5, 5), Vector2(7, 7), 1.8], ["seg", Vector2(17, 17), Vector2(19, 19), 1.8],
		["seg", Vector2(19, 5), Vector2(17, 7), 1.8], ["seg", Vector2(5, 19), Vector2(7, 17), 1.8]],
	"undo": [["arc", Vector2(13, 14), 7, 2.2, 180, 360], ["seg", Vector2(6, 14), Vector2(2.5, 10), 2.2], ["seg", Vector2(6, 14), Vector2(10, 10.5), 2.2]],
	"redo": [["arc", Vector2(11, 14), 7, 2.2, 180, 360], ["seg", Vector2(18, 14), Vector2(21.5, 10), 2.2], ["seg", Vector2(18, 14), Vector2(14, 10.5), 2.2]],
	"history": [["ring", Vector2(13, 12), 8, 2], ["seg", Vector2(13, 12), Vector2(13, 7), 2], ["seg", Vector2(13, 12), Vector2(16.5, 14), 2],
		["seg", Vector2(2, 9), Vector2(5, 12.5), 2], ["seg", Vector2(5, 12.5), Vector2(8, 9.5), 2]],
	"size": [["box", Rect2(2, 12, 8, 8), 1.6], ["box", Rect2(11, 4, 11, 16), 1.8], ["seg", Vector2(5, 9), Vector2(9, 5), 1.4], ["seg", Vector2(9, 5), Vector2(9, 8), 1.4]],
	"search": [["ring", Vector2(10, 10), 6, 2.2], ["seg", Vector2(14.5, 14.5), Vector2(21, 21), 2.8]],
	# the Browser's per-part buttons (round 30, KK1): shown / hidden, locked / free
	"eye": [["arc", Vector2(12, 22), 13, 2, 226, 314], ["arc", Vector2(12, 3.2), 13, 2, 46, 134], ["disc", Vector2(12, 12.5), 3.2]],
	"eye_off": [["arc", Vector2(12, 22), 13, 2, 226, 314], ["arc", Vector2(12, 3.2), 13, 2, 46, 134], ["disc", Vector2(12, 12.5), 3.2],
		["seg", Vector2(4, 21), Vector2(20, 4), 2.2]],
	"lock": [["box", Rect2(5, 11, 14, 10), 0], ["arc", Vector2(12, 11), 5, 2.2, 180, 360]],
	"unlock": [["box", Rect2(5, 11, 14, 10), 0], ["arc", Vector2(12, 8), 5, 2.2, 180, 330], ["seg", Vector2(7, 8), Vector2(7, 11), 2.2]],
	"contact": [["ring", Vector2(12, 16), 8, 1.6], ["disc", Vector2(12, 16), 4.5], ["seg", Vector2(9, 6), Vector2(9, 11), 2.2], ["seg", Vector2(15, 6), Vector2(15, 11), 2.2]],
	"hints": [["ring", Vector2(12, 10), 7.5, 1.8], ["seg", Vector2(8, 16), Vector2(5, 22), 1.8], ["seg", Vector2(5, 22), Vector2(12.5, 17.5), 1.8],
		["disc", Vector2(12, 7), 1.3], ["seg", Vector2(12, 10), Vector2(12, 13.5), 1.8]],
	"export": [["seg", Vector2(12, 3), Vector2(12, 14), 2.2], ["seg", Vector2(7.5, 8.5), Vector2(12, 3), 2.2], ["seg", Vector2(16.5, 8.5), Vector2(12, 3), 2.2],
		["seg", Vector2(3, 13), Vector2(3, 21), 2.2], ["seg", Vector2(21, 13), Vector2(21, 21), 2.2], ["seg", Vector2(3, 21), Vector2(21, 21), 2.2]],
	# SHARE BY QR (ROADMAP R26): the three corner squares of a QR code; open = the same with an arrow coming in
	# HIT REACTION PICKER (ROADMAP R16): a fighter (head, body) knocked back from a burst on the left
	"react": [["seg", Vector2(3, 8), Vector2(8, 11), 2], ["seg", Vector2(3, 14), Vector2(8, 13), 2], ["seg", Vector2(4, 19), Vector2(8, 15), 2],
		["disc", Vector2(17, 5.5), 2.6], ["seg", Vector2(15, 9), Vector2(11, 14), 2.2], ["seg", Vector2(11, 14), Vector2(10, 21), 2.2], ["seg", Vector2(15, 9), Vector2(21, 12), 2], ["seg", Vector2(11, 14), Vector2(17, 20), 2.2]],
	# I2 REACT TO THE HIT (PHYSICS): an impact star on the left, a head knocked back with a bend of the neck
	"react_hit": [["seg", Vector2(2, 12), Vector2(8, 12), 2], ["seg", Vector2(3, 7), Vector2(7.5, 9.5), 2], ["seg", Vector2(3, 17), Vector2(7.5, 14.5), 2],
		["ring", Vector2(16, 8), 3.4, 2], ["seg", Vector2(13.5, 11), Vector2(11.5, 20), 2.2], ["seg", Vector2(13.5, 11), Vector2(20, 14), 2], ["seg", Vector2(11.5, 20), Vector2(17.5, 21), 2]],
	# I27 THROW AND CATCH: a dotted arc from a start dot to a ring (the catch)
	"throw": [["disc", Vector2(4, 18), 2.2], ["disc", Vector2(8, 10), 1.5], ["disc", Vector2(12, 7), 1.5], ["disc", Vector2(16, 9), 1.5], ["ring", Vector2(19, 16), 3.2, 2]],
	# I13 IMPACT FRAMES: a burst of rays round a point (the freeze); the off one has a bar across it
	"impact": [["disc", Vector2(12, 12), 2.6], ["seg", Vector2(12, 3), Vector2(12, 7), 2], ["seg", Vector2(12, 17), Vector2(12, 21), 2], ["seg", Vector2(3, 12), Vector2(7, 12), 2],
		["seg", Vector2(17, 12), Vector2(21, 12), 2], ["seg", Vector2(5.5, 5.5), Vector2(8.5, 8.5), 2], ["seg", Vector2(15.5, 15.5), Vector2(18.5, 18.5), 2], ["seg", Vector2(18.5, 5.5), Vector2(15.5, 8.5), 2], ["seg", Vector2(8.5, 15.5), Vector2(5.5, 18.5), 2]],
	"impact_off": [["disc", Vector2(12, 12), 2.6], ["seg", Vector2(12, 3), Vector2(12, 7), 2], ["seg", Vector2(12, 17), Vector2(12, 21), 2], ["seg", Vector2(3, 12), Vector2(7, 12), 2],
		["seg", Vector2(17, 12), Vector2(21, 12), 2], ["seg", Vector2(3, 21), Vector2(21, 3), 2.4]],
	"pack": [["box", Rect2(4, 8, 16, 12), 1.8], ["seg", Vector2(12, 8), Vector2(12, 20), 1.6], ["seg", Vector2(12, 3), Vector2(12, 12), 2], ["seg", Vector2(8.5, 8.5), Vector2(12, 12), 2], ["seg", Vector2(15.5, 8.5), Vector2(12, 12), 2]],
	"unpack": [["box", Rect2(4, 8, 16, 12), 1.8], ["seg", Vector2(12, 8), Vector2(12, 20), 1.6], ["seg", Vector2(12, 12), Vector2(12, 2), 2], ["seg", Vector2(8.5, 5.5), Vector2(12, 2), 2], ["seg", Vector2(15.5, 5.5), Vector2(12, 2), 2]],
	"qr": [["box", Rect2(3, 3, 7, 7), 1.8], ["box", Rect2(14, 3, 7, 7), 1.8], ["box", Rect2(3, 14, 7, 7), 1.8], ["box", Rect2(5.5, 5.5, 2, 2), 0],
		["box", Rect2(16.5, 5.5, 2, 2), 0], ["box", Rect2(5.5, 16.5, 2, 2), 0], ["box", Rect2(14, 14, 3, 3), 0], ["box", Rect2(18, 18, 3, 3), 0]],
	"qr_open": [["box", Rect2(3, 3, 7, 7), 1.8], ["box", Rect2(14, 3, 7, 7), 1.8], ["box", Rect2(3, 14, 7, 7), 1.8], ["box", Rect2(5.5, 5.5, 2, 2), 0],
		["box", Rect2(16.5, 5.5, 2, 2), 0], ["box", Rect2(5.5, 16.5, 2, 2), 0], ["seg", Vector2(21, 17.5), Vector2(14, 17.5), 2], ["seg", Vector2(14, 17.5), Vector2(17, 14.5), 2],
		["seg", Vector2(14, 17.5), Vector2(17, 20.5), 2]],
	"export_glb": [["box", Rect2(3, 9, 12, 12), 1.8], ["seg", Vector2(10, 14), Vector2(20, 4), 2], ["seg", Vector2(20, 4), Vector2(14, 4), 2],
		["seg", Vector2(20, 4), Vector2(20, 10), 2]],
	"export_bvh": [["disc", Vector2(6, 5), 2.2], ["seg", Vector2(6, 8), Vector2(6, 15), 2], ["seg", Vector2(6, 15), Vector2(3, 21), 1.8],
		["seg", Vector2(6, 15), Vector2(9, 21), 1.8], ["seg", Vector2(11, 12), Vector2(21, 12), 2], ["seg", Vector2(21, 12), Vector2(17, 8), 2],
		["seg", Vector2(21, 12), Vector2(17, 16), 2]],
	"export_game": [["box", Rect2(2.5, 7, 19, 11), 1.8], ["seg", Vector2(6, 12.5), Vector2(10, 12.5), 1.8], ["seg", Vector2(8, 10.5), Vector2(8, 14.5), 1.8],
		["disc", Vector2(15.5, 11), 1.3], ["disc", Vector2(18, 14), 1.3]],
	"version": [["ring", Vector2(13, 13), 7.5, 1.8], ["seg", Vector2(13, 13), Vector2(13, 8), 1.8], ["seg", Vector2(13, 13), Vector2(16.5, 15), 1.8],
		["arc", Vector2(13, 13), 10.5, 1.4, 150, 250]],
	# frame data / line of action (ROADMAP 12, 23)
	"loa": [["arc", Vector2(12, 12), 11, 2, 100, 260], ["disc", Vector2(15, 3.5), 2], ["disc", Vector2(7, 12), 1.5], ["disc", Vector2(15, 20.5), 1.5]],
	"say_it": [["box", Rect2(3.5, 4.5, 17, 11), 1.8], ["seg", Vector2(8, 15.5), Vector2(7, 20.5), 1.8], ["seg", Vector2(7, 20.5), Vector2(13, 15.5), 1.8], ["seg", Vector2(7.5, 8.5), Vector2(16.5, 8.5), 1.4], ["seg", Vector2(7.5, 11.5), Vector2(13.5, 11.5), 1.4]],
	"sketch_pose": [["ring", Vector2(12, 4.5), 2.5, 1.4], ["seg", Vector2(12, 7), Vector2(12, 14), 1.8], ["seg", Vector2(12, 8.5), Vector2(5, 12), 1.8], ["seg", Vector2(12, 8.5), Vector2(19, 11), 1.8],
		["seg", Vector2(12, 14), Vector2(7, 21), 1.8], ["seg", Vector2(12, 14), Vector2(17, 21), 1.8]],
	"loa_sketch": [["seg", Vector2(4, 20), Vector2(9, 11), 2], ["seg", Vector2(9, 11), Vector2(15, 14), 2], ["seg", Vector2(15, 14), Vector2(20, 4), 2],
		["disc", Vector2(4, 20), 1.6], ["seg", Vector2(17, 17), Vector2(21, 21), 1.8], ["seg", Vector2(21, 17), Vector2(17, 21), 1.8]],
	"fd": [["box", Rect2(2.5, 9, 6, 6), 0], ["box", Rect2(9, 9, 6, 6), 1.6], ["box", Rect2(15.5, 9, 6, 6), 1.6], ["seg", Vector2(3, 19), Vector2(21, 19), 1.4], ["seg", Vector2(3, 5), Vector2(21, 5), 1.4]],
	"fd_boxes": [["box", Rect2(3, 3, 11, 11), 1.8], ["box", Rect2(10, 10, 11, 11), 1.8], ["disc", Vector2(8.5, 8.5), 1.6]],
	"fd_rate": [["ring", Vector2(12, 13), 8, 1.8], ["seg", Vector2(12, 13), Vector2(16, 9), 2], ["seg", Vector2(9, 3), Vector2(15, 3), 2], ["disc", Vector2(12, 13), 1.4]],
	"export_fd": [["box", Rect2(3, 11, 12, 10), 1.8], ["seg", Vector2(6, 14), Vector2(6, 18), 1.6], ["seg", Vector2(9, 14), Vector2(9, 18), 1.6], ["seg", Vector2(12, 14), Vector2(12, 18), 1.6],
		["seg", Vector2(11, 12), Vector2(20, 3), 2], ["seg", Vector2(20, 3), Vector2(14, 3), 2], ["seg", Vector2(20, 3), Vector2(20, 9), 2]],
	# R5: Render shots = a film frame with sprocket lines and a play triangle
	"render_shots": [["box", Rect2(2.5, 5, 19, 14), 1.8], ["seg", Vector2(8, 5), Vector2(8, 19), 1.4], ["seg", Vector2(16, 5), Vector2(16, 19), 1.4],
		["seg", Vector2(10.5, 9), Vector2(10.5, 15), 1.8], ["seg", Vector2(10.5, 9), Vector2(14, 12), 1.8], ["seg", Vector2(10.5, 15), Vector2(14, 12), 1.8]],
	"help": [["arc", Vector2(12, 8.5), 4.5, 2.2, 160, 420], ["seg", Vector2(12, 13), Vector2(12, 16), 2.2], ["disc", Vector2(12, 20.5), 1.5]],
	"whywrong": [["ring", Vector2(12, 12), 9, 2], ["seg", Vector2(12, 6.5), Vector2(12, 13.5), 2.4], ["disc", Vector2(12, 17.5), 1.5]],
	# ROADMAP 54: Mirror scene = a frame and its mirror copy (a dashed axis between); Mirror in place = one frame split by its axis
	"mirror_scene": [["box", Rect2(2.5, 6.5, 7.5, 11), 1.6], ["box", Rect2(14, 6.5, 7.5, 11), 1.6], ["seg", Vector2(12, 3), Vector2(12, 21), 1.2],
		["seg", Vector2(17.5, 18.5), Vector2(19.5, 21), 1.4], ["disc", Vector2(12, 3), 1.2]],
	"pathwalk": [["seg", Vector2(3, 20), Vector2(9, 15), 1.8], ["seg", Vector2(9, 15), Vector2(15, 16), 1.8], ["seg", Vector2(15, 16), Vector2(21, 7), 1.8],
		["disc", Vector2(3, 20), 1.6], ["disc", Vector2(21, 7), 1.6], ["disc", Vector2(10, 7), 2.0], ["seg", Vector2(10, 9), Vector2(10, 12), 1.8]],
	"mirror_inplace": [["box", Rect2(5, 4, 14, 16), 1.6], ["seg", Vector2(12, 2), Vector2(12, 22), 1.2], ["seg", Vector2(9, 9), Vector2(5, 12), 1.6],
		["seg", Vector2(5, 12), Vector2(9, 15), 1.6], ["seg", Vector2(15, 9), Vector2(19, 12), 1.6], ["seg", Vector2(19, 12), Vector2(15, 15), 1.6]],
	# the search box's row kinds (ROADMAP 52, scripts/command_search.gd): a command prompt, a posed figure, a film frame
	"kind_command": [["seg", Vector2(3, 6), Vector2(10, 12), 2.0], ["seg", Vector2(10, 12), Vector2(3, 18), 2.0], ["seg", Vector2(12, 18), Vector2(21, 18), 2.0]],
	"kind_pose": [["disc", Vector2(12, 4.5), 2.6], ["seg", Vector2(12, 8), Vector2(12, 15), 2.4], ["seg", Vector2(12, 9.5), Vector2(5, 13), 2.0],
		["seg", Vector2(12, 9.5), Vector2(19, 4), 2.0], ["seg", Vector2(12, 15), Vector2(8, 22), 2.0], ["seg", Vector2(12, 15), Vector2(16, 22), 2.0]],
	"kind_macro": [["disc", Vector2(7, 12), 4.0], ["seg", Vector2(13, 7), Vector2(21, 7), 2.0], ["seg", Vector2(13, 12), Vector2(21, 12), 2.0], ["seg", Vector2(13, 17), Vector2(21, 17), 2.0]],
	"kind_script": [["seg", Vector2(6, 5), Vector2(6, 19), 2.0], ["seg", Vector2(6, 19), Vector2(18, 19), 2.0], ["seg", Vector2(11, 8), Vector2(19, 8), 2.0], ["seg", Vector2(11, 13), Vector2(17, 13), 2.0]],
	"kind_scene": [["box", Rect2(2, 4, 20, 16), 1.6], ["box", Rect2(6, 7.5, 12, 9), 1.2], ["disc", Vector2(4.5, 6), 0.9], ["disc", Vector2(19.5, 6), 0.9],
		["disc", Vector2(4.5, 18), 0.9], ["disc", Vector2(19.5, 18), 0.9]],
	# EASY HOME (scripts/easy_home.gd): one stick figure per card, 24-unit grid, drawn large by big()
	"walk": [["disc", Vector2(12, 4.5), 2.6], ["seg", Vector2(12, 8), Vector2(12, 15), 2.4], ["seg", Vector2(12, 9.5), Vector2(7, 13), 2.0],
		["seg", Vector2(12, 9.5), Vector2(17, 13), 2.0], ["seg", Vector2(12, 15), Vector2(6.5, 21), 2.2], ["seg", Vector2(12, 15), Vector2(17.5, 21), 2.2]],
	"run": [["disc", Vector2(15, 4.5), 2.6], ["seg", Vector2(14, 8.5), Vector2(11, 15), 2.4], ["seg", Vector2(13, 10), Vector2(20, 11), 2.0],
		["seg", Vector2(13, 10), Vector2(6, 8), 2.0], ["seg", Vector2(11, 15), Vector2(4, 19), 2.2], ["seg", Vector2(11, 15), Vector2(17, 21), 2.2]],
	"jump": [["disc", Vector2(12, 4), 2.6], ["seg", Vector2(12, 8), Vector2(12, 14), 2.4], ["seg", Vector2(12, 9.5), Vector2(6, 3), 2.0],
		["seg", Vector2(12, 9.5), Vector2(18, 3), 2.0], ["seg", Vector2(12, 14), Vector2(7, 18), 2.2], ["seg", Vector2(7, 18), Vector2(10, 22), 2.2],
		["seg", Vector2(12, 14), Vector2(16, 18), 2.2], ["seg", Vector2(16, 18), Vector2(13, 22), 2.2]],
	"punch": [["disc", Vector2(10, 4.5), 2.6], ["seg", Vector2(10, 8), Vector2(10, 15), 2.4], ["seg", Vector2(10, 9.5), Vector2(21, 9.5), 2.2],
		["seg", Vector2(10, 9.5), Vector2(7, 14), 2.0], ["seg", Vector2(10, 15), Vector2(6, 22), 2.2], ["seg", Vector2(10, 15), Vector2(16, 22), 2.2]],
	"kick": [["disc", Vector2(9, 4.5), 2.6], ["seg", Vector2(9, 8), Vector2(9, 15), 2.4], ["seg", Vector2(9, 9.5), Vector2(5, 14), 2.0],
		["seg", Vector2(9, 9.5), Vector2(14, 12), 2.0], ["seg", Vector2(9, 15), Vector2(7, 22), 2.2], ["seg", Vector2(9, 15), Vector2(20, 9), 2.2]],
	"wave": [["disc", Vector2(11, 4.5), 2.6], ["seg", Vector2(11, 8), Vector2(11, 15), 2.4], ["seg", Vector2(11, 9.5), Vector2(19, 2.5), 2.2],
		["seg", Vector2(11, 9.5), Vector2(6, 15), 2.0], ["seg", Vector2(11, 15), Vector2(7, 22), 2.2], ["seg", Vector2(11, 15), Vector2(15, 22), 2.2]],
	"fall": [["disc", Vector2(4.5, 8), 2.6], ["seg", Vector2(7.5, 9.5), Vector2(16, 14), 2.4], ["seg", Vector2(16, 14), Vector2(21, 20), 2.2],
		["seg", Vector2(16, 14), Vector2(20, 21), 2.2], ["seg", Vector2(8.5, 11), Vector2(5, 17), 2.0], ["seg", Vector2(2, 21.5), Vector2(22, 21.5), 1.2]],
	"mesh_cube": [["box", Rect2(3, 9, 12, 12), 1.6], ["box", Rect2(9, 3, 12, 12), 1.6], ["seg", Vector2(3, 9), Vector2(9, 3), 1.4], ["seg", Vector2(15, 9), Vector2(21, 3), 1.4], ["seg", Vector2(15, 21), Vector2(21, 15), 1.4]],
	"body_save": [["ring", Vector2(9, 5), 3, 1.8], ["box", Rect2(5.5, 9.5, 7, 6), 1.8], ["seg", Vector2(17, 4), Vector2(17, 18), 1.8], ["seg", Vector2(13.5, 14.5), Vector2(17, 18), 1.8], ["seg", Vector2(20.5, 14.5), Vector2(17, 18), 1.8]],
	"xf_move": [["seg", Vector2(12, 3), Vector2(12, 21), 1.8], ["seg", Vector2(3, 12), Vector2(21, 12), 1.8], ["seg", Vector2(9, 6), Vector2(12, 3), 1.8], ["seg", Vector2(15, 6), Vector2(12, 3), 1.8], ["seg", Vector2(9, 18), Vector2(12, 21), 1.8], ["seg", Vector2(15, 18), Vector2(12, 21), 1.8], ["seg", Vector2(6, 9), Vector2(3, 12), 1.8], ["seg", Vector2(6, 15), Vector2(3, 12), 1.8], ["seg", Vector2(18, 9), Vector2(21, 12), 1.8], ["seg", Vector2(18, 15), Vector2(21, 12), 1.8]],
	"xf_rot": [["arc", Vector2(12, 12), 8, 2.0, -60, 240], ["seg", Vector2(19.5, 4), Vector2(20, 9), 2.0], ["seg", Vector2(20, 9), Vector2(15, 8.5), 2.0]],
	"xf_scale": [["box", Rect2(3, 12, 8, 8), 1.6], ["seg", Vector2(12, 11), Vector2(20, 3), 1.8], ["seg", Vector2(14, 3), Vector2(20, 3), 1.8], ["seg", Vector2(20, 3), Vector2(20, 9), 1.8]],
	"inset": [["box", Rect2(3, 3, 18, 18), 1.8], ["box", Rect2(8, 8, 8, 8), 1.6]],
	"loopcut": [["box", Rect2(3, 5, 18, 14), 1.6], ["seg", Vector2(8, 5), Vector2(8, 19), 1.4], ["seg", Vector2(14, 5), Vector2(14, 19), 1.4], ["seg", Vector2(3, 12), Vector2(21, 12), 2.2]],
	"knife": [["seg", Vector2(5, 19), Vector2(19, 5), 2.2], ["seg", Vector2(14, 5), Vector2(19, 5), 1.6], ["seg", Vector2(19, 5), Vector2(19, 10), 1.6]],
	"proportional": [["disc", Vector2(12, 12), 3], ["ring", Vector2(12, 12), 7, 1.6], ["ring", Vector2(12, 12), 10.5, 1.2]],
	"stack": [["box", Rect2(3, 4, 18, 4), 1.6], ["box", Rect2(3, 10, 18, 4), 1.6], ["box", Rect2(3, 16, 18, 4), 1.6]],
	"validate": [["box", Rect2(5, 3, 14, 18), 1.6], ["seg", Vector2(8, 9), Vector2(16, 9), 1.3], ["seg", Vector2(8, 13), Vector2(16, 13), 1.3], ["seg", Vector2(8, 17), Vector2(13, 17), 1.3]],
	"wrench": [["seg", Vector2(5, 19), Vector2(14, 10), 3.0], ["ring", Vector2(16, 8), 4.5, 2.2]],
	"sphere": [["ring", Vector2(12, 12), 8.5, 1.8], ["arc", Vector2(12, 12), 5.5, 1.4, 200, 340]],
	# Voxel remesh (1e2500f5): a sphere ring with an even grid of quads inside it, each chord cut at the ring
	"remesh": [["ring", Vector2(12, 12), 8.5, 1.8],
		["seg", Vector2(4.6, 7.75), Vector2(19.4, 7.75), 1.2], ["seg", Vector2(3.5, 12), Vector2(20.5, 12), 1.2], ["seg", Vector2(4.6, 16.25), Vector2(19.4, 16.25), 1.2],
		["seg", Vector2(7.75, 4.6), Vector2(7.75, 19.4), 1.2], ["seg", Vector2(12, 3.5), Vector2(12, 20.5), 1.2], ["seg", Vector2(16.25, 4.6), Vector2(16.25, 19.4), 1.2]],
	"brush_draw": [["seg", Vector2(4, 20), Vector2(14, 10), 2.6], ["disc", Vector2(17, 7), 3.6]],
	"brush_inflate": [["disc", Vector2(12, 12), 5.5], ["seg", Vector2(12, 1), Vector2(12, 4), 1.6], ["seg", Vector2(12, 20), Vector2(12, 23), 1.6], ["seg", Vector2(1, 12), Vector2(4, 12), 1.6], ["seg", Vector2(20, 12), Vector2(23, 12), 1.6]],
	"brush_grab": [["disc", Vector2(12, 15), 4], ["seg", Vector2(8, 10), Vector2(8, 4), 2], ["seg", Vector2(12, 9), Vector2(12, 3), 2], ["seg", Vector2(16, 10), Vector2(16, 4), 2]],
	"brush_clay": [["disc", Vector2(9, 14), 5], ["disc", Vector2(16, 9), 4]],
	"brush_crease": [["seg", Vector2(4, 5), Vector2(12, 19), 2.2], ["seg", Vector2(12, 19), Vector2(20, 5), 2.2]],
	"smooth": [["seg", Vector2(3, 9), Vector2(7, 6), 2], ["seg", Vector2(7, 6), Vector2(12, 10), 2], ["seg", Vector2(12, 10), Vector2(17, 6), 2], ["seg", Vector2(17, 6), Vector2(21, 9), 2], ["seg", Vector2(3, 16), Vector2(7, 13), 2], ["seg", Vector2(7, 13), Vector2(12, 17), 2], ["seg", Vector2(12, 17), Vector2(17, 13), 2], ["seg", Vector2(17, 13), Vector2(21, 16), 2]],
	"brush_flat": [["box", Rect2(3, 11, 18, 6), 0]],
	"brush_pinch": [["seg", Vector2(3, 4), Vector2(10, 12), 2], ["seg", Vector2(3, 20), Vector2(10, 12), 2], ["seg", Vector2(21, 4), Vector2(14, 12), 2], ["seg", Vector2(21, 20), Vector2(14, 12), 2]],
	"brush_snake": [["arc", Vector2(7, 12), 4, 2, 180, 360], ["arc", Vector2(17, 12), 4, 2, 0, 180]],
	"vpaint": [["seg", Vector2(5, 19), Vector2(13, 11), 2.8], ["disc", Vector2(16, 8), 4.5]],
	"uv": [["box", Rect2(3, 4, 11, 11), 1.6], ["box", Rect2(10, 9, 11, 11), 1.6]],
	"uv_game": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(8, 8, 8, 8), 1.4]],
	"uv_pack": [["box", Rect2(3, 3, 8, 8), 1.4], ["box", Rect2(13, 3, 8, 8), 1.4], ["box", Rect2(8, 13, 8, 8), 1.4]],
	"photo_mat": [["box", Rect2(3, 4, 18, 16), 1.6], ["disc", Vector2(8, 9), 2.0], ["seg", Vector2(4, 18), Vector2(10, 12), 1.6], ["seg", Vector2(10, 12), Vector2(14, 16), 1.6], ["seg", Vector2(14, 16), Vector2(21, 10), 1.6]],
	# BODY: SMOOTH (the body's outline with soft, rounded flanks, not the boxy mannequin)
	"body_smooth": [["ring", Vector2(12, 4.5), 2.6, 1.8], ["seg", Vector2(7, 9.5), Vector2(17, 9.5), 1.8], ["seg", Vector2(7, 9.5), Vector2(9, 15), 1.8], ["seg", Vector2(9, 15), Vector2(8.5, 21), 1.8], ["seg", Vector2(17, 9.5), Vector2(15, 15), 1.8], ["seg", Vector2(15, 15), Vector2(15.5, 21), 1.8], ["seg", Vector2(12, 15), Vector2(12, 21), 1.2]],
	# POSE: ONLY THE PART I DRAG (one box lit up, a pointer on it; the rest of the figure is left out)
	"only_part": [["box", Rect2(4, 4, 10, 10), 1.8], ["seg", Vector2(21, 21), Vector2(14.5, 14.5), 2.2], ["seg", Vector2(14.5, 14.5), Vector2(14.5, 19.5), 2.0], ["seg", Vector2(14.5, 14.5), Vector2(19.5, 14.5), 2.0]],
	# EXPORT: USE AS A PROP (a box dropped down onto the floor line)
	"use_prop": [["box", Rect2(7, 3, 10, 8), 1.6], ["seg", Vector2(12, 12), Vector2(12, 18), 2.0], ["seg", Vector2(8.5, 15), Vector2(12, 18.5), 2.0], ["seg", Vector2(15.5, 15), Vector2(12, 18.5), 2.0], ["seg", Vector2(3, 21), Vector2(21, 21), 1.8]],
	# EXPORT: OPEN EXPORTS FOLDER (a folder with its tab, an arrow leaving it)
	"open_folder": [["box", Rect2(3, 5, 8, 3), 1.6], ["box", Rect2(3, 7.5, 18, 13), 1.6], ["seg", Vector2(9, 16), Vector2(15, 10), 1.8], ["seg", Vector2(10.5, 10), Vector2(15, 10), 1.8], ["seg", Vector2(15, 10), Vector2(15, 14.5), 1.8]],
	# VIEW: GRAPHICS QUALITY (three bars climbing: the picture gets finer)
	"gfx": [["box", Rect2(3, 14, 4, 7), 0], ["box", Rect2(10, 10, 4, 11), 0], ["box", Rect2(17, 5, 4, 16), 0]],
	# BODY: MANNEQUIN AS SHIPPED (the mannequin standing on its display plinth)
	"mannequin_ship": [["ring", Vector2(12, 4.5), 2.6, 1.8], ["box", Rect2(8.5, 8.5, 7, 5.5), 1.8], ["seg", Vector2(10, 14), Vector2(10, 18), 1.8], ["seg", Vector2(14, 14), Vector2(14, 18), 1.8], ["seg", Vector2(3.5, 21.5), Vector2(20.5, 21.5), 2.6]],
	# SCULPT: SCULPT THE BODY (a figure's torso with a brush stroke curling over it)
	"sculpt_body": [["ring", Vector2(7, 4.5), 2.2, 1.6], ["box", Rect2(3, 8, 8, 12), 1.6], ["arc", Vector2(16, 14), 4, 2.2, 180, 360], ["seg", Vector2(20, 14), Vector2(20, 20), 2.2]],
	# MODEL: USE IN SCENE (a scene frame with the model put into it from the side)
	"use_scene": [["box", Rect2(3, 4, 18, 15), 1.6], ["box", Rect2(6, 8, 5, 6), 1.4], ["seg", Vector2(21, 21), Vector2(15, 15), 1.9], ["seg", Vector2(15, 15), Vector2(15, 19.5), 1.9], ["seg", Vector2(15, 15), Vector2(19.5, 15), 1.9]],
	# SURFACE: EXPORT UVS (a UV square with its grid, an arrow out of it)
	"uv_export": [["box", Rect2(3, 3, 12, 12), 1.4], ["seg", Vector2(7, 3), Vector2(7, 15), 1.0], ["seg", Vector2(3, 9), Vector2(15, 9), 1.0], ["seg", Vector2(18, 10), Vector2(18, 21), 2.0], ["seg", Vector2(14.5, 17), Vector2(18, 21), 2.0], ["seg", Vector2(21.5, 17), Vector2(18, 21), 2.0]],
	# s219: the Part timeline steps that had no picture (a step kind with no icon errored on every refresh)
	"part_move": [["seg", Vector2(12, 3), Vector2(12, 21), 1.8], ["seg", Vector2(3, 12), Vector2(21, 12), 1.8], ["seg", Vector2(12, 3), Vector2(9, 6.5), 1.8], ["seg", Vector2(12, 3), Vector2(15, 6.5), 1.8], ["seg", Vector2(12, 21), Vector2(9, 17.5), 1.8], ["seg", Vector2(12, 21), Vector2(15, 17.5), 1.8], ["seg", Vector2(3, 12), Vector2(6.5, 9), 1.8], ["seg", Vector2(3, 12), Vector2(6.5, 15), 1.8], ["seg", Vector2(21, 12), Vector2(17.5, 9), 1.8], ["seg", Vector2(21, 12), Vector2(17.5, 15), 1.8]],   # MOVE: a four-way arrow
	"part_lay": [["box", Rect2(3, 13, 18, 7), 1.7], ["arc", Vector2(12, 9), 6, 1.8, 200, 340], ["seg", Vector2(18, 9), Vector2(15.5, 6.5), 1.8], ["seg", Vector2(18, 9), Vector2(20.5, 6.5), 1.8]],   # LAY: a block lying flat, a turn arrow over it
	"part_align": [["seg", Vector2(4, 3), Vector2(4, 21), 1.8], ["box", Rect2(4, 5, 14, 4), 1.6], ["box", Rect2(4, 10, 9, 4), 1.6], ["box", Rect2(4, 15, 17, 4), 1.6]],   # ALIGN: three bars on one edge
	"part_lattice": [["box", Rect2(3.5, 3.5, 17, 17), 1.6], ["seg", Vector2(9.2, 3.5), Vector2(9.2, 20.5), 1.2], ["seg", Vector2(14.8, 3.5), Vector2(14.8, 20.5), 1.2], ["seg", Vector2(3.5, 9.2), Vector2(20.5, 9.2), 1.2], ["seg", Vector2(3.5, 14.8), Vector2(20.5, 14.8), 1.2]],   # LATTICE: a block of cells
	"part_fitobj": [["box", Rect2(3, 3, 18, 18), 1.8], ["ring", Vector2(12, 12), 4.5, 1.8], ["disc", Vector2(12, 12), 1.6]],   # FIT TO AN OBJECT: a holder around a thing
	"part_offset": [["box", Rect2(3, 3, 18, 18), 1.7], ["box", Rect2(8, 8, 8, 8), 1.7]],   # OFFSET: a block and a second skin around it
	"part_meshsolid": [["seg", Vector2(12, 3), Vector2(21, 15), 1.7], ["seg", Vector2(21, 15), Vector2(12, 21), 1.7], ["seg", Vector2(12, 21), Vector2(3, 15), 1.7], ["seg", Vector2(3, 15), Vector2(12, 3), 1.7], ["seg", Vector2(12, 3), Vector2(12, 21), 1.2], ["seg", Vector2(3, 15), Vector2(21, 15), 1.2]],   # MESH SOLID: a faceted gem
	"part_generic": [["box", Rect2(4, 4, 16, 16), 1.7], ["disc", Vector2(12, 12), 3.0]],   # s219: the picture for any step kind that has none yet
}

static var _cache := {}


## the icon at 64 px for a big picture card (Easy home): the same drawing, painted at the larger size
static func big(name: String) -> ImageTexture:
	var k := name + "@64"
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(paint(DRAW[_known(name)], 64))
	return _cache[k]


## the icon as a texture (made once)
static func tex(name: String) -> ImageTexture:
	if not _cache.has(name):
		_cache[name] = ImageTexture.create_from_image(paint(DRAW[_known(name)]))
	return _cache[name]


## the icon at any size (the Piece picker's cards): painted at px, not scaled
static func sized(name: String, px: int) -> ImageTexture:
	var k := "%s@sized%d" % [name, px]
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(paint(DRAW[_known(name)], px))
	return _cache[k]


## the icon at 16 px (the Browser's rows: room for the part's name); scaled down from the 22 px drawing
static func small(name: String) -> ImageTexture:
	var k := name + "@16"
	if not _cache.has(k):
		var img := paint(DRAW[_known(name)])
		img.resize(16, 16, Image.INTERPOLATE_LANCZOS)
		_cache[k] = ImageTexture.create_from_image(img)
	return _cache[k]


static func paint(shapes: Array, px := SIZE) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var k := 24.0 / px   # pixels -> grid units
	for y in px:
		for x in px:
			var p := Vector2(x + 0.5, y + 0.5) * k
			var d := INF
			for s in shapes:
				d = minf(d, dist(s, p))
			var a := clampf(0.5 - d / k, 0.0, 1.0)   # distance in PIXELS: one pixel of soft edge
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## signed distance from p to the shape's ink (negative inside)
static func dist(s: Array, p: Vector2) -> float:
	match s[0]:
		"seg":
			var a: Vector2 = s[1]
			var ab: Vector2 = s[2] - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			return p.distance_to(a + ab * t) - s[3] * 0.5
		"disc":
			return p.distance_to(s[1]) - s[2]
		"ring":
			return absf(p.distance_to(s[1]) - s[2]) - s[3] * 0.5
		"arc":
			var c: Vector2 = s[1]
			var r: float = s[2]
			var a0 := deg_to_rad(s[4])
			var a1 := deg_to_rad(s[5])
			var ang := fposmod(atan2(p.y - c.y, p.x - c.x) - a0, TAU)
			if ang <= a1 - a0:
				return absf(p.distance_to(c) - r) - s[3] * 0.5
			var e0 := c + Vector2(cos(a0), sin(a0)) * r
			var e1 := c + Vector2(cos(a1), sin(a1)) * r
			return minf(p.distance_to(e0), p.distance_to(e1)) - s[3] * 0.5
		"box":
			var r: Rect2 = s[1]
			var q := (p - r.get_center()).abs() - r.size * 0.5
			var out := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			return out if s[2] == 0 else absf(out) - s[2] * 0.5
	return INF


## s219: a name with no drawing gets the generic picture, not a script error
static func _known(name: String) -> String:
	return name if DRAW.has(name) else "part_generic"
