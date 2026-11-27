# SPDX-License-Identifier: 0BSD
"""Negative controls for experiment validity; no game, captures or saved worlds."""
import io
import hashlib
import json
import struct
import unittest
from PIL import Image
from analyze_vegetation_lab import contrast, packet, paired_windows, summarize, temporal
from run_vegetation_lab import PLAN, configurations


def fixture():
    paths=['hold','strafe','approach_turn']
    rows=[]
    for case in ('reference','reference_repeat'):
        for path in paths:
            rows.append(dict(case=case,path=path,hashes=['same']*32,
                             frames=[dict(frame=i,samples=[.4+(i%2)*.01]*12) for i in range(32)]))
    return dict(fixture_valid=True,failures=0,rows=rows,cost=[],
                near_parity=dict(filtered_candidate=True,filtered_optimized=True),
                field=dict(grass_changed_pixels=200,anchors=[[0,0,0]]*12,distance_isolated=True),
                matrix=dict(paths=paths,cases=[dict(id='reference',parent=None,question='control',change={})]))


class LabControls(unittest.TestCase):
    def test_paired_cost_retains_overlap_and_missing_monitor_uncertainty(self):
        report=dict(cost_settings=dict(order='ABBA'),cost=[dict(case=name,start_unix_s=100+i*10,end_unix_s=109+i*10,
                    gpu_ms=[cost]*16,cpu_ms=[1]*16,draws=[100]*16) for i,(name,cost) in enumerate(zip(['a','b','b','a'],[5,6,6,5]))])
        self.assertIsNone(paired_windows(report,None)[0]['other_job_observed_near_window'])
        witness=dict(monitor_started_unix_s=90,monitor_error=None,observations=[dict(seconds=7,jobs=['other'])])
        row=paired_windows(report,witness)[0]
        self.assertTrue(row['other_job_observed_near_window'])
        self.assertEqual(row['gpu_ms']['delta_median'],1)
        report['cost'][2]['case']='a'
        with self.assertRaises(ValueError):paired_windows(report,witness)

    def test_matrix_changes_one_factor_and_separates_coarsening(self):
        plan=json.loads(PLAN.read_text());resolved=configurations(plan)
        self.assertEqual(len(resolved),67)
        for kind in ('stone','flower'):
            for control in ('removed','no_specular','flat_color','no_fade','unlit','fixed_low'):
                case=resolved[kind+'_'+control]
                self.assertEqual([k for k in case if case[k]!=resolved['fern_cluster'][k]],['detail_probe'])
        for suffix in ('06','045'):
            opaque,filtered=resolved['opaque_'+suffix],resolved['filtered_'+suffix]
            self.assertEqual([k for k in opaque if opaque[k]!=filtered[k]],['coverage'])
        plan['cases'][1]['change']['wind']=False
        with self.assertRaises(ValueError):configurations(plan)

    def test_unrepeatable_baseline_invalidates_declared_pass(self):
        data=fixture();self.assertTrue(summarize(data)['fixture_valid'])
        data['rows'][-1]['hashes'][15]='noise'
        self.assertFalse(summarize(data)['fixture_valid'])

    def test_empty_field_and_changed_near_view_are_rejected(self):
        for mutation in ('field','near','occlusion'):
            data=fixture()
            if mutation=='field':data['field']['grass_changed_pixels']=0
            elif mutation=='occlusion':data['field']['distance_isolated']=False
            else:data['near_parity']['filtered_optimized']=False
            self.assertFalse(summarize(data)['fixture_valid'])

    def test_missing_frames_or_anchor_identity_are_rejected(self):
        row=fixture()['rows'][0]
        row['frames'][15]['frame']=14
        with self.assertRaises(ValueError):temporal(row)
        row=fixture()['rows'][0];row['frames'][15]['samples'].pop()
        with self.assertRaises(ValueError):temporal(row)
        for value in (-0.1,1.1,float('nan')):
            row=fixture()['rows'][0];row['frames'][15]['samples'][0]=value
            with self.assertRaises(ValueError):temporal(row)
        data=fixture();data['rows'][0]['frames'][15]['samples'][0]=1.1
        self.assertFalse(summarize(data)['fixture_valid'])

    def test_brightness_change_is_not_hidden_by_zero_temporal_noise(self):
        dark=contrast(Image.new('RGB',(16,16),(80,80,80)))
        bright=contrast(Image.new('RGB',(16,16),(160,160,160)))
        self.assertEqual(dark['dark_outliers'],bright['dark_outliers'])
        self.assertGreater(bright['mean_display_luma'],dark['mean_display_luma']*1.9)
        result=summarize(fixture())
        self.assertFalse(result['production_promotion']);self.assertFalse(result['human_approved'])

    def test_truncated_capture_cannot_be_reported_as_valid(self):
        metadata=json.dumps(dict(case='reference',path='hold',frame=0)).encode()
        stream=io.BytesIO();Image.new('RGB',(320,128)).save(stream,format='WEBP',lossless=True)
        image=stream.getvalue();data=struct.pack('<I',len(metadata))+metadata+struct.pack('<I',len(image))+image
        self.assertEqual(len(list(packet(data))),1)
        with self.assertRaises(ValueError):list(packet(data[:-1]))

    def test_pixel_hash_rejects_encoding_damage(self):
        original=Image.new('RGB',(320,128),(10,20,30))
        metadata=json.dumps(dict(case='reference',path='hold',frame=0,rgb_sha256=hashlib.sha256(original.tobytes()).hexdigest())).encode()
        for changed in (False,True):
            frame=original.copy()
            if changed:frame.putpixel((100,50),(255,255,255))
            stream=io.BytesIO();frame.save(stream,format='PNG');payload=stream.getvalue()
            data=struct.pack('<I',len(metadata))+metadata+struct.pack('<I',len(payload))+payload
            if changed:
                with self.assertRaises(ValueError):list(packet(data))
            else:self.assertEqual(len(list(packet(data))),1)

    def test_species_samples_require_visible_distance_isolation(self):
        data=fixture();data['rows'][0]['stone_frames']=data['rows'][0]['frames']
        data['stone_field']=dict(distance_isolated=True,plants=4,anchors=[[0,0,0]]*12)
        self.assertTrue(summarize(data)['fixture_valid'])
        data['stone_field']['distance_isolated']=False
        self.assertFalse(summarize(data)['fixture_valid'])


if __name__=='__main__':unittest.main()
