// SPDX-License-Identifier: 0BSD
#include "terrain_region_store.hpp"
#include <set>
namespace terraforest {
bool NativeTerrainRegionStore::mount_world(World &world,const Buffer &reference){
 std::lock_guard<std::mutex> lock(mutex_);Index index;if(!load_index(reference,index))return false;
 // Verify every authoritative product before admitting the checkpoint, but keep
 // only one decoded region in scratch. Never construct an expanded world blob.
 std::set<uint32_t> expected(index.order.begin(),index.order.end());
 for(const auto &[key,entry]:index.regions){std::map<uint32_t,Buffer> pages;if(!load_region(key,entry,pages))return false;
  for(const auto &[page,raw]:pages)if(!expected.erase(page))return false;
 }
 if(!expected.empty())return false;
 World staged;staged.build_control=world.build_control;staged.init(index.seed,index.generator);staged.surface_style=world.surface_style;staged.revision=index.revision;staged.edits=index.edits;
 if(tr_oom||!staged.edit_columns){staged.release();return false;}
 if(!staged.pages.reserve(int(index.order.size()))){staged.release();return false;}
 int capacity=64;while((index.order.size()+1)*10>=size_t(capacity)*7)capacity*=2;staged.pages_by_key.rehash(capacity);
 if(tr_oom){staged.release();return false;}
 for(uint32_t key:index.order){Page page;page.key=key;page.clean_version=page.storage_version;
  int at=staged.pages.push(page);staged.pages_by_key.put(key,at);uint32_t v=key-1,x=v%WORLD_PAGE_COLUMNS;v/=WORLD_PAGE_COLUMNS;uint32_t z=v%WORLD_PAGE_COLUMNS,y=v/WORLD_PAGE_COLUMNS;staged.edit_columns[x+WORLD_PAGE_COLUMNS*z]|=1u<<y;
 }
 for(int64_t at=0;at<index.blocks.size();at+=8)if(!staged.set_block(index.blocks.decode_u32(at),index.blocks.decode_u32(at+4))){staged.release();return false;}
 if(tr_oom){staged.release();return false;}
 world.release();world=staged;page_cache_.clear();page_cache_id_=Buffer();page_cache_region_=0;return true;
}
NativeTerrainRegionStore::Buffer NativeTerrainRegionStore::read_page(const Buffer &reference,uint32_t page){
 std::lock_guard<std::mutex> lock(mutex_);if(!valid_page(page)||reference.size()!=40)return {};
 Buffer id=reference.slice(8,40);if(id!=cached_id_){Index ignored;if(!load_index(reference,ignored))return {};}
 uint32_t region=region_for(page);
 if(id!=page_cache_id_||region!=page_cache_region_){
  auto found=cached_index_.regions.find(region);if(found==cached_index_.regions.end())return {};
  std::map<uint32_t,Buffer> pages;if(!load_region(region,found->second,pages))return {};
  // Mount authenticated exact membership; the same immutable region digest is
  // checked again on each fault. No history-wide scan is needed on a page miss.
  page_cache_=std::move(pages);page_cache_id_=id;page_cache_region_=region;
 }
 auto found=page_cache_.find(page);return found==page_cache_.end()?Buffer():found->second;
}
}
