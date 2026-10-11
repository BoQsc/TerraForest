// SPDX-License-Identifier: 0BSD
#include "water_surface.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/time.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeWaterSurface::_bind_methods(){
    ClassDB::bind_method(D_METHOD("begin","network","coordinate"),&NativeWaterSurface::begin);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterSurface::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterSurface::statistics);
    ClassDB::bind_method(D_METHOD("surface_arrays"),&NativeWaterSurface::surface_arrays);
}
bool NativeWaterSurface::current() const{return network.is_valid()&&network->current()&&network->water_revision==revision;}
bool NativeWaterSurface::begin(const Ref<NativeWaterNetwork> &water,const Vector3i &coordinate){
    if(status!=-1||water.is_null()||water->status!=1||!water->current()||bool(water->solver->statistics()["busy"]))return false;
    auto at=water->indices.find({coordinate.x,coordinate.y,coordinate.z});if(at==water->indices.end())return false;
    network=water;revision=water->water_revision;piece=at->second;status=0;
    if(int64_t(water->solver->statistics()["total_ml"])==0){status=1;phase=4;return true;}
    heads.resize(network->global_leaves,NAN);quads.resize(4096,NAN);return true;
}
void NativeWaterSurface::triangle(const Vector3 &a,const Vector3 &b,const Vector3 &c){
    // Godot front faces are clockwise; ascending x/z polygon order faces upward.
    triangles.push_back(a);triangles.push_back(b);triangles.push_back(c);
}
void NativeWaterSurface::unit(){
    if(phase==0){
        if(cursor==int(heads.size())){phase=1;cursor=0;return;}
        const Dictionary state=network->solver->inspect(cursor);
        if(int64_t(state["component_amount_ml"])>0)heads[cursor]=double(state["level_mm"])/1000.0;
        ++cursor;return;
    }
    const auto &p=network->pieces[piece];const auto &g=*p.profiles->topology.ptr();const auto view=g.view();
    auto world=[&](double x,double y,double z){return view.origin+Vector3(x,y,z)*view.spacing;};
    if(phase==1){
        if(cursor==4096){phase=2;cursor=0;return;}
        const int slot=cursor++;const Vector3i cell=g.first+Vector3i(slot%16,(slot/256)%16,(slot/16)%16);
        const int base=view.cell(cell.x,cell.y,cell.z)*6;double density[8],levels[6];bool full=true;
        for(int k=0;k<8;++k){const auto c=cell+lake_corner(k);density[k]=view.density[view.node(c.x,c.y,c.z)];full=full&&density[k]>0;}
        for(int t=0;t<6;++t){
            levels[t]=NAN;const auto first=g.ids.ptr(),end=first+g.ids.size(),at=std::lower_bound(first,end,base+t);
            if(at!=end&&*at==base+t)levels[t]=heads[network->mapping[p.offset+p.profiles->basins->owners[at-first]]];
            full=full&&std::isfinite(levels[t])&&(t==0||levels[t]==levels[0]);
        }
        const double fill=(levels[0]-view.origin.y)/view.spacing-cell.y;
        if(full&&fill>0&&fill<=1){quads[slot]=fill;return;}
        struct Point{Vector2 p;double d;};
        for(int t=0;t<6;++t){
            const double fy=(levels[t]-view.origin.y)/view.spacing-cell.y;
            if(!std::isfinite(fy)||fy<=0||fy>1)continue;
            Point polygon[6],clipped[8];int count=0,n=0;
            auto add=[&](Vector2 pos,double d){for(int i=0;i<count;++i)if(polygon[i].p.distance_squared_to(pos)<1e-12f)return;polygon[count++]={pos,d};};
            for(int k=0;k<4;++k){const auto c=lake_corner(lake_tets[t][k]);if(double(c.y)==fy)add(Vector2(c.x,c.z),density[lake_tets[t][k]]);}
            for(int a=0;a<4;++a)for(int b=a+1;b<4;++b){
                const auto ca=lake_corner(lake_tets[t][a]),cb=lake_corner(lake_tets[t][b]);
                if((ca.y<fy&&cb.y>fy)||(cb.y<fy&&ca.y>fy)){
                    const double f=(fy-ca.y)/(cb.y-ca.y);const Vector3 q=Vector3(ca)+(Vector3(cb)-Vector3(ca))*f;
                    add(Vector2(q.x,q.z),density[lake_tets[t][a]]+f*(density[lake_tets[t][b]]-density[lake_tets[t][a]]));}
            }
            if(count<3)continue;
            Vector2 center;for(int k=0;k<count;++k)center+=polygon[k].p;center/=count;
            std::sort(polygon,polygon+count,[&](const Point &a,const Point &b){return std::atan2(a.p.y-center.y,a.p.x-center.x)<std::atan2(b.p.y-center.y,b.p.x-center.x);});
            for(int k=0;k<count;++k){const auto a=polygon[k],b=polygon[(k+1)%count];
                if(a.d>0)clipped[n++]=a;
                if((a.d>0)!=(b.d>0)){const double f=a.d/(a.d-b.d);clipped[n++]={a.p+(b.p-a.p)*f,0};}}
            auto vertex=[&](int k){return world(cell.x+clipped[k].p.x,cell.y+fy,cell.z+clipped[k].p.y);};
            for(int k=1;k+1<n;++k)if(std::abs((clipped[k].p-clipped[0].p).cross(clipped[k+1].p-clipped[0].p))>1e-8f)triangle(vertex(0),vertex(k),vertex(k+1));
        }return;
    }
    if(phase==2){
        if(cursor==4096){vertices.resize(triangles.size());normals.resize(triangles.size());uv.resize(triangles.size());phase=3;cursor=0;return;}
        const int slot=cursor++,x=slot%16,z=(slot/16)%16,y=slot/256;const double fy=quads[slot];if(!std::isfinite(fy))return;
        int ex=x+1,ez=z+1;while(ex<16&&quads[y*256+z*16+ex]==fy)++ex;
        while(ez<16){bool match=true;for(int a=x;a<ex;++a)if(quads[y*256+ez*16+a]!=fy){match=false;break;}if(!match)break;++ez;}
        for(int b=z;b<ez;++b)for(int a=x;a<ex;++a)quads[y*256+b*16+a]=NAN;
        const double h=g.first.y+y+fy;const auto a=world(g.first.x+x,h,g.first.z+z),b=world(g.first.x+ex,h,g.first.z+z),c=world(g.first.x+ex,h,g.first.z+ez),d=world(g.first.x+x,h,g.first.z+ez);
        triangle(a,b,c);triangle(a,c,d);return;
    }
    if(phase==3){
        if(cursor==int(triangles.size())){status=1;phase=4;return;}
        const auto p=triangles[cursor];vertices.set(cursor,p);normals.set(cursor,Vector3(0,1,0));uv.set(cursor,Vector2(p.x,p.z));++cursor;
    }
}
Dictionary NativeWaterSurface::advance(int64_t budget){
    int64_t work=0;if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=0;return out;}
    if(status==0&&!current())status=-2;
    const auto start=Time::get_singleton()->get_ticks_usec();
    while(status==0&&work<budget){unit();++work;++work_total;if(work%16==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;}
    Dictionary out=statistics();out["ok"]=status>=0&&current();out["work_units"]=work;return out;
}
Dictionary NativeWaterSurface::statistics() const {Dictionary out;out["status"]=status;out["current"]=current();out["vertices"]=int64_t(triangles.size());out["work_units_total"]=work_total;return out;}
Array NativeWaterSurface::surface_arrays() const {
    Array out;if(status!=1||!current())return out;out.resize(Mesh::ARRAY_MAX);
    out[Mesh::ARRAY_VERTEX]=vertices;out[Mesh::ARRAY_NORMAL]=normals;out[Mesh::ARRAY_TEX_UV]=uv;return out;
}
}
