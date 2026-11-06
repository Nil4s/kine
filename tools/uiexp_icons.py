"""UIEXP icon generator (lane L2): writes assets/icons/uiexp/<id>.svg and the id list scripts/uiexp_icons_list.gd.
Original drawings (no icon pack): a 24 px grid, 2 px stroke, round caps, the palette's text colour for the body of a glyph and its
amber for the one part that says what it does. The loader (scripts/uiexp_icons.gd) swaps both colours for the light theme.
Run: python tools/uiexp_icons.py"""
import os

INK = "#ECEFF4"
AMB = "#FFC733"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons", "uiexp")

# each icon: list of (kind, svg-attributes-string, accent?)  kind: p=path, c=circle, r=rect, l=line
def P(d, a=False, fill=False): return ("p", d, a, fill)
def C(cx, cy, r, a=False, fill=False): return ("c", (cx, cy, r), a, fill)
def R(x, y, w, h, a=False, rx=0, fill=False): return ("r", (x, y, w, h, rx), a, fill)

ICONS = {
 # SKETCH
 "line": [P("M5 19 L19 5", True), C(5, 19, 1.6, False, True), C(19, 5, 1.6, False, True)],
 "rectangle": [R(4, 6, 16, 12, True), C(4, 6, 1.4, False, True), C(20, 18, 1.4, False, True)],
 "circle": [C(12, 12, 8, True), C(12, 12, 1.2, False, True)],
 "arc": [P("M4 18 A9 9 0 0 1 20 18", True), C(4, 18, 1.5, False, True), C(20, 18, 1.5, False, True)],
 "spline": [P("M3 17 C7 5 11 5 12 12 S17 19 21 7", True)],
 "dimension": [P("M4 7 L4 17 M20 7 L20 17"), P("M4 12 L20 12", True), P("M7 9.5 L4 12 L7 14.5 M17 9.5 L20 12 L17 14.5")],
 "constrain": [P("M4 9 L20 9 M4 15 L20 15", True), P("M12 4 L12 20")],
 "finish_sketch": [R(4, 4, 16, 16, False, 2), P("M8 12.5 L11 15.5 L16.5 9", True)],
 "snap": [P("M5 5 L5 19 L19 19"), C(12, 12, 2.2, True), P("M12 5 L12 9.8 M5 12 L9.8 12")],
 # CREATE
 "extrude": [P("M5 17 L12 20 L19 17 L12 14 Z"), P("M12 14 L12 6", True), P("M8.5 9.5 L12 5.5 L15.5 9.5", True)],
 "revolve": [P("M12 3 L12 21"), P("M12 7 C19 7 19 17 12 17", True), P("M12 7 L8 7 L8 17 L12 17")],
 "mirror": [P("M12 3 L12 21", False), P("M10 7 L4 12 L10 17 Z"), P("M14 7 L20 12 L14 17 Z", True)],
 "loft": [R(4, 15, 10, 5), P("M14 7 L20 7 L20 9 L14 9 Z", True), P("M4 15 L14 7 M14 20 L20 9")],
 "sweep": [C(5, 18, 2.6), P("M8 17 C13 17 12 8 19 6", True), P("M16 5 L19.5 6 L18 9.5", True)],
 "offset_plane": [P("M3 17 L9 13 L21 13 L15 17 Z"), P("M3 10 L9 6 L21 6 L15 10 Z", True), P("M12 15 L12 9", False)],
 "split": [R(4, 4, 16, 16), P("M3 12 L21 12", True)],
 "canvas": [R(3.5, 4.5, 17, 15), P("M3.5 15 L9 10 L13 14 L16 11.5 L20.5 16", True), C(8, 8.5, 1.4, False, True)],
 "pattern": [R(3.5, 3.5, 5, 5, True), R(10.5, 3.5, 5, 5), R(17, 3.5, 3.5, 5), R(3.5, 10.5, 5, 5), R(10.5, 10.5, 5, 5), R(3.5, 17, 5, 3.5)],
 "combine": [C(9, 12, 6), C(15, 12, 6, True)],
 "primitive": [P("M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z"), P("M4 7.5 L12 12 L20 7.5 M12 12 L12 21", True)],
 "ornament": [P("M12 3 C13 8 16 11 21 12 C16 13 13 16 12 21 C11 16 8 13 3 12 C8 11 11 8 12 3 Z", True)],
 "roof_shell": [P("M3 13 L12 5 L21 13"), P("M6 11 L6 20 L18 20 L18 11", False), P("M8 13.5 L12 10 L16 13.5", True)],
 "hinge": [R(3.5, 6, 7, 12), R(13.5, 6, 7, 12), C(12, 12, 1.6, True, True), P("M12 6 L12 9 M12 15 L12 18", True)],
 # MODIFY
 "fillet": [P("M5 4 L5 14 A6 6 0 0 0 11 20 L20 20", True), P("M5 4 L20 4 L20 20", False)],
 "chamfer": [P("M5 4 L5 12 L12 20 L20 20", True), P("M5 4 L20 4 L20 20")],
 "shell": [R(3.5, 3.5, 17, 17), R(8, 8, 8, 8, True)],
 "appearance": [C(12, 12, 8.5), P("M12 3.5 A8.5 8.5 0 0 1 12 20.5 Z", True, True)],
 "offset_face": [P("M4 16 L12 20 L20 16 L12 12 Z"), P("M4 10 L12 14 L20 10 L12 6 Z", True)],
 "draft": [P("M7 20 L7 5 M17 20 L14 5"), P("M5 20 L19 20", False), P("M14 5 L17 5", True), P("M17 20 L14.4 8", True)],
 # INSPECT / PART
 "measure": [P("M3.5 15 L15 3.5 L20.5 9 L9 20.5 Z"), P("M7 12 L9 14 M10 9 L12 11 M13 6 L15 8", True)],
 "section": [P("M4 7 L12 3 L20 7 L20 17 L12 21 L4 17 Z"), P("M3 12 L21 12", True)],
 "part": [P("M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z"), P("M4 7.5 L12 12 L20 7.5 M12 12 L12 21", False), C(12, 12, 1.6, True, True)],
 "undo": [P("M9 8 L4.5 12 L9 16", False), P("M5 12 L14 12 C18 12 19.5 14.5 19.5 17", True)],
 "redo": [P("M15 8 L19.5 12 L15 16", False), P("M19 12 L10 12 C6 12 4.5 14.5 4.5 17", True)],
 "more": [C(5, 12, 1.7, False, True), C(12, 12, 1.7, True, True), C(19, 12, 1.7, False, True)],
 # ASSEMBLY
 "add_part": [P("M4 9 L10 6 L16 9 L16 15 L10 18 L4 15 Z"), P("M4 9 L10 12 L16 9 M10 12 L10 18"), P("M19 4 L19 10 M16 7 L22 7", True)],
 "open": [P("M3.5 18 L3.5 6 L9 6 L11 8.5 L20.5 8.5 L20.5 18 Z"), P("M3.5 18 L6 12 L22 12 L20.5 18", True)],
 "save": [P("M4 4 L17 4 L20 7 L20 20 L4 20 Z"), R(7.5, 4, 8, 5), P("M7.5 20 L7.5 14 L16.5 14 L16.5 20", True)],
 "new": [P("M6 3 L14 3 L19 8 L19 21 L6 21 Z"), P("M14 3 L14 8 L19 8"), P("M12.5 12 L12.5 18 M9.5 15 L15.5 15", True)],
 "move": [P("M12 3 L12 21 M3 12 L21 12", True), P("M9 6 L12 3 L15 6 M9 18 L12 21 L15 18 M6 9 L3 12 L6 15 M18 9 L21 12 L18 15")],
 "turn": [P("M19 12 A7 7 0 1 1 15 5.7", True), P("M12 1.5 L15.5 5.8 L10.8 7.8")],
 "edit_part": [P("M4 20 L5 15 L16 4 L20 8 L9 19 Z"), P("M13.5 6.5 L17.5 10.5", True)],
 "remove": [P("M5 7 L19 7"), P("M9 7 L9 4.5 L15 4.5 L15 7"), P("M7 7 L8 20 L16 20 L17 7"), P("M10 11 L10 16 M14 11 L14 16", True)],
 "fix": [P("M12 4 L12 14", True), P("M8 14 L16 14"), P("M12 14 L12 20"), P("M9 20 L15 20"), C(12, 4, 1.6, False, True)],
 "done": [C(12, 12, 9), P("M7.5 12.5 L10.5 15.5 L16.5 9", True)],
 "back": [P("M10 6 L4 12 L10 18"), P("M4.5 12 L20 12", True)],
 # ENGINEERING
 "motion": [C(7, 12, 4), C(17, 12, 4), P("M10.5 9.5 L13.5 9.5 M10.5 14.5 L13.5 14.5", True), P("M7 6 L7 3 M17 21 L17 18")],
 "bom": [R(3.5, 4.5, 17, 15), P("M3.5 9.5 L20.5 9.5 M3.5 14.5 L20.5 14.5"), P("M9.5 4.5 L9.5 19.5", True)],
 "stages": [P("M4 18 L9 18 L9 13 L14 13 L14 8 L20 8", True), P("M4 21 L20 21")],
 "fits": [C(9, 12, 6), C(15.5, 12, 3.5, True), P("M12.5 12 L19 12", False)],
 "drive": [C(12, 12, 4), P("M12 3 L12 6 M12 18 L12 21 M3 12 L6 12 M18 12 L21 12 M5.6 5.6 L7.7 7.7 M16.3 16.3 L18.4 18.4 M5.6 18.4 L7.7 16.3 M16.3 7.7 L18.4 5.6", True)],
 "joint": [R(3, 9, 8, 6, False, 3), R(13, 9, 8, 6, False, 3), C(11.5, 12, 1.5, True, True)],
 "run": [P("M7 4.5 L19 12 L7 19.5 Z", True)],
 "play": [P("M8 5 L18 12 L8 19 Z", True), P("M4 5 L4 19")],
 "key": [C(8, 12, 4.5, True), P("M12.5 12 L21 12 M18 12 L18 15.5 M21 12 L21 14.5")],
 "unkey": [C(8, 12, 4.5), P("M12.5 12 L21 12 M18 12 L18 15.5"), P("M15 4 L21 10", True)],
 "csv": [P("M6 3 L14 3 L19 8 L19 21 L6 21 Z"), P("M9 12 L16 12 M9 15 L16 15 M9 18 L13 18", True)],
 "copy": [R(8.5, 8.5, 11.5, 11.5, False, 1), P("M15.5 8.5 L15.5 4 L4 4 L4 15.5 L8.5 15.5", True)],
 "cheapest": [C(12, 12, 9), P("M14.5 8.5 C13.5 7.5 9 7.5 9 10 C9 13 15 11 15 14.5 C15 17 10.5 16.7 9.5 15.5", True), P("M12 6 L12 7.6 M12 16.6 L12 18")],
 "plus": [P("M12 5 L12 19 M5 12 L19 12", True)],
 "minus": [P("M5 12 L19 12", True)],
 "flip": [P("M4 9 L20 9 M16 5 L20 9 L16 13", True), P("M20 16 L4 16 M8 12 L4 16 L8 20")],
 "stack": [P("M12 4 L21 8.5 L12 13 L3 8.5 Z", True), P("M3 12.5 L12 17 L21 12.5"), P("M3 16.5 L12 21 L21 16.5")],
 "pair": [C(5.5, 12, 3), C(18.5, 12, 3, True), P("M8.5 12 L15.5 12"), P("M12 8 L12 16", True)],
 # DELIVER
 "stl": [P("M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z"), P("M4 7.5 L12 12 L20 7.5 M12 12 L12 21 M8 5.25 L16 9.75"), P("M9 12 L12 15 L15 12", True)],
 "glb": [P("M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z"), C(12, 12, 3.3, True)],
 "step": [P("M4 20 L4 15 L9 15 L9 10 L14 10 L14 5 L20 5"), P("M4 20 L20 20", True)],
 "video": [R(3, 6, 13, 12, False, 2), P("M16 10.5 L21 7.5 L21 16.5 L16 13.5", True)],
 "drawing": [R(3.5, 3.5, 17, 17), R(7, 7, 6, 6, True), P("M7 17 L17 17 M16 8 L16 13")],
 "schematic": [P("M3 12 L7 12 L8.5 8 L11.5 16 L13 12 L21 12", True), C(3, 12, 1.2, False, True), C(21, 12, 1.2, False, True)],
 "export": [R(3.5, 13, 17, 7.5), P("M12 3.5 L12 14", True), P("M8 8 L12 3.5 L16 8", True)],
 # SHELL / RAIL GROUPS
 "g_sketch": [P("M3.5 20.5 L3.5 11 L13 20.5 Z"), P("M11 11 L17 5 L20 8 L14 14 Z", True)],
 "g_create": [P("M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z"), P("M12 8 L12 16 M8 12 L16 12", True)],
 "g_modify": [P("M5 4 L5 14 A6 6 0 0 0 11 20 L20 20"), P("M9 4 L20 4 L20 15", True)],
 "g_assemble": [R(3.5, 11, 9, 9), R(11.5, 4, 9, 9, True)],
 "g_check": [P("M12 3 L19.5 6 L19.5 12 C19.5 16.5 16 19.5 12 21 C8 19.5 4.5 16.5 4.5 12 L4.5 6 Z"), P("M8.5 12 L11 14.5 L15.5 9.5", True)],
 "g_deliver": [P("M3.5 14 L3.5 20.5 L20.5 20.5 L20.5 14"), P("M7 16 L17 6", True), P("M10 6 L17 6 L17 13", True)],
}


def render(items):
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">']
    for kind, geo, acc, fill in items:
        col = AMB if acc else INK
        f = col if fill else "none"
        if kind == "p":
            out.append('<path d="%s" stroke="%s" fill="%s"%s/>' % (geo, col, f, ' fill-opacity="0.35"' if fill and geo.endswith("Z") else ""))
        elif kind == "c":
            cx, cy, r = geo
            out.append('<circle cx="%s" cy="%s" r="%s" stroke="%s" fill="%s"/>' % (cx, cy, r, col, f))
        else:
            x, y, w, h, rx = geo
            out.append('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" stroke="%s" fill="%s"/>' % (x, y, w, h, rx, col, f))
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    for k, v in ICONS.items():
        with open(os.path.join(OUT, k + ".svg"), "w", newline="\n") as f:
            f.write(render(v))
    ids = list(ICONS.keys())
    with open(os.path.join(os.path.dirname(__file__), "..", "scripts", "uiexp_icons_list.gd"), "w", newline="\n") as f:
        f.write("class_name UiExpIconList\nextends RefCounted\n## GENERATED by tools/uiexp_icons.py: every icon id in assets/icons/uiexp/ (do not edit by hand)\nconst IDS := [%s]\n" % ", ".join('"%s"' % i for i in ids))
    print(len(ids), "icons")


if __name__ == "__main__":
    main()
