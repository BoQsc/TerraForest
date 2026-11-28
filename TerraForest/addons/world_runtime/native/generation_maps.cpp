// SPDX-License-Identifier: 0BSD
// Fresh-world cartography: owner-thread native source batches, then immutable
// rasters/terrain queries on one worker. No per-region or per-query frame waits.
#include "surface_map_raster.hpp"
#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/object.hpp>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>

using namespace godot;
namespace terraforest {
class NativeGenerationMaps : public RefCounted {
    GDCLASS(NativeGenerationMaps,RefCounted)
    struct Model {String name;uint64_t owner=0;Dictionary index;};
    uint64_t game_id=0,terrain_id=0,blocks_id=0,began=0,source_us=0,worker_us=0,max_advance_us=0;
    int64_t epoch=0,revision=0,block_revision=0,water_revision=0;
    Ref<RefCounted> core,water;
    Ref<Thread> worker;
    Ref<NativeSurfaceMapRaster> rasters[3];
    PackedByteArray base_pixels,pixels[3];
    Dictionary block_index,result;
    std::vector<Model> models;
    std::vector<Vector2i> tiles;
    int phase=0,model_cursor=0,region_cursor=0;
    int64_t chunk_cursor=0,after_id=0,water_cursor=0,ocean_cursor=0;
    Array boxes;Vector2i projection;
    bool ocean_done=false,region_done=false,attempted=false,admitted=false,done=false,started_worker=false;
    std::atomic<bool> stop{false},ready{false};
    std::atomic<int> patches{0},visibility_calls{0};
    int source_calls[3]{};
    String rejection,save_path,save_slot,cache_identity;
    Ref<RefCounted> archive;bool publishing=false;uint64_t publish_us=0;
    static uint64_t now(){return Time::get_singleton()->get_ticks_usec();}
    static Object *member(Object *object,const char *name){return object?static_cast<Object*>(object->get(name)):nullptr;}
    static bool resident(const Dictionary &index){
        const PackedInt32Array keys=index.get("keys",PackedInt32Array());
        const PackedByteArray sums=index.get("checksums",PackedByteArray());
        if(keys.size()%3||keys.size()/3>65536||sums.size()!=keys.size()/3*32)return false;
        for(int i=0;i<sums.size();++i)if(sums[i])return false;
        return true;
    }
    static Transform3D frame(Object *owner){auto *node=Object::cast_to<Node3D>(owner);return node->is_inside_tree()?node->get_global_transform():node->get_transform();}
    bool field_current() const {
        PackedByteArray packet;packet.resize(4);packet.encode_u32(0,0);
        PackedByteArray reply=core->call("execute",packet);
        return reply.size()>=16&&reply.decode_u32(0)==0x32505254&&reply.decode_u32(8)==0&&reply.decode_u32(12)==uint64_t(revision);
    }
    bool current() const {
        auto *game=ObjectDB::get_instance(game_id),*terrain=ObjectDB::get_instance(terrain_id),*blocks=ObjectDB::get_instance(blocks_id);
        if(!game||!terrain||!blocks||bool(game->get("shutdown_requested"))||!bool(terrain->get("world_ready"))||
           !bool(terrain->get("diagnostics_pause_streaming"))||bool(terrain->get("pending_edit"))||bool(terrain->get("stopping"))||
           int64_t(terrain->get("epoch"))!=epoch||int64_t(terrain->get("density_revision"))!=revision||
           int64_t(blocks->call("survey_content_revision_id"))!=block_revision||int64_t(water->call("survey_revision_id"))!=water_revision)return false;
        if(frame(blocks)!=Transform3D(block_index["transform"]))return false;
        for(const auto &model:models){auto *owner=ObjectDB::get_instance(model.owner);if(!owner||int64_t(owner->call("survey_revision_id"))!=int64_t(model.index["revision"])||frame(owner)!=Transform3D(model.index["transform"])||AABB(owner->call("survey_prototype_bounds"))!=AABB(model.index["prototype_bounds"]))return false;}
        return true;
    }
    void join(){if(worker.is_valid()&&worker->is_started())worker->wait_to_finish();worker.unref();}
    void finish(bool ok,const String &reason=String()){
        stop.store(true);join();done=true;
        result["ok"]=ok;result["reason"]=reason;
        Dictionary cost;cost["source_us"]=int64_t(source_us);cost["worker_us"]=int64_t(worker_us);cost["total_us"]=int64_t(now()-began);cost["max_advance_us"]=int64_t(max_advance_us);
        cost["publish_us"]=int64_t(publish_us);cost["patches"]=patches.load();cost["visibility_calls"]=visibility_calls.load();
        PackedInt32Array counts;for(int count:source_calls)counts.push_back(count);cost["source_calls"]=counts;result["profile"]=cost;
    }
    bool offer(int layer,const Dictionary &part,const Transform3D &frame=Transform3D()){
        if(!bool(part.get("ok",false))||bool(part.get("stale",false))||!bool(part.get("ready",true)))return false;
        PackedVector3Array points=part.get("points",PackedVector3Array());
        for(int i=0;i<points.size();++i)points.set(i,frame.xform(points[i]));
        ++source_calls[layer];return rasters[layer]->offer(points,part.get("colors",PackedColorArray()));
    }
    bool source_step(){
        if(phase==1){
            const PackedInt32Array keys=block_index["keys"];
            if(region_cursor>=keys.size()/3){phase=2;region_cursor=0;return true;}
            auto *blocks=ObjectDB::get_instance(blocks_id);if(!blocks)return false;
            Vector3i key(keys[region_cursor*3],keys[region_cursor*3+1],keys[region_cursor*3+2]);
            const Dictionary part=blocks->call("survey_columns",key,chunk_cursor,block_index["revision"]);
            if(!offer(1,part,block_index["transform"]))return false;
            chunk_cursor=part["offset"];if(bool(part["complete"])){++region_cursor;chunk_cursor=0;}return true;
        }
        if(phase==2){
            if(model_cursor>=int(models.size())){phase=3;return true;}
            auto &model=models[model_cursor];const PackedInt32Array keys=model.index["keys"];
            if(region_cursor>=keys.size()/3){++model_cursor;region_cursor=0;after_id=0;return true;}
            if(!boxes.is_empty()){
                Dictionary projected=rasters[2]->project_bounds(boxes,model.index["transform"],projection);
                if(!bool(projected.get("ok",false)))return false;
                Color color=Color::html("898981");
                if(model.name.contains("iron_outcrop"))color=Color::html("78828f");
                else if(model.name.contains("copper_outcrop"))color=Color::html("ad784d");
                else if(model.name.contains("wood")||model.name.contains("door")||model.name.contains("chair")||model.name.contains("chest"))color=Color::html("776044");
                PackedColorArray colors;colors.resize(PackedVector3Array(projected["points"]).size());colors.fill(color);projected["colors"]=colors;
                if(!offer(2,projected))return false;projection=projected["cursor"];
                if(bool(projected["complete"])){boxes.clear();if(region_done){++region_cursor;after_id=0;}}
                return true;
            }
            auto *owner=ObjectDB::get_instance(model.owner);if(!owner)return false;
            Vector3i key(keys[region_cursor*3],keys[region_cursor*3+1],keys[region_cursor*3+2]);
            Dictionary part=owner->call("survey_bounds",key,after_id,model.index["revision"]);
            if(!bool(part.get("ok",false)))return false;
            after_id=part["after_id"];boxes=part["bounds"];projection=Vector2i();region_done=part["complete"];
            if(boxes.is_empty()&&region_done){++region_cursor;after_id=0;}return true;
        }
        return true;
    }
    bool water_step(){
        Dictionary part=ocean_done?Dictionary(water->call("survey_surfaces",water_cursor,water_revision,4)):Dictionary(water->call("survey_ocean",ocean_cursor,water_revision));
        if(!offer(0,part))return false;
        if(ocean_done){water_cursor=part["cursor"];if(bool(part["complete"]))phase=1;}
        else{ocean_cursor=part["cursor"];ocean_done=part["complete"];}
        return true;
    }
    static Ref<RefCounted> instance(const char *name){Variant value=ClassDBSingleton::get_singleton()->instantiate(name);return Ref<RefCounted>(Object::cast_to<RefCounted>(static_cast<Object*>(value)));}
    static PackedByteArray digest(const PackedByteArray &bytes){Ref<HashingContext> hash;hash.instantiate();hash->start(HashingContext::HASH_SHA256);hash->update(bytes);return hash->finish();}
    static bool write_cache(const String &slot,const String &identity,const PackedByteArray &bytes,const String &folder,int limit){
        if(identity.is_empty()||DirAccess::make_dir_recursive_absolute(folder)!=OK)return false;
        const String path=folder.path_join(digest(slot.to_utf8_buffer()).hex_encode()+String(".bin"));
        const String temporary=path+String(".tmp_")+String::num_int64(OS::get_singleton()->get_process_id())+String("_")+String::num_int64(now());
        auto file=FileAccess::open(temporary,FileAccess::WRITE);if(file.is_null())return false;
        auto header=String("TFEDIT01").to_utf8_buffer();header.append_array(digest((String("base=5|")+identity).to_utf8_buffer()));
        PackedByteArray signed_bytes=header;signed_bytes.append_array(bytes);
        file->store_buffer(header);file->store_buffer(digest(signed_bytes));file->store_buffer(bytes);const auto error=file->get_error();file->close();file.unref();
        const bool ok=error==OK&&DirAccess::rename_absolute(temporary,path)==OK;
        if(FileAccess::file_exists(temporary))DirAccess::remove_absolute(temporary);if(!ok)return false;
        struct Entry{String path;uint64_t time;};std::vector<Entry> entries;
        const PackedStringArray names=DirAccess::get_files_at(folder);
        for(int i=0;i<names.size();++i){const String name=names[i],candidate=folder.path_join(name);
            if(name.length()==68&&name.ends_with(".bin")&&name.trim_suffix(".bin").is_valid_hex_number()&&candidate!=path)entries.push_back({candidate,FileAccess::get_modified_time(candidate)});
        }
        std::sort(entries.begin(),entries.end(),[](const Entry&a,const Entry&b){return a.time<b.time;});
        for(int i=0;i<int(entries.size())+1-limit;++i)DirAccess::remove_absolute(entries[i].path);
        return true;
    }
    void publish(){
        const uint64_t start=now();
        bool ok=false;
        do{
            auto raw=instance("NativeWorldArchive");if(raw.is_null())break;
            const PackedByteArray canonical=raw->call("read",save_path);
            const Dictionary certificates=archive->call("map_certificates");if(!bool(certificates.get("ok",false)))break;
            const Dictionary root=raw->call("decode",canonical);if(!bool(root.get("ok",false)))break;
            const Dictionary sections=root["sections"];if(!sections.has("volumetric_water"))break;
            auto water_store=instance("NativeWaterRegionStore");if(water_store.is_null()||!bool(water_store->call("open_store",save_path+String(".water"))))break;
            const PackedByteArray snapshot=water_store->call("expand_water_snapshot",sections["volumetric_water"]);water_store->call("close");if(snapshot.is_empty())break;
            const Dictionary certified_models=certificates["models"];PackedStringArray parts;bool valid=true;
            for(const auto &model:models){if(!certified_models.has(model.name)){valid=false;break;}
                parts.push_back(model.name+String("|")+String(certified_models[model.name])+String("|")+UtilityFunctions::var_to_bytes(model.index["transform"]).hex_encode()+String("|")+UtilityFunctions::var_to_bytes(model.index["prototype_bounds"]).hex_encode());
            }
            if(!valid||stop.load()||PackedByteArray(raw->call("read",save_path))!=canonical)break;
            const String identities[3]={String("snapshot-v1|")+digest(snapshot).hex_encode(),String(certificates["blocks_identity"])+String("|")+UtilityFunctions::var_to_bytes(block_index["transform"]).hex_encode(),String("|").join(parts).sha256_text()};
            const char *namespaces[]={"water-map-v2","block-map-material-v2-512","model-map-material-v2-512"};
            const char *folders[]={"user://cartography/water","user://cartography/blocks","user://cartography/models"};
            if(!write_cache(save_slot,cache_identity,base_pixels,"user://cartography/edited",16))break;
            for(int i=0;i<3;++i){
                const String key=String(namespaces[i])+String("|certified|")+cache_identity+String("|")+identities[i];
                if(stop.load()||!write_cache(key,key,pixels[i],folders[i],i==0?64:16)){valid=false;break;}
            }
            ok=valid&&!stop.load()&&PackedByteArray(raw->call("read",save_path))==canonical;
        }while(false);
        if(!ok)rejection="Could not certify and publish saved map caches";
        publish_us=now()-start;ready.store(true,std::memory_order_release);
    }
    void calculate(){
        const uint64_t start=now();
        for(const auto &tile:tiles){
            if(stop.load()){rejection="Map generation cancelled";break;}
            Dictionary part=core->call("survey_patch",1024,tile.x*16,tile.y*16,16,16);
            PackedByteArray bytes=part.get("pixels",PackedByteArray());
            if(!bool(part.get("ok",false))||int64_t(part.get("revision",-1))!=revision||bytes.size()!=1024){rejection="Terrain changed during map generation";break;}
            for(int row=0;row<16;++row)std::memcpy(base_pixels.ptrw()+((tile.y*16+row)*1024+tile.x*16)*4,bytes.ptr()+row*64,64);
            patches.fetch_add(1);
        }
        const Color tints[3]={Color(54/255.f,117/255.f,140/255.f),Color::html("d9c9ad"),Color::html("8e8b82")};
        for(int layer=0;layer<3&&rejection.is_empty();++layer){
            for(int64_t offset=0;offset<rasters[layer]->count();){
                if(stop.load()){rejection="Map generation cancelled";break;}
                const Dictionary reply=core->call("survey_water_visibility",rasters[layer]->batch(offset,256));
                const PackedByteArray mask=reply.get("visible",PackedByteArray());
                if(!bool(reply.get("ok",false))||int64_t(reply.get("revision",-1))!=revision||mask.is_empty()||!rasters[layer]->accept_prefix(offset,mask)){rejection="Invalid or stale map visibility result";break;}
                offset+=mask.size();visibility_calls.fetch_add(1);
            }
            if(rejection.is_empty())pixels[layer]=rasters[layer]->pixels(tints[layer]);
        }
        worker_us=now()-start;ready.store(true,std::memory_order_release);
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("start","game","base_pixels"),&NativeGenerationMaps::start);
        ClassDB::bind_method(D_METHOD("begin_publication","absolute_save_path","snapshot_codec","slot","terrain_identity"),&NativeGenerationMaps::begin_publication);
        ClassDB::bind_method(D_METHOD("advance"),&NativeGenerationMaps::advance);
        ClassDB::bind_method(D_METHOD("sources_ready"),&NativeGenerationMaps::sources_ready);
        ClassDB::bind_method(D_METHOD("cancel"),&NativeGenerationMaps::cancel);
        ClassDB::bind_method(D_METHOD("get_result"),&NativeGenerationMaps::get_result);
        ClassDB::bind_method(D_METHOD("terrain_pixels"),&NativeGenerationMaps::terrain_pixels);
        ClassDB::bind_method(D_METHOD("layer_pixels","layer"),&NativeGenerationMaps::layer_pixels);
    }
public:
    ~NativeGenerationMaps(){stop.store(true);join();}
    void cancel(){stop.store(true);}
    Dictionary get_result()const{return result;}
    bool sources_ready()const{return started_worker;}
    PackedByteArray terrain_pixels()const{return done&&bool(result.get("ok",false))?base_pixels:PackedByteArray();}
    PackedByteArray layer_pixels(int layer)const{return layer>=0&&layer<3&&done&&bool(result.get("ok",false))?pixels[layer]:PackedByteArray();}
    bool begin_publication(const String &path,const Ref<RefCounted> &codec,const String &slot,const String &identity){
        if(publishing||!done||!bool(result.get("ok",false))||codec.is_null()||!codec->is_class("NativeRegionWorldArchive")||!path.is_absolute_path()||slot.is_empty()||identity.is_empty()||!current()||!field_current())return false;
        publishing=true;save_path=path;save_slot=slot;cache_identity=identity;archive=codec;done=false;stop.store(false);ready.store(false);
        worker.instantiate();if(worker->start(callable_mp(this,&NativeGenerationMaps::publish))!=OK){finish(false,"Map publication worker failed to start");return false;}return true;
    }
    bool start(Object *game,const PackedByteArray &initial){
        if(attempted||!game||initial.size()!=1024*1024*4)return false;attempted=true;began=now();
        auto *terrain=member(game,"terrain"),*structures=member(game,"structures"),*lakes=member(game,"lakes");
        auto *backend=member(terrain,"backend"),*blocks=member(structures,"blocks");
        if(!terrain||!structures||!lakes||!backend||!blocks||!blocks->is_class("NativeBlockWorld"))return false;
        core=Ref<RefCounted>(Object::cast_to<RefCounted>(member(backend,"native")));water=Ref<RefCounted>(Object::cast_to<RefCounted>(member(lakes,"water")));
        if(core.is_null()||water.is_null()||!core->is_class("TerrainCore")||!water->is_class("NativeRegionalWater"))return false;
        game_id=game->get_instance_id();terrain_id=terrain->get_instance_id();blocks_id=blocks->get_instance_id();
        epoch=terrain->get("epoch");revision=terrain->get("density_revision");block_revision=blocks->call("survey_content_revision_id");water_revision=water->call("survey_revision_id");
        block_index=blocks->call("survey_index");if(!resident(block_index))return false;
        Dictionary collections=structures->call("model_collections");if(collections.size()>512)return false;
        Array names=collections.keys();names.sort();
        for(int i=0;i<names.size();++i){auto *owner=static_cast<Object*>(collections[names[i]]);if(!owner||!owner->is_class("NativeStaticBatch"))return false;Dictionary index=owner->call("survey_index");if(!bool(index.get("ready",false))||!resident(index))return false;models.push_back({String(names[i]),owner->get_instance_id(),index});}
        if(!current()||!field_current())return false;
        base_pixels=initial.duplicate();for(int layer=0;layer<3;++layer){rasters[layer].instantiate();rasters[layer]->configure(layer==0?256:512);}
        int generator=backend->get("world_generator");ocean_done=!((generator>=19&&generator<=35&&(generator%2))||generator==36);
        std::array<bool,4096> dirty{};Dictionary columns=terrain->get("modified_columns");Array keys=columns.keys();
        for(int i=0;i<keys.size();++i){if(keys[i].get_type()!=Variant::VECTOR2I)return false;Vector2i cell=keys[i];
            int x0=std::clamp(int(std::floor((cell.x*16.-8)*1024/2000/16)),0,63),x1=std::clamp(int(std::floor((cell.x*16.+24)*1024/2000/16)),0,63);
            int z0=std::clamp(int(std::floor((cell.y*16.-8)*1024/2000/16)),0,63),z1=std::clamp(int(std::floor((cell.y*16.+24)*1024/2000/16)),0,63);
            for(int z=z0;z<=z1;++z)for(int x=x0;x<=x1;++x)dirty[z*64+x]=true;
        }
        for(int z=0;z<64;++z)for(int x=0;x<64;++x)if(dirty[z*64+x])tiles.emplace_back(x,z);
        admitted=true;return true;
    }
    bool advance(){
        if(done)return true;if(!admitted){finish(false,"Map job not started");return true;}
        if(!current())stop.store(true);
        if(!started_worker){
            const uint64_t start=now();
            while(!stop.load()&&phase<3&&now()-start<8000){if(!(phase==0?water_step():source_step())){finish(false,"Map source changed or is not resident");return true;}}
            const uint64_t elapsed=now()-start;source_us+=elapsed;max_advance_us=std::max(max_advance_us,elapsed);
            if(stop.load()){finish(false,"Map generation cancelled");return true;}
            if(phase<3)return false;
            worker.instantiate();if(worker->start(callable_mp(this,&NativeGenerationMaps::calculate))!=OK){finish(false,"Map worker failed to start");return true;}started_worker=true;
        }
        if(!ready.load(std::memory_order_acquire))return false;join();
        if(stop.load()||!rejection.is_empty()||!current()||!field_current()){finish(false,rejection.is_empty()?String("Map inputs changed"):rejection);return true;}
        finish(true);return true;
    }
};
void register_generation_maps(){GDREGISTER_CLASS(NativeGenerationMaps);}
}
