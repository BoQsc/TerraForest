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
        ClassDB::bind_method(D_METHOD("candidates","cell","seed"),&NativeGroundCover::candidates);
        ClassDB::bind_method(D_METHOD("place","ids","points","normals"),&NativeGroundCover::place);
        ClassDB::bind_method(D_METHOD("pack","ids","transforms","excluded"),&NativeGroundCover::pack);
    }
public:
    TypedArray<Vector2i> wanted(Vector2i center) const {
        TypedArray<Vector2i> out;
        if(center.x<-3||center.y<-3||center.x>65||center.y>65)return out;
        struct Cell{Vector2i p;int d;};std::vector<Cell> cells;
        for(int z=std::max(0,center.y-3);z<=std::min(62,center.y+3);++z)
            for(int x=std::max(0,center.x-3);x<=std::min(62,center.x+3);++x)
                cells.push_back({Vector2i(x,z),(x-center.x)*(x-center.x)+(z-center.y)*(z-center.y)});
        std::sort(cells.begin(),cells.end(),[](const Cell&a,const Cell&b){return a.d!=b.d?a.d<b.d:(a.p.y!=b.p.y?a.p.y<b.p.y:a.p.x<b.p.x);});
        for(const auto &c:cells)out.append(c.p);return out;
    }
    Dictionary candidates(Vector2i cell,int64_t seed) const {
        PackedVector3Array points;PackedInt64Array ids;
        if(cell.x>=0&&cell.y>=0&&cell.x<63&&cell.y<63&&seed>=0&&seed<=0x7fffffff){
            for(int i=0;i<64;++i){
                int64_t id=1+(cell.y*63+cell.x)*64+i;uint32_t h=hash(uint32_t(id)^uint32_t(seed));
                const float x=cell.x*32+(i%8+.15f+.7f*(h&65535)/65535.f)*4;
                const float z=cell.y*32+(i/8+.15f+.7f*(h>>16)/65535.f)*4;
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
        for(int64_t i=0;i<ids.size();++i)if(ids[i]<1||ids[i]>63*63*64||!seen.insert(ids[i]).second)return out;
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
        PackedInt64Array keys[3];PackedFloat32Array values[3];
        std::unordered_set<int64_t> seen;
        for(int64_t i=0;i<ids.size();++i){
            if(ids[i]<1||ids[i]>63*63*64||!seen.insert(ids[i]).second)return Array();
            Transform3D t=transforms[i];if(!t.origin.is_finite()||!t.basis.is_finite()||std::abs(t.basis.determinant())<1e-12)return Array();
            if(excluded[i])continue;
            int pick=hash(uint32_t(ids[i]))%10;int species=pick==0?0:(pick<3?1:2);
            keys[species].append(ids[i]);
            for(int row=0;row<3;++row){for(int col=0;col<3;++col)values[species].append(t.basis[row][col]);values[species].append(t.origin[row]);}
        }
        for(int i=0;i<3;++i){Dictionary row;row["ids"]=keys[i];row["transforms"]=values[i];out.append(row);}return out;
    }
};
}
