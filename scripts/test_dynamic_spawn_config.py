"""Read-only saved-MIZ checks and standard-aircraft migration fixtures."""
import copy
import importlib.util
from pathlib import Path
import unittest
from zipfile import ZipFile

spec = importlib.util.spec_from_file_location('migration', Path(__file__).with_name('configure_dynamic_spawn.py'))
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = Path('mission/persistant_and_dynamic_traning.miz')
        with ZipFile(cls.path) as z:
            cls.mission, cls.warehouse = z.read('mission').decode(), z.read('warehouses').decode()

    def original_layout(self):
        data = copy.deepcopy(migration.LuaData(self.mission, 'mission').root.value)
        country = next(c for c in data['coalition']['blue']['country'].values() if c['name'] == 'USA')
        for category, prefix in [('plane', 'BLUE_HORNET_'), ('helicopter', 'BLUE_APACHE_')]:
            retained = [g for g in country.get(category, {}).get('group', {}).values() if not g['name'].startswith(prefix)]
            groups = {i+1: g for i, g in enumerate(retained)}
            count = 10 if category == 'plane' else 8
            for i in range(count):
                groups[len(groups)+1] = {'name': prefix + 'TEST_' + str(i), 'groupId': 10000+i+(100 if category == 'plane' else 0),
                    'units': {1: {'skill': 'Client', 'type': 'FA-18C_hornet' if category == 'plane' else 'AH-64D_BLK_II'}}}
            country.setdefault(category, {})['group'] = groups
        return 'mission=' + migration.LuaData.literal(data)

    def test_preview_is_read_only(self):
        before = self.path.read_bytes()
        a, b, report = migration.configure_standard(self.mission, self.warehouse)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertIn(len(report['removedGroups']), (0,18))
        self.assertEqual(len(report['locations']), 5)

    def test_migration_is_idempotent(self):
        a, b, _ = migration.configure_standard(self.mission, self.warehouse)
        c, d, report = migration.configure_standard(a.decode(), b.decode())
        self.assertEqual((a,b), (c,d))
        self.assertEqual(report['removedGroups'], [])
        self.assertEqual(report['clearedLinks'], 0)

    def test_only_selected_types_keep_unlimited_stock_and_no_template_links(self):
        a, b, report = migration.configure_standard(self.mission, self.warehouse)
        data = migration.LuaData(b.decode(), 'warehouses').root.value
        for location in report['locations']:
            stock = data[location['category']][location['id']]
            self.assertTrue(stock['dynamicSpawn'])
            self.assertFalse(stock['unlimitedAircrafts'])
            kinds = set()
            for types in stock['aircrafts'].values():
                for kind, item in types.items():
                    self.assertTrue(item['unlimited'])
                    self.assertEqual(item['linkDynTempl'], 0)
                    self.assertEqual(len(item['wsType']), 4)
                    kinds.add(kind)
            self.assertEqual(kinds, set(location['aircraftTypes']))
            self.assertEqual('AH-64D_BLK_II' in kinds, location['category'] == 'airports')

    def test_literal_parser_refuses_executable_and_duplicate_key_data(self):
        for text in ['mission={ ["x"]=os.execute("bad") }', 'mission={} bad()', 'mission={[1]=1,[1]=2}']:
            with self.assertRaises((ValueError, IndexError)):
                migration.LuaData(text, 'mission')

    def test_unexpected_partial_layout_is_refused(self):
        data = migration.LuaData(self.original_layout(), 'mission').root.value
        for country in data['coalition']['blue']['country'].values():
            for group in country.get('plane', {}).get('group', {}).values():
                if group['name'].startswith('BLUE_HORNET_'):
                    group['name'] = 'UNRELATED_AI'
                    with self.assertRaises(AssertionError):
                        migration.configure_standard('mission='+migration.LuaData.literal(data), self.warehouse)
                    return
        self.fail('Missing fixture original')

    def test_eighteen_originals_removed_without_touching_ai_weather_or_triggers(self):
        # Give the synthetic original layout an already-unlinked warehouse.
        _, stock, _ = migration.configure_standard(self.mission, self.warehouse)
        source = self.original_layout()
        a, b, report = migration.configure_standard(source, stock.decode())
        self.assertEqual(len(report['removedGroups']), 18)
        expected = migration.LuaData(source, 'mission').root.value
        for country in expected['coalition']['blue']['country'].values():
            for category in ('plane', 'helicopter'):
                if category in country:
                    kept = [g for _,g in sorted(country[category]['group'].items())
                        if not g['name'].startswith(('BLUE_HORNET_', 'BLUE_APACHE_'))]
                    country[category]['group'] = {i+1:g for i,g in enumerate(kept)}
        self.assertEqual(migration.LuaData(a.decode(), 'mission').root.value, expected)
        self.assertEqual(b, stock)

    def test_unrelated_warehouse_link_is_refused(self):
        source = self.original_layout()
        _, stock, _ = migration.configure_standard(self.mission, self.warehouse)
        warehouse = migration.LuaData(stock.decode(), 'warehouses').root.value
        warehouse['airports'][6]['aircrafts']['planes']['FA-18C_hornet']['linkDynTempl'] = 999999
        with self.assertRaises(AssertionError):
            migration.configure_standard(source, 'warehouses='+migration.LuaData.literal(warehouse))


if __name__ == '__main__':
    unittest.main()
