"""Light actors and the level's compiled BSP."""
import struct

from common import ExtractError, UU, actor_scale, godot_basis, outer_class, point, ref_export, to_godot
import environment

LIGHT_CLASSES = ('PointLight', 'SpotLight', 'SpotLightMovable', 'TdAreaLight')


def _color(value, default=(1.0, 1.0, 1.0)):
    return list(value[1:4]) if isinstance(value, tuple) and value and value[0] == 'color' else list(default)


def install_color_decoding(mr):
    """props() leaves FColor as raw; decode it (stored B, G, R, A)."""
    original = mr._value

    def value(typ, extra, q, sz):
        if typ == 'StructProperty' and extra == 'Color' and sz == 4:
            b, g, r, _a = mr.d[q:q + 4]
            return ('color', r / 255.0, g / 255.0, b / 255.0)
        return original(typ, extra, q, sz)
    mr._value = value


def collect_lights(mr):
    """The original is baked with Beast: when bUseBakerColorAndBrightness is
    set, the effective brightness and colour live on the actor's Baker*
    fields and the component's Brightness is usually 0."""
    pkg = mr.pkg
    lights = []
    for i, e in enumerate(pkg.exports, 1):
        cls = pkg.class_of(e)
        if cls not in LIGHT_CLASSES or outer_class(pkg, e) != 'Level':
            continue
        props, _ = mr.props_inherited(i)
        if not props or 'Location' not in props:
            continue
        component_idx = ref_export(props.get('LightComponent'))
        component = (mr.props_inherited(component_idx)[0] or {}) if component_idx else {}
        baker = props.get('bUseBakerColorAndBrightness', False)
        tagged = environment._props(mr, component_idx) if component_idx else {}
        channels = tagged.get('LightingChannels') if isinstance(tagged.get('LightingChannels'), dict) else {}
        # Switched off in the original until its Kismet turns it on.
        if tagged.get('bEnabled') is False:
            continue
        lights.append({
            'name': e['name'], 'class': cls, 'package': mr.label, 'tag': props.get('Tag'),
            'position': point(props['Location']),
            'basis': godot_basis(props.get('Rotation') or (0, 0, 0), (1.0, 1.0, 1.0)),
            'brightness': props.get('BakerBrightness', 1.0) if baker else component.get('Brightness', 1.0),
            'color': _color(props.get('BakerColor')) if baker else _color(component.get('LightColor')),
            'radius_m': component.get('Radius', 1024.0) / UU,
            'outer_cone_deg': component.get('OuterConeAngle', 44.0),
            'inner_cone_deg': component.get('InnerConeAngle', 0.0),
            # Lights only what moves: kept off the world's BSP and static
            # meshes by its LightingChannels, there to light the character or
            # a car. The tutorial hangs one of brightness 8 over a crash mat
            # and one of 5 outside the tutorial's door; the Prologue's
            # "CarLights" are 10. The channels decide, not bForceDynamicLight:
            # the door lamp has no such flag and, built as a world light at
            # the lamp scale, whited out the wall round the door.
            'character_only': channels.get('BSP') is False and channels.get('Static') is False
                              and channels.get('Dynamic') is not False,
        })
    return lights


def collect_bsp(mr):
    """Polygons of the level's compiled world BSP. Brush actors are not
    triangulated separately: doing so would fill the CSG holes (doorways)."""
    pkg, data = mr.pkg, mr.d
    faces = []
    for index, model in enumerate(pkg.exports, 1):
        if pkg.class_of(model) != 'Model' or outer_class(pkg, model) != 'Level':
            continue
        _, native = mr.props(index)
        cursor = native + 28
        end = model['offset'] + model['size']

        def bulk(expected):
            nonlocal cursor
            stride, count = struct.unpack_from('<2i', data, cursor)
            if stride != expected or not 0 <= count < 1000000:
                raise ExtractError('%s.%s: BSP bulk %d x %d' % (mr.label, model['name'], stride, count))
            cursor += 8
            start = cursor
            cursor += stride * count
            if cursor > end:
                raise ExtractError('%s.%s: BSP overruns export' % (mr.label, model['name']))
            return [data[start + i * stride:start + (i + 1) * stride] for i in range(count)]

        bulk(12)                                            # vectors
        points = [struct.unpack('<3f', raw) for raw in bulk(12)]
        nodes = bulk(64)
        _owner, surface_count = struct.unpack_from('<2i', data, cursor)
        cursor += 8 + surface_count * 56
        verts = bulk(24)
        for node in nodes:
            plane = struct.unpack_from('<4f', node)
            pool = struct.unpack_from('<i', node, 16)[0]
            count = node[54]
            if count < 3:
                continue
            polygon = []
            for vertex in verts[pool:pool + count]:
                p = points[struct.unpack_from('<i', vertex)[0]]
                if abs(sum(plane[k] * p[k] for k in range(3)) - plane[3]) > 0.05:
                    raise ExtractError('%s: BSP vertex off its plane' % mr.label)
                polygon.append([round(c, 4) for c in to_godot(*p)])
            faces.append({'vertices': polygon, 'normal': [plane[0], plane[2], plane[1]]})
    return faces
