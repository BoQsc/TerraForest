// SPDX-License-Identifier: 0BSD
#include "actor_navigator.hpp"
using namespace godot;
namespace terraforest {
void NativeActorNavigator::update_query_exclusions(){
    TypedArray<RID> planning=exclusions_.duplicate();planning.append_array(interactions_);
    for(auto &agent:agents_){
        agent.ray->set_exclude(planning);agent.shape->set_exclude(planning);
        agent.motion_ray->set_exclude(exclusions_);agent.motion_shape->set_exclude(exclusions_);
    }
}
void NativeActorNavigator::set_exclusions(const TypedArray<RID> &ids){
    if(ids.size()>64)return;exclusions_=ids.duplicate();invalidate();update_query_exclusions();
}
void NativeActorNavigator::set_interactions(const TypedArray<RID> &ids){
    if(ids.size()>64||ids==interactions_)return;
    interactions_=ids.duplicate();interaction_bounds_.clear();interaction_bounds_known_=false;
    invalidate();update_query_exclusions();
}
bool NativeActorNavigator::set_interactions_scoped(const TypedArray<RID> &ids,const TypedArray<AABB> &bounds){
    if(ids.size()>64||ids.size()!=bounds.size())return false;
    std::map<RID,AABB> next;
    for(int i=0;i<ids.size();++i){
        const RID id=ids[i];const AABB region=bounds[i];
        if(!id.is_valid()||!region.position.is_finite()||!region.size.is_finite()||
           region.size.x<=0||region.size.y<=0||region.size.z<=0||region.position.abs().length()>1000000||
           region.get_end().abs().length()>1000000||!next.emplace(id,region).second)return false;
    }
    if(interaction_bounds_known_&&next==interaction_bounds_)return true;
    const bool global=!interaction_bounds_known_&&!interactions_.is_empty();
    AABB changed;bool has_bounds=false;
    auto include=[&](const AABB &region){changed=has_bounds?changed.merge(region):region;has_bounds=true;};
    for(const auto &entry:interaction_bounds_){
        auto found=next.find(entry.first);
        if(found==next.end()||found->second!=entry.second)include(entry.second);
    }
    for(const auto &entry:next){
        auto found=interaction_bounds_.find(entry.first);
        if(found==interaction_bounds_.end()||found->second!=entry.second)include(entry.second);
    }
    // Keep removed RID bounds until the new policy is fully validated. No
    // physics query dereferences retired RIDs; they only identify exclusions.
    interactions_=ids.duplicate();interaction_bounds_=std::move(next);interaction_bounds_known_=true;
    update_query_exclusions();
    if(global||has_bounds)invalidate(global?AABB():changed);
    return true;
}
}
