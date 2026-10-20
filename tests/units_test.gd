## godot --headless --path . -s tests/units_test.gd     (ROADMAP 56: CLEAR UNITS EVERYWHERE)
## Scans the source of every scripts/*.gd for the numbers the user is shown: a string literal with a numeric format
## spec (%d %i %f %g %.Nf ...) on a line that says it (_say, _note), sets a label, tooltip, title, status or a
## message. Each spec must be followed by a unit (m/s cm mm m deg ° s ms f frames fps % × kg N BPM dB sd px breaths),
## or be one of the explicit counts and indices below, with its reason. A length in bare m is a failure: the app shows
## lengths in cm (mm under 1 cm) through Units.len. Units.gd is checked on real numbers, and the scanner on fixtures
## (a scanner that flags nothing proves nothing).
extends SceneTree

## a unit directly after the number (longest first, so "frames" wins over "f", "m/s" over "m")
const UNITS := ["rad/s", "m/s^2", "frames", "frame", "breaths", "steps/min", "m/s", "fps", "cm", "mm", "ms", "BPM", "bits", "bit", "BW", "dB", "deg", "kg", "px", "Hz",
	"sd", "SD", "×", "°", "%%", "%", "degrees", "degree", "minutes", "minute", "points", "W", "J", "m", "N", "g", "s", "f"]  # W watts, J joules, points of a 0-100 score

## a count of things the user can see: the number is how many (no unit), with the reason it is not a quantity
const COUNT_NOUNS := {  # a number before one of these words is a count (no unit), with its reason
	"animations": "how many animations", "button": "how many buttons", "buttons": "how many buttons", "characters": "how many characters", "landings": "how many landings", "angles": "how many angles", "walkers": "how many walkers", "chars": "how many characters", "leaf": "how many leaf bones", "twin": "how many twin ranges", "locked": "how many locked feet", "left": "how many left", "were": "how many were already there",
	"card": "how many cards", "cards": "how many cards", "part": "how many parts", "parts": "how many parts",
	"key": "how many keys", "keys": "how many keys", "step": "how many undo steps", "steps": "how many steps",
	"note": "how many notes", "notes": "how many notes", "finding": "how many findings",
	"findings": "how many findings", "fighter": "how many fighters", "fighters": "how many fighters",
	"joint": "how many joints", "joints": "how many joints", "marker": "how many markers",
	"markers": "how many markers", "range": "how many ranges", "ranges": "how many ranges",
	"clip": "how many clips", "clips": "how many clips", "item": "how many items", "items": "how many items",
	"file": "how many files", "files": "how many files", "edit": "how many edits", "edits": "how many edits",
	"layer": "how many layers", "layers": "how many layers", "change": "how many changes",
	"changes": "how many changes", "pass": "how many passes", "passes": "how many passes",
	"fingertip": "how many fingertips", "fingertips": "how many fingertips", "beat": "how many beats",
	"beats": "how many beats", "pose": "how many poses", "poses": "how many poses", "row": "how many rows",
	"rows": "how many rows", "entry": "how many entries", "entries": "how many entries", "bar": "how many bars",
	"bars": "how many bars", "window": "how many windows", "windows": "how many windows",
	"mouth": "how many mouth changes", "set": "how many sets", "sets": "how many sets",
	"time": "how many times", "times": "how many times", "try": "how many tries", "tries": "how many tries",
	"person": "how many people", "people": "how many people", "hit": "how many hits", "hits": "how many hits",
	"strike": "how many strikes", "strikes": "how many strikes", "copy": "how many copies",
	"copies": "how many copies", "option": "how many options", "options": "how many options",
	"sound": "how many sounds", "camera": "how many cameras", "fold": "how many folds", "tag": "how many tags",
	"chunk": "how many chunks", "hold": "how many holds", "contact": "how many contacts",
	"contacts": "how many contacts", "bone": "how many bones", "bones": "how many bones",
	"shape": "how many shapes", "shapes": "how many shapes", "scene": "how many scenes",
	"scenes": "how many scenes", "dummy": "how many dummies", "moves": "how many moves",
	"move": "how many moves", "view": "how many views", "views": "how many views",
	"undo": "how many undo steps", "undos": "how many undo steps", "pick": "how many picks",
	"picks": "how many picks", "tip": "how many tips", "tips": "how many tips",
	"videos": "how many videos (2 to 4 cameras of one person)", "letters": "how many letters (a note's length limit)",
	"knots": "how many knots on a curve", "strands": "how many hair strands", "segments": "how many hair segments",
	"usable": "how many usable frames (a pose file's frames the tracker could read)", "picked": "how many were picked",
	"must": "a count of must-fix findings",
	"WRONG": "a count of failed checks", "PASS-THROUGH": "a count of clashes that pass through",
	"gap": "how many gaps", "gaps": "how many gaps", "check": "how many checks", "checks": "how many checks",
	"PNG": "how many PNG frames", "comment": "how many comments", "comments": "how many comments",
	"more": "how many more", "alternating": "a count of alternating plants",
	"sliding": "a count of sliding feet", "secondary": "a count of items", "clash": "how many clashes",
	"clashes": "how many clashes", "query": "how many queries", "queries": "how many queries",
	"switch": "how many switches", "switches": "how many switches", "search": "how many searches",
	"searches": "how many searches", "cameras": "how many cameras", "lines": "how many lines",
	"lines,": "how many lines", "stroke": "how many strokes", "strokes": "how many strokes",
	"tags": "how many tags", "versions": "how many versions", "version": "how many versions",
	"limb": "how many limbs", "limbs": "how many limbs", "plant": "how many plants",
	"plants": "how many plants", "foot": "how many feet", "feet": "how many feet", "wall": "how many walls",
	"walls": "how many walls", "hand": "how many hands", "hands": "how many hands",
	# round-3 features: counts of things the UI lists
	"fall": "how many falls", "falls": "how many falls", "lesson": "how many lessons", "lessons": "how many lessons",
	"swing": "how many swings", "swings": "how many swings", "event": "how many events", "events": "how many events",
	"cue": "how many cues", "cues": "how many cues", "variant": "how many variants", "variants": "how many variants",
	"action": "how many actions", "actions": "how many actions", "shot": "how many shots", "shots": "how many shots",
	"found": "how many were found", "dropped": "how many were dropped", "slides": "how many slides of a strike",
	"recovers": "how many recover cards", "guard": "how many guard cards", "guards": "how many guards",
}
## a 1-based index of a thing ("card 3", "fighter 2 of 2", "marker 4"): the number names a position, not a quantity
const INDEX_BEFORE := ["card", "cards", "fighter", "marker", "clip", "step", "steps", "hit", "pose", "row", "item", "note", "pass", "range", "roadmap", "round", "upgrades",
	"#", "fall", "swing", "key", "set", "layer", "view", "tip", "camera", "bone", "fingertip", "sound", "frame", "version", "no.", "clip's", "track", "tracks"]
## a number right after one of these words is a count (no unit), with its reason
## a dimensionless quantity named by the word before it: a factor, a weight from 0 to 1, a correlation r
const DIMENSIONLESS_BEFORE := {"factor": "a dimensionless factor (a multiplier; 1 = no change)", "weight": "a layer weight from 0 to 1: dimensionless",
	"r": "a correlation coefficient r: dimensionless", "fitness": "a fitness value from 0 to 1: dimensionless",
	"fatigue": "fatigue from 0 (fresh) to 1 (spent): dimensionless", "strength": "a cue strength from 0 to 1: dimensionless"}
const COUNT_BEFORE := ["must-fix", "FOOT SLIDE", "became", "count:", "clashes:", "beats:", "picked", "->", "→"]

## the explicit allow list: a literal (substring) in a file that shows a unitless number, and why it is allowed
const ALLOW := [
	{"file": "co_edit.gd", "lit": "version mismatch", "reason": "a version number: an id that both peers must match, not a quantity"},
	{"file": "co_edit.gd", "lit": "fighter count: host", "reason": "a count of fighters on each peer (a count, no unit)"},
	{"file": "llm_client.gd", "lit": "HTTP %d", "reason": "an HTTP status code the server sent, not a quantity"},
	{"file": "llm_client.gd", "lit": "error %d", "reason": "an error code (a number the OS or the server gives), not a quantity"},
	{"file": "main.gd", "lit": "error %d", "reason": "an error code (a number the OS gives), not a quantity"},
	{"file": "main.gd", "lit": "127.0.0.1:%d", "reason": "a network port number, not a quantity"},
	{"file": "main.gd", "lit": "IK weight there %.2f", "reason": "an IK weight from 0 to 1: a dimensionless fraction, shown as a number"},
	{"file": "main.gd", "lit": "'%s' weight %.2f here", "reason": "a layer weight from 0 to 1 (0 = the layers below alone): dimensionless"},
	{"file": "main.gd", "lit": "weight key at %s = %.2f", "reason": "a layer weight from 0 to 1 at a key: dimensionless"},
	{"file": "main.gd", "lit": "weight keyed at %s = %.2f", "reason": "a layer weight from 0 to 1 at a key: dimensionless"},
	{"file": "main.gd", "lit": "end of fight: %.0f", "reason": "the fatigue slider value from 0 to 1 (a dimensionless fraction)"},
	{"file": "main.gd", "lit": "fatigue at fitness %.2f", "reason": "the fitness value from 0 to 1 (a dimensionless fraction)"},
	{"file": "engine_export.gd", "lit": "Unreal Engine 5", "reason": "a product name, not a quantity"},
	{"file": "engine_export.gd", "lit": "Godot 4", "reason": "a product name, not a quantity"},
	{"file": "ai_box.gd", "lit": "glm-4.7-flash", "reason": "a model name (an identifier), not a quantity"},
	{"file": "view_cube.gd", "lit": "keys 1-5", "reason": "keyboard keys 1 to 5, names not quantities"},
	{"file": "main.gd", "lit": "Unreal 5", "reason": "a product name, not a quantity"},
	{"file": "main.gd", "lit": "numpad 0", "reason": "a keyboard key name"},
	{"file": "main.gd", "lit": "16:9", "reason": "an aspect ratio (a frame shape), not a quantity"},
	{"file": "main.gd", "lit": "4/4 grid", "reason": "a musical time signature (4 beats per bar), not a quantity"},
	{"file": "main.gd", "lit": "UPGRADES #209", "reason": "a roadmap item number"},
	{"file": "main.gd", "lit": "4242", "reason": "the default network port the server listens on, not a quantity"},
	{"file": "main.gd", "lit": "the port is a number from 1 to 65535", "reason": "a network port range, a name of a valid port"},
	{"file": "main.gd", "lit": "round-5", "reason": "a roadmap round name, not a quantity"},
	{"file": "main.gd", "lit": "normalize normalise -1 1", "reason": "command-palette search keywords (hidden), not shown text"},
	{"file": "main.gd", "lit": "Godot 4", "reason": "a product name, not a quantity"},
	{"file": "props.gd", "lit": "size 5", "reason": "a football size class (FIFA size 5), a name not a quantity"},
	{"file": "props.gd", "lit": "US 32 x 80 in", "reason": "a US door size written in inches, as the standard names it"},
	{"file": "engine_export.gd", "lit": "Import Uniform Scale 100", "reason": "a UE5 import setting name (the glTF default scale), not a quantity"},
	{"file": "stunt_load.gd", "lit": "AJSM 33:492", "reason": "a journal citation (volume 33, page 492)"},
	{"file": "moves.gd", "lit": "3-2u", "reason": "the smoothstep formula constant (e = u*u*(3-2u)), not a quantity"},
	{"file": "weight_feel.gd", "lit": "(x%.2f)", "reason": "a dimensionless multiplier of the swing's weight"},
	{"file": "main.gd", "lit": "exported %d .fbx", "reason": "a count of files"},
	{"file": "main.gd", "lit": "binary FBX 7.4", "reason": "the FBX format version, a name not a quantity"},
	{"file": "main.gd", "lit": "Blender 4.5", "reason": "a product version, a name not a quantity"},
	# tonight's merges: counts, 0/1 blend values and product names (each a count or a dimensionless value, no unit)
	{"file": "export_dialog.gd", "lit": "Unreal Engine 5", "reason": "a product name, not a quantity"},
	{"file": "export_dialog.gd", "lit": "Godot 4", "reason": "a product name, not a quantity"},
	{"file": "export_dialog.gd", "lit": "outside 1-120", "reason": "the legal fps range 1 to 120: the unit (fps) is in the same sentence"},
	{"file": "export_dialog.gd", "lit": "%d prop%s not in any export", "reason": "a count of props"},
	{"file": "face_ui.gd", "lit": "%d channel%s", "reason": "a count of face channels"},
	{"file": "main.gd", "lit": "the blend keyed 0", "reason": "the IK/FK blend value 0 (all FK): a dimensionless fraction"},
	{"file": "main.gd", "lit": "the blend keyed 1", "reason": "the IK/FK blend value 1 (all IK): a dimensionless fraction"},
	{"file": "main.gd", "lit": "0 removes nothing", "reason": "a tolerance of zero: the line gives the unit (degrees) just before"},
	{"file": "main.gd", "lit": "main key%s", "reason": "a count of keys"},
	{"file": "main.gd", "lit": "%+.2f, %s.  Ctrl+Z undoes", "reason": "a dimensionless ease value from -1 to 1"},
	{"file": "main.gd", "lit": "the IK/FK blend is keyed 0", "reason": "the IK/FK blend value 0: a dimensionless fraction"},
	{"file": "main.gd", "lit": "the IK/FK blend keyed 1", "reason": "the IK/FK blend value 1: a dimensionless fraction"},
	{"file": "main.gd", "lit": "the last 5 autosaves", "reason": "a count of autosaves"},
	{"file": "main.gd", "lit": "Kine keeps the last %d", "reason": "a count of autosaves"},
	{"file": "main.gd", "lit": "when %d newer ones are opened", "reason": "a count of scenes"},
	{"file": "main.gd", "lit": "(%d dabs)", "reason": "a count of brush dabs"},
	{"file": "main.gd", "lit": "impact shake%s", "reason": "a count of shakes"},
	# tonight's merges (crowd, camera solve, attributes): an identifier, a 0..1 value and a typed example, no unit
	{"file": "main.gd", "lit": "re-rolled: seed %d", "reason": "a random seed: an identifier that picks the crowd's layout, not a quantity"},
	{"file": "main.gd", "lit": "(grip 0 .. 1)", "reason": "a custom attribute's range example: a dimensionless value from 0 to 1"},
	{"file": "main.gd", "lit": "is a number, e.g. 0 or 0.5", "reason": "an example of a typed value in a hint (what to type), not a reading"},
	{"file": "main.gd", "lit": "needs 2 to %d videos", "reason": "a count of videos (2 is the least, MULTI_MAX the most): the scan reads the 2 before 'to %d' as unitless"},
	{"file": "rise.gd", "lit": "rising %d/%d", "reason": "a key index of the rise: stage k of the NKEY-1 keys (a count of keys, not a quantity)"},
	{"file": "plugins.gd", "lit": "Godot error %d", "reason": "an error code the engine gives, not a quantity"},
	# round-6 merges (page bar, card strip, path run/walk, feasibility): keys, card names, counts
	{"file": "main.gd", "lit": "card moved to place %d", "reason": "a 1-based position in the strip: an index"},
	{"file": "main.gd", "lit": "page (Shift+%d)", "reason": "a keyboard key 1 to 5: a key name"},
	{"file": "main.gd", "lit": "(Alt+%d too", "reason": "a keyboard key 1 to 5: a key name"},
	{"file": "main.gd", "lit": "Shift+%d", "reason": "a keyboard key 1 to 5: a key name"},
	{"file": "path_run.gd", "lit": "%s %s %d", "reason": "a card name: the stride number is an index"},
	{"file": "path_run.gd", "lit": "air %d", "reason": "a card name: the stride number is an index"},
	{"file": "path_walk.gd", "lit": "pivot %d.%d", "reason": "a card name: step and pivot indices"},
	{"file": "feasible.gd", "lit": "%d problem%s", "reason": "a count of problems found"},
	# fix25: counts, indices, ids and dimensionless values from the merges
	{"file": "auto_camera_ui.gd", "lit": "shots suggested", "reason": "a count of suggested shots"},
	{"file": "auto_camera_ui.gd", "lit": "shots for card", "reason": "a count of shots for a card"},
	{"file": "auto_camera_ui.gd", "lit": "shot%s written", "reason": "a count of shots written"},
	{"file": "beat_fight.gd", "lit": "4/4 grid", "reason": "a musical time signature (4 beats per bar), not a quantity"},
	{"file": "beat_fight.gd", "lit": ", %d flagged", "reason": "a count of flagged cards"},
	{"file": "body_panel.gd", "lit": "%dth", "reason": "a percentile rank: an ordinal, the unit is the word percentile"},
	{"file": "body_panel.gd", "lit": "x height", "reason": "a dimensionless ratio of arm span to height"},
	{"file": "counter_ui.gd", "lit": "ghost%s on", "reason": "a count of ghosts"},
	{"file": "export_dialog.gd", "lit": "8 sub-frames", "reason": "a count of sub-frames (8), the unit of the shutter is in the same sentence"},
	{"file": "fight_phrase.gd", "lit": "%s %d", "reason": "a card name: the beat number is an index"},
	{"file": "fight_phrase.gd", "lit": "FP %d FLAG", "reason": "a mark name: the beat number is an index"},
	{"file": "fight_phrase.gd", "lit": "beat %d at", "reason": "a beat number: an index, the time follows in s"},
	{"file": "hit_physics.gd", "lit": "react.py failed (exit %d)", "reason": "a process exit code, not a quantity"},
	{"file": "impact_frames_ui.gd", "lit": "squash %.2f", "reason": "a dimensionless squash factor (1 = no squash)"},
	{"file": "main.gd", "lit": "sub-frames over a", "reason": "a count of sub-frames"},
	{"file": "main.gd", "lit": "shots, %s) in", "reason": "a count of shots"},
	{"file": "main.gd", "lit": "min while you edit, last", "reason": "a count of kept snapshots"},
	{"file": "main.gd", "lit": "The last %d are kept", "reason": "a count of kept snapshots"},
	{"file": "main.gd", "lit": "sample reaction clips are in", "reason": "a count of clips"},
	{"file": "main.gd", "lit": "reaction cards from", "reason": "a count of cards"},
	{"file": "main.gd", "lit": "Python 3 with mujoco", "reason": "a product version (Python 3), a name not a quantity"},
	{"file": "main.gd", "lit": "too long for one QR", "reason": "a count of characters"},
	{"file": "main.gd", "lit": "characters one QR holds", "reason": "a count of characters and a QR version number: an id, not a quantity"},
	{"file": "main.gd", "lit": "port %d is busy", "reason": "a network port number, not a quantity"},
	{"file": "main.gd", "lit": "The port is [api] port", "reason": "a network port number (the default), not a quantity"},
	{"file": "main.gd", "lit": "knee bent 90", "reason": "a typed example phrase (what to type), not a reading"},
	{"file": "main.gd", "lit": "sneaky, -1 to +1", "reason": "the range -1 to +1 of a dimensionless slider"},
	{"file": "main.gd", "lit": "one score 0-100", "reason": "a dimensionless score from 0 to 100"},
	{"file": "main.gd", "lit": "AU4+6/7+9/10+43", "reason": "FACS action unit codes (Ekman & Friesen): names, not quantities"},
	{"file": "main.gd", "lit": "make 3 sample clips", "reason": "a count of clips"},
	{"file": "main.gd", "lit": "the median of the (up to 5) nearest", "reason": "counts of saved scenes"},
	{"file": "main.gd", "lit": "placed, %d partly", "reason": "counts of phrases"},
	{"file": "main.gd", "lit": "retime by a factor from 0.1 to 10", "reason": "a dimensionless factor range (2 = twice as slow)"},
	{"file": "main.gd", "lit": "pick another f-stop (f/1.4 to f/22)", "reason": "f-stops: a ratio (focal length over aperture), written f/N"},
	{"file": "main.gd", "lit": "(score %.2f)", "reason": "a dimensionless suggestion score"},
	{"file": "make_physical.gd", "lit": "physical %d", "reason": "a card name: the span number is an index"},
	{"file": "make_physical_ui.gd", "lit": "gold note", "reason": "a count of notes"},
	{"file": "make_physical_ui.gd", "lit": "span%s", "reason": "a count of spans"},
	{"file": "make_physical_ui.gd", "lit": "physical cards;", "reason": "a count of cards"},
	{"file": "qr_share.gd", "lit": "bytes unpacked", "reason": "a count of bytes"},
	{"file": "qr_share.gd", "lit": "lists %d cards", "reason": "a count of cards and the legal range 1 to the maximum"},
	{"file": "qr_share.gd", "lit": "(kind %d)", "reason": "a format kind id, not a quantity"},
	{"file": "reaction_picker.gd", "lit": "reactions found", "reason": "a count of reactions"},
	{"file": "realism_ui.gd", "lit": "realism score how realistic number", "reason": "hidden search keywords"},
	{"file": "realism_ui.gd", "lit": "REALISM  %d / 100", "reason": "a score out of 100: dimensionless"},
	{"file": "realism_ui.gd", "lit": "-%.1f points", "reason": "points of a score out of 100: dimensionless"},
	{"file": "realism_ui.gd", "lit": "of the clip = -", "reason": "points of a score out of 100: dimensionless"},
	{"file": "realism_ui.gd", "lit": "score = 100 - sum of", "reason": "a score out of 100: dimensionless"},
	{"file": "realism_ui.gd", "lit": "realism score %d / 100", "reason": "a score out of 100: dimensionless"},
	{"file": "smart_drag.gd", "lit": "%s@%d", "reason": "a hidden cache key (path and file time stamp), not shown"},
	{"file": "snap_diff.gd", "lit": "added, %d removed", "reason": "counts of added and removed items"},
	{"file": "style_dial_ui.gd", "lit": "%s  %+.2f", "reason": "a dimensionless slider value from -1 to +1"},
	{"file": "style_dial_ui.gd", "lit": "%s %+.2f", "reason": "a dimensionless slider value from -1 to +1"},
	{"file": "style_dial_ui.gd", "lit": "+1 is the size", "reason": "a dimensionless slider scale (+1 = one spread of your own clips)"},
	{"file": "style_dial_ui.gd", "lit": "-1 .. +1", "reason": "the range of a dimensionless slider"},
	{"file": "style_dial_ui.gd", "lit": "sliders to 0", "reason": "a dimensionless slider value (0 = off)"},
	{"file": "style_dial_ui.gd", "lit": "planted feet and", "reason": "counts of feet and contacts"},
	{"file": "timing_coach_ui.gd", "lit": "%d suggestions", "reason": "a count of suggestions"},
	{"file": "timing_coach_ui.gd", "lit": "timing coach: %d written", "reason": "a count of written suggestions"},
	# round-3 features: card names with a number, counts the nouns cannot reach, a cache key, an HTML charset
	{"file": "breakfall.gd", "lit": "to fix", "reason": "a count of falls to fix"},
	{"file": "choreograph.gd", "lit": "wind-up %d", "reason": "a card name: the strike number is an index"},
	{"file": "choreograph.gd", "lit": "STRIKE %d", "reason": "a card name: the strike number is an index"},
	{"file": "choreograph.gd", "lit": "follow-through %d", "reason": "a card name: the strike number is an index"},
	{"file": "combo_ui.gd", "lit": "a combo needs 2 or more cards", "reason": "a count of cards (the least a combo has)"},
	{"file": "exertion.gd", "lit": "(needs %d)", "reason": "a count of strikes (the least a verdict needs)"},
	{"file": "exertion.gd", "lit": "up to x%.2f", "reason": "a dimensionless multiplier of the strike time (x2 = twice as slow)"},
	{"file": "exertion_ui.gd", "lit": "fatigue at the end", "reason": "fatigue 0..1 at the end of the clip and its peak: dimensionless"},
	{"file": "motion_match.gd", "lit": "%s%s@%d", "reason": "a hidden cache key (path and file time stamp), not shown"},
	{"file": "safety_sheet.gd", "lit": "<!doctype html>", "reason": "the charset name utf-8 in an HTML page written to disk, not a quantity"},
	{"file": "sell_hit.gd", "lit": "strike%s: %d sold", "reason": "counts of strikes sold, not sold and unsafe"},
	{"file": "weapon_torque_ui.gd", "lit": "need work. ", "reason": "a count of swings that need work"},
	{"file": "style_ui.gd", "lit": "save %d or more clips", "reason": "a count of clips"},
	{"file": "weapon_torque.gd", "lit": "slow the swing x%.2f", "reason": "a dimensionless multiplier of the swing time (x2 = twice as slow)"},
	{"file": "weapon_torque.gd", "lit": "scales it x%.2f", "reason": "a dimensionless multiplier"},
	{"file": "main.gd", "lit": "restitution 0.5", "reason": "Newton's coefficient of restitution: dimensionless (0 sticks, 1 bounces fully)"},
	{"file": "weapon_rebound_ui.gd", "lit": "weapon contacts", "reason": "a count of weapon contacts and of swings stopped dead"},
	{"file": "weapon_rebound_ui.gd", "lit": "restitution %.1f", "reason": "Newton's coefficient of restitution: dimensionless"},
	{"file": "weapon_rebound_ui.gd", "lit": "Contact %d", "reason": "the contact's number in the list (an index)"},
	{"file": "weapon_rebound_ui.gd", "lit": "contacts, %d stopped dead", "reason": "a count of contacts and of swings stopped dead"},
	{"file": "weapon_rebound_ui.gd", "lit": "IK keys on", "reason": "a count of IK keys and of hands"},
]

## the last word before a number, without a list bracket: "(r" -> "r"
static func last_word(before: String) -> String:
	before = before.rstrip(" +-")
	var w := before.get_slice(" ", before.get_slice_count(" ") - 1) if before != "" else ""
	if w.begins_with("(") and w.length() > 1:
		w = w.substr(1)
	return w


## lines that show something to the user: a say, a note, a label, a tooltip, a title, a status, a message
const UI_HINTS := ["_say(", "_say_plain(", "_note(", ".text", "text =", "tooltip", "set_text(", "title", "hint",
	"\"msg\"", "\"text\"", "status", "toast", "label", "lbl", "readout", "caption", "popup", "alert", "why", "dlg.",
	"b.text", "\"detail\"", "say(", "_status(", "append(", "_f(", "msg", "why", "note", "detail", "_button(", "_label(", "add.call(", "_row(", "_toggle(", "_menu(", "_tag("]

var fails := 0
const WIDE := false   # true: every string literal is scanned, not only the UI lines (a wider net, not yet clean)
## files whose strings are file formats or agent protocol, not text the user reads: skipped (reason in each line)
const NOT_UI := {
	"usd_export.gd": "a USD text file written to disk (matrices, schema), not the UI",
	"bvh_export.gd": "a BVH text file written to disk",
	"bvh_import.gd": "a BVH text file read from disk",
	"gltf_export.gd": "a glTF file written to disk",
	"game_export.gd": "a game data file written to disk",
	"agent_tools.gd": "the agent protocol (JSON-RPC), read by a program",
	"llm_client.gd": "a web request body, not shown",
	"fbx_export.gd": "a binary FBX file written to disk (format ids, connections), not the UI",
	"review.gd": "an HTML page written to disk for the review report",
}
var scanned := 0      # numeric specs seen on UI lines
var with_unit := 0
var counted := 0      # counts and indices (allowed by their word)
var allowed := 0      # listed on ALLOW
var found := []        # violations: [file, line, literal, spec]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func is_word_end(s: String, i: int) -> bool:
	if i >= s.length():
		return true
	var c := s.unicode_at(i)
	var word := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
	return not word


## the string literals of one source line (comments stop the scan; escapes are kept as a space)
static func literals_of(line: String) -> Array:
	var out := []
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "#":
			break
		if c == "\"" or c == "'":
			var j := i + 1
			var buf := ""
			while j < n and line[j] != c:
				if line[j] == "\\" and j + 1 < n and line[j + 1] == "u" and j + 5 < n:
					buf += " "      # a unicode glyph escape: its hex digits are not numbers
					j += 6
				elif line[j] == "\\" and j + 1 < n:
					buf += " "
					j += 2
				else:
					buf += line[j]
					j += 1
			out.append(buf)
			i = j + 1
		else:
			i += 1
	return out


## every numeric format spec in a literal: [{"at", "end", "conv"}]; "%%" is a literal percent and is skipped
static func specs_of(lit: String) -> Array:
	var out := []
	var i := 0
	var n := lit.length()
	while i < n:
		if lit[i] != "%":
			i += 1
			continue
		if i + 1 < n and lit[i + 1] == "%":
			i += 2
			continue
		if i + 1 < n and lit[i + 1] == " ":   # "10% faster" is text, not a space-flagged spec
			i += 1
			continue
		var j := i + 1
		while j < n and "-+ 0#".contains(lit[j]):
			j += 1
		while j < n and "0123456789.".contains(lit[j]):
			j += 1
		if j < n and "dfgi".contains(lit[j]):
			out.append({"at": i, "end": j + 1, "conv": lit[j]})
		i = j + 1
	return out


## what follows a spec, as a unit ("unit", token) or a count ("count", noun) or nothing ("", "")
static func after_kind(after: String) -> Array:
	var a := after.lstrip(" ")
	if a.begins_with(")"):   # the unit of a group: "(%.2f, %.2f) m" is metres for both
		a = a.substr(1).lstrip(" ")
	for u in UNITS:
		if a.begins_with(u) and (u.ends_with("%") or u.ends_with("°") or is_word_end(a, u.length())):
			return ["unit", u]
	for noun in COUNT_NOUNS:
		if a.begins_with(noun) and is_word_end(a, noun.length()):
			return ["count", noun]
	return ["", ""]


## the classification of spec k of lit: ["unit"|"count"|"index"|"", token]. Order: a unit right after the number wins;
## then a list label "(3)", a connector that passes the next spec's unit ("%.2f-%.2f s", "%.0f x %.0f cm"), an index
## word before it ("card 3", "frame 12", a range "cards 2-5"), a count word before it ("must-fix 2") or after it
## ("3 of 10", "3 cards", "2 left", "(3 in this scene)").
static func classify(lit: String, specs: Array, k: int, forward := true) -> Array:
	var sp: Dictionary = specs[k]
	var before := lit.substr(0, sp["at"]).rstrip(" ")
	var rest := lit.substr(sp["end"])
	var r := rest.lstrip(" ")
	var whole: bool = sp["conv"] == "d" or sp["conv"] == "i"   # a count and an index are whole numbers
	if whole and before.ends_with("(") and r.begins_with(")"):
		return ["count", "a count in a list label, e.g. 'Set  (3)'"]
	if before != "" and not lit.substr(0, int(sp["at"])).ends_with(" ") and (is_word_char(before.unicode_at(before.length() - 1)) or before.ends_with(":")) and after_kind(rest)[0] != "unit":
		return ["name", "an id glued to the number (c%d, m%d, note_%d)"]
	if whole and before.ends_with("(") and rest.begins_with(" in "):
		return ["count", "a count in the scene, e.g. '(3 in this scene)'"]
	for conn in ["->", "→", "-", "–", ",", "x", "×", "to", "of", "/"]:
		if forward and r.begins_with(conn) and k + 1 < specs.size():
			var at_next := lit.length() - r.substr(conn.length()).lstrip(" ").length()
			if int(specs[k + 1]["at"]) == at_next:
				var nxt := classify(lit, specs, k + 1)
				if nxt[0] != "":
					return nxt
	var kind := after_kind(rest)
	if kind[0] == "unit":
		return kind
	var last := before.get_slice(" ", before.get_slice_count(" ") - 1) if before != "" else ""
	if last.begins_with("(") and last.length() > 1:
		last = last.substr(1)
	if whole and (last.to_lower() in INDEX_BEFORE or before.ends_with("#")):
		return ["index", last]
	if whole and (before.ends_with("-") or before.ends_with("–")) and k > 0 and classify(lit, specs, k - 1, false)[0] == "index":
		return ["index", "a range of indices"]
	for w in COUNT_BEFORE:
		if whole and before.ends_with(w):
			return ["count", w]
	if whole and (r.begins_with("of ") or r == "of" or before.ends_with(" of") or before == "of"):
		return ["count", "of"]   # "3 of 10": a count, and the total it is out of
	if whole and kind[0] == "count":
		return kind
	if DIMENSIONLESS_BEFORE.has(last.to_lower()):
		return ["dimensionless", DIMENSIONLESS_BEFORE[last.to_lower()]]
	return ["", ""]


## the plain (non-spec) numbers in a literal, as [start, end) pairs: "0.84 m", "12-20 breaths", "1.5 to 2.0 m".
## A digit run is a number unless a letter, digit, underscore or dot is glued to it ("v1.4", "127.0.0.1", "F1"), or a colon
## ("text:0.7" is a style string the label parses, not a shown number).
static func plain_numbers(lit: String, specs: Array) -> Array:
	var inside := []
	inside.resize(lit.length())
	inside.fill(false)
	for sp in specs:
		for i in range(int(sp["at"]), int(sp["end"])):
			inside[i] = true
	var out := []
	var i := 0
	var n := lit.length()
	while i < n:
		var c: int = lit.unicode_at(i)
		var digit: bool = c >= 48 and c <= 57
		var glued: bool = i > 0 and (is_word_char(lit.unicode_at(i - 1)) or lit[i - 1] == "." or lit[i - 1] == ":" or lit[i - 1] == "^" or lit[i - 1] == "#" or inside[i - 1])
		if digit and not inside[i] and not glued:
			var j := i
			while j < n and lit.unicode_at(j) >= 48 and lit.unicode_at(j) <= 57:
				j += 1
			if j + 1 < n and lit[j] == "." and lit.unicode_at(j + 1) >= 48 and lit.unicode_at(j + 1) <= 57:
				j += 1
				while j < n and lit.unicode_at(j) >= 48 and lit.unicode_at(j) <= 57:
					j += 1
			var dotted := j + 1 < n and lit[j] == "." and lit.unicode_at(j + 1) >= 48 and lit.unicode_at(j + 1) <= 57
			if not dotted:
				out.append([i, j])
			i = j
		else:
			i += 1
	return out


static func is_word_char(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


## what a plain number means: the unit or count after it (a connector passes the next number's unit, as for specs)
static func number_kind(lit: String, specs: Array, nums: Array, k: int) -> Array:
	var rest: String = lit.substr(int(nums[k][1]))
	var r := rest.lstrip(" ")
	for conn in ["->", "→", "-", "–", ",", "or", "and", "to", "/", "x", "×"]:
		if r.begins_with(conn):
			var after_conn := r.substr(conn.length()).lstrip(" ")
			var at_next := lit.length() - after_conn.length()
			if after_conn != "" and after_conn[0] >= "0" and after_conn[0] <= "9" and k + 1 < nums.size():
				if int(nums[k + 1][0]) == at_next:
					return number_kind(lit, specs, nums, k + 1)
			if after_conn != "" and after_conn[0] == "%":
				for j in specs.size():
					if int(specs[j]["at"]) == at_next:
						var cs := classify(lit, specs, j, true)
						if cs[0] == "unit":
							return cs
	var tok := lit.substr(int(nums[k][0]), int(nums[k][1]) - int(nums[k][0]))
	var before := lit.substr(0, int(nums[k][0]))
	var bw := before.rstrip(" ")
	var lw := last_word(bw)
	if tok.length() == 4 and tok.is_valid_int() and int(tok) >= 1900 and int(tok) <= 2099:
		return ["name", "a year: a date or a citation (Author 2001)"]
	var suffix := rest.substr(0, 2).to_lower()
	if suffix in ["st", "nd", "rd", "th"] or rest.begins_with("D ") or rest.begins_with("D)") or rest == "D":
		return ["name", "an ordinal or a name glued to the number (2nd, 3D, 5th)"]
	if rest.begins_with("  ") or (rest.begins_with(" ") and rest.length() > 1 and rest[1] >= "A" and rest[1] <= "Z" and k == 0 and bw == ""):
		return ["index", "a numbered step in a list (the step number, not a quantity)"]
	if lw.to_lower() in INDEX_BEFORE or lw.to_lower() in ["step", "steps", "key", "keys", "tab"]:
		return ["index", lw]
	if (bw.ends_with("-") or bw.ends_with("–")) and k > 0 and last_word(lit.substr(0, int(nums[k - 1][0])).rstrip(" ")).to_lower() in INDEX_BEFORE:
		return ["index", "a range of list numbers (10-13)"]
	if (lw == "and" or lw == "or" or lw == ",") and k > 0 and last_word(lit.substr(0, int(nums[k - 1][0])).rstrip(" ")).to_lower() in INDEX_BEFORE:
		return ["index", "a list of step numbers (2 and 3)"]
	if bw.ends_with("(") and r.begins_with(")"):
		return ["count", "a count in a list label, e.g. 'Set  (3)'"]
	if r.begins_with("of ") or r == "of" or bw.ends_with(" of"):
		return ["count", "of"]
	if DIMENSIONLESS_BEFORE.has(lw.to_lower()):
		return ["dimensionless", DIMENSIONLESS_BEFORE[lw.to_lower()]]
	if r.begins_with("=") or r.begins_with("..") or r.begins_with("…"):
		return ["legend", "a dimensionless value named in a legend, e.g. '0 = as it is, 1 = the full change'"]
	var kind := after_kind(rest)
	if kind[0] != "":
		return kind
	return ["", ""]


## the violations of one source line: [[literal, spec_text, reason], ...]; also counts into the totals
func check_line(file: String, lineno: int, line: String) -> void:
	if NOT_UI.has(file):
		return
	var ui := false
	for h in UI_HINTS:
		if line.contains(h):
			ui = true
			break
	if not ui and not WIDE:
		return
	for lit in literals_of(line):
		if not ui and (lit.find(" ") < 0 or not lit.contains("%") and not lit.contains("0") and not lit.contains("1") and not lit.contains("2")):
			continue
		var specs := specs_of(lit)
		var nums := plain_numbers(lit, specs)
		for k in nums.size():
			scanned += 1
			var tok: String = lit.substr(int(nums[k][0]), int(nums[k][1]) - int(nums[k][0]))
			var c := number_kind(lit, specs, nums, k)
			var verdict := ""
			if c[0] == "unit" and c[1] == "m":
				verdict = "a length in bare m: show it in cm (mm under 1 cm)"
			elif c[0] == "unit":
				with_unit += 1
				continue
			elif c[0] == "count" or c[0] == "index":
				counted += 1
				continue
			elif c[0] == "legend" or c[0] == "dimensionless" or c[0] == "name":
				allowed += 1
				continue
			else:
				verdict = "a plain number with no unit: add a unit, or list it as a count or index with a reason"
			var listed := false
			for a in ALLOW:
				if file.ends_with(a["file"]) and lit.contains(a["lit"]):
					listed = true
			if listed:
				allowed += 1
				continue
			found.append([file, lineno, lit, tok, verdict])
		for k in specs.size():
			scanned += 1
			var sp: Dictionary = specs[k]
			var spec_text: String = lit.substr(int(sp["at"]), int(sp["end"]) - int(sp["at"]))
			var c := classify(lit, specs, k)
			var verdict := ""
			if c[0] == "unit" and c[1] == "m":
				verdict = "a length in bare m: show it with Units.len (cm, mm under 1 cm)"
			elif c[0] == "unit":
				with_unit += 1
				continue
			elif c[0] == "count" or c[0] == "index":
				counted += 1
				continue
			elif c[0] == "dimensionless" or c[0] == "legend" or c[0] == "name":
				allowed += 1
				continue
			else:
				verdict = "a unitless number: add a unit, or list it as a count or index with a reason"
			var listed := false
			for a in ALLOW:
				if file.ends_with(a["file"]) and lit.contains(a["lit"]):
					listed = true
			if listed:
				allowed += 1
				continue
			found.append([file, lineno, lit, spec_text, verdict])


func scan_sources() -> void:
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		fails += 1
		print("FAIL cannot open res://scripts")
		return
	var names := dir.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://scripts/" + f)
		var lines := text.split("\n")
		var pending := ""
		for i in lines.size():
			var line: String = lines[i] if pending == "" else pending + " " + lines[i]
			# a format string that runs over several lines is checked as one line
			if count_quotes(line) % 2 == 1 and i + 1 < lines.size():
				pending = line
				continue
			pending = ""
			check_line(f, i + 1, line)


static func count_quotes(line: String) -> int:
	var n := 0
	for i in line.length():
		if line[i] == "\"" and (i == 0 or line[i - 1] != "\\"):
			n += 1
	return n


func fixtures() -> void:
	# anti-vacuity: the scanner must flag the bad shapes and pass the good ones
	var bad := 0
	bad += int(literal_bad('_say("took %d goes")'))
	bad += int(literal_bad('_say("%.1f m")'))
	bad += int(literal_bad('_say("%d")'))
	bad += int(literal_bad('_say("a 1.8 m rod")'))
	bad += int(literal_bad('_say("a 0.5 long rod")'))
	var good := 0
	good += int(not literal_bad('_say("card %d is now")'))
	good += int(not literal_bad('_say("the time is %.2f s")'))
	good += int(not literal_bad('_say("%d%% done")'))
	good += int(not literal_bad('_say("%.2f-%.2f s")'))
	good += int(not literal_bad('_say("a 12 cm rod, 2 cards, 50 %")'))
	good += int(not literal_bad('_say("hold 0.5 s")'))
	good += int(not literal_bad('_say("3 of %d cards")'))
	ok(bad == 5 and good == 7, "scanner fixtures: 5 bad shapes flagged, 7 good shapes passed (%d and %d)" % [bad, good])


func literal_bad(line: String) -> bool:
	var before := found.size()
	check_line("fixture.gd", 0, line)
	var hit := found.size() > before
	found.resize(before)
	return hit


func units_helpers() -> void:
	var a := [Units.len(0.5), Units.len(0.004), Units.len(0.085), Units.len(1.2), Units.ang(4.26), Units.ang(45.2),
		Units.time(0.4, 30.0), Units.time(1.0, 24.0)]
	var want := ["50 cm", "4 mm", "8.5 cm", "120 cm", "4.3°", "45°", "0.40 s (12 f)", "1.00 s (24 f)"]
	ok(a == want, "Units helpers on real numbers: %s" % str(a))


func _init() -> void:
	units_helpers()
	fixtures()
	scanned = 0
	with_unit = 0
	counted = 0
	allowed = 0
	scan_sources()
	for v in found:
		print("FAIL %s:%d  %s  [%s]  %s" % [v[0], v[1], v[4], v[3], v[2]])
	ok(found.is_empty(), "every number shown carries a unit or is a listed count/index: %d specs on UI lines, %d with a unit, %d counts or indices, %d allowed, %d unitless or bare m (must be 0)" % [scanned, with_unit, counted, allowed, found.size()])
	print("units: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
