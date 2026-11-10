// SPDX-License-Identifier: 0BSD
#include "destruction_coordinator.hpp"
#include "../../structures/native/block_word.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <cmath>
namespace terraforest {
using namespace godot;
void NativeDestructionCoordinator::_bind_methods(){
    ClassDB::bind_method(D_METHOD("execute","blocks","durability","records","offset","center","count"),&NativeDestructionCoordinator::execute);
    ClassDB::bind_method(D_METHOD("commit_damage"),&NativeDestructionCoordinator::commit_damage);
}
bool NativeDestructionCoordinator::commit_damage(){
    if(!executing||!armed||committed||owner.is_null()||owner->revision!=expected_revision||!block_owner||!bool(block_owner->call("destruction_commit_active",this)))return false;
    // All map nodes were prepared before admission. This section allocates no
    // durability records and invokes no observers or engine callbacks.
    for(int i=0;i<removed_count;i++)if(owner->damaged.erase(removed_keys[i]))++owner->revision;
    while(!staged.empty()){
        auto entry=staged.extract(staged.begin());auto at=owner->damaged.find(entry.key());
        if(at==owner->damaged.end()){owner->damaged.insert(std::move(entry));++owner->revision;}
        else if(at->second.health!=entry.mapped().health||at->second.damage!=entry.mapped().damage){at->second=entry.mapped();++owner->revision;}
    }
    committed=true;armed=false;return true;
}
Dictionary NativeDestructionCoordinator::execute(Object *blocks,const Ref<NativeWorldDurability> &durability,const PackedInt32Array &records,int64_t offset,Vector3 center,int64_t count){
    Dictionary result;result["ok"]=false;
    if(executing||!blocks||blocks->get_class()!=StringName("NativeBlockWorld")||blocks->get_script().get_type()!=Variant::NIL||durability.is_null()||!center.is_finite()||count<1||count>64||offset<0||offset%4||records.size()%4||offset>records.size())return result;
    const uint64_t began=Time::get_singleton()->get_ticks_usec();
    executing=true;owner=durability;block_owner=blocks;expected_revision=owner->revision;staged.clear();removed_count=0;committed=false;
    const int64_t end=std::min(offset+count*4,records.size());
    const int64_t block_revision=blocks->call("survey_revision_id");
    PackedInt32Array removed;PackedFloat64Array forces;
    removed.resize(count*4);forces.resize(count);
    int capacity=int(owner->damaged.size());bool valid=true;
    constexpr int maximums[4]={90,60,120,180};
    for(int64_t i=offset;i<end;i+=4){
        Vector3i cell(records[i],records[i+1],records[i+2]);int word=records[i+3];
        if(!valid_block_word(word)||std::abs(int64_t(cell.x))>1048575||std::abs(int64_t(cell.y))>1048575||std::abs(int64_t(cell.z))>1048575){valid=false;break;}
        if(!word||int64_t(blocks->call("get_cell",cell))!=word)continue;
        const double distance=(Vector3(cell)+Vector3(.5,.5,.5)).distance_to(center);
        if(!std::isfinite(distance)){valid=false;break;}
        const int maximum=maximums[block_material(word)],amount=std::max(1,int(std::round(300*(1-distance/5))));
        std::string key="block:"+std::to_string(cell.x)+":"+std::to_string(cell.y)+":"+std::to_string(cell.z);
        auto at=owner->damaged.find(key);
        if(at==owner->damaged.end()&&owner->damaged.size()>=65536)continue;
        int previous=at==owner->damaged.end()||at->second.health!=maximum?0:at->second.damage;
        int damage=std::min(maximum,previous+amount);
        if(damage==maximum){
            for(int axis=0;axis<3;axis++)removed.set(removed_count*4+axis,cell[axis]);
            removed.set(removed_count*4+3,word);forces.set(removed_count,9*(1-distance/6));removed_keys[removed_count++]=std::move(key);
        }else{
            // Match the existing sequential hit capacity: rejected survivor hits
            // do not consume a record; destruction does not grant extra capacity.
            auto planned=staged.find(key);
            if(planned!=staged.end()){
                // Older valid combat snapshots may repeat a survivor record.
                // Preserve every hit; only repeated destructive erasures reject.
                planned->second.damage=std::min(maximum,planned->second.damage+amount);
            }else{
                if(at==owner->damaged.end()&&capacity>=65536)continue;
                if(at==owner->damaged.end())++capacity;
                staged.emplace(std::move(key),NativeWorldDurability::Entry{maximum,damage});
            }
        }
    }
    removed.resize(removed_count*4);forces.resize(removed_count);
    bool accepted=false;
    if(valid&&owner->revision==expected_revision&&int64_t(blocks->call("survey_revision_id"))==block_revision){
        armed=true;
        accepted=blocks->call("erase_cells_transaction",removed,block_revision,this);
        armed=false;
    }
    result["ok"]=accepted&&committed;
    if(accepted&&committed){result["offset"]=end;result["removed"]=removed;result["forces"]=forces;result["damage_changed"]=owner->revision!=expected_revision;}
    result["store_us"]=Time::get_singleton()->get_ticks_usec()-began;
    result["geometry_ready"]=false;
    staged.clear();owner.unref();block_owner=nullptr;executing=false;return result;
}
}
