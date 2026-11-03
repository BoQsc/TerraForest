// SPDX-License-Identifier: 0BSD
#include "block_prefab.hpp"
#include "block_shapes.hpp"
#include <map>
#include <set>
#include <tuple>
#include <algorithm>
#include <cmath>
namespace terraforest {
Dictionary NativeBlockPrefab::interior_light_sites() const {
    Dictionary result;result["ok"]=false;Array rooms;
    if(bounds.size.x>128||bounds.size.y>128||bounds.size.z>128||cells.size()>200000)return result;
    using Key=std::tuple<int,int,int>;
    std::map<Key,int> words;std::set<int> levels;
    for(const auto &cell:cells){words[{cell.x,cell.y,cell.z}]=cell.word;levels.insert(cell.y+1);}
    auto solid=[&](Vector3 point){
        Vector3 floor=point.floor();auto found=words.find({int(floor.x),int(floor.y),int(floor.z)});
        if(found==words.end())return false;
        int word=found->second;Vector3 local=block_basis(block_rotation(word)).transposed().xform(point-floor-Vector3(.5,.5,.5))+Vector3(.5,.5,.5);
        bool any=false,inside=true;
        visit_shape_hulls(block_shape(word),[&](){inside=true;},[&](Vector3 normal,double offset){if(normal.dot(local)>offset+1e-6)inside=false;},[&](){any=any||inside;});
        return any;
    };
    std::vector<AABB> doors;
    for(int index=0;index<model_attachments.size();++index){Dictionary row=model_attachments[index];String name=row["model"];
        if(name.contains("door")){Transform3D pose=row["transform"];doors.push_back(pose.xform(AABB(Vector3(-.1,0,-.3),Vector3(1.2,2,.6))));}
    }
    int low_x=int(std::floor(bounds.position.x)),high_x=int(std::ceil(bounds.get_end().x));
    int low_z=int(std::floor(bounds.position.z)),high_z=int(std::ceil(bounds.get_end().z));
    uint64_t probes=0;
    for(int level:levels){
        std::set<std::pair<int,int>> walk;
        for(int row=low_z;row<high_z;++row)for(int column=low_x;column<high_x;++column){
            if(++probes>200000)return result;
            auto support=words.find({column,level-1,row});
            if(support==words.end()||(block_shape(support->second)!=1&&block_shape(support->second)!=8))continue;
            Vector3 feet(column+.5,level,row+.5);
            if(!solid(feet-Vector3(0,.02,0))||solid(feet+Vector3(0,.03,0))||solid(feet+Vector3(0,1,0))||solid(feet+Vector3(0,2.15,0)))continue;
            bool doorway=false;for(const auto &door:doors)if(door.grow(.1).has_point(feet+Vector3(0,.5,0)))doorway=true;
            if(doorway)continue;
            bool covered=false;for(int above=3;above<=12;++above)if(words.count({column,level+above,row})){covered=true;break;}
            if(covered)walk.insert({column,row});
        }
        while(!walk.empty()){
            std::vector<std::pair<int,int>> pending{*walk.begin()},region;walk.erase(walk.begin());
            for(size_t cursor=0;cursor<pending.size();++cursor){
                auto cell=pending[cursor];region.push_back(cell);
                for(auto step:std::vector<std::pair<int,int>>{{1,0},{-1,0},{0,1},{0,-1}}){auto next=std::make_pair(cell.first+step.first,cell.second+step.second);auto found=walk.find(next);if(found!=walk.end()){pending.push_back(next);walk.erase(found);}}
            }
            if(region.size()<4)continue;
            std::set<std::pair<int,int>> members(region.begin(),region.end());
            bool room_width=false;
            for(auto cell:region)if(members.count({cell.first+1,cell.second})&&members.count({cell.first,cell.second+1})&&members.count({cell.first+1,cell.second+1})){room_width=true;break;}
            if(!room_width)continue;
            struct Choice {Vector3 point;int walls;double distance;};std::vector<Choice> choices;
            Vector3 center;for(auto cell:region)center+=Vector3(cell.first+.5,level,cell.second+.5);center/=region.size();
            for(auto cell:region){
                Vector3 feet(cell.first+.5,level,cell.second+.5);int walls=0;
                for(Vector3 direction:std::vector<Vector3>{Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)})if(solid(feet+direction+Vector3(0,1.2,0)))++walls;
                bool near_door=false;for(const auto &door:doors)if(door.grow(1.2).has_point(feet+Vector3(0,.5,0)))near_door=true;
                if(!near_door)choices.push_back({feet,walls,feet.distance_squared_to(center)});
            }
            std::sort(choices.begin(),choices.end(),[](const Choice &first,const Choice &second){if(first.walls!=second.walls)return first.walls>second.walls;if(first.distance!=second.distance)return first.distance>second.distance;return std::tie(first.point.x,first.point.z)<std::tie(second.point.x,second.point.z);});
            PackedVector3Array candidates;
            for(const auto &choice:choices){if(candidates.size()==16)break;candidates.push_back(choice.point);}
            if(candidates.is_empty())continue;
            if(rooms.size()==128)return result;
            Dictionary room;room["floor"]=level;room["area"]=int(region.size());room["candidates"]=candidates;rooms.push_back(room);
        }
    }
    result["ok"]=true;result["rooms"]=rooms;result["probes"]=int64_t(probes);return result;
}
}
