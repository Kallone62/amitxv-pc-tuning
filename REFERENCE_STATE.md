# Reference state normalized from source screenshots

The submitted `SSD Setup` archive included seven non-executable UI screenshots. They were reviewed before deployment and are intentionally represented here as text rather than committed as large binary history. This makes changes reviewable while preserving the settings that matter for reconstruction.

The original source archive SHA-256 and package-level validation are recorded in [`VALIDATION.md`](VALIDATION.md). Original screenshot SHA-256 values are listed at the bottom of this file.

## CS2 video state

Source: `Game/video1.jpg`, `Game/video2.jpg`, `Game/video3.jpg`.

- Display mode: **Fullscreen**
- Aspect ratio: **Normal 4:3**
- Resolution: **1280×960**
- Refresh rate: **400 Hz**
- Brightness: **93%** in the captured display page
- Boost Player Contrast: **Enabled**
- V-Sync: **Disabled**
- NVIDIA G-Sync: **Disabled** in the captured CS2 state
- NVIDIA Reflex Low Latency: **Disabled** in the captured CS2 state
- Maximum FPS in game: **0 / uncapped**
- Maximum FPS in menus: **200**
- Current video preset: **Custom**
- Multisampling Anti-Aliasing: **8× MSAA**
- Global Shadow Quality: **Low**
- Dynamic Shadows: **All**
- Model / Texture Detail: **Low**
- Texture Filtering Mode: **Bilinear**
- Shader Detail: **Low**
- Particle Detail: **Low**
- Ambient Occlusion: **Disabled**
- High Dynamic Range: **Quality**
- FidelityFX Super Resolution: **Disabled**

This is a captured working state for this machine, not a claim that every option is universally optimal.

## Logitech G PRO X Superlight 2 DEX

Source: `Mouse/onboardmemory.png`.

- Onboard profile: **Slot 1**
- DPI X/Y: **1600 / 1600**
- Lift-off distance: **High**
- Wired report rate: **1000 Hz**
- Wireless report rate: **2000 Hz**
- Current competitive baseline uses the wireless **2000 Hz** state
- BHOP option shown in the source UI: **Disabled**

## Wooting 80HE

Sources: `Keyboard/80he1.png`, `Keyboard/80he2.png`, `Keyboard/80he3.png` plus the user-defined baseline for this system.

- Tachyon Mode: **Enabled**
- Scan rate shown by Wootility: **8000 Hz**
- True 8K polling: **Active**
- General-key actuation: **0.5 mm**
- Left Shift actuation: **0.3 mm**
- Left Ctrl actuation: **0.3 mm**
- WASD actuation: **0.1 mm**
- Rapid Trigger baseline: **0.1 mm on WASD + Ctrl**
- Wootility profile identifier: `90b41feb17ab6cc810dac967b1477fea38f8`

The Wooting screenshots are useful source evidence, but the user-defined baseline above is the authoritative intended state when a screenshot label and the actively maintained profile description differ.

## Original visual-reference SHA-256

- `58be6df738faeb6b017d08b5b41a0ec7cbfb06ecf42c7c4d4e52f698c4d3e581`  `Game/video1.jpg`
- `9ee8646c9d24f824ee5b47311edc95db55b02ad24f68a308cc16b7ef7bd31b2c`  `Game/video2.jpg`
- `5e08c778afc31e0d6b6c1254b7c2554d51f050ecd5791f7ce2ca21d71ee4e3c7`  `Game/video3.jpg`
- `d0b1b96304a84c69230c06a068548cb110fde19e4d688cd70bff4cdfee2768ce`  `Keyboard/80he1.png`
- `a592b134e6b17a150640a623758f14d20f552659a7c5ba47c75647c2c64c51e4`  `Keyboard/80he2.png`
- `cbf41c39b1d1aa50944af569f68c63f8906d62c8fe454f2eb16823ba6f83796c`  `Keyboard/80he3.png`
- `6727f38396a56232c426c9057e8412ba169762e8a72681cd504b16e64dc424be`  `Mouse/onboardmemory.png`
