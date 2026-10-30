// SPDX-License-Identifier: 0BSD
#include "vehicle_horizon.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleHorizon::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","fleet","parts","kind"),&NativeVehicleHorizon::configure);
    ClassDB::bind_method(D_METHOD("set_excluded","identities"),&NativeVehicleHorizon::set_excluded);
    ClassDB::bind_method(D_METHOD("advance","records","page_uploads"),&NativeVehicleHorizon::advance,DEFVAL(128),DEFVAL(3));
    ClassDB::bind_method(D_METHOD("statistics"),&NativeVehicleHorizon::statistics);
    ClassDB::bind_method(D_METHOD("represented_ids"),&NativeVehicleHorizon::represented_ids);
}
NativeVehicleHorizon::~NativeVehicleHorizon(){
    if(fleet.is_valid()){
        fleet->disconnect("presentation_changed",callable_mp(this,&NativeVehicleHorizon::change));
        fleet->disconnect("presentation_reset",callable_mp(this,&NativeVehicleHorizon::reset));
    }
}
void NativeVehicleHorizon::_notification(int what){if(what==NOTIFICATION_INTERNAL_PROCESS)advance();}
bool NativeVehicleHorizon::configure(const Ref<NativeVehicleFleet> &source,const Array &prototype,const String &type){
    if(fleet.is_valid()||source.is_null()||!NativeVehicleStorage::valid_kind(type)||prototype.is_empty()||prototype.size()>64)return false;
    std::vector<Part> accepted;
    for(int index=0;index<prototype.size();++index){
        if(prototype[index].get_type()!=Variant::DICTIONARY)return false;
        Dictionary row=prototype[index];Variant mesh=row.get("mesh",Variant()),transform=row.get("transform",Variant()),material=row.get("material",Variant());
        if(mesh.get_type()!=Variant::OBJECT||transform.get_type()!=Variant::TRANSFORM3D)return false;
        Part part;part.mesh=mesh;part.local=transform;
        if(part.mesh.is_null()||!part.local.is_finite()||std::abs(part.local.basis.determinant())<.000001)return false;
        if(material.get_type()!=Variant::NIL){
            if(material.get_type()!=Variant::OBJECT)return false;
            Object *object=material;if(object&&!Object::cast_to<Material>(object))return false;
            part.material=material;
        }
        accepted.push_back(part);
    }
    fleet=source;kind=type;parts=std::move(accepted);
    fleet->connect("presentation_changed",callable_mp(this,&NativeVehicleHorizon::change));
    fleet->connect("presentation_reset",callable_mp(this,&NativeVehicleHorizon::reset));
    set_process_internal(true);return true;
}
void NativeVehicleHorizon::change(int64_t identity){changed.insert(identity);}
void NativeVehicleHorizon::reset(){
    for(auto &entry:pages)for(auto *node:entry.second.nodes)memdelete(node);
    pages.clear();available.clear();cell_pages.clear();locations.clear();changed.clear();dirty.clear();excluded.clear();cursor=0;scanned=false;live=false;next_page=0;
}
void NativeVehicleHorizon::remove(int64_t identity){
    auto found=locations.find(identity);if(found==locations.end())return;
    const Location location=found->second;auto &page=pages.at(location.page);
    const int64_t tail=page.ids.back();page.ids[location.slot]=tail;page.ids.pop_back();
    if(tail!=identity)locations.at(tail).slot=location.slot;
    locations.erase(found);dirty.insert(location.page);
    auto &members=cell_pages.at(page.cell);const int donor_key=*members.rbegin();
    if(donor_key!=location.page){
        auto &donor=pages.at(donor_key);const int64_t moved=donor.ids.back();donor.ids.pop_back();
        auto &placement=locations.at(moved);placement.page=location.page;placement.slot=int(page.ids.size());page.ids.push_back(moved);dirty.insert(donor_key);
    }
    auto &last=pages.at(donor_key);available[page.cell].clear();
    if(last.ids.empty())members.erase(donor_key);
    else if(last.ids.size()<PAGE_SIZE)available[page.cell].insert(donor_key);
}
void NativeVehicleHorizon::reconcile(int64_t identity){
    auto record=fleet->records_.find(identity);auto module=fleet->modules_.find(identity);
    const String type=module==fleet->modules_.end()?NativeVehicleStorage::default_kind():module->second.first;
    if(record==fleet->records_.end()||type!=kind||excluded.count(identity)){remove(identity);return;}
    const Vector3 position=record->second.origin;const int cell=int(position.x/256)+int(position.z/256)*8;
    auto found=locations.find(identity);
    if(found!=locations.end()&&pages.at(found->second.page).cell==cell){found->second.pose=record->second;dirty.insert(found->second.page);return;}
    remove(identity);
    auto &free=available[cell];
    if(free.empty()){const int key=++next_page;pages[key].cell=cell;free.insert(key);cell_pages[cell].insert(key);}
    const int key=*free.begin();auto &page=pages.at(key);
    locations[identity]={key,int(page.ids.size()),record->second};page.ids.push_back(identity);dirty.insert(key);
    if(page.ids.size()==PAGE_SIZE)free.erase(key);
}
std::set<int> NativeVehicleHorizon::affected(int64_t identity) const {
    std::set<int> result;const auto found=locations.find(identity);const auto record=fleet->records_.find(identity);const auto module=fleet->modules_.find(identity);
    const String type=module==fleet->modules_.end()?NativeVehicleStorage::default_kind():module->second.first;
    const bool present=record!=fleet->records_.end()&&type==kind&&!excluded.count(identity);
    const int destination=present?int(record->second.origin.x/256)+int(record->second.origin.z/256)*8:-1;
    if(found!=locations.end()){
        const auto &page=pages.at(found->second.page);result.insert(found->second.page);
        if(present&&page.cell==destination)return result;
        result.insert(*cell_pages.at(page.cell).rbegin());
    }
    if(present){const auto free=available.find(destination);result.insert(free==available.end()||free->second.empty()?next_page+1:*free->second.begin());}
    return result;
}
void NativeVehicleHorizon::upload(int key){
    ++last_uploads;
    auto &page=pages.at(key);
    if(page.ids.empty()){
        for(auto *node:page.nodes)memdelete(node);
        available[page.cell].erase(key);pages.erase(key);return;
    }
    if(page.nodes.empty())for(const auto &part:parts){
        Ref<MultiMesh> instances;instances.instantiate();instances->set_transform_format(MultiMesh::TRANSFORM_3D);
        instances->set_mesh(part.mesh);instances->set_instance_count(PAGE_SIZE);instances->set_visible_instance_count(0);
        auto *node=memnew(MultiMeshInstance3D);node->set_multimesh(instances);node->set_material_override(part.material);
        node->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);add_child(node);page.nodes.push_back(node);
    }
    PackedFloat32Array buffer;buffer.resize(PAGE_SIZE*12);float *values=buffer.ptrw();
    for(size_t index=0;index<parts.size();++index){
        const auto &part=parts[index];AABB bounds;bool first=true;
        std::fill(values,values+PAGE_SIZE*12,0.f);
        for(size_t slot=0;slot<page.ids.size();++slot){
            const Transform3D transform=locations.at(page.ids[slot]).pose*part.local;
            for(int axis=0;axis<3;++axis){for(int column=0;column<3;++column)values[slot*12+axis*4+column]=transform.basis[axis][column];values[slot*12+axis*4+3]=transform.origin[axis];}
            const AABB box=transform.xform(part.mesh->get_aabb());bounds=first?box:bounds.merge(box);first=false;
        }
        auto instances=page.nodes[index]->get_multimesh();instances->set_buffer(buffer);instances->set_custom_aabb(bounds);instances->set_visible_instance_count(page.ids.size());
        upload_bytes+=PAGE_SIZE*48;
    }
    page.published=page.ids;++uploads;
}
bool NativeVehicleHorizon::set_excluded(const PackedInt64Array &identities){
    if(fleet.is_null()||identities.size()>512)return false;
    std::set<int64_t> next;for(auto identity:identities){if(identity<=0)return false;next.insert(identity);}
    if(next==excluded)return true;
    std::vector<int64_t> changes;
    std::set_symmetric_difference(next.begin(),next.end(),excluded.begin(),excluded.end(),std::back_inserter(changes));
    excluded=std::move(next);std::set<int> pending;pending.swap(dirty);
    for(auto identity:changes){reconcile(identity);changed.erase(identity);}
    auto urgent=std::move(dirty);dirty=std::move(pending);
    for(auto key:urgent){dirty.erase(key);upload(key);}
    return true;
}
void NativeVehicleHorizon::advance(int records,int page_uploads){
    if(fleet.is_null()||records<1||records>512||page_uploads<3||page_uploads>8)return;
    const uint64_t began=Time::get_singleton()->get_ticks_usec();last_records=0;last_uploads=0;
    while(!changed.empty()&&last_records<records){
        const auto identity=*changed.begin();
        if(live){auto required=affected(identity);required.insert(dirty.begin(),dirty.end());if(required.size()>size_t(page_uploads))break;}
        changed.erase(changed.begin());reconcile(identity);++last_records;
    }
    if(!scanned){
        auto iterator=fleet->records_.upper_bound(cursor);
        while(iterator!=fleet->records_.end()&&last_records<records){cursor=iterator->first;++iterator;reconcile(cursor);++last_records;}
        scanned=iterator==fleet->records_.end();
    }
    while(!dirty.empty()&&last_uploads<page_uploads){const int key=*dirty.begin();dirty.erase(dirty.begin());upload(key);}
    if(scanned&&changed.empty()&&dirty.empty())live=true;
    last_us=Time::get_singleton()->get_ticks_usec()-began;
}
Dictionary NativeVehicleHorizon::statistics() const {
    Dictionary result;int rendered=0;for(const auto &entry:pages)rendered+=entry.second.published.size();
    result["ready"]=scanned&&changed.empty()&&dirty.empty();result["records"]=int64_t(locations.size());result["rendered"]=rendered;
    result["pages"]=int64_t(pages.size());result["parts"]=int64_t(parts.size());result["pending_changes"]=int64_t(changed.size());result["pending_pages"]=int64_t(dirty.size());
    result["instance_capacity_bytes"]=int64_t(pages.size()*parts.size()*PAGE_SIZE*48);result["upload_bytes"]=int64_t(upload_bytes);result["uploads"]=int64_t(uploads);
    result["last_records"]=last_records;result["last_uploads"]=last_uploads;result["last_us"]=int64_t(last_us);return result;
}
PackedInt64Array NativeVehicleHorizon::represented_ids() const {PackedInt64Array result;for(const auto &entry:pages)for(auto identity:entry.second.published)result.push_back(identity);result.sort();return result;}
}
