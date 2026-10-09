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
    enum Mode { RESIDENT, REFERENCE, STORAGE, CHECKPOINT_STORAGE };
    bool parse_block_payload(const godot::PackedByteArray &bytes,godot::Dictionary *result,Mode mode) const;
    static const char *magic(Mode mode);
    bool configured=false;
    std::set<godot::String> assets;
    bool parse(const godot::PackedByteArray &bytes,godot::Dictionary *result,Mode mode=RESIDENT) const;
    godot::PackedByteArray encode_payload(const godot::PackedByteArray &blocks,const godot::Dictionary &models,Mode mode) const;
    bool parse_storage(const godot::PackedByteArray &payload,godot::Dictionary *result) const;
protected:
    static void _bind_methods();
public:
    bool has_asset(const godot::String &asset) const {return configured&&assets.count(asset);}
    godot::PackedByteArray encode_model_storage(const godot::PackedByteArray &resident,const godot::PackedInt32Array &keys,const godot::PackedByteArray &checksums) const;
    static bool parse_model_storage(const godot::PackedByteArray &bytes,godot::String &asset,godot::Dictionary *state=nullptr);
    static godot::PackedByteArray model_reference(const godot::String &asset,const godot::PackedByteArray &checkpoint);
    static bool parse_model_reference(const godot::PackedByteArray &bytes,godot::String &asset,godot::PackedByteArray &checkpoint);
    // Configure once on the main thread, then share the immutable schema with workers.
    bool configure_assets(const godot::PackedStringArray &ids);
    godot::PackedByteArray encode(const godot::PackedByteArray &blocks,const godot::Dictionary &models) const;
    godot::Dictionary decode(const godot::PackedByteArray &bytes) const;
    godot::PackedByteArray encode_reference(const godot::PackedByteArray &checkpoint,const godot::Dictionary &models) const;
    godot::Dictionary decode_reference(const godot::PackedByteArray &bytes) const;
    godot::PackedByteArray encode_storage(const godot::PackedByteArray &resident,const godot::PackedInt32Array &keys,const godot::PackedByteArray &checksums,const godot::Dictionary &models,const godot::PackedByteArray &checkpoint=godot::PackedByteArray()) const;
    godot::PackedByteArray encode_metadata(const godot::PackedByteArray &checkpoint,const godot::PackedInt32Array &keys,const godot::PackedByteArray &checksums,const godot::Dictionary &models) const;
    godot::Dictionary decode_storage(const godot::PackedByteArray &bytes) const;
    bool validate_storage_snapshot(const godot::PackedByteArray &bytes) const {return parse(bytes,nullptr)||parse(bytes,nullptr,STORAGE)||parse(bytes,nullptr,CHECKPOINT_STORAGE);}
    bool validate_snapshot(const godot::PackedByteArray &bytes) const {return parse(bytes,nullptr);}
};
}
