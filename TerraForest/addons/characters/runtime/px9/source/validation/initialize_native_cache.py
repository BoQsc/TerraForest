#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Initialize Godot cache with valid tangent settings for original solid-color hairs."""
from pathlib import Path
import argparse,hashlib,json,re,struct,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--package',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();root=a.package.resolve()
files=('Human.r11.glb','Human.px9_eclipse.glb','PX9_Eclipse_FP.glb','PX9_Eclipse_FP_RestSpace.glb')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={n:sha(root/n)for n in files};start=time.monotonic()
d=(root/'Human.r11.glb').read_bytes();length,kind=struct.unpack_from('<II',d,12);assert kind==0x4e4f534a;doc=json.loads(d[20:20+length]);uvless=[];textured=[]
def contains_texture(value):
 if isinstance(value,dict):return any('texture'in key.lower()or contains_texture(item)for key,item in value.items())
 if isinstance(value,list):return any(contains_texture(item)for item in value)
 return False
for mesh in doc['meshes']:
 for primitive in mesh['primitives']:
  attributes=primitive['attributes']
  if'TEXCOORD_0'not in attributes:
   material=doc['materials'][primitive['material']]if'material'in primitive else{}
   uvless.append({'mesh':mesh.get('name'),'material':material.get('name'),'material_has_texture':contains_texture(material)})
  else:textured.append('TANGENT'in attributes)
eligible=before['Human.r11.glb']=='0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8'and bool(uvless)and not any(row['material_has_texture']for row in uvless)and all(textured)
adjustments=[]
def adjust_generated_import_setting():
 path=root/'Human.r11.glb.import'
 if not eligible or not path.is_file():return False
 text=path.read_text()
 if'meshes/ensure_tangents=true'not in text:return False
 old=sha(path);path.write_text(text.replace('meshes/ensure_tangents=true','meshes/ensure_tangents=false'))
 adjustments.append({'path':'Human.r11.glb.import','setting':'meshes/ensure_tangents','before':True,'after':False,'before_sha256':old,'after_sha256':sha(path),'scope':'Generated preview/editor cache setting only. Source GLB and its existing tangent attributes are unchanged. UV-less original brow/lash surfaces use solid-color material without texture.'})
 return True
adjust_generated_import_setting();attempts=[]
for attempt in range(2):
 done=subprocess.run(['godot','--headless','--editor','--path',str(root),'--import'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=1800)
 print(done.stdout,flush=True)
 errors=[line for line in done.stdout.splitlines()if'ERROR:'in line or'SCRIPT ERROR'in line or'Parse Error'in line]
 attempts.append({'returncode':done.returncode,'reported_errors':errors})
 if attempt==0 and errors and all(line=='ERROR: UVs are required to generate tangents.'for line in errors)and adjust_generated_import_setting():continue
 break
remaps=[]
for name in files:
 imp=root/(name+'.import');entry={'source':name,'import_exists':imp.is_file()}
 if imp.is_file():
  match=re.search(r'^path="([^"]+)"',imp.read_text(),re.MULTILINE);entry['cache_resource']=match.group(1)if match else None
  path=root/entry['cache_resource'][6:]if entry['cache_resource']and entry['cache_resource'].startswith('res://')else None
  entry['cache_exists']=path.is_file()if path else False;entry['cache_bytes']=path.stat().st_size if path and path.is_file()else 0
 remaps.append(entry)
checks={'editor_import_exit_zero':done.returncode==0,'no_reported_import_script_errors':not errors,'all_required_glb_remaps_present':all(row.get('cache_exists')and row.get('cache_bytes',0)>0 for row in remaps),'input_glb_bytes_unchanged':before=={n:sha(root/n)for n in files}}
report={'schema':'px9-godot-cache-initialization-2','passed':all(checks.values()),'checks':checks,'seconds':time.monotonic()-start,'returncode':done.returncode,'source_hashes':before,'remaps':remaps,'errors':errors,'attempts':attempts,'original_human_uvless_material_evidence':uvless,'original_human_all_uv_primitives_already_have_tangents':all(textured),'cache_configuration_adjustments':adjustments,'scope':'Headless editor import before native animation-library generation. Only generated import settings may change; all source GLBs remain exact. Cache files are intermediate and excluded from delivery.'}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2),flush=True)
raise SystemExit(0 if report['passed']else 1)
