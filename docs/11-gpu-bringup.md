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
| Baseline probe `scripts/collect-phone-state.sh <label> --gpu` (scripts/phone-gpu-probe.sh, PC test passes) | written, NOT yet run on the phone |
| Firmware pull from the phone's own vendor partition (TWRP) | not done |
| DT-only image set (`&gpu` okay) | not built |
| Power-up test, Mesa, Plasma on GPU | not done |

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
   from ssh (`echo DIR > /sys/module/firmware_class/parameters/path`, open a render node once, then clear the path). A TZ reset then costs one
   reboot instead of a boot loop, and nothing is written under `/lib/firmware`, so no apk trigger can regenerate `/boot/initramfs-extra`
   (docs/06 rule 3 is about the apk trigger; INFERENCE that plain files elsewhere cannot fire it; the probe records the initramfs-extra
   hash so this is checked, not assumed).

## 6. Risks and open questions

- **R1 firmware source.** The zap shader must be signed for this phone's secure world (Qualcomm's `qcom/sm8550/a740_zap.mbn` in linux-firmware
  is for development-fused boards: INFERENCE, would not authenticate). It has to come from this phone's own vendor partition (a logical
  partition inside `super`; TWRP can mount it). Expected names (INFERENCE from sections 3-4): `a740_zap.mdt`, `.b00`, `.b01`, `.b02`,
  `a740_sqe.fw`, `gmu_gen70200.bin`. Not pulled yet.
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
- **S1 firmware pull (TWRP, no phone write).** `adb` from recovery, mount the vendor partition read-only, copy the six files to
  `../_scratch/dm1q-gpu-fw/` (never committed), print sizes and sha256. Tooling not written yet.
- **S2 DT-only image set** `../_scratch/pmos-v19-gpu-bind`: `&gpu { status = "okay"; zap-shader { firmware-name = "qcom/sm8550/Samsung/dm1q/a740_zap.mdt"; }; };`
  in `dts/dm1q/dm1q.dts` (path pattern follows `qcom/sm8550/Sony/yodo/...`: INFERENCE that this is the upstream convention for vendor-signed files).
  No firmware on the phone yet, so this boot can only bind. Expected (INFERENCE): `[drm] Initialized msm`, `failed to load a740_sqe.fw` (from the
  fbdev client's open), no `no GPU device was found`, `3d6a000.gmu` still unbound (normal), no SMMU fault, display unchanged. Rollback: flash v17.
- **S3 on-demand power-up** (`phone-gpu-powerup.sh`, to be written with its PC test): stage the six files under a directory outside the default
  search path, set `firmware_class.path`, open `renderD128` once, read dmesg and the GPU debugfs state, clear the path. First with SQE + GMU only
  (the zap file absent: expected clean -ENOENT at the zap, proves clocks/rails/GMU), then with the zap (proves PAS auth and `hw_init`).
  Reset risk is in the second step; rollback is a reboot.
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
