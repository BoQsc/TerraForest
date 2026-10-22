#include "regional_water.hpp"
#include "lake_catalog.hpp"
#include "water_region_store.hpp"
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(terraforest::NativeLakeCatalog);
        GDREGISTER_CLASS(terraforest::NativeWaterTerrainPatch);
        GDREGISTER_CLASS(terraforest::NativeWaterTerrainBatch);
        GDREGISTER_CLASS(terraforest::NativeWaterMapIdentity);
        GDREGISTER_CLASS(terraforest::NativeRegionalWater);
        GDREGISTER_CLASS(terraforest::NativeWaterSnapshot);
        GDREGISTER_CLASS(terraforest::NativeWaterRegionStore);
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
