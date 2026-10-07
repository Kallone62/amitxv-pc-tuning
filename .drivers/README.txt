ï»¿GAMING DRIVER INSTALLER v2.3.4 - REVIEW BUILD
=============================================

This is the online post-format version.

Online driver versions are not pinned; the bundled ZOWIE monitor archive is fixed.

At every run it:
1. Verifies this is the intended ROG STRIX B850-I / Ryzen 7 9800X3D platform.
2. Resolves the current official driver from the vendor.
3. Checks the currently bound provider/INF DriverVer BEFORE installing.
4. Skips an exact current match.
5. Refuses an automatic downgrade if the installed driver is newer.
6. Checks device state again after each install; staging alone is not success.
7. Audit reports all six step results in one run, even if one step fails.
8. Install performs the entire Audit precheck first. A failed precheck stops
   before ANY installer or PnP driver-binding command is run.
9. Returns the elevated child's actual exit code to the CMD launcher.
10. Install mode asserts a temporary Windows Update / PnP driver guard before precheck.
11. The driver-specific guard is restored to its exact pre-run state after success or failure; NoAutoUpdate is intentionally retained.

WINDOWS UPDATE / PNP BOOTSTRAP GUARD
------------------------------------
Install mode temporarily sets the documented machine-policy paths used to stop
Windows Update from racing driver binding while the vendor packages are being
resolved and installed:
  - HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\ExcludeWUDriversInQualityUpdate = 1
  - HKLM\Software\Policies\Microsoft\Windows\DriverSearching\SearchOrderConfig = 0
  - HKLM\Software\Policies\Microsoft\Windows\DriverSearching\DontSearchWindowsUpdate = 1

Before changing those three driver-specific values, the installer snapshots
whether each value existed and its DWORD data. That snapshot is restored after
6/6 verification, after a failed precheck/install, and on the next run if a
previous run was interrupted before cleanup. The permanent NoAutoUpdate=1 value
is not part of that temporary snapshot because it belongs to this machine's
separate post-format update policy.

SELECTED DRIVER SOURCES
-----------------------
AMD B850 chipset:
  AMD official B850 support page -> drivers.amd.com
  Normal AMD chipset installer using AMD-documented /S unattended deployment.
  The outer wrapper exit code is diagnostic only: current 8.x packages are
  accepted only when the registered AMD Chipset Software version verifies.
  The script waits up to 180 seconds for the inner installer to settle.
  The installed-version check ignores unrelated uninstall entries without
  DisplayName or DisplayVersion before any install decision is made.

Intel I226-V:
  Current ASUS ROG STRIX B850-I Windows 11 LAN package.
  ZIP SHA-256 is taken from the ASUS support page and verified.
  The hash-checked ZIP is inspected in Audit or Install; the matching INF is
  installed with PnPUtil only in Install mode. ASUS's marketing package
  version is NOT assumed to equal the INF's DriverVer.
  The ASUS page's relative /pub/ASUS download path, version and SHA-256 are
  parsed from the SAME package record. No adjacent-package URL guessing.
  The exact INF model is checked against both Windows Hardware IDs and
  Compatible IDs. For PCI devices, the VEN/DEV base ID is also derived from
  the confirmed instance ID when Windows omits it from one of those lists.

Realtek UCM:
  UCM is Windows USB Type-C Connector Manager, not an FPS driver.
  The current ASUS motherboard Realtek UCM package is used for the detected
  ACPI\RTK5452 device. Its matching INF is installed with PnPUtil and its
  binding is verified.

AMD iGPU:
  Preferred source: AMD's CURRENT WHQL Recommended package for Ryzen 7 9800X3D.
  The script downloads the official AMD package and attempts to extract it with
  Windows 11's built-in tar/libarchive. It then installs ONLY the INF matching
  the present AMD display device through PnPUtil.

  No Adrenalin UI, overlay, recording or tuning package is intentionally run.

  If Windows tar cannot read AMD's self-extracting archive, the script falls
  back to the CURRENT ASUS OEM VGA ZIP for this exact motherboard, verifies the
  ASUS SHA-256, and again installs only the matching display INF.

  This avoids undocumented AMD consumer-installer switches while still
  preferring AMD's Recommended branch when the package can be extracted safely.

NVIDIA RTX 3080 12GB (PCI\VEN_10DE&DEV_220A):
  NVIDIA's official driver lookup backend for RTX 30 Series / RTX 3080.
  WHQL Game Ready / DCH.
  The lookup's URL-encoded package name is decoded before filtering for the
  Game Ready branch and explicit RTX 3080 support.
  The actual installed card reports DEV_220A; DEV_2206 is NOT its ID.
  The signed downloaded EXE is extracted with Windows tar. The signed
  setup.exe beside Display.Driver is then run as:
      -s -n Display.Driver
  If extraction does not work on the target Windows build, the step STOPS;
  it does not guess switches for the outer self-extracting EXE.
  NVIDIA App and other optional package selections are not installed by this
  script. Only exit code 0 or 1 is accepted, then the bound device is checked for up to 60 seconds.


ZOWIE XL2566X+ MONITOR
----------------------
The official ZOWIE XL2566X+ V001 / 1.0 WHQL monitor package is bundled at:

  Assets\Monitor\XL2566X+_WHQL dirver_V001_Windows_240605180238.7z

SHA-256:
  E8B600BE155F85BA417BEE80EAE6065848885F9E72A331B19D17D53FD9751D38

Precheck can DEFER monitor matching until after the NVIDIA driver binds; the
real 6/6 install step rescans the display stack before deciding.

The monitor layer:
- enumerates only PRESENT Monitor-class PnP devices
- matches the monitor's exact Hardware IDs against the INF in the package
- checks currently bound Provider + DriverVersion BEFORE installation
- skips an exact ZOWIE/BenQ match
- validates the WHQL catalog signature
- installs only the matching monitor INF with PnPUtil and checks its binding
- does not install XL Setting to Share or any resident ZOWIE software

A Microsoft Generic Monitor version is NOT compared numerically with the ZOWIE
INF version because those version schemes belong to different providers.

This monitor INF is device metadata/timing/color-profile plumbing, not an FPS
tweak. Its purpose is to leave Windows in the monitor vendor's intended state
without adding a resident service or filter driver.


NOT INSTALLED
-------------
- MediaTek Wi-Fi
- Bluetooth
- Realtek USB/ALC4080 audio
- Armoury Crate / RGB suites
- NVIDIA App
- AMD Adrenalin UI

Not requesting these drivers does NOT guarantee they are absent or disabled:
Windows inbox / Windows Update may install them. The separate device-disable
policy is NOT included in this ZIP. Do not disable USB, PCIe or audio parent
controllers by class or friendly name. Verify exact device instance IDs after
the final reboot before any separate disable step.

NO CLEAN-SWAP
-------------
No DDU.
No Driver Store purge.
No delete-driver /force.
This workflow assumes driver changes are paired with a clean Windows format.

FILES / STATE
-------------
Downloads and temporary extraction:
  C:\ProgramData\GamingDriverInstaller\
  ASUS downloads reuse a local file only if its SHA-256 matches the currently
  published ASUS hash. Signed AMD/NVIDIA EXEs now also reuse a local file
  across runs when its saved source URL and SHA-256 match. Their vendor
  Authenticode signature is checked again before use. New vendor versions
  have new URLs and are downloaded when actually required.

Logs:
  C:\ProgramData\GamingDriverInstaller\Logs\

FIRST RUN
---------
First, check script syntax without touching drivers:
  Check_Gaming_Driver_Syntax.cmd

Then run the audit:
  Audit_Gaming_Drivers_v2.cmd

Then install:
  Run_Gaming_Drivers_v2.cmd

The installer self-elevates through the PowerShell script.
The CMD waits for the elevated process and reports its actual exit code.
Install also repeats a complete six-step precheck in the same run, even if
you already ran Audit separately. If any precheck fails, no driver installation
starts. Audit continues to report the remaining steps after a step failure.

The temporary driver-specific Windows Update/PnP values are snapshotted before mutation and restored to their exact pre-run state after either success or failure. A small recovery JSON is kept under C:\ProgramData\GamingDriverInstaller only while the guard is active, so a later run can recover stale state after an interrupted process. Automatic Windows Update remains disabled by design (NoAutoUpdate=1). After a successful install pass, reboot once and run the CS2 baseline launcher.

AUDIT AND DOWNLOAD DECISIONS
----------------------------
[WOULD INSTALL] in Audit means the driver would be installed in Install mode;
Audit downloads that package to verify it, but does not run any installer.
AMD chipset and NVIDIA compare installed and official versions BEFORE a
package download. The ZOWIE archive is bundled locally, never fetched from
the web.
For an ASUS INF or AMD iGPU, the vendor's release label may differ from the
matching INF's DriverVer. On a first run with no trusted local archive, an
exact version/INF decision requires downloading and inspecting that package.
The same ZIP/EXE is reused on later Audit/Install runs after hash validation.

Audit does not run installers or bind drivers, but it writes logs/cache and
may download/extract the AMD, ASUS and NVIDIA packages, potentially several GB.
AMD chipset and NVIDIA download signatures are checked. NVIDIA's outer EXE is
also tested for archive extraction and a signed inner setup.exe. Later Install
can still fail because installer runtime, PnP ranking or a reboot-dependent
binding cannot be proven without performing the installation on Windows.

POST-INSTALL CHECK
------------------
PnPUtil can return successfully after staging a driver that Windows does not
bind because a different driver ranks higher. The script re-queries provider,
version, INF and PnP problem code before reporting a device verified. The
AMD chipset package is verified by its registered package version, NOT by
asserting that every individual chipset component was tested. If a step
reports a verification failure, reboot and audit before attempting a retry.

VERSION POLICY
--------------
This package intentionally resolves current official releases at runtime.
Running it after a later vendor release is NOT a reproducible frozen baseline.
Record installed versions in the log and test frame-time behavior before
declaring a new competitive baseline.

FAIL-CLOSED BEHAVIOR
--------------------
Install will STOP rather than guess when (Audit continues to collect failures):
- motherboard/CPU identity does not match
- an ASUS package cannot be resolved or its hash does not match
- ASUS SHA-256 cannot be read/verified
- a downloaded executable has an unexpected Authenticode signer
- an expected device has no matching INF in the official package
- several INFs contain the same matching hardware model entry
- PnPUtil stages an INF but Windows does not bind it to the expected device
- the NVIDIA self-extracting EXE cannot be extracted to a signed setup.exe
- NVIDIA's official lookup does not return a usable Game Ready result

This is deliberate: a post-format baseline should prefer a visible failure over
silently installing an unknown driver.
