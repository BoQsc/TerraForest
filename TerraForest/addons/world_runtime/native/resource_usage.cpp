#include "resource_usage.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <algorithm>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <psapi.h>
#include <pdh.h>
#include <pdhmsg.h>

namespace terraforest {
using namespace godot;
static std::wstring wide(const String &value){auto text=value.utf16();return std::wstring(reinterpret_cast<const wchar_t*>(text.get_data()),text.length());}
static String narrow(const std::string &value){return String::utf8(value.c_str());}
static bool protected_folder(const std::wstring &name){return !_wcsicmp(name.c_str(),L"worlds")||!_wcsicmp(name.c_str(),L"logs")||!_wcsicmp(name.c_str(),L"generation_reports")||!_wcsicmp(name.c_str(),L"screenshots");}
void NativeResourceUsage::_bind_methods(){
    ClassDB::bind_method(D_METHOD("sample","volume_path"),&NativeResourceUsage::sample);
    ClassDB::bind_method(D_METHOD("start_scan","locations","budget_ms"),&NativeResourceUsage::start_scan,DEFVAL(8000));
    ClassDB::bind_method(D_METHOD("cancel_scan"),&NativeResourceUsage::cancel_scan);
    ClassDB::bind_method(D_METHOD("scan_status"),&NativeResourceUsage::scan_status);
}
void NativeResourceUsage::initialize_gpu(){
    if(pdh_)return;
    pdh_=LoadLibraryW(L"pdh.dll");if(!pdh_)return;
    auto open=reinterpret_cast<decltype(&PdhOpenQueryW)>(GetProcAddress(HMODULE(pdh_),"PdhOpenQueryW"));
    auto add=reinterpret_cast<decltype(&PdhAddEnglishCounterW)>(GetProcAddress(HMODULE(pdh_),"PdhAddEnglishCounterW"));
    if(!open||!add||open(nullptr,0,reinterpret_cast<PDH_HQUERY*>(&query_)))return;
    std::wstring path=L"\\GPU Process Memory(pid_"+std::to_wstring(GetCurrentProcessId())+L"_*)\\Dedicated Usage";
    if(add(PDH_HQUERY(query_),path.c_str(),0,reinterpret_cast<PDH_HCOUNTER*>(&counter_)))counter_=nullptr;
}
Dictionary NativeResourceUsage::sample(const String &volume_path){
    Dictionary out;
    PROCESS_MEMORY_COUNTERS_EX memory{};memory.cb=sizeof(memory);
    auto info=reinterpret_cast<BOOL(WINAPI*)(HANDLE,PPROCESS_MEMORY_COUNTERS,DWORD)>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"K32GetProcessMemoryInfo"));
    if(info&&info(GetCurrentProcess(),reinterpret_cast<PPROCESS_MEMORY_COUNTERS>(&memory),sizeof(memory))){
        out["private_bytes"]=int64_t(memory.PrivateUsage);out["working_bytes"]=int64_t(memory.WorkingSetSize);
        out["private_peak_bytes"]=int64_t(memory.PeakPagefileUsage);out["working_peak_bytes"]=int64_t(memory.PeakWorkingSetSize);
    }
    ULARGE_INTEGER available{},total{};auto path=wide(volume_path);
    if(!path.empty()&&GetDiskFreeSpaceExW(path.c_str(),&available,&total,nullptr)){out["disk_free_bytes"]=int64_t(available.QuadPart);out["disk_total_bytes"]=int64_t(total.QuadPart);}
    initialize_gpu();
    if(counter_){
        auto collect=reinterpret_cast<decltype(&PdhCollectQueryData)>(GetProcAddress(HMODULE(pdh_),"PdhCollectQueryData"));
        auto format=reinterpret_cast<decltype(&PdhGetFormattedCounterArrayW)>(GetProcAddress(HMODULE(pdh_),"PdhGetFormattedCounterArrayW"));
        DWORD size=0,count=0;
        if(collect&&format&&!collect(PDH_HQUERY(query_))&&format(PDH_HCOUNTER(counter_),PDH_FMT_LARGE|PDH_FMT_NOSCALE,&size,&count,nullptr)==PDH_MORE_DATA&&size>0&&size<=4*1024*1024){
            std::vector<uint64_t> buffer((size+7)/8);
            if(!format(PDH_HCOUNTER(counter_),PDH_FMT_LARGE|PDH_FMT_NOSCALE,&size,&count,reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data()))&&count<=buffer.size()*8/sizeof(PDH_FMT_COUNTERVALUE_ITEM_W)){
                auto *items=reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());int64_t bytes=0;bool valid=false;
                for(DWORD index=0;index<count;++index)if(items[index].FmtValue.CStatus<=1&&items[index].FmtValue.largeValue>=0){bytes+=items[index].FmtValue.largeValue;valid=true;}
                if(valid){gpu_peak_=std::max(gpu_peak_,bytes);out["gpu_bytes"]=bytes;out["gpu_observed_peak_bytes"]=gpu_peak_;}
            }
        }
    }
    return out;
}
void NativeResourceUsage::publish(const Area &area,size_t index){std::lock_guard<std::mutex> lock(mutex_);areas_[index]=area;}
void NativeResourceUsage::scan_directory(const std::wstring &path,int depth,Area &area,size_t index,bool report){
    if(stop_||area.limited)return;
    if(std::chrono::steady_clock::now()>=deadline_){timed_out_=true;area.limited=true;return;}
    if(depth>64||area.entries>=2000000){area.limited=true;return;}
    WIN32_FIND_DATAW data{};
    std::vector<std::wstring> children;
    HANDLE search=FindFirstFileExW((path+L"\\*").c_str(),FindExInfoBasic,&data,FindExSearchNameMatch,nullptr,FIND_FIRST_EX_LARGE_FETCH);
    if(search==INVALID_HANDLE_VALUE){if(GetLastError()!=ERROR_FILE_NOT_FOUND)++area.errors;return;}
    do {
        std::wstring name=data.cFileName;if(name==L"."||name==L"..")continue;
        if(stop_)break;
        if(std::chrono::steady_clock::now()>=deadline_){timed_out_=true;area.limited=true;break;}
        if(visited_[index].fetch_add(1)>=2000000){area.limited=true;break;}
        ++area.entries;
        if(data.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT){++area.links;continue;}
        if(data.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY){
            if(area.mode==1&&depth==0&&_wcsicmp(name.c_str(),L"addons"))continue;
            if(area.mode==2&&depth==0){
                if(protected_folder(name))continue;
                DWORD marker=GetFileAttributesW((path+L"\\"+name+L"\\.terraforest-derived.lock").c_str());
                if(marker==INVALID_FILE_ATTRIBUTES||(marker&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))continue;
            }
            if(depth==0)children.push_back(path+L"\\"+name);
            else scan_directory(path+L"\\"+name,depth+1,area,index,report);
        }else{
            bool include=true;
            if(area.mode==1&&depth==0){auto extension=name.find_last_of(L'.');auto suffix=extension==std::wstring::npos?L"":name.substr(extension);include=!_wcsicmp(name.c_str(),area.pack_file.c_str())||!_wcsicmp(suffix.c_str(),L".exe")||!_wcsicmp(suffix.c_str(),L".dll");}
            if(area.mode==2)include=depth>0&&name.size()>4&&!_wcsicmp(name.c_str()+name.size()-4,L".trc");
            if(include){area.bytes+=(uint64_t(data.nFileSizeHigh)<<32)|data.nFileSizeLow;++area.files;}
        }
        if(report&&area.entries%256==0)publish(area,index);
    }while(FindNextFileW(search,&data));
    DWORD error=GetLastError();if(!stop_&&!area.limited&&error!=ERROR_NO_MORE_FILES)++area.errors;
    FindClose(search);
    if(depth!=0||children.empty()||area.limited||stop_)return;
    publish(area,index);
    std::atomic<size_t> next{0};std::mutex merge_mutex;std::vector<std::thread> workers;
    const auto count=std::min<size_t>(children.size(),std::min<size_t>(4,std::max<size_t>(1,std::thread::hardware_concurrency()/2)));
    for(size_t worker=0;worker<count;++worker)workers.emplace_back([&](){
        SetThreadPriority(GetCurrentThread(),THREAD_PRIORITY_BELOW_NORMAL);
        while(!stop_&&!timed_out_&&visited_[index]<2000000){
            size_t child=next.fetch_add(1);if(child>=children.size())break;
            Area local;local.mode=area.mode;local.pack_file=area.pack_file;
            scan_directory(children[child],1,local,index,false);
            std::lock_guard<std::mutex> lock(merge_mutex);
            area.bytes+=local.bytes;area.files+=local.files;area.entries+=local.entries;
            area.links+=local.links;area.errors+=local.errors;area.limited=area.limited||local.limited;
            publish(area,index);
        }
    });
    for(auto &worker:workers)worker.join();
    if(next.load()<children.size())area.limited=true;
}
bool NativeResourceUsage::start_scan(const Array &locations,int64_t budget_ms){
    if(running_||locations.is_empty()||locations.size()>8||budget_ms<1||budget_ms>8000)return false;
    std::vector<Area> next;
    for(int index=0;index<locations.size();++index){
        if(locations[index].get_type()!=Variant::DICTIONARY)return false;
        Dictionary entry=locations[index];String id=entry.get("id",String()),path=entry.get("path",String());int mode=entry.get("mode",0);
        String pack=entry.get("pack_file",String("TerraForest.pck"));
        if(id.is_empty()||id.length()>64||!path.is_absolute_path()||path.begins_with("res://")||path.begins_with("user://")||path.begins_with("//")||path.begins_with("\\\\")||!pack.is_valid_filename()||mode<0||mode>2)return false;
        for(const auto &previous:next)if(previous.id==id.utf8().get_data())return false;
        Area area;area.id=id.utf8().get_data();area.path=wide(path.simplify_path());area.pack_file=wide(pack);area.mode=mode;next.push_back(std::move(area));
    }
    if(worker_.joinable())worker_.join();
    {std::lock_guard<std::mutex> lock(mutex_);areas_=std::move(next);}
    for(auto &visited:visited_)visited=0;
    stop_=false;timed_out_=false;elapsed_ms_=0;started_=std::chrono::steady_clock::now();deadline_=started_+std::chrono::milliseconds(budget_ms);running_=true;
    worker_=std::thread([this](){
        SetThreadPriority(GetCurrentThread(),THREAD_PRIORITY_BELOW_NORMAL);
        for(size_t index=0;index<areas_.size()&&!stop_&&!timed_out_;++index){
            Area area;{std::lock_guard<std::mutex> lock(mutex_);area=areas_[index];}
            area.started=true;
            DWORD attributes=GetFileAttributesW(area.path.c_str());
            area.available=attributes!=INVALID_FILE_ATTRIBUTES&&(attributes&FILE_ATTRIBUTE_DIRECTORY)&&!(attributes&FILE_ATTRIBUTE_REPARSE_POINT);
            if(area.available)scan_directory(area.path,0,area,index);
            area.complete=!stop_&&!area.limited&&area.errors==0;publish(area,index);
        }
        elapsed_ms_=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started_).count();running_=false;
    });
    return true;
}
void NativeResourceUsage::cancel_scan(){if(running_)stop_=true;}
Dictionary NativeResourceUsage::scan_status(){
    Dictionary out;Array rows;
    {std::lock_guard<std::mutex> lock(mutex_);for(const auto &area:areas_){Dictionary row;row["id"]=narrow(area.id);row["bytes"]=area.bytes;row["files"]=area.files;row["entries"]=area.entries;row["links"]=area.links;row["errors"]=area.errors;row["started"]=area.started;row["available"]=area.available;row["complete"]=area.complete;row["limited"]=area.limited;rows.append(row);}}
    out["running"]=bool(running_);out["cancelled"]=bool(stop_);out["timed_out"]=bool(timed_out_);out["elapsed_ms"]=running_?int64_t(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started_).count()):elapsed_ms_.load();out["areas"]=rows;return out;
}
NativeResourceUsage::~NativeResourceUsage(){
    stop_=true;if(worker_.joinable())worker_.join();
    if(query_&&pdh_){auto close=reinterpret_cast<decltype(&PdhCloseQuery)>(GetProcAddress(HMODULE(pdh_),"PdhCloseQuery"));if(close)close(PDH_HQUERY(query_));}
    if(pdh_)FreeLibrary(HMODULE(pdh_));
}
}
