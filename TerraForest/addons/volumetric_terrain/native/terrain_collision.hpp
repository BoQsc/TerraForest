// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace terraforest {
// Constructed once by prepare(). No exposed setter and no physics RID on workers.
class NativeTerrainCollisionPiece : public godot::RefCounted {
    GDCLASS(NativeTerrainCollisionPiece, godot::RefCounted)
    godot::PackedVector3Array faces_;
    godot::String token_;
    friend class NativeTerrainCollision;
protected:
    static void _bind_methods();
public:
    godot::PackedVector3Array get_faces() const { return faces_; }
    godot::String get_token() const { return token_; }
    godot::Dictionary resolve(const godot::Dictionary &previous) const;
};

class NativeTerrainCollision : public godot::RefCounted {
    GDCLASS(NativeTerrainCollision, godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Dictionary prepare(const godot::PackedVector3Array &faces, int64_t triangles_per_piece) const;
};
}
