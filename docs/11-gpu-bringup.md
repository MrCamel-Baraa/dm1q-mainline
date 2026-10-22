# 11 - Adreno 740 (GPU) bring-up

Started 2026-10-18. Goal: the msm driver binds the GPU, the GMU boots, no SMMU faults, no resets; then Mesa
freedreno; then Plasma Mobile on the GPU (a working GPU removes llvmpipe, whose SVE JIT code kills every GL client on
this phone: docs/10 section 9.2).

Labels: **FACT** = read in a file or seen on the phone, **INFERENCE** = reasoned, not verified. Nothing in this
document has been run on the phone yet (state at the end of the first session: research and tooling only).

## 1. Status

| Step | State |
|---|---|
| Upstream + analog research (this document, sections 2-5) | done 2026-10-18 |
| Baseline probe `scripts/collect-phone-state.sh gpu-baseline --gpu` | run 2026-10-18 22:35, results in section 9 |
| Firmware (SQE, GMU, generic zap) on the PC from linux-firmware | done 2026-10-19, `../_scratch/dm1q-gpu-fw/` (not in the repo), section 9 |
| Vendor-signed zap pull (TWRP) | NEEDED: the secure world refused the generic zap (9.7); `scripts/pull-gpu-vendor-firmware.sh` |
| DT-only image set `../_scratch/pmos-v19-gpu-bind` (`&gpu` okay, no firmware on the phone) | built and verified on the PC 2026-10-19, NOT flashed |
| Power-up test S3: `sqe-gmu` OK (9.6); `full` with the generic zap refused by the secure world (9.7) | done, GPU not yet executing |
| Mesa, Plasma on GPU | not done |

## 2. What upstream has (FACT, kernel tree `../_scratch/linux-build/full`, 7.3-rc3)

- `arch/arm64/boot/dts/qcom/sm8550.dtsi`
  - `gpu: gpu@3d00000`, `compatible = "qcom,adreno-43050a01", "qcom,adreno"`, **`status = "disabled"`**; regs
    `3d00000/0x40000`, `3d9e000` (cx_mem), `3d61000` (cx_dbgc); IRQ SPI 300; `iommus = <&adreno_smmu 0 0x0>, <&adreno_smmu 1 0x0>`;
    `qcom,gmu = <&gmu>`; interconnect `gfx-mem`; child `gpu_zap_shader: zap-shader { memory-region = <&gpu_micro_code_mem>; }`
    (no `firmware-name`: every board must add one); OPP table 220 ... 680 MHz with `qcom,opp-acd-level`
    (comment in the dtsi: "Speedbin needs more work on A740+, keep only lower freqs").
  - `gmu: gmu@3d6a000`, `qcom,adreno-gmu-740.1`; regs gmu `3d6a000`, rscc `3d50000`, gmu_pdc `b280000`; IRQs hfi 304 / gmu 305;
    clocks gpucc AHB/CX_GMU/CXO/HUB_CX_INT/DEMET + gcc DDRSS_GPU_AXI/GPU_MEMNOC_GFX; power domains gpucc CX and GX GDSC;
    `iommus = <&adreno_smmu 5 0x0>`; `qcom,qmp = <&aoss_qmp>`. Enabled by default (no status line); no driver of its own binds
    it (msm takes it from the GPU's bind), so "unbound" is the normal state.
  - `gpucc: clock-controller@3d90000`, `qcom,sm8550-gpucc`, enabled. `adreno_smmu: iommu@3da0000` enabled (clocks from gpucc + gcc,
    power domain gpucc CX).
  - reserved memory `gpu_micro_code_mem: gpu-micro-code-region@9b09a000`, size 0x2000, `no-map`.
- `sm8550-qrd.dts` / `sm8550-hdk.dts`: `&gpu { status = "okay"; }; &gpu_zap_shader { firmware-name = "qcom/sm8550/a740_zap.mbn"; };`
- `drivers/gpu/drm/msm/adreno/a6xx_catalog.c`, chip id `0x43050a01`: `a740_sqe.fw`, `gmu_gen70200.bin`, default zap name
  `a740_zap.mdt`; no `.speedbins` for A740.
- Kconfig: `DRM_MSM` selects QCOM_SCM, QCOM_PAS, QCOM_MDT_LOADER, DRM_EXEC/GPUVM/SCHED, WANT_DEV_COREDUMP; it depends on
  QCOM_AOSS_QMP, QCOM_LLCC, QCOM_COMMAND_DB, QCOM_SMEM (`|| X=n`): a provider built as a module caps msm at "=m" (it cannot be
  "=y"), which is where we already are. The Sept-24 direct build `../_scratch/linux-build/out/.config` has QCOM_PAS=y, QCOM_SCM=y,
  ARM_SMMU(_QCOM)=y, QCOM_AOSS_QMP=y, QCOM_RPMHPD=y, INTERCONNECT_QCOM_SM8550=y, DRM_MSM=m, SM_GPUCC_8550=m, QCOM_MDT_LOADER=m,
  QCOM_LLCC=m. The RUNNING r7 config is to be read from the phone (`gpu.txt` section 2), not assumed.

## 3. What Samsung's side says (FACT)

- Downstream gpulist (`../_scratch/samsung-opensource-s911b/kernel/vendor/qcom/opensource/graphics-kernel/adreno-gpulist.h`),
  `gen7_2_0` and `gen7_2_1` (both A740 variants): `sqefw_name = "a740_sqe.fw"`, `gmufw_name = "gmu_gen70200.bin"`, `zap_name = "a740_zap.mbn"`,
  `gmu_fw_version` 4.1.0. Same names as mainline, so the firmware names are consistent across both trees.
- Downstream DT overlays (`../_scratch/crdroid-dm1q-dts/qcom/graphics/gpu/`): `kalama-gpu` (gen7-2-0) has power levels up to 746 MHz (NOM),
  719, 680 ...; `kalama-v2-gpu` (gen7-2-1) tops out at **719 MHz (SVS_L2)** and its lower levels and ACD values are exactly mainline's OPP table.
  Which overlay this phone gets is NOT known (INFERENCE: v2, the "for Galaxy" bin, since the sibling Tab S9 Ultra stock bin 0 is 719 MHz).
  Start with mainline's table (max 680 MHz); 719 MHz is a later, separate decision.
- Live reserved-memory map of this phone (`notes/2026-09-21-v2-bootloop/live-reserved-memory.txt`): `gpu_micro_code_region@9b09a000`,
  size 0x2000, no-map = mainline's `gpu_micro_code_mem` byte for byte. `dts/dm1q/dm1q.dts` does not delete it, so it is inherited.
  There is no other GPU carveout in the live map; `uh-heap` / `uh-guest` (the Samsung secure regions that caused hard resets, docs/05) are
  already reserved in dm1q.dts and are not GPU memory. `hwfence-shmem@e6440000` exists only downstream (INFERENCE: not used by mainline msm).

## 4. Same-SoC analog: Tab S9 Ultra (`../_scratch/gts9u-pmos-ref/docs/porting-log.md`, sessions 70-76, lines ~2810-3380)

FACT about what that port did and saw (different device, same SoC family, same Samsung secure-world stack):

- DT: `&gpu { status = "okay"; zap-shader { firmware-name = "qcom/a740_zap.mdt"; }; }` plus an OPP override adding 719 MHz (Samsung stock bin 0).
  The zap shader is **Samsung's own signed MDT set** (`a740_zap.mdt`, `.b00`, `.b01`, `.b02`) taken from the tablet's stock vendor image
  (`firmware/` directory); `a740_sqe.fw` and `gmu_gen70200.bin` came from the same directory. Their hashes are for that tablet and are not
  reused here.
- Their first boot with `&gpu` enabled failed with -110 until `SM_GPUCC_8550` was a driver (the symbol they first invented,
  `CONFIG_GPUCC_SM8550`, does not exist). On dm1q the gpucc module is already bound and `3da0000.iommu` already probes (docs/09), so this
  specific failure should not repeat (INFERENCE for the ordering with gpucc as a module, see R4).
- With firmware: `Loaded GMU firmware v4.1.9`, `gpu-initialized: 1`, `revision: 43050a01`, `eglinfo` over GBM: freedreno FD740, OpenGL 4.6,
  no hang. Missing firmware only showed up as `failed to load a740_sqe.fw` when a client opened the render node.
- Under Xorg/glamor on top of simpledrm they got `hangcheck` loops and an Xorg SEGV (their reading: a cross-device path; not shown for dm1q).
- Unified msm device (display and GPU in one DRM card, what KWin will use here): `glmark2` ran at 123 FPS but the OLED stayed black; they
  also had a separate warm-reboot problem (first panel init reads id `00 00 00`, black until a DSI off/on cycle). They ended with
  `msm.separate_gpu_kms=1` plus reverse PRIME. INFERENCE: their black panel was the panel-reinit problem, not the unified master (see R5).

## 5. Driver mechanics that decide how we test (FACT, 7.3-rc3 source read 2026-10-18)

1. **Bind is cheap, power-up is lazy.** At component bind `a6xx_gpu_init` -> `a6xx_gmu_init` only gets clocks, allocates the GMU buffers through the
   adreno SMMU, maps rscc, requests IRQs, attaches the CX/GX power domains, gets the AOSS QMP mailbox, reads the OPPs. No firmware, no power.
2. **`msm_open()` calls `load_gpu()`** (comment in the source: "load gpu on open ... to avoid the requirement of having firmware in the
   initrd"). `adreno_load_gpu()` then: loads `a740_sqe.fw`; `pm_runtime_get_sync` (GMU resume, which loads `gmu_gen70200.bin` and boots the GMU);
   `msm_gpu_hw_init` -> `a6xx_zap_shader_init` (zap MDT into the 0x2000 carveout, PAS auth); debugfs.
3. **What counts as an "open".** Any DRM file open on the unified device: renderD128, card1 (so the `drm-fill` tests and KWin), and, INFERENCE from
   `drm_file_alloc()` calling `driver->open`, the in-kernel fbdev client set up when msm binds. This fits a FACT already in docs/09: dmesg
   shows `no GPU device was found` at boot, which is printed by `adreno_load_gpu()` itself. Consequence: **once `&gpu` is enabled and the
   firmware can be found, the GPU power-up runs by itself on every boot when msm.ko loads.**
4. **Failure classes.**
   - SQE / GMU / zap file missing: `request_firmware` error, `load_gpu` returns NULL or `hw_init` returns -ENOENT. Safe; retried at every open.
   - `zap-shader` child missing, its memory-region unresolvable, or PAS returning -EOPNOTSUPP: `zap_available = false`, and `a6xx_hw_init`
     writes `RBBM_SECVID_TRUST_CNTL` itself. The source comment says "if you guessed wrong ... a permissions violation will soon follow".
     On this phone that is the same class as the `TZBSP_ERR_FATAL_NOC_ERROR` resets documented for protected regions (INFERENCE). Never
     boot a GPU-enabled DT without the `zap-shader` child carrying our `firmware-name`.
   - Wrong-signature zap: `Unable to authorize the image`, GPU left off (safe error).
   - GMU / HFI timeout: error, GPU left off.
5. **Custom firmware path.** `firmware_class.path` is a writable module parameter (`module_param_string(path, ..., 0644)`), searched before the
   standard directories, and honoured by both `request_firmware_direct` (zap `firmware-name` branch) and `qcom_mdt_load` (the `.bNN` pieces).
   So the blobs can live in a staging directory that is NOT on the default search path, and the power-up can be started by hand
   from ssh (`echo DIR > /sys/module/firmware_class/parameters/path`, open a render node once, then RESTORE the saved value: on this phone it is `/lib/firmware/postmarketos`, not empty, section 9). A TZ reset then costs one
   reboot instead of a boot loop, and nothing is written under `/lib/firmware`, so no apk trigger can regenerate `/boot/initramfs-extra`
   (docs/06 rule 3 is about the apk trigger; INFERENCE that plain files elsewhere cannot fire it; the probe records the initramfs-extra
   hash so this is checked, not assumed).

## 6. Risks and open questions

- **R1 firmware source.** Only the **zap shader** is device-specific: it is authenticated by the secure world (PAS), and the msm source says
  such firmware may be "signed with (potentially) device specific keys" (FACT, `adreno_gpu.c`); the Tab S9 Ultra DTS says the zap "must be
  signed for this device's TrustZone" and uses Samsung's own (FACT). SQE and GMU microcode are loaded by the kernel directly, no
  authentication, and are the same bytes as linux-firmware's (FACT per the gts9u staging script comment), so they can come from linux-firmware.
  Whether linux-firmware's generic `qcom/sm8550/a740_zap.mbn` is rejected by this phone is INFERENCE: none of the gts9u files say they tried it.
  A rejected image only logs `Unable to authorize the image` (safe), so **try the generic one first** (no TWRP trip); pull the phone's own
  zap from the vendor partition (logical partition inside `super`, mountable in TWRP; expected names `a740_zap.mdt`, `.b00`-`.b02`) only if
  PAS rejects it. Nothing pulled yet.
- **R2 carveout size.** `qcom_mdt_get_size()` of the zap MDT must be <= 0x2000 (8 KiB) or the driver logs "memory region is too small" (-E2BIG). Check at pull time.
- **R3 sync_state.** Probing gpu/gmu removes them from the "pending" lists of providers (docs/09 shows `sync_state() pending` lines for gpu_cc and
  3d6a000.gmu). Whole-provider sync_state still waits for the other consumers (cdsp, adsp, venus, camera ...), so a big change in rail/bandwidth
  votes is not expected (INFERENCE; the second boot's dmesg will tell).
- **R4 gpucc / msm are modules.** If the msm master binds before gpucc is ready, `a6xx_gmu_init` returns -EPROBE_DEFER and the whole display
  aggregate retries later; worst case the display comes up late. If it stalls, `CONFIG_SM_GPUCC_8550=y` (kernel change, needs the sudo build and
  `refresh-phone-modules.sh`). INFERENCE; the first DT-only boot decides.
- **R5 unified master and the panel.** Compare with the first `drm-fill` colours that already worked on v17; run the same test after the GPU
  node is on, and watch the screen (the Tab S9 Ultra black-panel report, section 4).
- **R6 OPP.** Start with mainline's 680 MHz table. 719 MHz and speedbin handling are a later change.
- **R7 llvmpipe SVE problem** is independent of the kernel: it is why the GPU path matters, not something this work fixes.

## 7. Test ladder

Each step has a rollback; the known-good set is `../_scratch/pmos-v17-splash-iommu` (v18 init_boot logger on top). Every flash is announced first.

- **S0 baseline (no change on the phone).** `bash scripts/collect-phone-state.sh gpu-baseline --gpu`, read `notes/<date>-gpu-baseline/gpu.txt`.
  It lists (never opens) the DRM nodes. Answers: running config (SM_GPUCC_8550, QCOM_PAS, MDT loader, FW_LOADER options), what is loaded/bound,
  whether any a740/gmu/zap file exists, whether `firmware_class.path` is empty, the initramfs-extra fingerprint, installed Mesa packages.
- **S1 firmware on the PC (no phone write) - DONE 2026-10-19, section 9.** Get `a740_sqe.fw`, `gmu_gen70200.bin` and the generic `qcom/sm8550/a740_zap.mbn` from
  linux-firmware (extract from the Alpine package on the PC, do NOT apk-install on the phone), into `../_scratch/dm1q-gpu-fw/` (never committed).
  Fallback, now needed (9.7, the secure world refused the generic zap): TWRP + adb pull of the phone's own `a740_zap.*` (+ SQE/GMU for comparison) from the vendor partition with
  `scripts/pull-gpu-vendor-firmware.sh` (device side `scripts/twrp-find-gpu-fw.sh`; read-only: it mounts the vendor partition `-o ro` in a RAM-disk directory if TWRP has not, verifies size and
  sha256 of every pull, unmounts again; output `../_scratch/dm1q-gpu-fw-vendor/`, never committed; PC test `scripts/test-pull-gpu-vendor-firmware.sh`, 46 checks). The expected names are INFERENCE
  (`a740_zap.mdt` + `.b00`-`.b02`, as on the Tab S9 Ultra, or `a740_zap.mbn`); the search is `a7*_zap*`, `a740*`, `gmu_gen70*`, `a7*_sqe*` under `/vendor` to depth 6. If the phone's vendor has no zap, the
  other source is Samsung's stock S911B firmware (super -> vendor image), which we do not have yet.
- **S2 DT-only image set** `../_scratch/pmos-v19-gpu-bind`: `&gpu { status = "okay"; zap-shader { firmware-name = "qcom/sm8550/a740_zap.mbn"; }; };`
  in `dts/dm1q/dm1q.dts` (generic zap first; a vendor-signed MDT set would instead need its own path such as `qcom/sm8550/Samsung/dm1q/a740_zap.mdt`,
  following `qcom/sm8550/Sony/yodo/...`: INFERENCE that this is the upstream convention).
  No firmware on the phone yet, so this boot can only bind. Expected (INFERENCE): `[drm] Initialized msm`, `failed to load a740_sqe.fw` (from the
  fbdev client's open), no `no GPU device was found`, `3d6a000.gmu` still unbound (normal), no SMMU fault, display unchanged. Rollback: flash v17.
- **S3 on-demand power-up** (`scripts/phone-gpu-powerup.sh`, PC test `scripts/test-phone-gpu-powerup.sh` 64 checks + shellcheck, flag
  `collect-phone-state.sh <label> --gpu-powerup=sqe-gmu|full`, written 2026-10-19): the script refuses unless `3d00000.gpu` is bound to adreno and the staged files
  are the pinned linux-firmware ones (section 9.2), copies the files for the mode to `/root/dm1q-gpu-fw-run` (the master copy is `/root/dm1q-gpu-fw`, never under
  `/lib/firmware`), saves `firmware_class.path`, points it at the run dir, opens `renderD128` O_RDWR for 5 s, restores the path (also on INT/TERM/HUP), removes the run dir, and
  prints only the NEW dmesg lines plus a key=value verdict (`gmu_firmware_loaded`, `zap_missing`, `pas_error`, `hw_init_failed`, `gmu_error`, `hang`, `smmu_faults`,
  `initramfs_extra_unchanged`, `RESULT:`). `sqe-gmu` stages SQE + GMU only: the GMU should boot and hw_init should stop at the missing zap (expected
  `Direct firmware load for qcom/sm8550/a740_zap.mbn failed with error -2`, INFERENCE for the exact text) - proves clocks, rails, GMU and SMMU without the secure-world step.
  `full` adds the generic zap (proves PAS and `hw_init`). The reset risk is in `full` (and, less, in the GMU boot of `sqe-gmu`); recovery is a reboot because the default path
  never has the files. After any unexpected reset read `/sys/fs/pstore` (ramoops console is enabled, but the earlier boot logs showed ramoops header errors, so it may be empty).
  CORRECTION 2026-10-19 (source re-read after the vendor-zap run): the zap is NOT requested at every power-up: `a6xx_zap_shader_init()` keeps a `static bool loaded` (`a6xx_gpu.c` line 1131),
  so after one successful load the GPU runs through suspend/resume without any file on disk, and the SQE/GMU images are cached in `adreno_gpu->fw[]`. What has to be findable is the firmware at the FIRST
  open after each boot (the fbdev client's open at ~7.8 s), so for the GPU to come up by itself the three files must sit in a standard search location before the boot: the later packaging step below.
- **S4 Mesa:** `mesa-dri-gallium` is probably there already (Plasma pulled it in); add `mesa-vulkan-freedreno` only after checking
  `/lib/apk/db/triggers`. `eglinfo` over GBM, then a frame.
- **S5** `bash scripts/collect-phone-state.sh gpu-plasma --plasma-start=240` (default profile). If the GPU is blocked, record it here and try the
  software-GL variants of docs/10 section 9.3.
- Only after the on-demand path is proven: ship the firmware as a proper package under `/lib/firmware` (docs/06 rule 3 then applies: TWRP +
  `fix-phone-initramfs-extra.sh` before the next reboot) and decide whether the GPU should power up at boot.

## 8. Reading `gpu.txt`

`gpu.txt` ends with a key=value summary: `gpu_driver`, `gpucc_driver`, `adreno_smmu_driver`, `render_node_present`, `firmware_*`,
`firmware_zap_files`, `dmesg_gpu_errors`. Expected for the baseline: `gpu_driver=absent`, `render_node_present=yes` (card1's sibling exists
without a GPU), all firmware `no`. Section 4 also prints the DT view (`DT gpu node`, `DT zap-shader child`, the carveout reg).

## 9. Results so far

### 9.1 Baseline probe, 2026-10-18 22:35 (`notes/2026-10-18-gpu-baseline/gpu.txt`, kernel 7.3.0-rc3 = r7, v17 DTB; all FACT)

- **Search path:** `firmware_class.path` is already `/lib/firmware/postmarketos` (pmOS sets it; the kernel cmdline has no `firmware_class.path`).
  So the staging approach of section 5 must save and restore the value, never clear it, and anything dropped into `/lib/firmware/postmarketos/`
  would be found at the next boot (that directory is also an mkinitfs trigger dir: docs/06 rule 3). Nothing a740/gmu/zap exists anywhere.
- **Running config:** QCOM_PAS=y (QCOM_PAS_TEE=m, `qcomtee` is loaded), QCOM_SCM=y, QCOM_TZMEM shmbridge, ARM_SMMU(_QCOM)=y,
  QCOM_AOSS_QMP=y, QCOM_RPMHPD=y, INTERCONNECT_QCOM_SM8550=y, DRM_MSM=m (+KMS_FBDEV=y, GPU_STATE=y), SM_GPUCC_8550=m, QCOM_MDT_LOADER=m,
  QCOM_UBWC_CONFIG=m, QCOM_LLCC=m, DRM_GPUVM/EXEC/SCHED=m, PM_DEVFREQ + simple_ondemand=y, FW_LOADER_USER_HELPER=y without FALLBACK,
  DEV_COREDUMP=y, ARM64_SVE=y. Every Kconfig prerequisite for the Adreno path is already there; no kernel config change is needed for S2/S3.
- **msm modules and parameters:** msm, ubwc_config, mdt_loader, drm_gpuvm, drm_exec, gpu_sched, llcc_qcom, gpucc_sm8550 are loaded.
  msm parameters include `skip_gpu=N`, `separate_gpu_kms=N`, `disable_acd=N`, `hang_debug=N`, `enable_preemption=-1`, `fbdev=Y`
  (what `skip_gpu` exactly skips is not read yet).
- **Devices:** `3d00000.gpu` absent (DT `disabled`; the zap-shader child exists with memory-region phandle 0xa1 and no firmware-name;
  `gpu-micro-code-region@9b09a000` reg = 0x9b09a000 size 0x2000, as in the live map). `3d6a000.gmu` unbound (normal, section 2). gpucc is bound
  (`gpu_cc-sm8550`), `3da0000.iommu` is bound (`arm-smmu`, SMMUv2, 22 context banks), `ae00000.display-subsystem` bound (`msm-mdss`). The carveout is
  not in `/proc/iomem` (no-map regions are not listed).
- **Boot order with gpucc as a module** (dmesg): `3da0000.iommu` returns -517 from 0.12 s until gpucc loads at 7.03 s, probes OK at 7.12 s;
  msm_dpu defers once at 7.288 and binds at 7.311; `[drm] Initialized msm 1.13.0` 7.3736; `no GPU device was found` 7.3736 (the same millisecond);
  `fb0: msmdrmfb` 7.65. That message is printed by `adreno_load_gpu()`; it appears right after the DRM device is registered and about 280 ms before the
  fbdev console exists, which supports section 5 point 3 (the in-kernel fbdev client's open runs `load_gpu`). With `&gpu` on, that open will try
  the SQE load at the same moment.
- **sync_state:** only `3d6a000.gmu` is named as pending for gcc and gpu_cc. The GMU never gets a driver of its own upstream, so this message is
  expected to stay (R3 is smaller than assumed). The cmdline also has `clk_ignore_unused pd_ignore_unused regulator_ignore_unused`.
- **Power:** `gpu_cc_gx_gdsc` and `gpu_cc_cx_gdsc` are off, cx and mmcx are on; all gpu_cc clocks have 0 enables except the SMMU's AHB / HLOS1 vote and the two gcc SMMU clocks.
- **Userspace:** mesa 26.2.4 (`mesa-dri-gallium`, egl, gbm, gl, gles), `msm_dri.so` and `kgsl_dri.so` present; no `mesa-vulkan-freedreno`, no `eglinfo` /
  `kmscube` / `vulkaninfo` / `modetest`.
- **Fingerprint:** `/boot/initramfs-extra` 11833999 bytes, sha256 `26ef233b781e1ccd7a2b19e8d3afe2a06e7407a398799b0f59037e805c1dca3c`; the saved
  `/root/dm1q-plasma/initramfs-extra.pre-plasma` is 11828461 bytes, `b952b26f...` (any later change to the first one without a TWRP fix is a rule 3 event).
- **No SMMU faults, no GPU lines other than `no GPU device was found`.**

### 9.2 Firmware on the PC, 2026-10-19 (from kernel.org linux-firmware, `../_scratch/dm1q-gpu-fw/`; never committed)

| file | bytes | sha256 | WHENCE version |
|---|---|---|---|
| `qcom/a740_sqe.fw` | 76724 | `96fee336424b139100fc60b5b45a907360e4b3936d7e1d00406b9bd80ca48473` | v1.81 |
| `qcom/gmu_gen70200.bin` | 66844 | `1a2a419c39046d3141fc5fed5aa7f971de2db40cc7a1d89693c3e26fad64dd98` | v4.01.09 (the Tab S9 Ultra's Samsung copy logged v4.1.9) |
| `qcom/sm8550/a740_zap.mbn` | 12088 | `386bbdc25ae94a9398e33e7580eecfdcef6c472682a1e3123e1374bcffe7cde3` | v0.11 |

The generic zap is a 3-program-header ELF (`QUALCOMM DSP6`): one LOAD segment of 0x430 bytes at 0x1000, plus the hash/signature segment. The loaded
span is far below the 0x2000 carveout, so R2 is not a problem for this file (the exact loader arithmetic was not re-read, INFERENCE; a vendor-signed MDT set
would need the same check). PAS backend: `qcom_pas_ops_register()` keeps the first backend that registers; the SCM one is built in, the TEE one is a module,
so SCM is most likely the active one (INFERENCE, nothing on dm1q has used PAS yet: the GPU zap would be its first user).

### 9.3 DT-only image set `../_scratch/pmos-v19-gpu-bind` (built 2026-10-19 00:30, NOT flashed)

- Source: the canonical `dts/dm1q/dm1q.dts` plus two blocks appended in `../_scratch/pmos-v19-gpu-bind/dm1q-gpu.dts`: `&gpu { status = "okay"; };` and
  `&gpu_zap_shader { firmware-name = "qcom/sm8550/a740_zap.mbn"; };`. Built with `make-dtb-image-set.sh --ref-set ../_scratch/pmos-v17-splash-iommu --apk <r7 apk>`;
  RESULT: image set OK. The DTB differs from v17's in exactly two places (status okay, firmware-name); the vendor ramdisk, bootconfig, vendor cmdline and the kernel are
  byte-identical to v17, `check-wlan-dtb.py` PASS, AVB footers OK.
- sha256: boot.img `f6bea05e5799e19c...`, vendor_boot.img `71f8571ba72780787ce272d7bdd256d72c6d71d3ac9ca9bb6acea547158bec83`.
- Flash: `boot` and `vendor_boot` only (as for the earlier DT-only sets, docs/09 15.3); `dtbo.img` differs from v17's but was not flashed in those tests either.
- Expected (INFERENCE): the display comes up as before, `[drm] Initialized msm`, a `failed to load a740_sqe.fw` style error instead of `no GPU device was found`, `3d00000.gpu`
  bound to `adreno`, `/dev/dri` unchanged, no SMMU fault, GMU still unbound. Rollback: reflash v17 (`../_scratch/pmos-v17-splash-iommu`), or, if only the display is
  affected and ssh works, blacklist msm in `/etc/modprobe.d` (docs/09 section 8).

### 9.4 First v19 boot, 2026-10-19 ~00:36: stuck in stage 1, NOT caused by the GPU node (FACT, `notes/2026-10-19-v19-gpu-bind-hang/dtbo-log-v19.txt`, uncommitted)

- Baraa flashed v19 and reported that it "gets stuck in kernel". The stage-1 log in `dtbo@1MiB` (read from TWRP with `adb exec-out dd ... | strings`, the logger of
  `kernel/initramfs/dtbo-logger.sh`) shows: `Extract /boot/initramfs-extra`, then `cpio: can't remove old file lib: Is a directory`, then `ERROR: udev not found!`,
  `/init_2nd.sh: line 712: parted: not found`, and from 2.56 s an endless `couldn't open /dev/input/` loop (27904 lines by the last flush, ~25 s). The healthy boot of the same morning
  prints `49636 blocks` at that step, two `couldn't open /dev/input/` lines, and `Switching root` at 4.86 s. No msm, adreno or gpucc line exists in the v19 log: the rootfs was never reached,
  so **the GPU DT change has not been tested at all**. (The `3da0000.iommu ... deferred probe timeout, ignoring dependency` / `-110` at 10.98 s is just stage 1 running
  long enough for the timeout to fire with no gpucc module loaded.)
- Cause (FACT, `scripts/fix-phone-initramfs-extra.sh` dry run from TWRP, backup in `~/.cache/dm1q-phone/`): the `/boot/initramfs-extra` on the phone is the mkinitfs-regenerated one with the
  usr-merge symlinks `bin`, `lib`, `sbin` (12682683 bytes, sha256 `3dfaf36aac622298...`; the baseline probe at 22:35 had the working 11833999-byte `26ef233b...`). `debugfs stat`: `initramfs`,
  `initramfs-extra` and `sm8550-samsung-dm1q.dtb` in the nested pmOS_boot were all rewritten at **19-Oct-2026 00:25:32** by the running pmOS (the phone's own clock in TWRP is 1970), i.e. an apk /
  mkinitfs run on the phone after the baseline and before the reboot. What ran it is not established yet (docs/06 rule 4: any apk operation touching a trigger dir). The fixed file the script
  builds is 12269736 bytes, 291 entries (was 294).
- Not caused by the image change: the v19 vendor ramdisk, init_boot and kernel are byte-identical to v17, which booted this morning.
- Remedy: `scripts/fix-phone-initramfs-extra.sh --yes` from TWRP (Baraa runs it), then reboot to system and redo the v19 check. Rollback of that fix: `--yes --file <extra-phone-*.gz>`.

### 9.5 v19 boot after the initramfs-extra repair, 2026-10-19 00:42 (`notes/2026-10-19-gpu-bind/`, uncommitted; all FACT)

- Baraa ran `fix-phone-initramfs-extra.sh --yes` from TWRP (the file is now 12269724 bytes, sha256 `61c42f44...`), and the phone booted to the login prompt on the real panel with the `&gpu` DTB.
  Cause of the earlier stuck boot: he had run `apk upgrade` on the phone (docs/06 rule 3). The upgrade moved Mesa 26.2.4 to 26.2.5-r0 (the probe lists mesa, mesa-dri/egl/gbm/gl/gles
  all 26.2.5-r0, libdrm 2.4.134, vulkan-loader 1.4.360; `msm_dri.so` and `kgsl_dri.so` still present; still no `mesa-vulkan-freedreno`, no eglinfo / kmscube).
- **The GPU binds (S2 passed):** `3d00000.gpu` bound to `adreno` ("probe of 3d00000.gpu with driver adreno returned 0" at 7.312 s, after gpucc 7.101 s and the SMMU 7.166 s), `msm_dpu: bound 3d00000.gpu`,
  `[drm] Initialized msm 1.13.0` at 7.8657 s, `fb0: msmdrmfb` at 8.107 s. The SMMU adds `3d00000.gpu` and `3d6a000.gmu` to iommu groups 6 and 7. IRQs: `gpu-irq` (332) and `gmu` (337).
  devfreq `3d00000.gpu` exists: governor simple_ondemand, cur 0, 220-680 MHz, 8 OPPs. `adreno 3d00000.gpu: supply vdd not found, using dummy regulator` and the same for `vddcx` (harmless: the GMU manages power).
- **load_gpu really runs at DRM registration (confirmed):** in the same millisecond as `Initialized msm` (7.865669) the kernel prints `Direct firmware load for qcom/a740_sqe.fw failed with error -2` and
  `failed to load a740_sqe.fw`; `no GPU device was found` is gone. So the in-kernel fbdev client's open does call `msm_open` -> `load_gpu` at every boot, as section 5 point 3 said; with the
  firmware findable the power-up would happen by itself at boot.
- **No SMMU faults (0), display unchanged, ssh up, `3d6a000.gmu` still unbound with `sync_state() pending due to 3d6a000.gmu` (expected).**
- Nothing a740/gmu/zap exists on the phone yet, `firmware_class.path` is still `/lib/firmware/postmarketos` (`gpu.txt` section 1).
- Next: S3 `sqe-gmu` (needs the PC on the phone's network and the firmware directory from 9.2).

### 9.6 S3 `sqe-gmu`, first power-up, 2026-10-19 06:25 (`notes/2026-10-19-gpu-powerup-sqe/gpu-powerup.txt`, uncommitted)

FACT (the six new kernel lines, everything else unchanged: no reset, no SMMU fault, `firmware_class.path` restored to `/lib/firmware/postmarketos`, initramfs-extra hash unchanged):

```
[33.977806] msm_dpu ae01000.display-controller: [drm:adreno_request_fw [msm]] loaded qcom/a740_sqe.fw from new location
[33.978217] msm_dpu ae01000.display-controller: [drm:adreno_request_fw [msm]] loaded qcom/gmu_gen70200.bin from new location
[33.980649] [drm] Loaded GMU firmware v4.1.9
[33.996291] adreno 3d00000.gpu: [drm:adreno_zap_shader_load [msm]] *ERROR* Unable to load qcom/sm8550/a740_zap.mbn
[33.996797] msm_dpu ae01000.display-controller: [drm:adreno_load_gpu [msm]] *ERROR* gpu hw init failed: -2
[34.007169] platform 3d6a000.gmu: [drm:a6xx_gmu_set_oob [msm]] *ERROR* Timeout waiting for GMU OOB set GPU_SET: 0x0
```

- The custom `firmware_class.path` is honoured by SQE and GMU ("from new location"); the GMU firmware is v4.1.9, the same version the Tab S9 Ultra logged.
- The zap error and `hw init failed: -2` are the designed stop (the zap file was not staged).
- INFERENCE from the source order, read 2026-10-19 (`a6xx_gpu.c` `hw_init()`, `a6xx_gmu.c` `a6xx_gmu_shutdown()`): `hw_init()` starts with `a6xx_gmu_set_oob(GMU_OOB_GPU_SET)`; had that timed out, hw_init would
  have returned that error before it ever reached the zap step. So the GMU booted and acked the first OOB, and hw_init got through its register programming up to the zap step without a bus error or reset.
  The `Timeout waiting for GMU OOB set GPU_SET` 10 ms after the zap error is then the upstream error-path cascade: hw_init returns on the zap error WITHOUT clearing that OOB, and the GMU shutdown
  (`needs_hw_init` is true) repeats the handshake, which cannot be acked a second time, then forces the GMU off. The script's classifier now recognises exactly this case
  (`oob_timeout_after_error`); an OOB timeout with no earlier error stays a failure. The real lines are a regression fixture in `test-phone-gpu-powerup.sh` (77 checks).
- devfreq `3d00000.gpu` reads cur 680 MHz afterwards; `gpu-irq` / `gmu` counters are still 0.
- Not shown: that the GPU executes anything (no zap, so the CP is still in secure mode and nothing was submitted).
- Next: S3 `full` (generic zap through PAS).

### 9.7 S3 `full` with the generic zap, 2026-10-19 06:29 (`notes/2026-10-19-gpu-powerup-full/gpu-powerup.txt`, uncommitted)

FACT (the three new kernel lines; no reset, no SMMU fault, path restored, initramfs-extra unchanged, SQE/GMU loaded from the cache so they printed nothing new):

```
[256.808795] adreno 3d00000.gpu: error -22 initializing firmware qcom/sm8550/a740_zap.mbn
[256.809056] msm_dpu ae01000.display-controller: [drm:adreno_load_gpu [msm]] *ERROR* gpu hw init failed: -22
[256.819578] platform 3d6a000.gmu: [drm:a6xx_gmu_set_oob [msm]] *ERROR* Timeout waiting for GMU OOB set GPU_SET: 0x0
```

- The first line is printed by `qcom_mdt_load()` (`mdt_loader.c`, comment "Invalid firmware metadata") when `qcom_pas_init_image(13, metadata, ...)` fails: the SCM call that hands the zap's ELF header, program headers and
  hash/signature segment to the secure world returned -22. That is before any code is copied or authenticated, so the secure world rejected the image's metadata, not its code.
- INFERENCE: the generic linux-firmware zap is signed for development-fused Qualcomm boards and this phone's secure world does not accept that signature chain (the expected outcome, docs/11 R1). It is not proven: the same
  SCM path accepted Samsung's own zap on the Tab S9 Ultra, but that was another kernel version, and -22 is the generic remapped SCM error, so a call-convention problem is not excluded. Loading the phone's own
  Samsung-signed zap through the same code is the discriminator.
- The OOB timeout 10 ms later is the same upstream cascade as in 9.6. The GMU and its OOB handshake work (the first OOB was acked, otherwise hw_init would not have reached the zap).
- `scripts/phone-gpu-powerup.sh` now has `zap_init_error` and says "the secure world REFUSED the staged zap image" for this case; the three real lines are a second regression fixture (84 checks).
- Next: pull the phone's own `a740_zap.*` (and its SQE/GMU for comparison) from the vendor partition in TWRP (`scripts/pull-gpu-vendor-firmware.sh`), then S3 `full` again with that set.

### 9.8 The phone's own Adreno firmware, pulled from its vendor partition in TWRP, 2026-10-19 11:23 (`../_scratch/dm1q-gpu-fw-vendor/`, never committed; FACT)

`twrp mount /vendor` mounted it (the script's own read-only mount was not needed); everything is under `/vendor/firmware/`:

| file | bytes | sha256 |
|---|---|---|
| `a740_sqe.fw` | 76724 | `96fee336...` = **identical** to linux-firmware's |
| `gmu_gen70200.bin` | 66844 | `1a2a419c...` = **identical** to linux-firmware's |
| `a740_zap.mbn` | 12088 | `60cf7ab4f3d96e0992a42560ac288c053328bda5e41b4fe5e678be94ecd7ae35` (the generic one is `386bbdc2...`) |
| `a740_zap.mdt` / `.b00` / `.b01` / `.b02` / `.elf` | 4044 / 148 / 1072 / 3896 / 5168 | the same zap as a split set and as one ELF |

- Only the zap is device-specific, as section 6 R1 said. The vendor `a740_zap.mbn` has the same size, the same ELF header and the same program headers as the generic one (LOAD 0x430 at 0x1000, the hash/signature
  segment at 0x2000). A byte comparison finds 2451 differing bytes, all between 0x2048 and 0x2b64: **only the signature and certificate segment differs; the LOAD segment (the zap code) is identical.**
  Together with 9.7 this is strong evidence that the secure world checks the signature chain of the hash segment against the OEM (Samsung) root and refused the generic one for that reason.
- The vendor zap is a single `.mbn`, so the v19 DT (`firmware-name = "qcom/sm8550/a740_zap.mbn"`) needs no change: no new image set, only a different file.
- Staged for the next run as `../_scratch/dm1q-gpu-fw-vendor-run/qcom/{a740_sqe.fw,gmu_gen70200.bin,sm8550/a740_zap.mbn}` (use `DM1Q_GPU_FW=<that dir>`; the collector now sends the hashes of the pushed set to the phone
  script as pins, wipes `/root/dm1q-gpu-fw` first so no stale zap can be used, and the phone script still refuses anything whose hash differs from what was pushed).
- Next: S3 `full` with the vendor zap.

### 9.9 S3 `full` with the phone's own zap, 2026-10-19 11:28 (`notes/2026-10-19-gpu-powerup-full-vendor/gpu-powerup.txt`, uncommitted): **the GPU initialises**

FACT (the only three new kernel lines; no error, no fault, no reset; path restored; initramfs-extra unchanged; set pinned by the hashes of 9.8):

```
[180.760770] msm_dpu ae01000.display-controller: [drm:adreno_request_fw [msm]] loaded qcom/a740_sqe.fw from new location
[180.760945] msm_dpu ae01000.display-controller: [drm:adreno_request_fw [msm]] loaded qcom/gmu_gen70200.bin from new location
[180.762665] [drm] Loaded GMU firmware v4.1.9
```

- No `Unable to load`, no `error -22 initializing firmware`, no `gpu hw init failed`, no OOB timeout (9.6 and 9.7 had all three kinds): `hw_init()` ran to the end, so the secure world accepted the Samsung-signed zap
  (`qcom_pas_init_image` and the authenticate-and-reset both returned 0) and the CP went through `CP_SET_SECURE_MODE` and idled (INFERENCE from the source order: any of those failing returns an error and logs a line).
  Generic zap: refused with -22 (9.7). Vendor zap, identical code with a different signature segment (9.8): accepted. That settles the cause: the signature, not the call path.
- The GPU is idle again afterwards (devfreq `cur_freq` 220 MHz); `gpu-irq` and `gmu` interrupt counts are still 0, since nothing has been submitted. Whether the GPU executes work is the next test.
- The GPU now stays initialised until the next reboot (`priv->gpu` is set; the zap is cached by `loaded`), so a GL client started now needs no firmware file. After a reboot the three files have to be findable at the first open again.

### 9.10 Plasma could not start for an unrelated reason: PAM, after the `apk upgrade` (2026-10-19; `notes/2026-10-19-gpu-plasma/`, `notes/2026-10-19-pam-diag/`, uncommitted; FACT unless marked)

- `collect-phone-state.sh gpu-plasma --plasma-start=240` (GPU already initialised by 9.9) never reached a GL client: `plasma-mobile.service` exits 1 in 40 ms, `startplasmamobile` logs `Could not start D-Bus`, and the crash-loop guard
  stopped the run after 3 restarts. The journal shows why: `user@10000.service: Failed at step PAM spawning /usr/lib/systemd/systemd` (status 224/PAM) preceded by
  `PAM unable to dlopen(/usr/lib/security/pam_selinux.so): No such file or directory` / `PAM failed: Module is unknown`. The UI user's systemd manager cannot start, so there is no session bus, no kwin, no plasmashell.
- It is new: the Oct 17-18 Plasma runs (`2026-10-17-plasma-start`, `2026-10-18-plasma-start-sp/-sw`) have no PAM failure at all and got as far as kwin_wayland and llvmpipe; the PAM failure is in the first Plasma run after Baraa's `apk upgrade` (97 packages, 2026-10-19 00:25).
- Cause (`pam.txt`): `/usr/lib/pam.d/systemd-user` and `systemd-run0` (owned by `systemd-262-r2`, built 26 Sep) contain `session required pam_selinux.so close` / `... nottys open`, while `/usr/lib/security` and `/lib/security` have no `pam_selinux.so`. The upgrade moved `linux-pam` 1.7.1-r3 -> r4 (and `linux-pam-systemd` the same),
  `shadow` 4.18.0 -> 4.20.3, `libselinux` 3.11-r2 -> r3, installed `gnome-keyring-pam`, and ran the mkinitfs trigger; no `systemd` upgrade line is in the transaction. INFERENCE: r3 shipped `pam_selinux.so` (it worked before) and r4 does not, so this is an edge packaging mismatch between linux-pam and systemd, not a fault of our files.
  `kde-fingerprint` and `kde-smartcard` in `/etc/pam.d` mention selinux too but are not used to start the session. The apk run also printed mirror warnings (`HTTP: unrecognized server error` for `mirror.postmarketos.org`, redirects to `mirror.nura.eco`).
- Fix without apk (so no mkinitfs trigger): Linux-PAM reads `/etc/pam.d` before `/usr/lib/pam.d` (INFERENCE from the vendor-dir layout: both directories already hold an `sshd`), so `scripts/phone-pam-fix.sh` (PC test `scripts/test-phone-pam-fix.sh`, 40 checks, flag `collect-phone-state.sh <label> --pam-fix[=check|undo]`) writes
  `/etc/pam.d/systemd-user` and `systemd-run0` as copies of the vendor files with the pam_selinux lines changed to `-session ... optional` ("-" ignores a missing module), marker line on top, refuses if the module exists or a foreign override is present, then starts `user@10000.service` once. `=undo` removes only files that carry the marker. A later systemd or linux-pam fix upstream makes the override unnecessary; delete it then.

### 9.11 Plasma Mobile on the Adreno 740, 2026-10-19 21:05 (`notes/2026-10-19-gpu-plasma2/`, uncommitted)

- `collect-phone-state.sh gpu-plasma2 --pam-fix --gpu-powerup=full --plasma-start=240` (vendor firmware set): the PAM override started `user@10000.service`, `plasma-mobile.service` stayed `active/running` for the whole 240 s with `restarts=0` and kwin alive,
  CPU load 0.2 to 0.6, hottest sensor 37 to 46 C. Baraa saw the desktop on the panel; the power and volume keys worked, touch worked for a while and then stopped.
- FACT from the kwin journal: `Added render device /dev/dri/renderD128: FD740` (Mesa freedreno identified the Adreno 740 through the msm driver), `Chose /dev/dri/renderD128 as the primary GPU`, `Using Atomic Mode Setting on gpu /dev/dri/card1`
  (10 planes), `New output on GPU /dev/dri/card1: DSI-1`, `OpenGL compositing has been successfully initialized`; `/dev/udmabuf: llvmpipe` is also listed as a render device but is not the primary one. No SIGILL, no GPU hang, no SMMU fault, no msm error in dmesg.
  The GPU had already been initialised by the earlier power-up in that boot, so the run's own power-up step printed no new kernel lines.
- NOT verified: that the GPU executes work under the compositor. The `gpu-irq` / `gmu` interrupt counters and the devfreq frequency were not captured after the run (the only counters on file, in `gpu-powerup.txt`, were taken before Plasma started and read 0). Add them to the monitor of `phone-plasma-start.sh`.
- The touch drop-out is NOT a GPU or Plasma problem: Baraa saw the same on the tty with the on-screen keyboard before the GPU work. It is handed over in `notes/2026-10-20-handoff-touch.md` and tracked in docs/08 2.11.

### 9.12 Making it permanent: GPU firmware at boot + Plasma Mobile autostart (2026-10-20; script and PC test written, NOT run on the phone yet)

Decision (Baraa, 2026-10-20 afternoon): stop powering the GPU up by hand after every reboot and start Plasma Mobile by itself; the touch work (docs/08 2.12) is paused after Step A.
`scripts/phone-boot-setup.sh` (modes `check | gpu-fw | undo-gpu-fw | plasma | undo-plasma`; PC test `scripts/test-phone-boot-setup.sh`, 116 checks, bash only because dash is not installed here; `bash --posix -n` and
`shellcheck -s sh -S warning` clean on the script and on the three scripts it generates; collector flag `--boot-setup=MODE`, with `DM1Q_GPU_FW=../_scratch/dm1q-gpu-fw-vendor-run`).

- **No apk anywhere** (docs/06 rule 3): only plain files under `/lib/firmware/postmarketos`, `/usr/local/sbin`, `/etc/systemd/system`, `/var/lib/dm1q`, and `systemctl enable / set-default`. The script prints the sha256 of `/boot/initramfs-extra` before and after and
  warns loudly if it changed. FACT (PC test): it never calls apk, and never calls `start`, `stop`, `restart`, `mask` or `isolate`.
- **`gpu-fw`:** installs `qcom/a740_sqe.fw`, `qcom/gmu_gen70200.bin` and the phone's own `qcom/sm8550/a740_zap.mbn` into the kernel's DEFAULT firmware path. The default pins are the hashes of this section's 9.8 (SQE `96fee336...`, GMU `1a2a419c...`, zap `60cf7ab4...`; checked
  against `../_scratch/dm1q-gpu-fw-vendor-run` on the PC); it refuses the generic zap (`386bbdc2...`, refused by the secure world, 9.7), a `firmware_class.path` other than `/lib/firmware/postmarketos`, and any foreign file already at those paths. The collector
  fails early on the PC if `$DM1Q_GPU_FW` holds the generic zap (the default dir `../_scratch/dm1q-gpu-fw` does).
- **Boot-loop breaker** (the one new risk: a TZ reset or hang at EVERY boot, instead of once after a hand-run): `dm1q-gpu-fw-guard.service` (sysinit, before udev and modules-load) leaves a marker; `dm1q-gpu-fw-ok.service` removes it 90 s after
  `multi-user.target`. A marker still present at the next boot means the previous boot never got that far, and the guard moves the three files to `/var/lib/dm1q/gpu-fw-disabled/` (and logs it to `/dev/kmsg`), so that boot comes up WITHOUT the GPU; `gpu-fw` again puts them back.
  FACT (PC test, the generated scripts are run for real): first boot leaves the marker, ok clears it, a boot with a stale marker moves the firmware away, a boot without a manifest does nothing. **Side effect:** rebooting within ~90 s of a boot also disables the GPU
  (the collector warns); `check` shows `gpu_fw=disabled-by-guard` then.
- **`plasma`:** enables `plasma-mobile.service` (alias `display-manager.service`; default target set to `graphical.target`, the previous one kept in `/var/lib/dm1q/plasma-prev-default`) plus a drop-in `10-dm1q-boot.conf`: `StartLimitBurst=4` in 180 s (the unit's own
  `OnFailure=getty@tty1.service` then gives the console back) and an `ExecStartPre` that waits up to 15 s for `/dev/dri/renderD128`. **It refuses** unless the firmware is installed, the GPU initialised BY ITSELF in the current boot (`Loaded GMU firmware` in dmesg, no
  `hw init failed` / `Unable to authorize` / `error -22` line), and the PAM override of 9.10 (or a real `pam_selinux.so`) is in place: without a GPU kwin falls back to llvmpipe, which dies with SIGILL in a restart loop (docs/10 9.3). It does not start the UI.
- **Order on the phone:** (1) `--boot-setup=gpu-fw`; (2) normal reboot, wait 2 minutes; (3) `--gpu --boot-setup=check` must show `gpu_state=initialised`; (4) `--boot-setup=plasma`; (5) reboot. Undo: `--boot-setup=undo-plasma`, `--boot-setup=undo-gpu-fw`.

INFERENCE, to be settled by step 3 (nothing here ran on hardware): msm loads in userspace after switch_root (the Plasma run's dmesg has `Initialized msm` at 7.7 s, the healthy stage 1 switches root at about 4.9 s, 9.4), so a file on the rootfs is visible when the fbdev client's open calls `load_gpu` (section 5 items 2 and 3); the
zap's `firmware-name` `qcom/sm8550/a740_zap.mbn` is resolved against `/lib/firmware/postmarketos` exactly as it was against the staging dir in 9.9. Whether the secure world accepts the zap at msm-bind time as it did at a later open is the real unknown (the guard exists for it).

Known problems this does NOT solve (they become visible once Plasma starts by itself):
- **The lock screen cannot authenticate** (`kscreenlocker_greet`: `Worker not ready yet, cannot authenticate`, 9.11; handoff section 5 item 3). If the screen locks (idle timer or the power key), the UI is stuck on the lock screen; recovery from ssh: `sudo systemctl restart plasma-mobile.service`. Disabling auto-lock (`~/.config/kscreenlockerrc`, `[Daemon] Autolock=false`, `LockOnResume=false`) is the likely stop-gap; not done, not tested.
- **Touch drop-out** (docs/08 2.11 / 2.12) is unchanged: with the UI on tty1 the on-screen keyboard of buffyboard is gone, so a dead touchscreen means a dead UI until the touch bug is fixed; the physical keys and ssh still work.
- **Result of step 1 and 2, 2026-10-20 21:09 / 21:14** (`notes/2026-10-20-boot-gpu-fw/`, `notes/2026-10-20-boot-check/`, uncommitted; FACT): `--boot-setup=gpu-fw` installed the three files (hashes equal the pins, `initramfs-extra` sha256 unchanged before and after, no apk). The boot BEFORE the install shows msm asking for `a740_sqe.fw` by itself 0.5 s after the GPU node probed and failing with -2 (`dmesg` 8.09 s), so the boot-time lookup exists. After a normal reboot: `dm1q-gpu-fw-guard` ran at 6.09 to 6.12 s (before udev loaded msm), `loaded qcom/a740_sqe.fw` / `gmu_gen70200.bin` at 7.66 s, `Loaded GMU firmware v4.1.9` at 7.67 s, **no failure line, no SMMU context fault, `dmesg_gpu_errors=0`, no reset**; the kernel prints nothing on a successful zap authentication, so its acceptance is INFERRED from the absence of any `Unable to authorize` / `error -22` / `hw init failed` line and from the same three-line success signature as 9.9 (INFERENCE, strongly supported: the secure world accepts the zap at msm-bind time too). The boot-pending marker had cleared at the check (about 3 minutes of uptime), firmware still installed, breaker units enabled, GPU idle (devfreq 220 MHz, `gpu-irq` and `gmu` counts 0: nothing submitted yet, as before). Not yet seen: the breaker ACTING (needs a boot that fails; only the PC test covers that) and the `dm1q-gpu-fw-ok.service` run itself (the cleared marker is the evidence, no log line for it was captured).
- A later `apk upgrade` that ships a file at one of the three firmware paths would replace the vendor zap (INFERENCE: apk owns files by path, ours are unowned); `check` prints whether the apk database names them. An apk run still needs the rule-3 warning and the TWRP repair path.

### 9.13 Why Plasma was hot and laggy: the GPU firmware was not found at boot; the zap is fine (2026-10-22; `notes/2026-10-21-touch-watch/`, `notes/2026-10-21-gpu-plasma2/`, `notes/2026-10-22-hot-cpu/`, `notes/2026-10-22-gpu-plasma2/`, uncommitted)

Baraa suggested rechecking the zap as the cause of the unusable (hot, laggy) phone. FACT (dmesg and the power-up logs of the four captures):

| Boot (capture) | boot-time request for `a740_sqe.fw` | GPU afterwards |
|---|---|---|
| 2026-10-20 21:16 (`boot-plasma`, 9.12 step 2) | found at 7.66 s, `Loaded GMU firmware v4.1.9` at 7.67 s | initialised by itself |
| 2026-10-21 07:11 (`touch-watch`) | `error -2` at 7.66 s, `error -40` at 11.3 s | not initialised until `--gpu-powerup=full` at 780 s (the 08:38 run) |
| 2026-10-22 05:45 (`hot-cpu`) | `error -2` at 8.05 s, `error -40` at 11.97, 12.03 and 105.9 s | never initialised in that boot (load probe: 2.16) |
| 2026-10-22 05:53 (`gpu-plasma2`) | `error -2` at 7.95 s, `error -40` from 3941 s | initialised by `--gpu-powerup=full` at 4165 s (07:06) |

- `dm1q-gpu-fw-guard.service` ran at 5.6 to 6.4 s in all of these boots, and **none of them contains the guard's own line** (`dm1q-gpu-fw-guard: the previous boot did not finish ... moved to ...`), so the guard did not act in a captured boot.
- The 07:06 power-up (vendor set, firmware from `/root/dm1q-gpu-fw-run` through `firmware_class.path`): SQE and GMU `loaded ... from new location`, `Loaded GMU firmware v4.1.9`, verdict `zap_missing=no pas_error=no zap_init_error=no hw_init_failed=no gmu_error=no oob_timeout_after_error=no`, devfreq 220 MHz afterwards. Baraa reports that the lag is gone after it.
- The same file names that fail from `/lib/firmware/postmarketos` at boot load from the staging directory in the same boot, so the kernel and msm are fine; what differs is what the standard search path holds.
- The hot state itself is the one of 2.16: every core ~89 % busy in `kwin_wayland` and `angelfish` (8 `llvmpipe` threads each), 84 to 90 C, GPU devfreq `cur=0`.

Readings:

- **The zap shader is not the cause (FACT for the two events above, INFERENCE for the rest).** In the boots without firmware the GPU never reached the zap step (the SQE request fails first), and every time the vendor set was actually loaded (9.9, 9.12 step 2, the 07:06 power-up) the secure world accepted the Samsung-signed zap (`60cf7ab4...`) without an error line. The generic zap stays refused (9.7).
- **The cause of the lag is the CPU fallback (INFERENCE, consistent with every observation).** With no initialised GPU, Mesa still lists `FD740` as a render device (kwin's journal), the first context creation fails at the msm open, and the compositor and the browser render with llvmpipe on all cores, which is what `top` and the temperature showed. After the power-up the GPU is initialised and the lag is gone.
- **Why the firmware was missing at boot is NOT established.** The leading candidate (INFERENCE) is the boot-loop guard acting in a boot that was not captured: it moves the three files away when the previous boot did not reach `multi-user.target` + 90 s, which includes a manual reboot soon after boot (Baraa had a dead touchscreen right after the first autostart boot and probably rebooted at once), and after that the guard has no manifest and does nothing, so every later boot lacks the firmware, silently. Not read yet: `/var/lib/dm1q/gpu-fw-disabled/`, the boot-pending marker, the files in `/lib/firmware/postmarketos`. The read-only `--boot-setup=check --gpu` prints all of them.
- **The `-40` is unexplained.** `-2` is `-ENOENT`. `-40` is `-ELOOP`, and it appears only for the `.xz` variant of every search directory (including `updates/<release>` directories that do not exist), after the plain-name lookups ended quietly with `-ENOENT` (`drivers/base/firmware_loader/main.c` `fw_get_filesystem_firmware`: only non-ENOENT results are logged, the `.xz` pass runs only when the plain pass ended in `-ENOENT`). A loop in a path that does not exist does not fit a plain symlink loop; it is not understood. Section 6b of the GPU probe now reads the lookup the way the loader does it, from this shell, from pid 1 and from pid 2 (the kernel threads), and tests each existing path with a read.

**Settled by the read-only check of 2026-10-22 12:03 (`notes/2026-10-22-fw-recheck/boot-setup.txt`, FACT):** `/lib/firmware/postmarketos` holds none of the three files, the manifest is absent, and `/var/lib/dm1q/gpu-fw-disabled/` holds `a740_sqe.fw a740_zap.mbn gmu_gen70200.bin gpu-fw.manifest.disabled`: **the guard moved the firmware away** in a boot that is not captured (the boot-pending marker is absent now, the units are enabled, the apk database does not name the files, initramfs-extra is unchanged `61c42f44...`), and every later boot had no GPU. What the earlier INFERENCE called the leading candidate is now the established mechanism; the trigger boot (INFERENCE: a reboot soon after an autostart boot) is still not captured.

Design problems this exposed (found by reading the generated scripts; FIXED 2026-10-22, in the PC tests, NOT yet on the phone):

1. **The guard cannot tell a reboot from a failed boot.** The marker is cleared 90 s after `multi-user.target`, so a `reboot` issued earlier than that, a normal thing to do when something looks wrong, makes the NEXT boot disable the GPU firmware, and a boot without a manifest never restores it. Fix: the guard unit is now `RemainAfterExit=yes` with `ExecStop=/usr/local/sbin/dm1q-gpu-fw-clean`, which clears the marker at a clean shutdown, so only a boot that ends without a clean shutdown (reset, hang, power key held) trips the guard; the 90 s rule stays for the other direction. PC test: boot 1 leaves the marker, the clean script clears it, boot 2 keeps the firmware, a third boot without a clean end moves it. Not seen on hardware: that systemd really runs the ExecStop at `reboot` (it should: the unit conflicts with `shutdown.target`).
2. **The Plasma autostart does not check the GPU.** Its `ExecStartPre` only waits for `renderD128`, which exists without any GPU. With the firmware missing, Plasma starts anyway and runs on llvmpipe (2.16). Fix: the drop-in's `ExecStartPre` is now `dm1q-plasma-gate` (replaces `dm1q-wait-render-node`): after the render-node wait it exits 1 unless the kernel log has `Loaded GMU firmware` and no hw-init failure line, so the unit fails and its `OnFailure=` gives tty1 to getty (a console login instead of a hot phone), with a line in the kernel log and the journal. Escape hatch: `touch /var/lib/dm1q/plasma-allow-cpu`. `scripts/test-phone-boot-setup.sh` has 130 checks (bash; dash is not installed here).
3. **A fix needs the firmware back first:** `--boot-setup=gpu-fw` (with `DM1Q_GPU_FW` at the vendor set), then a normal reboot and 2 minutes of waiting (rebooting inside the ~90 s window trips the guard).

Added: `scripts/phone-gpu-probe.sh` section 6b (and 125 checks in `scripts/test-phone-gpu-probe.sh`, a `fwpath` scenario with a symlink loop, a custom path and a pid-2 view).
