// SPDX-License-Identifier: 0BSD
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <algorithm>
#include <cmath>
#include <set>
#include <vector>
using namespace godot;
namespace terraforest {
class NativeGenerationEarthworks : public RefCounted {
    GDCLASS(NativeGenerationEarthworks,RefCounted)
    static void endpoints(PackedByteArray &p,const Vector3 &a,const Vector3 &b){for(int axis=0;axis<3;++axis){p.encode_float(4+axis*4,a[axis]);p.encode_float(16+axis*4,b[axis]);}}
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("arrival_points","roads","reserved","south"),&NativeGenerationEarthworks::arrival_points);
        ClassDB::bind_method(D_METHOD("heights","core","points"),&NativeGenerationEarthworks::heights);
        ClassDB::bind_method(D_METHOD("access_quality","core","paths"),&NativeGenerationEarthworks::access_quality);
        ClassDB::bind_method(D_METHOD("sample_ground","terrain","points"),&NativeGenerationEarthworks::sample_ground);
        ClassDB::bind_method(D_METHOD("compile","segments","deposits"),&NativeGenerationEarthworks::compile);
        ClassDB::bind_method(D_METHOD("ordered","segments"),&NativeGenerationEarthworks::ordered);
        ClassDB::bind_method(D_METHOD("curve_prefix","segment"),&NativeGenerationEarthworks::curve_prefix);
    }
public:
    Dictionary access_quality(const Ref<RefCounted> &core,const Array &paths) const {
        auto reject=[](const char *reason){Dictionary d;d["status"]="rejected";d["reason"]=reason;return d;};
        if(paths.size()>32)return reject("Invalid access span");
        PackedVector3Array probes;
        for(int i=0;i<paths.size();++i){
            if(paths[i].get_type()!=Variant::DICTIONARY)return reject("Invalid access span");const Dictionary path=paths[i];
            if(path.get("start",Variant()).get_type()!=Variant::VECTOR3||path.get("finish",Variant()).get_type()!=Variant::VECTOR3)return reject("Invalid access span");
            const Vector3 start=path["start"],finish=path["finish"];const double width=path.get("half_width",0.);
            if(!start.is_finite()||!finish.is_finite()||!std::isfinite(width)||width<0)return reject("Invalid access span");
            const Vector2 span(finish.x-start.x,finish.z-start.z);const double length=span.length();
            if(length<=0||length>64)return reject("Invalid access span");const int steps=int(std::ceil(length*2));
            const Vector3 across=Vector3(-span.y,0,span.x).normalized();
            if(std::abs(double(finish.y)-start.y)>length*.25)return reject("Approach exceeds 25% grade");
            for(int index=0;index<=steps;++index)for(double side:{-1.,0.,1.})probes.push_back(start.lerp(finish,double(index)/steps)+across*width*side);
        }
        const auto raw=heights(core,probes);if(raw.size()!=probes.size())return reject("Incomplete approach survey");
        double fill=0,cut=0;
        for(int i=0;i<raw.size();++i){fill=std::max(fill,double(probes[i].y)-raw[i]);cut=std::max(cut,double(raw[i])-probes[i].y);}
        Dictionary out;out["status"]=fill<=2&&cut<=3?"pass":"rejected";out["max_fill"]=fill;out["max_cut"]=cut;out["samples"]=raw.size();return out;
    }
    Array arrival_points(const Array &roads,const Array &reserved,bool south) const {
        if(roads.size()>32768||reserved.size()>4096)return {};
        std::vector<Rect2> exclusions;exclusions.reserve(reserved.size());
        for(int i=0;i<reserved.size();++i){if(reserved[i].get_type()!=Variant::RECT2)return {};Rect2 area=reserved[i];exclusions.push_back(area.grow(6));}
        std::set<Vector3> seen;std::vector<Vector3> points;
        for(int i=0;i<roads.size();++i){
            if(roads[i].get_type()!=Variant::DICTIONARY)return {};const Dictionary road=roads[i];
            for(const char *key:{"start","finish"}){
                if(!road.has(key)||road[key].get_type()!=Variant::VECTOR3)return {};const Vector3 point=road[key];
                if(!point.is_finite())return {};if(!seen.insert(point).second)continue;
                bool blocked=false;for(const auto &area:exclusions)if(area.has_point(Vector2(point.x,point.z))){blocked=true;break;}
                if(!blocked)points.push_back(point);
            }
        }
        std::sort(points.begin(),points.end(),[south](const Vector3&a,const Vector3&b){return a.z==b.z?a.x>b.x:south?a.z>b.z:a.z<b.z;});
        Array out;for(size_t i=0;i<std::min<size_t>(8,points.size());++i)out.push_back(points[i]);return out;
    }
    PackedFloat32Array heights(const Ref<RefCounted> &core,const PackedVector3Array &points) const {
        if(core.is_null()||!core->is_class("TerrainCore")||points.size()>131072)return {};
        PackedFloat32Array out;out.resize(points.size());
        for(int offset=0;offset<points.size();offset+=256){
            const int count=std::min<int>(256,points.size()-offset);PackedByteArray packet;packet.resize(8);packet.encode_u32(0,37);packet.encode_u32(4,count);
            packet.append_array(points.slice(offset,offset+count).to_byte_array());const PackedByteArray reply=core->call("execute",packet);
            if(reply.size()!=12+count*8||reply.decode_u32(0)!=0x32505254||reply.decode_u32(8)!=0)return {};
            for(int i=0;i<count;++i)out.set(offset+i,reply.decode_float(12+i*8));
        }
        return out;
    }
    Dictionary sample_ground(Object *terrain,const PackedVector3Array &points) const {
        Dictionary out;out["ok"]=false;
        if(!terrain||points.is_empty()||points.size()>32||!bool(terrain->get("world_ready"))||!bool(terrain->get("diagnostics_pause_streaming"))||bool(terrain->get("pending_edit"))||bool(terrain->get("stopping")))return out;
        Object *backend=terrain->get("backend");if(!backend)return out;
        Ref<RefCounted> core=backend->get("native");if(core.is_null()||!core->is_class("TerrainCore"))return out;
        const int64_t revision=terrain->get("density_revision"),epoch=backend->get("build_epoch");
        PackedVector3Array surfaces,normals;
        for(int i=0;i<points.size();++i){
            if(!points[i].is_finite())return out;
            Vector3 top=points[i],bottom=points[i];top.y=std::min(249.,double(top.y)+8);bottom.y=std::max(1.,double(bottom.y)-8);
            PackedByteArray packet;packet.resize(36);packet.encode_u32(0,24);endpoints(packet,top,bottom);packet.encode_u32(28,64);packet.encode_u32(32,epoch);
            const PackedByteArray reply=core->call("execute",packet);
            if(reply.size()!=52||reply.decode_u32(0)!=0x32505254||reply.decode_u32(4)!=24||reply.decode_u32(8)!=0||reply.decode_u32(12)!=revision||reply.decode_u32(20)>64)return out;
            if(reply.decode_u32(16)==1){out["ok"]=true;out["supported"]=false;return out;}
            if(reply.decode_u32(16)!=0)return out;
            Vector3 point,normal;for(int axis=0;axis<3;++axis){point[axis]=reply.decode_float(28+axis*4);normal[axis]=reply.decode_float(40+axis*4);}
            if(!point.is_finite()||!normal.is_finite())return out;surfaces.push_back(point);normals.push_back(normal);
        }
        out["ok"]=true;out["supported"]=true;out["points"]=surfaces;out["normals"]=normals;return out;
    }
    Array ordered(const Array &segments) const {
        if(segments.size()>16384)return {};
        Array phases[4];
        for(int i=0;i<segments.size();++i){
            if(segments[i].get_type()!=Variant::DICTIONARY)return {};
            const Dictionary s=segments[i];const String phase=s.get("phase",String());
            if(phase!=""&&phase!="excavation"&&phase!="surface_clearance")return {};
            if(bool(s.get("arched",false))&&(phase!="excavation"||!bool(s.get("cut_only",false))||bool(s.get("rectangular",false))||bool(s.get("level_caps",false))||double(s.get("shoulder",0))!=0||s.has("coefficients")))return {};
            if(phase=="surface_clearance"&&(!bool(s.get("cut_only",false))||!bool(s.get("rectangular",false))))return {};
            if(!s.has("material"))return {};
            phases[phase=="excavation"?2:phase=="surface_clearance"?3:int64_t(s["material"])==4?1:0].push_back(s);
        }
        Array out;for(const auto &phase:phases)out.append_array(phase);return out;
    }
    PackedFloat64Array curve_prefix(const Dictionary &s) const {
        const PackedFloat64Array coefficients=s.get("coefficients",PackedFloat64Array());
        int64_t index=s.get("curve_index",-1);
        if(coefficients.size()%4||coefficients.size()>256||index<0||index>=coefficients.size()/4)return coefficients;
        const Vector3 a=s.get("start",Vector3()),b=s.get("finish",Vector3());
        // GDScript promotes vector components to doubles before subtraction,
        // then narrows into Vector2. Preserve that boundary for exact packets.
        const double span=Vector2(double(b.x)-double(a.x),double(b.z)-double(a.z)).length();
        if(span<1)return coefficients;
        const int following=int(std::ceil(std::sqrt(2.)*(double(s.get("half_width",0))+double(s.get("shoulder",0))+6.)/span))+2;
        return coefficients.slice(0,std::min(int64_t(coefficients.size()),(index+following)*4));
    }
    Array compile(const Array &segments,const Array &deposits) const {
        if((segments.is_empty()&&deposits.is_empty())||segments.size()+deposits.size()>16384)return {};
        const Array sorted=ordered(segments);if(sorted.size()!=segments.size())return {};
        Array out;int64_t total=0;
        for(int i=0;i<sorted.size();++i){
            const Dictionary s=sorted[i];
            for(const char *name:{"start","finish","half_width","depth","clearance","material","shoulder"})if(!s.has(name))return {};
            if(s["start"].get_type()!=Variant::VECTOR3||s["finish"].get_type()!=Variant::VECTOR3)return {};
            PackedByteArray p;const bool curved=s.has("coefficients");
            const int profile=(bool(s.get("rectangular",false))?1:0)|(bool(s.get("level_caps",false))?2:0)|(bool(s.get("cut_only",false))?4:0)|(bool(s.get("arched",false))?8:0);
            if(curved){
                const PackedFloat64Array coefficients=curve_prefix(s);const int64_t index=s.get("curve_index",-1);
                if(coefficients.size()<4||coefficients.size()>256||coefficients.size()%4||index<0||index>=coefficients.size()/4)return {};
                p.resize(56+coefficients.size()*4);p.encode_u32(48,coefficients.size()/4);p.encode_u32(52,index);
                for(int k=0;k<coefficients.size();++k)p.encode_float(56+k*4,coefficients[k]);
            }else{p.resize(profile?52:double(s["shoulder"])!=0?48:44);if(profile)p.encode_u32(48,profile);}
            p.encode_u32(0,28);endpoints(p,s["start"],s["finish"]);
            p.encode_float(28,s["half_width"]);p.encode_float(32,s["depth"]);p.encode_float(36,s["clearance"]);p.encode_u32(40,s["material"]);
            if(p.size()>=48)p.encode_float(44,s["shoulder"]);
            total+=p.size();if(total>4*1024*1024)return {};out.push_back(p);
        }
        for(int i=0;i<deposits.size();++i){
            if(deposits[i].get_type()!=Variant::DICTIONARY)return {};const Dictionary d=deposits[i];
            for(const char *name:{"position","start","finish","material"})if(!d.has(name))return {};
            if(d["position"].get_type()!=Variant::VECTOR3||d["start"].get_type()!=Variant::VECTOR3||d["finish"].get_type()!=Variant::VECTOR3)return {};
            PackedByteArray p;p.resize(44);p.encode_u32(0,41);endpoints(p,Vector3(d["position"])+Vector3(0,.25,0),(Vector3(d["start"])+Vector3(d["finish"]))*.5f);
            p.encode_float(28,1.6);p.encode_u32(32,4);p.encode_u32(36,1);p.encode_u32(40,d["material"]);
            total+=p.size();if(total>4*1024*1024)return {};out.push_back(p);
        }
        return out;
    }
};
void register_generation_earthworks(){GDREGISTER_CLASS(NativeGenerationEarthworks);}
}
