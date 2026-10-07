"""Read and skin exported glTF numerically; independent of Blender's glTF importer."""
import json
import struct
from collections import Counter
import numpy as np


def quaternion_matrix(q):
    x, y, z, w = np.array(q, dtype=float) / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0],
                     [0, 0, 0, 1]])


def nearest_correspondence(points, bones, reference):
    indices = np.empty(len(points), dtype=int)
    maximum = 0
    for bone in sorted(set(bones)):
        target = np.flatnonzero(np.array(bones) == bone)
        source = np.flatnonzero(np.array(reference['bones']) == bone)
        assert len(source), bone
        distances = np.sum((points[target, None, :] - reference['rest'][source][None, :, :])**2, axis=2)
        best = np.argmin(distances, axis=1)
        error = float(np.sqrt(distances[np.arange(len(target)), best]).max())
        assert error < 1e-5, (bone, error)
        indices[target] = source[best]
        maximum = max(maximum, error)
    assert set(bones) == set(reference['bones'])
    # Check source coverage as well; duplicated seam vertices may have the same point.
    for bone in sorted(set(bones)):
        target = np.flatnonzero(np.array(bones) == bone)
        source = np.flatnonzero(np.array(reference['bones']) == bone)
        distances = np.sum((reference['rest'][source, None, :] - points[target][None, :, :])**2, axis=2)
        assert float(np.sqrt(np.min(distances, axis=1)).max()) < 1e-5, bone
    return indices, maximum


class GLB:
    def __init__(self, path):
        raw = path.read_bytes()
        magic, version, length = struct.unpack_from('<4sII', raw)
        assert magic == b'glTF' and version == 2 and length == len(raw)
        length, kind = struct.unpack_from('<II', raw, 12)
        self.doc = json.loads(raw[20:20+length])
        offset = 20+length
        size, kind = struct.unpack_from('<II', raw, offset)
        self.binary = raw[offset+8:offset+8+size]
        self.parent = {child: index for index, node in enumerate(self.doc['nodes'])
                       for child in node.get('children', [])}

    def accessor(self, index):
        a = self.doc['accessors'][index]
        assert 'sparse' not in a
        view = self.doc['bufferViews'][a['bufferView']]
        dtype = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
        size = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        step = np.dtype(dtype).itemsize
        values = np.ndarray((a['count'], size), dtype=dtype, buffer=self.binary,
                            offset=view.get('byteOffset',0)+a.get('byteOffset',0),
                            strides=(view.get('byteStride',size*step),step)).copy()
        if a.get('normalized'):
            assert dtype in ('u1','<u2')
            values = values.astype(float) / np.iinfo(np.dtype(dtype)).max
        return values

    def globals(self, transforms=None):
        matrices = {}
        def world(index):
            if index in matrices:return matrices[index]
            node = self.doc['nodes'][index]
            if 'matrix' in node:
                assert not transforms or index not in transforms
                local = np.array(node['matrix']).reshape(4,4).T
            else:
                values = dict(node)
                if transforms and index in transforms:values.update(transforms[index])
                local = quaternion_matrix(values.get('rotation',[0,0,0,1]))
                local[:3,:3] *= np.array(values.get('scale',[1,1,1]))[None,:]
                local[:3,3] = values.get('translation',[0,0,0])
            matrices[index] = world(self.parent[index]) @ local if index in self.parent else local
            return matrices[index]
        for index in range(len(self.doc['nodes'])):world(index)
        return matrices

    def animation_transforms(self, animation, time):
        result = {}
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            interpolation = sampler.get('interpolation','LINEAR')
            assert interpolation in ('LINEAR', 'STEP')
            times = self.accessor(sampler['input'])[:,0]
            values = self.accessor(sampler['output'])
            at = int(np.searchsorted(times, time, side='right'))
            if at == 0:value = values[0]
            elif at == len(times):value = values[-1]
            elif interpolation == 'STEP':value = values[at-1]
            else:
                fraction = (time-times[at-1])/(times[at]-times[at-1])
                a, b = values[at-1].astype(float), values[at].astype(float)
                if channel['target']['path'] == 'rotation':
                    dot = float(np.dot(a,b))
                    if dot<0:b=-b;dot=-dot
                    if dot>.9995:value=a+(b-a)*fraction;value/=np.linalg.norm(value)
                    else:
                        angle=np.arccos(np.clip(dot,-1,1))
                        value=(np.sin((1-fraction)*angle)*a+np.sin(fraction*angle)*b)/np.sin(angle)
                else:value=a+(b-a)*fraction
            result.setdefault(channel['target']['node'],{})[channel['target']['path']] = value
        return result


def validate_glb(path, reference):
    glb = GLB(path);doc=glb.doc
    assert len(doc['meshes']) == 1 and len(doc['skins']) == 1
    mesh_node = next(index for index,node in enumerate(doc['nodes']) if 'mesh' in node)
    skin = doc['skins'][doc['nodes'][mesh_node]['skin']]
    joint_names = [doc['nodes'][joint]['name'] for joint in skin['joints']]
    assert set(joint_names) == set(reference['hierarchy']) and len(joint_names)==17
    assert doc['nodes'][skin['skeleton']]['name'] == 'Root'
    sword = skin['joints'][joint_names.index('Sword')]
    hand = skin['joints'][joint_names.index('Hand.R')]
    assert glb.parent[sword] == hand
    inverse = glb.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    globals_rest = glb.globals()
    bind_error = max(float(np.abs(np.linalg.inv(globals_rest[mesh_node]) @ globals_rest[joint] @ inverse[i]-np.eye(4)).max())
                     for i,joint in enumerate(skin['joints']))
    assert bind_error < 1e-5, bind_error
    positions=[];bones=[];bone_indices=[];triangles=[];offset=0
    for primitive in doc['meshes'][0]['primitives']:
        assert 'targets' not in primitive and primitive.get('mode',4)==4
        attrs=primitive['attributes'];pos=glb.accessor(attrs['POSITION'])
        weights=glb.accessor(attrs['WEIGHTS_0']);joint=glb.accessor(attrs['JOINTS_0'])
        assert np.all(np.count_nonzero(weights>1e-6,axis=1)==1)
        assert np.allclose(weights.sum(axis=1),1,atol=1e-6)
        active=weights.argmax(axis=1);chosen=joint[np.arange(len(pos)),active].astype(int)
        positions.extend(pos);bones.extend(joint_names[i] for i in chosen);bone_indices.extend(chosen)
        triangles.extend(glb.accessor(primitive['indices'])[:,0].reshape(-1,3)+offset)
        offset+=len(pos)
    positions=np.array(positions);bone_indices=np.array(bone_indices);triangles=np.array(triangles)
    assert len(triangles)==4072
    # Blender Z-up to glTF Y-up; compare in Blender world coordinates.
    axis=np.array([[1,0,0,0],[0,0,1,0],[0,-1,0,0],[0,0,0,1]],dtype=float)
    to_blender=np.linalg.inv(axis)
    homogeneous=np.column_stack((positions,np.ones(len(positions))))
    def skinned(globals_pose):
        matrices=np.array([globals_pose[j] @ inverse[i] for i,j in enumerate(skin['joints'])])
        return (np.einsum('nij,nj->ni',matrices[bone_indices],homogeneous) @ to_blender.T)[:,:3]
    rest=skinned(globals_rest);correspondence,position_error=nearest_correspondence(rest,bones,reference)
    edges=np.vstack((triangles[:,[0,1]],triangles[:,[1,2]],triangles[:,[2,0]]))
    lengths=np.linalg.norm(rest[edges[:,0]]-rest[edges[:,1]],axis=1)
    all_paths=Counter(channel['target']['path'] for animation in doc['animations'] for channel in animation['channels'])
    assert set(all_paths)<= {'rotation','translation'}
    results=[];max_rigid=0;max_sword=0
    for animation in doc['animations']:
        name=animation['name'];assert name in reference['poses']
        end=max(float(glb.accessor(s['input'])[:,0].max()) for s in animation['samplers'])
        assert abs(end-(len(reference['poses'][name])-1)/30)<1e-5
        error=0
        for frame,expected in enumerate(reference['poses'][name]):
            globals_pose=glb.globals(glb.animation_transforms(animation,frame/30))
            current=skinned(globals_pose)
            error=max(error,float(np.linalg.norm(current-expected[correspondence],axis=1).max()))
            current_lengths=np.linalg.norm(current[edges[:,0]]-current[edges[:,1]],axis=1)
            max_rigid=max(max_rigid,float(np.abs(current_lengths-lengths).max()))
            relative=np.linalg.inv(globals_pose[hand]) @ globals_pose[sword]
            rest_relative=np.linalg.inv(globals_rest[hand]) @ globals_rest[sword]
            max_sword=max(max_sword,float(np.abs(relative-rest_relative).max()))
        assert error<2e-5,(name,error)
        results.append({'name':name,'seconds':end,'frames_checked':len(reference['poses'][name]),'max_source_pose_error':error})
    assert len(results)==3 and max_rigid<1e-5 and max_sword<1e-5
    return {'format':'GLB','mesh_count':1,'skin_count':1,'bone_count':17,
            'scale_animation_channels':0,'weight_animation_channels':0,
            'channel_types':dict(all_paths),'inverse_bind_identity_error':bind_error,
            'assembled_position_error':position_error,'rigid_weights':True,
            'max_edge_length_change':max_rigid,'max_sword_hand_relative_error':max_sword,
            'animations':results}
