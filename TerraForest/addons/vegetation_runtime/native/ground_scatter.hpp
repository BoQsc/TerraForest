// SPDX-License-Identifier: 0BSD
#pragma once
#include "scatter.hpp"
namespace terraforest {
class NativeGroundCover : public RefCounted {
    GDCLASS(NativeGroundCover,RefCounted)
    static uint32_t hash(uint32_t v){v^=v>>16;v*=0x7feb352du;v^=v>>15;v*=0x846ca68bu;return v^(v>>16);}
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("wanted","center"),&NativeGroundCover::wanted);
        ClassDB::bind_method(D_METHOD("wanted_view","eye","forward","fov","aspect"),&NativeGroundCover::wanted_view);
        ClassDB::bind_method(D_METHOD("candidates","cell","seed","layer"),&NativeGroundCover::candidates,DEFVAL(0));
        ClassDB::bind_method(D_METHOD("place","ids","points","normals"),&NativeGroundCover::place);
        ClassDB::bind_method(D_METHOD("pack","ids","transforms","excluded"),&NativeGroundCover::pack);
    }
public:
    TypedArray<Vector2i> wanted(Vector2i center) const {
        TypedArray<Vector2i> out;
        if(center.x<-4||center.y<-4||center.x>66||center.y>66)return out;
        struct Cell{Vector2i p;int d;};std::vector<Cell> cells;
        for(int z=std::max(0,center.y-4);z<=std::min(62,center.y+4);++z)
            for(int x=std::max(0,center.x-4);x<=std::min(62,center.x+4);++x)
                cells.push_back({Vector2i(x,z),(x-center.x)*(x-center.x)+(z-center.y)*(z-center.y)});
        std::sort(cells.begin(),cells.end(),[](const Cell&a,const Cell&b){return a.d!=b.d?a.d<b.d:(a.p.y!=b.p.y?a.p.y<b.p.y:a.p.x<b.p.x);});
        for(const auto &c:cells)out.append(c.p);return out;
    }
    Dictionary wanted_view(Vector3 eye,Vector3 forward,double fov,double aspect) const {
        Dictionary result;TypedArray<Vector2i> cells;result["range"]=124.0;result["cells"]=cells;
        if(!eye.is_finite()||!forward.is_finite()||!std::isfinite(fov)||!std::isfinite(aspect)||fov<1||fov>=179||aspect<=0||aspect>4||eye.x<-128||eye.z<-128||eye.x>2144||eye.z>2144)return result;
        Vector2i center(int(std::floor(eye.x/32)),int(std::floor(eye.z/32)));
        double zoom=std::clamp(std::tan(75.0*3.141592653589793/360.0)/std::tan(fov*3.141592653589793/360.0),1.0,2.0);
        Vector2 direction(forward.x,forward.z);
        if(zoom<=1.05||direction.length_squared()<0.04){result["cells"]=wanted(center);return result;}
        direction=direction.normalized();
        const double reach=124.0*zoom;
        // Expanded horizontal cone covers cell corners and small yaw changes.
        const double tangent=std::tan(std::atan(std::tan(fov*3.141592653589793/360.0)*aspect)+0.10);
        struct Candidate{Vector2i p;double distance;};std::vector<Candidate> candidates;
        int radius=int(std::ceil((reach+48)/32));
        for(int z=std::max(0,center.y-radius);z<=std::min(62,center.y+radius);++z)
            for(int x=std::max(0,center.x-radius);x<=std::min(62,center.x+radius);++x){
                Vector2 delta(x*32+16-eye.x,z*32+16-eye.z);
                double distance=delta.length(),along=delta.dot(direction),side=std::abs(delta.x*direction.y-delta.y*direction.x);
                if(distance>reach+24)continue;
                if(distance>72&&(along<0||side>along*tangent+32))continue;
                candidates.push_back({Vector2i(x,z),distance});
            }
        std::sort(candidates.begin(),candidates.end(),[](const Candidate&a,const Candidate&b){return a.distance!=b.distance?a.distance<b.distance:(a.p.y!=b.p.y?a.p.y<b.p.y:a.p.x<b.p.x);});
        double visible=reach;
        if(candidates.size()>81)visible=std::min(visible,std::max(124.0,candidates[81].distance-24.0));
        for(size_t i=0;i<std::min(size_t(81),candidates.size());++i)cells.append(candidates[i].p);
        result["cells"]=cells;result["range"]=visible;return result;
    }
    Dictionary candidates(Vector2i cell,int64_t seed,int layer=0) const {
        PackedVector3Array points;PackedInt64Array ids;
        if(cell.x>=0&&cell.y>=0&&cell.x<63&&cell.y<63&&seed>=0&&seed<=0x7fffffff&&layer>=0&&layer<16){
            for(int i=0;i<64;++i){
                int64_t id=layer==0?1+(cell.y*63+cell.x)*64+i:1+63*63*64+(cell.y*63+cell.x)*960+(layer-1)*64+i;uint32_t h=hash(uint32_t(id)^uint32_t(seed));
                float x=cell.x*32+(i%8+.15f+.7f*(h&65535)/65535.f)*4;
                float z=cell.y*32+(i/8+.15f+.7f*(h>>16)/65535.f)*4;
                if(layer>0){x=cell.x*32+(i%8)*4+(layer%4)+.15f+.7f*(h&65535)/65535.f;z=cell.y*32+(i/8)*4+(layer/4)+.15f+.7f*(h>>16)/65535.f;}
                if(x<2||z<2||x>=1998||z>=1998)continue;
                ids.append(id);points.append(Vector3(x,0,z));
            }
        }
        Dictionary out;out["ids"]=ids;out["points"]=points;return out;
    }
    Dictionary place(const PackedInt64Array &ids,const PackedVector3Array &points,const PackedVector3Array &normals) const {
        Dictionary out;out["ok"]=false;
        if(ids.size()>64||points.size()!=ids.size()||normals.size()!=ids.size())return out;
        std::unordered_set<int64_t> seen;
        for(int64_t i=0;i<ids.size();++i)if(ids[i]<1||ids[i]>63*63*1024||!seen.insert(ids[i]).second)return out;
        PackedInt64Array accepted;TypedArray<Transform3D> transforms;
        for(int64_t i=0;i<ids.size();++i){
            if(!points[i].is_finite()||!normals[i].is_finite()||normals[i].length_squared()<1e-12f||normals[i].normalized().y<.82f)continue;
            uint32_t h=hash(uint32_t(ids[i]));float scale=.7f+.6f*(h&65535)/65535.f;
            Basis basis(Vector3(0,1,0),float(h>>16)/65535.f*6.283185307f);
            transforms.append(Transform3D(basis.scaled(Vector3(scale,scale,scale)),points[i]-Vector3(0,.03f,0)));accepted.append(ids[i]);
        }
        out["ok"]=true;out["ids"]=accepted;out["transforms"]=transforms;return out;
    }
    Array pack(const PackedInt64Array &ids,const TypedArray<Transform3D> &transforms,const PackedByteArray &excluded) const {
        Array out;
        if(ids.size()>64||ids.size()!=transforms.size()||ids.size()!=excluded.size())return out;
        PackedInt64Array keys[8];PackedFloat32Array values[8];
        std::unordered_set<int64_t> seen;
        for(int64_t i=0;i<ids.size();++i){
            if(ids[i]<1||ids[i]>63*63*1024||!seen.insert(ids[i]).second)return Array();
            Transform3D t=transforms[i];if(!t.origin.is_finite()||!t.basis.is_finite()||std::abs(t.basis.determinant())<1e-12)return Array();
            if(excluded[i])continue;
            int pick=hash(uint32_t(ids[i]))%10;int species=pick==0?0:(pick<3?1:2);
            // Preserve stones/ferns and all identities; enrich a small subset of grass.
            uint32_t accent=hash(uint32_t(ids[i])^0x739ac51du)%1000;
            if(species==2){if(accent<15)species=3+accent/5;else if(accent<40)species=6;else if(accent<70)species=7;}
            if(ids[i]>63*63*64) {
                // Detail layers formerly forced every candidate to grass, overwhelming
                // the sparse base species. Small coherent understory pockets retain
                // the same candidate count, identities and persisted removal masks.
                const float patch=std::sin(t.origin.x*.17f)*std::cos(t.origin.z*.13f);
                species=2;
                if(accent<(patch>.25f?140u:20u))species=1;
                else if(accent>=150&&accent<165&&patch>0.0f)species=6;
                else if(accent>=170&&accent<175)species=7;
                else if(accent>=180&&accent<183)species=3+int(accent-180);
            }
            keys[species].append(ids[i]);
            for(int row=0;row<3;++row){for(int col=0;col<3;++col)values[species].append(t.basis[row][col]);values[species].append(t.origin[row]);}
        }
        for(int i=0;i<8;++i){Dictionary row;row["ids"]=keys[i];row["transforms"]=values[i];out.append(row);}return out;
    }
};
}
