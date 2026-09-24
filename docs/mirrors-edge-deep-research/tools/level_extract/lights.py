"""Light actors and the level's compiled BSP."""
import struct

from common import ExtractError, UU, actor_scale, godot_basis, outer_class, point, ref_export, to_godot
import environment

# PointLightMovable: [ME:CONFIRMED] the Subway's train-ride tunnel is lit by six
# of these and by nothing else, each hard-attached to one of the four rolling
# tunnel pieces. (Its 124 TdAreaLights are in Subway_TrainRide_Render, a bake
# scene 50 m to the side that the game never streams.) Unread, the ride was
# run in the dark.
LIGHT_CLASSES = ('PointLight', 'PointLightMovable', 'SpotLight', 'SpotLightMovable', 'TdAreaLight')


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
        # What it rides, as a placement says it: the builder makes it a target
        # of whatever sequence moves that actor.
        base_idx = ref_export(props.get('Base'))
        base = '%s.%s' % (mr.label, pkg.exports[base_idx - 1]['name']) if base_idx else None
        lights.append({
            'name': e['name'], 'class': cls, 'package': mr.label, 'tag': props.get('Tag'), 'base': base,
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


BSP_PLANE_SLACK_UU = 0.5
# FBspSurf: material, flags, base point, normal, the two texture vectors,
# brush poly, actor, plane, shadow map scale, lighting channels.
BSP_SURF_SIZE = 56
# Units a BSP texture spans per tile, the original's own constant. Read off
# the result: at this scale an office wall's plaster tiles as it does in the
# game, and the Plaza's paving slabs come out slab-sized.
BSP_TEXEL_SCALE = 128.0


def collect_bsp(mr):
    """Polygons of the level's compiled world BSP, each with the material its
    surface names and the texture coordinates that surface maps. Brush actors
    are not triangulated separately: doing so would fill the CSG holes
    (doorways).

    A node names a surface (FBspNode.iSurf at +20) and the surface carries the
    material plus the base point and two vectors that project a point into UV,
    exactly as the original maps a texture onto a wall. Skipped, every
    interior wall, ceiling and air duct in the game drew one flat grey.
    """
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

        vectors = [struct.unpack('<3f', raw) for raw in bulk(12)]
        points = [struct.unpack('<3f', raw) for raw in bulk(12)]
        nodes = bulk(64)
        _owner, surface_count = struct.unpack_from('<2i', data, cursor)
        cursor += 8
        surfs = [data[cursor + i * BSP_SURF_SIZE:cursor + (i + 1) * BSP_SURF_SIZE] for i in range(surface_count)]
        cursor += surface_count * BSP_SURF_SIZE
        verts = bulk(24)
        for node in nodes:
            plane = struct.unpack_from('<4f', node)
            pool = struct.unpack_from('<i', node, 16)[0]
            surf_index = struct.unpack_from('<i', node, 20)[0]
            count = node[54]
            if count < 3:
                continue
            if not 0 <= surf_index < len(surfs):
                raise ExtractError('%s: BSP node names surface %d of %d'
                                   % (mr.label, surf_index, len(surfs)))
            surf = surfs[surf_index]
            material_ref, base_index, u_index, v_index = (
                struct.unpack_from('<i', surf, offset)[0] for offset in (0, 8, 16, 20))
            base = points[base_index]
            texture_u, texture_v = vectors[u_index], vectors[v_index]
            polygon, uvs = [], []
            for vertex in verts[pool:pool + count]:
                p = points[struct.unpack_from('<i', vertex)[0]]
                # A parse error puts a vertex metres off; float rounding at
                # Mall's coordinates leaves one 0.19 uu off (2 mm).
                if abs(sum(plane[k] * p[k] for k in range(3)) - plane[3]) > BSP_PLANE_SLACK_UU:
                    raise ExtractError('%s: BSP vertex off its plane' % mr.label)
                polygon.append([round(c, 4) for c in to_godot(*p)])
                offset = [p[k] - base[k] for k in range(3)]
                uvs.append([round(sum(offset[k] * texture_u[k] for k in range(3)) / BSP_TEXEL_SCALE, 5),
                            round(sum(offset[k] * texture_v[k] for k in range(3)) / BSP_TEXEL_SCALE, 5)])
            faces.append({'vertices': polygon, 'normal': [plane[0], plane[2], plane[1]],
                          'uvs': uvs, 'material_ref': material_ref})
    return faces
