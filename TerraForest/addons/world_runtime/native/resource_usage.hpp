#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace terraforest {
class NativeResourceUsage : public godot::RefCounted {
    GDCLASS(NativeResourceUsage,godot::RefCounted)
    struct Area {
        std::string id;
        std::wstring path;
        std::wstring pack_file=L"TerraForest.pck";
        int mode=0;
        int64_t bytes=0,files=0,entries=0,links=0,errors=0;
        bool started=false,available=false,complete=false,limited=false;
    };
    std::vector<Area> areas_;
    std::mutex mutex_;
    std::thread worker_;
    std::atomic<bool> running_{false},stop_{false};
    void *pdh_=nullptr,*query_=nullptr,*counter_=nullptr;
    int64_t gpu_peak_=-1;
    void scan_directory(const std::wstring &path,int depth,Area &area,size_t index);
    void publish(const Area &area,size_t index);
    void initialize_gpu();
protected:
    static void _bind_methods();
public:
    ~NativeResourceUsage();
    godot::Dictionary sample(const godot::String &volume_path);
    bool start_scan(const godot::Array &locations);
    void cancel_scan();
    godot::Dictionary scan_status();
};
}
