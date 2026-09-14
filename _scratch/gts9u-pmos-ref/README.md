# postmarketOS for the Samsung Galaxy Tab S9 Ultra Wi-Fi

A **mainline-first** postmarketOS port for the Samsung Galaxy Tab S9 Ultra
Wi-Fi (**SM-X910**, codename `gts9uwifi`, Qualcomm Snapdragon 8 Gen 2 / SM8550
"kalama"), running upstream Linux **7.2-rc3**.

The goal is a real Linux desktop on the tablet—native DRM/KMS, Mesa/Turnip and
standard desktop software—without depending on Samsung's downstream 5.15
kernel, which is used only as hardware documentation.

## Status

The physically validated v1.71 baseline boots GNOME on Wayland at
2960×1848@120 Hz with Adreno 740 acceleration, touch, Wi-Fi, Bluetooth, audio,
motion sensors, lid wake, USB host and USB-C DisplayPort. The root filesystem
lives on microSD while Samsung ABL loads the boot images from internal UFS;
TWRP, Download Mode and Odin remain recoverable.

The remaining work is limited to charging polish, a few untested USB paths and
unsupported accessories/sensors. See
[the detailed hardware status](docs/hardware-status.md) for implementation
details, limitations and the invariants another distribution must preserve.

## Hardware support

| Component | Status | Notes |
|---|---|---|
| **Display** | ✅ | Native 2960×1848@120, DSI command mode + DSC + TE |
| **Desktop** | ✅ | GNOME/Wayland by default; XFCE/Xorg also available |
| **GPU** | ✅ | Adreno 740, Mesa/Freedreno/Turnip, OpenGL 4.6 |
| **Backlight / blanking** | ✅ | Manual brightness and screen blanking |
| **Touchscreen** | ✅ | Goodix Berlin / GT9916 |
| **Buttons** | ✅ | Power and volume |
| **UFS / microSD** | ✅ | UFS boot partitions; rootfs on microSD |
| **Wi-Fi** | ✅ | WCN7850 with ath12k |
| **Bluetooth** | ✅ | Persistent bonds and A2DP audio |
| **Speakers / microphones** | ✅ | Four speakers and DMIC capture via UCM |
| **Battery telemetry** | ✅ | Level, voltage, current and temperature |
| **USB-PD/PPS charging** | 🟡 | Functional; low-charge stability needs revalidation |
| **Suspend / resume** | ✅ | Deep suspend, power button and lid wake |
| **USB gadget / host** | ✅ | RNDIS, powered and bus-powered hubs, HID and storage |
| **Ethernet / UAS** | 🟡 | RTL8153 enumerates; traffic and UAS remain untested |
| **USB-C DisplayPort** | ✅ | 1080p60 validated, including retained-dock boot |
| **Motion sensors** | ✅ | Accelerometer, gyroscope, magnetometer and autorotation |
| **Book cover** | ✅ | Hall switch closes and wakes the tablet |
| **Ambient light** | ❌ | STK31610 is discovered but emits no lux samples |
| **S Pen / keyboard cover** | ❌ | Hardware identified; drivers not integrated |
| **Fingerprint / haptics** | ❌ | Not brought up |
| **Flash / cameras** | ❌ | Not started |
| **Speaker protection** | ❌ | Cirrus protection DSP firmware not loaded |
| **Modem** | — | Not applicable to the Wi-Fi-only model |

Every ✅ entry was tested on the physical tablet. A driver merely binding is
not considered proof that a subsystem works.

## Current focus

postmarketOS v1.71 is frozen as the stable, reproducible hardware baseline.
Future work can revalidate low-battery charging, test UAS/Ethernet and add the
remaining accessories, but the immediate project direction is to reuse this
mainline hardware support with an Ubuntu 24.04 LTS userspace. Detailed current
state and migration guidance live in
[docs/hardware-status.md](docs/hardware-status.md).

## Documentation

> The documents below are written in **Spanish**. This README is the only
> English-language document in the repository.

| Document | Contents |
|---|---|
| [docs/hardware-status.md](docs/hardware-status.md) | Canonical current hardware matrix, limits and distro-migration invariants |
| [docs/development-notes.md](docs/development-notes.md) | Durable hardware facts, safety rules and the “do not retry” inventory |
| [docs/porting-log.md](docs/porting-log.md) | Detailed chronological engineering log |
| [docs/boot-strategy.md](docs/boot-strategy.md) | Current boot chain, installation model, risks and recovery |
| [docs/panel-ana38407-bringup.md](docs/panel-ana38407-bringup.md) | Native panel bring-up |
| [docs/upstream-audit.md](docs/upstream-audit.md) | Historical initial upstream audit |
| [docs/testing-mainline-v0.md](docs/testing-mainline-v0.md) | Historical v0.6 test procedure; not for current installation |

## Layout

```text
├── pmaports/device/testing/   Kernel, device and firmware Alpine packages
├── scripts/                   Reproducible build, packaging and firmware tools
├── configs/                   Audio, display, Bluetooth, Wi-Fi and boot overlays
├── docs/                      Current reference and chronological history
├── artifacts/                 Generated output only; intentionally not versioned
└── work/                      Disposable local scratch space
```

## Installing

Installation always has two steps:

1. **Write the rootfs image to a microSD.** First remove old partition metadata
   with `sgdisk --zap-all`, then write the image and verify the data read back
   from the card before rebooting. The root partition expands on first boot.
2. **Flash the TWRP ZIP.** It writes `boot`, `init_boot`, `vendor_boot` and
   `dtbo`, then applies the matching overlay to the microSD. GPU, ADSP and audio
   firmware are supplied by that overlay, so a new card is incomplete until
   this second step finishes.

The exact boot chain, safe iteration procedure and recovery paths are in
[docs/boot-strategy.md](docs/boot-strategy.md).

### GNOME and GDM

GDM 47+ asks `systemd-userdbd` to allocate per-display greeter users. Alpine
builds systemd without userdbd, so the postmarketOS device package pre-creates
those accounts. This is an Alpine-specific workaround and should not be copied
to another distribution unless its native GDM exhibits the same failure.

## Firmware

This repository contains **no proprietary firmware**. Samsung and Qualcomm
blobs—Wi-Fi, Bluetooth, GPU, ADSP, CS35L45 and audio topology—are extracted
from the owner's device or source package by `scripts/stage-stock-*.sh`. The
helpers verify pinned checksums; generated images and ZIP files are ignored.

## Licensing

The project default is **MIT** (see [LICENSE](LICENSE)), except where a file's
SPDX header states otherwise. That per-file header always takes precedence.

| Part | Licence | Reason |
|---|---|---|
| Kernel drivers and patches | `GPL-2.0-only` | Derivative works of Linux |
| Device tree | `BSD-3-Clause` | Matches upstream Qualcomm DTS convention |
| Packaging, scripts, configuration and documentation | `MIT` | Compatible with pmaports and kernel contribution workflows |
| Samsung/Qualcomm firmware | Proprietary | Never redistributed |

## Contributing

Contributions are welcome, especially for unsupported hardware. Keep two
project rules:

- **No live-only fixes:** every change belongs in a reproducible DTS, config,
  package or script.
- **Verify on hardware:** a successful probe is not a functional test.
