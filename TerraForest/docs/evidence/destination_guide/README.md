# Gameplay destination guide

World-directory Track buttons are available in gameplay and development mode.
The HUD shows direct camera-relative bearing, horizontal distance, height offset
and an arrival indication. Selection does not mutate the world, move the player,
or query terrain. A 0.2-second UI timer runs only while a destination is selected;
clearing stops it. Menus, inventory and loading hide the guide. The vehicle system
already updates the occupant position and camera, which the guide reads.

Headless checks cover forward/right/left/back bearings, rotated facing, arrival,
and a target directly overhead which must not count as arrived. The actual-world
check used regional_workshops_20261018 with read-only snapshot mode. It pressed
the gameplay Track button, verified unchanged position and loading state, checked
HUD visibility, stopped tracking via the menu, and verified development travel
still reaches the western site. Passed in 21.57 seconds; both 1920x1080 screenshots
were inspected. This is not road pathfinding or a driving-route test. Selection
is session-local. No new native simulation or terrain rendering work was added.
