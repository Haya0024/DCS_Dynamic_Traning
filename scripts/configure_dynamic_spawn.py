"""Bounded, explicitly authorized one-time migration. Default is a read-only preview.

Preserves original Lua text except selected field values/insertions. No Lua code is executed.
Run with --apply only with approval for mission/warehouse settings changes (AGENTS.md).
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from zipfile import ZipFile


class Node:
    def __init__(self, start, end, value, fields=None):
        self.start, self.end, self.value, self.fields = start, end, value, fields


class LuaData:
    # Only the literal table subset emitted by Mission Editor is accepted.
    token = re.compile(r'\s+|--\[\[.*?\]\]|--[^\r\n]*|"(?:\\[\s\S]|[^"\\])*"|\'(?:\\[\s\S]|[^\'\\])*\'|-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|[A-Za-z_][A-Za-z_0-9]*|[{}\[\]=,;]', re.S)

    def __init__(self, text, expected):
        self.text, self.tokens, self.index, self.edits = text, [], 0, []
        position = 0
        for match in self.token.finditer(text):
            if match.start() != position:
                raise ValueError('Unsupported Lua data at byte ' + str(position))
            position = match.end()
            if not match[0].isspace() and not match[0].startswith('--'):
                self.tokens.append((match[0], match.start(), match.end()))
        if position != len(text):
            raise ValueError('Unsupported trailing Lua data')
        self.take(expected); self.take('='); self.root = self.parse()
        if self.index != len(self.tokens):
            raise ValueError('Trailing statements are not allowed')

    def take(self, expected=None):
        item = self.tokens[self.index]; self.index += 1
        if expected is not None and item[0] != expected:
            raise ValueError('Expected ' + expected + ', got ' + item[0])
        return item

    @staticmethod
    def string(token):
        def unescape(m):
            value = m[1]
            escapes = {'n': '\n', 'r': '\r', 't': '\t', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v'}
            return chr(int(value)) if value.isdigit() else escapes.get(value, value)
        return re.sub(r'\\(\d{1,3}|[\s\S])', unescape, token[1:-1])

    def parse(self):
        token, start, end = self.take()
        if token == '{':
            values, fields = {}, {}
            while self.tokens[self.index][0] != '}':
                self.take('['); key = self.parse().value; self.take(']'); self.take('=')
                if key in fields:
                    raise ValueError('Duplicate Lua key')
                child = self.parse(); values[key], fields[key] = child.value, child
                if self.tokens[self.index][0] in (',', ';'):
                    self.take()
            _, _, end = self.take('}')
            return Node(start, end, values, fields)
        if token[:1] in ('"', "'"):
            return Node(start, end, self.string(token))
        if token in ('true', 'false', 'nil'):
            return Node(start, end, {'true': True, 'false': False, 'nil': None}[token])
        if re.fullmatch(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?', token):
            value = float(token)
            return Node(start, end, int(value) if value.is_integer() else value)
        raise ValueError('Executable/nonliteral Lua value refused: ' + token)

    @staticmethod
    def literal(value):
        if isinstance(value, bool):
            return 'true' if value else 'false'
        if isinstance(value, str):
            return json.dumps(value, ensure_ascii=False)
        if isinstance(value, dict):
            return '{' + ','.join('[' + LuaData.literal(k) + ']=' + LuaData.literal(v) for k, v in value.items()) + '}'
        return str(value)

    def set(self, table, key, value):
        if table.value.get(key) == value:
            return
        if key in table.fields:
            node = table.fields[key]
            self.edits.append((node.start, node.end, self.literal(value)))
        else:
            self.edits.append((table.end - 1, table.end - 1, '[' + self.literal(key) + ']=' + self.literal(value) + ',\n'))
        table.value[key] = value

    def render(self):
        text = self.text
        for start, end, replacement in sorted(self.edits, reverse=True):
            text = text[:start] + replacement + text[end:]
        return text


def configure(mission_data, warehouse_data):
    mission, warehouse = LuaData(mission_data, 'mission'), LuaData(warehouse_data, 'warehouses')
    before_mission, before_warehouse = copy.deepcopy(mission.root.value), copy.deepcopy(warehouse.root.value)
    groups, selected = [], {}
    countries = mission.root.fields['coalition'].fields['blue'].fields['country']
    for country in countries.fields.values():
        for category in ('plane', 'helicopter'):
            if category not in country.fields:
                continue
            for group in country.fields[category].fields['group'].fields.values():
                name = group.value['name']
                if not (name.startswith('BLUE_HORNET_') or name.startswith('BLUE_APACHE_')):
                    continue
                assert all(u['skill'] == 'Client' for u in group.value['units'].values())
                mission.set(group, 'dynSpawnTemplate', True)
                # An opaque non-user password hides template-only traditional slots (ED guide).
                mission.set(group, 'password', hashlib.sha256(('DT_TEMPLATE_ONLY:' + name).encode()).hexdigest())
                groups.append((group, name))
                if name.endswith('_SOLO_01'):
                    point = group.value['route']['points'][1]
                    location = ('airports', point['airdromeId']) if 'airdromeId' in point else ('warehouses', point['linkUnit'])
                    kind = group.value['units'][1]['type']
                    assert kind in ('FA-18C_hornet', 'AH-64D_BLK_II')
                    selected.setdefault(location, {})[kind] = group.value['groupId']
    assert len(groups) == 18 and len(selected) == 5, 'Unexpected player/base layout; migration refused'
    allowed_mission = copy.deepcopy(before_mission)
    for country in allowed_mission['coalition']['blue']['country'].values():
        for category in ('plane', 'helicopter'):
            for group in country.get(category, {}).get('group', {}).values():
                if any(group['name'] == name for _, name in groups):
                    group['dynSpawnTemplate'] = True
                    group['password'] = hashlib.sha256(('DT_TEMPLATE_ONLY:' + group['name']).encode()).hexdigest()
    assert mission.root.value == allowed_mission
    report = []
    expected_warehouse = copy.deepcopy(before_warehouse)
    for (category, base), types in sorted(selected.items()):
        node = warehouse.root.fields[category].fields[base]
        assert str(node.value['coalition']).lower() == 'blue'
        inventory = {'planes': {}, 'helicopters': {}}
        # Published DCS warehouse type IDs; string type names remain the primary inventory keys.
        for kind, template in types.items():
            helicopter = kind == 'AH-64D_BLK_II'
            inventory['helicopters' if helicopter else 'planes'][kind] = {
                'initialAmount': 100, 'unlimited': True, 'linkDynTempl': template,
                'wsType': {1: 1, 2: 2 if helicopter else 1, 3: 6 if helicopter else 1, 4: 300 if helicopter else 280}}
        for key, value in {'dynamicSpawn': True, 'unlimitedAircrafts': False, 'aircrafts': inventory}.items():
            warehouse.set(node, key, value)
            expected_warehouse[category][base][key] = value
        report.append({'category': category, 'id': base, 'templates': types, 'stock': 'unlimited per selected type', 'hotStart': node.value['allowHotStart']})
    assert warehouse.root.value == expected_warehouse
    after_mission, after_warehouse = mission.render(), warehouse.render()
    assert LuaData(after_mission, 'mission').root.value == allowed_mission
    assert LuaData(after_warehouse, 'warehouses').root.value == expected_warehouse
    return after_mission.encode(), after_warehouse.encode(), {'templateGroups': len(groups), 'locations': report}


def configure_standard(mission_data, warehouse_data):
    """Remove only the former BLUE player originals and clear their warehouse links."""
    mission, warehouse = LuaData(mission_data, 'mission'), LuaData(warehouse_data, 'warehouses')
    expected_mission, expected_warehouse = copy.deepcopy(mission.root.value), copy.deepcopy(warehouse.root.value)
    removed, removed_ids = [], set()
    countries = mission.root.fields['coalition'].fields['blue'].fields['country']
    for country_id, country in countries.fields.items():
        for category in ('plane', 'helicopter'):
            if category not in country.fields:
                continue
            node = country.fields[category]
            kept = {}
            for _, group in sorted(node.value.get('group', {}).items()):
                if group['name'].startswith(('BLUE_HORNET_', 'BLUE_APACHE_')):
                    assert all(u['skill'] == 'Client' for u in group['units'].values()), 'Refuse to remove non-player group'
                    removed.append(group['name'])
                    removed_ids.add(group['groupId'])
                else:
                    kept[len(kept) + 1] = copy.deepcopy(group)
            mission.set(node, 'group', kept)
            expected_mission['coalition']['blue']['country'][country_id][category]['group'] = kept
    assert len(removed) in (0, 18), 'Unexpected player layout; standard migration refused'
    locations, cleared = [], 0
    for category, base in [('airports', 6), ('airports', 16), ('airports', 30), ('airports', 44), ('warehouses', 12)]:
        node = warehouse.root.fields[category].fields[base]
        assert str(node.value['coalition']).lower() == 'blue' and node.value['dynamicSpawn']
        kinds = set()
        for subcategory, types in node.fields['aircrafts'].fields.items():
            for kind, entry in types.fields.items():
                kinds.add(kind)
                assert entry.value['unlimited'] and entry.value['initialAmount'] > 0
                if entry.value.get('linkDynTempl', 0):
                    assert entry.value['linkDynTempl'] in removed_ids, 'Refuse to clear an unrelated template link'
                    cleared += 1
                warehouse.set(entry, 'linkDynTempl', 0)
                expected_warehouse[category][base]['aircrafts'][subcategory][kind]['linkDynTempl'] = 0
        assert kinds == ({'FA-18C_hornet', 'AH-64D_BLK_II'} if category == 'airports' else {'FA-18C_hornet'})
        locations.append({'category': category, 'id': base, 'aircraftTypes': sorted(kinds)})
    assert cleared in (0, 9), 'Unexpected warehouse template links'
    assert mission.root.value == expected_mission and warehouse.root.value == expected_warehouse
    after_mission, after_warehouse = mission.render(), warehouse.render()
    assert LuaData(after_mission, 'mission').root.value == expected_mission
    assert LuaData(after_warehouse, 'warehouses').root.value == expected_warehouse
    return after_mission.encode(), after_warehouse.encode(), {
        'removedGroups': sorted(removed), 'clearedLinks': cleared, 'locations': locations, 'aircraftSettings': 'DCS default'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mission', type=Path, default=Path('mission/persistant_and_dynamic_traning.miz'))
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--standard-aircraft', action='store_true', help='Remove former player originals and use DCS defaults')
    args = parser.parse_args()
    source = args.mission.read_bytes()
    with ZipFile(args.mission) as archive:
        assert archive.testzip() is None and len(archive.namelist()) == len(set(archive.namelist()))
        contents = {name: archive.read(name) for name in archive.namelist()}
        infos = archive.infolist()
    operation = configure_standard if args.standard_aircraft else configure
    new_mission, new_warehouse, report = operation(contents['mission'].decode(), contents['warehouses'].decode())
    replacements = {'mission': new_mission, 'warehouses': new_warehouse}
    changed = [name for name, data in replacements.items() if data != contents[name]]
    report.update({'changedEntries': changed, 'sourceSHA256': hashlib.sha256(source).hexdigest(), 'apply': args.apply})
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not args.apply or not changed:
        return
    backup = Path(str(args.mission) + ('.standard-spawn.bak' if args.standard_aircraft else '.dynamic-spawn.bak'))
    assert not backup.exists(), 'Migration backup already exists; inspect it before another migration'
    handle, temporary = tempfile.mkstemp(dir=args.mission.parent, suffix='.tmp')
    os.close(handle)
    try:
        with ZipFile(temporary, 'w') as output:
            for info in infos:
                output.writestr(info, replacements.get(info.filename, contents[info.filename]))
        with ZipFile(temporary) as verify:
            assert verify.testzip() is None
            for name in contents:
                assert verify.read(name) == replacements.get(name, contents[name])
        assert args.mission.read_bytes() == source, 'Mission changed during migration; replacement refused'
        shutil.copy2(args.mission, backup)
        os.replace(temporary, args.mission)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    main()
