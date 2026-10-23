"""Render the 3D background for the cover image. Does not modify the .blend.

    blender -b promo/build/idealine_promo.blend --python promo/blender/render_cover.py

Writes promo/build/cover/cover_3d.png (3840 x 2160).
"""
import os

import bpy
from mathutils import Vector

PROMO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROMO, "build", "cover")
os.makedirs(OUT, exist_ok=True)

scene = bpy.context.scene
FRAME = 640  # end of the reveal: top line settled with seven notes

cd = bpy.data.cameras.new("cam_cover")
cd.lens = 50
cd.sensor_width = 36
cd.dof.use_dof = True
cd.dof.aperture_fstop = 3.2
cd.dof.aperture_blades = 7
cam = bpy.data.objects.new("cam_cover", cd)
scene.collection.objects.link(cam)
loc = Vector((-0.62, -1.38, 0.265))
target = Vector((-0.28, 0.0, 0.205))
cam.location = loc
cam.rotation_euler = (target - loc).to_track_quat("-Z", "Y").to_euler()
focus = bpy.data.objects.new("cam_cover_focus", None)
scene.collection.objects.link(focus)
focus.location = (-0.42, -0.036, 0.36)
cd.dof.focus_object = focus

# markers bind cameras per shot; drop them so the cover camera stays active
scene.timeline_markers.clear()
scene.camera = cam
scene.frame_set(FRAME)
scene.render.resolution_x, scene.render.resolution_y = 3840, 2160
scene.render.use_motion_blur = False
scene.eevee.taa_render_samples = 96
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_depth = "8"
scene.render.filepath = os.path.join(OUT, "cover_3d.png")
bpy.ops.render.render(write_still=True)
print("Wrote", scene.render.filepath)
