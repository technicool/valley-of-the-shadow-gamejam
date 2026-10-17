# Shepherd Player and Combat: Implementation Plan

Each step is small, has its own "done when" check, and can be implemented and verified on its own. Work top to bottom.

## Current state (from the codebase)

- The player is one scene, [scenes/player.tscn](scenes/player.tscn), driven by [scripts/player.gd](scripts/player.gd). It is a capsule with no weapon, health, or attack. The main level and the 3D sidequests both instantiate it, so changing this one scene covers both.
- The 3D sidequests ([scripts/sidequest/sidequest_level_3d.gd](scripts/sidequest/sidequest_level_3d.gd)) spawn `sword`, `dagger`, and `slingshot` pickups and `wolf`, `bear`, and `giant` enemies from layout glyphs.
- The 2D path ([scripts/sidequest/sidequest_level.gd](scripts/sidequest/sidequest_level.gd), [scripts/sidequest/sidequest_player.gd](scripts/sidequest/sidequest_player.gd), `sidequest_enemy`, `sidequest_pickup`) is not referenced by any scene. It is a second, unused player.
- [elements/weapons/weapon_pickup.gd](elements/weapons/weapon_pickup.gd) emits `collected(weapon_id)`, but nothing connects to that signal.
- The main level builds its weapon pickups in `_create_weapon_pickup()` in [scripts/level_map_populator.gd](scripts/level_map_populator.gd). It creates a bare `Area3D` with no script and no `weapon_id`, so touching one does nothing.
- [elements/enemies/enemy_creature.gd](elements/enemies/enemy_creature.gd) has `max_health` and `attack_damage` exports, but no damage, death, or attack code.
- `scenes/sidequests` and the main level change scenes with `change_scene_to_file`. That destroys the player, so any state that must survive a sidequest trip has to live in an autoload.
- [project.godot](project.godot) binds Space (keycode 32) to `jump`. Space cannot be both jump and attack.
- Shepherd model: [assets/models/sketchfab/shepherd.glb](assets/models/sketchfab/shepherd.glb) (and `shepherd-alt.glb`). The mockup shows a staff in the left hand and a sword at the right hip.

## Decisions to confirm before Step 1

1. **Jump key.** Space becomes attack, remove jumping.
2. **Starting weapon.** unarmed at the start. The staff is always carried and only used if no other weapon, but it only has a 0% instant kill and damage only.
3. **80% rule meaning.** each successful hit rolls once. 80% of the time the enemy dies immediately. The other 20% of the time the hit deals the weapon's `damage`, and the enemy dies only if its health reaches 0. The rule applies to all three weapons, including slingshot stones.
4. **Slingshot ammo.** unlimited stones. Each stone flies until it hits an enemy, hits terrain, or times out after 3 seconds.
5. **Touch button.** Proposed: one on-screen attack button, shown only when `DisplayServer.is_touchscreen_available()` is true. It fires the same `attack` action as Space.

## Step 1: Shepherd model replaces the capsule body [DONE]

- **Files:** [scenes/player.tscn](scenes/player.tscn), new [assets/models/shepherd/shepherd_lowpoly.tscn](assets/models/shepherd/shepherd_lowpoly.tscn). Keep the existing `CapsuleShape3D` collider, since its size is tuned for movement and step-up.
- **Work:** Build the shepherd from low poly primitives to match the reference image: bearded face, white headwrap with brown band, tan tunic, grey apron with straps, brown belt, golden sword at the left hip, staff in the figure's right hand, sandals. Instance it under `Player` in place of the `Body` capsule mesh at 1:1 scale, feet at y = 0, about 1.8 m tall. Add `RightHand` and `LeftHand` anchor nodes for Step 4.
- **Done when:** The scene loads headlessly, and a windowed screenshot shows the shepherd standing on the ground with the collider aligned.

## Step 2: Remove the unused 2D player path [DONE]

- **Files:** [scripts/sidequest/sidequest_level.gd](scripts/sidequest/sidequest_level.gd), [scripts/sidequest/sidequest_player.gd](scripts/sidequest/sidequest_player.gd), [scenes/sidequests/sidequest_player.tscn](scenes/sidequests/sidequest_player.tscn), and the 2D sidequest pickup and enemy scripts. Confirm with a grep that nothing else references them first.
- **Done when:** A grep finds no references, all three 3D sidequests and the main scene still load, and the project has one player scene.

## Step 3: Equipped-weapon state in an autoload [DONE]

- **Files:** A new autoload, or an extension of [scripts/sidequest/sidequest_manager.gd](scripts/sidequest/sidequest_manager.gd). Register it in [project.godot](project.godot).
- **Work:** Store `equipped_weapon_id: String` (empty means unarmed). Add `equip(weapon_id)`, which replaces the current weapon, and a `changed` signal. Scene changes do not reset this state.
- **Done when:** A headless test equips sword, then dagger, and reads back `dagger`. The value persists across a `change_scene_to_file` call.

## Step 4: Held weapon visuals [DONE]

- **Files:** [scripts/player.gd](scripts/player.gd), [scenes/player.tscn](scenes/player.tscn).
- **Work:** Add a `BoneAttachment3D` on the shepherd's left hand bone. Attach the sword, dagger, or slingshot model to it, showing only the one that matches `equipped_weapon_id`. The staff stays in the right hand and is not controlled by equip state.
- **Done when:** Equipping each weapon in turn shows the correct model in the hand, and unarmed shows no weapon.

## Step 5: Pickups equip the player [DONE]

- **Files:** [elements/weapons/weapon_pickup.gd](elements/weapons/weapon_pickup.gd), [scripts/level_map_populator.gd](scripts/level_map_populator.gd).
- **Work:**
  - Connect `WeaponPickup` to the player's `equip` through the autoload from Step 3. On collect, call equip with `weapon_id`, then `queue_free`.
  - Replace the bare `Area3D` built in `_create_weapon_pickup()` with an instance of the matching weapon scene (`sword.tscn`, `dagger.tscn`, or `slingshot.tscn`) so the main level and the sidequests use the same pickup.
- **Done when:** Walking into a main-level weapon changes the equipped weapon, and so does walking into a sidequest weapon. The last pickup wins.

## Step 6: Attack input, and remove jump [DONE]

- **Files:** [project.godot](project.godot), [scripts/player.gd](scripts/player.gd).
- **Work:** Add an input action `attack` bound to Space. Replace the `jump` check in `_physics_process` only if it is needed. Add an attack cooldown timer.
- **Done when:** Space triggers `attack` (verified with a test that calls `Input.parse_input_event`), and jump works on the new key.

## Step 7: Melee swing (sword and dagger) [DONE]

- **Files:** [scripts/player.gd](scripts/player.gd), or a new `melee_weapon.gd` element.
- **Work:** On `attack`, if the equipped weapon is melee, open a swing window of about 0.25 s. During it, an `Area3D` hit box in front of the player checks overlapping bodies in group `enemy`. Each enemy is hit at most once per swing. Values per weapon: sword has longer reach and a slower cooldown. Dagger has shorter reach and a faster cooldown. Both sets are exported so they can be tuned.
- **Done when:** A headless test places an enemy in front of the player and confirms one hit per swing, and none when the enemy is out of reach.

## Step 8: Slingshot stones [DONE]

- **Files:** New `elements/weapons/stone_projectile.gd` and scene, plus [scripts/player.gd](scripts/player.gd).
- **Work:** On `attack` with the slingshot equipped, spawn a stone at the hand position. Give it velocity along the camera's forward direction. On contact with an enemy, call the hit resolution from Step 9. Remove the stone on terrain contact or after 3 s.
- **Done when:** A headless test fires a stone at an enemy and confirms the hit is resolved. The stone is removed after 3 s without hitting anything.

## Step 9: Hit resolution with the 80% kill chance

- **Files:** [elements/enemies/enemy_creature.gd](elements/enemies/enemy_creature.gd), plus a shared function (for example `CombatRules.resolve_hit`).
- **Work:**
  - Add `take_damage(amount)` and `die()`. `die()` removes the enemy from group `enemy` and frees it.
  - `resolve_hit(enemy, weapon_damage, rng)`: roll once. If the roll is below 0.8, call `die()`. Otherwise call `take_damage(weapon_damage)`.
  - Export `instant_kill_chance: float = 0.8` so it can be tuned.
  - Use an injectable `RandomNumberGenerator` so tests can seed it.
- **Done when:** A seeded test runs 10,000 rolls and the instant-kill rate is within 0.78 to 0.82. A separate test confirms a 20% branch hit with the wolf (12 health) and a 10-damage sword leaves the wolf alive, and a second hit kills it.

## Step 10: Make main-level guards targetable

- **Files:** [scripts/level_map_populator.gd](scripts/level_map_populator.gd) (`_create_enemy_guard_zone`), [elements/enemies/enemy_creature.gd](elements/enemies/enemy_creature.gd).
- **Work:** Confirm that the guard enemy stand-in in the main level is a `CharacterBody3D` in group `enemy` that uses the Step 9 hit path. If not, instance one of the creature scenes instead (for example `wolf.tscn`).
- **Done when:** A headless test in the main level scene can hit and kill a guard with a sword.

## Step 11: Touch attack button

- **Files:** New `scripts/touch_controls.gd` and a `CanvasLayer` added to [scenes/player.tscn](scenes/player.tscn) or to `main.tscn`.
- **Work:** Add one on-screen button. Show it only when `DisplayServer.is_touchscreen_available()` is true. On press, call `Input.action_press("attack")`, and on release call `Input.action_release("attack")`. The swing and stone logic from Steps 7 and 8 must not depend on which input caused it.
- **Done when:** A test that calls `Input.action_press("attack")` triggers the same swing as Space. The button is hidden on desktop builds.

## Step 12: Verification pass

- Load `main.tscn`, `sidequest_crypt.tscn`, `sidequest_grove.tscn`, and `sidequest_ruins.tscn` headlessly with no errors.
- Walk through: pick up a sword, swing at a wolf, pick up a slingshot in the ruins, fire a stone, leave the sidequest, and confirm the slingshot is still equipped in the main level.
- Confirm that the 80% rate test still passes.

## Testing rules (from AGENTS.md)

- Every headless test must cap its runtime. Use an internal timer of 5 s, or 30 s at most for a level that needs longer. Do not let a test loop forever.
- Use `godot --headless --path . --script res://...` for tests. Add an explicit fail-and-quit path, since a runtime error inside `_physics_process` does not stop the loop.
- Use `--import` to rebuild the class cache after adding a new `class_name` script.

## Out of scope for this plan

- Enemy attacks against the player, and player health.
- Ammo limits and stone pickup.
- Changing the 2D sidequests beyond the removal in Step 2.
