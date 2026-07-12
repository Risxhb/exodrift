# EXODRIFT: Carrier Command

> Pilot the flagship. Command the fleet. Survive the deep strike.

![EXODRIFT carrier combat](web/assets/flight-preview.png)

`EXODRIFT: Carrier Command` is a single-player Godot 4 action-RTS for PC and Web. Directly pilot a heavy carrier, launch fighters and drones from mirrored side bays, and command persistent wings and capital escorts through a live three-dimensional tactical map. Time never pauses when command mode opens.

[Play the browser build](web/play/) · [Read the game bible](GAME_BIBLE.md) · [View the showcase site](web/)

The public title is provisional. `Project Sidebay` remains the internal codename used by some runtime classes and stable IDs.

## Current playable

- Carrier-centered third-person flight with assisted movement, seven-round flak curtains, four-missile long-range salvos, visible automated defense, and shields → armor → hull damage.
- A four-craft Raptor interceptor wing, three Watcher scout drones, and the commandable missile frigate `ISS Resolute`.
- Visible launch, engagement, recall, side-bay recovery, servicing, relaunch, and armored bay-retraction cycles with a closed-bay jump interlock.
- Layered deep-space scenery and a pulsing tactical radar plotting uncertain and identified sensor contacts.
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
- Twelve persistent named officers across six departments, with assignments, tactical effects, traits, bonds, injuries, rescue, recovery, succession, and permanent death.
- Supply-funded treatment, earned promotions, requisition recruitment, rare officer unlocks, and deterministic operational events with authored radio and relationship outcomes.

## Run locally

Open the project in Godot 4 and press **F5**, or run:

```powershell
godot --path .
```

The packaged Windows build is generated at `build/ProjectSidebay.exe`. The GitHub Pages artifact lives in `web/`; the playable Godot export is nested under `web/play/` so the repository can present a full showcase page first.

## Controls

- `W/S`, `A/D`, `Space/C`: fore/aft, lateral, and vertical thrust
- `Shift`, `Ctrl`: boost and brake
- Mouse: steer; wheel: zoom carrier-centered camera; middle-drag: independently orbit combat camera; left mouse: flak barrage; right mouse: identified-target missile salvo
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
godot --path . --script tests/profile_menu.gd
godot --headless --path . --export-release "Web"
godot --headless --path . --export-release "Windows Desktop"
```

The last windowed development-PC gates measured 157.6 FPS for the animated menu and 165 FPS for the complete combat force at 1920×1080. The post-expansion automated 600-frame combat gate measures 145 FPS. See [GAME_BIBLE.md](GAME_BIBLE.md) for milestone acceptance evidence and current design truth.

## GitHub Pages

The checked-in workflow at `.github/workflows/deploy-pages.yml` publishes `web/` when the site changes. In the repository’s **Settings → Pages**, select **GitHub Actions** as the source, then run the workflow or push to `main`.

All currently defined milestones M1–M13 are implemented. M13 completes authored fleet acquisition, carrier and air-group sidegrades, salvage allocation, and route-level operational logistics.
