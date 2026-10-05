# System profile

This repository is intentionally tied to one physical PC and its peripherals. Hardware identity is part of the configuration: a setting that is useful here is not assumed to be useful on another machine.

## Current PC

| Component | Current hardware |
|---|---|
| CPU | AMD Ryzen 7 9800X3D |
| Memory | G.Skill F5-6400J3239G16GX2-TZ5RK, 2×16 GB DDR5; original heatspreaders removed |
| GPU | MSI GeForce RTX 3080 12 GB LHR |
| Motherboard | ASUS ROG STRIX B850-I GAMING WIFI |
| SSD | Samsung 990 Pro 1 TB |
| CPU cooler | DeepCool LT720 |
| Case | Lian Li LANCOOL III |
| PSU | FSP Hydro PTM PRO 1200W |
| UPS | Schneider Electric Easy UPS SRVS3KI |

### Memory continuity

The DDR5 kit did **not** change during the platform migration. The old Z690 notes called the memory only “Hynix A-Die 2×16”; that refers to the same physical G.Skill F5-6400J3239G16GX2-TZ5RK kit now used with the 9800X3D/B850-I system.

## Peripherals

| Device | Baseline |
|---|---|
| Monitor | BenQ ZOWIE XL2566X+; 400 Hz |
| Mouse | Logitech G PRO X Superlight 2 DEX; 1600 DPI; wireless 2000 Hz; LOD High |
| CS2 sensitivity | `0.475`; zoom ratio `0.9` |
| Keyboard | Wooting 80HE; Tachyon Mode / True 8K polling; source UI state normalized in `REFERENCE_STATE.md` |
| Keyboard actuation | general keys 0.5 mm; Ctrl/Shift 0.3 mm; WASD 0.1 mm |
| Rapid Trigger | WASD + Ctrl at 0.1 mm |
| Headset | Corsair HS80 |
| Mousepad | SteelSeries QcK+ |

## Current CS2 display reference

The submitted CS2 screenshots were reviewed and normalized into `REFERENCE_STATE.md`. Their captured display/video state was:

- fullscreen
- 4:3 / 1280×960
- 400 Hz
- V-Sync disabled
- G-Sync disabled in the captured CS2 state
- NVIDIA Reflex disabled in the captured CS2 state
- uncapped in-game FPS (`fps_max 0` / menu cap 200 in the screenshot)
- 8× MSAA
- low global shadows with dynamic shadows set to All
- low model/texture, shader and particle detail
- bilinear texture filtering
- ambient occlusion disabled
- HDR Quality
- FSR disabled

These are a **system snapshot**, not a claim that every value is globally optimal. Any future change should be tested against this machine and then recorded deliberately.

## Legacy platform

The previous motherboard/CPU platform was:

- Intel Core i9-13900KF
- Gigabyte Z690 Tachyon
- same physical G.Skill/Hynix A-Die 2×16 GB DDR5 kit
- RTX 3080
- Samsung 990 Pro 1 TB
- Lian Li GALAHAD 360
- Lian Li LANCOOL III
- FSP Hydro PTM PRO

Its BIOS exports are isolated in `.bios/legacy/Z690-Tachyon/`.

## Profile

Steam: https://steamcommunity.com/id/officialdescrip/
