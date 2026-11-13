// SPDX-License-Identifier: 0BSD
#include "water_basin_equilibrium.hpp"
#include "implicit_water_surface.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
using namespace godot;
namespace terraforest {
void NativeWaterBasinEquilibrium::_bind_methods(){
    ClassDB::bind_method(D_METHOD("solve","terrain","cells","spacing","quantity_ml","maximum_head"),&NativeWaterBasinEquilibrium::solve);
}
Dictionary NativeWaterBasinEquilibrium::solve(const PackedFloat32Array &terrain,int64_t cells,double spacing,int64_t quantity_ml,double maximum_head) const {
    Dictionary result;result["ok"]=false;result["quantity_ml"]=quantity_ml;
    if(cells<2||cells>64||!std::isfinite(spacing)||spacing<=0||spacing>4||quantity_ml<=0||quantity_ml>(int64_t(1)<<52)||!std::isfinite(maximum_head)||maximum_head<=0||maximum_head>cells*spacing){
        result["reason"]="Invalid bounded basin input";return result;
    }
    const int s=int(cells)+2,count=s*s*s;
    if(terrain.size()!=count){result["reason"]="Invalid terrain lattice";return result;}
    for(float d:terrain)if(!std::isfinite(d)){result["reason"]="Non-finite terrain";return result;}
    const uint64_t started=Time::get_singleton()->get_ticks_usec();
    Ref<NativeImplicitWaterSurface> extractor;extractor.instantiate();
    PackedFloat32Array field;field.resize(count);
    std::vector<uint8_t> visited(count);std::vector<int> queue;queue.reserve(count);
    bool open=false,disconnected=false;
    // Keep quantity authoritative in integer units. A render-volume tolerance
    // never rounds, deletes or manufactures this quantity.
    auto evaluate=[&](double head,Dictionary &packet,double &volume)->bool {
        int first=-1,wet=0;open=false;disconnected=false;
        std::fill(visited.begin(),visited.end(),0);
        for(int i=0;i<count;++i){
            const int x=i%s,y=(i/s)%s,z=i/(s*s);
            float d=std::max(float((y-1)*spacing-head),-terrain[i]);field.set(i,d);
            if(d<0){if(first<0)first=i;++wet;if(x==0||y==0||z==0||x==s-1||y==s-1||z==s-1)open=true;}
        }
        if(open)return false;
        if(first>=0){
            queue.clear();queue.push_back(first);visited[first]=1;
            for(size_t j=0;j<queue.size();++j){int i=queue[j];
                for(int offset:{-1,1,-s,s,-s*s,s*s}){int next=i+offset;
                    if(next>=0&&next<count&&!visited[next]&&field[next]<0){visited[next]=1;queue.push_back(next);}}
            }
            disconnected=int(queue.size())!=wet;
        }
        // Do not assign a common level to isolated basins. Their individual
        // quantities/spill history are required by the world-level service.
        if(disconnected)return false;
        packet=extractor->extract(field,cells,spacing);if(!bool(packet["ok"]))return false;
        Array arrays=packet["arrays"];PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
        double sum=0;
        for(int i=0;i<vertices.size();i+=3){
            const auto a=vertices[i],b=vertices[i+1],c=vertices[i+2];
            sum+=(double(a.x)*(double(b.y)*c.z-double(b.z)*c.y)+double(a.y)*(double(b.z)*c.x-double(b.x)*c.z)+double(a.z)*(double(b.x)*c.y-double(b.y)*c.x))/6.;
        }
        volume=std::abs(sum);return true;
    };
    Dictionary packet;double capacity=0;
    if(!evaluate(maximum_head,packet,capacity)){
        result["reason"]=open?"Basin reaches unavailable boundary":disconnected?"Separate basin quantities required":"Surface extraction failed";return result;
    }
    const double target=double(quantity_ml)*1e-6;
    if(target>capacity){result["reason"]="Quantity exceeds closed basin range";result["capacity_m3"]=capacity;return result;}
    double low=-spacing,high=maximum_head,head=high,volume=capacity;
    int iterations=0;
    for(;iterations<24;++iterations){
        head=(low+high)*.5;
        if(!evaluate(head,packet,volume)){
            result["reason"]=open?"Basin reaches unavailable boundary":disconnected?"Separate basin quantities required":"Surface extraction failed";return result;
        }
        if(std::abs(volume-target)<=std::max(1e-6,target*1e-5))break;
        if(volume<target)low=head;else high=head;
    }
    if(std::abs(volume-target)>std::max(1e-6,target*1e-4)){
        result["reason"]="Unresolved sub-lattice quantity";return result;
    }
    result["ok"]=true;result["head"]=head;result["field"]=field;result["surface"]=packet;
    result["boundary_volume_m3"]=volume;result["iterations"]=iterations+1;
    result["solve_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);
    result["scope"]="closed single basin reference";return result;
}
}
