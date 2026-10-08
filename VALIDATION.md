# Validation

## 2026-10-08 consolidated audit

The user-supplied package `SSD Setup - FINAL - 2026-10-08.zip` was treated as the candidate source baseline and independently re-audited before repository deployment.

Submitted package SHA-256:

`1ddf469322ad763cf298abcb6fd271db5867df0be0e2f4c61e1cad6956a68ff5`

The audit found four package-linkage/documentation drifts that were corrected before deployment:

1. `.drivers/README.txt` referenced `Check_Gaming_Driver_Syntax.cmd` and `Audit_Gaming_Drivers_v2.cmd`, but those launchers were missing from the submitted ZIP. They were restored and updated for driver v2.3.6.
2. `Run_CS2_Gaming_Scripts.cmd` declared REV14.8 but its end-of-file comment still said REV14.6. The stale footer was corrected.
3. `.scripts/Gaming-Device-Disable-v2.ps1` had a restore example pointing to the nonexistent `Gaming-Device-Disable-Final.ps1`; it now points to itself.
4. `Training/KOVAAKS_CS2_STANDARD_V1.zip` still carried the older CS2 size-1/gap--4/thickness-1 crosshair snapshot even though the root autoexec had moved to the current pixel-unit length-2/gap-0/thickness-2 state. The package source snapshot, manifest, asset, apply script and internal hashes were synchronized to the root autoexec.

Corrected post-audit package SHA-256:

`fc22d7d0d09aa602f645a8c446a1713dd4ab5e6469132d7d70678176bce0c2c5`

## Static/linkage checks completed

- outer corrected package: 37 files, ZIP CRC clean;
- all expected launchers/scripts present;
- all CMD/BAT `goto` / `call` labels resolve;
- all PowerShell files passed a lexical block-comment/string/here-string and delimiter-balance scan;
- no duplicate custom PowerShell function definitions were found;
- every custom function definition has at least one call site;
- launchers reference existing PowerShell targets;
- stale runtime markers for CS2 v1.0.8, PostFormat REV11, driver v2.3.4/v2.3.5 and launcher 14.6/14.7 are absent;
- final runtime versions match v2.3.6 / v1.0.9 / REV14.8 / I226 v2.4 / device-power v1.4 / PostFormat REV12;
- fresh-install launcher contains the expected D: format, WIM index 4/DISM apply, offline update/PnP guard and BypassNRO path, and contains no BCD/EFI mutation command;
- the bundled XL2566X+ WHQL archive still hashes to `E8B600BE155F85BA417BEE80EAE6065848885F9E72A331B19D17D53FD9751D38`, matching the driver installer's pin;
- KovaaK ZIP CRC passes and all 11 entries in its internal `SHA256SUMS.txt` verify;
- KovaaK `Source-CS2-autoexec.cfg` is byte-identical to root `Game/autoexec.cfg` after the audit sync;
- package PNG/JPG evidence assets decode successfully.

## Functional ownership checks

The scripts have a coherent ownership chain rather than competing global tweaks:

- fresh installer owns image application and offline first-boot policy staging;
- driver installer owns the six hardware-driver steps;
- CS2 launcher owns the ordered Windows/game baseline;
- I226 v2.4 owns NIC power behavior;
- gaming-device-power v1.4 owns only the exact audited Logitech/Wooting USB functions and reads, rather than reconfigures, the I226 master state;
- policy v1.2 owns update/security policy and the read-only scheduled WU driver scan;
- PostFormat REV12 owns the application layer.

## Windows runtime boundary

This repository audit is not a substitute for execution on the target Windows 11 image. The Linux-side review cannot execute Windows PowerShell 5.1, SetupAPI/PnP, NetAdapter, WUA COM, AppX/winget or the actual vendor installers.

Before the real driver install on the target PC, run:

1. `.drivers\Check_Gaming_Driver_Syntax.cmd`
2. `.drivers\Audit_Gaming_Drivers_v2.cmd`
3. `.drivers\Run_Gaming_Drivers_v2.cmd`

The individual scripts also keep their own hard verification and fail/partial reporting. The remaining clean-image prerequisite is unchanged: if the target Windows image has no usable inbox I226-V networking, bootstrap the Ethernet INF once before the online driver resolver can operate.
