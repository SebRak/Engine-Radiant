import argparse
import json
import math
from collections import Counter
from contextlib import ExitStack
import os
from pathlib import Path, PurePosixPath
import re

POINTS = r'(\([^()]*\)\s+\([^()]*\)\s+\([^()]*\))'
PAIR = re.compile(r'"([^"]+)"\s+"((?:\\.|[^"\\])*)"')
MATERIAL = re.compile(r'[A-Za-z0-9_./+@$-]+')


DIRECTIVE = re.compile(r'(?:contents|surfaceFlags|toolFlags)\s+[^;]+;')
NUM = re.compile(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
MATERIAL_TOKEN = re.compile(r'"[^"]+"|\S+')


def finite(values):
    if any(not NUM.fullmatch(value) for value in values):
        raise ValueError('Invalid numeric component')
    result = tuple(map(float, values))
    if not all(map(math.isfinite, result)):
        raise ValueError('Non-finite numeric component')
    return result


def verified_materials(path):
    if path is None:
        return {}
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    available = set(data['rawfront_textures'])
    result = {}
    for entry in data['materials']:
        if entry['status'] != 'verified':
            continue
        targets = entry['targets']
        if (len(targets) != 1 or targets[0] not in available
                or not MATERIAL.fullmatch(targets[0]) or '..' in targets[0]):
            raise ValueError(f"Invalid verified material: {entry['source']}")
        if entry['source'] in result:
            raise ValueError(f"Duplicate verified material: {entry['source']}")
        result[entry['source']] = targets[0]
    return result


def locate_prefab(reference, root):
    if root is None:
        return 'reference-only'
    path = PurePosixPath(reference.replace('\\', '/'))
    if path.is_absolute() or '..' in path.parts or ':' in reference:
        return 'unsafe-path'
    candidate = root.joinpath(*path.parts).resolve()
    if not candidate.is_relative_to(root):
        return 'unsafe-path'
    return 'found-not-expanded' if candidate.is_file() else 'not-found'


def convert(text, mappings=None, prefab_root=None):
    header, _, body = text.partition('\n')
    if header.strip() != 'iwmap 4':
        raise ValueError('Expected Call of Duty 2 iwmap 4')
    lines = iter((number, line.strip()) for number, line in
                 enumerate(body.splitlines(), 2)
                 if line.strip() and not line.lstrip().startswith('//'))
    materials, classes, models, flags = (Counter() for _ in range(4))
    brushes = patches = faces = 0
    meshes = 0
    output = []
    entities = []
    unsupported = []
    prefabs = []
    substitutions = Counter()
    unmapped_vertex_attributes = Counter()
    grid_layouts = []
    mappings = {} if mappings is None else mappings
    number = 1

    def take(expected=None):
        nonlocal number
        try:
            number, line = next(lines)
        except StopIteration:
            raise ValueError(f'Unexpected end of MAP after line {number}') from None
        if expected is not None and line != expected:
            raise ValueError(f'Line {number}: expected {expected!r}, got {line!r}')
        return line

    def shader(name):
        name = name.strip('"')
        if not MATERIAL.fullmatch(name) or name.startswith('/') or '..' in name:
            raise ValueError(f'Invalid shader name: {name}')
        if name in mappings:
            substitutions[name] += 1
            return mappings[name]
        materials[name] += 1
        return 'cod2_missing/' + name

    def patch(material, grid):
        nonlocal patches
        patches += 1
        columns = ['( ' + ' '.join(
            '( ' + ' '.join(f'{component:.10g}' for component in point) + ' )'
            for point in column) + ' )' for column in grid]
        return ['{', 'patchDef2', '{', material,
                f'( {len(grid)} {len(grid[0])} 0 0 0 )', '(', *columns, ')', '}', '}']

    def midpoint(a, b):
        return tuple(x / 2 + y / 2 for x, y in zip(a, b))

    def linear_spans(points):
        result = []
        for left, right in zip(points, points[1:]):
            result.extend((left, midpoint(left, right)))
        return [*result, points[-1]]

    def primitive(first):
        nonlocal brushes, faces, meshes
        opening = number
        directives = []
        while DIRECTIVE.fullmatch(first):
            directives.append(first)
            flags[first] += 1
            first = take()
        if first in ('curve', 'mesh'):
            kind = first
            take('{')
            material = take()
            while DIRECTIVE.fullmatch(material):
                directives.append(material)
                flags[material] += 1
                material = take()
            lightmap, dimensions = take(), take()
            size = dimensions.split()
            if len(size) != 4 or any(not item.isdecimal() for item in size):
                raise ValueError(f'Line {number}: invalid {kind} dimensions: {dimensions}')
            width, height = map(int, size[:2])
            if min(width, height) < 1 or width * height > 1_000_000:
                raise ValueError(f'Line {number}: invalid {kind} grid size')
            grid = []
            for _ in range(width):
                take('(')
                column = []
                for _ in range(height):
                    fields = take().split()
                    if fields[:1] != ['v'] or len(fields) < 9:
                        raise ValueError(f'Line {number}: invalid {kind} vertex')
                    xyz = fields[1:4]
                    tail = fields[4:]
                    if tail[0] == 'c' and len(tail) >= 10:
                        finite(tail[1:5])
                        unmapped_vertex_attributes['color'] += 1
                        tail = tail[5:]
                    if tail[0] != 't' or len(tail) not in (5, 7):
                        raise ValueError(f'Line {number}: invalid {kind} texture coordinates')
                    if len(tail) == 7:
                        if tail[5] != 'f':
                            raise ValueError(f'Line {number}: unknown {kind} vertex attribute')
                        finite(tail[6:])
                        unmapped_vertex_attributes['flag'] += 1
                    x, y, z, u, v, _, _ = finite(xyz + tail[1:5])
                    column.append((x, y, z, u / 128, v / 128))
                take(')')
                grid.append(column)
            take('}')
            take('}')
            if (kind == 'curve' and (min(width, height) < 3 or max(width, height) > 31
                                     or width % 2 != 1 or height % 2 != 1)) or min(width, height) < 2:
                unsupported.append(dict(line=opening, primitive=kind, material=material,
                                        reason='Control grid has no equivalent dimensions'))
                return []
            grid_layouts.append(dict(line=opening, primitive=kind, material=material,
                                     lightmap=lightmap, dimensions=list(map(int, size)),
                                     directives=directives))
            target = shader(material)
            if kind == 'curve':
                return patch(target, grid)
            meshes += 1
            result = []
            # One quadratic span per original linear segment, tiled to Radiant's 31-point limit.
            for x in range(0, width - 1, 15):
                for y in range(0, height - 1, 15):
                    tile = [linear_spans(column[y:y + 16]) for column in grid[x:x + 16]]
                    columns = []
                    for left, right in zip(tile, tile[1:]):
                        columns.append(left)
                        columns.append([midpoint(a, b) for a, b in zip(left, right)])
                    columns.append(tile[-1])
                    result.extend(patch(target, columns))
            return result
        if first not in ('}',) and not first.startswith('('):
            unsupported.append(dict(line=opening, primitive=first,
                                    reason='Unknown primitive; geometry omitted'))
            depth = 1
            while depth:
                line = take()
                depth += (line == '{') - (line == '}')
            return []
        brushes += 1
        result = ['{', 'brushDef', '{']
        line = first
        while line != '}':
            if DIRECTIVE.fullmatch(line):
                flags[line] += 1
            else:
                match = re.fullmatch(POINTS + r'\s+(.+)', line)
                if not match:
                    raise ValueError(f'Unsupported brush record: {line}')
                coords, tail = match.groups()
                tokens = MATERIAL_TOKEN.findall(tail)
                if len(tokens) != 14:
                    raise ValueError(f'Line {number}: invalid brush surface fields')
                mat, w, h, u, v, rotation, *_ = tokens
                finite(coords.replace('(', ' ').replace(')', ' ').split())
                w, h, u, v, rotation = finite((w, h, u, v, rotation))
                if w == 0 or h == 0:
                    raise ValueError(f'Line {number}: zero brush texture scale')
                theta = math.radians(rotation)
                c, s = math.cos(theta), math.sin(theta)
                matrix = (c/w, -s/w, u/128, s/h, c/h, v/128)
                matrix_text = ' '.join(f'{x:.10g}' for x in matrix[:3])
                matrix_text2 = ' '.join(f'{x:.10g}' for x in matrix[3:])
                result.append(f'{coords} ( ( {matrix_text} ) ( {matrix_text2} ) ) {shader(mat)} 0 0 0')
                faces += 1
            line = take()
        return result + ['}', '}']

    for number, start in lines:
        start_line = number
        if start != '{':
            raise ValueError(f'Line {number}: expected entity')
        properties, geometry = {}, []
        line = take()
        while line != '}':
            if line == '{':
                geometry.extend(primitive(take()))
            else:
                match = PAIR.fullmatch(line)
                if not match:
                    raise ValueError(f'Unsupported entity record: {line}')
                key, value = match.groups()
                properties[key] = value
            line = take()
        classname = properties.get('classname')
        if not classname:
            raise ValueError(f'Line {number}: entity missing classname')
        classes[classname] += 1
        if 'model' in properties:
            ref = properties['model']
            models[ref] += 1
            if ref.lower().endswith('.map') or classname == 'misc_prefab':
                prefabs.append(dict(entity=len(entities), line=start_line, reference=ref,
                                    placement={k: properties[k] for k in
                                               ('origin', 'angle', 'angles', 'modelscale', 'modelscale_vec')
                                               if k in properties},
                                    status=locate_prefab(ref, prefab_root)))
        entities.append(properties)
        if classname == 'worldspawn':
            keys = {k: v for k, v in properties.items() if k != 'model'}
        elif geometry:
            keys = {'classname': 'func_group', 'cod2_classname': classname}
        else:
            keys = {'classname': 'info_null', 'cod2_classname': classname}
            keys.update({k: properties[k] for k in ('origin', 'angles', 'angle') if k in properties})
        if 'model' in properties:
            keys['cod2_model'] = properties['model']
        output.extend(['{', *(f'"{k}" "{v}"' for k, v in keys.items()), *geometry, '}'])

    if classes['worldspawn'] != 1 or entities[0]['classname'] != 'worldspawn':
        raise ValueError('Expected one worldspawn as the first entity')
    report = {'format': 'iwmap 4 to Quake III brushDef / patchDef2', 'brushes': brushes,
              'brush_faces': faces, 'patches': patches, 'meshes': meshes,
              'entities': len(entities), 'prefabs': prefabs, 'unsupported': unsupported,
              'grid_layouts': grid_layouts, 'vertex_attributes_not_translated': unmapped_vertex_attributes,
              'material_substitutions': {name: {'target': mappings[name], 'count': count}
                                         for name, count in substitutions.items()}, 'entity_classes': classes,
              'model_references': models, 'brush_flags_not_translated': flags,
              'missing_materials': materials, 'original_entity_properties': entities,
              'notes': [
                  'All plane points and curve control XYZ are copied verbatim; no scaling or axis conversion.',
                  'Unmapped shaders retain separate cod2_missing/<original> identifiers. Only explicitly verified mappings are applied.',
                  'Mesh becomes tiled patches of bilinear spans, with XYZ and primary UV at original grid positions. Original tessellation and lightmap UV are not reproduced.',
                  'Prefab instances are recorded with placement metadata; external geometry is not expanded.',
                  'Brush UV projection is approximate; patch UV uses the first texture pair divided by 128 as a preview convention. Lightmap UV and curve subdivision settings are not imported.',
                  'Brush entity geometry is grouped at its source coordinates. Point entities are inert info_null references. CoD2 entity properties and model paths remain in this report.',
                  'This is an editor import. Engine gameplay semantics and collision flags are not converted.'
              ]}
    return '\n'.join(output) + '\n', report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--compatibility', type=Path, default=Path(__file__).with_name('cod2-compatibility.json'))
    parser.add_argument('--prefab-root', type=Path, help='Optional CoD2 map_source for read-only prefab lookup')
    args = parser.parse_args()
    report_path = args.output.with_suffix('.import.json')
    if args.output.suffix.lower() != '.map':
        parser.error('Output must end in .map')
    if args.output.exists() or report_path.exists():
        parser.error('Output or report already exists')
    created = []
    try:
        source = args.source.read_bytes().decode('utf-8-sig')
        prefab_root = args.prefab_root.resolve(strict=True) if args.prefab_root else None
        if prefab_root is not None and not prefab_root.is_dir():
            raise ValueError('Prefab root must be a directory')
        output, report = convert(source, verified_materials(args.compatibility), prefab_root)
        report['source'] = str(args.source)
        with ExitStack() as files:
            map_stream = files.enter_context(args.output.open('x', encoding='utf-8', newline='\n'))
            created.append(args.output)
            report_stream = files.enter_context(report_path.open('x', encoding='utf-8', newline='\n'))
            created.append(report_path)
            map_stream.write(output)
            json.dump(report, report_stream, indent=2, ensure_ascii=True)
            report_stream.write('\n')
    except (OSError, ValueError, KeyError) as exc:
        for path in created:
            os.unlink(path)
        parser.error(str(exc))
    print(f"{report['brushes']} brushes, {report['patches']} patches, "
          f"{len(report['missing_materials'])} missing materials")


if __name__ == '__main__':
    main()
