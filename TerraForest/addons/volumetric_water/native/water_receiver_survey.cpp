// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_terrain_class.hpp"
#include <algorithm>
#include <cstring>

using namespace godot;
namespace terraforest {

// Obtain cheap geometric certificates for a bounded part of the brush. This
// does not reserve a region, allocate water, or infer a connection across a
// mixed brick. A failed or oversized survey retains the normal face traversal.
void NativeWaterEquilibriumJob::expand_air_frontier(){
    using W=NativeRegionalWater;
    if(wet_frontier.entries.empty()||field_readers.empty()||cancelled.load())return;
    const Vector3i steps[]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
    if(!survey_attempted){
        survey_attempted=true;
        if(wide_edit_bounds.size()!=1)return;
        const auto &[lo,hi]=wide_edit_bounds.front();
        const int last_y=std::min(hi.y,int(std::ceil(wet_frontier.head*.25))-1);
        const size_t count=size_t(hi.x-lo.x+1)*(hi.z-lo.z+1)*std::max(0,last_y-lo.y+1);
        // Includes dictionary nodes, coordinates and the temporary batch.
        if(count<128||count>8192||count*128>hierarchy_cell_limit*1024/32)return;
        std::vector<std::vector<Vector3i>> batches(field_readers.size());
        for(int z=lo.z;z<=hi.z;++z)for(int x=lo.x;x<=hi.x;++x){
            const Rect2i footprint(x*4,z*4,4,4);
            auto owner=std::find_if(field_readers.begin(),field_readers.end(),[&](const FieldReader &r){return r.bounds.encloses(footprint);});
            if(owner==field_readers.end())owner=std::find_if(field_readers.begin(),field_readers.end(),[&](const FieldReader &r){return r.bounds.grow(29).encloses(footprint);});
            if(owner==field_readers.end())continue;
            auto &batch=batches[size_t(owner-field_readers.begin())];
            for(int y=lo.y;y<=last_y;++y){
                Vector3i b(x,y,z);const auto key=W::key(b);
                if(frozen->regions.count(key)||existing_outside.count(key)||receiver_neighbours.count(key)||
                   !clear_structure_bounds.encloses(AABB(Vector3(b)*4,Vector3(4,4,4)))||structure_hulls.has(b))continue;
                if(frozen->surrounding_ocean&&y>=7&&y<=10&&std::min({x,z,499-x,499-z})<35)continue;
                batch.push_back(b);
            }
        }
        for(size_t f=0;f<batches.size();++f){
            auto &core=field_readers[f].core;const auto &batch=batches[f];
            if(batch.empty()||!core->has_method("classify_water_bricks"))continue;
            for(size_t start=0;start<batch.size();start+=2048){
                if(cancelled.load())return;
                const int n=int(std::min<size_t>(2048,batch.size()-start));
                PackedInt32Array origins;if(origins.resize(n*3)!=OK)return;
                auto *p=origins.ptrw();
                for(int j=0;j<n;++j)for(int axis=0;axis<3;++axis)*p++=4*batch[start+j][axis];
                PackedByteArray classes=classify_edit_bricks(core.ptr(),origins,field_revision,field_epoch);
                if(classes.size()!=n*17)return;
                const auto *data=classes.ptr();
                for(int j=0;j<n;++j){
                    ReceiverClass record;std::memcpy(record.data(),data+17*j,17);
                    receiver_classes.emplace(W::key(batch[start+j]),record);
                }
            }
        }
        hierarchy_cell_limit-=(128*count+1023)/1024;
        cell_limit=std::min(cell_limit,4*hierarchy_cell_limit);
    }
    if(receiver_classes.empty())return;
    std::vector<uint64_t> open;
    for(const auto &[key,entry]:wet_frontier.entries){
        auto sample=receiver_classes.find(key);if(sample==receiver_classes.end()||sample->second[0]!=1)continue;
        // The existing frontier has already tested the source profile against
        // a full-air neighbour at this head. The class proves that assumption.
        open.push_back(key);
    }
    for(size_t i=0;i<open.size()&&!cancelled.load();++i){
        const auto b=W::position(open[i]);
        auto entry=wet_frontier.entries.at(open[i]);
        auto start=entry.first+steps[entry.second];
        for(int d=0;d<6;++d){
            auto p=start;int axis=d==0||d==5?1:(d<=2?0:2);
            p[axis]=b[axis]*8+(steps[d][axis]>0?7:0);
            auto q=p+steps[d];
            if(!W::in_domain(q)||std::max(p.y,q.y)*.5>=wet_frontier.head)continue;
            const auto key=W::region_key(q);
            auto sample=receiver_classes.find(key);
            if(sample==receiver_classes.end()||frozen->regions.count(key)||wet_frontier.entries.count(key))continue;
            if(required.size()+prepared_receivers.size()>=receiver_slots)return;
            bool external=false;
            for(auto step:steps){
                auto n=W::position(key)+step;
                if(n.x<0||n.y<0||n.z<0||n.x>=500||n.y>=64||n.z>=500)continue;
                auto neighbor=W::key(n);
                if(existing_outside.count(neighbor)&&!receiver_neighbours.count(neighbor)){external=true;break;}
            }
            if(external)continue;
            wet_frontier.entries.emplace(key,std::make_pair(p,d));
            required.push_back(key);++air_frontier_receivers;
            if(sample->second[0]==1)open.push_back(key);
        }
    }
}
}
