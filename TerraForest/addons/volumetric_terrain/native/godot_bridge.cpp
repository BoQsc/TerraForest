// SPDX-License-Identifier: 0BSD
#include "godot_abi.h"
#include "core.h"
#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
// Standalone DLL: no C/C++ runtime DLL or installer is required.
extern "C" int _fltused=0;
extern "C" void*memcpy(void*d,const void*s,size_t n){copy_bytes(d,s,n);return d;}
extern "C" void*memset(void*d,int v,size_t n){auto p=(u8*)d;for(size_t i=0;i<n;i++)p[i]=u8(v);return d;}
extern "C" void*memmove(void*d,const void*s,size_t n){auto a=(u8*)d;auto b=(const u8*)s;if(a<b){for(size_t i=0;i<n;i++)a[i]=b[i];}else for(size_t i=n;i>0;i--)a[i-1]=b[i-1];return d;}
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif
static GDPtr library;
static GDOpaque class_name,parent_name,execute_name,size_name,resize_name,empty_name,empty_string,result_name;
static void(*sn_new)(GDPtr,const char*);
static void(*register_class)(GDPtr,GDConst,GDConst,const GDClassInfo2*);
static void(*unregister_class)(GDPtr,GDConst);
static void(*register_method)(GDPtr,GDConst,const GDMethodInfo*);
static GDPtr(*construct_object)(GDConst);
static void(*set_instance)(GDPtr,GDConst,void*);
static void(*variant_call)(GDPtr,GDConst,const GDConst*,GDInt,GDPtr,GDCallError*);
static void(*variant_destroy)(GDPtr);
static void(*variant_nil)(GDPtr);
static int32_t(*variant_type)(GDConst);
static GDTypeCtor(*from_type)(int32_t);
static GDTypeCtor(*to_type)(int32_t);
static GDConstructor(*get_constructor)(int32_t,int32_t);
static GDDestructor(*get_destructor)(int32_t);
static const u8*(*bytes_const)(GDConst,GDInt);
static u8*(*bytes_write)(GDPtr,GDInt);
static void(*print_error)(const char*,const char*,const char*,int32_t,GDBool);
static void return_bytes(GDPtr target,const Bytes&b){
 GDOpaque packed,var,length,ret;get_constructor(29,0)(&packed,nullptr);from_type(29)(&var,&packed);get_destructor(29)(&packed);
 GDInt n=b.n;from_type(2)(&length,&n);GDConst args[]={&length};GDCallError err{};
 variant_call(&var,&resize_name,args,1,&ret,&err);variant_destroy(&ret);variant_destroy(&length);
 to_type(29)(&packed,&var);variant_destroy(&var);
 if(b.n)copy_bytes(bytes_write(&packed,0),b.p,b.n);
 from_type(29)(target,&packed);get_destructor(29)(&packed);
}
static void execute(void*,void*instance,const GDConst*args,GDInt argc,GDPtr ret,GDCallError*error){
 error->error=0;error->argument=0;error->expected=0;
 if(argc!=1||variant_type(args[0])!=29){error->error=argc<1?4:(argc>1?3:2);error->expected=29;variant_nil(ret);return;}
 GDOpaque length,packed;GDCallError call_error{};variant_call((GDPtr)args[0],&size_name,nullptr,0,&length,&call_error);GDInt n=0;to_type(2)(&n,&length);variant_destroy(&length);
 if(n<4||n>512ll*1024*1024){Bytes b;b.u(REPLY_MAGIC);b.u(0);b.u(1);return_bytes(ret,b);b.release();return;}
 to_type(29)(&packed,(GDPtr)args[0]);const u8*data=bytes_const(&packed,0);Bytes result;
 process_request(*(World*)instance,data,int(n),result);get_destructor(29)(&packed);return_bytes(ret,result);result.release();
}
static GDPtr create_instance(void*){
 auto w=(World*)tr_alloc(sizeof(World));if(!w)return nullptr;zero_bytes(w,sizeof(World));w->init();
 GDPtr object=construct_object(&parent_name);if(!object){w->release();tr_free(w);return nullptr;}set_instance(object,&class_name,w);return object;
}
static void free_instance(void*,void*instance){if(instance){auto w=(World*)instance;w->release();tr_free(w);}}
static void initialize(void*,int32_t level){
 if(level!=2)return;
 sn_new(&class_name,"TerrainCore");sn_new(&parent_name,"RefCounted");sn_new(&execute_name,"execute");sn_new(&size_name,"size");sn_new(&resize_name,"resize");sn_new(&empty_name,"");sn_new(&result_name,"result");get_constructor(4,0)(&empty_string,nullptr);
 GDClassInfo2 info{};info.is_exposed=1;info.create_instance_func=create_instance;info.free_instance_func=free_instance;
 register_class(library,&class_name,&parent_name,&info);
 GDPropertyInfo result{};result.type=29;result.name=&result_name;result.class_name=&empty_name;result.hint_string=&empty_string;result.usage=6;
 GDMethodInfo method{};method.name=&execute_name;method.call_func=execute;method.method_flags=1|16;method.has_return_value=1;method.return_value_info=&result;
 // A vararg entry point intentionally avoids generated ptrcall bindings and method hashes.
 register_method(library,&class_name,&method);
}
static void deinitialize(void*,int32_t level){if(level!=2)return;unregister_class(library,&class_name);GDOpaque*names[]={&class_name,&parent_name,&execute_name,&size_name,&resize_name,&empty_name,&result_name};for(auto n:names)get_destructor(21)(n);get_destructor(4)(&empty_string);}
EXPORT GDBool terrain_library_init(GDGetProc get,GDPtr lib,GDInitialization*init){
 library=lib;
#define LOAD(VAR,NAME) VAR=reinterpret_cast<decltype(VAR)>(get(NAME));if(!VAR)return 0
 LOAD(tr_alloc,"mem_alloc");LOAD(tr_realloc,"mem_realloc");LOAD(tr_free,"mem_free");
 LOAD(sn_new,"string_name_new_with_utf8_chars");LOAD(register_class,"classdb_register_extension_class2");LOAD(unregister_class,"classdb_unregister_extension_class");LOAD(register_method,"classdb_register_extension_class_method");
 LOAD(construct_object,"classdb_construct_object");LOAD(set_instance,"object_set_instance");LOAD(variant_call,"variant_call");LOAD(variant_destroy,"variant_destroy");LOAD(variant_nil,"variant_new_nil");LOAD(variant_type,"variant_get_type");
 LOAD(from_type,"get_variant_from_type_constructor");LOAD(to_type,"get_variant_to_type_constructor");LOAD(get_constructor,"variant_get_ptr_constructor");LOAD(get_destructor,"variant_get_ptr_destructor");LOAD(bytes_const,"packed_byte_array_operator_index_const");LOAD(bytes_write,"packed_byte_array_operator_index");LOAD(print_error,"print_error");
#undef LOAD
 init->minimum_initialization_level=2;init->userdata=nullptr;init->initialize=initialize;init->deinitialize=deinitialize;return 1;
}
