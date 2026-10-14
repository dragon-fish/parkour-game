"""A level's own look: sky colour, sun direction and default post process, read
from the WorldInfo of its persistent package.

The original's world is lit by baked lightmaps; its DirectionalLights light
only characters (every LightingChannel off). Where the sun stands is recorded
instead by the Mirror's Edge haze settings (HazeSunLocation), which is what the
builder points its sun along.

Post process in Mirror's Edge is its own. `tone_map` is what its tone mapping
pass is fed, resolved as the original resolves it ([ME:CONFIRMED
_local/me-re/findings/TM1.md]): the settings' Scene_* values and exposure
limits over the PostProcessSettings struct defaults, the PC modifier added on,
and the curves as their stored 16 linear segments Curves.Ms/Bs -- the runtime
never reads ControlPoints. PostProcessVolumes replace the world's settings
inside their brush (`post_process_volumes`).
"""
import struct

from common import UU, ExtractError, actor_scale, godot_basis, outer_class, point, ref_export
import matinee as mt

# [ME:CONFIRMED Engine/PostProcessVolume.uc] the PostProcessSettings struct's
# defaults: what a settings block that stores nothing of a field runs with.
TONE_DEFAULTS = {
    'Scene_Shadows': (0.0, 0.0, 0.0), 'Scene_HighLights': (1.0, 1.0, 1.0), 'Scene_MidTones': (1.0, 1.0, 1.0),
    'Scene_Desaturation': 0.0, 'Scene_ExposureManual': 1.0, 'Scene_ExposureSpeedUp': 3.5,
    'Scene_ExposureSpeedDown': 4.5, 'Scene_ExposureHigh': 1.65, 'Scene_ExposureLow': 0.85,
    'Scene_InterpolationDuration': 1.0,
}
# The fields a TdPostProcessModifier adds on; it holds 0 for each, and 1 for
# every Ms, unless it stores otherwise.
MODIFIED_FIELDS = ('Scene_Shadows', 'Scene_HighLights', 'Scene_MidTones', 'Scene_Desaturation',
                   'Scene_ExposureManual', 'Scene_ExposureSpeedUp', 'Scene_ExposureSpeedDown',
                   'Scene_ExposureHigh', 'Scene_ExposureLow')
CURVE_SEGMENTS = 16


def _decode(mr, value, depth=0):
    if isinstance(value, tuple) and value and value[0] == 'struct' and depth < 5:
        _ok, tags, _ = mr._chain(value[2], value[2] + value[3])
        return {t[0]: _decode(mr, mt._value(mr, t), depth + 1) for t in tags} if tags else None
    if isinstance(value, tuple) and value and value[0] == 'array':
        q, size = value[1], value[2]
        count = struct.unpack_from('<i', mr.d, q)[0]
        if count > 0 and 4 + count * 8 == size:
            # A curve's control points: plain (x, y) float pairs, no tags.
            return [list(struct.unpack_from('<2f', mr.d, q + 4 + k * 8)) for k in range(count)]
        return None
    return value


def _props(mr, idx):
    tags, _ = mr.chain_of(idx)
    return {t[0]: _decode(mr, mt._value(mr, t)) for t in tags}


def post_process(settings):
    """The parts of a PostProcessSettings struct the builder reproduces."""
    settings = settings or {}
    curves = settings.get('Curves') or {}
    out = {}
    if settings.get('Scene_MidTones'):
        out['midtones'] = [round(c, 4) for c in settings['Scene_MidTones']]
    for key in ('Scene_ExposureHigh', 'Scene_ExposureLow', 'Scene_ExposureManual',
                'Scene_InterpolationDuration'):
        if key in settings:
            out[key[len('Scene_'):].lower()] = round(float(settings[key]), 4)
    for channel in 'RGBA':
        points = curves.get('ControlPoints' + channel)
        if points and not (len(points) == 2 and points == [[0.0, 0.0], [1.0, 1.0]]):
            out['curve_' + channel.lower()] = [[round(x, 4), round(y, 4)] for x, y in points]
    return out


def _tags(mr, value):
    """The tags inside a struct value, or [] for anything else."""
    if not (isinstance(value, tuple) and value and value[0] == 'struct'):
        return []
    _ok, tags, _ = mr._chain(value[2], value[2] + value[3])
    return tags


def settings_block(mr, value):
    """What a PostProcessSettings (or TdPostProcessModifier) struct STORES:
    {'fields': {name: value}, 'ms': {i: (r, g, b)}, 'bs': {i: (r, g, b)}}.
    Ms and Bs are static arrays, one tag per stored element."""
    out = {'fields': {}, 'ms': {}, 'bs': {}}
    for tag in _tags(mr, value):
        if tag[0] == 'Curves':
            for element in _tags(mr, mt._value(mr, tag)):
                if element[0] in ('Ms', 'Bs'):
                    out[element[0].lower()][element[5]] = tuple(float(c) for c in mt._value(mr, element))
        elif tag[0] in TONE_DEFAULTS or tag[0] == 'bEnableSceneEffect':
            v = mt._value(mr, tag)
            out['fields'][tag[0]] = tuple(float(c) for c in v) if isinstance(v, tuple) else v
    return out


def _add(a, b):
    return tuple(x + y for x, y in zip(a, b)) if isinstance(a, tuple) else a + b


def _is_zero(v):
    return all(c == 0.0 for c in v) if isinstance(v, tuple) else v == 0.0


def tone_map(settings, modifier, fallback_modifier=None, curve_modifier=None):
    """The tone mapping pass's settings, resolved.

    [ME:CONFIRMED TM1 0x00c0f820, 0x00e77870] every modified field is the
    setting plus the modifier's; inside a volume a modifier field left at 0
    takes the world's modifier instead (`fallback_modifier`). Ms = s.Ms +
    m.Ms - 1 and Bs = s.Bs + m.Bs, with `curve_modifier` (the volume's own only
    when it sets bOverrideSKUSpecificCurveModifier). [ME:CONFIRMED TM1
    0x012d0420] bEnableSceneEffect off makes the grading the identity.
    """
    fields = dict(TONE_DEFAULTS)
    fields.update({k: v for k, v in settings['fields'].items() if k in TONE_DEFAULTS})
    zero = {k: (0.0, 0.0, 0.0) if isinstance(TONE_DEFAULTS[k], tuple) else 0.0 for k in MODIFIED_FIELDS}
    for key in MODIFIED_FIELDS:
        m = modifier['fields'].get(key, zero[key])
        if fallback_modifier is not None and _is_zero(m):
            m = fallback_modifier['fields'].get(key, zero[key])
        fields[key] = _add(fields[key], m)
    curves = curve_modifier or modifier
    ms, bs = [], []
    for i in range(CURVE_SEGMENTS):
        ms.append([round(a + b - 1.0, 6) for a, b in zip(settings['ms'].get(i, (0.0, 0.0, 0.0)),
                                                         curves['ms'].get(i, (1.0, 1.0, 1.0)))])
        bs.append([round(a + b, 6) for a, b in zip(settings['bs'].get(i, (0.0, 0.0, 0.0)),
                                                   curves['bs'].get(i, (0.0, 0.0, 0.0)))])
    if settings['fields'].get('bEnableSceneEffect', True) is False:
        fields.update({'Scene_Shadows': (0.0, 0.0, 0.0), 'Scene_HighLights': (1.0, 1.0, 1.0),
                       'Scene_MidTones': (1.0, 1.0, 1.0), 'Scene_Desaturation': 0.0})

    def r(v):
        return [round(c, 6) for c in v] if isinstance(v, tuple) else round(float(v), 6)
    return {'shadows': r(fields['Scene_Shadows']), 'highlights': r(fields['Scene_HighLights']),
            'midtones': r(fields['Scene_MidTones']), 'desaturation': r(fields['Scene_Desaturation']),
            'exposure_manual': r(fields['Scene_ExposureManual']),
            'exposure_speed_up': r(fields['Scene_ExposureSpeedUp']),
            'exposure_speed_down': r(fields['Scene_ExposureSpeedDown']),
            'exposure_high': r(fields['Scene_ExposureHigh']), 'exposure_low': r(fields['Scene_ExposureLow']),
            'interpolation_s': r(fields['Scene_InterpolationDuration']),
            'curve_m': ms, 'curve_b': bs}


def _world_settings(mr, idx):
    tags, _ = mr.chain_of(idx)
    by_name = {t[0]: mt._value(mr, t) for t in tags}
    return (settings_block(mr, by_name.get('DefaultPostProcessSettings')),
            settings_block(mr, by_name.get('DefaultPostProcessSettingsModifierPC')))


def post_process_volumes(packages, mr, world_modifier):
    """Every PostProcessVolume placed in this package: where it is, its
    priority, and the tone mapping inside it. Each hull is carried as its
    outward face planes [nx, ny, nz, d] in world space, a point being inside
    when n . p <= d for every one."""
    import annotations
    import packages as pk
    pkg = mr.pkg
    out = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'PostProcessVolume' or outer_class(pkg, e) != 'Level':
            continue
        props, _ = pk.resolved_props(packages, mr, i)
        tags, _ = mr.chain_of(i)
        by_name = {t[0]: mt._value(mr, t) for t in tags}
        settings = settings_block(mr, by_name.get('Settings'))
        modifier = settings_block(mr, by_name.get('PostProcessSettingsModifierPC'))
        curves = modifier if props.get('bOverrideSKUSpecificCurveModifier') else world_modifier
        volume = {'name': e['name'], 'package': mr.label, 'position': point(props.get('Location') or (0, 0, 0)),
                  'basis': godot_basis(props.get('Rotation') or (0, 0, 0), actor_scale(props))}
        component = ref_export(props.get('BrushComponent'))
        volume['hull'] = [h for h in (annotations.inherited_hulls(packages, mr, component) if component else [])
                          if annotations.built(h)]
        annotations.place_brush(props, volume, '%s.%s' % (mr.label, e['name']))
        planes = [_planes(volume, h) for h in volume.pop('hull')]
        if not planes:
            raise ExtractError('%s.%s: a post process volume with no brush' % (mr.label, e['name']))
        out.append({'name': e['name'], 'package': mr.label, 'priority': float(props.get('Priority', 0.0)),
                    'enabled': props.get('bEnabled', True) is not False, 'planes': planes,
                    'tone_map': tone_map(settings, modifier, world_modifier, curves)})
    return out


def _planes(volume, hull):
    """Outward planes of one convex hull, placed."""
    basis, origin = volume['basis'], volume['position']
    world = [[origin[k] + sum(basis[c][k] * v[c] for c in range(3)) for k in range(3)] for v in hull['vertices']]
    centre = [sum(p[k] for p in world) / len(world) for k in range(3)]
    t = hull['triangles']
    planes = []
    for a, b, c in zip(t[0::3], t[1::3], t[2::3]):
        u = [world[b][k] - world[a][k] for k in range(3)]
        w = [world[c][k] - world[a][k] for k in range(3)]
        n = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]]
        length = sum(x * x for x in n) ** 0.5
        if length < 1e-9:
            continue
        n = [x / length for x in n]
        if sum(n[k] * (world[a][k] - centre[k]) for k in range(3)) < 0.0:
            n = [-x for x in n]
        planes.append([round(n[0], 6), round(n[1], 6), round(n[2], 6),
                       round(sum(n[k] * world[a][k] for k in range(3)), 5)])
    return planes


def haze(settings):
    """The Mirror's Edge haze: a warm tint laid over distance, thickening by
    (distance / divider) ** curve, scaled by the multiplier. Distances in
    metres. Only the fields the builder reproduces."""
    out = {}
    color = settings.get('HazeColor')
    if isinstance(color, (list, tuple)) and len(color) >= 3:
        out['color'] = [round(float(c), 4) for c in color[:3]]
    if 'HazeDistanceDivider' in settings:
        out['distance_m'] = round(float(settings['HazeDistanceDivider']) / UU, 2)
    if 'HazeDistanceCurve' in settings:
        out['distance_curve'] = round(float(settings['HazeDistanceCurve']), 4)
    if 'HazeMultiplier' in settings:
        out['multiplier'] = round(float(settings['HazeMultiplier']), 4)
    if settings.get('HazeEnabled') is False:
        out['enabled'] = False
    return out


def collect(mr):
    """The look recorded on this package's WorldInfo, or None."""
    pkg = mr.pkg
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'WorldInfo' or outer_class(pkg, e) != 'Level':
            continue
        props = _props(mr, i)
        settings = props.get('DefaultPostProcessSettings') or {}
        out = {'package': mr.label, 'post_process': post_process(settings), 'haze': haze(settings)}
        world, modifier = _world_settings(mr, i)
        out['tone_map'] = tone_map(world, modifier)
        out['_modifier'] = modifier
        sky = props.get('SkyColor')
        if isinstance(sky, tuple) and len(sky) == 3:
            out['sky_color'] = [round(c, 4) for c in sky]
        sun = settings.get('HazeSunLocation')
        if isinstance(sun, (list, tuple)) and len(sun) == 3 and any(sun):
            # UE (x, y, z) -> Godot (x, z, y), as a unit vector toward the sun.
            length = sum(c * c for c in sun) ** 0.5
            out['sun_direction'] = [round(sun[0] / length, 5), round(sun[2] / length, 5), round(sun[1] / length, 5)]
        return out
    return None


def baked_sun(mr):
    """The DirectionalLight the world was baked with, or None.

    Beast reads its direction, colour and brightness off the actor's Baker*
    fields (bUseBakerColorAndBrightness); the component's own Brightness and
    LightingChannels belong to the dynamic light that only characters see.
    Measured in the tutorial and Stormdrain it stands within 7 degrees of
    HazeSunLocation, which the haze is drawn around; the light is the one the
    shadows were baked from, so it wins.
    """
    from common import godot_basis, ref_export
    pkg = mr.pkg
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'DirectionalLight' or outer_class(pkg, e) != 'Level':
            continue
        props, _ = mr.props_inherited(i)
        if not props or not props.get('bUseBakerColorAndBrightness'):
            continue
        component_idx = ref_export(props.get('LightComponent'))
        if component_idx and _props(mr, component_idx).get('bEnabled') is False:
            continue
        # A UE light shines along its +X; the basis columns are Godot axes.
        forward = godot_basis(props.get('Rotation') or (0, 0, 0), (1.0, 1.0, 1.0))[0]
        color = props.get('BakerColor')
        return {
            'package': mr.label, 'name': e['name'],
            'direction': [round(-c, 5) for c in forward],
            'color': [round(c, 4) for c in color[1:4]] if isinstance(color, tuple) and color and color[0] == 'color' else [1.0, 1.0, 1.0],
            'brightness': round(float(props.get('BakerBrightness', 1.0)), 4),
        }
    return None


# [ME:CONFIRMED MirrorsEdge.exe 0xff2810, 0xff1490, 0xd321a0] a pawn's light
# environment sees a light only through its CompositeDynamic channel: the
# pawn's meshes store no LightingChannels and are initialised to Dynamic alone,
# and a light's CompositeDynamic is read as Dynamic. What it then adds to the
# SHADOW environment (the one its modulated shadow is cast from) is every such
# light whose bCastCompositeShadow is set -- by default the directional and
# sky lights, never a point or spot. (_local/me-re findings on the DLE.)
CHARACTER_SHADOW_CLASSES = ('DirectionalLight', 'SkyLight')


def _linear(color):
    """[ME:CONFIRMED 0x115e240] a light's FColor as the light environment reads
    it: (byte / 255) ^ 2.2, a plain power, not the sRGB curve."""
    if isinstance(color, tuple) and color and color[0] == 'color':
        return [c ** 2.2 for c in color[1:4]]
    return [1.0, 1.0, 1.0]


def character_shadow_light(cls, component, tagged, rotation=(0, 0, 0)):
    """One light's part in a pawn's shadow environment, or None.

    `component` is the light component's properties with its defaults,
    `tagged` only those it stores (where a channel switched off shows).
    [ME:CONFIRMED 0xed9850, 0xff2310] a directional light adds Brightness *
    LightColor from where it shines, a sky light Brightness * LightColor from
    above and LowerBrightness * LowerColor from below; the Baker* fields are
    not read. A directional light that casts static shadows is traced from
    the pawn: blocked, it adds nothing."""
    if cls not in CHARACTER_SHADOW_CLASSES or tagged.get('bEnabled') is False:
        return None
    channels = tagged.get('LightingChannels') if isinstance(tagged.get('LightingChannels'), dict) else {}
    if channels.get('CompositeDynamic') is False or tagged.get('bCastCompositeShadow') is False:
        return None
    brightness = float(component.get('Brightness', 1.0))
    color = _linear(component.get('LightColor'))
    if cls == 'SkyLight':
        lower = float(component.get('LowerBrightness', 0.0))
        lower_color = _linear(component.get('LowerColor'))
        return {'kind': 'sky', 'upper': [round(brightness * c, 5) for c in color],
                'lower': [round(lower * c, 5) for c in lower_color]}
    forward = godot_basis(rotation or (0, 0, 0), (1.0, 1.0, 1.0))[0]
    return {'kind': 'sun', 'direction': [round(-c, 5) for c in forward],
            'intensity': [round(brightness * c, 5) for c in color],
            'traced': component.get('CastShadows', True) is not False and component.get('CastStaticShadows', True) is not False}


def character_shadow_lights(mr):
    """Every light of this package a pawn's shadow environment takes in."""
    pkg = mr.pkg
    out = []
    for i, e in enumerate(pkg.exports, 1):
        cls = pkg.class_of(e)
        if cls not in CHARACTER_SHADOW_CLASSES or outer_class(pkg, e) != 'Level':
            continue
        props, _ = mr.props_inherited(i)
        component_idx = ref_export((props or {}).get('LightComponent'))
        if not component_idx:
            continue
        component = mr.props_inherited(component_idx)[0] or {}
        light = character_shadow_light(cls, component, _props(mr, component_idx), props.get('Rotation'))
        if light:
            light.update({'package': mr.label, 'name': e['name']})
            out.append(light)
    return out
