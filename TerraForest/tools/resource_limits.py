"""Shared development budgets; unavailable telemetry never counts as memory qualification."""
import json
import os
from pathlib import Path
import shutil
import time

ROOT = Path(__file__).resolve().parents[1]


def load_budgets():
    limits = json.loads((ROOT / 'tools/resource_budgets.json').read_text(encoding='utf-8'))
    if limits.get('schema') != 1 or any(type(value) is not int or value < 0 for name, value in limits.items() if name.endswith('_bytes')):
        raise ValueError('Resource budgets require schema 1 and nonnegative integer byte thresholds')
    for name in ['ram', 'vram', 'redistributable']:
        if limits[name + '_warning_bytes'] > limits[name + '_limit_bytes']:
            raise ValueError('Resource warning exceeds limit: ' + name)
    return limits


def evaluate(private_bytes=None, vram_bytes=None, distribution_bytes=None, limits=None):
    limits = limits or load_budgets()
    values = {'ram': private_bytes, 'vram': vram_bytes, 'redistributable': distribution_bytes}
    return {name: {'bytes': value, 'status': 'unavailable' if value is None else
                  ('exceeded' if value > limits[name + '_limit_bytes'] else
                   'warning' if value >= limits[name + '_warning_bytes'] else 'within_budget')}
            for name, value in values.items()}


def require_free_space(path, extra_bytes=0):
    available = shutil.disk_usage(path).free
    required = load_budgets()['minimum_free_bytes'] + extra_bytes
    if available < required:
        raise OSError(f'Low storage: {available / 2**30:.2f} GiB free; need {required / 2**30:.2f} GiB including the safety reserve. Run storage maintenance first.')


def distribution_size(root, pack=None):
    root = Path(root)
    files = [Path(pack) if pack else root / 'TerraForest.pck']
    files.extend(path for path in (root / 'addons').rglob('*') if path.is_file())
    files.extend(path for path in root.iterdir() if path.is_file() and path.suffix.lower() in ('.exe', '.dll'))
    missing = [str(path) for path in files if not path.is_file()]
    if missing:
        raise ValueError('Missing distributable files: ' + ', '.join(missing))
    return sum(path.stat().st_size for path in files)


class ResourceMonitor:
    def __init__(self, pid):
        self.process = None
        self.gpu = None
        self.errors = []
        self.samples = 0
        self.gpu_samples = 0
        self.private_peak = None
        self.working_peak = None
        self.vram_peak = None
        self.next_sample = 0
        self.limits = load_budgets()
        if os.name == 'nt':
            from windows_process_metrics import ProcessMetrics, GpuMemoryMetrics
            for name, factory in [('process', ProcessMetrics), ('gpu', GpuMemoryMetrics)]:
                try:
                    setattr(self, name, factory(pid))
                except OSError as error:
                    self.errors.append(str(error))

    def sample(self):
        if time.monotonic() < self.next_sample:
            return
        self.next_sample = time.monotonic() + .5
        if self.process:
            try:
                row = self.process.sample()
                self.samples += 1
                self.private_peak = max(self.private_peak or 0, row['private_commit_bytes'], row['peak_private_commit_bytes'])
                self.working_peak = max(self.working_peak or 0, row['working_set_bytes'], row['peak_working_set_bytes'])
            except OSError:
                pass
        if self.gpu:
            value = self.gpu.sample()
            if value is not None:
                self.gpu_samples += 1
                self.vram_peak = max(self.vram_peak or 0, value)

    def close(self):
        for reader in [self.process, self.gpu]:
            if reader:
                reader.close()

    def report(self):
        checks = evaluate(self.private_peak, self.vram_peak, limits=self.limits)
        complete = self.samples >= 2 and self.gpu_samples >= 2
        return dict(samples=self.samples, gpu_samples=self.gpu_samples, peak_private_commit_bytes=self.private_peak,
                    peak_working_set_bytes=self.working_peak, peak_dedicated_gpu_bytes=self.vram_peak,
                    checks=checks, limits=self.limits, errors=self.errors,
                    exceeded=any(check['status'] == 'exceeded' for check in checks.values()),
                    telemetry_complete=complete,
                    within_sampled_limits=complete and all(checks[name]['status'] != 'exceeded' for name in ['ram', 'vram']),
                    scope='Process-specific Windows counters, sampled every 0.5 s; driver/instantaneous peaks and other workloads remain unqualified. GPU value sums dedicated allocations across adapters, not whole-device desktop usage.')
