// SPDX-License-Identifier: 0BSD
// Shared by ordinary world publication and the offline binary inspector.
#include "world_archive.hpp"
#include "world_recipe.hpp"
#include "generated_region.hpp"
#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;
namespace terraforest {
class NativeGeneratedWorldVerifier : public RefCounted {
    GDCLASS(NativeGeneratedWorldVerifier,RefCounted)
    static Dictionary failure(const String &reason){Dictionary out;out["ok"]=false;out["reason"]=reason;return out;}
    static Ref<RefCounted> owner(const char *name){
        const Variant value=ClassDBSingleton::get_singleton()->instantiate(name);
        return Ref<RefCounted>(Object::cast_to<RefCounted>(static_cast<Object*>(value)));
    }
    static String digest(const PackedByteArray &bytes){
        Ref<HashingContext> hash;hash.instantiate();
        if(hash->start(HashingContext::HASH_SHA256)!=OK||(!bytes.is_empty()&&hash->update(bytes)!=OK))return String();
        return hash->finish().hex_encode();
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("verify","path","seed","generator","options"),&NativeGeneratedWorldVerifier::verify,DEFVAL(Dictionary()));
        ClassDB::bind_method(D_METHOD("inspect","path"),&NativeGeneratedWorldVerifier::inspect);
    }
public:
    Dictionary inspect(const String &path) const {
        Ref<NativeWorldArchive> raw;raw.instantiate();const auto decoded=raw->decode(raw->read(path));
        if(!bool(decoded.get("ok",false)))return failure("Generated world root is invalid");
        const Dictionary sections=decoded["sections"];
        Ref<NativeGeneratedRegion> region;region.instantiate();
        if(!region->restore_snapshot(sections.get("generated_region",PackedByteArray())))return failure("Generated location metadata is invalid");
        const Dictionary plan=region->get_plan();
        if(!bool(plan.get("present",false)))return failure("This root has no supported generated-region identity");
        Ref<NativeWorldRecipe> recipe;recipe.instantiate();
        const PackedByteArray data=sections.get("world_recipe_v1",PackedByteArray());
        if(!recipe->validate_snapshot(data))return failure("Generated world recipe is invalid");
        return verify(path,plan["seed"],plan["generator"],recipe->decode(data));
    }
    Dictionary verify(const String &path,int64_t seed,int generator,const Dictionary &options=Dictionary()) const {
        const uint64_t began=Time::get_singleton()->get_ticks_usec();
        Ref<NativeWorldArchive> raw;raw.instantiate();const PackedByteArray canonical=raw->read(path);const auto decoded=raw->decode(canonical);
        if(!bool(decoded.get("ok",false)))return failure("Generated world root is invalid");
        const Dictionary sections=decoded["sections"];
        auto originals=owner("NativeLocationBaselineStore");
        if(originals.is_null()||!bool(originals->call("configure_world",path,true))||!bool(originals->call("restore_storage_snapshot",sections.get("location_baselines_v1",PackedByteArray())))||!bool(Dictionary(originals->call("verify_references")).get("ok",false)))return failure("Generated location originals are missing or invalid");
        Ref<NativeWorldRecipe> recipe;recipe.instantiate();
        if(sections.has("world_recipe_v1")&&!recipe->validate_snapshot(sections["world_recipe_v1"]))return failure("Generated world recipe is invalid");
        if(!options.is_empty()&&PackedByteArray(sections.get("world_recipe_v1",PackedByteArray()))!=recipe->encode(options))return failure("Generated world recipe differs from requested settings");
        Ref<NativeGeneratedRegion> minerals;minerals.instantiate();
        if(!minerals->restore_snapshot(sections.get("material_deposits_v1",PackedByteArray())))return failure("Material deposit metadata is invalid");
        const Dictionary mineral_plan=minerals->get_plan();
        if(int64_t(options.get("material_veins",0))==1&&(!bool(mineral_plan.get("present",false))||int64_t(mineral_plan.get("seed",-1))!=seed||int(mineral_plan.get("generator",-1))!=generator||Array(mineral_plan.get("places",Array())).is_empty()))return failure("Material deposits are missing or belong to another world");
        for(const char *name:{"terrain","structures","generated_region","volumetric_water"})if(!sections.has(name))return failure(String("Generated world is missing ")+name);
        Ref<NativeGeneratedRegion> region;region.instantiate();
        if(!region->restore_snapshot(sections["generated_region"]))return failure("Generated location metadata is invalid");
        const Dictionary plan=region->get_plan();
        if(!bool(plan.get("present",false))||int64_t(plan.get("seed",-1))!=seed||int(plan.get("generator",-1))!=generator)return failure("Generated location metadata belongs to another world");
        auto codec=owner("NativeStructuresSnapshot"),archive=owner("NativeRegionWorldArchive");
        if(codec.is_null()||archive.is_null())return failure("Native structure storage codec is unavailable");
        Dictionary reference=codec->call("inspect_reference",sections["structures"]);
        const bool regional=reference.get("ok",false);
        if(!regional)reference=codec->call("inspect_resident",sections["structures"]);
        if(!bool(reference.get("ok",false)))return failure("Generated building reference is invalid");
        const Array keys=Dictionary(reference["models"]).keys();PackedStringArray assets;
        for(int i=0;i<keys.size();i++)assets.push_back(keys[i]);
        // Generated regional worlds already own these stores. Verification must
        // never create missing companions just to attempt opening a corrupt save.
        if((regional&&!DirAccess::dir_exists_absolute(path+String(".regions")))||!DirAccess::dir_exists_absolute(path+String(".terrain"))||!DirAccess::dir_exists_absolute(path+String(".water")))return failure("Generated companion storage is missing");
        if(!bool(codec->call("configure_assets",assets)))return failure("Generated building schema is invalid");
        if(regional?(!bool(archive->call("configure",raw,codec))||!bool(archive->call("acquire",path))):!raw->acquire(path))return failure("Generated building storage is unavailable or in use");
        if(raw->read(path)!=canonical)return failure("Generated world changed before verification acquired ownership");
        auto terrain=owner("NativeTerrainRegionStore");
        if(terrain.is_null()||!bool(terrain->call("open_store",path+String(".terrain"))))return failure("Generated terrain storage is unavailable");
        const Dictionary field=terrain->call("verify_snapshot",sections["terrain"]);terrain->call("close");
        if(!bool(field.get("ok",false))||int64_t(field.get("seed",-1))!=seed||int(field.get("generator",-1))!=generator)return failure("Generated terrain checkpoint or identity is invalid");
        const bool buildings_ok=regional?bool(Dictionary(archive->call("decode",canonical)).get("ok",false)):bool(codec->call("validate_snapshot",sections["structures"]));
        if(!buildings_ok)return failure("Generated building region is missing or damaged");
        auto water=owner("NativeWaterRegionStore");
        if(water.is_null()||!bool(water->call("open_store",path+String(".water"))))return failure("Generated water storage is unavailable");
        const PackedByteArray expanded=water->call("expand_water_snapshot",sections["volumetric_water"]);water->call("close");
        if(expanded.is_empty())return failure("Generated water checkpoint is missing or damaged");
        if(regional)archive->call("release");else raw->release();
        Dictionary hashes,sizes;const Array names=sections.keys();
        for(int i=0;i<names.size();i++){const String name=names[i];const PackedByteArray bytes=sections[name];hashes[name]=digest(bytes);sizes[name]=bytes.size();}
        Dictionary out;out["ok"]=true;out["root_digest"]=digest(canonical);out["section_digests"]=hashes;out["section_bytes"]=sizes;out["root_bytes"]=canonical.size();out["terrain"]=field;out["model_assets"]=assets.size();out["places"]=Array(plan["places"]).size();out["roads"]=Array(plan["roads"]).size();out["milliseconds"]=(Time::get_singleton()->get_ticks_usec()-began)/1000.0;out["scope"]="Native binary integrity and saved identity; visual and traversal qualification run separately.";return out;
    }
};
void register_generated_world_verifier(){GDREGISTER_CLASS(NativeGeneratedWorldVerifier);}
}
