"""INDEPENDENT READER for the stretch keys of the USD export (L33). Run inside headless Blender (it ships Pixar's pxr):

    blender -b --factory-startup --python tools/usdstretch_check.py -- <dir>

<dir>/cases.json = [{"name", "usda", "frames": [..], "fps"}]. <dir>/report.json = {name: {"joints", "parents", "frames": {f: {"pos": joint
positions in skeleton space, "scale": the SkelAnimation's local scales}}}}. Nothing here imports Kine code: pxr's UsdSkel composes the joints.
"""
import json
import os
import sys

from pxr import Usd, UsdSkel


def main():
    a = sys.argv
    d = a[a.index("--") + 1]
    cases = json.load(open(os.path.join(d, "cases.json")))
    rep = {}
    for c in cases:
        st = Usd.Stage.Open(c["usda"])
        skel = [p for p in st.Traverse() if p.IsA(UsdSkel.Skeleton)][0]
        cache = UsdSkel.Cache()
        q = cache.GetSkelQuery(UsdSkel.Skeleton(skel))
        topo = q.GetTopology()
        joints = [str(j).split("/")[-1] for j in q.GetJointOrder()]
        parents = [topo.GetParent(i) for i in range(len(joints))]
        out = {"joints": joints, "parents": parents, "frames": {}}
        aq = q.GetAnimQuery()
        for f in c["frames"]:
            t = Usd.TimeCode(f)
            xf = q.ComputeJointSkelTransforms(t)
            tr, ro, sc = aq.ComputeJointLocalTransformComponents(t)
            out["frames"][str(f)] = {"pos": [list(x.ExtractTranslation()) for x in xf], "scale": [list(s) for s in sc]}
        rep[c["name"]] = out
    json.dump(rep, open(os.path.join(d, "report.json"), "w"))


main()
