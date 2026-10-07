"""Audit/remove only redundant, constant FBX scale curves. Run in Blender Python."""
from collections import Counter
import numpy as np
from io_scene_fbx import parse_fbx, encode_bin


def section(root, name):
    return next(element for element in root.elems if element.id == name)


def encoded_copy(element):
    result = encode_bin.FBXElem(element.id)
    methods = {
        ord('Y'): 'add_int16', ord('C'): 'add_char', ord('I'): 'add_int32',
        ord('L'): 'add_int64', ord('F'): 'add_float32', ord('D'): 'add_float64',
        ord('R'): 'add_bytes', ord('S'): 'add_string', ord('B'): 'add_bool',
        ord('Z'): 'add_int8', ord('f'): 'add_float32_array',
        ord('d'): 'add_float64_array', ord('i'): 'add_int32_array',
        ord('l'): 'add_int64_array', ord('b'): 'add_bool_array',
        ord('c'): 'add_byte_array',
    }
    for kind, value in zip(element.props_type, element.props):
        if kind == ord('B'):
            assert value in (0, 1), (element.id, kind, type(value), repr(value))
            value = bool(value)
        getattr(result, methods[kind])(value)
    result.elems = [encoded_copy(child) for child in element.elems]
    return result


def remove_constant_scale(raw_path, output_path):
    root, version = parse_fbx.parse(str(raw_path))
    objects = section(root, b'Objects')
    connections = section(root, b'Connections')
    by_id = {obj.props[0]: obj for obj in objects.elems}
    remove = set()
    scale_nodes = 0
    for connection in connections.elems:
        if len(connection.props) != 4 or connection.props[3] != b'Lcl Scaling':
            continue
        node_id = connection.props[1]
        assert by_id[node_id].id == b'AnimationCurveNode'
        scale_nodes += 1
        for link in connections.elems:
            if len(link.props) < 3 or link.props[2] != node_id:
                continue
            curve = by_id.get(link.props[1])
            if curve is None or curve.id != b'AnimationCurve':
                continue
            values = next(e.props[0] for e in curve.elems if e.id == b'KeyValueFloat')
            # Never discard a genuine scale animation, or conceal a non-unit bind scale.
            assert np.allclose(values, 1.0, atol=2e-6, rtol=0), (node_id, list(values))
            remove.add(curve.props[0])
        remove.add(node_id)
    objects.elems[:] = [obj for obj in objects.elems if obj.props[0] not in remove]
    connections.elems[:] = [c for c in connections.elems
                            if c.props[1] not in remove and c.props[2] not in remove]
    for obj in objects.elems:
        for child in obj.elems:
            if child.id == b'Properties70':
                for prop in child.elems:
                    if prop.id == b'P' and prop.props[0] == b'Lcl Scaling':
                        prop.props[3] = prop.props[3].replace(b'+', b'')
    # Keep FBX object counts consistent with the cleaned object table.
    counts = Counter(obj.id for obj in objects.elems)
    definitions = section(root, b'Definitions')
    for definition in definitions.elems:
        if definition.id == b'Count':
            definition.props[0] = len(objects.elems)
        elif definition.id == b'ObjectType':
            for child in definition.elems:
                if child.id == b'Count':
                    child.props[0] = counts[definition.props[0]]
    encode_bin.write(str(output_path), encoded_copy(root), version)
    return {'removed_constant_scale_curve_nodes': scale_nodes,
            'removed_curve_objects': len(remove)}
