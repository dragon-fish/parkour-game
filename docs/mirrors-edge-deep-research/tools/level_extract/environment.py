"""A level's own look: sky colour, sun direction and default post process, read
from the WorldInfo of its persistent package.

The original's world is lit by baked lightmaps; its DirectionalLights light
only characters (every LightingChannel off). Where the sun stands is recorded
instead by the Mirror's Edge haze settings (HazeSunLocation), which is what the
builder points its sun along.

Post process in Mirror's Edge is its own: Scene_MidTones and per-channel tone
curves (Curves.ControlPointsR/G/B, and A applied to all three), as (x, y)
pairs. Curves.Ms/Bs are recorded as read; their meaning is not known.
"""
import struct

from common import UU, outer_class
import matinee as mt


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
