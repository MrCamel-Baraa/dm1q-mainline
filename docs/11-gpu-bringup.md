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
| Vendor-signed zap pull (TWRP) | not needed unless PAS rejects the generic one |
| DT-only image set `../_scratch/pmos-v19-gpu-bind` (`&gpu` okay, no firmware on the phone) | built and verified on the PC 2026-10-19, NOT flashed |
| Power-up test (S3), Mesa, Plasma on GPU | not done |

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
  Fallback only if S3 shows PAS rejecting the generic zap: TWRP + adb pull of the phone's own `a740_zap.*` from the vendor partition (tooling not written).
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
  Because the zap is requested again at every `hw_init` (every power-up after the GPU idles), a working GPU needs the zap in the standard search path for good: that is the later
  packaging step below, not part of S3.
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
