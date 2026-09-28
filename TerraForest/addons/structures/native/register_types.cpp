#include "block_world.hpp"
#include "static_batch.hpp"
#include "structures_snapshot.hpp"
#include "structure_queries.hpp"
#include <godot_cpp/godot.hpp>
using namespace godot;
static void initialize(ModuleInitializationLevel level) {
    if(level==MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(terraforest::NativeBlockPrefab);
        GDREGISTER_CLASS(terraforest::NativeBlockWorld);
        GDREGISTER_CLASS(terraforest::NativeStaticBatch);
        GDREGISTER_CLASS(terraforest::NativeStructuresSnapshot);
        GDREGISTER_CLASS(terraforest::NativeStructureQueries);
    }
}
static void terminate(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT terraforest_structures_init(GDExtensionInterfaceGetProcAddress get_proc_address,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address,library,initialization);
    init.register_initializer(initialize); init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
