// SPDX-License-Identifier: 0BSD
#include "model_bounds_index.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace terraforest {
// Derived owner coverage only: no scene references or authoritative world data.
// Reuse the existing bounds tree and retain insertion order for bounded consumers.
class NativeOwnerBoundsIndex : public RefCounted {
    GDCLASS(NativeOwnerBoundsIndex,RefCounted)
    ModelBoundsIndex index;
    struct Owner {uint64_t order;bool active;};
    std::map<BlockKey,Owner> owners;
    std::set<BlockKey> unbounded;
    uint64_t serial=0;
    mutable uint64_t query_nodes=0;
    static BlockKey key(Vector2i value){return {value.x,0,value.y};}
    static bool valid(Vector2i value){return value.x>=-32768&&value.x<=32767&&value.y>=-32768&&value.y<=32767;}
    bool admit(Vector2i value,bool active){
        if(!valid(value))return false;
        auto k=key(value);auto found=owners.find(k);
        if(found==owners.end()){
            if(owners.size()>=16384)return false;
            owners.emplace(k,Owner{++serial,active});
        }else found->second.active=active;
        return true;
    }
    TypedArray<Vector2i> ordered(std::vector<std::pair<uint64_t,BlockKey>> &hits)const{
        std::sort(hits.begin(),hits.end(),[](const auto &a,const auto &b){return a.first<b.first;});
        TypedArray<Vector2i> out;for(const auto &hit:hits)out.push_back(Vector2i(hit.second.x,hit.second.z));return out;
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("set_bounds","owner","bounds"),&NativeOwnerBoundsIndex::set_bounds);
        ClassDB::bind_method(D_METHOD("set_unbounded","owner"),&NativeOwnerBoundsIndex::set_unbounded);
        ClassDB::bind_method(D_METHOD("set_inactive","owner"),&NativeOwnerBoundsIndex::set_inactive);
        ClassDB::bind_method(D_METHOD("erase","owner"),&NativeOwnerBoundsIndex::erase);
        ClassDB::bind_method(D_METHOD("clear"),&NativeOwnerBoundsIndex::clear);
        ClassDB::bind_method(D_METHOD("intersecting","bounds"),&NativeOwnerBoundsIndex::intersecting);
        ClassDB::bind_method(D_METHOD("all_owners"),&NativeOwnerBoundsIndex::all_owners);
        ClassDB::bind_method(D_METHOD("statistics"),&NativeOwnerBoundsIndex::statistics);
    }
public:
    bool set_bounds(Vector2i owner,const AABB &bounds){
        if(!bounds.position.is_finite()||!bounds.size.is_finite()||!bounds.get_end().is_finite()||
           bounds.size.x<0||bounds.size.y<0||bounds.size.z<0||!admit(owner,true))return false;
        index.insert(key(owner),bounds);unbounded.erase(key(owner));return true;
    }
    bool set_unbounded(Vector2i owner){if(!admit(owner,true))return false;index.erase(key(owner));unbounded.insert(key(owner));return true;}
    bool set_inactive(Vector2i owner){if(!admit(owner,false))return false;index.erase(key(owner));unbounded.erase(key(owner));return true;}
    void erase(Vector2i owner){if(!valid(owner))return;index.erase(key(owner));owners.erase(key(owner));unbounded.erase(key(owner));}
    void clear(){index.clear();owners.clear();unbounded.clear();serial=0;query_nodes=0;}
    TypedArray<Vector2i> all_owners()const{
        std::vector<std::pair<uint64_t,BlockKey>> hits;hits.reserve(owners.size());
        for(const auto &entry:owners)if(entry.second.active)hits.emplace_back(entry.second.order,entry.first);
        return ordered(hits);
    }
    TypedArray<Vector2i> intersecting(const AABB &bounds)const{
        query_nodes=0;
        if(!bounds.position.is_finite()||!bounds.size.is_finite()||!bounds.get_end().is_finite()||
           bounds.size.x<0||bounds.size.y<0||bounds.size.z<0)return {};
        std::vector<std::pair<uint64_t,BlockKey>> hits;
        for(const auto &owner:unbounded)hits.emplace_back(owners.at(owner).order,owner);
        const auto visit=[&](const auto &self,const ModelBoundsIndex::Node *node)->void{
            if(!node)return;++query_nodes;
            if(!node->bounds.intersects(bounds))return;
            if(node->box.intersects(bounds))hits.emplace_back(owners.at(node->key).order,node->key);
            self(self,node->left.get());self(self,node->right.get());
        };
        visit(visit,index.root());return ordered(hits);
    }
    Dictionary statistics()const{
        Dictionary out;out["owners"]=int64_t(owners.size());out["bounded"]=int64_t(index.size());
        out["last_query_nodes"]=int64_t(query_nodes);return out;
    }
};
void register_owner_bounds(){GDREGISTER_CLASS(NativeOwnerBoundsIndex);}
}
