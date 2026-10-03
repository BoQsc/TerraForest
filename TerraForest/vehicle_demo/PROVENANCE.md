# Vehicle source and license

The user supplied and authored the code and Vehicle.glb in
Godot_Vehicle_Driving_Test_FRESH_HEADLESS_REIMPORT_FIXED.zip, and explicitly
declared both their own 0BSD work in this chat on 2026-10-03.
Archive SHA-256: f38fc00ecd7a95ecd43c6beaf70f744f797dd862d656cb0d69822cf682cc82a0.
LICENSE.txt records the 0BSD terms. godot-cpp retains its separate MIT notice
inside the native addon, as with the other TerraForest native dependencies.

Original scripts remain as a behavior reference. Resource paths were relocated
under vehicle_demo; car.tscn uses car_native.gd, which overrides steering and
longitudinal policy with NativeDrivingPolicy. NativeVehicleSuspension owns
wheel-contact sampling and spring forces; effects reuse its samples. Impact
recovery, visual damage, accessories and interaction still use the original logic.
The isolated demo preserves 120 Hz physics and uses TerraForest's fullscreen
1920x1080 Forward+ rendering for comparison. It is not integrated into the
streamed world and is not yet qualified for fleets or multiplayer.
