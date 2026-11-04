"""POSER AS AN MCP SERVER (round 15, GATES V1). Any MCP client (Claude Code, Claude Desktop, an agent SDK) can drive the
poser: open a scene, pose the body in words, read where every part is at any moment, check the motion, save.

  python tools/mcp/poser_mcp.py [--godot <Godot executable>] [--math]      (or set POSER_GODOT; --math / POSER_MCP_MATH=1 adds the six C06 tools)

It speaks MCP over stdio (one JSON-RPC message per line) using the standard library only, and runs ONE live session of
`poser_cli serve` underneath (tools/poser_cli.gd), started on the first tool call. Each MCP tool is one serve method,
so the two never disagree; a serve error comes back as a tool result with isError and serve's own message (it says
what to do next). Scenes are saved only into scenes/_wip/ (serve refuses anything else).

Claude Code:  claude mcp add poser -- python C:/Users/Nick/Desktop/poser/tools/mcp/poser_mcp.py
"""
import json, os, queue, subprocess, sys, threading

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
    "look_facts": ("look_facts", "Numbers for how the final picture LOOKS per piece / kind / nature item (colour, contrast, neon, ring, share), from an id render. "
                   "Needs a part view or nature items showing: give piece, kind, nature or targets; camera, w, h optional.",
                   {"type": "object", "properties": {"piece": S, "kind": S, "nature": S, "targets": {"type": "array"}, "camera": {"type": "object"}, "w": N, "h": N}, "additionalProperties": True}),
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
    "commands": ("commands", "The window's commands (id, name, keys, whether it edits): the ids are run steps. The whole list is 500+ "
                 "commands (20-30k tokens): give find (a few words, e.g. 'mirror pose') to get only the best 25 matches.",
                 {"type": "object", "properties": {"find": S}, "additionalProperties": False}),
}

# C06: the maths tools are OPT-IN (--math or POSER_MCP_MATH=1): tests/py/mcp_drive.py pins the default list at 12 tools and an existing default does not change
MATH_TOOLS = ["frame_facts", "look_facts", "nature", "part_warn", "part_facts", "part_assert"]
MATH = "--math" in sys.argv or os.environ.get("POSER_MCP_MATH") == "1"
_MATH = {k: TOOLS.pop(k) for k in MATH_TOOLS}
if MATH:
    TOOLS.update(_MATH)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


class Session:
    """one `poser_cli serve` process, started when first needed"""

    def __init__(self):
        self.p = None
        self.q = queue.Queue()
        self.n = 0

    def start(self):
        self.p = subprocess.Popen([GODOT, "--headless", "--path", PROJ, "-s", "tools/poser_cli.gd", "--", "serve"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, encoding="utf-8", bufsize=1)
        threading.Thread(target=lambda: [self.q.put(l) for l in iter(self.p.stdout.readline, "")] + [self.q.put(None)], daemon=True).start()
        hello = self.read()
        log("poser serve ready:", hello.get("params", {}).get("methods"))

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


def handle(msg, sess):
    id_ = msg.get("id")
    m = msg.get("method")
    if id_ is None:   # a notification (notifications/initialized, cancelled): nothing to answer
        return None
    if m == "initialize":
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
