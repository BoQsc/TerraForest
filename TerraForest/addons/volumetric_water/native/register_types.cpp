#include "lake_volume.hpp"
#include "lake_catalog.hpp"
#include "water_quantity.hpp"
#include "water_capacity.hpp"
#include "water_settling.hpp"
#include "water_topology.hpp"
#include "water_basins.hpp"
#include "water_profiles.hpp"
#include "water_field.hpp"
#include "water_regions.hpp"
#include "water_network.hpp"
#include "water_surface.hpp"
#include "water_scene.hpp"
#include "water_runtime.hpp"
#include "water_remap_plan.hpp"
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(terraforest::NativeLakeVolume);
        GDREGISTER_CLASS(terraforest::NativeLakeCatalog);
        GDREGISTER_CLASS(terraforest::NativeWaterQuantity);
        GDREGISTER_CLASS(terraforest::NativeWaterCapacity);
        GDREGISTER_CLASS(terraforest::NativeWaterSettling);
        GDREGISTER_CLASS(terraforest::NativeWaterTopology);
        GDREGISTER_CLASS(terraforest::NativeWaterBasins);
        GDREGISTER_CLASS(terraforest::NativeWaterProfiles);
        GDREGISTER_CLASS(terraforest::NativeWaterField);
        GDREGISTER_CLASS(terraforest::NativeWaterRegions);
        GDREGISTER_CLASS(terraforest::NativeWaterNetwork);
        GDREGISTER_CLASS(terraforest::NativeWaterSurface);
        GDREGISTER_CLASS(terraforest::NativeWaterScene);
        GDREGISTER_CLASS(terraforest::NativeWaterRuntime);
        GDREGISTER_CLASS(terraforest::NativeWaterRemapPlan);
    }
}
static void terminate(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT terraforest_water_init(
    GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
