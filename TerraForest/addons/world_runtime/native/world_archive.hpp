#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
namespace terraforest {
class NativeWorldArchive : public godot::RefCounted {
    GDCLASS(NativeWorldArchive,godot::RefCounted)
    void *lease_ = nullptr;
    godot::String leased_path_;
protected:
    static void _bind_methods();
public:
    ~NativeWorldArchive();
    godot::Dictionary clone_world(const godot::String &absolute_root,const godot::String &source,const godot::String &destination,int64_t test_stop_after=-1) const;
    godot::Dictionary recover_world(const godot::String &absolute_root,const godot::String &destination) const;
    bool acquire(const godot::String &absolute_path);
    void release();
    bool validate_sections(const godot::Dictionary &sections) const;
    godot::PackedByteArray encode(const godot::Dictionary &sections) const;
    godot::Dictionary decode(const godot::PackedByteArray &bytes) const;
    godot::PackedByteArray read(const godot::String &absolute_path) const;
    int64_t publish(const godot::String &absolute_path, const godot::PackedByteArray &bytes) const;
};
}
