"""Render every specially separated brand from the saved Blender source.

Blender --background --factory-startup --python this-file
Runtime meshes and original PNGs are never changed by this preview helper.
"""
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve()
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE.parent))
import build_keychain_art as art

source = art.OUT / "source" / "brand-charms-v1.blend"
bpy.ops.wm.open_mainfile(filepath=str(source))
scene = bpy.context.scene
# Keep the source camera's saved aspect equal to the published four-brand view.
scene.render.resolution_x, scene.render.resolution_y = 2000, 850
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
for obj in scene.objects:
    if obj.type in {"MESH", "CURVE", "FONT"} and obj.name != "preview-only-backdrop":
        obj.hide_render = True

manifest = json.loads((art.OUT / "manifest.json").read_text())
providers = [p for p in sorted(manifest["providers"]) if manifest["providers"][p]["extraction"]["method"] != "alpha"]
label_mat = art.material("Audit labels", "263647", roughness=.8)
for i, provider in enumerate(providers):
    x, y = (i % 5 - 2) * 2.2, (1 - i // 5) * 2.1
    parts = [bpy.data.objects[f"charm-{provider}-{suffix}"]
             for suffix in ("glass-relief", "attachment", "suspension-ring")]
    art.duplicate_charm(parts, f"Audit {provider}", (x, y, 0))
    label = bpy.data.curves.new(f"Audit label {provider}", "FONT")
    label.body, label.align_x, label.size = provider, "CENTER", .13
    label.materials.append(label_mat)
    label_object = bpy.data.objects.new(f"Audit label {provider}", label)
    bpy.context.collection.objects.link(label_object)
    label_object.location = (x, y - .86, .01)

camera = scene.camera
camera.rotation_euler = (.11, -.10, 0)
camera.location = Vector((0, .16, 0)) + camera.rotation_euler.to_matrix() @ Vector((0, 0, 12))
scene.cycles.samples = 24
art.render(art.OUT / "previews" / "separated-brand-charms.png", camera, 2200, 1340, 11.9)
print(f"KEYNEST_SEPARATED_BRAND_AUDIT_READY {len(providers)} brands", flush=True)
