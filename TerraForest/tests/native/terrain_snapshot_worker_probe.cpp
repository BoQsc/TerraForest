#include "experimental/snapshot_worker.hpp"
#include <chrono>
#include <cstdio>
using namespace terraforest::experimental;
int failures=0;
void check(bool ok,const char*name){printf("{\"name\":\"%s\",\"passed\":%s}\n",name,ok?"true":"false");failures+=!ok;}
template<class F>int drain(SnapshotWorker&worker,u64 epoch,int revision,F&&fn){
 int received=0;auto until=std::chrono::steady_clock::now()+std::chrono::seconds(5);
 while(received<2&&std::chrono::steady_clock::now()<until){received+=worker.consume(epoch,revision,fn);if(received<2)std::this_thread::sleep_for(std::chrono::milliseconds(1));}return received;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 World w;w.init();auto reference=build_world_region(w,960,960,32);
 SnapshotWorker worker(3*1024*1024,32*1024*1024);
 bool admitted=worker.submit(w,960,960,32,1,10)&&worker.submit(w,960,960,32,1,11);
 check(admitted&&!worker.submit(w,960,960,32,1,12),"two slots include queued running and unconsumed work");
 bool exact=true;int hits=0;
 int received=drain(worker,1,w.revision,[&](u64 token,u64,int,bool stale,const Result&r){exact&=!stale&&r.status==MeshStatus::ok&&!(r.p!=reference.p)&&!(r.indices!=reference.indices)&&(token==10||token==11);hits++;});
 check(received==2&&hits==2&&exact&&worker.snapshot_bytes()==0&&worker.mesh_bytes()==0,"two exact completions drain all tracked memory");
 admitted=worker.submit(w,960,960,32,1,20)&&worker.submit(w,960,960,32,1,21);
 V3 lo,hi;int changes;V3 p={976,w.height(976,976),976};w.edit(p,p,5,0,false,1,lo,hi,changes);
 bool stale_ok=true;
 received=drain(worker,1,w.revision,[&](u64,u64,int,bool stale,const Result&r){stale_ok&=stale&&r.status==MeshStatus::cancelled&&r.p.empty()&&r.indices.empty();});
 check(admitted&&changes>0&&received==2&&stale_ok,"world edit after admission rejects old revision completions");
 admitted=worker.submit(w,960,960,32,1,30)&&worker.submit(w,960,960,32,1,31);
 stale_ok=true;received=drain(worker,2,w.revision,[&](u64,u64,int,bool stale,const Result&r){stale_ok&=stale&&r.p.empty()&&r.indices.empty();});
 check(admitted&&received==2&&stale_ok,"epoch change rejects otherwise matching revisions");
 admitted=worker.submit(w,960,960,32,2,40)&&worker.submit(w,960,960,32,2,41);worker.stop();
 int stopped=worker.consume(2,w.revision,[](u64,u64,int,bool,const Result&){});
 check(admitted&&stopped==2&&!worker.submit(w,960,960,32,2,42)&&worker.snapshot_bytes()==0&&worker.mesh_bytes()==0,"shutdown joins and accounts for every accepted job");
 {
  SnapshotWorker limited(3*1024*1024,0);admitted=limited.submit(w,960,960,32,1,1)&&limited.submit(w,960,960,32,1,2);bool failed=true;
  received=drain(limited,1,w.revision,[&](u64,u64,int,bool,const Result&r){failed&=r.status==MeshStatus::allocation_failed&&r.p.empty()&&r.indices.empty();});
  check(admitted&&received==2&&failed&&limited.mesh_bytes()==0&&limited.snapshot_bytes()==0,"mesh budget failure produces explicit empty failures");
 }
 {SnapshotWorker limited(0,1024);check(!limited.submit(w,960,960,32,1,1)&&limited.snapshot_bytes()==0,"snapshot budget rejects before job admission");}
 w.release();return failures?1:0;
}
