# 13 - Audio bring-up (ADSP first)

Started 2026-10-25. Confidence tags: CONFIRMED (seen in a log or in source), INFERRED (reasoned, not checked), TODO.

## 1. Where we start

The phone has no sound. Everything audio on SM8550 (Q6 / audio DSP, APR/GPR, ASoC card, codec, amplifiers) runs through the ADSP, so the first fact is
whether the ADSP runs at all.

- CONFIRMED (user paste 2026-10-25): `/sys/class/remoteproc/` has no entries. No remoteproc is registered, so the ADSP never starts.
- CONFIRMED (`/proc/config.gz`): `CONFIG_QCOM_Q6V5_PAS=m`, `CONFIG_QCOM_PMIC_GLINK=m`, `CONFIG_UCSI_PMIC_GLINK=m`. The PAS driver exists, so this is not a config gap.
- CONFIRMED: `dts/dm1q/dm1q.dts` enables no remoteproc node (the only ADSP-related content is the reserved-memory carveout). The mainline `sm8550.dtsi` defines
  `remoteproc_adsp` (`qcom,sm8550-adsp-pas`, regions `adspslpi_mem` + `q6_adsp_dtb_mem`) but leaves it disabled; the QRD board file enables it with `adsp.mbn` and `adsp_dtb.mbn`.
- CONFIRMED (live reserved-memory dump of the phone, `notes/2026-09-21-v2-bootloop/live-reserved-memory.txt`): `adspslpi_region@9ea00000` size 0x59b4000 (our DTS
  already carries this, mainline's dtsi has 0x4080000), `q6_adsp_dtb_region@9e980000` size 0x80000 (same as mainline), `adsp_mhi_region@81f00000` size 0x20000,
  and a reusable `adsp_heap_region` (12 MiB, shared-dma-pool). Only the first two are used by the mainline PAS node.
- CONFIRMED (Samsung S911B dm1q DT): `remoteproc-adsp@03000000` names no firmware file (stock Android loads it through its own `qcom,msm-adsp-loader`) and lists the
  supplies cx, mx and sensor_vdd (1.8 V).
- Unrelated to the battery: the battery is on I2C (docs/12), so the ADSP is not needed for it.

## 2. What is missing

1. The phone's own ADSP firmware. It is signed for this device and authenticated by the secure world (PAS), like the Adreno zap shader (docs/11): the generic
   linux-firmware images will not do. Expected names: `adsp.mbn` and `adsp_dtb.mbn` (or the `.mdt` + `.bNN` split form) in the modem partition (`image/`) or under
   `/vendor/firmware`; TODO: confirm where Samsung keeps them.
2. A DTS change: enable `&remoteproc_adsp` with `firmware-name`, and check the memory regions against the live ones (section 1).
3. The firmware on the phone under `/lib/firmware/postmarketos/qcom/sm8550/`, with a boot-loop guard like the GPU one (`scripts/phone-boot-setup.sh gpu-fw`): a wrong or
   refused ADSP image can hang the boot.

## 3. Step 1: pull the phone's own ADSP firmware (TWRP, read-only)

- `scripts/twrp-find-dsp-fw.sh` (device side) and `scripts/pull-dsp-vendor-firmware.sh` (PC side), modelled on the GPU pair (`scripts/twrp-find-gpu-fw.sh`,
  `scripts/pull-gpu-vendor-firmware.sh`): they mount the vendor and modem partitions READ-ONLY in RAM-disk directories, list every directory that holds `adsp*` or `battmgr*`
  files, pull the files with size + sha256 verification, and unmount. Nothing is written to a partition. Output goes to `../_scratch/dm1q-dsp-fw-vendor/` (blobs stay out of the repo);
  the scan output is in `scan.txt` there.
- Tested on the PC against a fake firmware tree (scan, FOUND lines, umount, usage); NOT yet run on the phone.

## 4. Later steps (not started)

- Q6 / APR / GPR drivers, `lpass` pin controllers, the ASoC sound card node (QRD's `sound` node as the reference), WCD9385/WCD938x codec with its soundwire
  and the speaker amplifiers; `alsa-ucm-conf` / topology in userspace.
- TODO: which codec and amplifiers the S23 uses (Samsung's DT has the answer); downstream audio is not a Qualcomm reference design.
