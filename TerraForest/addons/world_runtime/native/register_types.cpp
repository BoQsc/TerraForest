#include "entity_store.hpp"
#include "surface_map_raster.hpp"
#include "entity_actor.hpp"
#include "entity_activation.hpp"
#include "actor_navigator.hpp"
#include "zombie_awareness.hpp"
#include "zombie_population.hpp"
#include "zombie_anatomy.hpp"
#include "zombie_rest_body.hpp"
#include "entity_renderer.hpp"
#include "world_archive.hpp"
#include "derived_cache_index.hpp"
#include "resource_usage.hpp"
#include "road_anchors.hpp"
#include "generated_region.hpp"
#include "road_editor_settings.hpp"
#include "world_recipe.hpp"
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;
static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(terraforest::NativeEntityStore);
        GDREGISTER_CLASS(terraforest::NativeSurfaceMapRaster);
        GDREGISTER_CLASS(terraforest::NativeEntityActor);
        GDREGISTER_CLASS(terraforest::NativeActorOrders);
        GDREGISTER_CLASS(terraforest::NativeEntityActivation);
        GDREGISTER_CLASS(terraforest::NativeActorNavigator);
        GDREGISTER_CLASS(terraforest::NativeZombieAwareness);
        GDREGISTER_CLASS(terraforest::NativeZombiePopulation);
        GDREGISTER_CLASS(terraforest::NativeZombiePhysicalBone);
        GDREGISTER_CLASS(terraforest::NativeZombieRigidPart);
        GDREGISTER_CLASS(terraforest::NativeZombieAnatomy);
        GDREGISTER_CLASS(terraforest::NativeEntityRenderer);
        GDREGISTER_CLASS(terraforest::NativeWorldArchive);
        GDREGISTER_CLASS(terraforest::NativeDerivedCacheIndex);
        GDREGISTER_CLASS(terraforest::NativeResourceUsage);
        GDREGISTER_CLASS(terraforest::NativeRoadAnchors);
        GDREGISTER_CLASS(terraforest::NativeGeneratedRegion);
        GDREGISTER_CLASS(terraforest::NativeRoadEditorSettings);
        GDREGISTER_CLASS(terraforest::NativeWorldRecipe);
    }
}
static void terminate(ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT terraforest_runtime_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
