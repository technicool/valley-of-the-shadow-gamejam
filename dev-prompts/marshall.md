

## Level editing idea 1

Create a level populating script for the godot editor, a level map script, and a  data format to store terrain, altitude, and extra static objects on positions (debris, trees, etc)
Also a map data to allow for areas where weapons can spawn and where the region an enemy guards that prevents passing the path.

Ensure the level creation allows to join different levels with a start and different exit positions to other levels.

Provide documentation on how to use the tools in Godot editor to seed and then modify the areas. Modes for paths and for side quest maze or open areas.

Each level should be playable in about 30 seconds of travel with the character

Use  Godot’s built-in `TileMapLayer` for the terrain and the debris, trees, enemeies, and other scenery. If there is a way to allow for variation dynamically, incorporate combined with `FastNoiseLite` to procedurally map out terrain or other randomness.

Ensure the entrance/exit points are configurable for the levels (multiple exits to other levels)


## Level seeding for 2 starts

create 2 level tilemap files. the first should be the existing valley with high cliff edges, and a trail in the middle of a muddy valley path. the second should be a wide open field with a path that leds to it. Ensure that the main scene can load level 1 on start.

