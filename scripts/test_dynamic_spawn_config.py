"""Read-only saved-MIZ checks and disposable migration fixtures."""
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

    def test_preview_is_read_only_and_keeps_original_groups(self):
        original = self.path.read_bytes()
        mission, warehouse, report = migration.configure(self.mission, self.warehouse)
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(report['templateGroups'], 18)
        self.assertEqual(len(report['locations']), 5)

    def test_migration_is_idempotent(self):
        a, b, _ = migration.configure(self.mission, self.warehouse)
        c, d, _ = migration.configure(a.decode(), b.decode())
        self.assertEqual((a, b), (c, d))

    def test_only_selected_types_have_unlimited_stock_and_valid_solo_links(self):
        a, b, report = migration.configure(self.mission, self.warehouse)
        warehouse = migration.LuaData(b.decode(), 'warehouses').root.value
        for location in report['locations']:
            w = warehouse[location['category']][location['id']]
            self.assertTrue(w['dynamicSpawn'])
            self.assertFalse(w['unlimitedAircrafts'])
            actual = {}
            for section in w['aircrafts'].values():
                for kind, stock in section.items():
                    self.assertTrue(stock['unlimited'])
                    self.assertEqual(len(stock['wsType']), 4)
                    actual[kind] = stock['linkDynTempl']
            self.assertEqual(actual, location['templates'])
            self.assertEqual('AH-64D_BLK_II' in actual, location['category'] == 'airports')

    def test_literal_parser_refuses_executable_and_duplicate_key_data(self):
        for source in ['mission={ ["x"]=os.execute("bad") }', 'mission={} bad()', 'mission={[1]=1,[1]=2}']:
            with self.assertRaises((ValueError, IndexError)):
                migration.LuaData(source, 'mission')

    def test_unexpected_layout_is_refused(self):
        parsed = migration.LuaData(self.mission, 'mission')
        for country in parsed.root.fields['coalition'].fields['blue'].fields['country'].fields.values():
            for category in ('plane', 'helicopter'):
                if category not in country.fields:
                    continue
                for group in country.fields[category].fields['group'].fields.values():
                    if group.value['name'].startswith('BLUE_HORNET_'):
                        parsed.set(group, 'name', 'OTHER_GROUP')
                        with self.assertRaises(AssertionError):
                            migration.configure(parsed.render(), self.warehouse)
                        return
        self.fail('No player template found')

    def test_reparse_preserves_weather_triggers_red_and_every_unrelated_field(self):
        a, b, _ = migration.configure(self.mission, self.warehouse)
        before = migration.LuaData(self.mission, 'mission').root.value
        after = migration.LuaData(a.decode(), 'mission').root.value
        for country in before['coalition']['blue']['country'].values():
            for category in ('plane', 'helicopter'):
                for group in country.get(category, {}).get('group', {}).values():
                    if group['name'].startswith(('BLUE_HORNET_', 'BLUE_APACHE_')):
                        group['dynSpawnTemplate'] = True
                        group['password'] = migration.hashlib.sha256(('DT_TEMPLATE_ONLY:' + group['name']).encode()).hexdigest()
        self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
