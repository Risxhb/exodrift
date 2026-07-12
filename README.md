# EXODRIFT: Carrier Command

> Pilot the flagship. Command the fleet. Survive the deep strike.

![EXODRIFT carrier combat](web/assets/flight-preview.png)

`EXODRIFT: Carrier Command` is a single-player Godot 4 action-RTS for PC and Web. Directly pilot a heavy carrier, launch fighters and drones from mirrored side bays, and command persistent wings and capital escorts through a live three-dimensional tactical map. Time never pauses when command mode opens.

[Play the browser build](web/play/) · [Read the game bible](GAME_BIBLE.md) · [View the showcase site](web/)

The public title is provisional. `Project Sidebay` remains the internal codename used by some runtime classes and stable IDs.

## Current playable

- Carrier-centered third-person flight with assisted movement, seven-round flak curtains, four-missile long-range salvos, visible automated defense, and shields → armor → hull damage.
- A unified command-interface style groups carrier telemetry, air-group state, fire control, target data, radar, notifications, and controls into compact scalable panels across combat and campaign screens.
- A four-craft Raptor interceptor wing, three Watcher scout drones, and the commandable missile frigate `ISS Resolute`.
- Visible launch, engagement, recall, side-bay recovery, servicing, relaunch, and armored bay-retraction cycles with a closed-bay jump interlock.
- Layered deep-space scenery and a pulsing tactical radar plotting uncertain and identified sensor contacts.
- Modular textured capital-ship silhouettes, low-node fighter geometry, pooled combat flashes, missile exhaust, shield/hull feedback, and saved Low/Medium/High graphics profiles shared by Windows and Web.
- Strict sensor fog with uncertain contacts, active emissions, identification requirements, stale tracks, and command-link loss.
- Live 3D fleet command with selection, move, attack, intercept, escort, hold, recall, withdraw, stances, formations, and queued orders.
- An 18-node, three-sector run map with fuel, supplies, intel, forecasts, combat transitions, and manual versioned saves.
- Persistent carrier condition, wing losses and ammunition, escort survival, fleet servicing, and five authored module slots.
- Three fixed escort identities with requisition acquisition, sector-gated suppliers, reserve selection, unique permanent losses, and distinct tactical profiles.
- Three carrier-frame sidegrades and three refittable air-group complements with fixed 4/3, 5/2, and 3/4 interceptor/scout allocations.
- Persistent salvage stock with fixed supply, fuel, and requisition conversions plus three route logistics postures with explicit travel tradeoffs.
- Six objective types: command strike, interception, extraction, defense, escort, and capture.
- Withdrawal pursuit, jump-range stragglers, recoverable escape pods, and an after-action rescue/salvage/departure choice with persistent consequences.
- A centered main menu over a continuously simulated carrier battle, with New Operation, Continue, persistent settings, credits, and return-to-title navigation.
- A six-step first-operation orientation that teaches helm translation, active sensors, flight operations, the live tactical map, and intent-level orders without pausing combat.
- Three sector-specific hostile fleets—Acheron, Vesper, and Crucible—with different capital roles, fighter complements, opening formations, weapons, pursuit identities, and battlefield palettes.
- Three deterministic layouts per sector plus bespoke command battles: Acheron command-net screening, Vesper shield-break pincers, and the Crucible's anchored multi-phase strategic core.
- Textured, layered capital ships with faction hull plating, tapered armor, command towers, bridge windows, sensor masts, visible turrets, housed engines, and navy/raider/alien silhouette language.
- Named escorts and fighter classes use role-specific geometry, faction projectile palettes, engine trails, progressive breach indicators, damage sparks, and brighter fleet lighting for at-a-glance combat identification.
- Twelve persistent named officers across six departments, with assignments, tactical effects, traits, bonds, injuries, rescue, recovery, succession, and permanent death.
- Supply-funded treatment, earned promotions, requisition recruitment, rare officer unlocks, and ten deterministic operational events with authored radio and relationship outcomes.
- Adaptive three-sector procedural music, combat-pressure layering, faction-aware effects, and encounter-phase radio stingers with independent Master/Music/SFX controls.
- Atomic autosaves with a recoverable backup, corrupt-save fallback, New Operation confirmation, persistent keyboard remapping, and an in-game playtest debrief that exports structured telemetry and tester prompts.

## Run locally

Open the project in Godot 4 and press **F5**, or run:

```powershell
godot --path .
```

The packaged Windows build is generated at `build/ProjectSidebay.exe`. The GitHub Pages artifact lives in `web/`; the playable Godot export is nested under `web/play/` so the repository can present a full showcase page first.

## Controls

All listed keyboard actions can be remapped from **Settings → Remap Controls**.

- `W/S`, `A/D`, `Space/C`: fore/aft, lateral, and vertical thrust
- `Shift`, `Ctrl`: boost and brake
- Mouse: move the carrier-centered camera and flak director without rotating the hull; wheel: zoom; left mouse: directed flak barrage; right mouse: identified-target missile salvo
- `P`: active sensor ping
- `Z`, `X`: launch/recall interceptor and scout wings
- `Tab`: live tactical map
- Tactical map: `1–4` groups, left-click select, right-click context move/attack, `I` intercept, `E` escort carrier, Shift queue, `Q` stance, `F` formation, `R` recall, `H` hold, `X` withdraw, middle-drag orbit, wheel zoom
- `V`: begin jump preparation and wing recall; press again to emergency-seal the bays and risk stragglers
- `Esc`: pause/settings; `Enter`: restart or return to the campaign

## Tests and exports

```powershell
godot --headless --path . --script tests/run_tests.gd
godot --headless --path . --script tests/run_integration.gd
godot --headless --path . --script tests/run_campaign_tests.gd
godot --headless --path . --script tests/run_m15_encounter_tests.gd
godot --headless --path . --script tests/run_playtest_tests.gd
godot --headless --path . --script tests/run_save_settings_tests.gd
godot --headless --path . --script tests/run_ship_readability_tests.gd
godot --headless --path . --script tests/run_audio_narrative_tests.gd
godot --headless --path . --script tests/profile_combat_stress.gd
godot --path . --script tests/profile_menu.gd
godot --headless --path . --export-release "Web"
godot --headless --path . --export-release "Windows Desktop"
```

The M15 automated 600-frame combat gate measures 144.9 FPS at 1920×1080 with p95 7.25 ms and p99 7.32 ms. The sustained all-wings/flak/missile/point-defense stress gate measures 144.9 FPS with p95 9.78 ms and p99 10.57 ms on the development RTX 3060. See [GAME_BIBLE.md](GAME_BIBLE.md) for acceptance evidence and hardware-target caveats.

## GitHub Pages

The checked-in workflow at `.github/workflows/deploy-pages.yml` publishes `web/` when the site changes. In the repository’s **Settings → Pages**, select **GitHub Actions** as the source, then run the workflow or push to `main`.

All currently defined milestones M1–M15 are implemented. M15 adds authored encounter layouts and boss phases, playtest reporting, stronger ship readability, release-safe saves/settings, adaptive audio, and a broader campaign narrative pool. External first-time-player sessions remain the evidence-gathering step for subsequent balance tuning.
