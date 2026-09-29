#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <set>
namespace terraforest {
class NativeStructuresSnapshot : public godot::RefCounted {
    GDCLASS(NativeStructuresSnapshot,godot::RefCounted)
    bool configured=false;
    std::set<godot::String> assets;
    bool parse(const godot::PackedByteArray &bytes,godot::Dictionary *result,int mode=0) const;
    godot::PackedByteArray encode_payload(const godot::PackedByteArray &blocks,const godot::Dictionary &models,int mode) const;
    bool parse_storage(const godot::PackedByteArray &payload,godot::Dictionary *result) const;
protected:
    static void _bind_methods();
public:
    // Configure once on the main thread, then share the immutable schema with workers.
    bool configure_assets(const godot::PackedStringArray &ids);
    godot::PackedByteArray encode(const godot::PackedByteArray &blocks,const godot::Dictionary &models) const;
    godot::Dictionary decode(const godot::PackedByteArray &bytes) const;
    godot::PackedByteArray encode_reference(const godot::PackedByteArray &checkpoint,const godot::Dictionary &models) const;
    godot::Dictionary decode_reference(const godot::PackedByteArray &bytes) const;
    godot::PackedByteArray encode_storage(const godot::PackedByteArray &resident,const godot::PackedInt32Array &keys,const godot::PackedByteArray &checksums,const godot::Dictionary &models) const;
    godot::Dictionary decode_storage(const godot::PackedByteArray &bytes) const;
    bool validate_storage_snapshot(const godot::PackedByteArray &bytes) const {return parse(bytes,nullptr)||parse(bytes,nullptr,2);}
    bool validate_snapshot(const godot::PackedByteArray &bytes) const {return parse(bytes,nullptr);}
};
}
