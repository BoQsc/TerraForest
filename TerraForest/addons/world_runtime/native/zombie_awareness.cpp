// SPDX-License-Identifier: 0BSD
#include "zombie_awareness.hpp"
#include "zombie_sleep_state.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeZombieAwareness::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","capacity","seed"),&NativeZombieAwareness::configure);
    ClassDB::bind_method(D_METHOD("add_agent","id","feet"),&NativeZombieAwareness::add_agent);
    ClassDB::bind_method(D_METHOD("set_profile","id","profile"),&NativeZombieAwareness::set_profile);
    ClassDB::bind_method(D_METHOD("set_sleeping","id","pose"),&NativeZombieAwareness::set_sleeping);
    ClassDB::bind_method(D_METHOD("finish_waking","id"),&NativeZombieAwareness::finish_waking);
    ClassDB::bind_method(D_METHOD("capture_sleep","id"),&NativeZombieAwareness::capture_sleep);
    ClassDB::bind_method(D_METHOD("restore_sleep","id","bytes"),&NativeZombieAwareness::restore_sleep);
    ClassDB::bind_method(D_METHOD("remove_agent","id"),&NativeZombieAwareness::remove_agent);
    ClassDB::bind_method(D_METHOD("clear"),&NativeZombieAwareness::clear);
    ClassDB::bind_method(D_METHOD("wants_sight","id","feet","forward","player"),&NativeZombieAwareness::wants_sight);
    ClassDB::bind_method(D_METHOD("observe","id","player","visible","distance"),&NativeZombieAwareness::observe,DEFVAL(-1.0));
    ClassDB::bind_method(D_METHOD("provoke","id","player"),&NativeZombieAwareness::provoke);
    ClassDB::bind_method(D_METHOD("hear","id","feet","source","radius"),&NativeZombieAwareness::hear);
    ClassDB::bind_method(D_METHOD("accept_roam","id","supported"),&NativeZombieAwareness::accept_roam);
    ClassDB::bind_method(D_METHOD("advance","id","feet","delta","active","route_state"),&NativeZombieAwareness::advance);
    ClassDB::bind_method(D_METHOD("status","id"),&NativeZombieAwareness::status);
}
NativeZombieAwareness::Agent *NativeZombieAwareness::find(int64_t id){for(auto &a:agents_)if(a.id==id)return &a;return nullptr;}
double NativeZombieAwareness::random(Agent &a){a.random^=a.random<<13;a.random^=a.random>>17;a.random^=a.random<<5;return double(a.random)/4294967296.0;}
void NativeZombieAwareness::rest(Agent &a){a.state=IDLE;a.visible=false;a.remaining=a.profile.idle_min+random(a)*(a.profile.idle_max-a.profile.idle_min);a.blocked=0;a.confidence=0;a.interest=0;a.provoked=false;a.stationary=a.recovery_cooldown=0;a.search_pending=false;a.has_progress_anchor=false;++a.revision;}
void NativeZombieAwareness::roam(Agent &a,const Vector3 &feet,bool search){
    const double angle=random(a)*6.283185307179586,radius=search?2+random(a)*2:a.profile.roam_min+random(a)*(a.profile.roam_max-a.profile.roam_min);
    const Vector3 origin=feet;
    a.goal=origin+Vector3(real_t(std::sin(angle)*radius),0,real_t(std::cos(angle)*radius));
    // Stay in the local neighbourhood instead of drifting indefinitely.
    if(!search&&a.goal.distance_to(a.home)>24)a.goal=feet.lerp(a.home,real_t(.5));
    if(search)a.goal.y=feet.y;
    a.search_origin=feet;a.search_pending=false;a.search_retry=.5;
    a.state=search?SEARCH:WANDER;a.remaining=search?std::min(15.0,a.profile.search*(a.ambusher?1.5:1)):28;a.blocked=0;++a.revision;
}
void NativeZombieAwareness::reposition(Agent &a,const Vector3 &feet){
    Vector3 toward=a.last_seen-feet;toward.y=0;
    if(toward.length_squared()<.01)toward=Vector3(0,0,1);
    toward.normalize();
    const double side=random(a)<.5?-1:1;
    const Vector3 lateral(-toward.z,0,toward.x);
    a.goal=feet+(lateral*side+toward*.25).normalized()*real_t(1.2+random(a)*.8);
    a.search_origin=feet;a.state=REPOSITION;a.remaining=2.;a.stationary=a.blocked=0;
    a.search_pending=false;a.recovery_cooldown=3.;++a.revision;
}
Dictionary NativeZombieAwareness::describe(const Agent &a){
    static const char *names[]={"idle","wander","chase","investigate","search","suspicious","sleeping","waking","reposition"};
    Dictionary out;out["state"]=names[a.state];out["goal"]=a.goal;out["revision"]=a.revision;
    out["moving"]=a.state==WANDER||a.state==CHASE||a.state==INVESTIGATE||a.state==SEARCH||a.state==REPOSITION;out["combat"]=a.state==CHASE;out["visible"]=a.visible;
    out["urgent"]=a.state==CHASE||a.state==INVESTIGATE||a.state==SEARCH||a.state==REPOSITION;
    out["stationary_seconds"]=a.stationary;out["search_pending"]=a.search_pending;
    out["profile"]=a.profile.name;out["walk_speed"]=a.profile.walk_speed;
    out["chase_speed_multiplier"]=std::max(a.profile.chase_multiplier,a.ambusher?a.profile.sleeper_speed:(a.provoked||a.close_visible)?a.profile.provoked_speed:1.0);
    out["wake_speed"]=a.profile.wake_speed;out["ambusher"]=a.ambusher;out["provoked"]=a.provoked;
    out["notice_seconds"]=a.confidence;out["interest_seconds"]=a.interest;out["sleep_pose"]=a.sleep_pose;
    out["wake_elapsed"]=a.wake_elapsed;out["wake_ready"]=a.state==WAKING&&a.wake_elapsed>=a.profile.wake;
    out["unseen_seconds"]=a.unseen;out["remaining_seconds"]=a.remaining;out["ignore_seconds"]=a.ignore;return out;
}
bool NativeZombieAwareness::configure(int capacity,int64_t seed){if(capacity_||capacity<1||capacity>16)return false;capacity_=capacity;seed_=uint32_t(seed)|1;agents_.reserve(capacity);return true;}
bool NativeZombieAwareness::add_agent(int64_t id,const Vector3 &feet){
    if(!capacity_||id<=0||!feet.is_finite()||find(id)||int(agents_.size())>=capacity_)return false;
    Agent a;a.id=id;a.home=a.goal=a.last_seen=feet;a.random=(seed_^uint32_t(id)^uint32_t(uint64_t(id)>>32))|1;
    a.remaining=.3+random(a)*1.7;agents_.push_back(a);return true;
}
bool NativeZombieAwareness::set_profile(int64_t id,const Dictionary &values){
    auto *agent=find(id);if(!agent||(agent->state!=IDLE&&agent->state!=WANDER)||!values.has("id")||values["id"].get_type()!=Variant::STRING)return false;
    Profile profile;profile.name=values["id"];bool ambusher=false;
    if(profile.name.is_empty()||profile.name.length()>64)return false;
    struct Field {const char *key;double Profile::*member;double minimum,maximum;};
    const Field fields[]={
        {"sight_range",&Profile::sight,4,48},{"tracking_range",&Profile::tracking,4,64},{"near_sense_range",&Profile::near_sense,0,6},
        {"notice_seconds",&Profile::notice,0,5},{"pursuit_seconds",&Profile::pursuit,3,90},{"forget_seconds",&Profile::forget,1,30},
        {"search_seconds",&Profile::search,1,15},{"ignore_seconds",&Profile::ignore,1,30},
        {"roam_min",&Profile::roam_min,1,12},{"roam_max",&Profile::roam_max,1,16},
        {"idle_min",&Profile::idle_min,.2,10},{"idle_max",&Profile::idle_max,.2,20},
        {"hearing_scale",&Profile::hearing,.1,1.5},{"walk_speed",&Profile::walk_speed,.3,1.3},
        {"chase_speed_multiplier",&Profile::chase_multiplier,1,3},{"wake_seconds",&Profile::wake,.5,8},
        {"close_notice_seconds",&Profile::close_notice,0,1},{"sleeper_notice_seconds",&Profile::sleep_notice,.1,2},
        {"sleeper_sense_range",&Profile::sleep_range,.5,6},{"wake_speed",&Profile::wake_speed,1,2},
        {"sight_grace_seconds",&Profile::sight_grace,0,2},
        {"provoked_chase_multiplier",&Profile::provoked_speed,1,3},{"sleeper_chase_multiplier",&Profile::sleeper_speed,1,3}
    };
    for(const Variant &key:values.keys()){
        if(key.get_type()!=Variant::STRING)return false;
        if(String(key)=="id")continue;
        if(String(key)=="ambusher"){
            if(values[key].get_type()!=Variant::BOOL)return false;
            ambusher=values[key];continue;
        }
        bool known=false;
        for(const auto &field:fields)if(String(key)==field.key){
            Variant value=values[key];if(value.get_type()!=Variant::INT&&value.get_type()!=Variant::FLOAT)return false;
            double number=value;if(!std::isfinite(number)||number<field.minimum||number>field.maximum)return false;
            profile.*(field.member)=number;known=true;break;
        }
        if(!known)return false;
    }
    if(profile.tracking<profile.sight||profile.near_sense>profile.sight||profile.roam_min>profile.roam_max||profile.idle_min>profile.idle_max)return false;
    agent->profile=profile;agent->ambusher=ambusher;return true;
}
bool NativeZombieAwareness::set_sleeping(int64_t id,int pose){
    auto *agent=find(id);if(!agent||pose<1||pose>2||(agent->state!=IDLE&&agent->state!=WANDER))return false;
    agent->state=SLEEPING;agent->ambusher=true;agent->sleep_pose=pose;agent->visible=false;agent->confidence=0;agent->interest=0;agent->ignore=0;agent->wake_elapsed=0;++agent->revision;return true;
}
void NativeZombieAwareness::wake(Agent &agent,const Vector3 &source,bool provoked){
    if(agent.state!=WAKING){agent.state=WAKING;agent.wake_elapsed=0;++agent.revision;}
    agent.last_seen=agent.goal=source;agent.visible=false;agent.ignore=0;agent.unseen=0;agent.provoked=agent.provoked||provoked;
    agent.interest=agent.profile.pursuit*(agent.provoked?1.5:1);
}
bool NativeZombieAwareness::finish_waking(int64_t id){
    auto *agent=find(id);if(!agent||agent->state!=WAKING||agent->wake_elapsed<agent->profile.wake)return false;
    agent->state=agent->visible?CHASE:INVESTIGATE;agent->remaining=agent->profile.forget;agent->unseen=0;agent->sleep_pose=0;++agent->revision;return true;
}
PackedByteArray NativeZombieAwareness::capture_sleep(int64_t id){
    PackedByteArray bytes;const auto *agent=find(id);if(!agent||(agent->state!=SLEEPING&&agent->state!=WAKING))return bytes;
    bytes.resize(28);bytes.fill(0);bytes.encode_u32(0,agent->sleep_pose);bytes.encode_u32(4,agent->state==SLEEPING?1:2);bytes.encode_float(8,agent->wake_elapsed);
    for(int axis=0;axis<3;++axis)bytes.encode_float(12+axis*4,agent->goal[axis]);bytes.encode_u32(24,agent->provoked?1:0);return bytes;
}
bool NativeZombieAwareness::restore_sleep(int64_t id,const PackedByteArray &bytes){
    auto *agent=find(id);if(!agent||agent->state!=IDLE||!valid_sleep_intent(bytes))return false;
    agent->sleep_pose=bytes.decode_u32(0);agent->state=bytes.decode_u32(4)==1?SLEEPING:WAKING;
    agent->ambusher=true;
    agent->wake_elapsed=std::min(agent->profile.wake,double(bytes.decode_float(8)));agent->provoked=bytes.decode_u32(24)!=0;
    for(int axis=0;axis<3;++axis)agent->goal[axis]=bytes.decode_float(12+axis*4);
    agent->last_seen=agent->goal;agent->visible=false;agent->confidence=agent->ignore=agent->unseen=0;
    agent->interest=agent->state==WAKING?agent->profile.pursuit*(agent->provoked?1.5:1):0;++agent->revision;return true;
}
void NativeZombieAwareness::remove_agent(int64_t id){agents_.erase(std::remove_if(agents_.begin(),agents_.end(),[&](const Agent &a){return a.id==id;}),agents_.end());}
void NativeZombieAwareness::clear(){agents_.clear();}
bool NativeZombieAwareness::wants_sight(int64_t id,const Vector3 &feet,const Vector3 &forward,const Vector3 &player){
    auto *a=find(id);if(!a||!feet.is_finite()||!forward.is_finite()||!player.is_finite())return false;
    const double distance=feet.distance_squared_to(player);
    if(a->state==SLEEPING){
        if(distance>a->profile.sleep_range*a->profile.sleep_range)return false;
        if(distance<=1.5*1.5)return true;
        Vector3 offset=player-feet;offset.y=0;Vector3 facing=forward;facing.y=0;
        return offset.normalized().dot(facing.normalized())>=-.1;
    }
    // A nearby visible threat may break disinterest, but walls still require a host ray.
    if(a->ignore>0&&distance>a->profile.near_sense*a->profile.near_sense)return false;
    double range=(a->state==CHASE||a->state==INVESTIGATE||a->state==SEARCH||a->state==WAKING||a->state==REPOSITION)?a->profile.tracking:a->profile.sight;
    Vector3 offset=player-feet;if(offset.length_squared()>range*range)return false;
    if(offset.length_squared()<=a->profile.near_sense*a->profile.near_sense)return true;
    offset.y=0;Vector3 facing=forward;facing.y=0;
    return a->state==CHASE||a->state==WAKING||a->state==INVESTIGATE||a->state==SEARCH||a->state==REPOSITION||a->provoked||offset.normalized().dot(facing.normalized())>=.342;
}
void NativeZombieAwareness::observe(int64_t id,const Vector3 &player,bool visible,double distance){
    auto *a=find(id);if(!a||!player.is_finite()||!std::isfinite(distance))return;
    a->close_visible=visible&&distance>=0&&distance<=a->profile.near_sense;
    if(a->state==SLEEPING){
        a->visible=visible&&distance>=0&&distance<=a->profile.sleep_range;
        if(a->visible)a->last_seen=player;else a->confidence=0;
        return;
    }
    if(a->state==WAKING){
        a->visible=visible;
        if(visible)a->last_seen=a->goal=player;
        return;
    }
    if(a->close_visible)a->ignore=0;
    a->visible=visible&&a->ignore<=0;
    if(a->visible){
        a->last_seen=player;a->unseen=0;
        // Seeing the recipient does not cancel a short, validated attempt to
        // get unstuck. Melee proximity can interrupt it immediately.
        if(a->state==REPOSITION&&distance>1.6){a->interest=std::max(a->interest,a->profile.pursuit);return;}
        a->goal=player;
        if(a->state==IDLE||a->state==WANDER||a->state==SUSPICIOUS){
            if(a->profile.notice>0&&!a->provoked){a->state=SUSPICIOUS;return;}
            a->interest=a->profile.pursuit;
        }
        a->state=CHASE;
        // Confirmed sight renews interest; escape requires losing the target.
        a->interest=std::max(a->interest,a->profile.pursuit);
    }
    // A missed probe is not disengagement. Recognition decays, and pursuit
    // spends a short grace period on its last confirmed clue without homing.
}
void NativeZombieAwareness::provoke(int64_t id,const Vector3 &player){
    auto *a=find(id);if(!a||!player.is_finite())return;
    if(a->state==SLEEPING||a->state==WAKING){wake(*a,player,true);return;}
    a->ignore=0;a->last_seen=a->goal=player;a->unseen=0;a->remaining=a->profile.forget;a->state=a->visible?CHASE:INVESTIGATE;a->provoked=true;a->interest=a->profile.pursuit*1.5;
}
bool NativeZombieAwareness::hear(int64_t id,const Vector3 &feet,const Vector3 &source,double radius){
    auto *a=find(id);
    if(!a||a->sound_cooldown>0||a->state==CHASE||!feet.is_finite()||!source.is_finite()||!std::isfinite(radius)||radius<=0||radius>14)return false;
    const double reach=radius*a->profile.hearing;if(feet.distance_squared_to(source)>reach*reach)return false;
    a->sound_cooldown=.8;
    a->ignore=0;
    if(a->state==SLEEPING||a->state==WAKING){wake(*a,source,false);return true;}
    a->last_seen=source;a->unseen=0;a->interest=std::max(a->interest,a->profile.pursuit);
    if(a->state==REPOSITION)return true;
    a->visible=false;a->goal=source;a->remaining=a->profile.forget;a->state=INVESTIGATE;return true;
}
bool NativeZombieAwareness::accept_roam(int64_t id,const Vector3 &supported){
    auto *a=find(id);if(!a||(a->state!=WANDER&&a->state!=SEARCH&&a->state!=REPOSITION))return false;
    if(!supported.is_finite()){
        if(a->state==WANDER)rest(*a);
        else {a->goal=a->search_origin;a->search_pending=true;a->remaining=0;}
        return false;
    }
    a->goal=supported;return true;
}
Dictionary NativeZombieAwareness::advance(int64_t id,const Vector3 &feet,double delta,bool active,const String &route_state){
    auto *a=find(id);if(!a||!feet.is_finite()||!std::isfinite(delta)||delta<=0||delta>.1)return {};
    if(!active){auto out=describe(*a);out["suspended"]=true;return out;}
    a->sound_cooldown=std::max(0.0,a->sound_cooldown-delta);
    if(a->state==SLEEPING){
        if(a->visible){a->confidence+=delta;if(a->confidence>=a->profile.sleep_notice)wake(*a,a->last_seen,false);}
        return describe(*a);
    }
    if(a->state==WAKING){a->wake_elapsed=std::min(a->profile.wake,a->wake_elapsed+delta);return describe(*a);}
    a->ignore=std::max(0.0,a->ignore-delta);a->remaining-=delta;
    if(a->state==SUSPICIOUS){
        a->confidence=a->visible?a->confidence+delta:std::max(0.0,a->confidence-delta*.5);
        if(!a->visible){if(a->confidence<=0)rest(*a);return describe(*a);}
        if(a->confidence>=std::min(a->profile.notice,a->close_visible?a->profile.close_notice:a->profile.notice)){a->state=CHASE;a->interest=a->profile.pursuit;a->unseen=0;}
        return describe(*a);
    }
    a->recovery_cooldown=std::max(0.0,a->recovery_cooldown-delta);
    a->search_retry=std::max(0.0,a->search_retry-delta);
    const bool engaged=a->state==CHASE||a->state==INVESTIGATE||a->state==SEARCH||a->state==REPOSITION;
    if(engaged){
        // Motivation follows evidence, not success of one route or random point.
        a->interest=std::max(0.0,a->interest-delta);
        if(a->visible)a->unseen=0;else a->unseen+=delta;
        const double memory=std::min(30.0,a->profile.forget*(a->ambusher?1.35:1));
        if(!a->visible&&(a->unseen>=memory||a->interest<=0)){
            a->ignore=a->profile.ignore;rest(*a);return describe(*a);
        }
        if(!a->has_progress_anchor||a->progress_anchor.distance_to(feet)>.08){
            a->progress_anchor=feet;a->has_progress_anchor=true;a->stationary=0;
        }else if(route_state=="planning"||route_state=="following"||route_state=="unavailable"||route_state=="blocked"||route_state=="search_limit")a->stationary+=delta;
        else a->stationary=0;
        a->blocked=(route_state=="blocked"||route_state=="search_limit")?a->blocked+delta:0;
        if(a->state==REPOSITION){
            if(a->remaining<=0||feet.distance_to(a->goal)<.6||a->blocked>.5){
                a->state=a->visible?CHASE:INVESTIGATE;a->goal=a->last_seen;a->stationary=a->blocked=0;++a->revision;
            }
            return describe(*a);
        }
        const bool needs_recovery=a->blocked>.5||a->stationary>1.5;
        if(needs_recovery&&a->recovery_cooldown<=0&&feet.distance_to(a->last_seen)>1.6){
            reposition(*a,feet);return describe(*a);
        }
        if(a->state==CHASE){
            if(!a->visible&&a->unseen>=a->profile.sight_grace){a->state=INVESTIGATE;a->goal=a->last_seen;++a->revision;}
        }else if(a->state==INVESTIGATE){
            if(feet.distance_to(a->goal)<.8)roam(*a,feet,true);
        }else if(a->state==SEARCH){
            if(a->search_retry<=0&&(a->search_pending||a->remaining<=0||feet.distance_to(a->goal)<.65||a->blocked>.5))roam(*a,feet,true);
        }
        return describe(*a);
    }
    a->blocked=(route_state=="blocked"||route_state=="search_limit")?a->blocked+delta:0;
    if(a->state==WANDER){
        if(feet.distance_to(a->goal)<.65||a->remaining<=0||a->blocked>2)rest(*a);
    }else if(a->remaining<=0)roam(*a,feet,false);
    return describe(*a);
}
Dictionary NativeZombieAwareness::status(int64_t id){auto *a=find(id);return a?describe(*a):Dictionary();}
}
