// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <map>
#include <set>
#include <string>
namespace terraforest {
// Single worker owner. Filesystem operations are bounded by one candidate per call.
class NativeDerivedCacheIndex : public godot::RefCounted {
    GDCLASS(NativeDerivedCacheIndex,godot::RefCounted)
    struct Entry {godot::String path;uint64_t size,stamp,identity,volume,age;};
    std::map<std::string,Entry> entries_;
    std::set<std::pair<uint64_t,std::string>> order_;
    void *lease_=nullptr,*directory_=nullptr;
    godot::String root_;
    uint64_t clock_=0;
    bool ordinary(const godot::String &path) const;
    bool candidate(const godot::String &path) const;
protected:
    static void _bind_methods();
public:
    ~NativeDerivedCacheIndex();
    bool acquire(const godot::String &root);
    void release();
    bool track(const godot::String &path);
    bool safe_directory(const godot::String &path) const;
    void touch(const godot::String &path);
    void forget(const godot::String &path);
    godot::Dictionary evict_one();
    int64_t available_bytes() const;
    int64_t count() const{return int64_t(entries_.size());}
};
}
