"""Build the IdeaLine promo scene in Blender.

    blender -b --python promo/blender/build_scene.py

Writes promo/build/idealine_promo.blend and promo/build/events.json (sound cue frames).
Units: metres; UI sizes follow the app with 1 pt = 1 mm. The display faces -Y.
All motion is computed in Python and baked per frame.
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys

import numpy as np
from bpy_extras import anim_utils
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROMO = os.path.dirname(HERE)
sys.path.insert(0, PROMO)
import timeline as T  # noqa: E402

BUILD = os.path.join(PROMO, "build")
TEX = os.path.join(BUILD, "textures")
CONTENT = json.load(open(os.path.join(PROMO, "content.json"), encoding="utf-8"))
QUALITY = os.environ.get("PROMO_QUALITY", "final")  # "preview" lowers samples

F0, F1 = T.FRAME_START, T.FRAME_END
NF = F1 - F0 + 1
FPS = T.FPS
EVENTS = []


def mm(v):
    return v / 1000.0


def srgb(c):
    """sRGB 0-1 tuple -> linear RGBA."""
    lin = [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c[:3]]
    return (*lin, 1.0)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def lerp(a, b, t):
    return a + (b - a) * t


def vlerp(a, b, t):
    return Vector(a).lerp(Vector(b), t)


def smooth(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def ease_io(t):
    t = clamp(t)
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def ease_io_quint(t):
    t = clamp(t)
    return 16 * t ** 5 if t < 0.5 else 1 - (-2 * t + 2) ** 5 / 2


def ease_out(t):
    t = clamp(t)
    return 1 - (1 - t) ** 3


def ease_in(t):
    t = clamp(t)
    return t ** 3


def spring(t, response=0.55, damping=0.825):
    """SwiftUI-style spring step response (0 -> 1); t in seconds."""
    if t <= 0:
        return 0.0
    w0 = 2 * math.pi / response
    z = damping
    if z < 1:
        wd = w0 * math.sqrt(1 - z * z)
        return 1 - math.exp(-z * w0 * t) * (math.cos(wd * t) + (z * w0 / wd) * math.sin(wd * t))
    return 1 - math.exp(-w0 * t) * (1 + w0 * t)


def secs(frames):
    return frames / FPS


def event(frame, kind, **extra):
    EVENTS.append({"frame": round(float(frame), 3), "type": kind, **extra})


# ---------------------------------------------------------------------------
# Baked animation: every animated property is a numpy array over all frames.

CHANNELS = {}


def chan(id_data, path, size):
    key = (id_data.name, type(id_data).__name__, path)
    if key not in CHANNELS:
        if path.startswith('["'):
            val = id_data[path[2:-2]]
            base = np.full((NF, 1), float(val))
        else:
            val = id_data.path_resolve(path)
            if size == 1:
                base = np.full((NF, 1), float(val))
            else:
                base = np.tile(np.array(list(val)[:size], float), (NF, 1))
        CHANNELS[key] = (id_data, path, size, base)
    return CHANNELS[key][3]


def fi(frame):
    return int(frame) - F0


def frames(a, b):
    """Frames a..b-1 clipped to the timeline."""
    return range(max(F0, int(a)), min(F1 + 1, int(b)))


def set_vis(obj, visible_ranges):
    """Render visibility per frame: list of (start, end) frame ranges where obj is visible."""
    arr = chan(obj, "hide_render", 1)
    arr[:, 0] = 1
    for a, b in visible_ranges:
        for f in frames(a, b):
            arr[fi(f), 0] = 0


def bake_all():
    for id_data, path, size, arr in CHANNELS.values():
        constant = np.all(np.abs(arr - arr[0]) < 1e-9, axis=0)
        if path == "hide_render":
            interp = "CONSTANT"
        else:
            interp = "LINEAR"
        for i in range(size):
            col = arr[:, i]
            if constant[i]:
                value = float(col[0])
                if path == "hide_render":
                    id_data.hide_render = bool(value > 0.5)
                elif path.startswith('["'):
                    id_data[path[2:-2]] = value
                elif size == 1:
                    setattr_path(id_data, path, value)
                else:
                    prop = id_data.path_resolve(path)
                    prop[i] = value
                continue
            keep = [0]
            for k in range(1, NF - 1):
                if abs(col[k] - col[k - 1]) > 1e-9 or abs(col[k + 1] - col[k]) > 1e-9:
                    keep.append(k)
            keep.append(NF - 1)
            fc = fcurve(id_data, path, i if size > 1 else 0)
            fc.keyframe_points.clear()
            fc.keyframe_points.add(len(keep))
            co = np.empty(len(keep) * 2)
            co[0::2] = np.array(keep) + F0
            co[1::2] = col[keep]
            fc.keyframe_points.foreach_set("co", co.tolist())
            mode = {"CONSTANT": 0, "LINEAR": 1}[interp]
            fc.keyframe_points.foreach_set("interpolation", [mode] * len(keep))
            fc.update()


def setattr_path(id_data, path, value):
    if "." in path:
        owner_path, attr = path.rsplit(".", 1)
        setattr(id_data.path_resolve(owner_path), attr, value)
    else:
        if path == "hide_render":
            value = bool(value > 0.5)
        setattr(id_data, path, value)


def fcurve(id_data, path, index):
    ad = id_data.animation_data or id_data.animation_data_create()
    if ad.action is None:
        ad.action = bpy.data.actions.new(f"{id_data.name}_motion")
    if ad.action_slot is None:
        ad.action_slot = ad.action.slots.new(id_type=id_data.id_type, name=id_data.name)
    bag = anim_utils.action_ensure_channelbag_for_slot(ad.action, ad.action_slot)
    fc = bag.fcurves.find(path, index=index)
    if fc is None:
        fc = bag.fcurves.new(path, index=index)
    return fc


# ---------------------------------------------------------------------------
# Scene setup

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "IdeaLine"
scene.frame_start, scene.frame_end = F0, F1
scene.render.fps = FPS
scene.render.resolution_x, scene.render.resolution_y = T.WIDTH, T.HEIGHT
scene.render.resolution_percentage = 100
scene.render.engine = "BLENDER_EEVEE"
ee = scene.eevee
ee.taa_render_samples = 24 if QUALITY == "preview" else 48
ee.use_raytracing = True
ee.ray_tracing_options.resolution_scale = "2" if QUALITY == "preview" else "1"
ee.use_fast_gi = True
ee.fast_gi_method = "GLOBAL_ILLUMINATION"
ee.shadow_ray_count = 2
ee.shadow_step_count = 8
ee.use_bokeh_jittered = True
ee.bokeh_max_size = 64
scene.render.use_motion_blur = True
scene.render.motion_blur_shutter = 0.35
scene.render.film_transparent = False
scene.render.filter_size = 1.2
scene.view_settings.view_transform = "Khronos PBR Neutral"
scene.view_settings.exposure = -2.2
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGB"
scene.render.image_settings.color_depth = "8"
scene.render.image_settings.compression = 15
scene.render.filepath = os.path.join(PROMO, "render", "frame_")
scene.render.use_persistent_data = True

world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = srgb((0.95, 0.93, 0.89))
bg.inputs["Strength"].default_value = 0.18


def collection(name):
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    return col


def link(obj, col):
    col.objects.link(obj)
    return obj


def empty(name, col, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.02
    e.location = loc
    link(e, col)
    if parent:
        e.parent = parent
    return e


# ---------------------------------------------------------------------------
# Materials

def load_image(rel, colorspace="sRGB"):
    path = os.path.join(TEX, rel)
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    return img


def new_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.surface_render_method = "DITHERED"
    m.use_transparent_shadow = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)
    return m, nt, out


def alpha_chain(nt, shader_socket, out, corner=None, mask_display=None):
    """alpha = (1 - object["fade"]) * screen mask * corner mask; mixes the shader with transparency."""
    fade = nt.nodes.new("ShaderNodeAttribute")
    fade.attribute_type = "OBJECT"
    fade.attribute_name = "fade"
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(fade.outputs["Fac"], inv.inputs[1])
    alpha = inv.outputs[0]
    if mask_display is not None:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        tc.object = mask_display
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        inside = None
        for axis, limit in (("X", 0.8), ("Z", 0.5)):
            ab = nt.nodes.new("ShaderNodeMath")
            ab.operation = "ABSOLUTE"
            nt.links.new(sep.outputs[axis], ab.inputs[0])
            lt = nt.nodes.new("ShaderNodeMath")
            lt.operation = "LESS_THAN"
            lt.inputs[1].default_value = limit
            nt.links.new(ab.outputs[0], lt.inputs[0])
            if inside is None:
                inside = lt.outputs[0]
            else:
                mul = nt.nodes.new("ShaderNodeMath")
                mul.operation = "MULTIPLY"
                nt.links.new(inside, mul.inputs[0])
                nt.links.new(lt.outputs[0], mul.inputs[1])
                inside = mul.outputs[0]
        use = nt.nodes.new("ShaderNodeAttribute")
        use.attribute_type = "OBJECT"
        use.attribute_name = "screen_mask"
        # mask = 1 - use * (1 - inside)
        one_minus = nt.nodes.new("ShaderNodeMath")
        one_minus.operation = "SUBTRACT"
        one_minus.inputs[0].default_value = 1.0
        nt.links.new(inside, one_minus.inputs[1])
        m1 = nt.nodes.new("ShaderNodeMath")
        m1.operation = "MULTIPLY"
        nt.links.new(use.outputs["Fac"], m1.inputs[0])
        nt.links.new(one_minus.outputs[0], m1.inputs[1])
        mask = nt.nodes.new("ShaderNodeMath")
        mask.operation = "SUBTRACT"
        mask.inputs[0].default_value = 1.0
        nt.links.new(m1.outputs[0], mask.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(alpha, mul.inputs[0])
        nt.links.new(mask.outputs[0], mul.inputs[1])
        alpha = mul.outputs[0]
    if corner is not None:
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(alpha, mul.inputs[0])
        nt.links.new(corner, mul.inputs[1])
        alpha = mul.outputs[0]
    transparent = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha, mix.inputs["Fac"])
    nt.links.new(transparent.outputs[0], mix.inputs[1])
    nt.links.new(shader_socket, mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def rounded_corner_mask(nt, w, h, r):
    """Alpha for a rounded rectangle in UV space; w, h, r in metres."""
    uv = nt.nodes.new("ShaderNodeTexCoord")
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = (0.5, 0.5, 0.0)
    nt.links.new(uv.outputs["UV"], sub.inputs[0])
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = (w, h, 0.0)
    nt.links.new(sub.outputs[0], mul.inputs[0])
    ab = nt.nodes.new("ShaderNodeVectorMath")
    ab.operation = "ABSOLUTE"
    nt.links.new(mul.outputs[0], ab.inputs[0])
    q = nt.nodes.new("ShaderNodeVectorMath")
    q.operation = "SUBTRACT"
    q.inputs[1].default_value = (w / 2 - r, h / 2 - r, 0.0)
    nt.links.new(ab.outputs[0], q.inputs[0])
    mx = nt.nodes.new("ShaderNodeVectorMath")
    mx.operation = "MAXIMUM"
    mx.inputs[1].default_value = (0.0, 0.0, 0.0)
    nt.links.new(q.outputs[0], mx.inputs[0])
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(mx.outputs[0], ln.inputs[0])
    # alpha = clamp((r - len) / 0.0003 + 0.5)
    d = nt.nodes.new("ShaderNodeMath")
    d.operation = "SUBTRACT"
    d.inputs[0].default_value = r
    nt.links.new(ln.outputs["Value"], d.inputs[1])
    scale = nt.nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY_ADD"
    scale.inputs[1].default_value = 1 / 0.0003
    scale.inputs[2].default_value = 0.5
    scale.use_clamp = True
    nt.links.new(d.outputs[0], scale.inputs[0])
    return scale.outputs[0]


def paper_bump(nt, strength=0.08, scale=900.0):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    noise2 = nt.nodes.new("ShaderNodeTexNoise")
    noise2.inputs["Scale"].default_value = 14
    noise2.inputs["Detail"].default_value = 2
    nt.links.new(tc.outputs["Object"], noise2.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "MULTIPLY_ADD"
    add.inputs[1].default_value = 0.35
    nt.links.new(noise2.outputs["Fac"], add.inputs[0])
    nt.links.new(noise.outputs["Fac"], add.inputs[2])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = 0.0004
    nt.links.new(add.outputs[0], bump.inputs["Height"])
    return bump.outputs["Normal"]


MATS = {}


def mat_paper_face(key, rel, w, h, r, mask_display, emission=0.0, sequence=None):
    """Front face of a note or window: image texture, rounded corners, fade + screen mask."""
    m, nt, out = new_material(f"face_{key}")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.interpolation = "Cubic"
    tex.extension = "EXTEND"
    tex.image = load_image(rel)
    if sequence:
        tex.image.source = "SEQUENCE"
        tex.image_user.frame_start = sequence["start"]
        tex.image_user.frame_duration = sequence["count"]
        tex.image_user.frame_offset = 0
        tex.image_user.use_auto_refresh = True
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.62
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    bsdf.inputs["Sheen Weight"].default_value = 0.15
    if emission:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    nt.links.new(paper_bump(nt, 0.05), bsdf.inputs["Normal"])
    corner = rounded_corner_mask(nt, w, h, r) if r else None
    alpha_chain(nt, bsdf.outputs[0], out, corner, mask_display)
    MATS[f"face_{key}"] = m
    return m


def mat_plain(key, color, rough=0.65, mask_display=None, corner=None, emission=0.0, metallic=0.0, coat=0.0, bump=0.04):
    m, nt, out = new_material(key)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = 0.08
    if emission:
        bsdf.inputs["Emission Color"].default_value = srgb(color)
        bsdf.inputs["Emission Strength"].default_value = emission
    if bump:
        nt.links.new(paper_bump(nt, bump), bsdf.inputs["Normal"])
    c = rounded_corner_mask(nt, *corner) if corner else None
    alpha_chain(nt, bsdf.outputs[0], out, c, mask_display)
    MATS[key] = m
    return m


def mat_wood(key, mask_display=None):
    m, nt, out = new_material(key)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 1.0, 0.12)
    nt.links.new(tc.outputs["Object"], mapping.inputs["Vector"])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.rings_direction = "Z"
    wave.inputs["Scale"].default_value = 140
    wave.inputs["Distortion"].default_value = 7
    wave.inputs["Detail"].default_value = 3
    wave.inputs["Detail Scale"].default_value = 1.6
    nt.links.new(mapping.outputs[0], wave.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 260
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    mix.inputs["Factor"].default_value = 0.25
    nt.links.new(wave.outputs["Fac"], mix.inputs["A"])
    nt.links.new(noise.outputs["Fac"], mix.inputs["B"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.15
    ramp.color_ramp.elements[0].color = srgb((0.60, 0.37, 0.19))
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = srgb((0.86, 0.66, 0.42))
    nt.links.new(mix.outputs["Result"], ramp.inputs["Fac"])
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.48
    bsdf.inputs["Coat Weight"].default_value = 0.15
    bsdf.inputs["Coat Roughness"].default_value = 0.3
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.0002
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    alpha_chain(nt, bsdf.outputs[0], out, None, mask_display)
    MATS[key] = m
    return m


def mat_rope(key, mask_display=None):
    m, nt, out = new_material(key)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "DIAGONAL"
    wave.inputs["Scale"].default_value = 260
    wave.inputs["Distortion"].default_value = 1.5
    wave.inputs["Detail"].default_value = 1
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = srgb((0.43, 0.38, 0.29))
    ramp.color_ramp.elements[1].color = srgb((0.63, 0.57, 0.45))
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Sheen Weight"].default_value = 0.4
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    bump.inputs["Distance"].default_value = 0.0003
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    alpha_chain(nt, bsdf.outputs[0], out, None, mask_display)
    MATS[key] = m
    return m


def mat_screen(key, rel):
    m, nt, out = new_material(key)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = load_image(rel)
    tex.interpolation = "Cubic"
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    dim = nt.nodes.new("ShaderNodeMix")
    dim.data_type = "RGBA"
    dim.blend_type = "MULTIPLY"
    dim.inputs["Factor"].default_value = 1.0
    dim.inputs["B"].default_value = (0.55, 0.55, 0.55, 1)
    nt.links.new(tex.outputs["Color"], dim.inputs["A"])
    nt.links.new(dim.outputs["Result"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.62
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Coat Weight"].default_value = 0.6
    bsdf.inputs["Coat Roughness"].default_value = 0.03
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    MATS[key] = m
    return m


# ---------------------------------------------------------------------------
# Geometry

def rounded_outline(w, h, r, seg=8):
    """CCW points in the x-z plane (viewed from -Y), centred at the origin."""
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    for cx, cz, a0 in corners:
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def slab(name, col, w, h, d, r, mats, origin_top=False, seg=8, bevel=0.0):
    """Rounded box: front (-Y) gets material 0 with UVs, back material 1, sides material 2."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    pts = rounded_outline(w, h, r, seg) if r > 0 else [(w / 2, h / 2), (-w / 2, h / 2), (-w / 2, -h / 2), (w / 2, -h / 2)]
    dz = -h / 2 if origin_top else 0.0
    front = [bm.verts.new((x, -d / 2, z + dz)) for x, z in pts]
    back = [bm.verts.new((x, d / 2, z + dz)) for x, z in pts]
    ff = bm.faces.new(front)
    bf = bm.faces.new(list(reversed(back)))
    ff.material_index, bf.material_index = 0, 1
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((front[j], front[i], back[i], back[j]))
        f.material_index = 2
    bm.normal_update()
    if ff.normal.y > 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            x, _, z = loop.vert.co
            loop[uv].uv = ((x + w / 2) / w, (z - dz + h / 2) / h)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    for m in mats:
        me.materials.append(m)
    link(obj, col)
    if bevel:
        bv = obj.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(60)
        bv.harden_normals = False
    obj["fade"] = 0.0
    obj["screen_mask"] = 0.0
    return obj


def paper(name, col, w, h, mats, nx=20, nz=20, curl=0.0, seed=0):
    """Thin note: subdivided grid in x-z, origin at top centre, solidified. Shape key "flex" bends it."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rnd = random.Random(seed)
    c1 = rnd.uniform(-1, 1) * curl
    c2 = rnd.uniform(0.3, 1.0) * curl
    verts = {}
    for i in range(nx + 1):
        for j in range(nz + 1):
            x = -w / 2 + w * i / nx
            z = -h * j / nz
            u = x / (w / 2)
            v = -z / h
            y = -mm(1.2) * c1 * u * u - mm(2.2) * c2 * v ** 3
            verts[i, j] = bm.verts.new((x, y, z))
    uv = bm.loops.layers.uv.new("UVMap")
    for i in range(nx):
        for j in range(nz):
            f = bm.faces.new((verts[i, j], verts[i, j + 1], verts[i + 1, j + 1], verts[i + 1, j]))
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    if bm.faces[0].normal.y > 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    for f in bm.faces:
        for loop in f.loops:
            x, _, z = loop.vert.co
            loop[uv].uv = ((x + w / 2) / w, 1 + z / h)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    for m in mats:
        me.materials.append(m)
    link(obj, col)
    sol = obj.modifiers.new("Paper", "SOLIDIFY")
    sol.thickness = mm(0.35)
    sol.offset = -1
    sol.material_offset = 1
    sol.material_offset_rim = 2
    obj.shape_key_add(name="Basis")
    flex = obj.shape_key_add(name="flex", from_mix=False)
    for k, vtx in enumerate(me.vertices):
        x, y, z = vtx.co
        u = x / (w / 2)
        v = -z / h
        flex.data[k].co = (x, y - mm(26) * (u * u - 0.35) - mm(10) * v * v, z)
    flex.slider_min = -1.0
    flex.value = 0.0
    obj["fade"] = 0.0
    obj["screen_mask"] = 0.0
    return obj


def rope(name, col, pts, radius, mat):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for p, co in zip(sp.points, pts):
        p.co = (*co, 1.0)
    obj = bpy.data.objects.new(name, cu)
    cu.materials.append(mat)
    link(obj, col)
    obj["fade"] = 0.0
    obj["screen_mask"] = 0.0
    return obj


def wire_loop(name, col, w, d, z, radius, mat):
    """Closed rounded-rectangle wire in the x-y plane at height z (spring band around a clothespin)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    sp = cu.splines.new("POLY")
    outline = rounded_outline(w, d, min(w, d) * 0.3, 4)
    sp.points.add(len(outline) - 1)
    for p, (x, y) in zip(sp.points, outline):
        p.co = (x, y, z, 1.0)
    sp.use_cyclic_u = True
    obj = bpy.data.objects.new(name, cu)
    cu.materials.append(mat)
    link(obj, col)
    obj["fade"] = 0.0
    obj["screen_mask"] = 0.0
    return obj


def clothespin(name, col, wood, metal, scale=1.0):
    """Root empty at the spring pivot. Halves open by rotating about local X.

    Layout relative to the rope (pivot is 1 mm above it): top at +7 mm, jaw tips at -22 mm.
    """
    root = empty(name, col)
    halves = []
    W, H, D = mm(10) * scale, mm(29) * scale, mm(3.6) * scale
    gap = mm(1.5) * scale
    for side, sign in (("front", -1), ("back", 1)):
        hinge = empty(f"{name}_{side}_hinge", col, parent=root)
        half = slab(f"{name}_{side}", col, W, H, D, mm(2.2) * scale, [wood, wood, wood], bevel=mm(0.9) * scale)
        half.parent = hinge
        half.location = (0, sign * (gap + D / 2), mm(7) * scale - H / 2)
        halves.append(hinge)
    bands = []
    for k, dz in enumerate((mm(1.2), mm(-0.4))):
        b = wire_loop(f"{name}_spring{k}", col, W + mm(0.6) * scale, 2 * (gap + D) + mm(0.6) * scale, dz * scale, mm(0.42) * scale, metal)
        b.parent = root
        bands.append(b)
    return root, halves, bands


# ---------------------------------------------------------------------------
# Shared materials

C_INK = (0.20, 0.23, 0.20)
C_PAPER = (0.97, 0.96, 0.92)
C_NOTE = [(1.0, 0.95, 0.77), (0.88, 0.94, 0.86), (0.87, 0.93, 0.97), (0.98, 0.87, 0.83)]
C_CREAM = (0.84, 0.82, 0.77)

col_main = collection("MAIN")
col_keys = collection("KEYS")
col_end = collection("END")

display_frame = empty("DisplayFrame", col_main)  # screen-mask reference; never moves

NOTE_W, NOTE_H, NOTE_R = mm(184), mm(171), mm(4)
note_faces = {}
for i in range(len(CONTENT["notes"])):
    note_faces[i] = mat_paper_face(f"note{i}", f"notes/note_{i}.png", NOTE_W, NOTE_H, NOTE_R, display_frame)
note_faces["new"] = mat_paper_face("note_new", "notes/note_new.png", NOTE_W, NOTE_H, NOTE_R, display_frame)
note_backs = [mat_plain(f"paper_back{k}", c, 0.7, display_frame, (NOTE_W, NOTE_H, NOTE_R)) for k, c in enumerate(C_NOTE)]
wood = mat_wood("wood", display_frame)
metal = mat_plain("spring_metal", (0.62, 0.62, 0.64), 0.28, display_frame, metallic=1.0, bump=0)
rope_mat = mat_rope("rope", display_frame)


def note_color(key):
    return CONTENT["newNote"]["color"] if key == "new" else CONTENT["notes"][key]["color"]


def hanging_note(name, col, key, seed, scale=1.0):
    """A note with its clothespin. Returns dict; rig origin sits on the rope."""
    rig = empty(f"{name}_rig", col)
    swing = empty(f"{name}_swing", col, parent=rig)  # secondary swing of the paper
    back = note_backs[note_color(key)]
    note = paper(f"{name}_paper", col, NOTE_W * scale, NOTE_H * scale, [note_faces[key], back, back], curl=1.0, seed=seed)
    note.parent = swing
    note.location = (0, 0, -mm(10) * scale)
    pin, halves, bands = clothespin(f"{name}_pin", col, wood, metal, scale)
    pin.parent = rig
    pin.location = (0, 0, mm(1) * scale)
    return {"rig": rig, "swing": swing, "paper": note, "pin": pin, "halves": halves, "bands": bands, "key": key, "seed": seed,
            "parts": [note, *bands] + [h.children[0] for h in halves]}


def set_mask(objs, value):
    for o in objs:
        if "screen_mask" in o.keys():
            o["screen_mask"] = value


def all_parts(n):
    return n["parts"]


# ---------------------------------------------------------------------------
# MAIN set: display with clothesline rigs, composer, library window, cursor

SCREEN_W, SCREEN_H = mm(1600), mm(1000)
MENU = mm(25)
ROPE_Y = -mm(36)
SAG = mm(23)


def rope_z(x, z_end):
    half = SCREEN_W / 2 + mm(10)
    return z_end - SAG * (1 - (x / half) ** 2)


def build_display():
    alu = mat_plain("aluminum", (0.80, 0.80, 0.81), 0.42, metallic=1.0, bump=0)
    glass = mat_plain("bezel_glass", (0.02, 0.02, 0.022), 0.06, coat=1.0, bump=0)
    screen_mat = mat_screen("screen", "ui/desktop.png")
    body = slab("display_body", col_main, mm(1652), mm(1052), mm(24), mm(26), [glass, alu, alu], bevel=mm(3))
    body.location = (0, mm(12), 0)
    screen = slab("display_screen", col_main, SCREEN_W, SCREEN_H, mm(0.4), 0, [screen_mat, screen_mat, screen_mat])
    screen.location = (0, -mm(0.3), 0)
    # Stand: an angled plate from the back to a foot on the floor
    arm = slab("stand_arm", col_main, mm(250), mm(1080), mm(9), mm(8), [alu, alu, alu], bevel=mm(2))
    arm.location = (0, mm(150), -mm(470))
    arm.rotation_euler = (math.radians(-12), 0, 0)
    foot = slab("stand_foot", col_main, mm(250), mm(330), mm(9), mm(8), [alu, alu, alu], bevel=mm(2))
    foot.rotation_euler = (math.radians(90), 0, 0)
    foot.location = (0, mm(190), -mm(1000) + mm(4.5))
    for o in (body, screen, arm, foot):
        o.parent = display_frame


def cyclorama(name, col, origin, floor_z, wall_y, color, width=24.0, radius=1.6):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    prof = [(-10.0, floor_z)]
    y0 = wall_y - radius
    for k in range(17):
        a = math.radians(-90 + 90 * k / 16)
        prof.append((y0 + radius * math.cos(a), floor_z + radius + radius * math.sin(a)))
    prof.append((wall_y, floor_z + 12.0))
    left = [bm.verts.new((-width / 2, y, z)) for y, z in prof]
    right = [bm.verts.new((width / 2, y, z)) for y, z in prof]
    for k in range(len(prof) - 1):
        bm.faces.new((left[k], right[k], right[k + 1], left[k + 1]))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    obj.location = origin
    m = mat_plain(f"{name}_mat", color, 0.92, bump=0)
    me.materials.append(m)
    link(obj, col)
    # make sure normals face the camera side (+z on floor)
    if me.polygons[0].normal.z < 0:
        me.flip_normals()
    return obj


def area_light(name, col, loc, target, size, energy, color=(1, 1, 1), size_y=None, cutoff=None):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = "RECTANGLE" if size_y else "SQUARE"
    ld.size = size
    if size_y:
        ld.size_y = size_y
    ld.energy = energy
    ld.color = color
    if cutoff:
        ld.use_custom_distance = True
        ld.cutoff_distance = cutoff
    obj = bpy.data.objects.new(name, ld)
    obj.location = loc
    d = Vector(target) - Vector(loc)
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    link(obj, col)
    return obj


build_display()
cyclorama("main_cyc", col_main, (0, 0, 0), -1.0, 3.4, C_CREAM)
area_light("main_key", col_main, (-2.0, -2.4, 2.1), (0, 0, 0.1), 1.8, 950, (1.0, 0.93, 0.84), cutoff=14)
area_light("main_fill", col_main, (2.8, -2.6, 0.2), (0, 0, 0), 3.0, 380, (0.93, 0.96, 1.0), cutoff=14)
area_light("main_rim", col_main, (0.9, 1.6, 2.3), (0, 0, 0.3), 1.2, 520, (1.0, 0.97, 0.92), cutoff=14)
area_light("main_top", col_main, (0, -1.0, 2.8), (0, -0.3, 0.4), 2.0, 260, (1.0, 0.96, 0.9), cutoff=14)

ORDER_BEFORE = [0, 1, 2, 3, 4, 5]
ORDER_AFTER = ["new", 0, 1, 2, 3, 4, 5]
STRIDE = mm(208)
TOP_END = SCREEN_H / 2 - MENU - mm(12)
BOTTOM_PANEL_TOP = -SCREEN_H / 2 + mm(286)
BOTTOM_END = BOTTOM_PANEL_TOP - mm(12)


def slot_x(index, count):
    return (index - (count - 1) / 2) * STRIDE


def note_tilt(seed):
    return math.radians(((seed * 37) % 7) - 3)


def build_horizontal_rig(kind, keys):
    root = empty(f"rig_{kind}", col_main)
    z_end = TOP_END if kind == "top" else BOTTOM_END
    pts = []
    for k in range(49):
        x = -SCREEN_W / 2 - mm(10) + (SCREEN_W + mm(20)) * k / 48
        pts.append((x, ROPE_Y, rope_z(x, z_end)))
    line = rope(f"rope_{kind}", col_main, pts, mm(1.4), rope_mat)
    line.parent = root
    notes = []
    for idx, key in enumerate(keys):
        seed = 1 if key == "new" else key + 3
        n = hanging_note(f"{kind}_{key}", col_main, key, seed)
        n["rig"].parent = root
        notes.append(n)
    toolbar = None
    return {"root": root, "rope": line, "notes": notes, "z_end": z_end, "kind": kind, "toolbar": toolbar}


def build_vertical_rig(kind, keys):
    root = empty(f"rig_{kind}", col_main)
    sign = 1 if kind == "right" else -1
    x_rope = sign * (SCREEN_W / 2 - mm(28))
    x_note = sign * (SCREEN_W / 2 - mm(143))
    top = SCREEN_H / 2 - MENU
    line = rope(f"rope_{kind}", col_main, [(x_rope, ROPE_Y, top + mm(30)), (x_rope, ROPE_Y, -SCREEN_H / 2 - mm(30))], mm(1.4), rope_mat)
    line.parent = root
    notes, branches = [], []
    for i, key in enumerate(keys):
        zb = top - mm(34) - i * mm(213)
        br = rope(f"branch_{kind}_{i}", col_main, [(x_rope, ROPE_Y, zb), (x_note, ROPE_Y, zb)], mm(1.4), rope_mat)
        br.parent = root
        branches.append(br)
        n = hanging_note(f"{kind}_{key}", col_main, key, key + 11 if key != "new" else 5)
        n["rig"].parent = root
        n["rig"].location = (x_note, ROPE_Y, zb)
        notes.append(n)
    return {"root": root, "rope": line, "branches": branches, "notes": notes, "kind": kind}


rig_top = build_horizontal_rig("top", ORDER_AFTER)
rig_bottom = build_horizontal_rig("bottom", ORDER_AFTER)
rig_right = build_vertical_rig("right", ORDER_AFTER[:4])
rig_left = build_vertical_rig("left", ORDER_AFTER[:4])

for rig in (rig_top, rig_bottom, rig_right, rig_left):
    objs = [rig["rope"], *rig.get("branches", [])]
    for n in rig["notes"]:
        objs += all_parts(n)
    set_mask(objs, 1.0)
    rig["objs"] = objs


def toolbar_obj(name, rel, z):
    w = mm(296)
    h = mm(43)
    mt = mat_paper_face(name, rel, w, h, 0, display_frame, emission=0.25)
    # the texture already carries the pill shape in its alpha
    nt = mt.node_tree
    tex = [n for n in nt.nodes if n.type == "TEX_IMAGE"][0]
    mix = [n for n in nt.nodes if n.type == "MIX_SHADER"][0]
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(mix.inputs["Fac"].links[0].from_socket, mul.inputs[0])
    nt.links.new(tex.outputs["Alpha"], mul.inputs[1])
    nt.links.new(mul.outputs[0], mix.inputs["Fac"])
    o = slab(name, col_main, w, h, mm(0.2), 0, [mt, mt, mt])
    o.location = (0, -mm(14), z)
    o.parent = rig_top["root"]
    o["screen_mask"] = 1.0
    return o


toolbar_before = toolbar_obj("toolbar_before", "ui/toolbar_before.png", SCREEN_H / 2 - MENU - mm(228) - mm(21.5))
toolbar_after = toolbar_obj("toolbar_after", "ui/toolbar_after.png", SCREEN_H / 2 - MENU - mm(228) - mm(21.5))

# Composer window: image sequence built from typing states
COMPOSER_POS = Vector((0, -mm(210), mm(30)))
paper_mat = mat_plain("window_paper", C_PAPER, 0.5, bump=0.02)
composer_seq_dir = os.path.join(BUILD, "composer_seq")


def typing_schedule():
    """Per-frame (chunks_typed, caret_on) for the compose shot through the hang shot."""
    rnd = random.Random(7)
    chunks = CONTENT["typingChunks"]
    t = 0.75
    commits = []
    for c in chunks:
        if c == "\n":
            t += 0.30
        elif c in "，。：、":
            t += 0.16
        else:
            t += 0.15 + 0.07 * len(c) + rnd.uniform(-0.03, 0.06)
        commits.append(t)
    # fit the typing between 0.55 s and 3.75 s into the shot
    a, b = 0.55, 3.75
    first, last = commits[0], commits[-1]
    return [a + 0.15 + (c - first) / (last - first) * (b - a - 0.15) for c in commits]


COMMITS = typing_schedule()
SEQ_START = T.start("compose")
SEQ_END = T.start("hang") + 24


def composer_state(frame):
    t = secs(frame - SEQ_START)
    typed = sum(1 for c in COMMITS if c <= t)
    typing = COMMITS[0] - 0.1 < t < COMMITS[-1] + 0.35
    caret = 1 if typing else (1 if (t % 1.06) < 0.53 else 0)
    return typed, caret


def build_composer_sequence():
    import shutil
    if os.path.isdir(composer_seq_dir):
        shutil.rmtree(composer_seq_dir)
    os.makedirs(composer_seq_dir)
    for k, f in enumerate(range(SEQ_START, SEQ_END + 1)):
        typed, caret = composer_state(f)
        src = os.path.join(TEX, "composer", f"state_{typed:02d}_{caret}.png")
        os.link(src, os.path.join(composer_seq_dir, f"{k + 1:04d}.png"))
    return SEQ_END - SEQ_START + 1


seq_count = build_composer_sequence()
composer_face = mat_paper_face("composer", os.path.relpath(os.path.join(composer_seq_dir, "0001.png"), TEX), mm(600), mm(450), 0, None, emission=0.18,
                               sequence={"start": SEQ_START, "count": seq_count})
composer = slab("composer", col_main, mm(600), mm(450), mm(7), mm(14), [composer_face, paper_mat, paper_mat], bevel=mm(1.2))
composer.location = COMPOSER_POS

library_face = mat_paper_face("library", "ui/library.png", mm(900), mm(690), 0, None, emission=0.18)
library = slab("library", col_main, mm(900), mm(690), mm(8), mm(14), [library_face, paper_mat, paper_mat], bevel=mm(1.2))
LIBRARY_POS = Vector((0, -mm(300), mm(60)))
library.location = LIBRARY_POS

cursor_face = mat_paper_face("cursor", "ui/cursor.png", mm(32), mm(32), 0, None, emission=0.6)
_n = cursor_face.node_tree
_tex = [n for n in _n.nodes if n.type == "TEX_IMAGE"][0]
_mix = [n for n in _n.nodes if n.type == "MIX_SHADER"][0]
_mul = _n.nodes.new("ShaderNodeMath")
_mul.operation = "MULTIPLY"
_n.links.new(_mix.inputs["Fac"].links[0].from_socket, _mul.inputs[0])
_n.links.new(_tex.outputs["Alpha"], _mul.inputs[1])
_n.links.new(_mul.outputs[0], _mix.inputs["Fac"])
cursor = slab("cursor", col_main, mm(64), mm(64), mm(0.3), 0, [cursor_face, cursor_face, cursor_face])
cursor_root = empty("cursor_root", col_main)
cursor.parent = cursor_root
cursor.location = (mm(20), 0, -mm(24))  # tip at the root (tip is at 6,4 pt on the 32 pt canvas, drawn 2x)

# ---------------------------------------------------------------------------
# KEYS set (x = +60 m)

KEYS_O = Vector((60.0, 0, 0))
plastic_cache = {}


def keycap(name, legend_rel, w, d=mm(16.5)):
    m, nt, out = new_material(f"keycap_{name}")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = load_image(legend_rel)
    tex.extension = "CLIP"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = srgb((0.965, 0.963, 0.955))
    mix.inputs["B"].default_value = srgb((0.30, 0.32, 0.30))
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 0.92
    nt.links.new(tex.outputs["Alpha"], mul.inputs[0])
    nt.links.new(mul.outputs[0], mix.inputs["Factor"])
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.42
    bsdf.inputs["Specular IOR Level"].default_value = 0.45
    alpha_chain(nt, bsdf.outputs[0], out)
    side = plastic_cache.get("side") or mat_plain("keycap_side", (0.95, 0.948, 0.94), 0.45, bump=0)
    plastic_cache["side"] = side
    k = slab(f"key_{name}", col_keys, w, d, mm(3.2), mm(2.6), [m, side, side], bevel=mm(0.9))
    # lay it flat: front face (UV) up
    k.rotation_euler = (math.radians(-90), 0, 0)
    return k


def build_keys():
    alu = MATS["aluminum"]
    well = mat_plain("key_well", (0.12, 0.12, 0.13), 0.6, bump=0)
    groups = {}
    for gname, gx, specs in (
        ("hotkey", 0.0, [("ctrl", "keys/ctrl.png", mm(16.5)), ("opt", "keys/opt.png", mm(16.5)), ("n", "keys/n.png", mm(16.5))]),
        ("submit", 0.2, [("cmd", "keys/cmd.png", mm(21)), ("ret", "keys/ret.png", mm(33))]),
    ):
        total = sum(s[2] for s in specs) + mm(3.5) * (len(specs) - 1)
        deck = slab(f"deck_{gname}", col_keys, total + mm(30), mm(46), mm(4), mm(7), [alu, alu, alu], bevel=mm(1.2))
        deck.rotation_euler = (math.radians(-90), 0, 0)
        deck.location = KEYS_O + Vector((gx, 0, -mm(2)))
        keys = {}
        x = -total / 2
        for kname, rel, w in specs:
            cx = x + w / 2
            wl = slab(f"well_{kname}", col_keys, w + mm(1.6), mm(16.5) + mm(1.6), mm(0.4), mm(3), [well, well, well])
            wl.rotation_euler = (math.radians(-90), 0, 0)
            wl.location = KEYS_O + Vector((gx + cx, 0, mm(0.05)))
            k = keycap(kname, rel, w)
            k.location = KEYS_O + Vector((gx + cx, 0, mm(1.6) + mm(1.0)))
            keys[kname] = k
            x += w + mm(3.5)
        groups[gname] = keys
    return groups


KEYS = build_keys()
cyclorama("keys_cyc", col_keys, KEYS_O + Vector((0, 0, 0)), -mm(4), 0.9, C_CREAM, width=4.0, radius=0.3)
area_light("keys_key", col_keys, KEYS_O + Vector((-0.28, -0.22, 0.38)), KEYS_O + Vector((0.05, 0, 0)), 0.35, 26, (1.0, 0.93, 0.84), cutoff=3)
area_light("keys_fill", col_keys, KEYS_O + Vector((0.4, -0.3, 0.15)), KEYS_O, 0.6, 9, (0.93, 0.96, 1.0), cutoff=3)
area_light("keys_rim", col_keys, KEYS_O + Vector((0.15, 0.35, 0.25)), KEYS_O, 0.3, 14, (1.0, 0.97, 0.92), cutoff=3)

# ---------------------------------------------------------------------------
# END set (x = +40 m): a clothesline in a cream room, and the 3D app icon

END_O = Vector((40.0, 0, 0))
end_notes = []
end_keys = ["new", 0, 1, 2, 3, 4, 5, 0]
END_HALF = 1.0
end_rope_pts = []
for k in range(61):
    x = -END_HALF + 2 * END_HALF * k / 60
    end_rope_pts.append(tuple(END_O + Vector((x, 0, -mm(40) * (1 - (x / END_HALF) ** 2)))))
end_rope = rope("end_rope", col_end, end_rope_pts, mm(1.5), rope_mat)


def end_rope_z(x):
    return -mm(40) * (1 - (x / END_HALF) ** 2)


for i, key in enumerate(end_keys):
    n = hanging_note(f"end_{i}", col_end, key, 40 + i)
    x = (i - (len(end_keys) - 1) / 2) * STRIDE
    n["rig"].location = END_O + Vector((x, 0, end_rope_z(x)))
    n["x"] = x
    end_notes.append(n)
cyclorama("end_cyc", col_end, END_O, -1.6, 0.75, (0.76, 0.735, 0.69), width=8.0, radius=0.8)
area_light("end_key", col_end, END_O + Vector((-1.3, -1.6, 0.9)), END_O + Vector((0, 0, -0.2)), 1.2, 260, (1.0, 0.92, 0.82), cutoff=5)
area_light("end_fill", col_end, END_O + Vector((1.6, -1.8, -0.4)), END_O + Vector((0, 0, -0.2)), 2.0, 110, (0.92, 0.95, 1.0), cutoff=5)
area_light("end_rim", col_end, END_O + Vector((0.6, 0.5, 0.9)), END_O + Vector((0, -0.4, -0.2)), 0.8, 120, (1.0, 0.96, 0.9), cutoff=5)

area_light("end_window", col_end, END_O + Vector((-1.4, -3.6, 2.6)), END_O + Vector((0.4, 0.75, -0.3)), 0.6, 500, (1.0, 0.9, 0.76), cutoff=8)


def build_icon():
    """3D version of scripts/make-icon.swift. Icon pixel units: 1024 px = ICON_SIZE."""
    root = empty("icon_root", col_end)
    s = mm(0.3)  # metres per icon pixel (icon is 0.307 m wide)
    tile_mat = mat_plain("icon_tile", (0.975, 0.968, 0.94), 0.3, coat=0.6, bump=0.01)
    tile = slab("icon_tile", col_end, 984 * s, 984 * s, 70 * s, 220 * s, [tile_mat, tile_mat, tile_mat], seg=12, bevel=18 * s)
    tile.parent = root

    def p(x, y, dy=0.0):  # AppKit icon coords (y up) -> local
        return Vector(((x - 512) * s, -35 * s - dy, (y - 512) * s))

    rope_pts = []
    for k in range(41):
        t = k / 40
        a, b, c, d = Vector((60, 770)), Vector((300, 655)), Vector((720, 655)), Vector((964, 770))
        q = (1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t * t * c + t ** 3 * d
        rope_pts.append(tuple(p(q.x, q.y, 11 * s)))
    icon_rope_mat = mat_plain("icon_rope", (0.44, 0.42, 0.32), 0.8, bump=0)
    r = rope("icon_rope", col_end, rope_pts, 3.5 * s, icon_rope_mat)
    r.parent = root
    hinge = empty("icon_note_hinge", col_end, parent=root)
    hinge.location = p(512, 694 + 30, 23 * s)
    note_mat = mat_paper_face("icon_note", "ui/icon_note.png", 518 * s, 482 * s, 16 * s, None)
    back = mat_plain("icon_note_back", (1, 0.89, 0.59), 0.7, corner=(518 * s, 482 * s, 16 * s))
    note = paper("icon_note", col_end, 518 * s, 482 * s, [note_mat, back, back], nx=12, nz=12, curl=0.0)
    note.modifiers["Paper"].thickness = 4 * s
    note.parent = hinge
    note.location = (0, 0, -30 * s)
    pin_mat = mat_wood("icon_pin_wood")
    pin_scale = 117 * s / mm(29)
    pin, halves, bands = clothespin("icon_pin", col_end, pin_mat, MATS["spring_metal"], scale=pin_scale)
    pin.parent = hinge
    pin.location = (0, 0, (756 - 724) * s - mm(7) * pin_scale)
    return root, hinge


icon_root, icon_hinge = build_icon()

# ---------------------------------------------------------------------------
# Cameras

def camera(name, col, lens=50, fstop=4.0):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.sensor_width = 36
    cd.clip_start = 0.01
    cd.clip_end = 60
    cd.dof.use_dof = True
    cd.dof.aperture_fstop = fstop
    cd.dof.aperture_blades = 7
    cd.dof.aperture_rotation = math.radians(10)
    cam = bpy.data.objects.new(name, cd)
    link(cam, col)
    focus = empty(f"{name}_focus", col)
    cd.dof.focus_object = focus
    return cam, focus


def bake_camera(cam, focus, f_range, pose_fn):
    """pose_fn(frame) -> (location, target, focus_point, lens)."""
    loc = chan(cam, "location", 3)
    rot = chan(cam, "rotation_euler", 3)
    lens = chan(cam.data, "lens", 1)
    floc = chan(focus, "location", 3)
    prev = None
    for f in f_range:
        p, t, fp, ln = pose_fn(f)
        p, t = Vector(p), Vector(t)
        q = (t - p).to_track_quat("-Z", "Y")
        e = q.to_euler("XYZ", prev) if prev else q.to_euler("XYZ")
        prev = e
        i = fi(f)
        loc[i] = p
        rot[i] = e
        lens[i, 0] = ln
        floc[i] = fp
    # hold first/last pose outside the range
    a, b = fi(f_range[0]), fi(f_range[-1])
    for arr in (loc, rot, lens, floc):
        arr[:a] = arr[a]
        arr[b + 1:] = arr[b]


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def path(u, keys):
    """Catmull-Rom through keys [(u_k, Vector)], u in 0..1."""
    u = clamp(u)
    k = 0
    while k < len(keys) - 2 and u > keys[k + 1][0]:
        k += 1
    t = (u - keys[k][0]) / max(1e-6, keys[k + 1][0] - keys[k][0])
    p0 = keys[max(k - 1, 0)][1]
    p3 = keys[min(k + 2, len(keys) - 1)][1]
    return catmull(Vector(p0), Vector(keys[k][1]), Vector(keys[k + 1][1]), Vector(p3), clamp(t))


def keyposes(f, poses, ease=ease_io):
    """poses: list of (frame, value tuple). Piecewise eased interpolation."""
    if f <= poses[0][0]:
        return poses[0][1]
    for (fa, va), (fb, vb) in zip(poses, poses[1:]):
        if fa <= f <= fb:
            t = ease((f - fa) / max(1, fb - fa))
            return tuple(lerp(x, y, t) for x, y in zip(va, vb))
    return poses[-1][1]


# ---------------------------------------------------------------------------
# Animation helpers for notes

def breeze(t, seed, amp=1.0):
    """Small idle sway (radians) for in-plane tilt and toward-camera swing."""
    r = random.Random(seed)
    p1, p2, p3 = r.uniform(0, 6.28), r.uniform(0, 6.28), r.uniform(0, 6.28)
    tilt = amp * math.radians(0.55) * math.sin(2 * math.pi * t / 2.9 + p1) + amp * math.radians(0.25) * math.sin(2 * math.pi * t / 1.7 + p2)
    swing = -amp * math.radians(1.6) * (0.55 + 0.45 * math.sin(2 * math.pi * t / 3.4 + p3))
    return tilt, swing


def pin_open(n, f, angle):
    for side, h in zip((-1, 1), n["halves"]):
        chan(h, "rotation_euler", 3)[fi(f), 0] = side * angle


def note_swing(n, f, tilt, swing, flex=0.0):
    i = fi(f)
    rr = chan(n["rig"], "rotation_euler", 3)
    rr[i, 1] = tilt
    sw = chan(n["swing"], "rotation_euler", 3)
    sw[i, 0] = swing
    chan(n["paper"].data.shape_keys, 'key_blocks["flex"].value', 1)[i, 0] = flex


def set_fade(objs, f, value):
    for o in objs:
        if "fade" in o.keys():
            chan(o, '["fade"]', 1)[fi(f), 0] = value


def rope_bounce_fn(impulses, x_half):
    """impulses: list of (frame, x, amplitude metres). Returns d(x, frame) vertical offset."""
    def d(x, f):
        total = 0.0
        for f0, x0, amp in impulses:
            total += bounce_amp(f, f0, amp) * bounce_shape(x, x0, x_half)
        return total
    return d


def bounce_shape(x, x0, x_half):
    u = (x + x_half) / (2 * x_half)
    return math.sin(math.pi * clamp(u)) * (0.35 + 0.65 * math.exp(-((x - x0) / 0.32) ** 2))


def bounce_amp(f, f0, amp):
    t = secs(f - f0)
    if t < 0:
        return 0.0
    return -amp * math.exp(-t / 0.33) * math.cos(2 * math.pi * t / 0.42)


def bake_rope_bounce(rope_obj, impulses, x_half):
    """One shape key per impulse (unit dip of 10 mm), values baked per frame."""
    rope_obj.shape_key_add(name="Basis")
    for k, (f0, x0, amp) in enumerate(impulses):
        sk = rope_obj.shape_key_add(name=f"bounce{k}", from_mix=False)
        sk.slider_min, sk.slider_max = -2.0, 2.0
        for j, p in enumerate(rope_obj.data.splines[0].points):
            x, y, z = p.co[0], p.co[1], p.co[2]
            sk.data[j].co = (x, y, z + mm(10) * bounce_shape(x, x0, x_half))
        arr = chan(rope_obj.data.shape_keys, f'key_blocks["bounce{k}"].value', 1)
        for f in frames(F0, F1 + 1):
            arr[fi(f), 0] = bounce_amp(f, f0, amp) / mm(10)


# ---------------------------------------------------------------------------
# Shot timing

S = T.SHOTS
macro0, macro1 = S["macro"]
hot0, hot1 = S["hotkey"]
comp0, comp1 = S["compose"]
sub0, sub1 = S["submit"]
hang0, hang1 = S["hang"]
rev0, rev1 = S["reveal"]
edg0, edg1 = S["edges"]
drag0, drag1 = S["drag"]
lib0, lib1 = S["library"]
end0, end1 = S["end"]
ALL = (F0, F1 + 1)

# Visibility of the MAIN extras
set_vis(composer, [(comp0, comp1), (hang0, hang0 + 14)])
set_vis(library, [(lib0, lib1)])
set_vis(cursor, [(drag0, drag1)])
set_vis(toolbar_before, [(comp0, hang0 + 30)])
set_vis(toolbar_after, [(hang0 + 30, lib1)])
for rig in (rig_right, rig_bottom, rig_left):
    for o in rig["objs"]:
        set_vis(o, [(edg0, edg1)])

# ---------------------------------------------------------------------------
# MAIN top rig: positions over time

top_notes = {n["key"]: n for n in rig_top["notes"]}
X_HALF = SCREEN_W / 2 + mm(10)
impulses = []

# Hang: arrival frame of the new note
ARRIVE = hang0 + 30
SHIFT = hang0 + 12
# Drag: note 3 moves from slot 4 to slot 2
DRAG_KEY = 3
PRESS = drag0 + 26
DRAG_A, DRAG_B = drag0 + 30, drag0 + 72
RELEASE = drag0 + 76


def top_slot_x(key, f):
    """x position of a note on the top rope at frame f (ignores the flying phase)."""
    if key == "new":
        return slot_x(0, 7)
    old = ORDER_BEFORE.index(key)
    x_before = slot_x(old, 6)
    x_after = slot_x(old + 1, 7)
    if f < SHIFT:
        x = x_before
    else:
        x = lerp(x_before, x_after, spring(secs(f - SHIFT), 0.4, 0.75))
    if f >= drag0:
        order = list(ORDER_AFTER)
        pos = order.index(key)
        if key == DRAG_KEY:
            return x  # handled separately
        # neighbours 1 and 2 shift right when the dragged note passes them
        if pos in (2, 3):  # keys 1 and 2
            thresh = slot_x(pos, 7) + STRIDE / 2
            cross_frame = drag_cross_frame(thresh)
            if cross_frame is not None and f >= cross_frame:
                x = lerp(slot_x(pos, 7), slot_x(pos + 1, 7), spring(secs(f - cross_frame), 0.3, 0.85))
    return x


def drag_offset(f):
    t = (f - DRAG_A) / (DRAG_B - DRAG_A)
    return -2 * STRIDE * ease_io(t)


def drag_cross_frame(thresh):
    start_x = slot_x(4, 7)
    for f in range(DRAG_A, DRAG_B + 1):
        if start_x + drag_offset(f) <= thresh:
            return f
    return None


impulses.append((ARRIVE + 1, slot_x(0, 7), mm(5)))
impulses.append((RELEASE + 2, slot_x(2, 7), mm(3.5)))
bounce = rope_bounce_fn(impulses, X_HALF)

for f in frames(*ALL):
    t = secs(f)
    for key, n in top_notes.items():
        i = fi(f)
        loc = chan(n["rig"], "location", 3)
        x = top_slot_x(key, f)
        z = rope_z(x, TOP_END) + bounce(x, f)
        loc[i] = (x, ROPE_Y, z)
        tilt0 = note_tilt(n["seed"])
        tilt, swing = breeze(t, n["seed"])
        flex = 0.0
        if key != "new" and SHIFT <= f < SHIFT + 30:
            # notes being pushed sideways lag behind: a short tilt pulse
            v = spring(secs(f - SHIFT + 1), 0.4, 0.75) - spring(secs(f - SHIFT), 0.4, 0.75)
            tilt += -v * 1.2
        note_swing(n, f, tilt0 + tilt, swing, flex)

# Before the hang, the new note does not exist on the line
new = top_notes["new"]
set_fade(new["parts"], F0, 1.0)
for f in frames(F0, hang0):
    set_fade(new["parts"], f, 1.0)

# --- Composer pop-in (compose shot) and morph into the note (hang shot)
cl = chan(composer, "location", 3)
cs = chan(composer, "scale", 3)
cr = chan(composer, "rotation_euler", 3)
cf = chan(composer, '["fade"]', 1)
for f in frames(*ALL):
    i = fi(f)
    if f < comp0:
        cf[i] = 1.0
        continue
    t = secs(f - comp0)
    s = spring(t, 0.42, 0.72)
    cl[i] = COMPOSER_POS + Vector((0, mm(40) * (1 - s), -mm(25) * (1 - s)))
    sc = lerp(0.9, 1.0, s)
    cs[i] = (sc, sc, sc)
    cf[i] = 1 - clamp(t / 0.07)
    cr[i] = (math.radians(4) * (1 - s), 0, 0)
event(comp0, "pop")

# Morph: composer shrinks toward note size while the note grows out of it
MORPH = (hang0, hang0 + 10)
FLY = (hang0 + 10, ARRIVE)
note_center_offset = mm(10) + NOTE_H / 2
target = Vector((slot_x(0, 7), ROPE_Y, rope_z(slot_x(0, 7), TOP_END)))
sx0, sz0 = mm(600) / NOTE_W, mm(450) / NOTE_H
for f in frames(hang0, hang0 + 14):
    i = fi(f)
    m = ease_io((f - MORPH[0]) / (MORPH[1] - MORPH[0]))
    cs[i] = (lerp(1, 1 / sx0, m), 1, lerp(1, 1 / sz0, m))
    cf[i] = smooth((m - 0.15) / 0.5)
    cl[i] = COMPOSER_POS + Vector((0, 0, mm(8) * m))

nl = chan(new["rig"], "location", 3)
nr = chan(new["rig"], "rotation_euler", 3)
ns = chan(new["rig"], "scale", 3)
pin_s = chan(new["pin"], "scale", 3)
start_rig = COMPOSER_POS + Vector((0, -mm(4), note_center_offset))
ctrl = Vector((lerp(start_rig.x, target.x, 0.25), lerp(start_rig.y, target.y, 0.5) - mm(160), target.z + mm(80)))
for f in frames(hang0, hang1 + 200):
    i = fi(f)
    if f < FLY[0]:
        m = ease_io((f - MORPH[0]) / (MORPH[1] - MORPH[0]))
        sx, sz = lerp(sx0, 1, m), lerp(sz0, 1, m)
        ns[i] = (sx, 1, sz)
        nl[i] = COMPOSER_POS + Vector((0, -mm(4), note_center_offset * sz + mm(8) * m))
        set_fade(new["parts"], f, 1 - smooth(m / 0.45))
        pin_s[i] = (0, 0, 0)
        nr[i, 1] = 0
        continue
    if f < ARRIVE:
        u = ease_out((f - FLY[0]) / (FLY[1] - FLY[0]))
        a = start_rig + Vector((0, 0, mm(8)))
        pos = (1 - u) ** 2 * a + 2 * (1 - u) * u * ctrl + u * u * target
        nl[i] = pos
        ns[i] = (1, 1, 1)
        set_fade(new["parts"], f, 0.0)
        g = smooth((f - FLY[0]) / 8)
        pin_s[i] = (g, g, g)
        nr[i] = (math.radians(-10) * math.sin(math.pi * u), math.radians(-12) * u, math.radians(8) * math.sin(math.pi * u))
        flex = 0.55 * math.sin(math.pi * u)
        chan(new["paper"].data.shape_keys, 'key_blocks["flex"].value', 1)[i, 0] = flex
        pin_open(new, f, math.radians(16))
        continue
    # arrived: spring from -12 deg to the resting tilt, pin snaps shut
    t = secs(f - ARRIVE)
    tilt0 = note_tilt(new["seed"])
    tilt, swing = breeze(secs(f), new["seed"])
    s = spring(t, 0.7, 0.36)
    nr[i, 1] = lerp(math.radians(-12), tilt0, s) + tilt * smooth(t / 1.5)
    nr[i, 0] = 0
    nr[i, 2] = 0
    pin_s[i] = (1, 1, 1)
    ns[i] = (1, 1, 1)
    pin_open(new, f, math.radians(16) * (1 - smooth(t / 0.1)))
    chan(new["swing"], "rotation_euler", 3)[i, 0] = swing * smooth(t / 1.5) + math.radians(-7) * math.exp(-t / 0.35) * math.cos(2 * math.pi * t / 0.6)
    chan(new["paper"].data.shape_keys, 'key_blocks["flex"].value', 1)[i, 0] = 0.2 * math.exp(-t / 0.2)
    x = target.x
    nl[i] = (x, ROPE_Y, rope_z(x, TOP_END) + bounce(x, f))
event(hang0, "whoosh_short")
event(FLY[0], "whoosh")
event(ARRIVE, "clip")
event(SHIFT, "paper_shift")

# --- Drag (note 3: slot 4 -> slot 2)
dn = top_notes[DRAG_KEY]
dl = chan(dn["rig"], "location", 3)
dr = chan(dn["rig"], "rotation_euler", 3)
dsc = chan(dn["rig"], "scale", 3)
for f in frames(drag0, F1 + 1):
    i = fi(f)
    lift = smooth((f - PRESS) / 5) * (1 - smooth((f - RELEASE) / 6))
    x = slot_x(4, 7) + drag_offset(f)
    if f >= RELEASE:
        x = slot_x(2, 7)
    z = rope_z(x, TOP_END) + bounce(x, f)
    dl[i] = (x, ROPE_Y - mm(22) * lift, z + mm(4) * lift)
    sc = 1 + 0.035 * lift
    dsc[i] = (sc, sc, sc)
    tilt0 = note_tilt(dn["seed"])
    tilt, swing = breeze(secs(f), dn["seed"])
    vel = drag_offset(f + 1) - drag_offset(f)
    drag_tilt = -vel * 5.0 * lift  # paper trails the motion
    if f >= RELEASE:
        s = spring(secs(f - RELEASE), 0.5, 0.45)
        rest = lerp(0, tilt0, s)
    else:
        rest = tilt0 * (1 - lift)
    dr[i, 1] = rest + tilt * (1 - lift) + drag_tilt
    pin_open(dn, f, math.radians(9) * lift)
event(PRESS, "pickup")
event(DRAG_A, "slide")
event(RELEASE, "drop")
for key in (1, 2):
    pos = ORDER_AFTER.index(key)
    cf_ = drag_cross_frame(slot_x(pos, 7) + STRIDE / 2)
    if cf_:
        event(cf_, "paper_shift")

# rope bounce bake for the top rope
bake_rope_bounce(rig_top["rope"], impulses, X_HALF)

# Cursor path (drag shot)
crl = chan(cursor_root, "location", 3)
crs = chan(cursor_root, "scale", 3)
crf = chan(cursor, '["fade"]', 1)
grab = Vector((slot_x(4, 7) + mm(30), ROPE_Y - mm(60), rope_z(slot_x(4, 7), TOP_END) - mm(95)))
for f in frames(drag0, drag1):
    i = fi(f)
    a = Vector((mm(330), ROPE_Y - mm(60), mm(120)))
    if f < PRESS:
        u = ease_io((f - (drag0 + 8)) / (PRESS - 2 - (drag0 + 8)))
        p = a.lerp(grab, u)
    elif f < RELEASE:
        p = grab + Vector((drag_offset(f), -mm(22) * smooth((f - PRESS) / 5), 0))
    else:
        u = ease_io((f - RELEASE - 6) / 24)
        p = grab + Vector((-2 * STRIDE, 0, 0)) + Vector((mm(60), 0, -mm(90))) * u
    crl[i] = p
    press = smooth((f - PRESS + 2) / 3) * (1 - smooth((f - RELEASE) / 3))
    s = 1 - 0.12 * press
    crs[i] = (s, s, s)
    crf[i] = 1 - smooth((f - drag0 - 4) / 6) + smooth((f - drag1 + 14) / 8)

# --- Edges shot: rigs slide in/out (hiddenOffset 310 pt, spring 0.46 / 0.8)
EDGE_SWITCH = [edg0 + 27, edg0 + 63, edg0 + 99]  # top->right, right->bottom, bottom->left
OFFSETS = {"top": Vector((0, 0, mm(310))), "bottom": Vector((0, 0, -mm(310))), "right": Vector((mm(310), 0, 0)), "left": Vector((-mm(310), 0, 0))}
sequence = [("top", None, EDGE_SWITCH[0]), ("right", EDGE_SWITCH[0], EDGE_SWITCH[1]), ("bottom", EDGE_SWITCH[1], EDGE_SWITCH[2]), ("left", EDGE_SWITCH[2], None)]
rig_by = {"top": rig_top, "bottom": rig_bottom, "right": rig_right, "left": rig_left}
for kind, rig in rig_by.items():
    arr = chan(rig["root"], "location", 3)
    for f in frames(*ALL):
        arr[fi(f)] = OFFSETS[kind] if kind != "top" else (0, 0, 0)
for kind, t_in, t_out in sequence:
    rig = rig_by[kind]
    arr = chan(rig["root"], "location", 3)
    for f in frames(edg0, edg1):
        shown = 1.0
        if t_in is not None:
            shown = spring(secs(f - t_in - 4), 0.46, 0.8) if f >= t_in + 4 else 0.0
        if t_out is not None and f >= t_out:
            shown = 1 - spring(secs(f - t_out), 0.32, 1.0)
        arr[fi(f)] = OFFSETS[kind] * (1 - shown)
    # top rig returns for the drag shot
    if kind == "top":
        for f in frames(edg1, F1 + 1):
            arr[fi(f)] = (0, 0, 0)
    if t_in is not None:
        event(t_in, "swish")
        # notes arrive swinging, like HangingNote.onAppear
        for n in rig["notes"]:
            for f in frames(t_in + 4, edg1):
                tt = secs(f - t_in - 4)
                tilt0 = note_tilt(n["seed"])
                br, sw = breeze(secs(f), n["seed"])
                note_swing(n, f, lerp(math.radians(-12), tilt0, spring(tt, 0.7, 0.36)) + br, sw)

# Side and bottom rigs idle sway outside their entrance
for kind in ("right", "bottom", "left"):
    rig = rig_by[kind]
    t_in = dict((k, a) for k, a, _ in sequence)[kind]
    for n in rig["notes"]:
        for f in frames(F0, t_in + 4):
            br, sw = breeze(secs(f), n["seed"])
            note_swing(n, f, note_tilt(n["seed"]) + br, sw)
    if kind == "bottom":
        for idx, n in enumerate(rig["notes"]):
            x = slot_x(idx, 7)
            n["rig"].location = (x, ROPE_Y, rope_z(x, BOTTOM_END))

# --- Library window pop
ll = chan(library, "location", 3)
ls = chan(library, "scale", 3)
lf = chan(library, '["fade"]', 1)
lr = chan(library, "rotation_euler", 3)
for f in frames(lib0, lib1):
    i = fi(f)
    t = secs(f - lib0 - 2)
    s = spring(t, 0.45, 0.78)
    ll[i] = LIBRARY_POS + Vector((0, mm(60) * (1 - s), -mm(40) * (1 - s)))
    sc = lerp(0.92, 1.0, s)
    ls[i] = (sc, sc, sc)
    lf[i] = 1 - clamp(t / 0.15)
    lr[i] = (math.radians(5) * (1 - s), 0, 0)
event(lib0 + 2, "pop")

# --- KEYS: drop-in and presses
TRAVEL = mm(1.6)


def key_anim(k, f_range, drop_frame, presses):
    """presses: list of (down_frame, up_frame)."""
    loc = chan(k, "location", 3)
    base_z = k.location.z
    for f in f_range:
        i = fi(f)
        d = spring(secs(f - drop_frame), 0.5, 0.62) if f >= drop_frame else 0.0
        z = base_z + mm(28) * (1 - d)
        for down, up in presses:
            if down <= f < up + 8:
                pd = smooth((f - down) / 2.0)
                pu = 1 - spring(secs(f - up), 0.18, 0.55) if f >= up else 1.0
                z -= TRAVEL * pd * pu
        loc[i, 2] = z
        set_fade([k], f, 1 - smooth((f - drop_frame) / 3))


hk = KEYS["hotkey"]
DOWN = {"ctrl": hot0 + 34, "opt": hot0 + 44, "n": hot0 + 56}
UP = hot0 + 76
for idx, name in enumerate(("ctrl", "opt", "n")):
    key_anim(hk[name], frames(hot0 - 2, hot1 + 1), hot0 + 4 + idx * 4, [(DOWN[name], UP)])
    event(DOWN[name], "key_down", key=name)
event(UP, "key_up")
sk = KEYS["submit"]
SDOWN = {"cmd": sub0 + 4, "ret": sub0 + 12}
SUP = sub0 + 24
for name in ("cmd", "ret"):
    key_anim(sk[name], frames(sub0 - 2, sub1 + 1), sub0 - 40, [(SDOWN[name], SUP)])
    event(SDOWN[name], "key_down", key=name)
event(SUP, "key_up")

# Typing sound cues: key clicks between commits, a firmer click at each commit
rnd = random.Random(3)
prev = 0.55
for c, tc in zip(CONTENT["typingChunks"], COMMITS):
    n_clicks = max(1, int(len(c) * 2.2)) if c not in "\n，。：、" else 1
    for k in range(n_clicks):
        tt = prev + (tc - prev) * (k + 0.5) / (n_clicks + 0.5) + rnd.uniform(-0.015, 0.015)
        event(comp0 + round(tt * FPS * 1000) / 1000, "type")
    event(comp0 + tc * FPS, "type_commit")
    prev = tc

# --- END set: idle sway, icon entrance
for f in frames(*ALL):
    for n in end_notes:
        br, sw = breeze(secs(f), n["seed"], amp=1.3)
        note_swing(n, f, note_tilt(n["seed"]) + br, sw)

il = chan(icon_root, "location", 3)
ir = chan(icon_root, "rotation_euler", 3)
isc = chan(icon_root, "scale", 3)
ih = chan(icon_hinge, "rotation_euler", 3)
ICON_POS = None  # set after the end camera is defined


# ---------------------------------------------------------------------------
# Cameras and shots

cam_macro, foc_macro = camera("cam_macro", col_end, 100, 2.0)
cam_keys, foc_keys = camera("cam_keys", col_keys, 85, 3.2)
cam_compose, foc_compose = camera("cam_compose", col_main, 50, 3.2)
cam_main, foc_main = camera("cam_main", col_main, 50, 4.0)
cam_edges, foc_edges = camera("cam_edges", col_main, 50, 5.6)
cam_drag, foc_drag = camera("cam_drag", col_main, 50, 3.5)
cam_lib, foc_lib = camera("cam_lib", col_main, 50, 3.2)
cam_end, foc_end = camera("cam_end", col_end, 70, 2.4)

# Macro: slow dolly along the END line, rack focus from a clothespin to a note's text
n1, n2 = end_notes[2], end_notes[3]


def macro_pose(f):
    u = ease_io((f - macro0) / (macro1 - macro0))
    x = lerp(n1["x"] - 0.16, n2["x"] - 0.13, u)
    p = END_O + Vector((x, -0.62, -0.085 + 0.02 * u))
    t = END_O + Vector((x + 0.17, 0.0, -0.105 + 0.01 * u))
    pin_pt = Vector(n1["rig"].location) + Vector((0, 0, mm(-4)))
    text_pt = Vector(n2["rig"].location) + Vector((0, 0, -mm(70)))
    rf = smooth((f - macro0 - 40) / 45)
    fp = pin_pt.lerp(text_pt, rf)
    return p, t, fp, 100


bake_camera(cam_macro, foc_macro, list(frames(macro0, macro1)), macro_pose)


def keys_pose(f):
    if f < sub0:
        u = ease_io((f - hot0) / (hot1 - hot0))
        c = KEYS_O + Vector((0.0, 0, 0))
        p = c + Vector((lerp(0.06, 0.025, u), lerp(-0.21, -0.18, u), lerp(0.165, 0.14, u)))
        t = c + Vector((0.003, 0.004, 0))
        return p, t, KEYS["hotkey"]["opt"].location, 85
    u = ease_io((f - sub0) / (sub1 - sub0))
    c = KEYS_O + Vector((0.2 + 0.006, 0, 0))
    p = c + Vector((lerp(-0.05, -0.03, u), lerp(-0.2, -0.175, u), lerp(0.15, 0.13, u)))
    t = c + Vector((0, 0.004, 0))
    return p, t, c, 85


bake_camera(cam_keys, foc_keys, list(frames(hot0, sub1)), keys_pose)


def compose_pose(f):
    u = ease_io((f - comp0) / (comp1 - comp0))
    c = COMPOSER_POS
    t = c + Vector((lerp(0.02, -0.11, u), 0, lerp(0.0, 0.075, u)))
    p = t + Vector((lerp(0.40, 0.13, u), lerp(-1.62, -0.80, u), lerp(0.16, 0.05, u)))
    return p, t, c + Vector((-0.13, -mm(4), 0.07)), 50


bake_camera(cam_compose, foc_compose, list(frames(comp0, comp1)), compose_pose)

HANG_END_P = target + Vector((mm(230), -0.78, -mm(60)))
HANG_END_T = target + Vector((mm(150), 0, -mm(110)))
REV_END_P = Vector((0.92, -3.15, 0.34))
REV_END_T = Vector((0.0, 0.0, 0.06))


FOLLOW = {}
_prev = None
for _f in frames(hang0, ARRIVE + 7):
    _c = COMPOSER_POS + Vector((0, 0, 0.02)) if _f < FLY[0] else Vector(nl[fi(_f)]) + Vector((0, 0, -mm(95)))
    _prev = _c if _prev is None else _prev.lerp(_c, 0.2)
    FOLLOW[_f] = _prev


def main_pose(f):
    new_c = Vector(nl[fi(f)]) + Vector((0, 0, -mm(95)))
    if f < ARRIVE + 6:
        u = ease_io((f - hang0) / (ARRIVE + 6 - hang0))
        off = vlerp((0.20, -1.32, 0.06), HANG_END_P - HANG_END_T, u)
        t = FOLLOW[f].lerp(HANG_END_T, smooth((f - (ARRIVE - 8)) / 14))
        return t + off, t, new_c, 50
    if f < rev0:
        u = (f - ARRIVE - 6) / max(1, rev0 - ARRIVE - 6)
        p = HANG_END_P + Vector((-mm(30) * u, mm(40) * u, 0))
        return p, HANG_END_T, new_c, 50
    u = ease_io_quint((f - rev0) / (rev1 - rev0))
    hp = HANG_END_P + Vector((-mm(30), mm(40), 0))
    p = hp.lerp(REV_END_P, u)
    p.z += 0.25 * math.sin(math.pi * u)
    t = HANG_END_T.lerp(REV_END_T, u)
    fp = new_c.lerp(Vector((0, -0.04, 0.2)), u)
    return p, t, fp, lerp(50, 50, u)


bake_camera(cam_main, foc_main, list(frames(hang0, rev1)), main_pose)


def edges_pose(f):
    u = ease_io((f - edg0) / (edg1 - edg0))
    p = Vector((lerp(0.6, 0.2, u), lerp(-4.15, -3.95, u), lerp(0.0, -0.08, u)))
    return p, Vector((0, 0, -0.21)), Vector((0, -0.04, 0)), 50


bake_camera(cam_edges, foc_edges, list(frames(edg0, edg1)), edges_pose)


def drag_pose(f):
    u = ease_io((f - drag0) / (drag1 - drag0))
    c = Vector((mm(60), ROPE_Y, rope_z(0, TOP_END) - mm(80)))
    p = c + Vector((lerp(0.20, 0.08, u), lerp(-1.22, -1.08, u), lerp(-0.02, 0.0, u)))
    fp = Vector(dl[fi(f)]) + Vector((0, 0, -mm(90)))
    return p, c, fp, 50


bake_camera(cam_drag, foc_drag, list(frames(drag0, drag1)), drag_pose)


def lib_pose(f):
    u = ease_io((f - lib0) / (lib1 - lib0))
    c = LIBRARY_POS
    t = c + Vector((0.02, 0, -0.10))
    p = t + Vector((lerp(-0.62, -0.48, u), lerp(-2.15, -1.95, u), lerp(0.24, 0.17, u)))
    return p, t, c + Vector((-mm(150), 0, 0)), 50


bake_camera(cam_lib, foc_lib, list(frames(lib0, lib1)), lib_pose)

END_CAM_P = END_O + Vector((0.0, -1.95, -0.30))
END_CAM_T = END_O + Vector((0.0, 0.0, -0.30))


def ray_point(cam_loc, cam_target, lens, px, py, dist):
    """World point at distance `dist` along the camera ray through pixel (px, py)."""
    fwd = (Vector(cam_target) - Vector(cam_loc)).normalized()
    q = fwd.to_track_quat("-Z", "Y")
    k = 18 / lens
    dx = (px - T.WIDTH / 2) / (T.WIDTH / 2) * k
    dy = -(py - T.HEIGHT / 2) / (T.WIDTH / 2) * k
    return Vector(cam_loc) + q @ Vector((dx * dist, dy * dist, -dist))


ICON_DIST = 1.30
ICON_POS = ray_point(END_CAM_P, END_CAM_T, 70, 960, 372, ICON_DIST)
icon_px = 380  # target tile height in pixels
icon_scale = icon_px / (T.WIDTH / 2) * (18 / 70) * ICON_DIST / (984 * mm(0.3))


def end_pose(f):
    u = ease_io_quint((f - end0) / (end1 - end0))
    p = END_CAM_P + Vector((0.0, 0.10 * u, 0.0))
    return p, END_CAM_T + Vector((0, 0, 0)), ICON_POS, 70


bake_camera(cam_end, foc_end, list(frames(end0, end1)), end_pose)

for f in frames(*ALL):
    i = fi(f)
    t = secs(f - end0 - 2)
    s = spring(t, 0.95, 0.72) if t > 0 else 0.0
    il[i] = ICON_POS + Vector((0, 0.10 * (1 - s), -0.20 * (1 - s)))
    idle = math.sin(secs(f) * 0.9) * smooth(t / 2)
    ir[i] = (math.radians(38) * (1 - s) + math.radians(7), 0, math.radians(-24) * (1 - s) + math.radians(-11) + math.radians(2.5) * idle)
    sc = icon_scale * lerp(0.8, 1.0, s)
    isc[i] = (sc, sc, sc)
    tt = secs(f - end0 - 16)
    ih[i, 1] = math.radians(-14) * (1 - spring(tt, 0.7, 0.36)) if tt > 0 else math.radians(-14)
glint = area_light("end_glint", col_end, END_O, END_O, 0.25, 0, (1.0, 0.97, 0.92), size_y=1.2, cutoff=5)
gl = chan(glint, "location", 3)
gr = chan(glint, "rotation_euler", 3)
ge = chan(glint.data, "energy", 1)
for f in frames(end0, end1):
    u = ease_io((f - end0 - 40) / 70)
    pos = ICON_POS + Vector((lerp(-0.9, 0.9, u), -0.9, 0.35))
    gl[fi(f)] = pos
    gr[fi(f)] = (ICON_POS - pos).to_track_quat("-Z", "Y").to_euler()
    ge[fi(f), 0] = 140 * math.sin(math.pi * u)
event(end0 + 2, "whoosh_soft")
event(end0 + 20, "chime")

# Markers: camera per shot
for name, cam in (("macro", cam_macro), ("hotkey", cam_keys), ("compose", cam_compose), ("submit", cam_keys),
                  ("hang", cam_main), ("reveal", cam_main), ("edges", cam_edges), ("drag", cam_drag),
                  ("library", cam_lib), ("end", cam_end)):
    mk = scene.timeline_markers.new(name, frame=S[name][0])
    mk.camera = cam
scene.camera = cam_macro

bake_all()

os.makedirs(BUILD, exist_ok=True)
EVENTS.sort(key=lambda e: e["frame"])
json.dump({"fps": FPS, "frame_start": F0, "frame_end": F1, "events": EVENTS}, open(os.path.join(BUILD, "events.json"), "w"), indent=1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BUILD, "idealine_promo.blend"))
print(f"Saved scene with {len(CHANNELS)} animated channels, {len(EVENTS)} sound cues")
