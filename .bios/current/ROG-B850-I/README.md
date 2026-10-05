# Current BIOS baseline — ASUS ROG STRIX B850-I / Ryzen 7 9800X3D

Status: **pending capture and validation**.

This folder is reserved for the current machine's BIOS configuration. The existing Z690 Tachyon exports are intentionally isolated under `../../legacy/Z690-Tachyon/` and are not a source of direct values for this platform.

When this baseline is added, it should record at minimum:

- motherboard BIOS version / AGESA
- EXPO/manual memory configuration and UCLK/MCLK/FCLK relationship
- SoC / memory-controller related voltages actually used
- PBO / Curve Optimizer / boost controls, if any
- CPPC / preferred-core and power-management decisions
- virtualization / IOMMU / Secure Boot / TPM settings required by the current FACEIT baseline
- onboard-device enable/disable state
- PCIe / ReBAR / storage settings
- fan/pump controls relevant to repeatability

Values should be added only after they are confirmed on this exact board/BIOS and tested against the current Windows + CS2 baseline.
