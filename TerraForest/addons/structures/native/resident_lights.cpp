// SPDX-License-Identifier: 0BSD
#include "resident_lights.hpp"
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
namespace terraforest {
using namespace godot;
void NativeResidentLights::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","definitions","limit"),&NativeResidentLights::configure);
    ClassDB::bind_method(D_METHOD("set_focus","position"),&NativeResidentLights::set_focus);
    ClassDB::bind_method(D_METHOD("set_enabled","enabled"),&NativeResidentLights::set_enabled);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeResidentLights::statistics);
}
bool NativeResidentLights::configure(const Array &definitions,int limit){
    if(!sources.empty()||!slots.empty()||definitions.is_empty()||definitions.size()>8||limit<1||limit>8)return false;
    std::vector<Source> staged;
    for(int index=0;index<definitions.size();++index){
        if(definitions[index].get_type()!=Variant::DICTIONARY)return false;
        Dictionary row=definitions[index];
        if(!row.has("collection")||!row.has("offset")||!row.has("color")||!row.has("energy")||!row.has("range")||!row.has("shadows"))return false;
        if(row["collection"].get_type()!=Variant::OBJECT||row["offset"].get_type()!=Variant::VECTOR3||row["color"].get_type()!=Variant::COLOR||row["shadows"].get_type()!=Variant::BOOL)return false;
        auto number=[](Variant value){return value.get_type()==Variant::FLOAT||value.get_type()==Variant::INT;};
        if(!number(row["energy"])||!number(row["range"]))return false;
        auto *collection=Object::cast_to<NativeStaticBatch>(row["collection"]);
        Vector3 offset=row["offset"];Color color=row["color"];double energy=row["energy"],range=row["range"];
        if(!collection||!offset.is_finite()||offset.length()>4||!std::isfinite(energy)||energy<=0||energy>8||!std::isfinite(range)||range<=0||range>16)return false;
        for(int channel=0;channel<4;++channel)if(!std::isfinite(color[channel])||color[channel]<0||color[channel]>1)return false;
        for(const auto &source:staged)if(source.owner==collection->get_instance_id())return false;
        staged.push_back({collection->get_instance_id(),offset,color,energy,range,bool(row["shadows"])});
    }
    sources=std::move(staged);
    for(int index=0;index<limit;++index){
        auto *light=memnew(OmniLight3D);light->set_visible(false);light->set_param(Light3D::PARAM_SHADOW_BIAS,.04);
        light->set_shadow_caster_mask(0x7ffff);add_child(light);slots.push_back({light,-1,0});
    }
    set_process(enabled);return true;
}
void NativeResidentLights::set_focus(Vector3 value){
    if(!value.is_finite())return;
    focus=value;
    if(scanning&&focus.distance_squared_to(scan_focus)>16){scanning=false;timer=.1;}
}
void NativeResidentLights::set_enabled(bool value){
    enabled=value;set_process(value&&!sources.empty());
    if(!value)for(auto &slot:slots){slot.light->set_visible(false);slot.identity=0;slot.source=-1;}
    else {scanning=false;timer=.1;}
}
bool NativeResidentLights::point(const Source &source,int64_t identity,Vector3 &result) const {
    auto *collection=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(ObjectID(source.owner)));
    if(!collection||!collection->is_inside_tree()||!collection->is_visible_in_tree())return false;
    auto found=collection->placements.find(identity);
    if(found==collection->placements.end()||collection->visual_hidden.count(identity))return false;
    result=collection->get_global_transform().xform(collection->placement_transform(found->second).xform(source.offset));
    return result.is_finite()&&result.distance_squared_to(focus)<24*24;
}
void NativeResidentLights::select(){
    if(!scanning){selected.clear();source_cursor=cell_cursor=0;after_identity=0;scan_cells.clear();scan_focus=focus;scanning=true;}
    visited=0;int cell_work=0;
    while(source_cursor<sources.size()&&visited<512&&cell_work<512){
        const auto &source=sources[source_cursor];
        auto *collection=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(ObjectID(source.owner)));
        if(!collection||!collection->is_inside_tree()||!collection->is_visible_in_tree()){++source_cursor;scan_cells.clear();cell_cursor=0;after_identity=0;continue;}
        if(scan_cells.empty()){
            Transform3D frame=collection->get_global_transform();
            if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-9){++source_cursor;continue;}
            AABB local=frame.affine_inverse().xform(AABB(scan_focus-Vector3(28,28,28),Vector3(56,56,56)));
            Vector3 low=(local.position/32).floor(),high=(local.get_end()/32).floor();
            if(!low.is_finite()||!high.is_finite()||(high-low).length()>8||low.abs().length()>1000000){++source_cursor;continue;}
            for(int row=int(low.z);row<=int(high.z);++row)for(int level=int(low.y);level<=int(high.y);++level)for(int column=int(low.x);column<=int(high.x);++column)scan_cells.push_back({column,level,row});
        }
        while(cell_cursor<scan_cells.size()&&visited<512&&cell_work<512){
            ++cell_work;auto group=collection->groups.find(scan_cells[cell_cursor]);
            if(group==collection->groups.end()){++cell_cursor;after_identity=0;continue;}
            auto member=group->second.upper_bound(after_identity);
            while(member!=group->second.end()&&visited<512){
                int64_t identity=*member++;after_identity=identity;++visited;
                Vector3 position;if(!point(source,identity,position))continue;
                double distance=position.distance_squared_to(focus);
                bool retained=false;for(const auto &slot:slots)if(slot.source==int(source_cursor)&&slot.identity==identity)retained=true;
                if(retained)distance=std::max(0.0,distance-4);
                selected.push_back({int(source_cursor),identity,distance,position});
                std::sort(selected.begin(),selected.end(),[](const Candidate &first,const Candidate &second){if(first.distance!=second.distance)return first.distance<second.distance;if(first.source!=second.source)return first.source<second.source;return first.identity<second.identity;});
                if(selected.size()>slots.size())selected.pop_back();
            }
            if(member==group->second.end()){++cell_cursor;after_identity=0;}
        }
        if(cell_cursor==scan_cells.size()){++source_cursor;scan_cells.clear();cell_cursor=0;after_identity=0;}
    }
    total_visited+=visited;
    if(source_cursor==sources.size()){publish();scanning=false;++updates;}
}
void NativeResidentLights::publish(){
    std::vector<Candidate> ready;
    for(auto candidate:selected){Vector3 position;if(point(sources[candidate.source],candidate.identity,position)){candidate.position=position;ready.push_back(candidate);}}
    for(auto &slot:slots){
        auto found=std::find_if(ready.begin(),ready.end(),[&](const Candidate &candidate){return candidate.source==slot.source&&candidate.identity==slot.identity;});
        if(found==ready.end()){slot.source=-1;slot.identity=0;slot.light->set_visible(false);}
        else ready.erase(found);
    }
    for(const auto &candidate:ready)for(auto &slot:slots)if(!slot.identity){
        const auto &source=sources[candidate.source];slot.source=candidate.source;slot.identity=candidate.identity;
        slot.light->set_global_position(candidate.position);slot.light->set_color(source.color);slot.light->set_param(Light3D::PARAM_ENERGY,source.energy);
        slot.light->set_param(Light3D::PARAM_RANGE,source.range);slot.light->set_param(Light3D::PARAM_ATTENUATION,1.3);slot.light->set_shadow(source.shadows);slot.light->set_visible(true);break;
    }
}
void NativeResidentLights::_process(double delta){
    if(!enabled||sources.empty())return;
    uint64_t started=Time::get_singleton()->get_ticks_usec();
    for(auto &slot:slots)if(slot.identity){
        Vector3 position;
        if(!point(sources[slot.source],slot.identity,position)){slot.light->set_visible(false);slot.identity=0;slot.source=-1;}
        else {
            // Reasserting a static transform queues redundant notifications.
            // Keep exact poses/energy, submit only changes.
            if(slot.light->get_global_position()!=position)slot.light->set_global_position(position);
            const double distance=position.distance_to(focus);
            const float energy=float(sources[slot.source].energy*Math::clamp((24-distance)/6.0,0.0,1.0));
            if(slot.light->get_param(Light3D::PARAM_ENERGY)!=energy)slot.light->set_param(Light3D::PARAM_ENERGY,energy);
        }
    }
    timer+=std::max(0.0,delta);if(timer>=.1){timer=0;select();}
    last_us=Time::get_singleton()->get_ticks_usec()-started;max_us=std::max(max_us,last_us);
}
Dictionary NativeResidentLights::statistics() const {
    Dictionary result;int active=0;Array records;
    for(const auto &slot:slots)if(slot.identity){++active;Dictionary row;row["source"]=slot.source;row["id"]=slot.identity;row["position"]=slot.light->get_global_position();records.push_back(row);}
    result["capacity"]=int(slots.size());result["active"]=active;result["sources"]=int(sources.size());result["enabled"]=enabled;
    result["updates"]=int64_t(updates);result["visited"]=int64_t(visited);result["total_visited"]=int64_t(total_visited);result["scanning"]=scanning;
    result["last_us"]=int64_t(last_us);result["max_us"]=int64_t(max_us);result["lights"]=records;return result;
}
}
