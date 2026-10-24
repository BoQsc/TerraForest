"""Exercise Windows PowerShell with a real GUI-subsystem executable."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'nt' and shutil.which('powershell'), 'Windows PowerShell required')
class WorldsLauncherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='worlds launcher ')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.project = Path(cls.temporary.name).resolve()
        (cls.project/'tools').mkdir()
        shutil.copy2(ROOT/'tools/start_worlds.ps1', cls.project/'tools/start_worlds.ps1')
        shutil.copy2(ROOT/'Worlds.cmd', cls.project/'Worlds.cmd')
        cls.engine = cls.project/'Godot Engine.exe'
        source = cls.project/'Engine.cs'
        source.write_text('''using System;
using System.IO;
using System.Threading;
class Engine {
    static int Main(string[] arguments) {
        Thread.Sleep(250);
        bool icons = Array.IndexOf(arguments, "--headless") >= 0;
        string phase = icons ? "icons" : "game";
        File.AppendAllText(Environment.GetEnvironmentVariable("WORLD_TEST_TRACE"), phase + "\\n" + String.Join("\\n", arguments) + "\\n");
        Console.WriteLine("GUI_COMPLETED " + phase);
        return Int32.Parse(Environment.GetEnvironmentVariable(icons ? "WORLD_TEST_ICON_EXIT" : "WORLD_TEST_GAME_EXIT"));
    }
}
''', encoding='utf-8')
        command = f"Add-Type -TypeDefinition ([IO.File]::ReadAllText('{source}')) -OutputAssembly '{cls.engine}' -OutputType WindowsApplication"
        subprocess.run(['powershell', '-NoProfile', '-Command', command], check=True, capture_output=True, text=True, timeout=30)

    def launch(self, icon_exit=0, game_exit=0, check_only=False, batch=False):
        trace = self.project/(self._testMethodName+'.trace')
        environment = dict(os.environ, WORLD_TEST_TRACE=str(trace), WORLD_TEST_ICON_EXIT=str(icon_exit), WORLD_TEST_GAME_EXIT=str(game_exit))
        command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(self.project/'tools/start_worlds.ps1'), '-Godot', str(self.engine)]
        if check_only:
            command.append('-CheckOnly')
        if batch:
            command = f'cmd /d /s /c ""{self.project / "Worlds.cmd"}" -Godot "{self.engine}""'
        result = subprocess.run(command, input='\n', capture_output=True, text=True, env=environment, cwd=self.project, timeout=15)
        return result, trace.read_text() if trace.exists() else ''

    def test_check_only_does_not_start_engine(self):
        result, trace = self.launch(check_only=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(self.engine), result.stdout)
        self.assertEqual(trace, '')

    def test_batch_waits_for_both_gui_processes(self):
        result, trace = self.launch(batch=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('GUI_COMPLETED icons', result.stdout)
        self.assertIn('GUI_COMPLETED game', result.stdout)
        self.assertLess(trace.index('icons\n'), trace.index('game\n'))
        self.assertIn('--path\n'+str(self.project)+'\n', trace)
        self.assertIn('res://demo/worlds.tscn', trace)
        self.assertIn(str(self.project/'reports/worlds_icons.log'), trace)
        self.assertIn(str(self.project/'reports/worlds_game.log'), trace)

    def test_icon_failure_stops_launch_and_preserves_exit_code(self):
        result, trace = self.launch(icon_exit=3, batch=True)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertNotIn('game\n', trace)
        self.assertIn('Item icon refresh failed (exit 3)', result.stdout)

    def test_game_failure_preserves_exit_code(self):
        result, trace = self.launch(game_exit=7, batch=True)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn('game\n', trace)
        self.assertIn('TerraForest exited with an error (exit 7)', result.stdout)


if __name__ == '__main__':
    unittest.main()
