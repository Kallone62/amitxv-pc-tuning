SSD SETUP - FINAL BASELINE - 2026-10-08

CURRENT COMPONENT VERSIONS
--------------------------
Fresh-install launcher        : 00_Fresh_Install_W11_Pro.cmd
Gaming driver installer       : v2.3.6
CS2 Gaming-Only baseline      : v1.0.9
CS2 launcher                  : revision 14.8
Intel I226-V baseline         : v2.4 comprehensive supported PM lockdown
Gaming device power baseline  : v1.4
Post-format application layer : revision 12
Post-format policy baseline   : v1.2
Low-risk background baseline  : v1.1
App privacy baseline          : v1.1
KovaaK CS2 standard package   : v1.0.2 current-crosshair sync

NORMAL ORDER AFTER A CLEAN IMAGE
--------------------------------
1. Run 00_Fresh_Install_W11_Pro.cmd from the other Windows installation.
2. Complete OOBE on the new Windows.
3. Get Ethernet online if the clean image has no usable I226-V inbox driver.
4. Run .drivers\Check_Gaming_Driver_Syntax.cmd.
5. Run .drivers\Audit_Gaming_Drivers_v2.cmd.
6. Run .drivers\Run_Gaming_Drivers_v2.cmd.
7. Reboot after the driver layer completes.
8. Run Run_CS2_Gaming_Scripts.cmd.
9. Run Run_PostFormat_Apps.cmd.
10. Reboot once more before judging the gaming baseline.

IMPORTANT CLEAN-INSTALL NETWORK NOTE
------------------------------------
The driver layer downloads current official packages from AMD / ASUS / NVIDIA.
Therefore the very first driver run needs working Internet access.
On the tested clean image, Intel I226-V did not have usable networking until its
LAN INF was installed once. That bootstrap LAN installation is still the one
remaining manual prerequisite if Windows has no working Ethernet immediately
after OOBE. The automated driver layer then audits the exact provider/version
and skips/replaces as appropriate.

KEY FINAL BEHAVIOUR
-------------------
- Windows 11 Pro image is hard-coded to the tested WIM path/index and D: target.
- Fresh-install script fixes the previous ROBocopy trailing-backslash bug.
- Offline WU/PnP guards are staged before first boot.
- AMD chipset wrapper exit-code 2 is accepted only when the target package state
  verifies successfully.
- PnP driver verification uses direct devnode driver properties and recognizes
  reboot-pending Code 14 state.
- Realtek UCM uses exact INF/device binding verification.
- AMD iGPU remains driver-only.
- NVIDIA remains display-driver-only; NVIDIA App and HD Audio are not selected.
- NVIDIA Control Panel is installed separately through Microsoft Store HSA.
- I226-V applies the comprehensive supported NetAdapter PM disable path and
  separately verifies AllowComputerToTurnOffDevice=Disabled after one restart.
- EEE and Flow Control remain disabled; unrelated network scheduler/queue/ASPM
  tweaks remain untouched.
- Windows mouse desktop baseline is fixed for the intended 1600-DPI setup:
  MouseSensitivity=4 and Enhance Pointer Precision/acceleration disabled.
- Logitech LIGHTSPEED and Wooting exact audited device functions have USB power
  management disabled; unrelated USB/xHCI/root hubs remain stock.
- Defender intervention profile applies only after Tamper Protection is OFF;
  no Tamper Protection bypass is attempted.
- TeamSpeak 3.6.2 is installed without the /Overwolf opt-in; Overwolf is a
  forbidden final-state bundle and is removed/fail-closed if detected.
- FACEIT Anti-Cheat is kept; the separate FACEIT platform client is removed and
  the AC-only state is stabilized/verified.
- ExitLag remains manual/optional and no longer blocks the remaining app chain.
- Wootility Web and Logitech Onboard Memory Manager official pages are opened in
  the normal user session and Start Menu URL shortcuts are created.
- Already-installed post-format applications are detected and skipped on rerun.
- KovaaK CS2 standard now sources the current root autoexec and mirrors its current
  pixel crosshair: style 4 / length 2 / gap 0 / thickness 2 / green / 960 reference.

INTENTIONALLY NOT DONE
----------------------
- No timer/HPET/BCD scheduler hacks.
- No blanket service deletion/disable.
- No pagefile/memory-compression hacks.
- No global interrupt affinity/MSI hacks.
- No broad component-store surgery.
- No NVIDIA App / NVIDIA HD Audio / Overwolf / separate FACEIT platform client.
- No undocumented I226 registry fallback if supported NetAdapter APIs fail.

This package is the consolidated final state from the 2026-10-08 clean-install
test cycle.
