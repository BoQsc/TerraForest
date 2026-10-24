// SPDX-License-Identifier: 0BSD
#include "zombie_awareness.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeZombieAwareness::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","capacity","seed"),&NativeZombieAwareness::configure);
    ClassDB::bind_method(D_METHOD("add_agent","id","feet"),&NativeZombieAwareness::add_agent);
    ClassDB::bind_method(D_METHOD("remove_agent","id"),&NativeZombieAwareness::remove_agent);
    ClassDB::bind_method(D_METHOD("clear"),&NativeZombieAwareness::clear);
    ClassDB::bind_method(D_METHOD("wants_sight","id","feet","forward","player"),&NativeZombieAwareness::wants_sight);
    ClassDB::bind_method(D_METHOD("observe","id","player","visible"),&NativeZombieAwareness::observe);
    ClassDB::bind_method(D_METHOD("provoke","id","player"),&NativeZombieAwareness::provoke);
    ClassDB::bind_method(D_METHOD("accept_roam","id","supported"),&NativeZombieAwareness::accept_roam);
    ClassDB::bind_method(D_METHOD("advance","id","feet","delta","active","route_state"),&NativeZombieAwareness::advance);
    ClassDB::bind_method(D_METHOD("status","id"),&NativeZombieAwareness::status);
}
NativeZombieAwareness::Agent *NativeZombieAwareness::find(int64_t id){for(auto &a:agents_)if(a.id==id)return &a;return nullptr;}
double NativeZombieAwareness::random(Agent &a){a.random^=a.random<<13;a.random^=a.random>>17;a.random^=a.random<<5;return double(a.random)/4294967296.0;}
void NativeZombieAwareness::rest(Agent &a){a.state=IDLE;a.visible=false;a.remaining=1.5+random(a)*2.5;a.blocked=0;++a.revision;}
void NativeZombieAwareness::roam(Agent &a,const Vector3 &feet,bool search){
    const double angle=random(a)*6.283185307179586,radius=search?2+random(a)*2:4+random(a)*5;
    const Vector3 origin=search?a.last_seen:feet;
    a.goal=origin+Vector3(real_t(std::sin(angle)*radius),0,real_t(std::cos(angle)*radius));
    // Stay in the local neighbourhood instead of drifting indefinitely.
    if(!search&&a.goal.distance_to(a.home)>24)a.goal=feet.lerp(a.home,real_t(.5));
    a.state=search?SEARCH:WANDER;a.remaining=search?6:28;a.blocked=0;++a.revision;
}
Dictionary NativeZombieAwareness::describe(const Agent &a){
    static const char *names[]={"idle","wander","chase","investigate","search"};
    Dictionary out;out["state"]=names[a.state];out["goal"]=a.goal;out["revision"]=a.revision;
    out["moving"]=a.state!=IDLE;out["combat"]=a.state==CHASE;out["visible"]=a.visible;
    out["unseen_seconds"]=a.unseen;out["remaining_seconds"]=a.remaining;out["ignore_seconds"]=a.ignore;return out;
}
bool NativeZombieAwareness::configure(int capacity,int64_t seed){if(capacity_||capacity<1||capacity>6)return false;capacity_=capacity;seed_=uint32_t(seed)|1;agents_.reserve(capacity);return true;}
bool NativeZombieAwareness::add_agent(int64_t id,const Vector3 &feet){
    if(!capacity_||id<=0||!feet.is_finite()||find(id)||int(agents_.size())>=capacity_)return false;
    Agent a;a.id=id;a.home=a.goal=a.last_seen=feet;a.random=(seed_^uint32_t(id)^uint32_t(uint64_t(id)>>32))|1;
    a.remaining=.3+random(a)*1.7;agents_.push_back(a);return true;
}
void NativeZombieAwareness::remove_agent(int64_t id){agents_.erase(std::remove_if(agents_.begin(),agents_.end(),[&](const Agent &a){return a.id==id;}),agents_.end());}
void NativeZombieAwareness::clear(){agents_.clear();}
bool NativeZombieAwareness::wants_sight(int64_t id,const Vector3 &feet,const Vector3 &forward,const Vector3 &player){
    auto *a=find(id);if(!a||a->ignore>0||!feet.is_finite()||!forward.is_finite()||!player.is_finite())return false;
    Vector3 offset=player-feet;if(offset.length_squared()>((a->state==CHASE||a->state==INVESTIGATE||a->state==SEARCH)?36*36:24*24))return false;
    if(offset.length_squared()<=3.5*3.5)return true;
    offset.y=0;Vector3 facing=forward;facing.y=0;
    return a->state==CHASE||offset.normalized().dot(facing.normalized())>=.5;
}
void NativeZombieAwareness::observe(int64_t id,const Vector3 &player,bool visible){
    auto *a=find(id);if(!a||!player.is_finite())return;
    a->visible=visible&&a->ignore<=0;
    if(a->visible){a->last_seen=player;a->goal=player;a->state=CHASE;a->unseen=0;}
    else if(a->state==CHASE){a->state=INVESTIGATE;a->goal=a->last_seen;a->unseen=0;}
}
void NativeZombieAwareness::provoke(int64_t id,const Vector3 &player){
    auto *a=find(id);if(!a||!player.is_finite())return;
    a->ignore=0;a->last_seen=a->goal=player;a->unseen=0;a->remaining=18;a->state=INVESTIGATE;
}
bool NativeZombieAwareness::accept_roam(int64_t id,const Vector3 &supported){
    auto *a=find(id);if(!a||(a->state!=WANDER&&a->state!=SEARCH))return false;
    if(!supported.is_finite()){rest(*a);return false;}a->goal=supported;return true;
}
Dictionary NativeZombieAwareness::advance(int64_t id,const Vector3 &feet,double delta,bool active,const String &route_state){
    auto *a=find(id);if(!a||!feet.is_finite()||!std::isfinite(delta)||delta<=0||delta>.1)return {};
    if(!active){auto out=describe(*a);out["suspended"]=true;return out;}
    a->ignore=std::max(0.0,a->ignore-delta);a->remaining-=delta;
    a->blocked=(route_state=="blocked"||route_state=="search_limit")?a->blocked+delta:0;
    if(a->state==CHASE){
        if(feet.distance_to(a->last_seen)>64||a->blocked>6){a->ignore=10;rest(*a);}
    }else if(a->state==INVESTIGATE){
        a->unseen+=delta;
        if(a->unseen>=18||a->blocked>4){a->ignore=3;rest(*a);}
        else if(feet.distance_to(a->goal)<.8)roam(*a,feet,true);
    }else if(a->state==SEARCH){
        a->unseen+=delta;
        if(a->remaining<=0||a->unseen>=18||a->blocked>2){a->ignore=3;rest(*a);}
    }else if(a->state==WANDER){
        if(feet.distance_to(a->goal)<.65||a->remaining<=0||a->blocked>2)rest(*a);
    }else if(a->remaining<=0)roam(*a,feet,false);
    return describe(*a);
}
Dictionary NativeZombieAwareness::status(int64_t id){auto *a=find(id);return a?describe(*a):Dictionary();}
}
