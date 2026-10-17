# valley-of-the-shadow-gamejam
A 3D Game where you fight in the Psalm 23 valley of the shadow against the demons by finding swords or other armor.

## Pitch Deck

https://docs.google.com/presentation/d/1ccr6mZ1R_mxeQAmBeHe4VsWi2UIe3YXjzyVI0q1672Y/edit?usp=sharing

---

## Level Map & Editor Populating Tools

### Overview of Architecture
The level architecture consists of four integrated systems:
1. **[scripts/level_data.gd](scripts/level_data.gd)** (`LevelData`) & **[scripts/level_exit_data.gd](scripts/level_exit_data.gd)** (`LevelExitData`):
   - Standalone Godot `Resource` format storing 2D/3D grid terrain types (`GRASS`, `MUD`, `DEBRIS`, `DIRT`, `STONE`, `WATER`), stepped elevation levels, and static objects (`TREE`, `ROCK`, `DEBRIS_PILE`, `RUIN_PILLAR`, `BUSH`).
   - Stores entrance positions (`entrances` dictionary) and multiple exits (`exits: Array[LevelExitData]`), connecting different level files or scenes together.
   - Stores gameplay regions: `weapon_spawns` (positions, item types) and `enemy_guard_zones` (guard positions, patrol radii, path-blocking barriers).
2. **[scripts/level_map_generator.gd](scripts/level_map_generator.gd)** (`LevelMapGenerator`):
   - Procedural generator driven by `FastNoiseLite` (elevation simplex noise, terrain detail wobble noise, and cellular object distribution noise).
   - Modes:
     - `LINEAR_PATH`: 30-second winding main path with shoulders, hills, an optional side-quest branch, weapon relic spawns, and a guardian roadblock on `exit_main`.
     - `OPEN_EXPLORATION`: Open valley with ancient ruins, multi-directional exits (North, East), and arena weapon spawns.
     - `SIDE_QUEST_MAZE`: Labyrinthine canyon/ruins with maze walls, dead ends, and a guarding stalker.
3. **[scripts/level_map_populator.gd](scripts/level_map_populator.gd)** (`LevelMapPopulator`):
   - `@tool` script for the Godot editor.
   - Synchronizes `LevelData` with a 2D `TileMapLayer` (`TerrainTileMap`) used for painting. The layer exists only in `scenes/editor.tscn` and is hidden at runtime.
   - Automatically builds the full 3D stepped terrain collision mesh (`ArrayMesh` + `trimesh_shape` StaticBody3D).
   - Populates 3D scenery (trees with collision, rocks, debris piles, ruin pillars, bushes).
   - Generates interactive weapon pickup areas and enemy guard zones with barrier gates.
   - Generates illuminated portal exit beacons that trigger transitions when the player (collision layer 2) enters them.
4. **[scripts/level.gd](scripts/level.gd)**:
   - Root level manager that connects exit signals and transitions smoothly between levels and entrance points. Level changes run deferred, since exits fire from physics callbacks.

---

### Scenes
- `scenes/editor.tscn`: the authoring scene. Open it in the Godot editor to generate, paint, and save levels. It is not part of the game.
- `scenes/main.tscn`: the playable 3D game and the project's main scene (F5). Its `LevelMapPopulator` plays `res://levels/level_01.tres`. It contains no 2D TileMapLayer.

### How to Use the Tools in the Godot Editor

#### 1. Procedurally Seeding a Level
1. Open `scenes/editor.tscn` in the Godot editor.
2. Select the `LevelMapPopulator` node in the Scene tree.
3. In the Inspector:
   - Choose a **Generation Mode**: `LINEAR_PATH`, `OPEN_EXPLORATION`, or `SIDE_QUEST_MAZE`.
   - Set **World Seed** (e.g. `1337`, `42`, or any integer).
   - Toggle **Generate Level Button** on.
4. The generator will compute the terrain, place scenery, weapon spawns, guard zones, and exits, and automatically rebuild the 3D scene.

#### 2. Visual Painting & Modifying in Godot Editor via `TileMapLayer`
1. Under `LevelMapPopulator`, select the child node `TerrainTileMap` (`TileMapLayer`).
2. The Godot 2D tile editor dock opens at the bottom with the 6 terrain palette tiles:
   - Tile `0` (Green): `GRASS` (Road / Walkway)
   - Tile `1` (Brown): `MUD` (Inner shoulder)
   - Tile `2` (Grey-Brown): `DEBRIS` (Outer shoulder)
   - Tile `3` (Ochre): `DIRT` (Hills & Wildlands)
   - Tile `4` (Slate Grey): `STONE` (Walls & Ruins)
   - Tile `5` (Blue): `WATER` (Depressions)
3. Paint any paths, clearings, or terrain variations with the pencil/bucket tool in the editor.
4. When done painting, select `LevelMapPopulator` in the Scene tree and turn on **Sync From Tilemap Button** in the Inspector. The 3D preview updates. The game reads only the saved level file, so save it as described in section 3.

#### 3. Saving & Reusing Level Files
- In `scenes/editor.tscn`, click the dropdown on the `Level Data` property of `LevelMapPopulator` and choose **Save As...**. Save to `res://levels/level_01.tres` to replace the level the game plays, or to a new file such as `res://levels/my_level.tres`.
- To play a different file, assign it to the `Level Data` property of `LevelMapPopulator` in `scenes/main.tscn`.
- Painted tiles reach the level only after **Sync From Tilemap** (step 2). Paint saved inside `editor.tscn` is not read by the game.
- Level files can also be referenced from other levels' `target_level_path`.

#### 4. Configuring Entrances and Multiple Exits
In the `LevelData` resource (or directly in the inspector under `level_data`):
- **Entrances**: Set coordinate keys such as `"start"`: `(40, 6)` or `"from_dungeon"`: `(15, 60)`.
- **Exits**: Add items to `exits`:
  - `id`: Unique identifier (e.g. `"exit_ruins"`).
  - `grid_pos`: Grid position on the map (e.g. `(70, 40)`).
  - `target_level_path`: Destination level (e.g. `"res://levels/level_02.tres"`).
  - `target_entrance_id`: Destination entrance identifier (e.g. `"start"`).
  - `label`: On-screen or portal name.
  - `color`: Beam of light beacon color.

#### 5. Gameplay Pacing (~30 Seconds per Level)
- Character walk speed is $5.0\text{ m/s}$.
- An $80 \times 80$ block map with a winding path provides approximately 70–85 linear blocks of travel:
  $$\text{Travel Time} = \frac{70\text{--}85\text{ m}}{5\text{ m/s}} \approx 14\text{--}17\text{ s (direct run)} \quad \text{to} \quad 30\text{ s (with slope navigation, weapon stops, and enemy barrier)}.$$

### Known Limitations
- Enemy guard barriers have no defeat or removal logic yet.
- Each guard gate is a ring of 29 ruin pillars around its guarded exit (`exit_main` in `LINEAR_PATH`, `exit_north` in `OPEN_EXPLORATION`, `exit_depths` in `SIDE_QUEST_MAZE`). The ring has a 3-cell gap on the start side, and the guard stands 2 cells outside the gap. The gap is closed by three barrier slabs.
- The generator keeps a gate only if route search shows that the gap is the sole route to its exit and the other exits stay reachable. Otherwise it logs a warning and places no guard.
- Rocks are climbable, so gates use ruin pillars. Terrain slopes are limited to one level per cell, so only objects can block a route.
- Until enemy defeat or barrier removal exists, the guarded exits stay closed.
- Weapon pickups are placeholders with no pickup logic yet.
- Exits with an empty `target_level_path` return the player to the start entrance.
- The 2D paint layer covers terrain only. Elevation, objects, and gameplay markers are generated, not painted.
