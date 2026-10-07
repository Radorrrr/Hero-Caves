"""Blender 4.3: normalize the existing Knight and export a separate v2 test asset.

blender -b --disable-autoexec assets/knight/Knight_Rigged_Animated.blend \
  --python tools/knight/export_roblox.py -- --output-dir assets/knight
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fbx_channels import remove_constant_scale

ACTIONS = ('Knight_Idle', 'Knight_Walk', 'Knight_SwordAttack')


def assembled_signature(objects):
    """Triangle corners include the original UV and rigid bone: join must preserve all."""
    triangles = []
    for obj in objects:
        obj.data.calc_loop_triangles()
        uv = obj.data.uv_layers.active
        assert uv is not None and obj.data.shape_keys is None
        for triangle in obj.data.loop_triangles:
            corners = []
            for vertex_index, loop_index in zip(triangle.vertices, triangle.loops):
                vertex = obj.data.vertices[vertex_index]
                influences = [g for g in vertex.groups if g.weight > 0]
                assert len(influences) == 1 and abs(influences[0].weight - 1) < 1e-6
                name = obj.vertex_groups[influences[0].group].name
                position = obj.matrix_world @ vertex.co
                corners.append((name, *[round(x, 7) for x in position],
                                *[round(x, 7) for x in uv.data[loop_index].uv]))
            triangles.append(tuple(sorted(corners)))
    return hashlib.sha256(repr(sorted(triangles)).encode()).hexdigest(), len(triangles)


def identity(matrix):
    return max(abs(matrix[r][c] - (1 if r == c else 0))
               for r in range(4) for c in range(4)) < 1e-6


def clean_glb(raw_path, output_path):
    data = raw_path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data)
    assert magic == b'glTF' and version == 2 and length == len(data)
    json_size, json_type = struct.unpack_from('<II', data, 12)
    document = json.loads(data[20:20 + json_size])
    offset = 20 + json_size
    binary_size, binary_type = struct.unpack_from('<II', data, offset)
    binary = data[offset + 8:offset + 8 + binary_size]
    removed = 0
    import numpy as np
    for animation in document['animations']:
        kept = []
        for channel in animation['channels']:
            path = channel['target']['path']
            assert path != 'weights', 'Morph/weight animation is not supported'
            if path == 'scale':
                sampler = animation['samplers'][channel['sampler']]
                accessor = document['accessors'][sampler['output']]
                view = document['bufferViews'][accessor['bufferView']]
                assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC3'
                assert view.get('byteStride', 12) == 12
                values = np.frombuffer(binary, dtype='<f4', count=accessor['count'] * 3,
                                       offset=view.get('byteOffset', 0) + accessor.get('byteOffset', 0))
                assert np.allclose(values, 1, atol=2e-6, rtol=0)
                removed += 1
            else:
                assert path in ('rotation', 'translation')
                kept.append(channel)
        used = sorted({channel['sampler'] for channel in kept})
        mapping = {old: new for new, old in enumerate(used)}
        animation['samplers'] = [animation['samplers'][i] for i in used]
        for channel in kept:
            channel['sampler'] = mapping[channel['sampler']]
        animation['channels'] = kept
    parents = {child: index for index, node in enumerate(document['nodes'])
               for child in node.get('children', [])}
    for skin in document['skins']:
        roots = [joint for joint in skin['joints'] if parents.get(joint) not in skin['joints']]
        assert len(roots) == 1
        skin['skeleton'] = roots[0]  # Explicit single skeleton root for importers.
    payload = json.dumps(document, separators=(',', ':')).encode()
    payload += b' ' * (-len(payload) % 4)
    output = struct.pack('<4sII', magic, version, 12 + 8 + len(payload) + 8 + len(binary))
    output += struct.pack('<II', len(payload), json_type) + payload
    output += struct.pack('<II', len(binary), binary_type) + binary
    output_path.write_bytes(output)
    return {'removed_constant_scale_channels': removed}


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', type=Path, required=True)
    options = parser.parse_args(args)
    out = options.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    source = Path(bpy.data.filepath)
    assert source.name == 'Knight_Rigged_Animated.blend', 'Load the original source, not v2'
    rig = bpy.data.objects['Knight_Rig']
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert len(meshes) == 16 and len(rig.data.bones) == 17
    assert not rig.constraints and not (rig.animation_data and rig.animation_data.drivers)
    for obj in [rig, *meshes]:
        # The existing source is already normalized. Reject unexpected changes rather
        # than baking an unknown object transform into animated bone translations.
        assert identity(obj.matrix_world) and identity(obj.matrix_parent_inverse), obj.name
        assert not obj.constraints and not (obj.animation_data and obj.animation_data.drivers)
    for action in bpy.data.actions:
        for curve in action.fcurves:
            assert 'scale' not in curve.data_path and 'weight' not in curve.data_path
    textures_before = {image.name: hashlib.sha256(image.packed_file.data).hexdigest()
                       for image in bpy.data.images if image.packed_file}
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    for pose in rig.pose.bones:
        assert not pose.constraints
        pose.matrix_basis = Matrix.Identity(4)
    rig.data.pose_position = 'POSE'
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    before, triangles = assembled_signature(meshes)
    assert triangles == 4072
    # Detach without moving vertices, apply the identity transforms, then join.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        obj.select_set(True)
    bpy.context.view_layer.objects.active = sorted(meshes, key=lambda o: o.name)[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = 'Basic_Knight'
    mesh.data.name = 'Basic_Knight_4072_Tris'
    mesh.parent = rig
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    mesh.matrix_basis = Matrix.Identity(4)
    assert len(mesh.modifiers) == 1 and mesh.modifiers[0].type == 'ARMATURE'
    mesh.modifiers[0].object = rig
    assert assembled_signature([mesh]) == (before, triangles)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    assert identity(rig.matrix_world) and identity(mesh.matrix_world)
    # Keep all maps packed and byte-for-byte identical. FBX embeds supported maps;
    # GLB and .blend preserve the complete original packed metallic/roughness graph.
    for image in bpy.data.images:
        if image.packed_file:
            image.filepath = str(source.parent / 'textures' / (image.name + '.jpg'))
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    for name in ACTIONS:
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.mute = True
        action = bpy.data.actions[name]
        strip = track.strips.new(name, 1, action)
        strip.action_frame_start, strip.action_frame_end = action.frame_range
    rig.animation_data.action = None  # Saved file opens assembled, without an active pose.
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end, scene.render.fps = 1, 61, 30
    scene.frame_set(1)
    bpy.context.view_layer.update()
    assert assembled_signature([mesh]) == (before, triangles)
    bpy.ops.file.pack_all()
    assert textures_before == {image.name: hashlib.sha256(image.packed_file.data).hexdigest()
                               for image in bpy.data.images if image.packed_file}
    bpy.ops.wm.save_as_mainfile(filepath=str(out / 'Knight_Roblox_Test_v2.blend'))
    mesh.select_set(True)
    report = {
        'original_source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'source_mesh_count': 16, 'export_mesh_count': 1, 'bone_count': 17,
        'triangles': triangles, 'geometry_uv_rigid_weight_signature': before,
        'textures_sha256': textures_before, 'object_transforms_identity': True,
        'animation_actions': [{'name': name, 'frames': list(bpy.data.actions[name].frame_range)}
                              for name in ACTIONS], 'fps': 30,
    }
    with tempfile.TemporaryDirectory(prefix='knight-v2-export-') as temporary:
        temp = Path(temporary)
        raw_fbx = temp / 'Knight_Roblox_Test_v2.fbx'
        bpy.ops.export_scene.fbx(
            filepath=str(raw_fbx), use_selection=True, object_types={'MESH', 'ARMATURE'},
            use_mesh_modifiers=True, add_leaf_bones=False, use_armature_deform_only=True,
            apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS',
            bake_space_transform=False, axis_forward='-Z', axis_up='Y',
            bake_anim=True, bake_anim_use_all_actions=True, bake_anim_use_nla_strips=False,
            bake_anim_use_all_bones=True, bake_anim_force_startend_keying=True,
            bake_anim_step=1, bake_anim_simplify_factor=0,
            path_mode='COPY', embed_textures=True)
        report['fbx_cleanup'] = remove_constant_scale(raw_fbx, out / raw_fbx.name)
        raw_glb = temp / 'Knight_Roblox_Test_v2.glb'
        bpy.ops.export_scene.gltf(
            filepath=str(raw_glb), export_format='GLB', use_selection=True,
            export_animations=True, export_force_sampling=True, export_anim_slide_to_zero=True,
            export_animation_mode='NLA_TRACKS', export_nla_strips=True)
        report['glb_cleanup'] = clean_glb(raw_glb, out / raw_glb.name)
    (out / 'Knight_Roblox_Test_v2-export-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS v2 export:', json.dumps(report))


if __name__ == '__main__':
    main()
