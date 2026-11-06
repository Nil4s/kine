"""TEST FIXTURE ONLY (tests/charimp_test.gd R9): Kine's own mannequin (assets/mannequin.glb, Quaternius, CC0) re-exported as a SKINNED .fbx
with Blender, so the FBX reader (ufbx) is tested on mesh + skin weights, not only on animation.
    blender -b --factory-startup --python tests/fixtures/make_skinned_fbx.py -- assets/mannequin.glb out.fbx
"""
import sys
import bpy
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
bpy.ops.export_scene.fbx(filepath=argv[1], add_leaf_bones=False, bake_anim=False, object_types={'ARMATURE', 'MESH'}, path_mode='COPY', embed_textures=False)
