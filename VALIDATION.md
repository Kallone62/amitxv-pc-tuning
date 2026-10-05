# Snapshot validation

Validation date: **2026-10-06**

Source archive SHA-256:

`266e2edc9a1d06edb6f4789770a7d4dc4ce49cde60f4e3bd7529285d73f2c5dc`

This repository snapshot was reviewed before deployment. The review distinguishes static/package validation from checks that can only be proven on the actual Windows machine.

## Passed static/package checks

- 32 source files were present in the submitted `SSD Setup` archive.
- No obvious passwords, API keys, private keys, webhook URLs or user-profile absolute paths were found in the text/script scan.
- All root launchers reference files that are present in the package.
- Batch-file `goto` / local-label references resolve within their files.
- The gaming driver installer explicitly preflights the current platform: ASUS ROG STRIX B850-I, Ryzen 7 9800X3D and NVIDIA PCI device `DEV_220A` for the RTX 3080 12 GB target.
- The bundled ZOWIE XL2566X+ monitor archive hash is exactly the SHA-256 expected by `.drivers/README.txt` and the driver script: `E8B600BE155F85BA417BEE80EAE6065848885F9E72A331B19D17D53FD9751D38`.
- ZOWIE still publishes the XL2566X+ V001 WHQL driver for Windows 10/11.
- ASUS still publishes the B850-I support stack used by the driver's online resolver, including Intel I225/I226 LAN and Realtek UCM packages.
- AMD's B850 chipset and Ryzen 7 9800X3D driver pages, NVIDIA's GeForce driver page, and the ASUS B850-I support page remain live official sources.
- `Training/KOVAAKS_CS2_STANDARD_V1.zip` was extracted and every entry listed in its internal `SHA256SUMS.txt` passed verification.

## Runtime validation still required on the target PC

Static review cannot prove Windows runtime behavior. The following are intentionally left to the actual machine:

- PowerShell parsing/execution under 64-bit Windows PowerShell 5.1 and the installed Windows build
- exact PnP instance IDs and driver binding/ranking after install
- current vendor page HTML/API formats used by the online resolver
- effective registry/policy state after reboot
- device-disable safety against the live topology
- FACEIT security/preflight state
- frametime, DPC/ISR, network and input behavior after changes

The scripts already contain many preflight, audit, idempotency and post-change verification checks; those checks remain the authority during real deployment.

## Known configuration drift — preserved, not silently “fixed”

The root `Game/autoexec.cfg` and the embedded KovaaK's standard are not identical snapshots.

The root CS2 autoexec currently uses a different crosshair block than the `KOVAAKS_CS2_STANDARD_V1` source snapshot. The KovaaK package still contains the older/source CS2 crosshair reconstruction (`size 1 / gap -4 / thickness 1` asset), while the root autoexec uses the newer visible block (`length 2 / gap 0 / thickness 2`, green custom RGB values).

This mismatch is documented rather than rewritten because the archive itself does not establish which crosshair should overwrite the other. Sensitivity (`0.475`), zoom ratio (`0.9`), resolution (`1280×960`) and uncapped CS2 FPS remain aligned between the important source snapshots.

## BIOS status

The only BIOS files in the submitted archive were from the old Z690 Tachyon platform. They have been moved into `.bios/legacy/Z690-Tachyon/` without changing their content. The current 9800X3D / B850-I BIOS baseline is intentionally marked pending.

## Repository normalization of source screenshots

The source archive contained seven non-executable JPG/PNG UI screenshots for CS2, Wooting and Logitech state. They were inspected during validation, but the GitHub repository stores their relevant visible settings in `REFERENCE_STATE.md` instead of committing the large binaries. Their original SHA-256 values are retained there, and the complete submitted archive is anchored by the source SHA-256 at the top of this file.

This normalization does **not** modify the operational scripts, configuration files, legacy BIOS exports, bundled monitor-driver asset, or KovaaK's deployment package.
