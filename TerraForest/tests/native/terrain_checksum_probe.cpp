// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "terrain_checksum.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int failures=0;
void check(bool ok,const char *name){
 printf("{\"name\":\"%s\",\"passed\":%s}\n",name,ok?"true":"false");
 failures+=!ok;
}
u32 fnv(const u8 *p,int n){u32 h=2166136261u;while(n--){h^=*p++;h*=16777619u;}return h;}
std::vector<u8> save(const World &w,bool fast=false){
 Bytes b;w.serialize(b,fast);std::vector<u8> result(b.p,b.p+b.n);b.release();return result;
}
void reseal(std::vector<u8> &b){u32 h=terrain_checksum::software(b.data(),int(b.size()-4));copy_bytes(b.data()+b.size()-4,&h,4);}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 const u8 *golden=reinterpret_cast<const u8 *>("123456789");
 check(terrain_checksum::software(golden,9)==0xe3069283u&&terrain_checksum::checksum(golden,9)==0xe3069283u,"standard CRC32C golden vector");
 check(terrain_checksum::checksum(nullptr,0)==0,"empty input CRC32C");
 std::vector<u8> data(131080);u32 random=42;
 for(auto &v:data){random=random*1664525u+1013904223u;v=u8(random>>24);}
 bool parity=true;
 for(int offset=0;offset<8;offset++)for(int size=0;size<=131072;size=size<64?size+1:size*2){
  u32 expected=terrain_checksum::software(data.data()+offset,size);
  parity&=terrain_checksum::checksum(data.data()+offset,size)==expected;
#if defined(TERRAFOREST_CRC_HW)
  if(terrain_checksum::available())parity&=terrain_checksum::accelerated(data.data()+offset,size)==expected;
#endif
 }
 check(parity,"hardware and portable CRC32C agree on all alignments and tails");
 World source;source.init(1703,19);V3 lo,hi;int changes;
 V3 p={1200,source.height(1200,1200)-.6f,1200};source.edit(p,p,2.5f,0,false,1,lo,hi,changes);
 check(changes>0&&source.pages.n>0,"fixture contains actual edited terrain pages");
 auto legacy=save(source),fast=save(source,true);
 bool framing=legacy.size()==fast.size();
 for(size_t i=0;i+4<legacy.size();i++)if(i<4||i>=8)framing&=legacy[i]==fast[i];
 check(framing&&legacy[4]==2&&fast[4]==3,"format 3 changes only format tag and integrity checksum");
 World restored;restored.init(99);
 check(restored.deserialize(fast.data(),int(fast.size()))&&save(restored)==legacy,"format 3 restores exact pages materials generator and metadata");
 check(restored.deserialize(legacy.data(),int(legacy.size()))&&save(restored)==legacy,"format 2 remains readable and byte stable");
 World old_source;old_source.init(42,1);auto old2=save(old_source);auto old1=old2;
 old1.erase(old1.begin()+28,old1.begin()+32);old1[4]=1;
 u32 h=fnv(old1.data(),int(old1.size()-4));copy_bytes(old1.data()+old1.size()-4,&h,4);
 check(restored.deserialize(old1.data(),int(old1.size()))&&save(restored)==old2,"legacy format 1 remains readable");
 restored.deserialize(fast.data(),int(fast.size()));bool atomic=true;
 for(size_t offset:{size_t(0),size_t(4),size_t(8),size_t(28),size_t(32),fast.size()/2,fast.size()-1}){
  auto broken=fast;broken[offset]^=1;
  atomic&=!restored.deserialize(broken.data(),int(broken.size()))&&save(restored)==legacy;
 }
 for(int size:{0,7,31,32,int(fast.size()-1)})atomic&=!restored.deserialize(fast.data(),size)&&save(restored)==legacy;
 check(atomic,"corruption and truncation reject without changing live terrain");
 auto broken=fast;u32 invalid=99;copy_bytes(broken.data()+28,&invalid,4);reseal(broken);
 check(!restored.deserialize(broken.data(),int(broken.size()))&&save(restored)==legacy,"valid CRC cannot bypass generator semantic validation");
 broken=fast;invalid=0xffffffffu;copy_bytes(broken.data()+32,&invalid,4);reseal(broken);
 check(!restored.deserialize(broken.data(),int(broken.size()))&&save(restored)==legacy,"valid CRC cannot bypass page address validation");
 Bytes request,response;request.u(4);request.u(3);process_request(source,request.p,request.n,response);
 check(response.n==int(fast.size())+12&&response.p[8]==0&&!std::memcmp(response.p+12,fast.data(),fast.size()),"command 4 explicitly selects format 3");
 request.release();response.release();request.u(4);request.u(99);process_request(source,request.p,request.n,response);
 check(response.n>=12&&response.p[8]!=0,"unknown serialization option rejects");
 request.release();response.release();
 auto allocator=tr_realloc;tr_realloc=[](void*,size_t)->void*{return nullptr;};
 Bytes denied;source.serialize(denied,true);
 check(tr_oom&&denied.n==0&&denied.p==nullptr,"save allocation rejection leaves no partial archive");
 tr_realloc=allocator;tr_oom=false;denied.release();
 source.release();restored.release();old_source.release();
 return failures?1:0;
}
