# SPDX-License-Identifier: 0BSD
extends RefCounted
# Worker orchestration only. Native codecs validate binary fields/checkpoints;
# creating a world never launches another rendered game to verify its storage.
const Survey=preload("res://addons/world_runtime/survey_cache.gd")
static func verify(path:String,seed_value:int,generator:int,options:Dictionary={})->Dictionary:
 var began:=Time.get_ticks_usec()
 var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
 var canonical:PackedByteArray=raw.read(path)
 var decoded:Dictionary=raw.decode(canonical)
 if not decoded.get("ok",false):return {"ok":false,"reason":"Generated world root is invalid"}
 var sections:Dictionary=decoded.sections
 var recipe:RefCounted=ClassDB.instantiate("NativeWorldRecipe")
 if sections.has("world_recipe_v1") and not recipe.validate_snapshot(sections.world_recipe_v1):return {"ok":false,"reason":"Generated world recipe is invalid"}
 if not options.is_empty() and sections.get("world_recipe_v1",PackedByteArray())!=recipe.encode(options):return {"ok":false,"reason":"Generated world recipe differs from requested settings"}
 for required:String in ["terrain","structures","generated_region","volumetric_water"]:
  if not sections.has(required):return {"ok":false,"reason":"Generated world is missing "+required}
 var region:RefCounted=ClassDB.instantiate("NativeGeneratedRegion")
 if not region.restore_snapshot(sections.generated_region):return {"ok":false,"reason":"Generated location metadata is invalid"}
 var plan:Dictionary=region.get_plan()
 if not plan.get("present",false) or plan.seed!=seed_value or plan.generator!=generator:return {"ok":false,"reason":"Generated location metadata belongs to another world"}
 var inspector:RefCounted=ClassDB.instantiate("NativeStructuresSnapshot")
 var reference:Dictionary=inspector.inspect_reference(sections.structures)
 if not reference.get("ok",false):return {"ok":false,"reason":"Generated building reference is invalid"}
 var assets:=PackedStringArray(reference.models.keys())
 var codec:RefCounted=ClassDB.instantiate("NativeStructuresSnapshot")
 var archive:RefCounted=ClassDB.instantiate("NativeRegionWorldArchive")
 if not codec.configure_assets(assets) or not archive.configure(raw,codec) or not archive.acquire(path):return {"ok":false,"reason":"Generated building storage is unavailable or in use"}
 if raw.read(path)!=canonical:return {"ok":false,"reason":"Generated world changed before verification acquired ownership"}
 var terrain:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
 if not terrain.open_store(path+".terrain"):return {"ok":false,"reason":"Generated terrain storage is unavailable"}
 var field:Dictionary=terrain.verify_snapshot(sections.terrain);terrain.close()
 if not field.get("ok",false) or field.seed!=seed_value or field.generator!=generator:return {"ok":false,"reason":"Generated terrain checkpoint or identity is invalid"}
 # Full native checkpoint decoding checks every referenced building/model region.
 # This is storage validation, independent of visual/traversal acceptance.
 var restored:Dictionary=archive.decode(canonical)
 if not restored.get("ok",false):return {"ok":false,"reason":"Generated building region is missing or damaged"}
 var water:RefCounted=ClassDB.instantiate("NativeWaterRegionStore")
 if not DirAccess.dir_exists_absolute(path+".water") or not water.open_store(path+".water"):return {"ok":false,"reason":"Generated water storage is unavailable"}
 var expanded:PackedByteArray=water.expand_water_snapshot(sections.volumetric_water);water.close()
 if expanded.is_empty():return {"ok":false,"reason":"Generated water checkpoint is missing or damaged"}
 archive.release()
 var hashes:Dictionary={};var sizes:Dictionary={}
 for name:String in sections:
  hashes[name]=Survey.digest(sections[name]).hex_encode();sizes[name]=sections[name].size()
 return {"ok":true,"root_digest":Survey.digest(canonical).hex_encode(),"section_digests":hashes,"section_bytes":sizes,"root_bytes":canonical.size(),"terrain":field,"model_assets":assets.size(),"places":plan.places.size(),"roads":plan.roads.size(),"milliseconds":(Time.get_ticks_usec()-began)/1000.0,"scope":"Native binary integrity and saved identity; visual and traversal qualification run separately."}
