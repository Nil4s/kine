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
	"lit_three": [["disc", Vector2(12, 14), 3.2], ["disc", Vector2(4.5, 6), 2.0], ["disc", Vector2(19.5, 8), 1.4], ["disc", Vector2(12, 3.5), 1.6], ["seg", Vector2(6, 7.2), Vector2(9.6, 11.8), 1.4]],
	"lit_rim": [["ring", Vector2(12, 12), 6.5, 1.6], ["arc", Vector2(12, 12), 9.5, 2.2, 200, 340], ["seg", Vector2(12, 12), Vector2(12, 12.1), 1.0]],
	"lit_noir": [["disc", Vector2(12, 12), 7.5], ["box", Rect2(12, 4.5, 7.5, 15), 0.0], ["seg", Vector2(4, 4), Vector2(8, 8), 1.6]],
	"lit_day": [["disc", Vector2(12, 12), 4.0], ["seg", Vector2(12, 2), Vector2(12, 5), 1.8], ["seg", Vector2(12, 19), Vector2(12, 22), 1.8], ["seg", Vector2(2, 12), Vector2(5, 12), 1.8], ["seg", Vector2(19, 12), Vector2(22, 12), 1.8], ["seg", Vector2(5, 5), Vector2(7, 7), 1.6], ["seg", Vector2(17, 17), Vector2(19, 19), 1.6], ["seg", Vector2(19, 5), Vector2(17, 7), 1.6], ["seg", Vector2(5, 19), Vector2(7, 17), 1.6]],
	"crowd": [["disc", Vector2(6, 6), 2.0], ["disc", Vector2(12, 5), 2.0], ["disc", Vector2(18, 6), 2.0], ["seg", Vector2(6, 9), Vector2(6, 17), 2.0], ["seg", Vector2(12, 8), Vector2(12, 18), 2.0], ["seg", Vector2(18, 9), Vector2(18, 17), 2.0]],
	"reroll": [["arc", Vector2(12, 12), 7.5, 2.2, -60, 210], ["seg", Vector2(19.5, 5), Vector2(18.5, 10), 2.2], ["seg", Vector2(18.5, 10), Vector2(13.5, 9), 2.2], ["disc", Vector2(12, 12), 2.4]],
	"crowd_remove": [["disc", Vector2(12, 5), 2.4], ["seg", Vector2(12, 8), Vector2(12, 16), 2.4], ["seg", Vector2(12, 10), Vector2(5, 15), 2.0], ["seg", Vector2(12, 10), Vector2(19, 15), 2.0], ["seg", Vector2(6, 21), Vector2(18, 21), 2.6]],
	"body_prop": [["seg", Vector2(12, 3), Vector2(12, 21), 1.8], ["seg", Vector2(12, 3), Vector2(8.5, 6.5), 1.8], ["seg", Vector2(12, 3), Vector2(15.5, 6.5), 1.8], ["seg", Vector2(12, 21), Vector2(8.5, 17.5), 1.8], ["seg", Vector2(12, 21), Vector2(15.5, 17.5), 1.8], ["seg", Vector2(17, 8), Vector2(21, 8), 1.6], ["seg", Vector2(17, 16), Vector2(21, 16), 1.6]],
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
	"fit": [["seg", Vector2(3, 8), Vector2(3, 3), 1.8], ["seg", Vector2(3, 3), Vector2(8, 3), 1.8], ["seg", Vector2(16, 3), Vector2(21, 3), 1.8], ["seg", Vector2(21, 3), Vector2(21, 8), 1.8],
		["seg", Vector2(21, 16), Vector2(21, 21), 1.8], ["seg", Vector2(21, 21), Vector2(16, 21), 1.8], ["seg", Vector2(8, 21), Vector2(3, 21), 1.8], ["seg", Vector2(3, 21), Vector2(3, 16), 1.8],
		["box", Rect2(8.5, 8.5, 7, 7), 1.6]],
	"grid": [["seg", Vector2(3, 8), Vector2(21, 8), 1.4], ["seg", Vector2(3, 16), Vector2(21, 16), 1.4], ["seg", Vector2(8, 3), Vector2(8, 21), 1.4],
		["seg", Vector2(16, 3), Vector2(16, 21), 1.4], ["box", Rect2(3, 3, 18, 18), 1.4]],
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
	"style_dial": [["seg", Vector2(4, 8), Vector2(20, 8), 1.6], ["seg", Vector2(4, 16), Vector2(20, 16), 1.6], ["disc", Vector2(9, 8), 2.6], ["disc", Vector2(15, 16), 2.6]],
	"realism": [["arc", Vector2(12, 15), 8, 2.0, 180, 360], ["seg", Vector2(12, 15), Vector2(17, 8), 2.2], ["disc", Vector2(12, 15), 1.8], ["seg", Vector2(4, 20), Vector2(20, 20), 1.8]],
	"learned": [["ring", Vector2(12, 10), 6, 1.8], ["seg", Vector2(9, 19), Vector2(15, 19), 2.0], ["seg", Vector2(10, 22), Vector2(14, 22), 2.0]],
	"timing": [["ring", Vector2(12, 13), 8, 1.8], ["seg", Vector2(12, 13), Vector2(12, 8), 2.0], ["seg", Vector2(12, 13), Vector2(16, 15), 2.0], ["seg", Vector2(9, 3), Vector2(15, 3), 2.0]],
	"fightbeat": [["seg", Vector2(4, 20), Vector2(4, 5), 2.0], ["seg", Vector2(12, 20), Vector2(12, 5), 2.0], ["seg", Vector2(20, 20), Vector2(20, 5), 2.0], ["ring", Vector2(12, 12), 4, 2.4]],
	"choreo_song": [["seg", Vector2(3, 20), Vector2(3, 14), 2.0], ["seg", Vector2(8, 20), Vector2(8, 6), 2.0], ["seg", Vector2(13, 20), Vector2(13, 11), 2.0], ["seg", Vector2(18, 20), Vector2(18, 3), 2.0], ["ring", Vector2(21, 9), 2, 2.0]],
	"mystyle": [["seg", Vector2(4, 20), Vector2(4, 14), 2.0], ["seg", Vector2(9, 20), Vector2(9, 8), 2.0], ["seg", Vector2(14, 20), Vector2(14, 11), 2.0], ["seg", Vector2(19, 20), Vector2(19, 4), 2.0]],
	"usestyle": [["seg", Vector2(3, 8), Vector2(21, 8), 1.6], ["seg", Vector2(3, 16), Vector2(21, 16), 1.6], ["disc", Vector2(15, 8), 2.6], ["disc", Vector2(9, 16), 2.6], ["seg", Vector2(12, 3), Vector2(12, 6), 1.6]],
	"combos": [["disc", Vector2(5, 14), 2.6], ["disc", Vector2(12, 8), 2.6], ["disc", Vector2(19, 14), 2.6], ["seg", Vector2(5, 14), Vector2(12, 8), 1.6], ["seg", Vector2(12, 8), Vector2(19, 14), 1.6]],
	"rhythm": [["seg", Vector2(3, 18), Vector2(3, 10), 2.0], ["seg", Vector2(8, 18), Vector2(8, 5), 2.0], ["seg", Vector2(14, 18), Vector2(14, 12), 2.0], ["seg", Vector2(21, 18), Vector2(21, 7), 2.0]],
	"keeper": [["seg", Vector2(3, 12), Vector2(21, 12), 2.0], ["seg", Vector2(3, 7), Vector2(3, 17), 2.0], ["seg", Vector2(21, 7), Vector2(21, 17), 2.0], ["disc", Vector2(12, 12), 2.6]],
	"sellhit": [["seg", Vector2(3, 6), Vector2(15, 6), 2.0], ["seg", Vector2(15, 6), Vector2(15, 18), 2.0], ["seg", Vector2(15, 18), Vector2(3, 18), 2.0], ["seg", Vector2(3, 18), Vector2(3, 6), 2.0], ["disc", Vector2(18, 12), 3.0]],
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
	# I13 IMPACT FRAMES: a burst of rays round a point (the freeze); the off one has a bar across it
	"impact": [["disc", Vector2(12, 12), 2.6], ["seg", Vector2(12, 3), Vector2(12, 7), 2], ["seg", Vector2(12, 17), Vector2(12, 21), 2], ["seg", Vector2(3, 12), Vector2(7, 12), 2],
		["seg", Vector2(17, 12), Vector2(21, 12), 2], ["seg", Vector2(5.5, 5.5), Vector2(8.5, 8.5), 2], ["seg", Vector2(15.5, 15.5), Vector2(18.5, 18.5), 2], ["seg", Vector2(18.5, 5.5), Vector2(15.5, 8.5), 2], ["seg", Vector2(8.5, 15.5), Vector2(5.5, 18.5), 2]],
	"impact_off": [["disc", Vector2(12, 12), 2.6], ["seg", Vector2(12, 3), Vector2(12, 7), 2], ["seg", Vector2(12, 17), Vector2(12, 21), 2], ["seg", Vector2(3, 12), Vector2(7, 12), 2],
		["seg", Vector2(17, 12), Vector2(21, 12), 2], ["seg", Vector2(3, 21), Vector2(21, 3), 2.4]],
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
	"kind_scene": [["box", Rect2(2, 4, 20, 16), 1.6], ["box", Rect2(6, 7.5, 12, 9), 1.2], ["disc", Vector2(4.5, 6), 0.9], ["disc", Vector2(19.5, 6), 0.9],
		["disc", Vector2(4.5, 18), 0.9], ["disc", Vector2(19.5, 18), 0.9]],
}

static var _cache := {}


## the icon as a texture (made once)
static func tex(name: String) -> ImageTexture:
	if not _cache.has(name):
		_cache[name] = ImageTexture.create_from_image(paint(DRAW[name]))
	return _cache[name]


## the icon at 16 px (the Browser's rows: room for the part's name); scaled down from the 22 px drawing
static func small(name: String) -> ImageTexture:
	var k := name + "@16"
	if not _cache.has(k):
		var img := paint(DRAW[name])
		img.resize(16, 16, Image.INTERPOLATE_LANCZOS)
		_cache[k] = ImageTexture.create_from_image(img)
	return _cache[k]


static func paint(shapes: Array) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var k := 24.0 / SIZE   # pixels -> grid units
	for y in SIZE:
		for x in SIZE:
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
