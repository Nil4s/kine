"""TEST TOOL (ROADMAP 78): re-encodes an ASCII FBX 7.4 file as BINARY FBX 7.4, the same node tree, so that Blender can read
it (Blender 4.5's importer refuses ASCII FBX). Used only by the Blender check (tests/py/fbx_blender_check.py); the
exporter itself writes ASCII. Run with:  python -I tests/py/fbx_to_binary.py <in.fbx> <out.fbx>

The parser is fbx_check.py's (the same reader that checks the ASCII). Value types are chosen the way FBX writes them:
ids and KTime as int64 ('L'), other integers as int32 ('I'), decimals as float64 ('D'), KeyTime as int64 arrays, KeyValueFloat
as float32 arrays, the KeyAttr arrays as int32 / float32, matrices as float64 arrays; T / Y become bool ('C').
An object's name "Class::name" is written the binary way, "name" + NUL + SOH + "Class".
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fbx_check import parse_block, tokenize  # noqa: E402

MAGIC = b"Kaydara FBX Binary  \x00" + b"\x1a\x00"
NULL_RECORD = b"\x00" * 13
INT_RE = re.compile(r"-?\d+$")
NAME_SEP = "\x00\x01"
ID_NODES = {"Model", "NodeAttribute", "AnimationCurveNode", "AnimationCurve", "Pose", "AnimationStack",
            "AnimationLayer", "Document"}
ARRAY_CODE = {"KeyTime": "l", "KeyValueFloat": "f", "KeyAttrFlags": "i", "KeyAttrDataFloat": "f",
              "KeyAttrRefCount": "i", "Matrix": "d"}


def enc_array(code, items):
    n = len(items)
    if code == "l":
        data = struct.pack("<%dq" % n, *[int(x) for x in items])
    elif code == "f":
        data = struct.pack("<%df" % n, *[float(x) for x in items])
    elif code == "i":
        data = struct.pack("<%di" % n, *[int(x) for x in items])
    else:
        data = struct.pack("<%dd" % n, *[float(x) for x in items])
    return code.encode() + struct.pack("<III", n, 0, len(data)) + data


def enc_scalar(kind, s, force_long=False, as_double=False):
    """one value: kind is 'S' (quoted) or 'W' (a bare word or number)"""
    if kind == "S":
        if "::" in s:
            cls, rest = s.split("::", 1)
            s = rest + NAME_SEP + cls
        b = s.encode("utf-8")
        return b"S" + struct.pack("<I", len(b)) + b
    if s in ("T", "Y"):
        return b"C" + bytes([1])
    if INT_RE.match(s):
        v = int(s)
        if as_double:
            return b"D" + struct.pack("<d", float(v))
        if force_long or abs(v) >= 2 ** 31:
            return b"L" + struct.pack("<q", v)
        return b"I" + struct.pack("<i", v)
    return b"D" + struct.pack("<d", float(s))


def encode_props(node):
    """the property list of one node: ids and KTime as int64, a P line's KTime values too, matrices as float64"""
    name = node["name"]
    out = []
    vals = node["values"]
    kinds = node["kinds"]
    is_ktime = name == "P" and len(vals) > 1 and vals[1] == "KTime"
    for idx, v in enumerate(vals):
        if isinstance(v, list):
            out.append(enc_array(ARRAY_CODE.get(name, "d"), v))
            continue
        force_long = (name in ID_NODES and idx == 0) or (name == "C" and idx in (1, 2)) \
            or name in ("PoseNode", "Node", "RootNode") or (is_ktime and idx >= 4)
        as_double = name == "Default"
        out.append(enc_scalar(kinds[idx], v, force_long, as_double))
    return out


def encode_record(node, start):
    name_b = node["name"].encode("utf-8")
    props_b = b"".join(encode_props(node))
    header = 4 + 4 + 4 + 1 + len(name_b)
    cur = start + header + len(props_b)
    children_b = b""
    for ch in node["children"]:
        rec = encode_record(ch, cur)
        children_b += rec
        cur += len(rec)
    if node["children"]:
        children_b += NULL_RECORD
    end = start + header + len(props_b) + len(children_b)
    return struct.pack("<III", end, len(node["values"]), len(props_b)) + bytes([len(name_b)]) + name_b + props_b + children_b


def convert(src_path, dst_path):
    text = open(src_path, encoding="utf-8").read()
    top, _ = parse_block(tokenize(text), 0)
    out = bytearray(MAGIC + struct.pack("<I", 7400))
    for node in top:
        out += encode_record(node, len(out))
    out += NULL_RECORD
    out += b"\x00" * 16   # padding, as the SDK writes before its footer
    with open(dst_path, "wb") as f:
        f.write(bytes(out))
    return len(out)


if __name__ == "__main__":
    n = convert(sys.argv[1], sys.argv[2])
    print("ok   wrote binary FBX %s (%d bytes)" % (sys.argv[2], n))
