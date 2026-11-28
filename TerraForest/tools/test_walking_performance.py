# SPDX-License-Identifier: 0BSD
"""Negative controls: a single hitch or invalid capture must never pass."""
import unittest
from analyze_walking_performance import analyze


class WalkingGateTests(unittest.TestCase):
    def fixture(self):
        columns = ['frame','end_us','frame_ms','phase','invalid','cap','vsync','recorder_us']
        rows = [[n, (n+1)*10000, 10, 0, 0, 0, 0, 8] for n in range(3000)]
        meta = dict(columns=columns, frames=len(rows), failures=[], overflow=False,
                    pacing='uncapped', diagnostic=False, requested_seconds=30,
                    presentation=dict(viewport=[1920,1080], render_scale=1, headless=False),
                    travelled_m=100, phases=[dict(id=0, label='walk', first=0, end=len(rows))])
        return meta, rows

    def test_clean_route(self):
        self.assertTrue(analyze(*self.fixture())['capacity_qualification_pass'])

    def test_one_hitch_is_critical_even_with_excellent_p99(self):
        meta, rows = self.fixture()
        rows[-1][2] = 50;rows[-1][1] += 40000
        result = analyze(meta, rows)
        self.assertTrue(result['valid'])
        self.assertEqual(result['critical_frames'], 1)
        self.assertEqual(result['cadence_ms']['p99'], 10)
        self.assertFalse(result['capacity_qualification_pass'])

    def test_61_budget_and_headroom_are_stricter_than_60(self):
        for value in (14, 16.5):
            meta, rows = self.fixture()
            rows[-1][2] = value;rows[-1][1] += (value-10)*1000
            result = analyze(meta, rows)
            self.assertEqual(result['critical_frames'], 0)
            self.assertFalse(result['capacity_qualification_pass'])
            self.assertEqual(result['route_61fps_pass'], value < 16)

    def test_invalid_or_missing_data_cannot_pass(self):
        for change in ('overflow','death','gap','cap','duration','phase'):
            meta, rows = self.fixture()
            if change == 'overflow':meta['overflow'] = True
            if change == 'death':rows[5][4] = 1
            if change == 'gap':rows[5][0] += 2
            if change == 'cap':rows[5][5] = 60
            if change == 'duration':meta['requested_seconds'] = 60
            if change == 'phase':meta['phases'][0]['end'] -= 1
            result = analyze(meta, rows)
            self.assertFalse(result['valid'], change)
            self.assertFalse(result['capacity_qualification_pass'], change)

    def test_nan_is_rejected(self):
        meta, rows = self.fixture();rows[3][2] = float('nan')
        with self.assertRaises(ValueError):analyze(meta, rows)

    def test_resolution_and_clock_corruption_are_rejected(self):
        meta, rows = self.fixture();meta['presentation']['render_scale'] = .5
        self.assertFalse(analyze(meta, rows)['valid'])
        meta, rows = self.fixture();rows[100][1] += 1000
        self.assertFalse(analyze(meta, rows)['valid'])

    def test_diagnostics_cannot_qualify_capacity(self):
        meta, rows = self.fixture();meta['diagnostic'] = True
        self.assertFalse(analyze(meta, rows)['capacity_qualification_pass'])


if __name__ == '__main__':
    unittest.main()
