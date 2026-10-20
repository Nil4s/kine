"""Kine MJCF -> USD with Isaac Lab's MJCF importer. Output: D:/kine-physics/kine_humanoid/ (the .usd, instanceable).

Run (from the worktree root):  D:/isaac-venv/Scripts/python.exe tools/physics/isaac/import_usd.py
The MJCF is Y-up (Kine); Isaac is Z-up. The importer keeps the body frames, so push_env.py spawns the robot rotated
+90 deg about X (y -> z, z -> -y) instead of editing the model. The floor, lights and cameras of the MuJoCo file are dropped.
"""
import os
import re
import sys

OUT = "D:/kine-physics"
os.environ.setdefault("OMNI_KIT_ACCEPT_EULA", "YES")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import kine_mjcf  # noqa: E402

xml, hinges, info, K = kine_mjcf.build()
xml = re.sub(r'\s*<geom name="floor"[^>]*/>', "", xml)
xml = re.sub(r"\s*<light [^>]*/>", "", xml)
xml = re.sub(r"\s*<camera [^>]*/>", "", xml)


def split_multi_hinge(xml_text):
    """The importer turns a body with 2-3 hinges into one generic D6 joint (axes lost, DOF names unknown). Make every
    joint a plain revolute: a body with hinges h1,h2,h3 becomes the chain W1(h1) > W2(h2) > body(h3), all with the
    body's frame (same kinematics as MuJoCo's joint order), the wrappers carry 5 g and 1e-6 kg m^2 (+0.2 % mass)."""
    import xml.etree.ElementTree as ET
    root = ET.fromstring(xml_text)

    def walk(parent):
        for i, b in enumerate(list(parent)):
            if b.tag != "body":
                continue
            walk(b)
            js = [j for j in b if j.tag == "joint"]
            if len(js) < 2:
                continue
            pos = b.get("pos")
            prev, top = parent, None
            chain = []
            for k, j in enumerate(js[:-1]):
                w = ET.Element("body", {"name": f"{b.get('name')}_h{k}", "pos": pos if k == 0 else "0 0 0"})
                ET.SubElement(w, "inertial", {"pos": "0 0 0", "mass": "0.005", "diagonal": "1e-6 1e-6 1e-6"})
                b.remove(j)
                w.append(j)
                chain.append(w)
            b.set("pos", "0 0 0")
            for a, c in zip(chain, chain[1:] + [b]):
                a.append(c)
            parent.remove(b)
            parent.insert(i, chain[0])

    walk(root.find("worldbody"))
    return ET.tostring(root, encoding="unicode")


xml = split_multi_hinge(xml)
os.makedirs(OUT, exist_ok=True)
mjcf_path = os.path.join(OUT, "kine_humanoid.xml")
open(mjcf_path, "w").write(xml)
with open(os.path.join(OUT, "hinge_names.txt"), "w") as f:
    f.write("\n".join(h[0] for h in hinges))

from isaaclab.app import AppLauncher  # noqa: E402
import argparse  # noqa: E402
p = argparse.ArgumentParser()
AppLauncher.add_app_launcher_args(p)
args = p.parse_args(["--headless", "--kit_args=--/app/vulkan=false"])
app = AppLauncher(args).app

import omni.kit.app  # noqa: E402
omni.kit.app.get_app().get_extension_manager().set_extension_enabled_immediate('isaacsim.asset.importer.mjcf', True)
from isaaclab.sim.converters import MjcfConverter, MjcfConverterCfg  # noqa: E402

cfg = MjcfConverterCfg(asset_path=mjcf_path, usd_dir=os.path.join(OUT, "kine_humanoid"), usd_file_name="kine_humanoid.usd",
                       fix_base=False, import_inertia_tensor=True, self_collision=False, make_instanceable=False,
                       force_usd_conversion=True)
conv = MjcfConverter(cfg)
print("USD:", conv.usd_path)
from pxr import Usd, UsdPhysics  # noqa: E402
st = Usd.Stage.Open(conv.usd_path)
for pr in st.Traverse():     # the importer also tags the world body as an articulation root: keep only the pelvis one
    if pr.HasAPI(UsdPhysics.ArticulationRootAPI) and pr.GetName() == "worldBody":
        pr.RemoveAPI(UsdPhysics.ArticulationRootAPI)
st.GetRootLayer().Save()

st = Usd.Stage.Open(conv.usd_path)
mass, njoint, root = 0.0, 0, None
for pr in st.Traverse():
    if pr.HasAPI(UsdPhysics.MassAPI):
        m = UsdPhysics.MassAPI(pr).GetMassAttr().Get()
        if m:
            mass += m
    if pr.IsA(UsdPhysics.RevoluteJoint):
        njoint += 1
    if pr.HasAPI(UsdPhysics.ArticulationRootAPI):
        root = str(pr.GetPath())
print(f"IMPORT total mass {mass:.3f} kg, revolute joints {njoint}, articulation root {root}")
app.close()
