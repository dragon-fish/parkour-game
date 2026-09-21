"""Where an AnimSequence carries a skinned piece of SCENERY, as move-track keys.

[ME:CONFIRMED] the helicopters the Edge and the Scraper end on do not fly on a
move track. Each is a SkeletalMeshActor pinned where it stands -- the Edge's at
the world's origin -- by a move track of ONE key, and flown by an
InterpTrackAnimControl: `sp01_helicopter02_start`, `cs16_helicopter`. The
flight is the animation of two bones, the root and the VH_Main the body is
skinned to. Read as a move track, the way every mover here is, the helicopter
never left the origin.

So the animation is read for exactly that: the path of the one bone the mesh
is bound to, sampled into the keys a move track would have had. The rest of
the skeleton -- the rotors -- stays in its reference pose.

The compressed data, package version 536, walked on AS_SP01_Helicopter01:

    CompressedTrackOffsets      per track: translation offset, key count,
                                rotation offset, key count -- into the stream
    native: CompressedByteStream    count, bytes
        translation keys        3 floats each (ACF_None)
        rotation, ONE key       3 floats, W rebuilt (ACF_Float96NoW whatever
                                the sequence's format says)
        rotation, more          24 bytes of mins and ranges that only the
                                interval formats read, then 3 WORDs each:
                                (u - 32767) / 32767, W rebuilt (ACF_Fixed48NoW)

Keys are evenly spaced over SequenceLength. Tracks are in the order of the
AnimSet's TrackBoneNames.
"""
import math
import struct

from common import ExtractError, UU
from matinee import _int_array, _props, _struct_array, _value

ROTATION_RANGE_BYTES = 24
# Seconds between the keys written out. The flight is smooth and the builder's
# Matinee goes linearly between keys; ten a second is under a centimetre off.
SAMPLE_STEP_S = 0.1
SUPPORTED_ROTATION = 'ACF_Fixed48NoW'


# ---- 3x3 matrices as three COLUMNS, quaternions as (x, y, z, w), UE space

def _from_quat(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y)],
            [2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x)],
            [2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)]]


def _from_rotator(pitch, yaw, roll):
    """UE3's FRotationMatrix, angles in its 65536-to-a-turn units."""
    p, y, r = (a * math.pi / 32768.0 for a in (pitch, yaw, roll))
    cp, sp, cy, sy, cr, sr = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
    return [[cp * cy, cp * sy, sp],
            [sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp],
            [-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp]]


def _apply(m, v):
    return [sum(m[c][k] * v[c] for c in range(3)) for k in range(3)]


def _mul(a, b):
    return [_apply(a, column) for column in b]


def _transpose(m):
    return [[m[r][c] for r in range(3)] for c in range(3)]


def _euler_degrees(m):
    """(roll, pitch, yaw) as a Matinee euler key has them, of rotation `m`."""
    x, y, z = m
    pitch = math.atan2(x[2], math.hypot(x[0], x[1]))
    yaw = math.atan2(x[1], x[0])
    roll = math.atan2(-y[2], z[2])
    return [math.degrees(roll), math.degrees(pitch), math.degrees(yaw)]


# ---- the data

def _rebuild_w(x, y, z):
    return (x, y, z, math.sqrt(max(0.0, 1.0 - x * x - y * y - z * z)))


def bone_tracks(mr, sequence_idx):
    """({bone name: (positions, quaternions)}, length in seconds)."""
    pkg, d = mr.pkg, mr.d
    export = pkg.exports[sequence_idx - 1]
    where = '%s.%s' % (mr.label, export['name'])
    chain, native = mr.chain_of(sequence_idx, widest=True)
    props = {tag[0]: tag for tag in chain}
    if 'CompressedTrackOffsets' not in props or native is None:
        raise ExtractError('%s: no compressed tracks' % where)
    rotation = _value(mr, props['RotationCompressionFormat']) if 'RotationCompressionFormat' in props else 'ACF_None'
    if rotation != SUPPORTED_ROTATION or 'TranslationCompressionFormat' in props:
        raise ExtractError('%s: compression %s is not read' % (where, rotation))
    length = float(_value(mr, props['SequenceLength']))
    at = props['CompressedTrackOffsets'][3]
    offsets = struct.unpack_from('<%di' % struct.unpack_from('<i', d, at)[0], d, at + 4)
    size = struct.unpack_from('<i', d, native)[0]
    stream = native + 4
    if size <= 0 or stream + size > export['offset'] + export['size']:
        raise ExtractError('%s: compressed stream of %d bytes' % (where, size))

    names = []
    for tag in mr.chain_of(export['outer_idx'], widest=True)[0]:
        if tag[0] == 'TrackBoneNames':
            names = [pkg.name(struct.unpack_from('<i', d, tag[3] + 4 + 8 * k)[0])
                     for k in range(struct.unpack_from('<i', d, tag[3])[0])]
    if len(names) * 4 != len(offsets):
        raise ExtractError('%s: %d tracks for %d bones' % (where, len(offsets) // 4, len(names)))

    tracks = {}
    for k, bone in enumerate(names):
        t_at, t_keys, r_at, r_keys = offsets[4 * k:4 * k + 4]
        positions = [struct.unpack_from('<3f', d, stream + t_at + 12 * i) for i in range(t_keys)]
        if r_keys == 1:
            quats = [_rebuild_w(*struct.unpack_from('<3f', d, stream + r_at))]
        else:
            quats = []
            for i in range(r_keys):
                u = struct.unpack_from('<3H', d, stream + r_at + ROTATION_RANGE_BYTES + 6 * i)
                quats.append(_rebuild_w(*[(c - 32767) / 32767.0 for c in u]))
        # [ME:INFERRED] UE3's AnimSequence hands every bone but the root back
        # with W negated -- its reference poses are stored the other way
        # round. Here it only decides which way a hovering body sways.
        if k > 0:
            quats = [(x, y, z, -w) for x, y, z, w in quats]
        tracks[bone] = (positions, quats)
    return tracks, length


def _key_at(keys, fraction):
    """Linear between evenly spaced keys; normalised lerp for a rotation."""
    if len(keys) == 1:
        return list(keys[0])
    place = min(max(fraction, 0.0), 1.0) * (len(keys) - 1)
    i = min(int(place), len(keys) - 2)
    f = place - i
    a, b = keys[i], keys[i + 1]
    if len(a) == 4 and sum(p * q for p, q in zip(a, b)) < 0.0:
        b = [-c for c in b]
    out = [p + (q - p) * f for p, q in zip(a, b)]
    if len(a) == 4:
        norm = math.sqrt(sum(c * c for c in out)) or 1.0
        out = [c / norm for c in out]
    return out


def body_pose(skeleton, tracks, fraction):
    """(rotation, translation) carrying the mesh from its reference pose to
    where the bone it is bound to stands `fraction` of the way through, in the
    ACTOR's frame (the mesh's RotOrigin applied), UE units."""
    chain = []
    bone = skeleton['bound_to']
    while bone >= 0:
        chain.append(bone)
        bone = skeleton['bones'][bone]['parent'] if skeleton['bones'][bone]['parent'] != bone else -1
    rotation, translation = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]], [0.0, 0.0, 0.0]
    reference = [0.0, 0.0, 0.0]
    for index in reversed(chain):
        entry = skeleton['bones'][index]
        positions, quats = tracks.get(entry['name'], ([entry['position']], [entry['rotation']]))
        local_t = _key_at(positions, fraction)
        local_r = _from_quat(_key_at(quats, fraction))
        translation = [translation[k] + _apply(rotation, local_t)[k] for k in range(3)]
        rotation = _mul(rotation, local_r)
        # Every reference rotation of these skeletons is the identity, so the
        # reference pose of the chain is the sum of its offsets.
        reference = [reference[k] + entry['position'][k] for k in range(3)]
    moved = [translation[k] - _apply(rotation, reference)[k] for k in range(3)]
    turn = _from_rotator(*skeleton['rot_origin'])
    return _mul(_mul(turn, rotation), _transpose(turn)), _apply(turn, moved)


def _sequences(mr, group_idx):
    """{sequence name: export index} over the group's GroupAnimSets."""
    out = {}
    for anim_set in _int_array(mr, _props(mr, group_idx).get('GroupAnimSets')):
        if anim_set <= 0:
            continue
        for sequence in _int_array(mr, _props(mr, anim_set).get('Sequences')):
            if sequence > 0:
                chain = {tag[0]: tag for tag in mr.chain_of(sequence, widest=True)[0]}
                if 'SequenceName' in chain:
                    out[str(_value(mr, chain['SequenceName']))] = sequence
    return out


def flight_keys(mr, group_idx, track_idx, skeleton, length, location, rotation):
    """Move-track keys, in matinee._keys()'s shape, of what the AnimControl
    track `track_idx` plays on a body with `skeleton`, over a sequence
    `length` seconds long, for an actor standing at `location` turned
    `rotation` (UE units).

    ABSOLUTE keys, a world track's. A relative track is measured from where
    its actor stands when the sequence STARTS, and these come in threes -- fly
    in, hover, fly out, one sequence each, every one of them animated from the
    same standing place: relative, the second would begin where the first
    left off and fly the whole way again from there."""
    known = _sequences(mr, group_idx)
    plays = []
    # The WIDEST chain: a track's own properties are few and each AnimSeqs
    # entry has more, so the default reading comes back as one of its entries.
    wide = {tag[0]: _value(mr, tag) for tag in mr.chain_of(track_idx, widest=True)[0]}
    for entry in _struct_array(mr, wide.get('AnimSeqs')):
        name = str(entry.get('AnimSeqName'))
        if name not in known:
            continue
        tracks, seconds = bone_tracks(mr, known[name])
        plays.append({'start': float(entry.get('StartTime', 0.0)), 'tracks': tracks, 'seconds': seconds,
                      'offset': float(entry.get('AnimStartOffset', 0.0)), 'rate': float(entry.get('AnimPlayRate', 1.0)),
                      'loops': bool(entry.get('bLooping', False))})
    if not plays:
        return None
    plays.sort(key=lambda play: play['start'])
    stands = _from_rotator(*rotation)
    times = [min(i * SAMPLE_STEP_S, length) for i in range(int(math.ceil(length / SAMPLE_STEP_S)) + 1)]
    position, euler, last = [], [], None
    for time in times:
        play = next((p for p in reversed(plays) if p['start'] <= time), plays[0])
        into = max(time - play['start'], 0.0) * play['rate'] + play['offset']
        into = math.fmod(into, play['seconds']) if play['loops'] and play['seconds'] > 0.0 else min(into, play['seconds'])
        turned, moved = body_pose(skeleton, play['tracks'], into / play['seconds'] if play['seconds'] > 0.0 else 0.0)
        moved = [location[k] + _apply(stands, moved)[k] for k in range(3)]
        angles = _euler_degrees(_mul(stands, turned))
        if last is not None:
            # Keys are interpolated a component at a time: -179 after 179 has
            # to read 181, or the body spins the long way round between them.
            angles = [a + 360.0 * round((b - a) / 360.0) for a, b in zip(angles, last)]
        last = angles
        key = {'time': round(time, 4), 'arrive': [0.0, 0.0, 0.0], 'leave': [0.0, 0.0, 0.0], 'mode': 'linear'}
        position.append(dict(key, value=[moved[0] / UU, moved[2] / UU, moved[1] / UU]))
        euler.append(dict(key, value=[round(a, 4) for a in angles]))
    return {'position': position, 'euler': euler, 'local': False, 'absolute': True}
