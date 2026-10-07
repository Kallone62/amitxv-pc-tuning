# my-pc-optimization

Personal, system-specific Windows / CS2 deployment and optimization repository for my own gaming PC.

This is **not a generic tweak pack or public tuning guide**. Hardware identity, firmware, device topology, installed drivers, peripheral firmware/settings and the exact CS2/FACEIT workload are part of the baseline. A change belongs here only when it makes sense for this machine and can be reapplied deliberately.

> Current platform: **Ryzen 7 9800X3D · ASUS ROG STRIX B850-I · 32 GB G.Skill DDR5 · RTX 3080 12 GB · Samsung 990 Pro · ZOWIE XL2566X+ 400 Hz**

Full hardware/peripheral context: [`SYSTEM.md`](SYSTEM.md)  
Snapshot review and known gaps: [`VALIDATION.md`](VALIDATION.md)

## What this repository is for

The repository is the reproducible setup layer for a dedicated competitive-CS2 machine. Its job is to make a clean Windows install converge toward the same known configuration without turning the setup into a pile of undocumented one-off tweaks.

The focus is practical:

- reconstruct the machine after a clean format
- install the intended driver set while avoiding unnecessary resident vendor software
- apply the Windows / device / network policies used by this PC
- preserve CS2, mouse, keyboard and KovaaK's reference configuration
- keep post-update maintenance actions in one place
- separate old-platform material from the current baseline
- retain enough validation and rollback context that a later change can be evaluated rather than guessed

The target is not “the highest tweak count”. The target is a repeatable system that remains responsive and consistent for CS2 while avoiding changes that are broad, unverified or hard to reverse.

## Current hardware baseline

- **CPU:** AMD Ryzen 7 9800X3D
- **Motherboard:** ASUS ROG STRIX B850-I GAMING WIFI
- **Memory:** G.Skill F5-6400J3239G16GX2-TZ5RK, 2×16 GB DDR5, heatspreaders removed
- **GPU:** MSI GeForce RTX 3080 12 GB LHR
- **SSD:** Samsung 990 Pro 1 TB
- **Cooling:** DeepCool LT720
- **Case:** Lian Li LANCOOL III
- **PSU:** FSP Hydro PTM PRO 1200W
- **UPS:** Schneider Electric Easy UPS SRVS3KI

The RAM is the same physical kit that was used on the previous 13900KF/Z690 Tachyon platform; old notes calling it only “Hynix A-Die 2×16” refer to this same kit.

## Competitive peripheral baseline

- **Monitor:** BenQ ZOWIE XL2566X+, 400 Hz
- **Mouse:** Logitech G PRO X Superlight 2 DEX — 1600 DPI, 2000 Hz wireless, LOD High
- **CS2 sensitivity:** `0.475`; zoom sensitivity ratio `0.9`
- **Keyboard:** Wooting 80HE — 0.5 mm general actuation, 0.3 mm Ctrl/Shift, 0.1 mm WASD; Rapid Trigger 0.1 mm on WASD + Ctrl
- **Headset:** Corsair HS80
- **Mousepad:** SteelSeries QcK+

The submitted setup also included UI screenshots for CS2, Wooting and Logitech state. Their settings have been normalized into [`REFERENCE_STATE.md`](REFERENCE_STATE.md) so the repository stays diffable and Git-friendly. The original screenshot hashes and the submitted archive hash remain recorded for provenance.

## Repository layout

```text
.
├── .bios/
│   ├── current/ROG-B850-I/       # current BIOS baseline (pending capture)
│   └── legacy/Z690-Tachyon/      # old 13900KF/Tachyon AMISCE exports
├── .drivers/
│   ├── Assets/Monitor/           # fixed XL2566X+ WHQL monitor package
│   ├── Install-Gaming-Drivers-v2-LatestOfficial.ps1
│   ├── Run_Gaming_Drivers_v2.cmd
│   └── README.txt
├── .scripts/                     # Windows/device/network/application policy layers
├── After Game Update/            # maintenance used after relevant game/driver updates
├── Game/                         # CS2 autoexec
├── Keyboard/                     # Wooting profile identifier
├── Mouse/                        # reserved for mouse-specific deployable state
├── Training/                     # KovaaK's CS2 standard + aim routine
├── Run_CS2_Gaming_Scripts.cmd    # main gaming-baseline orchestrator
├── Run_PostFormat_Apps.cmd       # selected app/runtime installer
├── Test_WU_Driver_Scan_Once.cmd  # read-only Windows Update driver scan test
├── SYSTEM.md
├── REFERENCE_STATE.md
└── VALIDATION.md
```

## Deployment flow

The package is intended to be used in layers rather than by randomly running every script.

### 1. Clean Windows / platform prerequisites

Start from the intended Windows 11 gaming install and establish the firmware/security state required by the current FACEIT setup. The main gaming baseline performs Secure Boot / TPM and related preflight checks and deliberately refuses several broad “latency tweak” classes.

### 2. Drivers

Run:

```bat
.drivers\Run_Gaming_Drivers_v2.cmd
```

The driver workflow is hardware-specific. It verifies the B850-I / 9800X3D / RTX 3080 12 GB target before installation and resolves current official packages at runtime.

Its selected path covers:

- AMD B850 chipset
- Intel I226-V LAN from the ASUS board support package
- Realtek UCM for the detected board device
- AMD 9800X3D iGPU as driver-only where the package can be safely extracted
- NVIDIA RTX 3080 Game Ready display driver with optional NVIDIA package components intentionally avoided
- bundled ZOWIE XL2566X+ V001 WHQL monitor INF

The driver installer is designed around audit-before-mutation, exact-device/INF matching, vendor/hash/signature checks where available, refusal of automatic downgrades, and post-install binding verification. It does **not** use DDU or a blanket Driver Store purge.

The current driver layer is **v2.3.4 (review build)**. For a clean-format install it snapshots the pre-run Windows Update/PnP driver-policy state, applies a temporary guard while vendor drivers are resolved and bound, and restores those temporary values on both success and failure; interrupted runs retain a small recovery state for the next launch. AMD chipset success is judged by the registered package version rather than the outer wrapper exit code alone, PnP/NVIDIA binding gets a longer settle-and-verify window, and the ZOWIE monitor step can rescan after the NVIDIA display stack changes. `.drivers/Check_Gaming_Driver_Syntax.cmd` and `.drivers/Audit_Gaming_Drivers_v2.cmd` are the intended non-mutating checks before the real install.

### 3. Post-format applications

Preview first if desired:

```bat
Run_PostFormat_Apps.cmd -Preview
```

Then install:

```bat
Run_PostFormat_Apps.cmd
```

The application layer installs/verifies the selected Microsoft runtimes and the personal gaming-app set, including Chrome, AutoHotkey, FACEIT AC, Spotify, TeamSpeak, Steam and the other explicitly configured entries in `.scripts/Install-PostFormat-Apps.ps1`.

### 4. Windows / device / network gaming baseline

Run:

```bat
Run_CS2_Gaming_Scripts.cmd
```

This launcher coordinates the current Windows baseline modules. Important sublayers include:

- `CS2-GamingOnly-Pro-v1.0.8.ps1` — dedicated Steam/CS2/FACEIT Windows baseline and preflight
- `I226V_Baseline_v2.ps1` — I226-V power-saving/network-device baseline without blindly changing RSS/ITR/offload topology
- `Gaming-Device-Disable-v2.ps1` — conservative allowlisted disable layer for explicitly unused endpoints, with restore state
- `Gaming-Device-Power-Baseline-v1.ps1` — exact Logitech/Wooting function power settings plus narrow I226-V power controls
- `Gaming-Background-Cleanup-v1.ps1` — selected updater/task background cleanup with restore support
- `PostFormat-Policy-Baseline-v1.ps1` — Windows Update / security / file-intervention policy used by this dedicated image
- `PostFormat-LowRisk-Background-v1.ps1` — low-risk background-feature policy
- `PostFormat-App-Privacy-Capabilities-v1.ps1` — documented Windows app-capability policy layer
- `WU-Driver-Scan-v1.ps1` — read-only Windows Update Agent driver search used by the policy workflow

The main baseline explicitly avoids applying timer/BCD hacks, blanket service shutdowns, MSI/IRQ affinity tuning, C-state/core-parking changes, memory-manager hacks and similar broad modifications simply because they are popular “optimization” tweaks.

## Game / input / training state

### CS2

`Game/autoexec.cfg` is the current text configuration snapshot. The submitted CS2 video screenshots were reviewed and their visible state is transcribed in [`REFERENCE_STATE.md`](REFERENCE_STATE.md), including 1280×960 fullscreen at 400 Hz and the captured advanced-video settings.

### Mouse

The submitted Logitech onboard-memory screenshot was reviewed and normalized into [`REFERENCE_STATE.md`](REFERENCE_STATE.md): active slot 1, 1600 DPI, High LOD, 1000 Hz wired and 2000 Hz wireless polling.

### Keyboard

`Keyboard/wootility.io.txt` preserves the Wootility profile identifier. The submitted Wooting screenshots were reviewed and their Tachyon/8K, actuation and Rapid Trigger state is normalized into [`REFERENCE_STATE.md`](REFERENCE_STATE.md).

### KovaaK's

`Training/KOVAAKS_CS2_STANDARD_V1.zip` is a self-contained, checksummed deployment package for the CS2-oriented KovaaK's profile. It includes its own backup/restore mechanism and internal verification. The package passed its own SHA-256 manifest check before this repository deployment.

The root CS2 autoexec has evolved since that KovaaK package was generated, particularly around the crosshair block. This difference is recorded in [`VALIDATION.md`](VALIDATION.md) rather than silently rewriting either source.

## After game/driver updates

`After Game Update/shadercachereset.bat` clears selected NVIDIA and Windows DirectX shader-cache locations while leaving the top-level cache folders in place. Shader-cache clearing is not treated as a routine FPS “boost”; the script itself warns that rebuilding shaders can temporarily cause stutter on the first runs afterwards.

## Safety and validation model

This repository contains scripts that can change drivers, devices, Windows policies, Defender preferences and application state. It is personal infrastructure, not a recommendation for another PC.

The current package favors several safety properties:

- exact hardware checks where the action is hardware-dependent
- audit/preview modes where practical
- refusal to guess when multiple devices match
- allowlists and hard exclusions for device operations
- idempotent checks before repeating changes
- post-change state verification rather than trusting installer exit codes alone
- restore state for selected disable/background layers
- no automatic use of legacy BIOS values on the new AMD platform

A static review was completed before the first GitHub deployment; details and limits are in [`VALIDATION.md`](VALIDATION.md). Runtime success still has to be established on the real Windows installation because PnP ranking, firmware state, Windows policy behavior and current vendor packages cannot be proven from the repository alone.

## BIOS state

The current **9800X3D + ASUS ROG STRIX B850-I** BIOS baseline is the main unfinished layer.

The two existing BIOS exports came from the previous **13900KF + Gigabyte Z690 Tachyon** platform. They are preserved under `.bios/legacy/Z690-Tachyon/` for comparison only and must not be treated as direct values for the current board.

Once the B850-I baseline is captured, it should be added under `.bios/current/ROG-B850-I/` together with the exact BIOS/AGESA version and enough context to reproduce the validated state.

## Change policy

Future changes should be handled as system-specific experiments:

1. define the intended gain and mechanism;
2. change one meaningful variable at a time where possible;
3. decide the acceptance metric before testing;
4. compare under similar conditions;
5. keep the change only if the benefit is repeatable without worsening stability or tail behavior;
6. record the resulting working point so the next clean install can reproduce it.

Subjective “feel” is useful as a hypothesis, but it is not a substitute for repeatable behavior. Average FPS alone is also not enough; frametime consistency, tail events, input behavior, networking and real-match stability matter to the final baseline.

## Legacy platform

For historical context, the prior platform was a Core i9-13900KF + Gigabyte Z690 Tachyon with the **same DDR5 kit**, RTX 3080, Samsung 990 Pro, GALAHAD 360, LANCOOL III and FSP Hydro PTM PRO. Only the CPU/motherboard/cooling platform context changed; the old BIOS exports are clearly segregated so they remain useful without contaminating the current configuration.

## Personal profile

Steam: https://steamcommunity.com/id/officialdescrip/
