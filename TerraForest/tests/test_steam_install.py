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
                      last_world=True, artwork=False, desktop=True,
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
        with patch.object(sys, 'argv', []), contextlib.redirect_stderr(self.output):
            app.work()
        app.pump()
        self.assertEqual(app.code, 1)
        app.note.configure.assert_called_with(text='Install Godot Engine')


@unittest.skipUnless(sys.platform == 'win32', 'Windows Steam and Shell links')
class CompleteInstallTests(unittest.TestCase):
    def setUp(self):
        import install_to_steam
        self.install = install_to_steam
        self.tool = self.install.steam_tool
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.project = self.root/'CopiedProject'
        self.project.mkdir()
        self.target = self.project/'TerraForest.exe'
        self.source = file(self.root/'Godot.exe')
        self.steam = self.root/'CustomSteam'
        self.shortcut = self.steam/'userdata'/'123'/'config'/'shortcuts.vdf'
        file(self.shortcut.with_name('localconfig.vdf'), b'"UserLocalConfigStore" {}')
        self.desktop = self.install.load('integration_desktop', LIB.parent/'add_desktop_shortcuts.py')
        original_load = self.install.load
        for replacement in (
                patch.object(self.install, 'ROOT', self.project),
                patch.object(self.install, 'TARGET', self.target),
                patch.object(self.install, 'stamp', return_value=True),
                patch.object(self.install, 'load', side_effect=lambda name, path:
                             self.desktop if name == 'add_desktop_shortcuts' else original_load(name, path)),
                patch.object(self.desktop, 'PROJECT', self.project),
                patch.object(self.desktop, '_STEAM', self.tool),
                patch.object(self.tool, 'steam_roots', return_value=[]),
                patch.object(self.tool.winreg, 'OpenKey', side_effect=OSError),
                patch.object(self.tool, 'PROGRESS_FACTORY', return_value=Mock()),
                patch.object(self.tool, 'CONFIRM', None),
                contextlib.redirect_stdout(io.StringIO())):
            replacement.__enter__()
            self.addCleanup(replacement.__exit__, None, None, None)
        self.args = SimpleNamespace(source=self.source, steam=self.steam, account=None,
                force=False, dry_run=False, name='TerraForest', no_restart=False,
                last_world=True, artwork=True, desktop=True, desktop_folder=self.root/'Desktop')

    def stored(self):
        return self.tool.load(self.shortcut)[2]

    def assert_desktop_routes(self, entries):
        for name in ('TerraForest', 'TerraForest Last World'):
            fields = next(entry for entry in entries.values() if entry['AppName'] == name)
            target, args = self.desktop.read_shortcut(self.args.desktop_folder/f'{name}.lnk')
            self.assertEqual(Path(target).resolve(), self.desktop.RUNDLL.resolve())
            self.assertEqual(args, 'url.dll,FileProtocolHandler steam://rungameid/'
                             + str(self.desktop.long_app_id(fields['appid'])))

    def test_fresh_account_full_install_real_shell_links_artwork_and_idempotence(self):
        # Only the Steam process boundary is mocked; VDF/artwork/.lnk writes are real.
        self.assertFalse(self.shortcut.exists())
        with patch.object(self.tool, 'steam_running', return_value=[]), \
                patch.object(self.tool, 'stop_steam') as stop, \
                patch.object(self.tool, 'start_steam') as start:
            self.assertEqual(self.install.deploy(self.args), 0)
            entries = self.stored()
            self.assertEqual({entry['AppName'] for entry in entries.values()},
                             {'TerraForest', 'TerraForest Last World'})
            self.assert_desktop_routes(entries)
            world = next(entry for entry in entries.values() if entry['AppName'].endswith('Last World'))
            self.assertTrue(world['LaunchOptions'].endswith(' -- --continue-last'))
            self.assertEqual(len(list((self.shortcut.parent/'grid').iterdir())), 10)
            original = self.shortcut.read_bytes()
            self.assertEqual(self.install.deploy(self.args), 0)
            self.assertEqual(self.shortcut.read_bytes(), original)
            self.assert_desktop_routes(self.stored())
            stop.assert_not_called()
            start.assert_not_called()

    def test_repair_pair_one_restart_preserves_shutdown_writes_and_replaces_native_links(self):
        existing = self.tool.shortcut_fields('TerraForest', self.target, '--old-options')
        existing['LastPlayTime'] = 12345
        file(self.shortcut, self.tool.serialize_shortcuts('shortcuts', {'0': existing}))
        self.args.desktop_folder.mkdir()
        for name in ('TerraForest', 'TerraForest Last World'):
            self.desktop.write_shortcut(self.args.desktop_folder/f'{name}.lnk',
                    self.target, '--old-native', self.project, name, self.target)
        unrelated = self.tool.shortcut_fields('Unrelated Game', self.root/'Other.exe', '--keep')

        def shutdown(*args, **kwargs):
            # Steam flushes its in-memory data as it shuts down.
            file(self.shortcut, self.tool.serialize_shortcuts('shortcuts', {'0': existing, '1': unrelated}))
            return True

        with patch.object(self.tool, 'steam_running', return_value=['steam.exe']), \
                patch.object(self.tool, 'stop_steam', side_effect=shutdown) as stop, \
                patch.object(self.tool, 'start_steam', return_value=True) as start:
            self.assertEqual(self.install.deploy(self.args), 0)
            stop.assert_called_once()
            start.assert_called_once()
        entries = self.stored()
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries['1'], unrelated)
        self.assertEqual(entries['0']['LastPlayTime'], 12345)
        self.assert_desktop_routes(entries)
        backup, = self.shortcut.parent.glob('shortcuts.vdf.bak-*')
        self.assertEqual(self.tool.parse_shortcuts(backup.read_bytes())[1]['1'], unrelated)

    def test_no_silent_native_fallback_when_registration_fails(self):
        with patch.object(self.tool, 'upsert_all', return_value=2):
            self.assertEqual(self.install.deploy(self.args), 2)
        self.assertFalse(self.args.desktop_folder.exists())

    def test_verification_detects_steam_dropping_last_world(self):
        def restart(*args, **kwargs):
            entries = self.stored()
            entries = {index: entry for index, entry in entries.items()
                       if entry['AppName'] != 'TerraForest Last World'}
            file(self.shortcut, self.tool.serialize_shortcuts('shortcuts', entries))
            return True

        with patch.object(self.tool, 'steam_running', return_value=['steam.exe']), \
                patch.object(self.tool, 'stop_steam', return_value=True), \
                patch.object(self.tool, 'start_steam', side_effect=restart):
            with self.assertRaisesRegex(SystemExit, 'installation is incomplete'):
                self.install.deploy(self.args)
        self.assertFalse(self.args.desktop_folder.exists())

    def test_no_space_project_quoted_launch_options_still_produce_steam_links(self):
        self.assertNotIn(' ', str(self.project))
        wanted = self.install.wanted_entries('TerraForest')
        self.desktop.create_shortcuts(self.args.desktop_folder, True, exe=self.target,
                                       entries=wanted)
        self.assertTrue(all(item['mode'].startswith('steam') for item in self.desktop.plan(
            self.args.desktop_folder, exe=self.target, plain_entry=wanted[0], world_entry=wanted[1])))

    def test_missing_steam_entry_is_error_in_default_desktop_mode(self):
        with self.assertRaisesRegex(SystemExit, 'Steam entry is missing'):
            self.desktop.plan(self.root/'Desktop', exe=self.target)

    def test_semantically_equivalent_path_quoting_uses_steam(self):
        wanted = self.install.wanted_entries('TerraForest')[0]
        wanted['LaunchOptions'] = f'--path {self.project}'
        self.assertIsNotNone(self.desktop.steam_route(wanted, f'--path "{self.project}"', 'steam'))

    def test_wrong_launch_options_fail_instead_of_creating_bad_steam_link(self):
        wanted = self.install.wanted_entries('TerraForest')[0]
        wanted['LaunchOptions'] = '--path "C:\\wrong-project"'
        with self.assertRaisesRegex(SystemExit, 'launch options need repair'):
            self.desktop.steam_route(wanted, self.install.launch_options(), 'steam')

    def test_active_account_beats_newer_other_account_without_vdf(self):
        other = self.steam/'userdata'/'456'/'config'/'localconfig.vdf'
        file(other, b'{}')
        os.utime(other, (2000000000, 2000000000))
        with patch.object(self.tool.winreg, 'OpenKey', return_value=Mock(__enter__=Mock(return_value=Mock()),
                                                                     __exit__=Mock(return_value=False))), \
                patch.object(self.tool.winreg, 'QueryValueEx', return_value=(123, 4)):
            self.assertEqual(self.tool.accounts(self.steam)[0], self.shortcut)

    def test_loginusers_most_recent_account_without_existing_shortcuts(self):
        file(self.steam/'userdata'/'456'/'config'/'localconfig.vdf', b'{}')
        text = '"users" { "76561197960265851" { "MostRecent" "1" } "76561197960266184" { "MostRecent" "0" } }'
        file(self.steam/'config'/'loginusers.vdf', text.encode())
        self.assertEqual(self.tool.accounts(self.steam)[0], self.shortcut)

    def test_defaults_include_both_entries_artwork_and_desktop(self):
        with patch.object(sys, 'argv', ['install', '--no-log']), \
                patch.object(self.install, 'deploy', return_value=0) as deploy:
            self.assertEqual(self.install.main(), 0)
        args = deploy.call_args.args[0]
        self.assertTrue(args.last_world and args.artwork and args.desktop)


class UnifiedLogTests(unittest.TestCase):
    def setUp(self):
        import install_log
        self.log = install_log
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root/'install.log'
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        for replacement in (patch.object(self.log, 'DEFAULT_LOG', self.path),
                            contextlib.redirect_stdout(self.stdout),
                            contextlib.redirect_stderr(self.stderr)):
            replacement.__enter__()
            self.addCleanup(replacement.__exit__, None, None, None)

    def test_single_log_absorbs_legacy_and_captures_both_streams_warn_and_exit_code(self):
        file(self.root/'gui.log', b'old GUI failure')
        file(self.root/'history.tsv', b'old exit history')
        with self.log.run('install', []) as run:
            print('normal output')
            print('error output', file=sys.stderr)
            self.log.warn('refused game session')
            with self.log.run('nested worker', []) as worker:
                self.assertIs(worker, run)
                print('one copy only')
                worker.code = 2
        self.assertEqual(list(self.root.iterdir()), [self.path])
        text = self.path.read_text('utf-8')
        self.assertIn('old GUI failure', text)
        self.assertIn('old exit history', text)
        self.assertIn('error output', text)
        self.assertIn('WARN', text)
        self.assertIn('code=2', text)
        self.assertIn('result=incomplete', text)
        self.assertEqual(text.count('one copy only'), 1)
        self.assertEqual(text.count(self.log.MARKER), 1)

    def test_exception_traceback_and_latest_run_copy(self):
        with self.log.run('older run', []):
            print('old detail')
        with self.assertRaisesRegex(ValueError, 'diagnostic detail'):
            with self.log.run('new run', []):
                raise ValueError('diagnostic detail')
        latest = self.log.latest_text(self.path)
        self.assertNotIn('old detail', latest)
        self.assertIn('Traceback', latest)
        self.assertIn('diagnostic detail', latest)
        self.assertIn('code=1', latest)

    def test_no_log_does_not_create_logs_even_under_pythonw(self):
        with patch.object(sys, 'stdout', None), patch.object(sys, 'stderr', None):
            with self.log.run('disabled', [], enabled=False):
                with self.log.run('nested', []):
                    print('discarded')
                with self.assertRaisesRegex(OSError, 'disabled'):
                    self.log.latest_text()
        self.assertFalse(self.path.exists())

    @unittest.skipUnless(sys.platform == 'win32', 'Windows launcher')
    def test_gui_bootstrap_and_import_failure_are_in_the_same_log(self):
        import steam_gui
        import ensure_deps
        with patch.object(ensure_deps, 'bootstrap', side_effect=lambda: print('dependency status')), \
                patch.object(steam_gui, 'load_tool', side_effect=ImportError('tool import failed')):
            with self.assertRaises(ImportError):
                steam_gui.launch('install_to_steam', [])
        text = self.path.read_text('utf-8')
        self.assertIn('dependency status', text)
        self.assertIn('tool import failed', text)
        self.assertIn('Traceback', text)

    @unittest.skipUnless(sys.platform == 'win32', 'Windows launcher')
    def test_copy_log_copies_only_current_run(self):
        import steam_gui
        with self.log.run('old', []):
            print('old output')
        with self.log.run('current', []):
            print('copy this output')
            app = steam_gui.App(None, [], 'Test')
            app.root = Mock()
            app.note = Mock()
            app.copy_log()
            copied = app.root.clipboard_append.call_args.args[0]
            self.assertIn('copy this output', copied)
            self.assertNotIn('old output', copied)


if __name__ == '__main__':
    unittest.main()
