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
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <unordered_set>
#include <algorithm>
#include <cmath>
namespace terraforest {
using namespace godot;
class NativeVegetationScatter : public RefCounted {
    GDCLASS(NativeVegetationScatter,RefCounted)
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("candidates","cell","seed","density"),&NativeVegetationScatter::candidates);
        ClassDB::bind_method(D_METHOD("place_surface","ids","points","normals","rotations","scales","min_up"),&NativeVegetationScatter::place_surface);
    }
public:
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
    Dictionary candidates(Vector2i cell,int64_t seed,double density) const {
        PackedVector3Array points;PackedInt64Array ids;PackedFloat32Array rotations,scales;
        if(cell.x>=0&&cell.x<32&&cell.y>=0&&cell.y<32&&std::isfinite(density)&&density>=0&&density<=1){
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
                const double biome=std::clamp((1000.0-point.x)/100.0,0.0,1.0)*std::clamp((point.z-1000.0)/100.0,0.0,1.0);
                if(roll>=density*biome||point.x<2||point.z<2||point.x>=1998||point.z>=1998)continue;
                points.append(point);ids.append(1+(cell.y*32+cell.x)*36+z*6+x);
                rotations.append(yaw);scales.append(scale);
            }
        }
        Dictionary out;out["points"]=points;out["ids"]=ids;out["rotations"]=rotations;out["scales"]=scales;return out;
    }
};
}
