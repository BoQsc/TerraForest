// SPDX-License-Identifier: 0BSD
#pragma once
#include "scatter.hpp"
#include <map>
namespace terraforest {
// Resident interaction proxies, not physics bodies. Queries use semantic clump bounds.
class NativeGroundCoverPicker : public RefCounted {
    GDCLASS(NativeGroundCoverPicker,RefCounted)
    struct Item {int64_t id;int species;Transform3D inverse;};
    std::map<int,std::vector<Item>> cells;
    static bool valid_cell(Vector2i key){return key.x>=0&&key.y>=0&&key.x<63&&key.y<63;}
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("replace_cell","cell","species"),&NativeGroundCoverPicker::replace_cell);
        ClassDB::bind_method(D_METHOD("remove_cell","cell"),&NativeGroundCoverPicker::remove_cell);
        ClassDB::bind_method(D_METHOD("pick","from","to"),&NativeGroundCoverPicker::pick);
    }
public:
    bool replace_cell(Vector2i key,const Array &species){
        if(!valid_cell(key)||species.size()!=3)return false;
        int owner=key.y*63+key.x;
        if(!cells.count(owner)&&cells.size()>=49)return false;
        std::vector<Item> staged;std::unordered_set<int64_t> seen;
        for(int s=0;s<3;++s){
            if(species[s].get_type()!=Variant::DICTIONARY)return false;
            Dictionary row=species[s];
            if(!row.has("ids")||!row.has("transforms")||row["ids"].get_type()!=Variant::PACKED_INT64_ARRAY||row["transforms"].get_type()!=Variant::PACKED_FLOAT32_ARRAY)return false;
            PackedInt64Array ids=row["ids"];PackedFloat32Array values=row["transforms"];
            if(staged.size()+ids.size()>320||values.size()!=ids.size()*12)return false;
            for(int64_t i=0;i<ids.size();++i){
                if(ids[i]<=0||!seen.insert(ids[i]).second)return false;
                const float *p=values.ptr()+i*12;
                Transform3D t;for(int r=0;r<3;++r){for(int c=0;c<3;++c)t.basis[r][c]=p[r*4+c];t.origin[r]=p[r*4+3];}
                if(!t.is_finite()||std::abs(t.basis.determinant())<.001||t.origin.x<key.x*32||t.origin.x>=(key.x+1)*32||t.origin.z<key.y*32||t.origin.z>=(key.y+1)*32)return false;
                // Row norm bounds guarantee the proxy never extends beyond the 8m query padding, even for shear.
                for(int r=0;r<3;++r)if(t.basis[r].length_squared()>48.f)return false;
                staged.push_back({ids[i],s,t.affine_inverse()});
            }
        }
        cells[owner]=std::move(staged);return true;
    }
    void remove_cell(Vector2i key){if(valid_cell(key))cells.erase(key.y*63+key.x);}
    Dictionary pick(Vector3 from,Vector3 to) const{
        Dictionary out;out["hit"]=false;out["tested"]=0;out["cells"]=0;
        if(!from.is_finite()||!to.is_finite()||from.distance_squared_to(to)>64.01||from==to||std::abs(from.x)>100000||std::abs(from.z)>100000)return out;
        int x0=std::max(0,int(std::floor((std::min(from.x,to.x)-8)/32))),x1=std::min(62,int(std::floor((std::max(from.x,to.x)+8)/32)));
        int z0=std::max(0,int(std::floor((std::min(from.z,to.z)-8)/32))),z1=std::min(62,int(std::floor((std::max(from.z,to.z)+8)/32)));
        double closest=2;int64_t selected=0;int selected_species=0,selected_owner=0,tested=0,visited=0;
        for(int z=z0;z<=z1;++z)for(int x=x0;x<=x1;++x){
            ++visited;auto found=cells.find(z*63+x);if(found==cells.end())continue;
            for(const auto &item:found->second){
                ++tested;Vector3 start=item.inverse.xform(from),end=item.inverse.xform(to),direction=end-start;
                Vector3 low(-.4,item.species==0?-.2:0,-.4),high(.4,item.species==0?.2:.75,.4);
                double enter=0,leave=1;bool hit=true;
                for(int axis=0;axis<3;++axis){
                    if(std::abs(direction[axis])<1e-9){if(start[axis]<low[axis]||start[axis]>high[axis]){hit=false;break;}}
                    else{double a=(low[axis]-start[axis])/direction[axis],b=(high[axis]-start[axis])/direction[axis];if(a>b)std::swap(a,b);enter=std::max(enter,a);leave=std::min(leave,b);if(enter>leave){hit=false;break;}}
                }
                if(hit&&(enter<closest||(enter==closest&&item.id<selected))){closest=enter;selected=item.id;selected_species=item.species;selected_owner=z*63+x;}
            }
        }
        out["tested"]=tested;out["cells"]=visited;
        if(selected){out["hit"]=true;out["id"]=selected;out["cell"]=Vector2i(selected_owner%63,selected_owner/63);out["species"]=selected_species;out["fraction"]=closest;out["position"]=from+(to-from)*closest;}
        return out;
    }
};
}
