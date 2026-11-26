// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <cmath>
#include <vector>

namespace terraforest {
// A placement batch is immutable for the duration of one exclusion query.
// Collections with the same exact frame share its validation and local boxes.
// Keep only the most recent frame: memory is O(candidates), not O(collections).
class ExclusionQueries {
    std::vector<godot::Transform3D> poses;
    godot::AABB prototype;
    godot::Transform3D cached_frame;
    bool frame_ready=false;
public:
    std::vector<godot::AABB> boxes;
    godot::AABB combined;
    uint64_t transformed=0,reused=0;
    bool configure(const godot::TypedArray<godot::Transform3D> &input,const godot::AABB &bounds) {
        frame_ready=false;poses.clear();boxes.clear();transformed=0;reused=0;
        if(input.size()>65536||!bounds.position.is_finite()||!bounds.size.is_finite()||
           bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0)return false;
        prototype=bounds;poses.reserve(input.size());
        for(int64_t i=0;i<input.size();++i) {
            godot::Transform3D pose=input[i];const double determinant=pose.basis.determinant();
            if(!pose.is_finite()||!std::isfinite(determinant)||std::abs(determinant)<1e-12)return false;
            poses.push_back(pose);
        }
        return true;
    }
    bool in_frame(const godot::Transform3D &frame) {
        if(frame_ready&&frame==cached_frame){++reused;return true;}
        const double determinant=frame.basis.determinant();
        if(!frame.is_finite()||!std::isfinite(determinant)||std::abs(determinant)<1e-12)return false;
        frame_ready=false;const auto inverse=frame.affine_inverse();boxes.resize(poses.size());
        for(size_t i=0;i<poses.size();++i) {
            const auto box=(inverse*poses[i]).xform(prototype);
            if(!box.position.is_finite()||!box.get_end().is_finite())return false;
            boxes[i]=box;combined=i?combined.merge(box):box;
        }
        transformed+=poses.size();cached_frame=frame;frame_ready=true;return true;
    }
};
}
