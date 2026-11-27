// SPDX-License-Identifier: 0BSD
// Offline generation only: immutable prefab definitions, native terrain reads,
// then ordered owner-thread prefab transactions. No editor/palette operations.
#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <map>
#include <vector>

using namespace godot;
namespace terraforest {
class NativeGenerationBuildings : public RefCounted {
    GDCLASS(NativeGenerationBuildings,RefCounted)
    // Creation has no active gameplay/physics. Leave time for progress rendering
    // without throwing away most of each 60 Hz frame after a tiny work slice.
    static constexpr uint64_t OWNER_QUANTUM_US=8000;
    struct Lot {Ref<Resource> asset;Vector3i origin;int rotation=0,band=0,doors=0;String label;int64_t samples[4]{};uint64_t check_us=0;};
    std::vector<Lot> lots;
    Ref<RefCounted> core,placement;
    Ref<Thread> worker;
    Dictionary models,result;
    std::atomic<bool> stop{false},checked{false};
    std::atomic<int> validated{0};
    uint64_t game_id=0,terrain_id=0,blocks_id=0,doors_id=0;
    int64_t epoch=0,revision=0,door_count=0,cells=0,definition_cells=0,definitions=0;
    int cursor=0;
    bool attempted=false,done=false,pending=false;
    String rejection;
    uint64_t began=0,clone_us=0,validation_us=0,publication_us=0,max_advance_us=0;
    static uint64_t now(){return Time::get_singleton()->get_ticks_usec();}
    static Object *member(Object *object,const char *name){return object?static_cast<Object*>(object->get(name)):nullptr;}
    static Ref<RefCounted> instance(const char *name){const Variant value=ClassDBSingleton::get_singleton()->instantiate(name);return Ref<RefCounted>(Object::cast_to<RefCounted>(static_cast<Object*>(value)));}
    static bool reply_ok(const PackedByteArray &bytes){return bytes.size()>=12&&bytes.decode_u32(0)==0x32505254&&bytes.decode_u32(8)==0;}
    bool field_current() const {
        PackedByteArray packet;packet.resize(4);packet.encode_u32(0,0);
        const PackedByteArray reply=core->call("execute",packet);
        return reply_ok(reply)&&reply.size()>=16&&reply.decode_u32(12)==uint64_t(revision);
    }
    bool current() const {
        auto *game=ObjectDB::get_instance(game_id),*terrain=ObjectDB::get_instance(terrain_id);
        return game&&terrain&&!bool(game->get("shutdown_requested"))&&bool(terrain->get("world_ready"))&&
            bool(terrain->get("diagnostics_pause_streaming"))&&!bool(terrain->get("pending_edit"))&&!bool(terrain->get("stopping"))&&
            int64_t(terrain->get("epoch"))==epoch&&int64_t(terrain->get("density_revision"))==revision;
    }
    void join(){if(worker.is_valid()&&worker->is_started())worker->wait_to_finish();worker.unref();}
    void finish(bool ok,const String &reason=String()) {
        stop.store(true);join();
        if(placement.is_valid()&&pending)placement->call("cancel");pending=false;done=true;
        result["ok"]=ok;result["reason"]=reason;result["buildings"]=cursor;result["cells"]=cells;result["definition_cells"]=definition_cells;result["definitions"]=definitions;
        Array checks;for(const auto &lot:lots){Dictionary row;row["label"]=lot.label;row["foundation"]=lot.samples[0];row["deep_support"]=lot.samples[1];row["clearance"]=lot.samples[2];row["surfaces"]=lot.samples[3];row["microseconds"]=int64_t(lot.check_us);checks.push_back(row);}result["checks"]=checks;
        Dictionary profile;profile["clone_us"]=int64_t(clone_us);profile["validation_us"]=int64_t(validation_us);profile["publication_us"]=int64_t(publication_us);profile["max_advance_us"]=int64_t(max_advance_us);profile["total_us"]=int64_t(now()-began);result["profile"]=profile;
    }
    static String contract(const Ref<Resource> &asset,int &band) {
        if(asset.is_null()||!asset->is_class("NativeBlockPrefab"))return "Invalid building asset";
        const Variant offset=asset->get_meta("site_surface_offset",0),sample=asset->get_meta("site_sample_band",0);
        if(offset.get_type()!=Variant::INT||sample.get_type()!=Variant::INT)return "Building surface and foundation sample datums disagree";
        const int64_t height=offset,sample_band=sample;
        if((height!=0&&height!=1&&height!=5&&height!=9)||height!=sample_band)return "Building surface and foundation sample datums disagree";
        band=int(sample_band);
        if(height==5&&!bool(asset->get_meta("cellar_clearance",false)))return "Underground surface needs a cellar excavation plan";
        const Variant volumes=asset->get_meta("cellar_volumes",Array());
        if(height==9&&(volumes.get_type()!=Variant::ARRAY||Array(volumes).is_empty()))return "Deep underground surface needs explicit interior excavation volumes";
        const double reveal=height>0?.125:0.0;
        if(asset->has_meta("site_surface_inset")&&!Math::is_equal_approx(double(asset->get_meta("site_surface_inset")),reveal))return "Per-building soil offsets cannot override the terrain contact standard";
        return String();
    }
    bool scan(Lot &lot,const PackedVector3Array &points,int mode,int depth) {
        if(points.is_empty()||points.size()>512){rejection="Invalid bounded terrain check";return false;}
        if(stop.load()){rejection="Building generation cancelled";return false;}
        PackedByteArray packet;const int header=depth>0?16:12;packet.resize(header+points.size()*12);
        packet.encode_u32(0,depth>0?30:mode>=2?31:29);packet.encode_u32(4,uint32_t(revision));packet.encode_u32(8,points.size());
        if(depth>0)packet.encode_u32(12,depth);
        for(int i=0;i<points.size();i++)for(int axis=0;axis<3;axis++)packet.encode_float(header+i*12+axis*4,points[i][axis]);
        const PackedByteArray reply=core->call("execute",packet);
        if(!reply_ok(reply)||reply.size()!=20+points.size()*4||reply.decode_u32(12)!=uint64_t(revision)||reply.decode_u32(16)!=points.size()){rejection="Terrain changed or unavailable during building checks";return false;}
        lot.samples[mode]+=points.size();
        for(int i=0;i<points.size();i++){
            const double value=reply.decode_float(20+i*4);
            if(!std::isfinite(value)){rejection="Invalid terrain check";return false;}
            if((mode<2&&value>=0)||(mode>=2&&value<0)){
                rejection=mode==0?String("Unsupported foundation; grade terrain first"):mode==1?String("Fill lacks support through grading depth; choose a lower site"):mode==2?String("Terrain inside building; clear or grade site first"):String("Terrain intersects exposed block surface at ")+String(points[i]);return false;
            }
        }
        return true;
    }
    void validate() {
        const uint64_t started=now();
        for(auto &lot:lots){
            const uint64_t lot_started=now();
            const PackedVector3Array foundation=lot.asset->call("foundation_samples",lot.origin,lot.rotation,lot.band);
            if(foundation.is_empty()){rejection="No foundation probes";break;}
            bool ok=true;
            for(int mode=0;mode<4&&ok;mode++){
                const int64_t count=mode<2?foundation.size():mode==2?int64_t(lot.asset->call("clearance_sample_count")):int64_t(lot.asset->call("terrain_surface_sample_count",lot.band));
                if(count<0){rejection="Terrain surface check exceeds bounded probe budget";ok=false;break;}
                for(int64_t offset=0;offset<count&&ok;offset+=512){
                    const PackedVector3Array points=mode<2?foundation.slice(offset,std::min(offset+512,count)):
                        PackedVector3Array(lot.asset->call(mode==2?"clearance_samples":"terrain_surface_samples",lot.origin,lot.rotation,offset,512,lot.band));
                    if(points.size()!=std::min<int64_t>(512,count-offset)){rejection="Invalid terrain sample page";ok=false;break;}
                    ok=scan(lot,points,mode,mode==1?std::clamp(lot.origin.y-4,0,8):0);
                }
            }
            lot.check_us=now()-lot_started;if(!ok)break;validated.fetch_add(1);
        }
        validation_us=now()-started;checked.store(true,std::memory_order_release);
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("start","game","lots"),&NativeGenerationBuildings::start);
        ClassDB::bind_method(D_METHOD("advance"),&NativeGenerationBuildings::advance);
        ClassDB::bind_method(D_METHOD("cancel"),&NativeGenerationBuildings::cancel);
        ClassDB::bind_method(D_METHOD("progress"),&NativeGenerationBuildings::progress);
        ClassDB::bind_method(D_METHOD("get_result"),&NativeGenerationBuildings::get_result);
    }
public:
    ~NativeGenerationBuildings(){stop.store(true);join();if(placement.is_valid()&&pending)placement->call("cancel");}
    void cancel(){stop.store(true);}
    Dictionary get_result() const{return result;}
    Dictionary progress() const {Dictionary out;out["phase"]=checked.load()?"placing":"validating";out["validated"]=validated.load();out["completed"]=cursor;out["total"]=int(lots.size());return out;}
    bool start(Object *game,const Array &input) {
        if(attempted||!game||input.size()>256)return false;attempted=true;began=now();
        auto *terrain=member(game,"terrain"),*structures=member(game,"structures"),*doors=member(game,"doors");
        auto *backend=member(terrain,"backend"),*blocks=member(structures,"blocks"),*collection=member(doors,"collection");
        if(!terrain||!backend||!structures||!blocks||!collection)return false;
        game_id=game->get_instance_id();terrain_id=terrain->get_instance_id();blocks_id=blocks->get_instance_id();doors_id=collection->get_instance_id();
        epoch=terrain->get("epoch");revision=terrain->get("density_revision");core=Ref<RefCounted>(Object::cast_to<RefCounted>(member(backend,"native")));
        if(core.is_null()||!core->is_class("TerrainCore")||!current()||!field_current())return false;
        models=structures->call("model_collections");door_count=PackedInt64Array(collection->call("get_ids")).size();
        placement=instance("NativePrefabPlacement");if(placement.is_null())return false;
        std::map<uint64_t,Ref<Resource>> copies;
        for(int i=0;i<input.size();i++){
            if(input[i].get_type()!=Variant::DICTIONARY)return false;const Dictionary row=input[i];
            if(row.get("asset",Variant()).get_type()!=Variant::OBJECT||row.get("origin",Variant()).get_type()!=Variant::VECTOR3I||row.get("rotation",Variant()).get_type()!=Variant::INT)return false;
            Ref<Resource> source=row["asset"];Lot lot;const int64_t rotation=row["rotation"];
            if(rotation<0||rotation>3||!contract(source,lot.band).is_empty())return false;
            lot.origin=row["origin"];lot.rotation=int(rotation);lot.label=row.get("label",String("Building"));
            auto found=copies.find(source->get_instance_id());
            if(found==copies.end()){
                const int64_t count=source->call("get_cell_count");if(count<1||definition_cells+count>2097152)return false;definition_cells+=count;
                auto copy=source->duplicate(true);if(copy.is_null())return false;found=copies.emplace(source->get_instance_id(),copy).first;
            }
            lot.asset=found->second;cells+=int64_t(lot.asset->call("get_cell_count"));const Array attachments=lot.asset->call("get_model_attachments");
            for(int n=0;n<attachments.size();n++)if(String(Dictionary(attachments[n]).get("model",String()))==String("architecture/wooden_door/v1"))++lot.doors;
            lots.push_back(std::move(lot));
        }
        definitions=copies.size();clone_us=now()-began;worker.instantiate();
        if(worker->start(callable_mp(this,&NativeGenerationBuildings::validate))!=OK){worker.unref();return false;}
        return true;
    }
    bool advance() {
        if(done)return true;
        if(!attempted||worker.is_null()&&!checked.load()){finish(false,"Building generation not started");return true;}
        if(!current())stop.store(true);
        if(!checked.load(std::memory_order_acquire))return false;
        join();
        if(stop.load()||!rejection.is_empty()||!field_current()){finish(false,!rejection.is_empty()?rejection:String("Building generation cancelled or terrain changed"));return true;}
        const uint64_t started=now();
        while(cursor<int(lots.size())&&now()-started<OWNER_QUANTUM_US){
            auto *blocks=ObjectDB::get_instance(blocks_id),*doors=ObjectDB::get_instance(doors_id);
            if(!blocks||!doors){finish(false,"Building owners disappeared");return true;}
            auto &lot=lots[cursor];Dictionary state;
            if(!pending){state=placement->call("begin",blocks,lot.asset,lot.origin,lot.rotation,models,Array());pending=bool(state.get("ok",false));}
            else state=placement->call("advance",8192,64,4000);
            if(!bool(state.get("ok",false))){finish(false,String(state.get("reason",String("Native prefab transaction failed"))));return true;}
            if(String(state.get("status",String()))==String("ready")){
                if(!current()||!field_current()){finish(false,"Terrain changed before building publication");return true;}
                state=placement->call("commit",Array());pending=false;
                if(!bool(state.get("ok",false))){finish(false,String(state.get("reason",String("Native prefab commit failed"))));return true;}
                door_count+=lot.doors;
                if(PackedInt64Array(doors->call("get_ids")).size()!=door_count){finish(false,"Generated door count differs from prefab");return true;}
                ++cursor;
            }
        }
        const uint64_t elapsed=now()-started;publication_us+=elapsed;max_advance_us=std::max(max_advance_us,elapsed);
        if(cursor==int(lots.size())){finish(true);return true;}return false;
    }
};
void register_generation_buildings(){GDREGISTER_CLASS(NativeGenerationBuildings);}
}
