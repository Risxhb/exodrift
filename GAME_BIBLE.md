# EXODRIFT: Carrier Command — Game Bible

**Document status:** Canonical source of truth  
**Public title:** EXODRIFT: Carrier Command `[PROVISIONAL]`  
**Internal codename:** Project Sidebay  
**Last updated:** 2026-07-12
**Target:** Godot 4, Windows PC and Web, mouse and keyboard, single-player

This file owns the current design, technical constraints, milestone gates, and decision history. Foundational decisions are marked `[LOCKED]`. Values, names, content counts, and experimental behavior remain `[PROVISIONAL]` until playtesting validates them. When a decision changes, update the relevant section first and add a dated entry to the decision log.

## 1. Vision and player promise

EXODRIFT: Carrier Command is a single-player action-RTS in which the player directly pilots a heavy carrier while commanding fighter wings, drones, and capital escorts through a live three-dimensional tactical map. The carrier is simultaneously the player's avatar, mobile base, primary command node, and run-ending vulnerability.

The defining experience is moving continuously between two forms of command:

1. Fly and fight from a third-person chase view using flak cannons, lock-on missiles, movement, and defensive positioning.
2. Open a live holographic map without pausing time, inspect imperfect sensor information, and issue intent-level orders to fleet groups.
3. Launch craft through visible port and starboard bays, rotate damaged or depleted wings home, protect recovery lanes, and relaunch serviced squadrons.

### Design pillars `[LOCKED]`

- **The commander remains in the battle.** Opening the tactical map never removes risk or stops time.
- **The carrier must look and behave like a carrier.** Mirrored side launch galleries, approach lanes, recovery, turnaround, ammunition, and endurance are gameplay systems rather than decoration.
- **Command intent, not individual flight paths.** Squadrons and escorts accept orders, formations, and stances; role AI performs execution.
- **Information is a weapon.** Sensor uncertainty, active emissions, stale tracks, and communication loss materially affect decisions.
- **Loss creates stories.** Full runs eventually preserve personnel history, injuries, rescues, relationships, and death across operations.
- **Readable simulation.** Projectiles, travel time, firing arcs, interception, and layered damage are physical, while the HUD clearly explains threats and outcomes.

## 2. Moment-to-moment combat

### Carrier control `[LOCKED]`

- Third-person carrier control uses one visible-pointer command view. Double-clicking empty space sets a full-cruise heading, middle-drag orbits the chase camera, and the wheel zooms; weapon use never requires a camera/control-mode switch. `[LOCKED]`
- Heavy inertia and slow rotation communicate scale; braking assist and practical lateral/vertical thrust prevent sluggish controls from becoming frustrating.
- Keyboard thrust: fore/aft, lateral, vertical, boost, and brake.
- The vertical combat volume is capped at ±1,400 meters on the Godot Y axis for every capital ship and craft; outward velocity is canceled at the boundary. `[PROVISIONAL]`
- The carrier keeps its current velocity or assigned autopilot destination while the tactical map is open.
- Flak is a carrier-relative area-denial screen. `1` opens a temporary placement view, the pointer places a visible 250 m airburst volume 1.0–3.2 km from the carrier in 250 m steps, and distributed batteries sustain staggered seven-round curtains into that volume until ceased or relocated. The flak-director upgrade extends the placement maximum to 4 km.
- `2` fires the four-round identified-lock missile salvo. `3` fires one interceptable nuclear torpedo per battle; it arms after 1.2 km and applies a 650 m falloff blast to friendly and hostile ships.
- Missiles lock identified targets and launch four-weapon salvos for deliberate anti-ship attacks out to 8.5 kilometers.
- Automated close defense throws visible three-round flak curtains at interceptable projectiles and remains active while the tactical map is open.
- Durability resolves through shields, then armor, then hull. Hull reaching zero destroys the ship.

### Battle rhythm `[LOCKED]`

Battles remain continuous real time and use cinematic distances. A normal engagement moves through reconnaissance, passive contact, active emissions or scouting, long-range missile exchange and interception, fighter commitment, visible close combat, recovery, and either destruction or withdrawal. There is no time acceleration in the intended game.

Major ships use moderate, recoverable lethality: focused fire becomes dangerous within tens of seconds, leaving time for screening, retreat, recovery, and counter-orders.

### Fleet command `[LOCKED]`

The tactical map is a simplified 3D holographic view that can orbit and zoom. It supports:

- persistent group selection and numeric control groups;
- context-sensitive move, attack, intercept, escort, and interact orders;
- explicit hold, recall, withdraw, stance, and formation commands;
- Shift-queued orders and waypoints;
- aggressive, balanced, defensive, and evade/return stances;
- formation templates with configurable spacing and a leader;
- visible order paths, command-link state, acknowledgements, and rejection reasons.

Role AI executes maneuvers. The player does not steer individual allied craft.

### Sensors and communications `[LOCKED]`

- Passive sensors produce estimated tracks with confidence, classification, position/velocity error, and uncertainty volume.
- Active ping resolves nearby tracks quickly but reveals the emitter.
- Unobserved tracks become stale, drift according to estimated velocity, lose confidence, and expand their uncertainty.
- Targets require sufficient identification before lock-on weapons and attack orders can use them.
- Command links can be linked, delayed, or disconnected.
- Groups outside the command network retain their last confirmed order and local stance until communication returns.
- Advanced deception, spoofing, relays, and detailed jamming are post-first-playable systems.

## 3. Carrier operations and fleet composition

### Carrier `[LOCKED]`

The starting human carrier has a long industrial armored hull, obvious bridge and engine masses, flak emplacements, missile cells, and mirrored port/starboard flight galleries. Each gallery visibly retracts toward the hull while split armor doors seal the opening. Doors, approach lighting, traffic direction, launch rails, and recovery lanes clearly communicate deck state. Flight operations require fully extended bays; jump execution requires both bays fully retracted and sealed.

Carrier builds use authored module slots for weapons, defenses, sensors, support systems, and hangar complements. The core hull and side-bay silhouette remain recognizable. Equipment is composed of authored sidegrades with fixed tactical identities; randomized affix loot is excluded.

### Wings and escorts `[LOCKED]`

- Wings are persistent squadrons, launched and recalled manually by squadron.
- Emergency return triggers when craft are critically damaged or below configured ammunition/endurance thresholds.
- Craft proceed through queued, launching, deployed, returning, approach, docking, servicing, and ready states.
- Escorts include corvettes, frigates, and cruisers. Carrier command rating limits escort capacity; physical bay and deck-support capacity limit wings.
- The intended late-run scale is approximately four to eight capital ships and twenty to forty launched craft.

## 4. Full-game run structure

The campaign layer is out of scope until the first playable passes every acceptance gate, but its constraints are canonical so combat architecture remains compatible.

### Operation loop `[LOCKED]`

- A successful run lasts approximately two to three hours and supports manual saves.
- One run is a deep-strike campaign through three branching sectors: outer line, contested interior, and command zone.
- Nearby nodes reveal type and threat estimates. Intel reveals compositions, rewards, hazards, or farther routes.
- Objectives include elimination, defense, interception, escort, capture, salvage, and withdrawal.
- Withdrawal requires reaching an extraction condition while exposed; stragglers, escape pods, fuel, and pursuit create costs.
- Supplies repair and rearm; fuel constrains routing; intel controls information. Ships arrive through limited requisition and salvage opportunities.
- Upgrade nodes provide small context-driven offers based on salvage, suppliers, faction access, and intel.
- A run ends when the carrier is destroyed or the strategic command target is defeated.

### Persistent progression `[LOCKED]`

- Meta-progression unlocks carriers, weapons, craft, officers, and starting options as sidegrades, never raw permanent stat inflation.
- One human navy is initially playable. Rival humans and aliens provide opposition with distinct doctrines and silhouettes.
- Six personnel departments exist: Command, Flight, Gunnery, Engineering, Sensors, and Medical.
- Department rosters contain named personnel with skills, traits, bonds, injuries, assignments, and operational effects.
- Assignments, treatment, promotion, and relationship decisions occur between encounters; combat exposes only urgent consequences.
- Escape capacity, rescue time, injury, and battlefield recovery determine survival after ship loss. Persistent personnel can die permanently.
- Reputation or requisition fills a recruitment pool between operations; rare authored officers are unlockable.

## 5. Presentation

- Industrial military science fiction with functional hulls, armor plating, exposed bays, readable weapon mounts, and restrained navy colors. `[LOCKED]`
- One human navy player roster with human and alien opponents. `[LOCKED]`
- Crisp military HUD styled as carrier combat systems; readability takes priority over fully diegetic interfaces. `[LOCKED]`
- Compressed ship silhouettes but cinematic engagement distance and long-range sensor/missile phases. `[LOCKED]`
- Orchestral-electronic military score using command-room tension, synth pulses, and layered orchestral escalation. `[LOCKED]`
- Light emergent narrative through officers, radio barks, faction events, and operational consequences. `[LOCKED]`
- The public-facing presentation uses a premium fleet-archive style: luminous military UI, dramatic ship dossiers, banner-scale battle imagery, and rarity-like role frames without implying randomized purchases or gacha monetization. `[PROVISIONAL]`
- The in-game presentation shell uses a centered command menu over a continuously simulated carrier battle, with broadside fleet choreography, projectile exchanges, fighters, explosions, live telemetry, and restrained military framing. `[PROVISIONAL]`

## 6. First playable specification

The first playable is one greybox locate-and-destroy battle. Campaign, economy, crew UI, permanent progression, controller support, multiplayer, advanced electronic deception, time acceleration, randomized loot, and final-quality art are excluded.

### Friendly force `[LOCKED]`

- One player carrier with mirrored side bays, placed sustained flak, lock-on missiles, one nuclear torpedo, automated point defense, layered durability, passive sensors, and active ping.
- Port bay: one four-craft interceptor squadron.
- Starboard bay: one three-craft scout-drone squadron.
- One commandable missile frigate escort.

### Hostile force `[LOCKED]`

- One hostile command frigate whose destruction wins the battle.
- One hostile corvette screen.
- One hostile fighter squadron.
- Hostiles begin as uncertain contacts and cannot receive lock-on attacks until identified.

### Required loop `[LOCKED]`

1. Pilot the carrier and observe uncertain passive contacts.
2. Resolve contacts using the scout wing, closing distance, or an active ping.
3. Launch both wings visibly from their assigned side bays.
4. Command both wings and the escort through the live tactical map while the carrier continues moving and defending itself.
5. Expend wing ammunition/endurance, recall the groups, recover them through the correct bays, service them, and relaunch without duplication.
6. Destroy the identified command frigate to win, or lose the carrier and the battle.

### Provisional greybox values

| Value | Initial target |
|---|---:|
| Carrier length | 120 m |
| Frigate length | 65 m |
| Fighter length | 8 m |
| Passive sensor range | 8 km |
| Active ping range | 12 km |
| Command link range | 7 km |
| Flak effective range | 3.2 km base / 4 km upgraded |
| Missile range | 5 km |
| Wing service time | 6 seconds |
| Target frame rate | 60 FPS at 1920x1080 on the development PC |

## 7. Technical architecture

### Platform constraints `[LOCKED]`

- Godot 4 using typed GDScript. The greybox uses the GL Compatibility renderer for broad development-machine support; Forward+ remains a post-greybox visual evaluation. `[PROVISIONAL]`
- Single-player Windows PC and mouse/keyboard first. A single-threaded Web export is maintained as a secondary build for GitHub Pages. `[PROVISIONAL]`
- Physics and combat continue while the tactical map is displayed.
- Gameplay definitions are data-driven `Resource` classes; runtime state is not stored in scene paths.
- Every persistent or commandable object receives a stable entity ID.

### Data resources

- `ShipDefinition`: identity, role, dimensions, movement, signature, sensor, command, durability, and weapon definitions.
- `SquadronDefinition`: role, craft count, endurance, ammunition, launch/recovery timing, stance defaults, and craft definition.
- `WeaponDefinition`: weapon role, range, cadence, damage, velocity, lock requirement, tracking, and interception behavior.
- `ModuleDefinition`: slot type, capability tags, and authored modifiers.
- `DamageLayerDefinition`: maximum shields, armor, hull, shield regeneration, and armor mitigation.

### Runtime contracts

- `FleetOrder`: order type, target entity ID or 3D position, issue time, queue state, stance, and command-link requirement.
- `SensorContact`: contact ID, classification, estimated position/velocity, confidence, uncertainty radius, identification state, and last update.
- `CommandLinkState`: linked, delayed, or disconnected, including the last confirmed order.
- `BayOperation`: queued, launching, deployed, returning, approach, docking, repairing, refueling, rearming, or ready; the former aggregate servicing state remains migration-compatible.
- `CarrierOperationsState`: power, subsystem condition, hazards, damage-control teams, crew, stores, deck priorities, selected wing packages, battle incidents, and persistent reporting.
- `WingLoadoutDefinition`: data-driven package ammunition and combat/sensor/rescue behavior for one interceptor or scout role.

## 8. Milestones and acceptance gates

**Implementation status (2026-07-13):** M1–M19 are implemented. Twenty functional, integration, campaign, carrier-operations, onboarding, presentation, and regression suites pass. At 2560×1440, the normal gate measures 145.0 effective FPS with p95 7.50 ms/p99 7.72 ms; the carrier-incident/all-wings/ordnance stress gate measures 145.0 effective FPS with p95 10.14 ms/p99 10.60 ms and bounded nodes/VFX, and the full-runtime-model menu measures 144.9 effective FPS on the development RTX 3060 using GL Compatibility. The mainstream GTX 1060/1650-class 1080p60 target remains a reference-hardware acceptance target rather than a claim measured on this machine.

### M1 — Canonical bible and Godot foundation `[IMPLEMENTED]`

- Bible, project skeleton, input map, data contracts, headless tests, scale guide, and baseline battlefield exist.
- Project boots without script or resource errors.

### M2 — Carrier flight and combat `[IMPLEMENTED]`

- Chase camera, assisted movement, braking, flak, missile lock, projectile interception, layered damage, HUD, and destruction work.
- Carrier can be controlled for ten minutes without camera instability or accumulating roll error.

### M3 — Side bays and squadrons `[IMPLEMENTED]`

- Both galleries visibly launch and recover their assigned wings.
- Wings consume resources, emergency-return, service, and relaunch without collision, loss of identity, or duplicate craft.

### M4 — Fleet command `[IMPLEMENTED]`

- Live 3D map selects groups, issues and queues all required orders, changes stance/formation, and preserves carrier motion/autodefense.
- Commands show paths, link state, acknowledgements, and valid rejection feedback.

### M5 — Sensors, communications, and AI `[IMPLEMENTED]`

- Passive uncertainty, active ping, stale tracks, identification, link state, role AI, and disconnected doctrine work.
- The complete hostile force can locate, engage, screen, and destroy the carrier.

### M6 — Integrated first playable `[IMPLEMENTED]`

- Locate-and-destroy mission, win/loss, restart, pause/settings, placeholder audio, and readable feedback work.
- The packaged Windows build holds 60 FPS at 1080p on the development PC with the complete force.
- Campaign, economy, crew, or permanent progression may begin only after every first-playable automated and manual acceptance test passes.

### M7 — Run-layer foundation and browser distribution `[IMPLEMENTED]`

- A deterministic 18-node graph spans the outer line, contested interior, and command zone with two opening routes, branching midpoints, sector bosses, and a final strategic-command node.
- Run state owns stable node IDs, seed, supplies, fuel, intel, completed/revealed nodes, battles won, and completion/failure state.
- Reachable nodes spend the active logistics posture's quoted fuel and supply cost; salvage, repair-support, intel, combat, and boss nodes resolve distinct rewards. Intel reveals deeper forecasts.
- Combat nodes instantiate the existing battle executor, scale hostile strength by threat, and return victory/defeat to the campaign map.
- Manual versioned JSON save/load works through `user://`, including persistent browser storage.
- Windows and single-threaded Web exports are generated. The `web/` artifact and GitHub Pages Actions workflow are browser-tested through campaign and combat with no console errors.

### M8 — Fleet persistence, buildcraft, and public showcase `[IMPLEMENTED]`

- Carrier shield/armor/hull condition, surviving wing craft, wing ammunition, and escort survival persist between campaign battles and through versioned manual saves.
- The sector map exposes a fleet configuration screen with quoted supply costs for full repair, rearm, replacement craft, and escort requisition.
- Five authored module slots—weapon, defense, sensor, support, and hangar—apply deterministic tactical modifiers. Victories unlock sidegrades in a fixed catalog; randomized affixes remain excluded.
- The public title is `EXODRIFT: Carrier Command`; `Project Sidebay` remains the internal codename.
- GitHub Pages serves a responsive fleet-showcase landing page at the root and launches the playable Web build from `/play/`. The site uses current build captures and clearly identifies development footage.

### M9 — Objectives, extraction, and partial victory `[IMPLEMENTED]`

- Campaign combat nodes select authored command-strike, interception, extraction, defense, escort, and capture objectives across the three sectors.
- Defense protects the Longwatch relay for a timed hold, escort moves the Atlas convoy to a marked jump corridor, and capture requires uncontested friendly control of a visible zone. Losing a protected objective records failure but preserves the task force and route.
- Interception completes by destroying the corvette and hostile fighter screen; extraction opens a visible withdrawal beacon after a hold period.
- Emergency withdrawal can be requested with `V` in any battle. The first command recalls wings and begins bay retraction once craft are aboard; the jump corridor cannot resolve until both bays are sealed. A second `V` authorizes an emergency seal that can abandon deployed craft as stragglers. A pursuit corvette enters during the exposed retraction window. The route advances with one-quarter supplies, no intel or module, and a persistent withdrawal count rather than a battle victory.
- Destroyed friendly craft and protected ships produce recoverable escape pods. Nearby pods are rescued during battle; unrescued pods and withdrawal stragglers are itemized in the after-action report.
- Every battle ends with a consequential choice: spend one fuel on a rescue operation, sweep wreckage into unallocated salvage stock, or depart immediately. Recovered craft, escort status, rescued/lost personnel, salvage, objective successes, and objective failures persist in version-9 manual saves.
- Direct combat and tactical-map cameras both support wheel zoom. Identified locks show a screen-edge direction indicator plus an EVE-style compact ship silhouette, range, confidence, and live shield/armor/hull bars.

### M10 — Presentation shell and animated main menu `[IMPLEMENTED]`

- The application opens on a centered EXODRIFT command menu over a continuously simulated 3D battle with the Sidebay carrier, friendly and hostile capital ships, fighter formations, projectiles, explosions, starfield, and moving camera.
- Begin New Operation transitions cleanly into a fresh campaign. Continue restores either the in-memory operation or the versioned manual save; the sector map can return to title without discarding its in-memory state.
- Settings persist independent Master/Music/SFX volume, fullscreen, reduced combat flashes, graphics quality, and remappable command keys through local configuration. New Operation requires confirmation when a checkpoint exists; Credits and desktop quit navigation are functional, while browser builds omit the desktop-only quit action.
- Automated presentation-shell checks cover menu-first startup, live background motion, settings behavior, New Operation, Continue, and title/campaign visibility transitions. Visual capture is reviewed at 1280×720.
- The isolated menu simulation averages 157.6 FPS at 1920×1080 on the development PC; the complete combat force remains at 165 FPS in the same validation run.

### M11 — Personnel and department command `[IMPLEMENTED]`

- Twelve authored officers form the initial Command, Flight, Gunnery, Engineering, Sensors, and Medical rosters. Stable personnel IDs, ranks, roles, skill ratings, traits, bonds, mission counts, status, injuries, and department assignments persist in versioned saves; older saves receive the canonical roster during migration.
- The sector map opens a Personnel Command screen showing both members, availability, assignment, and exact department effect. Available leads can be cycled between encounters; injury or death triggers deterministic succession.
- Assigned Command, Flight, Gunnery, Engineering, and Sensors leads modify command range, servicing time, carrier weapon damage, carrier hull, and sensor range. Medical skill reduces injuries sustained during rescue operations.
- Escape-pod source IDs map endangered craft and ships to appropriate named personnel. The after-action report identifies recovered and adrift officers before the rescue/salvage/departure decision.
- Rescued officers suffer persistent injuries and recover across completed nodes. Abandoned officers die permanently; bonded survivors gain a Grieving trait that reduces effective skill.
- Direct combat uses independent mouse free-look with a camera/cursor-directed flak solution; the hull retains its helm attitude, and every combat ship is held inside the ±1,400-meter vertical battlespace.

### M12 — Personnel progression and operational events `[IMPLEMENTED]`

- Requisition is a persistent run resource earned from salvage and full victories. The Personnel screen exposes an authored recruitment pool, quotes exact requisition costs, recruits officers into their matching department, and marks rare candidates explicitly.
- Ten deterministic, non-repeating operational events appear after noncombat nodes. Each presents authored narrative, a radio bark, two explicit outcomes, resource requirements, and relationship, trait, recovery, intel, fuel, requisition, or recruitment consequences.
- The event set now also covers a ghost convoy, reactor resonance, an Acheron deserter, a black-box memorial, a crew confidence vote, and the fleet's last prewar torpedo. Event decisions and unresolved pending events persist in version-6 saves.
- Injured officers can receive immediate supply-funded treatment with Medical-department cost reduction. Eligible active officers promote after three completed nodes, spending supplies to gain a persistent rank, skill point, promotion count, and Proven trait.
- Relationship decisions create new mutual bonds or traits. Recruitment expands department rosters without replacing existing personnel; assignment cycling remains deterministic among available officers.
- Version-5 saves migrate into the authored recruitment pool with one starting requisition. No randomized recruits, affixes, or permanent meta-stat purchases are introduced.

### M13 — Fleet acquisition and operational economy `[IMPLEMENTED]`

- Extend requisition into authored escort acquisition, replacement hull choices, hangar-complement changes, and limited suppliers while preserving fixed tactical identities.
- Add salvage allocation and route-level logistics decisions without randomized affix loot or grind-based permanent power.
- **Implemented slice (2026-07-12):** The starting ISS Resolute, fast ISS Harrier screen corvette, and armored ISS Bulwark line frigate form a fixed authored escort catalog. Requisition purchases unique hulls from sector-gated suppliers; acquired, selected, and permanently lost escort identities persist in version-7 saves. The active hull's dimensions, mobility, durability, weapon, interception capability, name, and stable ID reach tactical combat. Supplies service the carrier and air group but no longer recreate a destroyed escort.
- **Implemented slice (2026-07-12):** CVN Sidebay, CVN Vanguard, and CVN Citadel form a fixed carrier-frame catalog with balanced, assault, and armored-command identities. Balanced, Raptor Strike, and Watcher Recon air groups provide authored 4/3, 5/2, and 3/4 interceptor/scout allocations with distinct ammunition, endurance, and service profiles. Requisition unlocks sector-gated frames and complements; supply-funded deck refits quote their exact repair/rearm cost. Selections persist in version-8 saves and drive tactical identity, movement, durability, weapon output, command/sensor reach, craft counts, stores, endurance, and servicing.
- **Implemented slice (2026-07-12):** Battle sweeps and salvage nodes recover persistent allocation stock. Fixed recipes convert stock into supplies, fuel, or requisition. Balanced Stores, Lean Burn, and Recovery Rig postures expose exact route fuel/supply and salvage-yield tradeoffs; affordability, node cards, route execution, after-action projections, and version-9 persistence all use the selected posture. No randomized affixes, grind currency, or permanent stat power are introduced.

### M14 — Combat graphics and performance foundation `[IMPLEMENTED]`

- The carrier uses an original modular industrial hull with tapered bow armor, dorsal command mass, textured plating, readable flak mounts and missile cells, housed engine banks, retractable lit galleries, split bay doors, approach markers, and state feedback. Escorts, hostiles, and fighters use role/faction visual profiles without changing combat definitions.
- GL-compatible shared projectile meshes/materials, bounded reusable impact slots, missile exhaust, flak tracers, muzzle flashes, shield/hull impacts, optional debris, nebula cards, parallax dust, and tiered backdrop visibility replace per-shot mesh/material construction.
- A shared command-interface style provides consistent bordered panels, typography, focus/hover states, compact durability bars, and accent colors across the combat HUD, tactical map, campaign, fleet, personnel, logistics, event, and after-action screens. Combat information is grouped by telemetry, air group, fire control, target solution, radar, notifications, and control context.
- Saved Low, Medium, and High profiles apply immediately. Windows defaults to High and Web to Medium; cosmetic density, impact budget, trail length, debris, and backdrop layers never alter simulation damage or collision behavior.
- A maintained weak-reference combat registry replaces repeated scene-wide projectile/entity scans in projectile collision, point defense, sensors, and target resolution. Radar contact reconstruction runs at 10 Hz while pulse and sweep motion remain smooth.
- The 1920×1080 normal gate passes at 144.9 FPS with p95 7.20 ms/p99 7.29 ms. The sustained stress gate passes at 144.9 FPS with p95 9.72 ms/p99 10.02 ms, projectile-adjusted bounded post-warmup node growth, and zero dropped effects in the measured run.

### M15 — Ship-readiness completion `[IMPLEMENTED]`

- The first campaign battle provides a dismissible six-step orientation covering carrier translation, active-ping risk, wing launch, the live tactical map, and intent-level orders. Action cards require a readable dwell before credit and the active-ping lesson cannot be skipped by an earlier input.
- The three sectors field distinct Acheron, Vesper, and Crucible forces with authored command/screen roles, dimensions, movement, durability, weapon behavior, fighter complements, opening geometry, pursuit identity, lighting, dust, star, and nebula palettes. The standalone first playable retains the original Acheron force.
- Navy, raider, and alien-carapace SVG hull textures are paired with expanded low-node capital geometry: armor ribs, engineering blocks, command towers, bridge windows, sensor masts, weapon turrets, engine housings/nozzles, navy mission pods, and hostile blade fins. Combat definitions and collision volumes remain separate from presentation.
- Each sector has three deterministic encounter layouts with distinct geometry, interference, fortification, and reinforcement logic. Acheron's command net, Vesper's shield-break pincer, and Crucible's shield-anchor/core sequence provide bespoke multi-phase command battles, including the final strategic-command encounter.
- Named escorts, fighter classes, and hostile factions use distinct geometry, engine trails, projectile/impact palettes, progressive damage breaches, sparks, and brighter fleet lighting. The presentation remains GL Compatibility-safe and separate from collision geometry.
- Playtest telemetry records onboarding, command usage, battle timing, layouts, phases, outcomes, and first-time acceptance. A campaign debrief exports a structured report, tester notes, and six consistent interview prompts; external sessions remain the evidence-gathering input for later balance revisions.
- Checkpoints use atomic temp writes, preserve a recoverable backup, fall back after corrupt primary data, autosave at campaign transitions, and confirm destructive New Operation choices. Independent audio buses and persistent keyboard rebinding complete the release settings surface.
- A three-sector synthesized score layers combat pressure dynamically. Phase-aware radio stingers, faction-aware combat audio, and ten authored operational events replace the placeholder-audio/narrow-event-pool state.

### M16 — Helm and presentation refit `[IMPLEMENTED]`

- The title screen uses a compact bottom horizontal command row over a reframed seven-capital, twelve-fighter live engagement. Secondary panels remain centered and the browser build omits the desktop-only Quit action without leaving a gap.
- Intent-driven heading commands, persistent throttle, and removed lateral/vertical strafe inputs established the heavy-carrier helm foundation. M17 supersedes the temporary split-mode interaction with one visible-pointer command view.
- The stretched bitmap panorama was rejected during visual QA. A resolution-independent procedural sky dome, vector nebula veils, tiered stars/dust, and sector palettes now provide crisp space at native resolution without a hard horizon seam.
- The combat HUD uses compact asymmetric rails, clipped corners, a command/throttle readout, and a Web-safe placement cursor while preserving objective, telemetry, air-group, fire-control, target, radar, notification, and command information.
- Navy, Acheron, Vesper, and Crucible ships use dedicated surface atlases, material response, faction wear, recognition lighting, and additional modeled hull features within capital/fighter node budgets. Current build captures and the M16 milestone are reflected on the public landing page.
- Dedicated helm-control, main-menu-layout, ship-surface, and space/HUD-readability suites pass. The final normal/stress/menu gates measure 144.9 FPS (p95 7.29 ms/p99 7.35 ms), 144.9 FPS (p95 9.34 ms/p99 9.75 ms), and 165.0 effective FPS respectively on the development RTX 3060.

### M17 — Fleet authenticity and strategic ordnance `[IMPLEMENTED]`

- Direct combat uses one visible-pointer command view: double-click sets full-cruise heading, middle-drag orbits, wheel zooms, and `W/S`, `Ctrl`, and `Shift` operate persistent heavy-carrier throttle, stop, and boost. Acceleration is 14 m/s² times frame profile and turn response is 0.30 rad/s times frame profile.
- `1` opens a temporary camera move toward a visible carrier-relative flak volume. Left click confirms, right click or `Esc` cancels, `Shift+1` ceases, and brackets adjust a 1.0–3.2 km range in 250 m steps, or to 4 km with the flak director. Confirmed screens retain their local bearing as the carrier moves and turns and sustain staggered seven-round fire into a 250 m interception/airburst radius.
- `2` fires four guided missiles at an identified lock. `3` fires the battle's single 10 km nuclear torpedo, which arms after 1.2 km, can be intercepted, leaves a two-stage trail, and applies a 650 m falloff blast with friendly fire.
- Missile, nuclear, fighter, and carrier engine trails plus layered hull hits, ship detonations, shock rings, cores, and debris use the existing quality-scaled 80-slot pool. Reduced-flash behavior and zero-drop stress acceptance remain intact.
- Pressing `Z` or `X` during servicing queues the surviving wing to physically relaunch as soon as deck turnaround completes; the HUD exposes the queued state.
- The title battle instantiates the exact playable carrier plus current textured capital/fighter builders against the procedural sky, with 22 flak tracers, six arcing missile plumes, and four layered explosion rigs. The public fleet archive replaces seven CSS glyphs with 900×506 direct Godot renders of the actual Sidebay, Resolute, Raptor, Watcher, Acheron, Vesper, and Crucible models.
- Fourteen automated suites pass. Normal combat measures 144.9 FPS (p95 7.19 ms/p99 7.28 ms), sustained maximum ordnance measures 144.9 FPS (p95 8.83 ms/p99 9.37 ms, zero dropped effects), and the runtime-model menu measures 165.0 effective FPS on the development RTX 3060.

### M18 — Tactical interface and deep-space polish `[IMPLEMENTED]`

- Flak placement keeps the carrier centered and zooms aft to frame the hull and screen volume. The authored 125 m framing is signed zoom 0%; players can zoom in to +100% or out to -100% at 650 m.
- `1` places flak in direct combat or the tactical overlay. Tactical LMB confirms and RMB cancels without leaving the command map.
- Remappable `B` opens both hangar wings and deploys available air groups, or recalls both groups and retracts the galleries after recovery. `Z` and `X` remain granular wing controls.
- Carrier Telemetry, Air Group, Fire Control, Target Solution, and Tactical Overview are collapsible. Target Solution no longer contains a placeholder ship silhouette.
- The interactive overview lists contact name, range, closing speed, and identification state. Identified contacts can be manually locked and issued persistent Approach, Orbit, or Keep 2.5K carrier commands.
- Projected target graphics now use scalable corner brackets, envelope color, range/relative-velocity annotation, a motion-lead pip, and the existing off-screen direction indicator.
- Gameplay and title scenes use a GL-compatible infinite space shader with multi-scale stars, galactic structure, nebula regions, and dust lanes. Foreground star/nebula geometry remains quality-scaled for parallax.
- Capital hull cores, dorsal armor, and keels use tapered faceted geometry with brighter triplanar PBR surfaces and restrained rim response while retaining the existing texture atlases and node budgets.
- The `/exodrift/` showcase and `risxhb.github.io` home page use current runtime models in a premium, truthful fleet-collection presentation with accessible faction tabs.
- All fourteen automated suites pass. Normal combat measures 144.9 FPS (p95 7.40 ms/p99 7.59 ms), sustained maximum ordnance measures 144.9 FPS (p95 9.57 ms/p99 9.99 ms, zero dropped effects), and the runtime-model menu measures 144.9 effective FPS on the development RTX 3060.

### Combat presentation and tutorial upgrade `[IMPLEMENTED]`

- Sidebay's base flak envelope is 1.0–3.2 km in 250 m fuse steps, extended to 4 km by the flak director. Seven-round curtains now use a 250 m falloff volume and pooled WWII-inspired flashes, smoke clusters, fragments, and pressure rings while retaining interception, faction safety, and reduced-flash behavior.
- Carrier and menu propulsion use layered white-blue cores, cyan tapered exhaust, and outer ion glow. Plume length and opacity respond to propulsion demand with per-nozzle flicker.
- CVN Sidebay retains its 120 m gameplay envelope, bays, hardpoints, and statistics while presenting a tapered armored bow, overlapping ribbed plates, recessed waist, side hangar pods, aft engineering spine, paired nacelles, dark gunmetal plating, cyan registry marks, and restrained amber hazards.
- A seam-feathered 3840×1920 galaxy-arm panorama blends with the existing procedural sky in menu and combat, at reduced combat intensity for target and HUD legibility.
- Desktop output defaults to 2560×1440. Edge-anchored combat HUD groups render at 75% visual scale while preserving the logical canvas, all information, and collapsible panels.
- Right-clicking an identified contact marker or Tactical Overview row with the carrier selected opens one menu for lock, 500 m approach, 500 m/5 km/10 km/25 km orbit, the same keep-at-distance values, and clear relative navigation. Empty-space moves and wing/escort orders retain their established behavior.
- The title menu includes an eight-lesson standalone communications tutorial with Commander Mara Voss. It resolves live key bindings and uses three consistent poses, four eye/mouth facial states per pose, 36-character-per-second text, punctuation pauses, speaking-only mouth animation, and randomized blinks.

### M19 — Integrated Carrier Operations `[IMPLEMENTED]`

- Version-10 run state persists eight subsystem conditions, surviving generic crew, finite carrier/aviation stores, damage-control spares, and selected wing packages while resetting power, hazards, and team assignments safely at battle start. Versions 1–9 migrate to the canonical full state.
- Eight reactor points feed propulsion, defense, weapons, and flight operations through four presets or manual allocation. Reactor damage reduces the budget and deterministically sheds excess allocation; subsystem condition and emergency damage-control functionality independently modify the corresponding systems.
- Hull penetrations deterministically map impact location and weapon role into reactor, propulsion, shield grid, fire control, sensors, command/CIC, or either deck. Two four-second-transit teams contain fires/breaches before spending persistent spares on repairs; uncontained hazards cause deterministic crew casualties.
- The carrier consumes 2,100 flak rounds, 24 guided missiles, one nuclear torpedo, one selected-air-group reload, and 14 refuel units. Siege cells, expanded magazines, fleet repair drones, and rapid turnaround decks modify their exact authored systems.
- Both decks run explicit repair, refuel, and rearm queues with Rapid Turn, Balanced, or Repair First priority, partial service, and disabled-deck emergency recovery. Raptor CAP/Multirole/Strike and Watcher Recon/Screen/Rescue are data-driven packages changeable only while aboard before rearming.
- Severe uncontained subsystem incidents trap the assigned department lead behind a ten-second rescue countdown. Rescue or death produces immediate severity-three injury, succession, bond, telemetry, and after-action consequences; unresolved battle-end incidents receive a deterministic emergency recovery and cannot disappear.
- Remappable `C` opens a responsive, non-pausing Carrier Operations console from direct or tactical view. A compact collapsible HUD summary shows the live binding, power preset, warnings, and officer countdown. Mara Voss's tutorial now has nine lessons and first-operation onboarding has seven steps.
- Fleet logistics separates repair, rearm, air-group restoration, and full service with exact supply breakdowns. Repair nodes restore at most 24 missing generic crew; routine fleet service never replaces casualties.

## 9. Test matrix

Automated tests cover damage-layer transitions, missile-lock eligibility, FIFO order queues, sensor confidence decay and track drift, command-link transitions, and every valid bay-state transition.

Campaign and integration tests also cover all six objective assignments, defense/escort/capture success conditions, withdrawal pursuit, jump-range stragglers, escape-pod accounting, after-action rescue and salvage choices, persistent consequences, and save migration through version 10.

M11 tests cover camera orbit independence, vertical bounds, authored roster construction, all department cards, assignment changes, tactical skill modifiers, named risk previews, injuries, medical mitigation, recovery, succession, bonds, permanent death, and version-4 roster migration.

M12 tests cover treatment quotes and recovery, promotion eligibility and costs, requisition recruitment, rare-candidate unlocks, mutual relationship bonds, authored event selection and outcomes, unaffordable-choice gating, pending-event persistence, event UI flow, and version-5 recruitment migration.

M13 tests cover escort, carrier-yard, and flight-group supplier sector gates; exact requisition, refit, route, and salvage-conversion costs; authored acquisition and selection; unique permanent escort loss; version-9 persistence and older-save migration; dynamic 4/3, 5/2, and 3/4 hangar capacities; logistics and fleet-screen interaction; adjusted route affordability and salvage yields; and propagation of every selected tactical profile into combat.

M14 tests cover ship visual profiles, immediate quality switching, backdrop tier visibility, VFX budgets, original texture resources, shared projectile mesh/material identity, combat-registry population, radar animation, normal p95/p99 frame time, sustained legal maximum fire, all deployed wings, hostile missile pressure, node stability, effect drops, and clean ObjectDB shutdown.

M15 tests cover deterministic onboarding progression and minimum card dwell, active-ping timing, nine deterministic layout variants, all bespoke boss phases, first-time-player telemetry/debrief output, atomic-save recovery, overwrite confirmation, input rebinding, independent audio buses, named-ship/fighter silhouettes, damage presentation, faction VFX, adaptive sector audio, ten operational events, and campaign/integration compatibility.

M16 tests cover heading navigation, persistent throttle and stop/boost behavior, removed strafe bindings, cursor restoration, the compact adaptive bottom menu, live engagement composition, faction surface atlases/material response/modeling budgets, procedural-sky construction, nebula/star readability, asymmetric HUD styling, and control-strip copy.

M17 tests cover remappable 1/2/3 and bracket actions, placement-camera travel and return, carrier-local screen anchoring, range clamps, staggered fire, airburst interception, nuclear inventory/arming/AoE/friendly fire/interception/trails, heavy carrier limits, speed-reactive engine trails, queued wing redeploy, exact runtime title/archive models, layered menu effects, pooled VFX bounds, and regression compatibility.

M18 tests cover signed carrier zoom, carrier-centered flak framing, direct/tactical placement parity, remappable aggregate hangar-wing control, persistent manual target locks, orbit/approach/keep-distance geometry, collapsible command panels, the interactive overview, projected lock brackets and lead, shader-driven deep space, tapered hull construction, and all prior campaign/combat contracts.

The combat-presentation upgrade tests cover 250 m flak falloff and immunity, fuse clamps and upgrades, layered pooled airbursts, propulsion-demand plume layers, Sidebay geometry and material identity, panorama integration, 1440p HUD density and menu placement, every relative-navigation distance and clear command, all eight tutorial lessons, live bindings, typewriter completion, pose selection, blink/mouth timing, and clean repeated entry.

M19 tests cover reactor budgets and shedding, all subsystem effects, deterministic impacts and hazard propagation, team transit/containment/repair/spare depletion, casualties and crew penalties, officer rescue/death/battle-end resolution/succession, every carrier and aviation store, partial deck service, all priorities and six packages, disabled-deck recovery, dynamic air-group reload capacity, exact service costs, version-10 migration/round trips, remapped responsive operations UI, nine tutorial lessons, seven onboarding steps, and non-pausing repeated entry.

Presentation tests cover menu-first startup, continuous background battle motion, accessibility settings, title-to-campaign fades, manual-save Continue, and return-to-title state preservation.

Carrier-combat integration tests cover unified mouse heading/camera control without hull snap, placed seven-round flak screening, four-missile salvos, nuclear safety behavior, pulsing contact radar, layered deep-space backdrop, flight-operation locks and redeploy, emergency sealing, pursuit exposure, and the closed-bay jump interlock.

Verbose headless integration exits without leaked ObjectDB instances; procedural tones and score generation are skipped only under the headless display driver so desktop and Web audio remain unchanged.

Manual integration checks verify:

- map mode never pauses combat;
- the carrier maintains motion and automated defense in map mode;
- disconnected groups retain the last confirmed order and resume command cleanly;
- both wings repeatedly complete their full flight-deck cycle through the correct bay;
- unidentified contacts reject lock-on attacks;
- the battle cleans up correctly after victory, defeat, and repeated restart;
- the complete encounter meets the performance target.

## 10. Goal protocol

Each `/goal` owns exactly one milestone. Before work begins, read this bible and record the milestone ID in the goal objective. A milestone is complete only when its acceptance gate has evidence. Implementation discoveries may update `[PROVISIONAL]` values directly; changes to `[LOCKED]` decisions require a dated decision-log entry.

## 11. Decision log

- **2026-07-10:** `[LOCKED]` Chose third-person action piloting, continuous real-time tactical command, and a run-based deep-strike structure.
- **2026-07-10:** `[LOCKED]` Chose assisted 3D movement, dozens-of-craft target scale, and visible recover/rearm carrier operations.
- **2026-07-10:** `[LOCKED]` Chose flak and missile carrier armament with shields, armor, and hull durability.
- **2026-07-10:** `[LOCKED]` Chose strict sensor fog, active emissions, estimated tracks, and command-link disruption.
- **2026-07-10:** `[LOCKED]` Chose a three-sector, two-to-three-hour operation with supplies, fuel, intel, salvage, and costly withdrawal.
- **2026-07-10:** `[LOCKED]` Chose department-roster crew management and persistent personnel death with evacuation and rescue.
- **2026-07-10:** `[LOCKED]` Chose Godot 4, Windows PC, mouse/keyboard, and single-player only for the initial product.
- **2026-07-10:** `[LOCKED]` Chose a complete greybox combat loop as the first playable.
- **2026-07-11:** `[PROVISIONAL]` Adopted the first-playable dimensions, ranges, timings, and force counts listed in this bible pending playtest.
- **2026-07-11:** `[PROVISIONAL]` Selected GL Compatibility for the greybox build so testing does not require Vulkan; renderer choice will be revisited with final art targets.
- **2026-07-11:** Implemented and packaged the complete greybox first playable. Automated contract/integration suites and the 1080p performance gate pass; the stabilized development-PC measurement was 165 FPS.
- **2026-07-11:** `[PROVISIONAL]` Added Web as a secondary distribution target using cursor-offset camera/flak direction and single-threaded export for static GitHub Pages hosting.
- **2026-07-11:** Implemented M7 run-layer foundation: three-sector graph, resources, forecasts, threat-scaled combat transitions, manual saves, browser build, and Pages deployment workflow.
- **2026-07-11:** `[PROVISIONAL]` Adopted `EXODRIFT: Carrier Command` as the public title while retaining `Project Sidebay` as the internal codename.
- **2026-07-11:** Implemented M8 fleet persistence and buildcraft: battle condition carries across nodes and saves, supply service restores losses, and victories unlock authored module sidegrades.
- **2026-07-11:** `[PROVISIONAL]` Chose a premium fleet-archive visual language for the public showcase. Deferred the centered animated-battle main menu to M10, after representative combat art exists.
- **2026-07-11:** Implemented the M9 foundation: mixed command-strike/interception/extraction objectives, visible emergency extraction, persistent reduced-reward withdrawals, dual-mode camera zoom, and directional layered target-lock presentation.
- **2026-07-11:** Completed M9 with defense, escort, and capture missions; withdrawal pursuit and jump-range stragglers; recoverable escape pods; and a mandatory after-action rescue/salvage/departure decision backed by version-4 persistent consequence data.
- **2026-07-11:** Re-ran the complete 600-frame 1080p performance gate after M9 at 145 FPS on the development PC; contract, campaign, integration, Web export, Windows export, and packaged-build smoke checks pass.
- **2026-07-11:** Promoted EXODRIFT to the `risxhb.github.io` root experience while retaining Codex City and Eve as bottom-of-page playable projects.
- **2026-07-11:** Completed M10 with an isolated animated fleet-battle title scene, centered command navigation, persistent audio/display/accessibility settings, Credits, Continue/New Operation flows, and return-to-title support. Visual, functional, and 1080p performance gates pass.
- **2026-07-11:** Completed M11 with twelve authored officers across six departments, assignment-driven tactical effects, named escape-pod risk, persistent injuries and recovery, bond consequences, succession, permanent death, and version-5 save migration. Added independent combat-camera orbit and a ±1,400-meter vertical battlespace cap.
- **2026-07-11:** Completed M12 with treatment, promotions, requisition, common and rare authored recruits, deterministic operational events, relationship choices, radio barks, resource-gated outcomes, and version-6 persistence. The 1080p combat gate remains 165 FPS.
- **2026-07-12:** Began M13 with three fixed escort identities, limited sector suppliers, requisition-funded acquisition, unique hull loss, active-escort selection, version-7 persistence, and tactical-profile propagation. Carrier hull replacement, hangar complements, salvage allocation, and deeper logistics remain open.
- **2026-07-12:** Extended M13 with three carrier frames, three air-group complements, exact supply-funded deck refits, dynamic wing capacities, version-8 persistence, and tactical-profile propagation. Salvage allocation and deeper route logistics remain open.
- **2026-07-12:** Completed M13 with persistent salvage stock, three fixed conversion recipes, three route logistics postures, exact map and executor costs, adjusted recovery yields, version-9 persistence, passing automated suites, clean 1280×720 logistics/fleet captures, and successful Web and Windows release exports. All defined milestones M1–M13 are implemented.
- **2026-07-12:** Reworked the playable carrier's combat identity around dense flak curtains, four-missile long-range salvos, retractable armored flight galleries, and a closed-bay jump interlock. Reframed the chase camera on the carrier, removed the center crosshair, expanded the procedural space backdrop, and added a pulsing tactical radar. Emergency sealing preserves withdrawal straggler consequences.
- **2026-07-12:** Completed the carrier-combat stabilization pass: added explicit weapon-cycle/range HUD feedback, removed all headless ObjectDB audio leaks, re-ran every automated suite cleanly, and passed the 600-frame 1920×1080 performance gate at 145 FPS.
- **2026-07-12:** Completed M14 with an original modular/textured carrier combat presentation, role/faction ship profiles, shared and pooled GL-compatible VFX, saved live quality profiles, a maintained combat registry, 10 Hz radar contact caching, tiered parallax space, direct-render captures, and normal/stress performance gates. Carrier rules, bay/jump safety, sensors, and damage remain unchanged.
- **2026-07-12:** Began M15 with a six-step first-operation orientation, three sector-specific enemy fleets and battlefield palettes, original navy/raider/alien hull plating, and expanded capital-ship silhouettes with readable functional detail. Contract, campaign, integration, and dedicated onboarding suites pass; bespoke bosses and external playtest validation remain open.
- **2026-07-12:** Completed M15 implementation with nine deterministic sector layouts, bespoke Acheron/Vesper/Crucible command phases, structured playtest telemetry and debriefing, role-readable ship/fighter geometry and damage VFX, atomic backup-recoverable autosaves, overwrite confirmation, remappable controls, independent audio buses, an adaptive procedural score, and ten authored operational events. Nine automated suites, menu/normal/stress performance gates, and both release exports pass; external first-time-player sessions now drive post-M15 balance evidence.
- **2026-07-12:** Completed M16 with a compact bottom title command row, a reframed fleet engagement, intent-driven helm controls, double-click vector flight, persistent throttle, an asymmetric military HUD, faction-specific surface refits, and updated landing-page media. Replaced the blurry panorama with a crisp procedural sky after direct-render visual QA. All thirteen regression suites, normal/stress/menu performance gates, both release exports, and the packaged-build smoke check pass.
- **2026-07-12:** Completed M17 with a unified visible-pointer command view, heavy carrier inertia, carrier-relative placed flak screening, guided and nuclear ordnance hotkeys, physical post-service wing redeploy, speed-reactive trails, layered bounded impacts/explosions, exact runtime models in the title engagement, and direct Godot model renders in the public fleet archive. Fourteen suites and normal/stress/menu gates pass; release exports and live-site verification are the remaining packaging checks.
- **2026-07-12:** Completed the combat-presentation and tutorial upgrade: 3.2 km/250 m flak airbursts, demand-driven layered carrier exhaust, the dark gunmetal Sidebay silhouette refit, a seam-feathered galaxy panorama, 2560×1440 output with a 75% HUD, carrier right-click relative-navigation distances, and an eight-part animated Commander Mara Voss tutorial.
- **2026-07-13:** Completed M19 Integrated Carrier Operations with version-10 persistence, engineering triage, power distribution, deterministic internal hazards, damage-control teams, persistent crew survival, finite magazines and aviation stores, explicit deck logistics, six wing packages, officer rescue/succession, exact fleet-service actions, a responsive live operations console, nine tutorial lessons, and seven-step first-operation onboarding. Twenty functional suites and all 1080p/1440p performance profiles pass.
