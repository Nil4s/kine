"""POSER AS AN MCP SERVER (round 15, GATES V1). Any MCP client (Claude Code, Claude Desktop, an agent SDK) can drive the
poser: open a scene, pose the body in words, read where every part is at any moment, check the motion, save.

  python tools/mcp/poser_mcp.py [--godot <Godot executable>] [--math]      (or set POSER_GODOT; --math / POSER_MCP_MATH=1 adds the six C06 tools)

It speaks MCP over stdio (one JSON-RPC message per line) using the standard library only, and runs ONE live session of
`poser_cli serve` underneath (tools/poser_cli.gd), started on the first tool call. Each MCP tool is one serve method,
so the two never disagree; a serve error comes back as a tool result with isError and serve's own message (it says
what to do next). Scenes are saved only into scenes/_wip/ (serve refuses anything else).

Claude Code:  claude mcp add poser -- python C:/Users/Nick/Desktop/poser/tools/mcp/poser_mcp.py
"""
import json, os, queue, subprocess, sys, threading, time

PROJ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("POSER_GODOT", r"C:\Users\Nick\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe")
if "--godot" in sys.argv:
    GODOT = sys.argv[sys.argv.index("--godot") + 1]
VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]   # newest first; the client's is used if it is one of these
TIMEOUT = 300

S = {"type": "string"}
N = {"type": "number"}
# name -> (serve method, description, input schema)
TOOLS = {
    "open": ("open", "Open a scene file (e.g. scenes/combo3.json) as the live scene. Returns its cards and length.",
             {"type": "object", "properties": {"path": S}, "required": ["path"], "additionalProperties": False}),
    "new": ("new", "Start an empty scene (no cards). Build it with run: pose= then add.",
            {"type": "object", "properties": {}, "additionalProperties": False}),
    "run": ("run", "Run steps in order, as the window's buttons would: e.g. [\"card=2\", \"pose=raise the right arm 90\", "
            "\"update\"], [\"add\", \"name=hit\"], [\"weapon_metal_bat\", \"weapon_in_right_hand\"], [\"slower_10\"], "
            "[\"fix=1\"]. The step list is `commands` plus card=N, pose=..., name=..., fix=N. Stops at the first failing step.",
            {"type": "object", "properties": {"steps": {"type": "array", "items": S, "minItems": 1}}, "required": ["steps"], "additionalProperties": False}),
    "pose": ("pose", "Pose the body in words: 'raise the right arm 90, bend the left elbow 45' (a number turns BY that "
             "much; 'to N' sets the angle). Says what each joint REACHED and where a limit stopped it.",
             {"type": "object", "properties": {"text": S}, "required": ["text"], "additionalProperties": False}),
    "state": ("state", "The body: every joint's bend/side/twist (deg), where 17 parts are (points, m: y up, +z his "
              "front), the weapon's knob and tip. Give t (s) or frame + fps for a moment of the scene; none = as it stands.",
              {"type": "object", "properties": {"t": N, "frame": {"type": "integer"}, "fps": N}, "additionalProperties": False}),
    "measure": ("measure", "Numbers you would otherwise eyeball, at a moment t (s) of what plays, each with its unit: what = "
                "[\"distance hand_r head\", \"angle upperarm_r lowerarm_r hand_r\" (180 = straight), \"height head\", "
                "\"speed weapon_tip\" (m/s), \"clearance\" (weapon to dummy, m; < 0 = in it)]. Frames and formulas: docs/AGENT_MATH.md.",
                {"type": "object", "properties": {"what": {"type": "array", "items": S, "minItems": 1}, "t": N, "frame": {"type": "integer"}, "fps": N},
                 "required": ["what"], "additionalProperties": False}),
    "describe": ("describe", "The scene: its cards (name, times, the pose's gist), length, weapon, settings.",
                 {"type": "object", "properties": {}, "additionalProperties": False}),
    "check": ("check", "Grade the motion against real recorded human motion: numbered findings (MUST FIX = breaks a human "
              "limit; look = looks off), each with its card, time and a fix if one exists (run fix=N).",
              {"type": "object", "properties": {}, "additionalProperties": False}),
    "diff": ("diff", "What changed between a scene file and the live scene: cards added/removed/renamed, timing, joints.",
             {"type": "object", "properties": {"path": S}, "required": ["path"], "additionalProperties": False}),
    "validate": ("validate", "Check a scene file (or the live scene, with no path) against docs/scene.schema.json.",
                 {"type": "object", "properties": {"path": S}, "additionalProperties": False}),
    "save": ("save", "Save the live scene into scenes/_wip/ (e.g. scenes/_wip/my_fight.json). Nothing else is writable.",
             {"type": "object", "properties": {"out": S}, "required": ["out"], "additionalProperties": False}),
    # C06: the maths for building and for pictures (serve methods outside METHODS: AgentTools.MCP_EXTRA)
    "frame_facts": ("frame_facts", "Numbers for the picture, no screenshot: the silhouette's px box, share of the frame, cut, centre, top/bottom rows per piece "
                    "(pieces: names or col* patterns; camera {pos, target, fov}; w, h; part {record} frames a given part). Also `light`: per piece emission, "
                    "peak_luminance, glow_px, which edges it touches, the brightest_piece, and touching_frame_edge (and _with_glow).",
                    {"type": "object", "properties": {"pieces": {"type": "array", "items": S}, "camera": {"type": "object"}, "w": N, "h": N, "part": {"type": "object"}}, "additionalProperties": False}),
    "dyntopo": ("dyntopo", "Dynamic topology step: under the sculpt brush edges longer than L_max = detail x radius are split and edges shorter than 0.4 L_max are collapsed. "
                "Runs one step on a test sphere and returns tris before/after, splits, collapses, edges in the brush outside the band (band_bad), min/max edge in mm, manifold, native, ms.",
                {"type": "object", "properties": {"radius": N, "detail": N, "levels": N}, "additionalProperties": False}),
    "texture_paint": ("texture_paint", "Texture paint: one brush stamp in SCREEN px (x, y, radius) projected onto a built-in UV-mapped shape (sphere or cylinder, camera 3 m back) and written into the texture's texels on every UV island it covers, "
                      "with seam bleed (pad texels) so no seam shows; back-facing and occluded surface is left alone. Returns texels written, screen_pct, engine (native / gdscript), ms, tex_hash.",
                      {"type": "object", "properties": {"shape": S, "x": N, "y": N, "radius": N, "size": N, "color": S, "strength": N, "hardness": N, "pad": N, "w": N, "h": N}, "additionalProperties": False}),
    "blend_matrix": ("blend_matrix", "Blend matrix of a moveset: every clip crossfaded into every other (the end of A into the start of B over blend_s) and checked for limit breaks (deg, with the joint), "
                     "self-clash (mm) and planted-foot skate (mm), plus the pose distance at the seam; a grid (B bad, w watch, . ok) and the ranked bad pairs with their numbers. clips = scene files "
                     "(else every scene and move with motion); a and b name one pair to get its cell; full adds the whole matrix.",
                     {"type": "object", "properties": {"clips": {"type": "array", "items": S}, "blend_s": N, "a": S, "b": S, "full": {"type": "boolean"}, "top": N}, "additionalProperties": False}),
    "cancel_windows": ("cancel_windows", "Where can the next move start? Cancel windows from the body: the frame runs (f0 to f1, at least min_run long) where the body is balanced (COM inside the feet), slow (COM velocity and whole-body angular momentum under thresholds) and no foot is off the floor. "
                       "clip = a scene file (else the live scene); frame adds whether that frame is cancelable; v_max (m/s), h_max (m^2/s per unit mass), margin_min (m) override the thresholds.",
                       {"type": "object", "properties": {"clip": S, "frame": {"type": "integer"}, "fps": N, "v_max": N, "h_max": N, "margin_min": N}, "additionalProperties": False}),
    "reactable": ("reactable", "Is each strike reactable? Per strike: the frame a viewer can first SEE it coming (the tell), its first active frame, the window between them and the frames a human needs "
                  "(plus latency_ms), status reactable / not reactable and the margin. clip = a scene file (else the live scene); frame adds what that frame is (tell / active / idle).",
                  {"type": "object", "properties": {"clip": S, "frame": {"type": "integer"}, "latency_ms": N, "fps": N}, "additionalProperties": False}),
    "throw_check": ("throw_check", "Does the throw work? Two bodies judged frame by frame: verdict (throw works / no kuzushi / thrower falls / no contact), the key frame, and per frame the partner's "
                    "extrapolated centre of mass outside his feet (out_m) and the thrower's own balance margin (margin_m). clip = a scene file with a partner (else the live scene); thrower 0 = hero, 1 = partner. brief true = only the verdict, the key frame, the partner out and the thrower margin (under 1 KB).",
                    {"type": "object", "properties": {"clip": S, "fps": N, "thrower": {"type": "integer"}, "brief": {"type": "boolean"}}, "additionalProperties": False}),
    "impact_align": ("impact_align", "Impact alignment at the contact frame: flags a bent wrist on a punch, a wrist past the safe load line, a locked knee on a kick, an elbow snapped straight on a miss, each with the angle and a fix pose. clip = a scene file (else the live scene), or give ang {joint: [bend, side, twist]} with kind punch|kick, side l|r, miss.",
                     {"type": "object", "properties": {"clip": S, "fps": N, "ang": {"type": "object"}, "kind": S, "side": S, "miss": {"type": "boolean"}}, "additionalProperties": False}),
    "bake_reaction": ("bake_reaction", "Bake the hit reaction onto the struck partner at the contact frame: the region (from the fist's height, or tag/y/head_y/region) and impulse give region_react's joint deltas, written as one card that arrives at contact + drop delay. Frames before the contact do not change. One undo step on the live scene; with clip a copy is baked and the numbers returned.",
                      {"type": "object", "properties": {"clip": S, "frame": {"type": "integer"}, "tag": S, "y": N, "head_y": N, "region": S, "impulse": N, "side": S}, "additionalProperties": False}),
    "fix_impact": ("fix_impact", "Fix the flagged impact (bent wrist, locked knee) at the contact frame by writing impact_align's fix pose into the cards around it. One undo step; an error when the impact is clean.",
                   {"type": "object", "properties": {"clip": S, "fps": N}, "additionalProperties": False}),
    "bake_momentum": ("bake_momentum", "Key body_collide's after-hit velocities onto both bodies' roots (pelvis offset cards at 0.1/0.2/0.4/0.8 s after the contact). v_a/v_b [x,y,z] m/s, m_a/m_b kg override the measured root speeds and masses; t forces a contact time. One undo step.",
                      {"type": "object", "properties": {"clip": S, "frame": {"type": "integer"}, "t": N, "v_a": {"type": "array"}, "v_b": {"type": "array"}, "m_a": N, "m_b": N, "sex": S, "e": N}, "additionalProperties": False}),
    "hit_region": ("hit_region", "Hit reaction by body region: from an anatomy tag (obliques_r = liver, face low = chin, quadriceps = thigh, abdominals high = solar plexus) and the impulse (N s) it returns the region and joint deltas (liver folds to the hit side with a delayed drop, chin snaps the head and buckles both knees, thigh buckles the hit leg, solar plexus folds forward), inside body limits, growing with impulse.",
                   {"type": "object", "properties": {"tag": S, "y": N, "head_y": N, "impulse": N, "side": S}, "required": ["tag"], "additionalProperties": False}),
    "body_collide": ("body_collide", "Shoulder charge / tackle: momentum shared between two bodies by de Leva upper-body mass; the lighter one changes speed more. Returns after-velocities, momentum before/after, and pelvis keys for both bodies.",
                     {"type": "object", "properties": {"m_a": N, "v_a": {"type": "array"}, "m_b": N, "v_b": {"type": "array"}, "sex": S, "e": N}, "required": ["m_a", "v_a", "m_b"], "additionalProperties": False}),
    "disarm_check": ("disarm_check", "Does a disarm work? Lever torque on the wrist (force x lever arm) against the grip hold (hands x friction x grip force x handle radius, from the grip book). Verdict: grip holds / works / wrist breaks first, with the torques. Give kind + grip (a grip-book name) or hands + lever_m; force_n, grip_n optional.",
                     {"type": "object", "properties": {"kind": S, "grip": S, "hands": {"type": "integer"}, "lever_m": N, "force_n": N, "grip_n": N}, "additionalProperties": False}),
    "group_fight": ("group_fight", "One vs many: schedule attackers around the hero by reach and line of sight. Returns a timed attack schedule (no two from the same side at once, none starting out of reach, every attacker a window), a wait position each, and the check counts. attackers = [{id, x, z, reach}] metres from the hero (facing +z).",
                    {"type": "object", "properties": {"attackers": {"type": "array"}}, "required": ["attackers"], "additionalProperties": False}),
    "lock_check": ("lock_check", "Does the lock reach his limit, or go past it? Two bodies judged frame by frame: the partner's elbow, wrist and shoulder angles the clip asks, against his joint limits, on the arm the locker touches. "
                   "Verdict: lock not on / at limit (within 5 deg) / past limit: injury (joint, axis, degrees past) / no contact; the key frame; per frame margin_deg. clip = a scene file with a partner (else the live scene); locker 0 = hero, 1 = partner.",
                   {"type": "object", "properties": {"clip": S, "fps": N, "locker": {"type": "integer"}}, "additionalProperties": False}),
    "look_facts": ("look_facts", "Numbers for how the final picture LOOKS per piece / kind / nature item (colour, contrast, neon, ring, share), from an id render. "
                   "Needs a part view or nature items showing: give piece, kind, nature or targets; camera, w, h optional.",
                   {"type": "object", "properties": {"piece": S, "kind": S, "nature": S, "targets": {"type": "array"}, "camera": {"type": "object"}, "w": N, "h": N}, "additionalProperties": True}),
    "final_render": ("final_render", "Render the shot camera as a PNG sequence + mp4 with a quality preset: draft | final | final_hq (Final HQ = GI bounce, depth of field at the shot's focus, motion blur from sub-frames across the shutter, jittered accumulation). "
                     "w, h (default 1920x1080), first, count (frame range), out (folder), subframes (default 8), accum (default 2), shutter (fraction of a frame, 0.5). Returns dir, frames, mp4.",
                     {"type": "object", "properties": {"preset": S, "w": N, "h": N, "first": N, "count": N, "out": S, "subframes": N, "accum": N, "shutter": N}, "additionalProperties": False}),
    "nature": ("nature", "Trees, hedges, shrubs, grass, flowers, paths, scatter: op list | add {item} | words {text: '2 oak trees 5 m tall'} | remove {id} | clear | measure.",
               {"type": "object", "properties": {"op": S, "item": {"type": "object"}, "text": S, "id": S}, "additionalProperties": True}),
    "part_warn": ("part_warn", "The part's warnings at its level (off / look / print / engineering), the list the Part panel shows; level, mute, unmute edit the record "
                  "(one undo step). part {record} reads a given part.",
                  {"type": "object", "properties": {"level": S, "mute": {}, "unmute": {}, "part": {"type": "object"}}, "additionalProperties": False}),
    "part_facts": ("part_facts", "The part as numbers: per body volume (mm3), box, touches/overlaps/near, repeats, floats; box_mm of the whole part (its top is box_mm.max[1]), "
                   "bodies_math, failed_steps, touching_pairs, holes and fillets with radii; gap [a, b] (1-based) gives the distance between two bodies in mm. "
                   "part {record} or path, else the live part.",
                   {"type": "object", "properties": {"part": {"type": "object"}, "path": S, "gap": {"type": "array", "items": N, "minItems": 2, "maxItems": 2}, "cap": N, "near_mm": N}, "additionalProperties": False}),
    "part_assert": ("part_assert", "One-line checks on the part (e.g. 'piston touches barrel clearance 0.0-0.2 mm'); no lines = the record's saved asserts; save keeps the lines that pass.",
                    {"type": "object", "properties": {"lines": {"type": "array", "items": S}, "part": {"type": "object"}, "path": S, "save": {"type": "boolean"}, "clear": {"type": "boolean"}}, "additionalProperties": False}),
    "lightrig": ("lightrig", "Light rig: {look: studio|noir|overcast|sunset|night} puts a preset on the shot at the playhead; {sky: clear_day|overcast|sunset|night|studio_grey|\"\"} sets the sky map with rot (deg) and int; {link: {key|fill|rim: true}} makes a light character-only (it skips the floor). {} returns the facts: sky, links, lights.",
                 {"type": "object", "properties": {"look": S, "sky": S, "rot": N, "int": N, "link": {"type": "object"}}, "additionalProperties": True}),
    "fits": ("fits", "ISO 286 fits and stack-ups as data: each mating pair (fit kind, min/max clearance in um, interference-as-sliding flag), each stack-up (nominal, worst case, RSS) and every sized dimension with its class. assembly {record} or path, else the Assembly on screen, else the live part dimensions; csv adds each stack-up CSV.",
             {"type": "object", "properties": {"assembly": {"type": "object"}, "path": S, "part": {"type": "object"}, "csv": {"type": "boolean"}}, "additionalProperties": False}),
    "part_build": ("part_build", "Build a part from steps in ONE call (mm, y up); append: true adds steps to the part on screen (send only new ones). "
                   "Main step: {t:'prim', kind: box|cylinder|tube|cone|sphere|wedge, op: new|join|cut|intersect, into: body, box/wedge x,y,z (corner) w,h,d; "
                   "cylinder x,y,z (cap centre) axis x|y|z r len; tube +r_in; cone +r2; sphere x,y,z r}. Also pattern {body,kind linear|circular,count,mm,dir|axis,deg}, "
                   "move {body,d:[x,y,z]}, appear {body,color:[r,g,b]}, bname {body,called}, hinge, shell, combine. Returns bodies, box_mm, per-step errors; save, facts optional.",
                   {"type": "object", "properties": {"steps": {"type": "array", "items": {"type": "object"}}, "part": {"type": "object"}, "append": {"type": "boolean"},
                                                     "name": S, "save": {"type": "boolean"}, "facts": {"type": "boolean"}}, "additionalProperties": False}),
    "commands": ("commands", "The window's commands (id, name, keys, whether it edits): the ids are run steps. The whole list is 500+ "
                 "commands (20-30k tokens): give find (a few words, e.g. 'mirror pose') to get only the best 25 matches.",
                 {"type": "object", "properties": {"find": S}, "additionalProperties": False}),
}

# C06: the maths tools are OPT-IN (--math or POSER_MCP_MATH=1): tests/py/mcp_drive.py pins the default list at 12 tools and an existing default does not change
MATH_TOOLS = ["cancel_windows", "reactable", "throw_check", "lock_check", "impact_align", "hit_region", "body_collide", "disarm_check", "group_fight", "bake_reaction", "fix_impact", "bake_momentum", "frame_facts", "look_facts", "nature", "part_warn", "part_facts", "part_assert", "part_build", "fits", "lightrig", "final_render", "blend_matrix", "texture_paint", "dyntopo"]
MATH = "--math" in sys.argv or os.environ.get("POSER_MCP_MATH") == "1"
_MATH = {k: TOOLS.pop(k) for k in MATH_TOOLS}
if MATH:
    TOOLS.update(_MATH)


# MCPFAST: --cad (or POSER_MCP_CAD=1) adds the CAD tools, the maths tools, `batch`, and the cheap replies (compact text only, numbers rounded to `prec`
# decimals, `diff` for only what changed). Without it the server is exactly what it was.
CAD = "--cad" in sys.argv or os.environ.get("POSER_MCP_CAD") == "1"
OBJ = {"type": "object"}
B = {"type": "boolean"}
CAD_TOOLS = {
    "cad_part": ("cad_part", "Build or replay a Part record in the live session: {name, record: {features: [...]}} or {name, path}; a name already built needs no record. "
                 "Cached by the record's hash (cached: true = no replay); a changed record rebuilds. Returns name, hash, bodies, volume_mm3, size_mm. detail: true adds per-body volumes.",
                 {"type": "object", "properties": {"name": S, "record": OBJ, "path": S, "detail": B, "prec": N}, "additionalProperties": False}),
    "cad_asm": ("cad_asm", "Run N assembly steps in one call: ops [{op: new|load|add|place|remove|joint|drive|drive_to, ...}] (add {part, id?, name?, pos?, rot?}: mm, deg; load {assembly}; "
                "joint {kind, a, b, axis, origin, origin_b?}; drive {name, part, kind, axis, origin, range}; drive_to {drive, value}). Returns ids + names added and ONLY the places that moved since the last reply.",
                {"type": "object", "properties": {"ops": {"type": "array", "items": OBJ, "minItems": 1}, "detail": B, "prec": N}, "required": ["ops"], "additionalProperties": False}),
    "check_fit": ("check_fit", "Every pair of placed parts, exact solids: overlap volume (mm3) and distance (mm). Terse: the overlap volumes of the pairs whose boxes are near (1-10 ms each); distance: true (or detail: true) adds the exact distances (0.1-0.3 s a pair, the 8 nearest listed; detail lists every pair). "
                  "near_mm (2) = how close counts and the box prefilter; hit_mm3 (1) = what counts as an overlap; drive + value poses the assembly first.",
                  {"type": "object", "properties": {"near_mm": N, "hit_mm3": N, "drive": S, "value": N, "cap": N, "distance": B, "detail": B, "prec": N}, "additionalProperties": False}),
    "bom": ("bom", "The assembly's bill of materials: per line part, count, mass_kg, cost; totals. detail: true adds material, volume, ids, warnings.",
            {"type": "object", "properties": {"detail": B, "prec": N}, "additionalProperties": False}),
    "eval_gd": ("eval_gd", "Run a short GDScript snippet (the body of a function; one expression line returns itself) in the live session, to test an idea without a Godot boot. "
                "Has H.write(path, text) (only scenes/_wip and the temp dir; anything else is refused), H.part(name), H.solids(name), H.assembly(), H.note(x), m, KCad. "
                "Files, processes and engine internals are refused.",
                {"type": "object", "properties": {"code": S, "detail": B, "prec": N}, "required": ["code"], "additionalProperties": False}),
    "look4d": ("look4d", "Look at the live assembly in steps, cheapest first. level 0 (default, ~30 tokens): moving, fastest, contacts, near misses, hidden, held. level 1: moving parts [id, pos, vel, speed], static parts as names, touching and held pairs. "
               "level 2 + part: one part in full (size, rotation, accel, joint and limits, mass, contacts with point/normal/penetration, nearest gaps with time to collision, support, visible share, last/next positions). "
               "level 3 + ids, t, t1, step: a track. since: only what changed since that time. t in s (the assembly's animation) ; cam {pos, look, fov} optional. image: true returns the annotated image path when a display exists. A screenshot is the last resort.",
               {"type": "object", "properties": {"level": N, "part": S, "ids": {"type": "array", "items": S}, "t": N, "t1": N, "step": N, "since": N, "parts": {"type": "array", "items": S}, "cam": OBJ, "h": N, "image": B, "tokens": B}, "additionalProperties": False}),
    "sweep": ("sweep", "Sweep a drive or a parameter and get ONE summary instead of every step: {drive, from, to, steps} or {param: {id, field: pos|rot, axis}, from, to, steps} or values []. "
              "metric overlap_mm3 (default) | n_overlaps | min_gap_mm (exact, slow); threshold. Returns worst {value, at, pair}, count over the threshold, where, min, max. The 36-angle CH13 sweep is ~0.4 KB instead of 15.9 KB.",
              {"type": "object", "properties": {"drive": S, "param": OBJ, "from": N, "to": N, "steps": N, "values": {"type": "array", "items": N}, "metric": S, "threshold": N, "near_mm": N, "hit_mm3": N}, "additionalProperties": False}),
    "cad_reset": ("cad_reset", "Forget built parts (cache: true) and/or the assembly (asm: true); both by default.",
                  {"type": "object", "properties": {"cache": B, "asm": B}, "additionalProperties": False}),
}
BATCH = ("batch", "Run N tool calls in one round trip: calls [{tool, args}], stops at the first error. Returns one terse result per call.",
         {"type": "object", "properties": {"calls": {"type": "array", "items": {"type": "object", "properties": {"tool": S, "args": OBJ}, "required": ["tool"]}, "minItems": 1}}, "required": ["calls"], "additionalProperties": False})
if CAD:
    TOOLS.update(_MATH)
    TOOLS.update(CAD_TOOLS)
    for _k, _v in list(TOOLS.items()):   # every serve tool takes prec (decimals kept, default 4) and diff (only what changed since this tool's last reply)
        if _k not in CAD_TOOLS:
            _v[2]["properties"].update({"prec": N, "diff": B})
    TOOLS["batch"] = BATCH
_LAST = {}   # tool -> its last result, for diff


def rnd(v, prec):
    if isinstance(v, float):
        return round(v, prec)
    if isinstance(v, list):
        return [rnd(x, prec) for x in v]
    if isinstance(v, dict):
        return {k: rnd(x, prec) for k, x in v.items()}
    return v


def dif(new, old):
    """only what differs from old: changed / new keys of a dict (recursively); anything else is given whole"""
    if isinstance(new, dict) and isinstance(old, dict):
        d = {k: dif(v, old[k]) if k in old else v for k, v in new.items() if k not in old or v != old[k]}
        gone = [k for k in old if k not in new]
        if gone:
            d["_gone"] = gone
        return d
    return new


def log(*a):
    print(*a, file=sys.stderr, flush=True)


class Session:
    """one `poser_cli serve` process, started when first needed"""

    def __init__(self):
        self.p = None
        self.q = queue.Queue()
        self.n = 0
        self.lock = threading.RLock()
        self.startup_ms = None
        self.reported = False

    def start(self):
        with self.lock:
            if self.p is not None and self.p.poll() is None:
                return
            self._start()

    def _start(self):
        t0 = time.time()
        self.p = subprocess.Popen([GODOT, "--headless", "--path", PROJ, "-s", "tools/poser_cli.gd", "--", "serve"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, encoding="utf-8", bufsize=1)
        threading.Thread(target=lambda: [self.q.put(l) for l in iter(self.p.stdout.readline, "")] + [self.q.put(None)], daemon=True).start()
        hello = self.read()
        self.startup_ms = round((time.time() - t0) * 1000)
        log("poser serve ready:", hello.get("params", {}).get("methods"), "in %d ms" % self.startup_ms)

    def read(self):
        while True:
            line = self.q.get(timeout=TIMEOUT)
            if line is None:
                raise RuntimeError("the poser session ended (Godot exited)")
            if line.strip().startswith("{"):
                return json.loads(line)

    def call(self, method, params):
        if self.p is None or self.p.poll() is not None:
            self.start()
        with self.lock:
            self.n += 1
            self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params}) + "\n")
            self.p.stdin.flush()
            return self.read()

    def stop(self):
        if self.p is not None and self.p.poll() is None:
            try:
                self.call("quit", {})
                self.p.wait(timeout=20)
            except Exception:
                self.p.kill()


def result(id_, r):
    return {"jsonrpc": "2.0", "id": id_, "result": r}


def error(id_, code, msg):
    return {"jsonrpc": "2.0", "id": id_, "error": {"code": code, "message": msg}}


def call_cad(name, args, sess):
    """MCPFAST reply shaping: compact text only (no structuredContent twin), numbers rounded to prec, diff on request, the startup cost once"""
    args = dict(args)
    prec = int(args.pop("prec", 4)) if name not in CAD_TOOLS and name != "batch" else 4
    want_diff = bool(args.pop("diff", False)) if name not in CAD_TOOLS else False
    if name == "batch":
        outs = []
        for c in args.get("calls") or []:
            if c.get("tool") not in TOOLS or c.get("tool") == "batch":
                outs.append({"error": "no tool '%s'" % c.get("tool")})
                break
            r = call_cad(c["tool"], c.get("args") or {}, sess)
            t = r["content"][0]["text"]
            if r["isError"]:
                outs.append({"error": t})
                break
            outs.append(json.loads(t))
        return {"content": [{"type": "text", "text": json.dumps(outs, separators=(",", ":"))}], "isError": any(isinstance(o, dict) and "error" in o for o in outs)}
    try:
        r = sess.call(TOOLS[name][0], args)
    except Exception as e:
        sess.p = None
        return {"content": [{"type": "text", "text": "the poser session failed: %s (the next call starts a new one)" % e}], "isError": True}
    if "error" in r:
        e = r["error"]
        return {"content": [{"type": "text", "text": e["message"] + (("\n" + json.dumps(e["data"])) if e.get("data") else "")}], "isError": True}
    res = r["result"]
    if name not in CAD_TOOLS:
        res = rnd(res, prec)
    if want_diff:
        full, res = res, dif(res, _LAST.get(name, {}))
        _LAST[name] = full
    if isinstance(res, dict) and not sess.reported and sess.startup_ms is not None:
        sess.reported = True
        res = dict(res, startup_ms=sess.startup_ms)
    return {"content": [{"type": "text", "text": json.dumps(res, separators=(",", ":"))}], "isError": False}


def handle(msg, sess):
    id_ = msg.get("id")
    m = msg.get("method")
    if id_ is None:   # a notification (notifications/initialized, cancelled): nothing to answer
        return None
    if m == "initialize":
        if CAD and sess.p is None:   # boot Godot while the agent reads the tool list: the first call finds it ready
            threading.Thread(target=sess.start, daemon=True).start()
        want = (msg.get("params") or {}).get("protocolVersion")
        return result(id_, {"protocolVersion": want if want in VERSIONS else VERSIONS[0],
                            "capabilities": {"tools": {"listChanged": False}},
                            "serverInfo": {"name": "poser", "version": "15.0"},
                            "instructions": "Poser: a mannequin posing and animation tool. Start with open (or new), "
                                            "pose in words, add cards with run, read state at any t, check, save into scenes/_wip/."})
    if m == "ping":
        return result(id_, {})
    if m == "tools/list":
        return result(id_, {"tools": [{"name": k, "description": v[1], "inputSchema": v[2]} for k, v in TOOLS.items()]})
    if m == "tools/call":
        p = msg.get("params") or {}
        name = p.get("name")
        if name not in TOOLS:
            return error(id_, -32602, "no tool '%s': the tools are %s" % (name, ", ".join(TOOLS)))
        args = p.get("arguments") or {}
        if CAD:
            return result(id_, call_cad(name, args, sess))
        try:
            r = sess.call(TOOLS[name][0], args)
        except Exception as e:   # the session died or timed out: a tool error the agent can read, not a dead server
            sess.p = None
            return result(id_, {"content": [{"type": "text", "text": "the poser session failed: %s (the next call starts a new one)" % e}], "isError": True})
        if "error" in r:
            e = r["error"]
            text = e["message"] + (("\n" + json.dumps(e["data"])) if e.get("data") else "")
            return result(id_, {"content": [{"type": "text", "text": text}], "isError": True})
        # compact JSON (no spaces after , and :): the same data, about 10% fewer tokens for the agent reading it
        return result(id_, {"content": [{"type": "text", "text": json.dumps(r["result"], separators=(",", ":"))}],
                            "structuredContent": r["result"] if isinstance(r["result"], dict) else {"items": r["result"]},
                            "isError": False})
    return error(id_, -32601, "no method '%s' (initialize, ping, tools/list, tools/call)" % m)


def main():
    sess = Session()
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                out = error(None, -32700, "not JSON")
            else:
                out = handle(msg, sess) if isinstance(msg, dict) else error(None, -32600, "not a request")
            if out is not None:
                sys.stdout.write(json.dumps(out) + "\n")
                sys.stdout.flush()
    finally:
        sess.stop()


if __name__ == "__main__":
    main()
