#include "entity_store.hpp"
#include "entity_actor.hpp"
#include "entity_renderer.hpp"
#include "world_archive.hpp"
#include "road_anchors.hpp"
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;
static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(terraforest::NativeEntityStore);
        GDREGISTER_CLASS(terraforest::NativeEntityActor);
        GDREGISTER_CLASS(terraforest::NativeEntityRenderer);
        GDREGISTER_CLASS(terraforest::NativeWorldArchive);
        GDREGISTER_CLASS(terraforest::NativeRoadAnchors);
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
