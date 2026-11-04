# SPDX-License-Identifier: 0BSD
"""Original AI-assisted regressions for local Steam/Godot discovery and install."""
import contextlib
import io
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

LIB = Path(__file__).resolve().parents[1]/'steam'/'lib'
sys.path.insert(0, str(LIB))
import exe_source as discovery


def file(path, content=b'engine'):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return path


def quoted(path):
    return '"' + str(path).replace('\\', '\\\\') + '"'


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root/'project'
        self.steam = self.root/'Steam'
        env = patch.dict(os.environ, {'GODOT_EXE': ''})
        env.start()
        self.addCleanup(env.stop)
        which = patch.object(discovery.shutil, 'which', return_value=None)
        which.start()
        self.addCleanup(which.stop)

    def sources(self, roots=None):
        return [p for p in discovery.source_candidates(self.project, roots or [self.steam])
                if p.is_file()]

    def engine(self, library, name='godot.windows.opt.tools.64.exe', directory='Godot Engine'):
        return file(library/'steamapps'/'common'/directory/name)

    def libraries(self, text):
        return file(self.steam/'steamapps'/'libraryfolders.vdf', text.encode('utf-8'))

    def test_standard_library_both_names_prefer_direct_engine(self):
        direct = self.engine(self.steam)
        launcher = self.engine(self.steam, 'Godot Engine.exe')
        self.assertEqual(self.sources(), [direct, launcher])

    def test_standard_library_launcher_only_without_metadata(self):
        engine = self.engine(self.steam, 'Godot Engine.exe')
        self.assertEqual(self.sources(), [engine])

    def test_modern_compact_vdf_escaped_unicode_paths_comments_and_duplicates(self):
        library = self.root/'Games with spaces é'/'SteamLibrary'
        engine = self.engine(library)
        self.libraries('// "path" "ignored"\n"libraryfolders" { "0" { "path" '
                       + quoted(self.steam) + ' } "1" { "path" ' + quoted(library)
                       + ' "apps" { "404790" "123" } } "2" { "path" '
                       + quoted(library) + ' } }')
        self.assertEqual(self.sources(), [engine])

    def test_legacy_library_file(self):
        library = self.root/'Old Library'
        engine = self.engine(library, 'Godot Engine.exe')
        self.libraries('"LibraryFolders" { "TimeNextStatsReport" "123" "1" '
                       + quoted(library) + ' }')
        self.assertEqual(self.sources(), [engine])

    def test_manifest_install_directory_and_versioned_executable(self):
        engine = self.engine(self.steam, 'Godot_v4.7-stable_win64.exe', 'Godot Custom')
        file(self.steam/'steamapps'/'appmanifest_404790.acf',
             b'"AppState" { "appid" "404790" "installdir" "Godot Custom" }')
        self.assertEqual(self.sources(), [engine])

    def test_malformed_manifest_falls_back_to_known_directory(self):
        engine = self.engine(self.steam)
        self.libraries('"libraryfolders" { "1" { "path" "truncated"')
        file(self.steam/'steamapps'/'appmanifest_404790.acf', b'"AppState" "wrong shape"')
        self.assertEqual(self.sources(), [engine])

    def test_export_then_quoted_environment_override_then_steam(self):
        export = file(self.project/'dist'/'TerraForest.exe')
        override = file(self.root/'My Godot.exe')
        engine = self.engine(self.steam)
        with patch.dict(os.environ, {'GODOT_EXE': f'"{override}"'}):
            self.assertEqual(self.sources(), [export, override, engine])

    def test_invalid_environment_falls_through_and_path_wrapper_is_not_copied(self):
        engine = self.engine(self.steam)
        wrapper = file(self.root/'godot.cmd')
        with patch.dict(os.environ, {'GODOT_EXE': str(self.root/'absent.exe')}), \
                patch.object(discovery.shutil, 'which', return_value=str(wrapper)):
            self.assertEqual(self.sources(), [engine])

    def test_path_native_executable_fallback(self):
        engine = file(self.root/'bin'/'godot4.exe')
        with patch.object(discovery.shutil, 'which', side_effect=[None, str(engine)]):
            self.assertEqual(self.sources(), [engine])


@unittest.skipUnless(sys.platform == 'win32', 'Windows Steam installer')
class InstallTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import install_to_steam
        import steam_gui
        cls.install = install_to_steam
        cls.gui = steam_gui

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root/'TerraForest.exe'
        self.output = io.StringIO()
        for replacement in (patch.object(self.install, 'TARGET', self.target),
                            contextlib.redirect_stdout(self.output)):
            replacement.__enter__()
            self.addCleanup(replacement.__exit__, None, None, None)

    def args(self, **changes):
        values = dict(source=None, steam=self.root/'Steam', account=None, force=False,
                      dry_run=True, name='TerraForest', no_restart=False,
                      last_world=False, artwork=False, desktop=True,
                      desktop_folder=self.root/'Desktop')
        return SimpleNamespace(**(values | changes))

    def test_explicit_steam_root_is_searched_without_registry(self):
        engine = file(self.root/'Steam'/'steamapps'/'common'/'Godot Engine'/'Godot Engine.exe')
        with patch.object(self.install.steam_tool, 'steam_roots', return_value=[]), \
                patch.object(self.install, 'ROOT', self.root/'project'), \
                patch.dict(os.environ, {'GODOT_EXE': ''}), \
                patch.object(discovery.shutil, 'which', return_value=None):
            self.assertEqual(self.install.godot_sources(self.root/'Steam'), [engine])

    def test_missing_source_stops_before_icon_or_steam_with_actionable_message(self):
        with patch.object(self.install, 'godot_sources', return_value=[]), \
                patch.object(self.install, 'stamp') as stamp, \
                patch.object(self.install, 'register') as register:
            with self.assertRaises(SystemExit) as error:
                self.install.deploy(self.args())
            self.assertIn('Install Godot Engine in Steam', str(error.exception))
            self.assertIn('GODOT_EXE', str(error.exception))
            stamp.assert_not_called()
            register.assert_not_called()
        self.assertFalse(self.target.exists())

    def test_first_install_dry_run_checks_source_and_plans_all_shortcuts_without_writes(self):
        source = file(self.root/'Godot.exe')
        shortcut = file(self.root/'Steam'/'userdata'/'123'/'config'/'shortcuts.vdf',
                        self.install.steam_tool.serialize_shortcuts('shortcuts', {}))
        original = shortcut.read_bytes()
        desktop = self.install.load('desktop_test', LIB.parent/'add_desktop_shortcuts.py')
        original_load = self.install.load
        with patch.object(self.install.app_icon, 'check', return_value=(['different icon'], 7, [])) as check, \
                patch.object(self.install.steam_tool, 'steam_roots', return_value=[self.root/'Steam']), \
                patch.object(self.install.steam_tool, 'commit') as commit, \
                patch.object(self.install, 'load', side_effect=lambda name, path:
                             desktop if name == 'add_desktop_shortcuts' else original_load(name, path)), \
                patch.object(desktop, 'steam_entry', return_value=(None, None)), \
                patch.object(desktop, 'write_shortcut') as write_link:
            self.assertEqual(self.install.deploy(self.args(source=source, last_world=True)), 0)
            check.assert_called_once_with(source, self.install.ICON)
            commit.assert_not_called()
            write_link.assert_not_called()
        self.assertEqual(shortcut.read_bytes(), original)
        self.assertFalse(self.target.exists())
        self.assertFalse((self.root/'Desktop').exists())
        self.assertEqual(list(shortcut.parent.iterdir()), [shortcut])
        self.assertIn('TerraForest Last World', self.output.getvalue())
        self.assertIn('dry run complete; nothing changed', self.output.getvalue())

    def test_force_dry_run_checks_replacement_not_old_copy(self):
        file(self.target, b'old')
        source = file(self.root/'New.exe', b'new')
        with patch.object(self.install, 'stamp', return_value=True) as stamp, \
                patch.object(self.install, 'shortcut_file'), \
                patch.object(self.install, 'register', return_value=1):
            self.assertEqual(self.install.deploy(self.args(source=source, force=True)), 1)
            stamp.assert_called_once_with(True, source)
        self.assertEqual(self.target.read_bytes(), b'old')

    def test_existing_target_needs_no_source_and_force_same_source_is_safe(self):
        file(self.target, b'kept')
        self.install.prepare(None, False, False)
        self.install.prepare(self.target, True, False)
        self.assertEqual(self.target.read_bytes(), b'kept')

    def test_bad_explicit_source_is_actionable_and_target_untouched(self):
        with self.assertRaisesRegex(SystemExit, 'source executable does not exist'):
            self.install.prepare(self.root/'missing.exe', False, False)
        self.assertFalse(self.target.exists())

    def test_real_copy_uses_selected_source(self):
        source = file(self.root/'Godot.exe', b'new engine')
        self.assertTrue(self.install.prepare(source, False, False))
        self.assertEqual(self.target.read_bytes(), source.read_bytes())

    def test_standard_steam_root_fallback_without_registry(self):
        steam = self.root/'Program Files'/'Steam'
        steam.mkdir(parents=True)
        with patch.object(self.install.steam_tool.winreg, 'OpenKey', side_effect=OSError), \
                patch.dict(os.environ, {'ProgramFiles(x86)': str(steam.parent), 'ProgramFiles': ''}):
            self.assertEqual(self.install.steam_tool.steam_roots(), [steam])

    def test_gui_retains_system_exit_reason_after_finish(self):
        module = SimpleNamespace(__name__='fake_install', main=Mock(side_effect=SystemExit('Install Godot Engine')))
        app = self.gui.App(module, [], 'Test')
        app.root = Mock()
        app.stage = Mock()
        app.note = Mock()
        app.cancel_button = Mock()
        app.go_button = Mock()
        with patch.object(sys, 'argv', []):
            app.work()
        app.pump()
        self.assertEqual(app.code, 1)
        app.note.configure.assert_called_with(text='Install Godot Engine')


if __name__ == '__main__':
    unittest.main()
