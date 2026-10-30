// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <unordered_set>
#include <algorithm>
#include <vector>
#include <cmath>
#include "../../world_runtime/native/biome_field.hpp"
namespace terraforest {
using namespace godot;
class NativeVegetationScatter : public RefCounted {
    GDCLASS(NativeVegetationScatter,RefCounted)
    std::vector<Vector3> groves; // X/Z centre, Y radius; bounded offline-authored regions.
    static uint32_t read32(const uint8_t *p){return uint32_t(p[0])|(uint32_t(p[1])<<8)|(uint32_t(p[2])<<16)|(uint32_t(p[3])<<24);}
    static void write32(uint8_t *p,uint32_t v){for(int i=0;i<4;++i)p[i]=uint8_t(v>>(i*8));}
    static bool valid_grove(Vector3 p){return p.is_finite()&&p.x>=2&&p.x<=1998&&p.z>=2&&p.z<=1998&&p.y>=4&&p.y<=64&&std::floor(p.x)==p.x&&std::floor(p.y)==p.y&&std::floor(p.z)==p.z;}

protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("configure_groves","regions"),&NativeVegetationScatter::configure_groves);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeVegetationScatter::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeVegetationScatter::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeVegetationScatter::restore_storage_snapshot);

        ClassDB::bind_method(D_METHOD("wanted_cells","center","radius_world","limit","circular"),&NativeVegetationScatter::wanted_cells,DEFVAL(false));
        ClassDB::bind_method(D_METHOD("world_cells","center"),&NativeVegetationScatter::world_cells);
        ClassDB::bind_method(D_METHOD("candidates","cell","seed","density","natural_region","biome_profile"),&NativeVegetationScatter::candidates,DEFVAL(false),DEFVAL(0));
        ClassDB::bind_method(D_METHOD("place_surface","ids","points","normals","rotations","scales","min_up"),&NativeVegetationScatter::place_surface);
    }
public:
    TypedArray<Vector2i> world_cells(Vector2i center) const {
        const int center_x=std::clamp(center.x,0,31),center_z=std::clamp(center.y,0,31);
        std::vector<Vector2i> cells;
        cells.reserve(1024);
        for(int row=0;row<32;++row)for(int column=0;column<32;++column)cells.emplace_back(column,row);
        std::sort(cells.begin(),cells.end(),[&](const Vector2i &first,const Vector2i &second){
            const int first_distance=(first.x-center_x)*(first.x-center_x)+(first.y-center_z)*(first.y-center_z);
            const int second_distance=(second.x-center_x)*(second.x-center_x)+(second.y-center_z)*(second.y-center_z);
            return first_distance!=second_distance?first_distance<second_distance:first.y*32+first.x<second.y*32+second.x;
        });
        TypedArray<Vector2i> result;
        for(const auto &cell:cells)result.append(cell);
        return result;
    }
    bool configure_groves(const PackedVector3Array &regions){
        if(regions.size()>32)return false;
        std::vector<Vector3> staged;
        for(int64_t i=0;i<regions.size();++i){if(!valid_grove(regions[i]))return false;staged.push_back(regions[i]);}
        groves.swap(staged);return true;
    }
    PackedByteArray capture_storage_snapshot() const {
        PackedByteArray out;out.resize(8+groves.size()*12);auto *p=out.ptrw();
        write32(p,0x31565247);write32(p+4,uint32_t(groves.size()));
        for(size_t i=0;i<groves.size();++i){write32(p+8+i*12,uint32_t(groves[i].x));write32(p+12+i*12,uint32_t(groves[i].y));write32(p+16+i*12,uint32_t(groves[i].z));}
        return out;
    }
    bool validate_snapshot(const PackedByteArray &data) const {
        // Pure validation: safe on the archive worker, no mutable state reads.
        if(data.size()<8||data.size()>392)return false;
        const auto *p=data.ptr();const auto count=read32(p+4);
        if(read32(p)!=0x31565247||count>32||data.size()!=8+int64_t(count)*12)return false;
        for(uint32_t i=0;i<count;++i)if(!valid_grove(Vector3(read32(p+8+i*12),read32(p+12+i*12),read32(p+16+i*12))))return false;
        return true;
    }
    bool restore_storage_snapshot(const PackedByteArray &data){
        if(!validate_snapshot(data))return false;
        const auto *p=data.ptr();std::vector<Vector3> staged;
        for(uint32_t i=0;i<read32(p+4);++i)staged.push_back(Vector3(read32(p+8+i*12),read32(p+12+i*12),read32(p+16+i*12)));
        groves.swap(staged);return true;
    }

    TypedArray<Vector2i> wanted_cells(Vector2i center,double radius_world,int64_t limit,bool circular=false) const {
        TypedArray<Vector2i> out;
        // The current world has 32 x 32 owners. Bound work before allocating.
        if(!std::isfinite(radius_world)||radius_world<0||radius_world>768||limit<0||limit>625||limit==0)return out;
        const int64_t radius=int64_t(std::ceil(radius_world/64.0))+(circular?1:0);
        const int64_t x0=std::max(int64_t(0),int64_t(center.x)-radius),x1=std::min(int64_t(31),int64_t(center.x)+radius);
        const int64_t z0=std::max(int64_t(0),int64_t(center.y)-radius),z1=std::min(int64_t(31),int64_t(center.y)+radius);
        if(x0>x1||z0>z1)return out;
        struct Cell { Vector2i position; int64_t distance; int64_t id; };
        std::vector<Cell> cells;cells.reserve((x1-x0+1)*(z1-z0+1));
        for(int64_t z=z0;z<=z1;++z)for(int64_t x=x0;x<=x1;++x){
            const int64_t dx=x-center.x,dz=z-center.y;
            const double gap_x=std::max(int64_t(0),std::abs(dx)-1)*64.0;
            const double gap_z=std::max(int64_t(0),std::abs(dz)-1)*64.0;
            if(circular&&gap_x*gap_x+gap_z*gap_z>radius_world*radius_world)continue;
            cells.push_back({Vector2i(x,z),dx*dx+dz*dz,z*32+x});
        }
        const auto count=std::min(size_t(limit),cells.size());
        std::partial_sort(cells.begin(),cells.begin()+count,cells.end(),[](const Cell &a,const Cell &b){
            return a.distance!=b.distance?a.distance<b.distance:a.id<b.id;
        });
        for(size_t i=0;i<count;++i)out.append(cells[i].position);
        return out;
    }
    Dictionary place_surface(const PackedInt64Array &ids,const PackedVector3Array &points,const PackedVector3Array &normals,const PackedFloat32Array &rotations,const PackedFloat32Array &scales,double min_up) const {
        Dictionary out;out["ok"]=false;
        const int64_t count=ids.size();
        if(count>4096||points.size()!=count||normals.size()!=count||rotations.size()!=count||scales.size()!=count||!std::isfinite(min_up)||min_up<0||min_up>1)return out;
        // Validate metadata before producing any placement. Nonfinite surface
        // points/normals are missing-support samples, and are skipped below.
        std::unordered_set<int64_t> seen;seen.reserve(count);
        for(int64_t i=0;i<count;++i){
            if(ids[i]<=0||!seen.insert(ids[i]).second||!std::isfinite(rotations[i])||!std::isfinite(scales[i])||scales[i]<0.05||scales[i]>10)return out;
        }
        PackedInt64Array accepted;TypedArray<Transform3D> transforms;
        for(int64_t i=0;i<count;++i){
            if(!points[i].is_finite()||!normals[i].is_finite()||normals[i].length_squared()==0||normals[i].y<min_up)continue;
            const Basis basis=Basis(Vector3(0,1,0),rotations[i]).scaled(Vector3(1,1,1)*scales[i]);
            accepted.append(ids[i]);transforms.append(Transform3D(basis,points[i]-Vector3(0,0.2,0)));
        }
        out["ok"]=true;out["ids"]=accepted;out["transforms"]=transforms;return out;
    }
    static double woodland_noise(double x,double z,uint32_t seed) {
        const int ix=int(std::floor(x)),iz=int(std::floor(z));
        auto sample=[&](int a,int b){uint32_t h=uint32_t(a)*73856093u^uint32_t(b)*19349663u^seed;h^=h>>16;h*=0x7feb352du;h^=h>>15;h*=0x846ca68bu;h^=h>>16;return double(h&65535u)/65535.0;};
        double u=x-ix,v=z-iz;u=u*u*(3-2*u);v=v*v*(3-2*v);
        return (sample(ix,iz)*(1-u)+sample(ix+1,iz)*u)*(1-v)+(sample(ix,iz+1)*(1-u)+sample(ix+1,iz+1)*u)*v;
    }
    Dictionary candidates(Vector2i cell,int64_t seed,double density,bool natural_region=false,int biome_profile=0) const {
        PackedVector3Array points;PackedInt64Array ids;PackedFloat32Array rotations,scales;
        if(cell.x>=0&&cell.x<32&&cell.y>=0&&cell.y<32&&std::isfinite(density)&&density>=0&&density<=1&&biome_profile>=0&&biome_profile<=2){
            Ref<RandomNumberGenerator> rng;rng.instantiate();
            rng->set_seed(uint64_t(seed)^uint64_t((int64_t(cell.y)*32+cell.x+1)*73856093));
            for(int z=0;z<6;++z)for(int x=0;x<6;++x){
                // Preserve legacy RNG draw order, including rejected candidates.
                // GDScript promotes RNG floats to doubles before arithmetic.
                const double px=(cell.x+(x+double(rng->randf_range(0.2,0.8)))/6.0)*64.0;
                const double pz=(cell.y+(z+double(rng->randf_range(0.2,0.8)))/6.0)*64.0;
                const Vector3 point(px,0,pz);
                const double roll=rng->randf();
                const double yaw=rng->randf_range(0.0,6.283185307179586);
                const double scale=rng->randf_range(0.7,1.18);
                double biome=std::clamp((1000.0-point.x)/100.0,0.0,1.0)*std::clamp((point.z-1000.0)/100.0,0.0,1.0);
                if(natural_region){
                    // Coherent woodland and meadow boundaries across the whole map.
                    // Same candidate budget/IDs; only generation14 opts into this field.
                    const double broad=woodland_noise(px/230.0,pz/230.0,uint32_t(seed)^0x76b3a921u);
                    const double edge=woodland_noise(px/65.0,pz/65.0,uint32_t(seed)^0x1b873593u);
                    biome=std::clamp((broad*.8+edge*.2-.34)*4.0,0.0,1.0);
                }
                for(const auto &grove:groves){
                    const double dx=px-grove.x,dz=pz-grove.z;
                    biome=std::max(biome,std::clamp((double(grove.y)-std::sqrt(dx*dx+dz*dz))/4.0,0.0,1.0));
                }
                if(biome_profile>0)biome=std::min(biome,biome_woodland(px,pz,uint32_t(seed),biome_profile));
                if(roll>=density*biome||point.x<2||point.z<2||point.x>=1998||point.z>=1998)continue;
                points.append(point);ids.append(1+(cell.y*32+cell.x)*36+z*6+x);
                rotations.append(yaw);scales.append(scale);
            }
        }
        Dictionary out;out["points"]=points;out["ids"]=ids;out["rotations"]=rotations;out["scales"]=scales;return out;
    }
};
}
