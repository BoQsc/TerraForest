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
        ClassDB::bind_method(D_METHOD("candidates","cell","seed","layer","shelter","irregular"),&NativeGroundCover::candidates,DEFVAL(0),DEFVAL(PackedVector3Array()),DEFVAL(false));
        ClassDB::bind_method(D_METHOD("place","ids","points","normals"),&NativeGroundCover::place);
        ClassDB::bind_method(D_METHOD("pack","ids","transforms","excluded","shelter"),&NativeGroundCover::pack,DEFVAL(PackedVector3Array()));
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
    Dictionary candidates(Vector2i cell,int64_t seed,int layer=0,const PackedVector3Array &shelter=PackedVector3Array(),bool irregular=false) const {
        PackedVector3Array points;PackedInt64Array ids;
        if(cell.x>=0&&cell.y>=0&&cell.x<63&&cell.y<63&&seed>=0&&seed<=0x7fffffff&&layer>=0&&layer<16&&shelter.size()<=144){
            // Validate/copy the bounded anchor set once per batch, not per plant.
            Vector3 anchors[144];int anchor_count=0;
            for(int a=0;a<shelter.size();++a) {
                const Vector3 tree=shelter[a];
                if(tree.is_finite())anchors[anchor_count++]=tree;
            }
            for(int i=0;i<64;++i){
                int64_t id=layer==0?1+(cell.y*63+cell.x)*64+i:1+63*63*64+(cell.y*63+cell.x)*960+(layer-1)*64+i;uint32_t h=hash(uint32_t(id)^uint32_t(seed));
                float x=cell.x*32+(i%8+.15f+.7f*(h&65535)/65535.f)*4;
                float z=cell.y*32+(i/8+.15f+.7f*(h>>16)/65535.f)*4;
                if(layer>0){x=cell.x*32+(i%8)*4+(layer%4)+.15f+.7f*(h&65535)/65535.f;z=cell.y*32+(i/8)*4+(layer/4)+.15f+.7f*(h>>16)/65535.f;}
                if(layer>0) {
                    // Redistribute existing detail identities, never add candidates.
                    // Variable-strength pockets avoid a uniformly spaced lawn.
                    const float bx=cell.x*32+(i%8)*4,bz=cell.y*32+(i/8)*4;
                    if(irregular){
                        // Full subcell jitter removes the previous layer-aligned 1m
                        // lattice. Stable IDs, owner bounds and base stones are unchanged.
                        const uint32_t random=hash(h^0x51e2a9bdu);
                        x=bx+.04f+3.92f*(random&65535)/65535.f;
                        z=bz+.04f+3.92f*(random>>16)/65535.f;
                    }

                    const uint32_t pocket=hash(uint32_t((cell.y*8+i/8)*504+cell.x*8+i%8)^uint32_t(seed));
                    float ax=bx+1.0f+2.0f*(pocket&65535)/65535.f;
                    float az=bz+1.0f+2.0f*(pocket>>16)/65535.f;
                    const int64_t base_id=1+(cell.y*63+cell.x)*64+i;
                    // Existing stone positions are untouched; nearby plants gather around them.
                    if(hash(uint32_t(base_id))%10==0) {
                        const auto rock=hash(uint32_t(base_id)^uint32_t(seed));
                        ax=bx+(.15f+.7f*(rock&65535)/65535.f)*4;
                        az=bz+(.15f+.7f*(rock>>16)/65535.f)*4;
                    }
                    const float field=.5f+.25f*std::sin(bx*.083f+bz*.047f)+.25f*std::sin(bz*.139f-bx*.063f);
                    const float strength=irregular?.10f+.56f*field:.12f+.48f*float(pocket%997)/996.f;
                    x+=(ax-x)*strength;z+=(az-z)*strength;
                    // Potential tree anchors use the same persisted grove recipe, not
                    // currently resident trees: visit order/harvesting cannot shuffle plants.
                    float nearest=25.f;Vector3 anchor;
                    for(int a=0;a<anchor_count;++a) {
                        const Vector3 &tree=anchors[a];
                        float dx=x-tree.x,dz=z-tree.z,d=dx*dx+dz*dz;
                        if(d<nearest){nearest=d;anchor=tree;}
                    }
                    if(nearest>1.f&&nearest<25.f) {
                        float distance=std::sqrt(nearest),pull=.22f*(1.f-distance/5.f);
                        float edge=std::clamp(std::min({x-cell.x*32,z-cell.y*32,(cell.x+1)*32-x,(cell.y+1)*32-z})/2.f,0.f,1.f);
                        x+=(anchor.x-x)*pull*edge;z+=(anchor.z-z)*pull*edge;
                    }
                }
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
            basis=basis.scaled(Vector3(scale,scale,scale));
            // Apply shape variation before support/exclusion validation and packing.
            // Base-layer stones retain their existing shape and position.
            if(ids[i]>63*63*64 || h%10!=0){
                const uint32_t shape=hash(uint32_t(ids[i])^0xa92d33b1u);
                basis=basis.scaled_local(Vector3(.86f+.28f*float(shape&255)/255.f,
                    .90f+.20f*float((shape>>8)&255)/255.f,
                    .88f+.24f*float((shape>>16)&255)/255.f));
            }
            transforms.append(Transform3D(basis,points[i]-Vector3(0,.03f,0)));accepted.append(ids[i]);
        }
        out["ok"]=true;out["ids"]=accepted;out["transforms"]=transforms;return out;
    }
    Array pack(const PackedInt64Array &ids,const TypedArray<Transform3D> &transforms,const PackedByteArray &excluded,const PackedVector3Array &shelter=PackedVector3Array()) const {
        Array out;
        if(shelter.size()>144||ids.size()>64||ids.size()!=transforms.size()||ids.size()!=excluded.size())return out;
        PackedInt64Array keys[9];PackedFloat32Array values[9];
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
                else if(accent>=180&&accent<(patch>.35f?189u:180u))species=3+int(hash(uint32_t(std::floor(t.origin.x/8))*504+uint32_t(std::floor(t.origin.z/8)))%3);
            }
            if(species==2&&accent>=190&&accent<195)species=8;
            keys[species].append(ids[i]);
            for(int row=0;row<3;++row){for(int col=0;col<3;++col)values[species].append(t.basis[row][col]);values[species].append(t.origin[row]);}
        }
        for(int i=0;i<9;++i){Dictionary row;row["ids"]=keys[i];row["transforms"]=values[i];out.append(row);}return out;
    }
};
}
