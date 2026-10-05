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
#include <algorithm>
#include <cmath>
namespace terraforest {
using namespace godot;
class NativeVegetationScatter : public RefCounted {
    GDCLASS(NativeVegetationScatter,RefCounted)
protected:
    static void _bind_methods(){ClassDB::bind_method(D_METHOD("candidates","cell","seed","density"),&NativeVegetationScatter::candidates);}
public:
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
