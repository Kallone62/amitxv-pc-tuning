# Reference state

This file records the current source-of-truth settings that other layers are expected to follow.

## CS2

- Resolution: **1280×960**, 4:3 stretched
- Sensitivity: **0.475**
- Zoom sensitivity ratio: **0.9**
- `fps_max`: **0**
- VSync: disabled
- NVIDIA G-SYNC: disabled in the recorded game state
- NVIDIA Reflex: disabled in the recorded game state

### Current crosshair

The current root `Game/autoexec.cfg` uses the post-September-2026 pixel crosshair variables:

```cfg
cl_crosshair_drawoutline "0"
cl_crosshair_recoil "false"
cl_crosshair_t "false"
cl_crosshairdot "false"
cl_crosshairstyle "4"
cl_crosshair_length "2"
cl_crosshair_gap "0"
cl_crosshair_thickness "2"
cl_crosshaircolor_r "0"
cl_crosshaircolor_g "255"
cl_crosshaircolor_b "0"
cl_crosshaircolor_a "255"
cl_crosshair_screen_height "960"
```

This root autoexec is the CS2-specific authority. The KovaaK V1 package is synchronized to it.

## Desktop mouse baseline

For the intended 1600-DPI setup:

- `MouseSensitivity=4`
- `MouseSpeed=0`
- `MouseThreshold1=0`
- `MouseThreshold2=0`

This disables the Windows acceleration/EPP path used by the baseline while retaining the intended desktop pointer-speed setting.

## Mouse

Logitech Superlight 2 DEX:

- 1600 DPI
- 2000 Hz
- LOD High

## Keyboard

Wooting 80HE:

- general actuation: 0.5 mm
- Ctrl / Shift: 0.3 mm
- WASD: 0.1 mm
- Rapid Trigger: WASD / Ctrl 0.1 mm

## Display

BenQ XL2566X+; recorded CS2 display state uses 1280×960 fullscreen at 400 Hz.

Raw setup screenshots remain part of the audited source package; the repository keeps this text reference instead of duplicating large screenshots in Git history.
