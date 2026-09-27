// Minimal ABI declarations from Godot's gdextension_interface.h (4.3).
// Godot's MIT copyright/license is retained in GODOT_INTERFACE_LICENSE.txt.
// This file is NOT a third-party binding library; it is the engine's C ABI subset.
#pragma once
#include <stdint.h>
#include <stddef.h>
using GDPtr=void*;using GDConst=const void*;using GDBool=uint8_t;using GDInt=int64_t;
struct GDCallError {int32_t error,argument,expected;};
struct GDPropertyInfo {int32_t type;GDPtr name;GDPtr class_name;uint32_t hint;GDPtr hint_string;uint32_t usage;};
using GDMethodCall=void(*)(void*,void*,const GDConst*,GDInt,GDPtr,GDCallError*);
using GDMethodPtrCall=void(*)(void*,void*,const GDConst*,GDPtr);
struct GDMethodInfo {
 GDPtr name;void*method_userdata;GDMethodCall call_func;GDMethodPtrCall ptrcall_func;
 uint32_t method_flags;GDBool has_return_value;GDPropertyInfo*return_value_info;int32_t return_value_metadata;
 uint32_t argument_count;GDPropertyInfo*arguments_info;int32_t*arguments_metadata;
 uint32_t default_argument_count;GDPtr*default_arguments;
};
struct GDClassInfo2 {
 GDBool is_virtual,is_abstract,is_exposed;
 void *set_func,*get_func,*get_property_list_func,*free_property_list_func;
 void *property_can_revert_func,*property_get_revert_func,*validate_property_func;
 void *notification_func,*to_string_func,*reference_func,*unreference_func;
 GDPtr(*create_instance_func)(void*);void(*free_instance_func)(void*,void*);
 void *recreate_instance_func,*get_virtual_func,*get_virtual_call_data_func,*call_virtual_with_data_func,*get_rid_func;
 void *class_userdata;
};
struct GDInitialization {int32_t minimum_initialization_level;void*userdata;void(*initialize)(void*,int32_t);void(*deinitialize)(void*,int32_t);};
using GDProc=void(*)();using GDGetProc=GDProc(*)(const char*);
using GDTypeCtor=void(*)(GDPtr,GDPtr);
using GDConstructor=void(*)(GDPtr,const GDConst*);
using GDDestructor=void(*)(GDPtr);
// Opaque storage is deliberately larger than the single/double precision 64-bit ABI needs.
// All objects are constructed/destructed by Godot, never by guessing their private layout.
struct alignas(16) GDOpaque {uint8_t bytes[64];};
