"""Validate final files, not merely the Blender scene. Requires Blender 4.3/numpy.

blender -b --factory-startup --disable-autoexec --python-exit-code 1 \
  --python tools/knight/validate_roblox.py -- --asset-dir assets/knight
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import copy
import struct
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Matrix
from io_scene_fbx import parse_fbx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_roblox import assembled_signature, ACTIONS
from fbx_channels import section
from glb_validation import GLB, nearest_correspondence, validate_glb


def positions(objects):
    points = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        data = evaluated.to_mesh()
        points.extend(tuple(obj.matrix_world @ v.co) for v in data.vertices)
        evaluated.to_mesh_clear()
    return np.array(points)


def mesh_bones(objects):
    result = []
    for obj in objects:
        for vertex in obj.data.vertices:
            weights = [g for g in vertex.groups if g.weight > 1e-6]
            assert len(weights) == 1 and abs(weights[0].weight - 1) < 1e-6
            result.append(obj.vertex_groups[weights[0].group].name)
    return result


def hierarchy(rig):
    return {b.name: b.parent.name if b.parent else None for b in rig.data.bones}


def reference_from_source(path):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    scene = bpy.context.scene
    rig = bpy.data.objects['Knight_Rig']
    meshes = sorted((o for o in scene.objects if o.type == 'MESH'), key=lambda o: o.name)
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks: track.mute = True
    for pb in rig.pose.bones: pb.matrix_basis = Matrix.Identity(4)
    scene.frame_set(1)
    rig.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    result = {'bones': mesh_bones(meshes), 'rest': positions(meshes),
              'hierarchy': hierarchy(rig), 'poses': {},
              'signature': assembled_signature(meshes),
              'textures': {i.name: hashlib.sha256(i.packed_file.data).hexdigest()
                           for i in bpy.data.images if i.packed_file}}
    rig.data.pose_position = 'POSE'
    for name in ACTIONS:
        rig.animation_data.action = bpy.data.actions[name]
        frames = []
        for frame in range(1, int(bpy.data.actions[name].frame_range[1])+1):
            scene.frame_set(frame)
            frames.append(positions(meshes))
        result['poses'][name] = frames
    return result


def audit_fbx(path, reference):
    root, version = parse_fbx.parse(str(path))
    objects = section(root,b'Objects').elems
    connections = section(root,b'Connections').elems
    by_id = {o.props[0]:o for o in objects}
    node_properties = [c.props[3] for c in connections if len(c.props)==4
                       and by_id.get(c.props[1]) and by_id[c.props[1]].id==b'AnimationCurveNode']
    assert node_properties and set(node_properties)<= {b'Lcl Rotation',b'Lcl Translation'}
    for obj in objects:
        if obj.id==b'Deformer': assert obj.props[-1] in (b'Skin',b'Cluster')
        for element in obj.elems:
            if element.id==b'Properties70':
                for prop in element.elems:
                    if prop.id==b'P' and prop.props[0]==b'Lcl Scaling':
                        assert b'+' not in prop.props[3]
                        assert np.allclose(prop.props[4:],1,atol=2e-6)
    geometries=[o for o in objects if o.id==b'Geometry' and o.props[-1]==b'Mesh']
    mesh_models=[o for o in objects if o.id==b'Model' and o.props[-1]==b'Mesh']
    skins=[o for o in objects if o.id==b'Deformer' and o.props[-1]==b'Skin']
    bones=[o for o in objects if o.id==b'Model' and o.props[-1]==b'LimbNode']
    stacks=[o for o in objects if o.id==b'AnimationStack']
    assert len(geometries)==len(mesh_models)==len(skins)==1 and len(bones)==17 and len(stacks)==3
    poses=[o for o in objects if o.id==b'Pose' and o.props[-1]==b'BindPose']
    assert len(poses)==1
    pose_matrices={}
    for pose_node in poses[0].elems:
        if pose_node.id==b'PoseNode':
            index=next(e.props[0] for e in pose_node.elems if e.id==b'Node')
            values=next(e.props[0] for e in pose_node.elems if e.id==b'Matrix')
            pose_matrices[index]=np.array(values).reshape(4,4).T
    mesh_bind=pose_matrices[mesh_models[0].props[0]]
    clusters=[o for o in objects if o.id==b'Deformer' and o.props[-1]==b'Cluster']
    weights=Counter();bind_error=0
    for cluster in clusters:
        elements={e.id:e for e in cluster.elems}
        transform=np.array(elements[b'Transform'].props[0]).reshape(4,4).T
        link=np.array(elements[b'TransformLink'].props[0]).reshape(4,4).T
        # FBX stores this Transform in bone space, not as the world mesh matrix.
        bind_error=max(bind_error,float(np.abs(link @ transform-mesh_bind).max()))
        bone_id=next(c.props[1] for c in connections if len(c.props)>=3
                     and c.props[2]==cluster.props[0] and c.props[1] in by_id
                     and by_id[c.props[1]].id==b'Model')
        assert np.allclose(link,pose_matrices[bone_id],atol=1e-6)
        indices=elements[b'Indexes'].props[0] if b'Indexes' in elements else []
        values=elements[b'Weights'].props[0] if b'Weights' in elements else []
        assert len(indices)==len(values)
        for index,value in zip(indices,values):
            assert abs(value-1)<1e-6
            weights[index]+=1
    assert bind_error<1e-5 and all(value==1 for value in weights.values())
    vertices=next(e.props[0] for e in geometries[0].elems if e.id==b'Vertices')
    assert len(weights)==len(vertices)//3
    embedded={hashlib.sha256(e.props[0]).hexdigest()
              for obj in objects if obj.id==b'Video' for e in obj.elems if e.id==b'Content'}
    assert reference['textures']['Image_0'] in embedded and reference['textures']['Image_2'] in embedded
    return {'format':'FBX','binary_version':version,'mesh_count':1,'skin_count':1,'bone_count':17,
            'scale_animation_channels':0,'weight_animation_channels':0,
            'channel_types':{k.decode():v for k,v in Counter(node_properties).items()},
            'bind_matrix_identity_error':bind_error,'rigid_weights':True,
            'embedded_base_color_and_normal_bytes_unchanged':True,
            'animation_stacks':[s.props[1].split(b'\x00')[0].decode() for s in stacks]}


def validate_fbx(path, reference):
    report = audit_fbx(path,reference)
    for obj in list(bpy.data.objects): bpy.data.objects.remove(obj,do_unlink=True)
    for action in list(bpy.data.actions): bpy.data.actions.remove(action)
    # Import from a temporary directory: embedded textures must not dirty assets/.
    with tempfile.TemporaryDirectory(prefix='knight-v2-import-') as directory:
        copy=Path(directory)/path.name;shutil.copyfile(path,copy)
        bpy.ops.import_scene.fbx(filepath=str(copy),anim_offset=0,use_anim=True,
                                 automatic_bone_orientation=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        meshes=sorted((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:o.name)
        assert len(meshes)==1 and hierarchy(rig)==reference['hierarchy']
        rig.animation_data.action=None
        for track in rig.animation_data.nla_tracks:track.mute=True
        rig.data.pose_position='REST';bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
        rest=positions(meshes);bones=mesh_bones(meshes)
        correspondence,rest_error=nearest_correspondence(rest,bones,reference)
        assert Counter(bones)==Counter(reference['bones'])
        mesh=meshes[0];mesh.data.calc_loop_triangles()
        assert len(mesh.data.loop_triangles)==4072
        edges=np.array([list(e.vertices) for e in mesh.data.edges])
        lengths=np.linalg.norm(rest[edges[:,0]]-rest[edges[:,1]],axis=1)
        rig.data.pose_position='POSE'
        results=[];max_edges=0;max_sword=0
        for name in ACTIONS:
            matches=[a for a in bpy.data.actions if a.name.endswith(name)]
            assert len(matches)==1,(name,[a.name for a in bpy.data.actions])
            action=matches[0]
            # Blender's FBX importer synthesizes unit-scale FCurves when it
            # decomposes baked TRS, even without any scale curve in the file.
            for curve in action.fcurves:
                assert 'weight' not in curve.data_path
                if 'scale' in curve.data_path:
                    assert np.allclose([point.co[1] for point in curve.keyframe_points], 1, atol=2e-6, rtol=0)
            rig.animation_data.action=action
            first, last = action.frame_range
            assert abs(last-first-(len(reference['poses'][name])-1))<1e-4, list(action.frame_range)
            error=0;sword_rest=rig.data.bones['Hand.R'].matrix_local.inverted() @ rig.data.bones['Sword'].matrix_local
            for frame,expected in enumerate(reference['poses'][name],start=1):
                bpy.context.scene.frame_set(int(first)+frame-1);current=positions(meshes)
                error=max(error,float(np.linalg.norm(current-expected[correspondence],axis=1).max()))
                max_edges=max(max_edges,float(np.abs(np.linalg.norm(current[edges[:,0]]-current[edges[:,1]],axis=1)-lengths).max()))
                relative=rig.pose.bones['Hand.R'].matrix.inverted() @ rig.pose.bones['Sword'].matrix
                max_sword=max(max_sword,float(np.abs(np.array(relative)-np.array(sword_rest)).max()))
            assert error<2e-5,(name,error)
            results.append({'name':name,'frames_checked':len(reference['poses'][name]),'imported_frame_range':[float(first),float(last)],'max_source_pose_error':error})
        assert max_edges<1e-5 and max_sword<1e-5
        report.update(assembled_position_error=rest_error,max_edge_length_change=max_edges,
                      max_sword_hand_relative_error=max_sword,animations=results)
    return report


def validation_guards(path, reference):
    """Prove the validator rejects the actual failure classes, using corrupt files."""
    glb = GLB(path)
    def write_fixture(destination, document, binary):
        payload = json.dumps(document, separators=(',', ':')).encode()
        payload += b' ' * (-len(payload) % 4)
        header = struct.pack('<4sII', b'glTF', 2, 12+8+len(payload)+8+len(binary))
        destination.write_bytes(header+struct.pack('<II',len(payload),0x4e4f534a)+payload
                                +struct.pack('<II',len(binary),0x004e4942)+binary)
    results = []
    with tempfile.TemporaryDirectory(prefix='knight-v2-negative-') as temporary:
        for test in ('scale_channel', 'wrong_head_inverse_bind', 'sword_weighted_to_head'):
            document = copy.deepcopy(glb.doc);binary = bytearray(glb.binary)
            if test == 'scale_channel':
                document['animations'][0]['channels'][0]['target']['path'] = 'scale'
            elif test == 'wrong_head_inverse_bind':
                skin = document['skins'][0]
                head = next(i for i,joint in enumerate(skin['joints']) if document['nodes'][joint]['name']=='Head')
                accessor = document['accessors'][skin['inverseBindMatrices']]
                view = document['bufferViews'][accessor['bufferView']]
                offset = view.get('byteOffset',0)+accessor.get('byteOffset',0)+head*64+12*4
                value = struct.unpack_from('<f',binary,offset)[0]
                struct.pack_into('<f',binary,offset,value+.5)
            else:
                skin = document['skins'][0]
                names = [document['nodes'][joint]['name'] for joint in skin['joints']]
                primitive = document['meshes'][0]['primitives'][0]
                joints = glb.accessor(primitive['attributes']['JOINTS_0'])
                weights = glb.accessor(primitive['attributes']['WEIGHTS_0'])
                accessor = document['accessors'][primitive['attributes']['JOINTS_0']]
                view = document['bufferViews'][accessor['bufferView']]
                code = {5121:'B',5123:'H'}[accessor['componentType']];size=struct.calcsize(code)
                changed=0
                for vertex, row in enumerate(joints):
                    slot=int(np.argmax(weights[vertex]))
                    if int(row[slot]) == names.index('Sword'):
                        offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)+vertex*view.get('byteStride',4*size)+slot*size
                        struct.pack_into('<'+code,binary,offset,names.index('Head'));changed+=1
                assert changed>0
            fixture=Path(temporary)/(test+'.glb');write_fixture(fixture,document,binary)
            try:validate_glb(fixture,reference)
            except AssertionError:results.append({'case':test,'rejected':True})
            else:raise AssertionError('Validator accepted corrupt export: '+test)
    return results


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser();parser.add_argument('--asset-dir',type=Path,required=True)
    out=parser.parse_args(args).asset_dir.resolve()
    reference=reference_from_source(out/'Knight_Rigged_Animated.blend')
    export_report=json.loads((out/'Knight_Roblox_Test_v2-export-report.json').read_text())
    assert reference['signature']==(export_report['geometry_uv_rigid_weight_signature'],4072)
    assert reference['textures']==export_report['textures_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(out/'Knight_Roblox_Test_v2.blend'),load_ui=False,use_scripts=False)
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    assert assembled_signature(meshes)==reference['signature']
    rig=bpy.data.objects['Knight_Rig']
    assert hierarchy(rig)==reference['hierarchy'] and rig.animation_data.action is None
    assert all(np.allclose(np.array(o.matrix_world),np.eye(4),atol=1e-6) for o in [rig,*meshes])
    glb=validate_glb(out/'Knight_Roblox_Test_v2.glb',reference)
    guards=validation_guards(out/'Knight_Roblox_Test_v2.glb',reference)
    fbx=validate_fbx(out/'Knight_Roblox_Test_v2.fbx',reference)
    report={'status':'passed_local_validation','primary_roblox_test_file':'Knight_Roblox_Test_v2.fbx',
            'triangles':4072,'bones':reference['hierarchy'],
            'geometry_uv_rigid_weight_signature_unchanged':True,
            'source_textures_sha256':reference['textures'],'fbx':fbx,'glb':glb,
            'negative_validation_controls':guards,
            'roblox_studio_test':'Required; no Roblox Studio runtime is available in this environment.',
            'limitations':['Custom skeleton, not R15. No gameplay integration.',
                'FBX does not carry the original glTF packed metallic/roughness shader graph; use unchanged supplied maps for SurfaceAppearance setup.',
                'Studio 3D Importer rest pose and all three clips still need manual verification.']}
    (out/'Knight_Roblox_Test_v2-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS local source/export validation:',json.dumps(report))


if __name__=='__main__':main()
