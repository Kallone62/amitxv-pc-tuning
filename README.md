# my-pc-optimization

Personal, system-specific Windows 11 + CS2 baseline for my competitive PC. This is **not a generic tweak guide**: the scripts, validation rules and install order are built around the exact hardware and peripherals documented in [`SYSTEM.md`](SYSTEM.md).

The optimization goal is lower and more consistent end-to-end latency without trading away frametime consistency, tail behavior, stability or reproducibility. A setting is kept because it has a defined job in this machine's chain, not because it is generically described as an “FPS tweak”.

## Current machine

- AMD Ryzen 7 9800X3D
- ASUS ROG STRIX B850-I GAMING WIFI
- G.Skill F5-6400J3239G16GX2-TZ5RK, 2×16 GB (same physical Hynix A-die kit used on the previous platform; heatsinks removed)
- MSI RTX 3080 12 GB LHR
- Samsung 990 Pro 1 TB
- BenQ XL2566X+
- Logitech Superlight 2 DEX — 1600 DPI, 2000 Hz
- Wooting 80HE

The old 13900KF + Z690 Tachyon BIOS material is preserved only under `.bios/legacy/Z690-Tachyon/`. It is not the active platform baseline.

## Canonical 2026-10-08 baseline

The audited package baseline is the post-audit **r1** state:

- original submitted ZIP SHA-256: `1ddf469322ad763cf298abcb6fd271db5867df0be0e2f4c61e1cad6956a68ff5`
- audited/corrected r1 ZIP SHA-256: `fc22d7d0d09aa602f645a8c446a1713dd4ab5e6469132d7d70678176bce0c2c5`
- driver installer: **v2.3.6**
- CS2 Gaming-Only baseline: **v1.0.9**
- CS2 launcher: **REV14.8**
- Intel I226-V baseline: **v2.4**
- gaming-device power baseline: **v1.4**
- post-format applications: **REV12**
- policy baseline: **v1.2**
- KovaaK CS2 standard: **V1 / package revision 1.0.2-current-cs2-crosshair-sync**

`FINAL_README.txt` is the compact deployment order. `FINAL_AUDIT.txt` records the package-level static/linkage audit. [`VALIDATION.md`](VALIDATION.md) explains what was actually verified and what still requires execution on the target Windows image.

## Clean-install order

1. From the existing Windows installation, run `00_Fresh_Install_W11_Pro.cmd`.
2. Complete OOBE on the new Windows installation.
3. If the clean image does not provide a usable inbox Intel I226-V LAN driver, bootstrap that Ethernet INF once so the online driver resolver can reach the vendor endpoints.
4. Run `.drivers\Check_Gaming_Driver_Syntax.cmd`.
5. Run `.drivers\Audit_Gaming_Drivers_v2.cmd`.
6. Run `.drivers\Run_Gaming_Drivers_v2.cmd`.
7. Reboot.
8. Run `Run_CS2_Gaming_Scripts.cmd`.
9. Run `Run_PostFormat_Apps.cmd`.
10. Reboot before evaluating the final gaming state.

The syntax check and driver Audit are deliberately non-mutating. Install mode still performs its own six-step precheck before it changes a driver.

## Layer ownership

### Fresh Windows deployment

`00_Fresh_Install_W11_Pro.cmd` is deliberately specific to the tested image and target. It validates the hard-coded Windows 11 Pro WIM/index, quick-formats the configured `D:` target, applies the image with DISM, stages the offline Windows Update/PnP guard and `BypassNRO`, then copies the SSD Setup tree into the new Windows installation. It does not build or rewrite BCD/EFI state.

### Driver layer — v2.3.6

`.drivers/Install-Gaming-Drivers-v2-LatestOfficial.ps1` owns the clean-format vendor-driver baseline:

1. AMD B850 chipset
2. Intel I226-V LAN
3. Realtek UCM
4. AMD iGPU driver-only
5. NVIDIA RTX 3080 graphics driver-only
6. ZOWIE XL2566X+ WHQL monitor package

Important behavior:

- exact target hardware/platform assertions are performed before install;
- AMD's outer chipset wrapper exit code is diagnostic rather than sufficient proof of success — the target registered package version must verify;
- INF-backed devices use direct devnode verification, including reboot-pending Code 14 handling and PnP rank diagnostics for real mismatches;
- NVIDIA installs the graphics driver only; NVIDIA App and NVIDIA HD Audio are not selected;
- NVIDIA Control Panel is installed and verified separately through its Microsoft Store HSA package;
- the bundled ZOWIE package is pinned by SHA-256 and can be rescanned after the NVIDIA display stack binds.

### Windows / CS2 baseline — v1.0.9 / REV14.8

`Run_CS2_Gaming_Scripts.cmd` orchestrates the dedicated Windows/CS2 layers rather than hiding unrelated changes in one script. The active desktop-mouse baseline for the 1600-DPI setup is `MouseSensitivity=4`, `MouseSpeed=0`, `MouseThreshold1=0`, `MouseThreshold2=0`.

The baseline intentionally does **not** add HPET/BCD timer hacks, blanket service deletion, pagefile or memory-compression hacks, global interrupt-affinity/MSI hacks, or broad PCIe/network queue changes.

### Intel I226-V — v2.4

The I226-V layer owns NIC power policy. EEE and Flow Control are disabled, supported DMA Coalescing / Reduce Speed On Power Down / Ultra Low Power controls are disabled when exposed, and the supported Windows/NDIS power-management path is comprehensively disabled. `AllowComputerToTurnOffDevice=Disabled` is separately forced and verified after the adapter restart.

It intentionally leaves Interrupt Moderation, RSS, LSO/checksum offloads, Speed & Duplex and system-wide ASPM alone. There is no undocumented registry fallback if the supported NetAdapter interfaces fail.

### Gaming-device power — v1.4

Only the audited Logitech LIGHTSPEED and Wooting USB functions are changed. USB root hubs, xHCI and unrelated HID devices remain stock. This layer does not configure I226-V a second time; it checks the I226 master state produced by the preceding NIC layer.

### Policy / security

Windows Update freeze and read-only driver-scan behavior remain centralized in the policy layer. Defender's minimal-intervention preferences are applied only when Tamper Protection permits them; no Tamper Protection bypass is attempted.

### Post-format applications — REV12

Reruns skip already-satisfied applications. TeamSpeak 3.6.2 is installed from the pinned clean installer without the `/Overwolf` opt-in; Overwolf is a forbidden final-state component. FACEIT Anti-Cheat is kept while the separate FACEIT platform client is removed and the AC-only state is stabilized. ExitLag is optional/manual and does not abort the rest of the chain. Wootility Web and Logitech Onboard Memory Manager are opened in the normal user session and receive Start Menu shortcuts.

## CS2 ↔ KovaaK synchronization

`Game/autoexec.cfg` is the source of truth for CS2-specific values. The current baseline is:

- 1280×960 / 4:3 stretched
- sensitivity `0.475`
- zoom sensitivity ratio `0.9`
- `fps_max 0`
- static crosshair: style 4, **length 2, gap 0, thickness 2**, green RGBA `0/255/0/255`, reference screen height `960`

`Training/KOVAAKS_CS2_STANDARD_V1.zip` was re-synchronized during the final audit: its `Source-CS2-autoexec.cfg` is byte-identical to the root autoexec, its manifest uses the current values, and its 1280×960 crosshair asset follows the current CS2 pixel-unit crosshair rather than the older size-1/gap--4 snapshot.

## BIOS status

The active 9800X3D + B850-I BIOS baseline is intentionally not fabricated from the old Tachyon material. `.bios/current/ROG-B850-I/` remains the place for the real captured/validated firmware state. Legacy Tachyon files are preserved separately for provenance only.

## Validation rule

A successful script exit is not automatically treated as proof of competitive improvement. Changes are evaluated against the previous known-good state with the smallest comparison that answers the question, and retained only when they preserve or improve responsiveness, frametime/tail consistency and stability. Subjective feel is treated as a testable hypothesis, not as proof.
