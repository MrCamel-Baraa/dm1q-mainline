# Registro del port postmarketOS para gts9uwifi

## 2026-07-17 — sesión 1: inicio y elección de arquitectura

- Leídos por completo `../port/README.md` y `../port/docs/porting-log.md`, junto
  con los inventarios de firmware y compatibilidad de fuentes.
- Ubuntu Touch se declara baseline estable y queda fuera del alcance de cambios.
- Inicialmente se consideró un PoC downstream 5.15.153 para obtener rápidamente
  pantalla/SSH. La usuaria pidió priorizar una base limpia y se cambió a una
  estrategia mainline-first. El kernel Samsung queda sólo como oráculo de
  hardware; no será una etapa de ejecución de postmarketOS.
- Se confirma que TWRP monta la microSD, pero todavía no que el kernel normal
  pueda usarla como raíz temprana.
- El primer acceso WSL desde el sandbox falló con `WSL_E_DISTRO_NOT_FOUND`.
  Fuera del sandbox se confirmaron `Ubuntu`, `Ubuntu-24.04` y
  `docker-desktop`. Los comandos complejos enviados con `bash -lc` también
  fallaron por quoting; a partir de ahora se ejecutarán scripts versionados.
- No se ha construido ni flasheado ningún artefacto.

## 2026-07-17 — sesión 2: auditoría mainline y DTS v0

- Fijados pmbootstrap 3.11.1 (`08213ed7...`), pmaports
  `b7681d0e857d395edfaa6c8e5cd0d89e4315fd3f` y Linux Torvalds v7.2-rc3
  `a13c140cc289c0b7b3770bce5b3ad42ab35074aa` en
  `/root/pmos-gts9u/` sobre `Ubuntu-24.04`.
- El paquete `linux-postmarketos-mainline` de ese pmaports usa el mismo RC y
  trae SM8550, SDHCI MSM, ext4, initramfs, UART y DWC3. Simpledrm y configfs
  USB estaban desactivados/como módulos, por lo que se añadió un fragmento
  X910 con los controladores tempranos built-in.
- Capturado `/sys/firmware/fdt` de la tablet por SSH; el DTB mide 1,120,765
  bytes y tiene SHA-256
  `7f02a5bb18f1ca2ff086e3038780d372463ff82062b5ef029401398b938cac83`.
  La captura recursiva del árbol sysfs se abandonó por timeout.
- Confirmado framebuffer stock `0xb8000000/0x2b00000`, panel 2960×1848,
  SDHC2 con PM8550 GPIO12/L9B/L8B, UART7 y Goodix GT9916 en I2C4.
- Se estudió usar `sm8550-samsung-q5q.dts` como include. Se descartó antes de
  obtener una build porque su MPSS/carveouts pertenecen al Fold5. El DTS v0
  es autónomo e incluye sólo los dtsi del SoC/PMIC.
- El mapa base `sm8550.dtsi` coincide con casi todas las reservas X910. Sólo
  se reemplazó `adspslpi_mem` por el tamaño Samsung `0x59b4000`, y se añadieron
  la reserva exacta `splash_region` y ramoops sobre el carveout Samsung
  `sec_log_buf` de 2 MiB.
- El DTS v0 habilita simple framebuffer, SDHC2, UART7, GT9916 y un intento USB2
  peripheral fijo. Este último es experimental: el repetidor NXP eUSB2 y el
  SM5714 Type-C/PD aún no tienen el soporte necesario upstream.

### Boot chain

- Analizada `dtbo.img` stock sin depender de dtc: header Android DT table de
  32 bytes, dos entradas, page size 4096, campos table id/rev/custom a cero.
  Se confirmaron propiedades raíz exactas de board-id 00 y 03 y sus rangos
  `dtbo-hw_rev`.
- Creados dos overlays no-op que mantienen esos selectores. No se reutiliza la
  DTBO downstream ni se crea una tabla vacía.
- El conjunto mínimo fiable se fija en `boot`, `init_boot`, `vendor_boot`,
  `dtbo` y `vbmeta`; la raíz va en SD. Recovery/TWRP conserva DTB/DTBO propios.
- `build-android-v4-bundle.sh` reproduce header v4, offsets conocidos, AVB
  footer y tamaños de partición, pero aún no se ha ejecutado porque faltan el
  kernel final y el initramfs pmOS.
- Se generó por adelantado el ZIP de vuelta atrás
  `restore-ubuntu-touch-v8-boot-sm-x910.zip`: toma boot/init/vendor/vbmeta de
  la build UT v8, DTBO del firmware X910XXS5CYG1, rellena cada miembro al
  tamaño completo de partición y no incluye `super`. SHA-256 del ZIP:
  `240599697c20c500cb180b31771f008401b1274a744ac3f81f15f5fd5b1dfcbe`.
  CRC, permiso 0755 del instalador y hashes internos fueron validados.

### Intentos de compilación

1. El primer intento falló al aplicar `add-gts9uwifi-dtb.patch`: el fichero
   contenía los dos caracteres `\\t` en vez de un tabulador. Corregido.
2. El siguiente intento heredó como cwd la ruta Windows con espacios y fue
   cortado por el timeout corto; se fuerza ahora `cd /root/pmos-gts9u`.
3. La compilación completa con el target `modules` superó diez minutos y el
   runner la terminó. No llegó a exportar artefactos. El script directo pide
   ahora sólo `Image.gz` y el DTB; el package pmOS compilará módulos después.

No se ha flasheado ni escrito ninguna microSD. La tarjeta presente de 238.3 GB
está al 96 % y queda expresamente fuera de alcance.

La documentación pmbootstrap actual todavía declara WSL no soportado por los
loop devices. El kernel se compila correctamente en WSL2, pero falta comprobar
la fase `pmbootstrap install`; si ésta falla por loop/mount se usará una VM o
contenedor Linux privilegiado, sin modificar la arquitectura del port.

Al terminar esta sesión, el ejecutor rechazó nuevas llamadas WSL por un límite
temporal de uso. Esto impide reanudar los objetos parciales y lanzar
pmbootstrap, pero no aporta evidencia de un fallo del DTS/kernel. Se detiene el
trabajo remoto de forma explícita y no se intenta eludir el control mediante
otra vía de ejecución.

## 2026-07-17 — sesión 3: build completa y bundle mainline v0

La usuaria autorizó reintentar las ejecuciones WSL. Se reanudó el mismo árbol
en `/root/pmos-gts9u/`; no se tocó la tablet ni se seleccionó ninguna unidad
física.

### Kernel y DTB

- Terminó la compilación directa de Linux 7.2-rc3. `Image.gz` mide 19.837.293
  bytes y el DTB X910 115.616 bytes. Se verificaron como built-in simpledrm,
  SD/MMC/SDHCI MSM, ext4, gadget/configfs/NCM, UART Qualcomm, GT9916 y
  ramoops/pstore.
- El DTB decompilado conserva el framebuffer 2960×1848 en `0xb8000000`, la
  reserva splash, el carveout ADSP, ramoops, SDHC2, Goodix, UART7 y USB2
  peripheral experimental.
- El APK completo `linux-samsung-gts9uwifi-mainline` terminó en 3.215,9 s.
  Su release instalada es `7.2.0-rc3` y los módulos exponen el mismo vermagic.
- `zinstall` no deja un gzip Android en `/boot/vmlinuz`, sino un EFI zboot de
  19.767.808 bytes. Su cabecera `MZ/zimg` señala un payload gzip de 19.706.845
  bytes, SHA-256 `0237f8a0930fe85dd46256ffd7e723f11078b8439d70a8c093e12f0b4760f35c`;
  al descomprimir produce un `Image` ARM64 válido de 57.344.000 bytes. El
  generador extrae ese payload para no mezclar kernel y módulos de builds
  distintas.

### pmbootstrap y rootfs

- Se instaló `kpartx` en Ubuntu-24.04 y el flujo loop/mount de pmbootstrap
  funcionó pese a que WSL no está soportado oficialmente.
- Los primeros intentos del device APK fallaron sucesivamente por un
  mantenedor no válido, ausencia de `android-tools` y falta de page size para
  mkbootimg. Se corrigieron a un RFC822 válido, dependencia explícita y
  `deviceinfo_flash_pagesize="4096"`.
- Una rootfs de una sola partición produjo un initramfs de aproximadamente
  15,15 MiB, mayor que `init_boot`, y pmbootstrap no permite
  `initramfs-extra` con `--single-partition`. Se activó
  `deviceinfo_create_initfs_extra="true"` y se generó una imagen GPT estándar
  de dos particiones.
- Imagen final: 4.634.705.920 bytes, SHA-256
  `103fe9980b7322b2fe2878bd6cf191cabe7152f4d31561623be1a9f0b36ef3b4`.
  La partición 1 es ext2 `pmOS_boot` de unos 487 MiB y la 2 ext4 `pmOS_root`
  de unos 3,8 GiB.
- El initramfs final mide 2.133.928 bytes (SHA-256 `ba13b0d...`) y
  `initramfs-extra` 13.014.943 bytes (SHA-256 `b581bbe6...`). La rootfs incluye
  edge, systemd, XFCE4/LightDM, NetworkManager, OpenSSH, `xfce4-terminal`,
  usuario `phablet`, contraseña `<DEV_PASSWORD>` y hostname `gts9u`.

### Boot chain y artefactos

- Se construyeron `boot`, `init_boot`, `vendor_boot`, `dtbo` y `vbmeta` con
  sus tamaños completos de partición. El kernel procede del zboot del package,
  el initramfs de la rootfs y el DTB del mismo package.
- Se eliminaron dos fuentes de no determinismo: AVB usa un salt derivado del
  SHA-256 previo al footer y el CPIO vendor vacío usa timestamp cero con
  `--reproducible`. Dos generaciones consecutivas dieron hashes idénticos.
- Validación correcta: hashes internos, Android header v4, offsets Samsung,
  comparaciones byte a byte, DTBO de dos selectores, AVB y tamaños. Hashes de
  imágenes: `boot dfe592dc...`, `init_boot 36ed30f9...`,
  `vendor_boot 13bf87cb...`, `dtbo 9f2dc02e...`, `vbmeta f489966f...`.
- Imagen SD comprimida final:
  `postmarketos-edge-xfce-mainline-v0-sm-x910-sd.img.zst`, SHA-256
  `592deff221c271b03a6830d2b7dc89497e327151951ceac043f4ebadb8c0b237`.
- ZIP de prueba TWRP final:
  `postmarketos-edge-xfce-mainline-v0-sm-x910-twrp.zip`, SHA-256
  `7af75c71dcb451e0cc1400a6275c2a01908894e1bde9a34f9b85f34702837bc3`.
  CRC, permisos, tamaños y manifests interno/externo pasaron. El instalador
  resuelve de forma segura particiones con o sin sufijo y no toca `super` ni
  datos.
- Se regeneró y volvió a validar el rollback
  `restore-ubuntu-touch-v8-boot-sm-x910.zip`, SHA-256
  `fd1d31a5fb77c3586171601e438bc7aa7b439fd7e4981d05f1d0aa0f209234f3`.
- Una regeneración del ZIP cambió el hash aunque las imágenes no cambiaron:
  `writestr()` estaba fechando dos entradas con la hora actual. Se fijó
  1980-01-01 para todos los miembros y se comprobó que dos ZIP mainline y dos
  rollback independientes son idénticos byte a byte.
- Se añadió `docs/testing-mainline-v0.md`. El bundle queda listo para una
  prueba manual con microSD sacrificable, pero **todavía no está validado por
  un arranque físico**. Wi-Fi no está descrito en el DTS v0 y USB NCM depende
  del repetidor NXP/SM5714 todavía no soportado; no se promete SSH en este
  primer intento.

## 2026-07-18 — sesión 4: primer flash y corrección de vbmeta RO

- Analizado `../logs/recovery.log` tras dos intentos de instalar el ZIP v0.
  TWRP reconoció correctamente la primera partición de la nueva microSD como
  ext2 en `/dev/block/mmcblk1p1`, con unos 454 MiB.
- En ambos intentos se escribieron completos y sin error `boot` (96 MiB),
  `init_boot` (8 MiB), `vendor_boot` (96 MiB) y `dtbo` (16 MiB). El instalador
  terminó con error únicamente al abrir `/dev/block/by-name/vbmeta`.
- ADB confirmó que el symlink era correcto y resolvía a `/dev/block/sde15`.
  La partición mide 131072 bytes, no 65536, y el kernel de TWRP la marca RO.
  `blockdev --setrw` devuelve éxito pero el flag permanece en 1; no se intenta
  eludir la protección escribiendo por otro nodo.
- Se extrajo la partición actual completa. `avbtool` confirmó `Algorithm:
  NONE`, `Flags: 2`, sin descriptores. Los intentos fallidos no la modificaron
  y su contenido ya es apto para arrancar imágenes custom sin verificación.
- Causa raíz: el instalador trataba toda partición existente como escribible y
  consideraba fatal el `dd` de `vbmeta`. La instalación no falló por el ZIP,
  SD, kernel ni las otras imágenes.
- El instalador v0.1 hace un preflight antes de cualquier escritura: comprueba
  tamaño de 128 KiB, flag RO y los cuatro bytes big-endian de AVB flags en el
  offset 120. Si `vbmeta` es RO sólo continúa cuando son `00000002`, conserva
  la partición y escribe las otras cuatro. Si es RW, instala el nuevo vbmeta.
- Todos los generadores y validadores usan ahora el tamaño físico 131072. El
  nuevo ZIP es
  `postmarketos-edge-xfce-mainline-v0.1-sm-x910-twrp.zip`, SHA-256
  `aaef2bb5079d9357338ae173737f9e94cca83c20c0f6d07d2466ccddc8c6aca0`.
  Bundle Android, AVB, tamaños, CRC, permisos, hashes y zstd volvieron a pasar.
- El ZIP v0.1 se copió por ADB a `/sdcard/` mientras la tablet seguía en TWRP
  y se verificó allí el mismo SHA-256. No se flasheó ni se reinició la tablet.
- El rollback se regeneró con el tamaño corregido, SHA-256
  `eee755c73105ce55311e63eb4a8a50dff42ca6338b1930c017825c510a563e06`.
  La usuaria indica que no necesita conservar la instalación UT; se mantiene
  sólo como comodidad. La prioridad de seguridad sigue siendo conservar TWRP,
  Download Mode/Odin, bootloader y particiones de calibración, no el estado de
  `super`/userdata.

## 2026-07-18 — sesión 5: rechazo del DTB por ABL y bundle v0.2

- La usuaria flasheó v0.1 y reinició. La tablet mostró el splash Samsung con
  información RPMB/secure boot y código de barras, y después volvió a TWRP.
  No era un panic ni una consola del kernel: era Odin lanzado por ABL.
- Desde TWRP se recogió un diagnóstico de sólo lectura en
  `work/mainline-first-boot-twrp-20260718.txt`. `pstore` estaba montado pero
  vacío. `/proc/last_kmsg`, de 2 MiB, sí conservaba el log completo de XBL/ABL.
- Secuencia determinante del log: ABL reconoce Hyp, fija memoria en
  `0x80000000`, descomprime el kernel en 364 ms, registra `No match found for
  Soc Dtb type`, luego `Error: Appended Soc Device Tree blob not found` y
  finalmente `Launching odin`. Linux nunca llegó a ejecutarse, por lo que no
  hay todavía evidencia sobre SD, initramfs, simpledrm o USB.
- Se compararon las imágenes v0.1 con el rollback UT funcional. Ambos kernels
  son payloads ARM64 gzip válidos; el kernel UT no contiene un FDT appended
  detectable, de modo que el texto de ABL es un fallback genérico y no prueba
  que Samsung exija adjuntar el DTB al kernel. UT arranca usando el DTB de
  `vendor_boot`.
- El FDT vivo downstream tiene en la raíz `qcom,kalama-mtp`, `qcom,kalama`,
  `qcom,mtp`; `qcom,msm-id = <0x218 0x20000 0x207 0x20000 0x207 0x10000
  0x218 0x10000>`; y `qcom,board-id = <0x10008 0x03>`. El DTB mainline v0.1
  sólo tenía `samsung,gts9uwifi`, `qcom,sm8550` y carecía de ambos IDs.
- Causa raíz: ABL filtra el DTB base de `vendor_boot` usando esos metadatos
  downstream antes de arrancar Linux. Al no encontrar coincidencia, buscó un
  DTB appended inexistente y abrió Odin.
- El DTS mainline conserva sus compatibles upstream pero antepone exactamente
  los tres compatibles Qualcomm y añade los IDs del FDT vivo. Se incrementó
  `pkgrel` y se añadió una validación que extrae el DTB desde `vendor_boot` y
  exige los tres valores exactos.
- La recompilación incremental produjo un DTB de 115.742 bytes, SHA-256
  `571d04dc585702a04db219a78666f07509ccdbe641417a861e6e9d8b869f949a`.
  Para aislar esta hipótesis, v0.2 conserva el payload del kernel empaquetado
  (y por tanto su correspondencia con los módulos de la SD) y sustituye sólo
  el DTB en `vendor_boot`; no usa el `Image.gz` de la build directa.
- Nuevo `vendor_boot.img`: SHA-256
  `3ddf6ddbbb02fc4d687145ba74e52c3085373aff9c919bf56e9248bb4514c9e9`.
  El resto de imágenes no cambió. Todos los headers Android v4, offsets, AVB,
  tamaños, DTBO, comparaciones byte a byte, selectores de ABL, CRC, modos,
  manifests y el stream zstd pasaron.
- Artefacto listo:
  `postmarketos-edge-xfce-mainline-v0.2-sm-x910-twrp.zip`, SHA-256
  `9288af69c694fdc84b7b1f9694265152c5f7959a880d338f98b2e3d106c0f65c`,
  21.850.752 bytes. Se copió a `/sdcard/` y se verificó allí el mismo hash.
  La tablet permanece en TWRP y el asistente no lo ha flasheado.

## 2026-07-18 — sesión 6: fallo ufdt de v0.2 y bundle v0.3

- Tras flashear v0.2, la tablet volvió a mostrar Odin. Se regresó a TWRP y se
  capturó inmediatamente `/proc/last_kmsg` en
  `work/mainline-v02-last-kmsg-20260718.txt`; mide 4.245.076 bytes. `pstore`
  continúa vacío porque tampoco en esta ocasión se ejecutó Linux.
- El log contiene dos intentos v0.2 idénticos. En ambos desapareció el error
  v0.1 `No match found for Soc Dtb type`: ABL descomprime el kernel y ejecuta
  `FindBestMatch GetBoardRev = 5, DtSubType = 3`. Esto valida físicamente los
  compatibles e IDs añadidos en v0.2.
- La nueva secuencia de fallo es `ApplyOverlay: ufdt apply overlay failed`,
  `Error: Dtb overlay failed`, `Root Node is not found at BoardDtb`, y más
  tarde `ERROR: Invalid device tree header`, `Device Tree update failed` y
  `Launching odin`. El fallo sigue dentro de ABL, antes de entrar en Linux.
- Se extrajeron las dos entradas de la DTBO stock: miden 814.799 y 813.811
  bytes y son overlays completos Samsung. No se pueden reutilizar sobre el DTB
  mainline porque contienen cientos de fixups a símbolos/nodos downstream.
  La entrada no-op v0.2 es estructuralmente válida y `fdtoverlay` la aplica
  correctamente sobre el DTB v0.2.
- Se compiló desde la fuente oficial de Android una utilidad local basada en
  `ufdt_apply_overlay`; también aplicó correctamente el no-op v0.2. La
  incompatibilidad observada es por tanto específica del camino/fork ufdt de
  Samsung ABL, no un FDT mal formado según libfdt/libufdt estándar.
- Diferencia relevante: el DTB base stock funcional tiene `/__symbols__`; el
  DTB mainline v0.2 no. Aunque el overlay no-op usa `target-path` y no necesita
  fixups con la implementación estándar, la ruta Samsung falla sin esa tabla.
- El parche de Makefile del kernel añade ahora
  `DTC_FLAGS_sm8550-samsung-gts9uwifi := -@`; `pkgrel` sube a 2. El nuevo DTB
  mide 150.407 bytes, SHA-256
  `c0684a774f7a8e99ca19ddae603dcdba3638afecefbda7baad54fcd56731c64c`,
  conserva los selectores ABL exactos y exporta 474 símbolos.
- `fdtoverlay` y la utilidad `ufdt_apply_overlay` oficial aplicaron el overlay
  board03 sobre la nueva base. El validador de bundle exige ahora que el DTB
  extraído de `vendor_boot` contenga `/__symbols__` además de los IDs exactos.
- Bundle v0.3: el kernel empaquetado, initramfs, DTBO, vbmeta y SD no cambian;
  sólo cambia el DTB de `vendor_boot`. El nuevo `vendor_boot.img` tiene SHA-256
  `f12fbc3d4f543438f6b2a01c546e43d0b3ca90535f092aba477b42c711fd1850`.
- ZIP final:
  `postmarketos-edge-xfce-mainline-v0.3-sm-x910-twrp.zip`, 21.856.498 bytes,
  SHA-256
  `0a0d5b0e749c17155a0503e1c6a14e340ea3b9b437a3fbbcfbd77d9219bde240`.
  Pasó todas las validaciones, se reprodujo byte a byte, se copió a
  `/sdcard/` y se verificó allí. La tablet permanece en TWRP; el asistente no
  lo ha flasheado.

## 2026-07-18 — sesión 7: ufdt v0.3 descartado y fallback appended-DTB v0.4

- Tras flashear v0.3, la tablet volvió a Odin. Desde TWRP se capturó
  `work/mainline-v03-last-kmsg-20260718.txt`, de 4.238.058 bytes. `pstore`
  sigue vacío.
- La secuencia es indistinguible de v0.2: ABL descomprime el kernel, selecciona
  correctamente el DTB, tarda unos 10,6 ms y devuelve `ApplyOverlay: ufdt
  apply overlay failed`, `Root Node is not found at BoardDtb`, `Invalid device
  tree header` y `Launching odin`. Los 474 símbolos de v0.3 no cambian el
  comportamiento del fork Samsung; esa hipótesis queda descartada.
- Se recuperó como referencia el flujo Qualcomm ABL/Tianocore del commit
  `2a0c8e9714930333c059b820b857f925d4d3a3dd`. `BootLinux.c` llama a
  `LoadAndValidateDtboImg`: si la magia/tabla DTBO no es válida, omite
  `GetBoardDtb` y `ufdt_apply_overlay` y llama a `DeviceTreeAppended` sobre el
  contenido situado después del gzip. `Decompress.c` devuelve precisamente la
  posición final del miembro gzip como `DtbOffset`.
- Se elige ese fallback en vez de inventar IDs PMIC para forzar un supuesto
  exact-match o seguir alterando un overlay que las implementaciones estándar
  sí aceptan pero Samsung rechaza.
- El generador admite ahora `APPEND_DTB_TO_KERNEL=1`: conserva sin cambios el
  `Image.gz` del package y concatena el DTB raw inmediatamente después. El
  validador separa ambas regiones y las compara byte a byte con sus fuentes.
- `DISABLE_RUNTIME_DTBO=1` genera una imagen con prefijo cero, no una Android
  DT table. Después añade un footer hash AVB correcto y la expande a los
  16.777.216 bytes exactos. El validador exige la magia nula y sigue ejecutando
  `avbtool verify_image`. TWRP lleva recovery DTB/DTBO propios; el rollback
  restaura la DTBO stock si fuese necesario.
- Hashes de las imágenes modificadas: `boot.img`
  `342a2dc8e78267b1463d59fb8f889c456ea47bba899d7c314c9cb18a921aaa64`;
  `dtbo.img`
  `c17418be08365c03a5ce3a220af734b14ec2e6b03c0cbc1ed9721be6f21d3ef3`.
  `vendor_boot`, initramfs, vbmeta, kernel ejecutable y SD no cambian.
- ZIP v0.4:
  `postmarketos-edge-xfce-mainline-v0.4-sm-x910-twrp.zip`, 21.884.702 bytes,
  SHA-256
  `2083daf1ad515b32634a8f5686adc4972064ff8fd03153da0e6654d49f97a679`.
  Pasó headers, AVB, tamaños, comparaciones, CRC, manifests y zstd; se reprodujo
  byte a byte, se copió a `/sdcard/` y se verificó allí. La tablet sigue en
  TWRP y el asistente no lo ha flasheado.

## 2026-07-18 — sesión 8: Linux ejecuta, fatal NoC y bundle v0.5

- La usuaria flasheó v0.4. Por primera vez aparecieron la consola verbose y el
  logo de Linux; después la tablet se reinició. Esto valida físicamente la ruta
  appended-DTB y demuestra que ABL ya entrega el control al kernel mainline.
- De vuelta en TWRP se recogieron `/proc/last_kmsg`, `/proc/cmdline`, dmesg y
  pstore en `work/v04-linux-crash-20260718/`. Pstore estaba vacío.
  `/proc/last_kmsg` contiene el diagnóstico del siguiente XBL, que registra
  reset por PSHOLD, `restart_reason = 0x5023881` y
  `upload_cause = TZBSP_ERR_FATAL_NOC_ERROR`. La sección con información NoC,
  XPU y SMMU indica que el log TZ está cifrado, por lo que no revela
  maestro/esclavo, dirección o driver causante.
- Se descartó tratarlo como un panic ordinario o un fallo ABL. La salida Linux
  llegó a pantalla y el reset fue solicitado por firmware seguro; todavía no
  hay evidencia de que se montase la raíz de la microSD.
- Se compararon con `fdtget` todos los rangos de `/reserved-memory` del FDT vivo
  y del DTB mainline. El dtsi upstream cubría la mayoría de carveouts Qualcomm,
  pero el DTB v0.4 omitía los que normalmente añade la DTBO Samsung:
  `kaslr`, `uh_heap`, `uh_guest`, `chipinfo`, `sec_xbl_ramdump`, LLCC LPI y los
  rangos altos `sec_debug_pool`, reset info, debug BL, pmsg, debug kinfo, HDM y
  `sec_qcom_rdx`. En RAM alta sólo se había conservado `sec_log_buf` para
  ramoops; aproximadamente 180 MiB protegidos quedaban disponibles para el
  buddy allocator. También el HW-fence upstream era `0x64000` bytes menor que
  el rango X910.
- Hipótesis mínima v0.5: un acceso normal de Linux a esos rangos protegidos
  provoca el fatal NoC. Se añadieron las reservas fijas exactas del FDT vivo,
  todas `no-map` salvo el carveout ramoops, y se amplió HW-fence. No se cambió
  USB, Goodix, SD, cmdline, kernel ejecutable, initramfs ni rootfs, para aislar
  el efecto del mapa de memoria.
- El DTS compila sin errores. DTB final: 152.392 bytes, SHA-256
  `78397ab9c916084a68b37a5b19de2d1cd2619691201552f1ecc60a483ab44cd0`.
  El validador extrae el DTB de `vendor_boot` y exige los 15 rangos exactos,
  además de símbolos y selectores ABL.
- Imágenes modificadas: `boot.img`
  `384cdf879ed81f053cf3aeab4795f1d80b87f21c6692cbd4faeecfb58fe41af6`
  y `vendor_boot.img`
  `80fbd52d4e3d03f37a08d2cf90ce7eda44d94864cb4653151d4680dd4c525e63`.
  `dtbo`, `init_boot`, `vbmeta`, payload gzip y la imagen SD no cambiaron.
- ZIP v0.5:
  `postmarketos-edge-xfce-mainline-v0.5-sm-x910-twrp.zip`, 21.885.945 bytes,
  SHA-256
  `1ae10d4effba444a3d970e9c6a68bd11f9304692a7bffcf309633b9063388314`.
  Pasó AVB, headers v4, offsets, appended-DTB, carveouts, tamaños, CRC, modos,
  manifests y zstd; una segunda generación fue idéntica byte a byte. Se copió
  a `/sdcard/` y se verificó el mismo hash en TWRP. El asistente no lo flasheó.

## 2026-07-18 — sesión 9: vídeo v0.5, LPASS AG NOC y bundle v0.6

- La usuaria probó v0.5 y grabó `C:/Users/agcar/Downloads/20260718_033322.mp4`.
  Linux volvió a mostrar verbose/logo y reinició. Desde TWRP se recogieron
  `work/v05-linux-crash-20260718/last_kmsg`, dmesg, iomem y pstore. El reset es
  de nuevo `TZBSP_ERR_FATAL_NOC_ERROR`, ahora con
  `restart_reason = 0x5023a01`; pstore continúa vacío. Los carveouts v0.5 se
  mantienen por corrección, pero no eran el desencadenante inmediato.
- Se extrajeron fotogramas a 2 fps y capturas originales de los últimos
  segundos. El último frame legible antes de apagarse muestra a `26.772 s` el
  retorno correcto de `7400000.interconnect` y `7430000.interconnect`.
  Según el orden de `sm8550.dtsi`, el siguiente proveedor es
  `lpass_ag_noc: interconnect@7e40000`; no aparece su línea de retorno.
- La hipótesis v0.6 deshabilita únicamente `lpass_ag_noc`. Audio no es necesario
  para el primer rootfs/SSH y los otros dos NOC LPASS quedan activos porque el
  vídeo demuestra que sus probes terminan. Si v0.6 avanza, habrá que reconstruir
  la secuencia de alimentación específica X910 antes de reactivarlo.
- TWRP no expone el ramoops mainline porque recovery arranca con otro DTB y no
  registra ese backend. Se estudió el driver downstream `sec_log_buf`: usa una
  cabecera de 16 bytes (`boot_cnt`, magia `0x4d474f4c`/`LOGM`, `idx`,
  `prev_idx`) y un ring que recovery presenta como `/proc/last_kmsg`.
- Se añadió un driver built-in mínimo
  `SAMSUNG_GTS9UWIFI_SEC_LOG`: mapea el carveout real `0x880200000/2 MiB`,
  inicializa la cabecera compatible, registra una consola con
  `CON_PRINTBUFFER` y conserva el índice circular. El DTB sustituye el backend
  ramoops por `sec-log@880200000` y el nodo `sec-kernel-log`. Así, un próximo
  fatal temprano debería dejar printk recuperable desde TWRP.
- La build directa compiló el nuevo objeto y confirmó la opción, el texto del
  driver y `status = "disabled"` en `7e40000`. Después se reconstruyó mediante
  pmbootstrap el APK completo `linux-samsung-gts9uwifi-mainline-7.2_rc3-r4`,
  la rootfs y los initramfs, evitando mezclar el kernel directo con módulos
  anteriores. Kernel release y vermagic son `7.2.0-rc3`.
- Payload gzip empaquetado: SHA-256
  `34d1de801785b7bdab795f596ccebfd393557d3cd991af97307e40303c25f0a8`.
  DTB empaquetado: SHA-256
  `61b0bc560ad8f62f2aa06cb48bfe20cfdeff62678b8e43655b3434c268528081`.
  Initramfs: 2.134.007 bytes; `initramfs-extra`: 13.014.904 bytes.
- Imagen SD v0.6:
  `postmarketos-edge-xfce-mainline-v0.6-sm-x910-sd.img.zst`, 472.948.641
  bytes, SHA-256
  `6250db18ed8afaad2afd8d98dad376305fccefa0518be806c3cf08af0791939e`.
  Descomprimida mide 4.634.705.920 bytes y tiene SHA-256
  `62704236c7faa4b819a19751eefb32dfdafbf6151ce834738ac5a4d3d191a759`.
- ZIP TWRP v0.6:
  `postmarketos-edge-xfce-mainline-v0.6-sm-x910-twrp.zip`, 21.883.967 bytes,
  SHA-256
  `0890bbe1160aa5b03d40963209ae2a5193d7857531ee2518f0adbaf522d31a9a`.
  Bundle, AVB, DTB/status, consola persistente, tamaños, CRC, manifests y zstd
  pasaron. ZIP e imagen SD se reprodujeron byte a byte. El ZIP se copió y
  verificó en `/sdcard`; el asistente no flasheó nada.

## 2026-07-18 — sesión 10: `last_kmsg` mainline completo y traza pre-probe v0.7

- La usuaria probó v0.6 y la tablet volvió a reiniciarse. Se recogieron desde
  TWRP `last_kmsg`, cmdline, dmesg, iomem e índice pstore en
  `work/v06-linux-crash-20260718/`. El reset sigue siendo
  `TZBSP_ERR_FATAL_NOC_ERROR`, con `restart_reason = 0x58238a1`.
- La consola Samsung `LOGM` introducida en v0.6 funcionó: `/proc/last_kmsg`
  mide 453.717 bytes y contiene el printk mainline completo, desde la versión
  del kernel hasta el instante exacto anterior al firmware/XBL siguiente.
  Pstore continúa vacío, pero ya no es necesario y no harán falta vídeos en
  pruebas normales mientras se conserve este backend.
- Deshabilitar `lpass_ag_noc@7e40000` no cambió el punto visible del corte. En
  deferred probe terminan correctamente `7400000.interconnect` a 26,806 s y
  `7430000.interconnect` a 26,813 s; no se registra ningún retorno posterior.
  Por tanto la hipótesis v0.6 queda descartada y el nodo permanece aislado sólo
  por prudencia mientras el audio está fuera del primer hito.
- `8804000.mmc` había devuelto `-EPROBE_DEFER` a 23,698 s. Por el orden del DT
  su reintento después de los proveedores interconnect es el candidato
  principal, pero una línea de retorno no demuestra qué probe empieza después.
- Se añadió `log-probe-entry-before-call.patch`: con `initcall_debug`,
  `really_probe_debug()` imprime `probing <device> with driver <driver>` antes
  de entrar en `->probe()`. La consola persistente escribe esa línea de forma
  síncrona, por lo que debe sobrevivir aunque TrustZone reinicie dentro del
  driver. `pkgrel` queda en 5 y el script de build directo aplica el parche.
- Para reducir desgaste y tiempo de prueba, v0.7 reutiliza el DTB, initramfs,
  release y módulos de la SD v0.6; sólo sustituye el ejecutable built-in del
  kernel. No hay cambios de símbolos, configuración ni ABI de módulos.
- El bundle Android v4 v0.7 pasó hashes internos, tamaños exactos, headers,
  appended-DTB y verificación AVB. ZIP reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.7-probe-trace-sm-x910-twrp.zip`,
  22.012.743 bytes, SHA-256
  `1362e7f9ecf4cedd082af4cbabb963a651215292a7bcd847007978bf5bd3c2be`.
  Se copió a `/sdcard` y su hash remoto coincide. El asistente no lo flasheó.

- El arranque físico v0.7 produjo un `last_kmsg` de 453.927 bytes. La última
  entrada mainline, inmediatamente después del retorno correcto de
  `7430000.interconnect`, es `probing f100000.pinctrl with driver sm8550-tlmm`;
  no aparece su retorno. El siguiente firmware registra
  `restart_reason = 0x5003a01` y `TZBSP_ERR_FATAL_NOC_ERROR`. Se descarta así
  `8804000.mmc` como causante de este reset.
- El primer intento de TLMM a 6,016 s había devuelto `-EPROBE_DEFER`; el fatal
  sucede al reintentarlo cuando ya existe el dominio wakeup/PDC. El FDT vivo
  Samsung describe el TLMM downstream en `0xf000000` y, de forma decisiva,
  marca `qcom,gpios-reserved = <36 37 38 39>`. El desplazamiento de base no es
  por sí mismo un error: el driver mainline parte de `0xf100000` y usa offsets
  por GPIO equivalentes. La reserva segura sí faltaba.
- Se añadió a `&tlmm` la propiedad estándar mainline
  `gpio-reserved-ranges = <36 4>`. Es el equivalente exacto de la X910 y evita
  que gpiolib/irqchip acceda a registros TLMM propiedad de TrustZone. No se
  copiaron GPIO50–51 del Fold5, ausentes en la evidencia de nuestra placa.
- DTB v0.8: SHA-256
  `e3c872e9eae8865d4ff8f5b6871d896ef60261ff73556475e522ac48c298ed66`.
  El kernel instrumentado, initramfs, módulos y SD siguen siendo los de v0.7/
  v0.6; sólo cambia el DTB appended y su copia en vendor_boot.
- ZIP v0.8 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.8-tlmm-reserved-sm-x910-twrp.zip`,
  22.012.795 bytes, SHA-256
  `74607d30076c92cc7fcae787534e26d9ea083a4da60280c551e0a75e87788c92`.
  Se verificó estática y remotamente en `/sdcard`; el asistente no lo flasheó.

## 2026-07-18 — sesión 11: v0.8 supera TrustZone y logger robusto v0.9

- El arranque v0.8 dejó de reiniciarse por firmware. La tablet permaneció en
  una pantalla de kernel panic hasta que la usuaria la reinició manualmente a
  TWRP. La reserva `gpio-reserved-ranges = <36 4>` queda validada físicamente:
  el registro de TLMM ya no dispara el fatal NoC de TrustZone.
- Se recogió `work/v08-linux-panic-20260718/last_kmsg`, pero mide exactamente
  2.097.136 bytes y contiene el ring circular del recovery anterior, no el
  boot mainline. Pstore sigue vacío y TWRP no dispone de `/dev/mem`.
- Causa del fallo de captura: el logger mainline ponía `previous_index` al
  valor antiguo al iniciar y después sólo avanzaba `index`. Un reset fatal
  gestionado por firmware actualizaba la instantánea, como en v0.6/v0.7, pero
  el reinicio manual desde el panic no pasó por esa ruta. Recovery interpretó
  el índice anterior y expuso la sesión vieja.
- `keep-sec-log-previous-index-current.patch` hace avanzar `previous_index`
  junto a `index` en cada escritura. No cambia el formato ni el tamaño del
  ring; permite que `/proc/last_kmsg` conserve el stream mainline tras un
  reinicio manual. `pkgrel` sube a 6.
- Kernel v0.9 `Image.gz`: SHA-256
  `811de097a805e6008795f34803c3877a3505aa96a53624ae8c754664072c6f57`.
  DTB permanece en
  `e3c872e9eae8865d4ff8f5b6871d896ef60261ff73556475e522ac48c298ed66`;
  initramfs, módulos y SD v0.6 no cambian.
- ZIP v0.9 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.9-panic-log-sm-x910-twrp.zip`,
  22.012.505 bytes, SHA-256
  `e7a2d8b3264cc94cdf6863d8abdbbd5c90e6515d1c4577b4f3fd3651fd680375`.
  Se validó y copió a `/sdcard`; el asistente no lo flasheó.
- La primera prueba física de v0.9 volvió a terminar en el mismo panic visible.
  Al recoger `/proc/last_kmsg`, el recovery llevaba 1.026 s arrancado y el
  fichero ocupaba los 2.097.136 bytes máximos. Sólo contenía printk downstream
  del TWRP actual: en esos 17 minutos el recovery había escrito una vuelta
  completa al ring y sobrescrito el boot anterior. Esto no refuta el arreglo
  de índices; impone recuperar el fichero inmediatamente. Se repetirá v0.9 sin
  reflashear ni reescribir la SD.
- La repetición se capturó con sólo 146 s de TWRP, pero tampoco contiene el
  mainline. Entre ambas sesiones aparece `XBL(28, restored from storage)` y
  después arranca directamente el kernel 5.15 Foldiby de recovery. Esto prueba
  que el reinicio forzado desde la pantalla de panic restaura el log antiguo
  persistido por XBL; el contenido mainline se pierde antes de TWRP.
- Se contrastó el formato con el driver Samsung moderno
  `sec_log_buf_main.c`/`sec_log_buf_last_kmsg.c`: recovery copia el ring según
  `idx` durante su probe y sólo después empieza a registrar su propio printk.
  `prev_idx` no selecciona la instantánea en este driver. La estrategia debe
  conservar físicamente la RAM, no seguir ajustando el lector.
- v0.10 cambia sólo cmdline: elimina `initcall_debug`, usa `loglevel=7` y añade
  `panic=10`. Así el log mainline es mucho menor y el kernel reinicia en
  caliente diez segundos después del panic. La usuaria podrá interceptar ese
  reinicio para entrar en TWRP sin el reset forzado que activa la restauración
  de XBL.
- ZIP v0.10 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.10-auto-panic-sm-x910-twrp.zip`,
  22.012.502 bytes, SHA-256
  `47331b9616f68048f381b61d52e9a6e1ff74f3ab35dcb46addae5d39e7ae372a`.
  Se validó y copió a `/sdcard`; el asistente no lo flasheó.

## 2026-07-18 — sesión 12: v0.10, falsa apariencia de panic y canal USB fallido

- La prueba física v0.10 y su repetición no conservaron el printk mainline.
  Las capturas inmediatas `work/v010-linux-panic-warm-20260718/last_kmsg` y
  `work/v010-return-20260718-174922/last_kmsg` miden 2.097.136 bytes, contienen
  `XBL(... restored from storage)` y sólo el ring recovery/XBL antiguo. El
  reinicio automático o normal tampoco proporciona el canal persistente que
  se esperaba; no se seguirá iterando sobre los índices LOGM.
- Se desempaquetó íntegro el initramfs pmOS v0.10. `/init` busca durante 30 s
  la etiqueta `pmOS_boot`, monta esa partición, extrae `initramfs-extra` y pasa
  a `/init_2nd.sh`; no depende de un parámetro `root=` en la cmdline.
- La función `fail_halt_boot()` no llama a panic. Crea un FAT de 32 MiB con
  `pmOS_init.txt`, `dmesg.txt`, `blkid.txt`, `partitions.txt`, cmdline y FDT;
  intenta exponerlo como `PMOS_LOGS`, entra en `debug_shell()` y después
  duerme indefinidamente. Por tanto la pantalla que se describió como kernel
  panic puede ser realmente el error/halt del initramfs y `panic=10` no puede
  reiniciarlo.
- La shell diagnóstica también ofrece ACM `ttyGS0` o telnet sin contraseña en
  `172.16.42.1:23`, con DHCP para el host en `172.16.42.2`.
- Se reutilizó v0.10 sin flashear y se reinició por ADB desde TWRP. Durante más
  de 80 s Windows no detectó el volumen `PMOS_LOGS`, puerto serie, NCM/RNDIS ni
  interfaz en `172.16.42.0/24`. Aparecieron dos dispositivos USB desconocidos
  con error de solicitud de descriptor: el enlace tiene actividad parcial,
  pero el gadget mainline no ofrece aún un canal utilizable.
- Próximo paso: leer una foto fija de la pantalla detenida. Si no contiene el
  error suficiente, construir una v0.11 que muestre un resumen compacto de
  `/pmOS_init.log` y lo copie a `pmOS_boot` cuando la SD sea visible. La primera
  decisión será si `sdhc_2` no enumera o si el fallo ocurre después de montar
  boot/root; no se tocará hardware sin esa evidencia.

## 2026-07-18 — sesión 13: panic transcrito, microSD validada y bundle v0.11

- La foto fija `codex-clipboard-833caf54-71b2-45e3-aea4-305fa3c40946.webp`
  permitió ampliar el final completo. Corrige la hipótesis de la sesión 12:
  v0.10 no llega a `fail_halt_boot()` ni ejecuta `/init`; es un panic real del
  kernel al no poder desempaquetar el initramfs.
- La secuencia exacta visible es `Initramfs unpacking failed: invalid magic at
  start of compressed archive`, `Waiting for root device...`,
  `/dev/root: Can't open blockdev`, `VFS: Cannot open root device "(null)" or
  unknown-block(0,0): error -6` y la petición de una opción `root=`. Sin
  initramfs ejecutable y sin `root=` deliberadamente, el panic es consecuencia
  directa.
- Antes del fallo, el kernel enumera la tarjeta como `mmcblk1` y lista
  `mmcblk1p1`/`mmcblk1p2`. Esto valida por primera vez en hardware mainline
  SDHC2, pinctrl, reguladores, card-detect y el acceso inicial a la microSD.
- Desde TWRP se verificó que `p1` es ext2 `pmOS_boot`, `p2` es ext4
  `pmOS_root`, y recovery monta `p1`. `e2fsck -fn` completa las cinco pasadas
  de boot; el e2fsck antiguo de TWRP no entiende `FEATURE_C12` de root, pero
  su superbloque figura limpio. No se alteró la tarjeta.
- Se extrajo el ramdisk real de `init_boot` v0.10: gzip válido de 2.134.007
  bytes, CPIO válido de 7.168.248 bytes con `/init` y mkinitfs completo. El
  config empaquetado tiene `CONFIG_BLK_DEV_INITRD=y` y todos los `CONFIG_RD_*`,
  así que no se trata de un CPIO truncado ni de omitir el descompresor.
- La comparación con X910XXS5CYG1 muestra que Samsung usa LZ4 legacy, magia
  `02 21 4c 18`, tanto en `init_boot` (1.747.596 bytes) como en el vendor
  ramdisk (13.495.656 bytes). v0.10 combinaba vendor LZ4 con generic gzip; ABL
  entrega esa composición en una forma que mainline rechaza antes de PID 1.
- `build-android-v4-bundle.sh` recomprime ahora por defecto el mismo CPIO pmOS
  a LZ4 legacy. `validate-android-v4-bundle.sh` exige la magia stock, verifica
  LZ4 y compara el stream descomprimido contra el gzip pmOS original. No cambia
  ningún fichero interno del initramfs.
- El LZ4 resultante mide 2.410.662 bytes. `init_boot.img` v0.11 tiene SHA-256
  `bedcad22a49dbf442641dcaf13e3290edd87b221cbca6fb8f47b8f2460c16922`;
  `boot`, `vendor_boot`, `dtbo` y `vbmeta` son idénticos a v0.10.
- ZIP v0.11:
  `postmarketos-edge-xfce-mainline-v0.11-lz4-initramfs-sm-x910-twrp.zip`,
  21.988.029 bytes, SHA-256
  `9cdc1bdd4d6be730a3b64fd66c5413794889f6cc1c0fcc25ea1977604a3713f1`.
  Pasó dos generaciones idénticas, hashes internos, tamaños Android v4, AVB,
  appended-DTB, reservas TLMM/memoria, CRC y comparación íntegra del CPIO. Se
  copió a `/sdcard` y el hash remoto coincide; el asistente no lo flasheó.

## 2026-07-18 — sesión 14: primer login gráfico mainline y bloqueo USB

- La usuaria flasheó v0.11 y confirmó el primer arranque completo. La tablet
  ejecuta el initramfs LZ4, monta `pmOS_boot`/`pmOS_root`, arranca systemd y
  presenta el login de LightDM/XFCE4 para `phablet`. Simpledrm mantiene el
  framebuffer a resolución completa. Se validan así kernel, SD, initramfs,
  rootfs y escritorio ligero en hardware real.
- Buffyboard aparece como teclado en pantalla, pero el Goodix GT9916 todavía
  no produce entrada, de modo que no se puede iniciar sesión localmente.
- Con la tablet viva y conectada se inventariaron PnP, adaptadores, DHCP, ARP,
  ICMP y TCP/22. No aparece ACM, NCM/RNDIS ni una interfaz `172.16.42.0/24`;
  `172.16.42.1` no responde y Windows conserva dos dispositivos desconocidos
  con error al solicitar descriptor. No existe aún un canal SSH.
- La foto anterior del verbose contiene la causa temprana de ese síntoma:
  DWC3 registra `-ETIMEDOUT: failed to initialize core`. El DTS actual habilita
  sólo `usb_1_hsphy`, elimina el superspeed y fuerza peripheral/HS, pero no
  modela el repetidor físico NXP; confiaba experimentalmente en el estado de
  ABL.
- El FDT vivo X910 confirma el repetidor `nxp,eusb2-repeater` en I2C `0x4f`,
  rails `vdd18`/`vdd3`, reset PM8550VS GPIO4 y overrides
  `<0x20 0x06 0x21 0x07 0x63 0x08 0x01 0x0a>`. La PHY eUSB2 stock lo referencia
  como `usb-repeater`.
- En esta primera revisión se creyó que Linux 7.2-rc3 no tenía soporte para el
  NXP I2C y se planteó portar la secuencia Samsung. La auditoría completa de la
  sesión siguiente encontró el driver upstream exacto `phy-nxp-ptn3222`, por
  lo que esta hipótesis queda corregida y no se creará un driver local.
- Al cierre de esa sesión quedaban pendientes los logs persistentes y el
  soporte del repetidor; ambos se investigan y corrigen en la sesión siguiente.

## 2026-07-19 — sesión 15: journal v0.11 y bundle USB/táctil v0.12

- Con la tablet de nuevo en TWRP se montó `/dev/block/mmcblk1p2` como ext4
  `ro,norecovery` en `/tmp/pmos-root`. Se extrajo sin modificar la tarjeta el
  journal persistente de systemd, de 8 MiB, a
  `work/v011-rootfs-logs-20260719/` y se convirtió a texto.
- El journal fija el fallo USB: `dwc3-qcom a600000.usb: DWC3 controller soft
  reset failed`, seguido de `error -ETIMEDOUT: failed to initialize core` y
  fallo de probe `-110`. DWC3 nunca registra el gadget, lo que explica los
  descriptores fallidos del host y la ausencia de NCM/SSH.
- El mismo journal fija el bloqueo del táctil: `a90000.i2c` termina en deferred
  probe con `geni_i2c: Failed to get tx DMA ch`. `CONFIG_QCOM_GPI_DMA` era
  módulo; I2C4 e I2C6 dependen ambos de `gpi_dma1`, así que no podían alcanzar
  Goodix ni el repetidor durante el arranque. Tampoco existía `/dev/input`.
- La revisión completa de Linux 7.2-rc3 encontró
  `drivers/phy/phy-nxp-ptn3222.c` y el binding
  `Documentation/devicetree/bindings/phy/nxp,ptn3222.yaml`. Es exactamente un
  proveedor PHY con `vdd3v3`, `vdd1v8` y reset GPIO, y upstream lo encadena al
  HS PHY mediante `phys`; no hace falta portar el framework Samsung.
- Del FDT stock X910 se trasladaron sólo datos contrastados: PTN3222 en I2C6
  `0x4f`, PM8550B LDO5 a 3.104 V, PM8550B LDO15 a 1.8 V y reset
  PM8550VS-D GPIO4 activo-bajo. `usb_1_hsphy` referencia el repetidor; DWC3
  continúa deliberadamente en peripheral/high-speed.
- El primer DTS de prueba referenció `gpi_dma0`, etiqueta inexistente en el
  `sm8550.dtsi`, y la compilación falló. La inspección de las DMA de I2C4/I2C6
  confirmó que ambas pertenecen a `gpi_dma1`; se eliminó la referencia errónea
  y la siguiente build terminó correctamente.
- El fragmento r7 integra `CONFIG_QCOM_GPI_DMA=y`,
  `CONFIG_PHY_NXP_PTN3222=y`, `CONFIG_INPUT_UINPUT=y` y `CONFIG_UHID=y`.
  `Image.gz` resultante: SHA-256
  `195608d3dcb49c896e48f57510bf65327190be4939c8e1995d119375b803443c`;
  DTB: `6f5fb0944a3438a48c09a8deaec2540c862b4fa11970595c806fb5b1337467ea`;
  config: `e29bca4b34e4137d4341036a7d161ee644a5dcc4f83f8a804b4e1d72242a41d0`.
- El validador Android v4 exige ahora los cuatro built-ins, GPI DMA activo,
  I2C4/I2C6 activos a 400 kHz, PTN3222 con `#phy-cells = 0`, GPIO4
  activo-bajo, phandle enlazado desde la HS PHY y DWC3 peripheral/HS. La
  primera ejecución del validador usó la ruta equivocada `usb@a6f8800` y
  falló de forma segura; el nodo SM8550 real es `usb@a600000` y se corrigió.
- ZIP v0.12:
  `postmarketos-edge-xfce-mainline-v0.12-usb-touch-sm-x910-twrp.zip`,
  22.009.191 bytes, SHA-256
  `bf8067a1eb652b0154b8c8614ce254720a94cce96b428f465371890eb01fa5f2`.
  Dos ejecuciones produjeron exactamente el mismo ZIP. Pasó headers Android
  v4, LZ4 legacy, hashes internos, appended-DTB, AVB y las nuevas aserciones
  de hardware. Se copió a `/sdcard` y `sha256sum` allí coincide. El asistente
  no flasheó ninguna partición.
- Reto inmediato: prueba física v0.12. Si USB enumera, entrar por NCM/SSH y
  comprobar `dmesg`, `ip`, el gadget y `libinput`; en paralelo verificar si el
  GT9916 crea `/dev/input/event*`. Si falla, el journal de la SD permitirá
  separar init del PTN3222, DWC3 y firmware Goodix sin depender de vídeo.

## 2026-07-19 — sesión 16: resultado físico inicial v0.12

- La usuaria flasheó v0.12. El sistema sigue alcanzando LightDM/XFCE mediante
  simpledrm, pero el táctil no responde; por tanto integrar `gpi_dma1` no basta
  por sí solo para exponer el GT9916.
- Con la tablet encendida, Windows no presenta ADB, ACM, NCM/RNDIS ni un nuevo
  adaptador IPv4. Permanecen dos dispositivos USB desconocidos por error de
  descriptor, el mismo síntoma externo de v0.11, y `172.16.42.1:22` no
  responde. El soporte inicial upstream del PTN3222 no ha resuelto por sí solo
  el enlace físico.
- Un barrido concurrente de `<LAN_SUBNET>` encontró SSH en `.138` y `.150`.
  La usuaria confirmó posteriormente que `.138` es otro dispositivo pmOS de
  la red y debe ignorarse; `.150` también es otro equipo. No se obtuvo canal
  remoto atribuible a la tablet.
- Próximo paso obligatorio: volver a TWRP, montar `mmcblk1p2` en sólo lectura
  y extraer el journal de este arranque. Se compararán registro/deferred probe
  de `gpi_dma1`, I2C4/I2C6, PTN3222, DWC3, firmware Goodix y `/dev/input` antes
  de preparar v0.13.

## 2026-07-19 — sesión 17: journal v0.12 y correcciones Goodix/PTN3222 v0.13

- Con la tablet en TWRP se montó `/dev/block/mmcblk1p2` exclusivamente como
  `ro,norecovery` en `/tmp/pmos-root`. Se extrajeron el journal persistente,
  Xorg y los logs de boot/LightDM a `work/v012-rootfs-logs-20260719/`; el
  journal original tiene SHA-256
  `be7e7a159b56d06874a7360310c73d6a42578749a76aaa33cd0aafb53d595794`.
  La partición se desmontó después sin modificar el rootfs.
- El boot v0.12 demuestra que el arreglo GPI DMA funcionó. A 1,628 s aparece
  `Goodix Berlin Capacitive TouchScreen` en
  `a90000.i2c/i2c-4/4-005d/input/input0`. Inmediatamente, cada evento real se
  rechaza con `touch data checksum error`; el fallo ya no es I2C, DMA, probe
  ni firmware.
- `goodix_berlin_core.c` obtiene `point_struct_len` desde `IC_INFO`, pero el
  parser upstream usaba ocho bytes constantes. El driver Samsung GT6936 de
  referencia usa cabecera de ocho, puntos de 16 y checksum sobre
  `event_num * 16 + 2`; también codifica ID/acción y coordenadas en un layout
  distinto. Se creó el parche trazable
  `support-samsung-goodix-16-byte-events.patch`, que selecciona el formato de
  8/16 bytes dinámicamente y mantiene compatibilidad con el upstream normal.
- El primer parche unificado escrito manualmente tenía conteos de hunk
  incorrectos. `git apply --check` lo detectó antes de compilar; se corrigió y
  la versión final aplica limpiamente sobre Linux mainline sin modificar.
- El DT activo stock publica `sec,max_coords = <1848 2960>`, no 1080×2400.
  El DTS r8 usa esas dimensiones y conserva `touchscreen-swapped-x-y`.
  Además se encontró `CONFIG_INPUT_EVDEV=m`: en la build directa sin módulos
  explicaba que no hubiera `/dev/input/event*` aunque existiera `input0`.
  Desde v0.13 `CONFIG_INPUT_EVDEV=y`.
- Para USB, el journal v0.12 muestra la cadena exacta de deferred probe:
  `a600000.usb` espera a `88e3000.phy`, que espera al PTN3222 `1-004f`.
  Antes aparece `qcom-spmi-gpio ... gpio@8800: pin_config_group_set op failed
  for group 3`. El DTS usaba `drive-strength = <2>`, propiedad no aceptada por
  el pinctrl SPMI Qualcomm. Se reprodujo el FDT stock del reset PM8550VS-D
  GPIO4: función normal, entrada y salida habilitadas, push-pull, bias
  deshabilitado, `power-source = <1>` y `qcom,drive-strength` medio.
- Una primera generación etiquetada v0.13 se completó antes de descubrir que
  EVDEV seguía como módulo. Su SHA empezaba por `501cc`; se descartó, no se
  copió a la tablet y no debe probarse. Después se recompiló kernel, DTB y
  bundle con EVDEV built-in. Una ejecución de build agotó el tiempo del runner
  cuando los outputs ya estaban completos; los hashes y las dos ejecuciones
  finales del empaquetado validaron esos outputs.
- Build directa final: `Image.gz` SHA-256
  `7cd3f980dab521874823d2a066b616cbfe39f13e6309c39ed0aa06a2b88f5c8b`;
  DTB `f38a0cfd5f5ed3430f210b2c8533f836871038992ee7b318f28577e1ca74a60f`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
  La compilación incluye `goodix_berlin_core.o` y `drivers/input/evdev.o`.
- El validador exige ahora `CONFIG_INPUT_EVDEV=y`, descomprime el Image
  empaquetado y localiza la cadena diagnóstica del parche, valida 1848×2960 y
  el intercambio de ejes, y comprueba todas las propiedades del reset PTN3222
  además de la cadena USB ya existente.
- ZIP final v0.13:
  `postmarketos-edge-xfce-mainline-v0.13-goodix-ptn-reset-sm-x910-twrp.zip`,
  22.018.623 bytes, SHA-256
  `c69e7b53db8e176eca2396fea4137e26c1ccdf6e8dce8fab1f166ca8e74a0b98`.
  Hashes internos: boot
  `b0c717000339e410f31a897bee511be162276345d8e4fbc294a8a95a3c4e27ca`,
  vendor_boot
  `10063d103778eb260a4558dac952862988e6e5b6edc45f5502e17ffc40b6aeba`.
  Dos generaciones finales fueron idénticas y el hash del ZIP copiado a
  `/sdcard` coincide. El asistente no flasheó ninguna partición.
- Reto inmediato: flashear manualmente v0.13, probar táctil en LightDM y
  observar la enumeración USB. Si NCM/RNDIS aparece, conectar por SSH y
  verificar en vivo eventos Goodix, PTN3222/DWC3 y estado de red.

## 2026-07-19 — sesión 18: resultado físico inicial v0.13

- La usuaria flasheó v0.13. El sistema vuelve a alcanzar LightDM, pero el
  táctil continúa sin producir entrada utilizable.
- El host no detecta ADB, ACM ni una interfaz NCM/RNDIS. Siguen presentes dos
  dispositivos USB desconocidos con error de solicitud de descriptor y
  `172.16.42.1:22` no responde; por tanto todavía no existe SSH sobre USB.
- Se sondeó en paralelo el puerto 22 de `<LAN_SUBNET>`, excluyendo el propio
  host, `.138` y `.150`. La usuaria confirmó que `.138` es otro dispositivo
  pmOS y `.150` ya estaba identificado como otro equipo; no apareció ningún
  endpoint SSH nuevo atribuible a la tablet.
- No se introducen nuevas correcciones a ciegas. El próximo paso es volver a
  TWRP y extraer en sólo lectura el journal v0.13 para comprobar el layout
  Goodix registrado, checksum, EVDEV/libinput y la cadena PTN3222/DWC3.

## 2026-07-19 — sesión 19: journal v0.13 y bundle v0.14

- En TWRP se montó `/dev/block/mmcblk1p2` como `ro,norecovery`, se extrajeron
  ambos journals persistentes, Xorg, boot y LightDM a
  `work/v013-rootfs-logs-20260719/`, y se desmontó la raíz. El journal actual
  tiene SHA-256
  `e4d2d9a437b122c83360653cfe926e20c29c9e8f5e9e8d7eb9a3343d7bd2c51a`;
  la operación no escribió en la microSD.
- El boot v0.13 (`f9385ea3b0d042f09f326ed2761c12b8`) registra Goodix a
  1,623 s y muestra `Goodix Berlin 6936 ... event layout 8/8`. A continuación
  todos los eventos reales fallan checksum. Los dumps de un contacto tienen
  10 bytes y los de dos contactos 18 porque el parser toma los bytes 8–9 o
  16–17 como checksum, aunque son todavía datos del registro Samsung; esto
  explica exactamente por qué el parche dinámico v0.13 no se activó.
- El driver Samsung no usa el `point_struct_len` leído de IC_INFO para eventos:
  fija `BYTES_PER_POINT=16`, checksum sobre `event_num * 16 + 2` y el layout
  de coordenadas ya portado. Se corrigió la hipótesis anterior: este firmware
  6936 anuncia ocho de forma incorrecta. El parche r9 fuerza 16 únicamente
  cuando el PID es `6936`, conservando ocho para firmware upstream normal.
- EVDEV está built-in y `input0` se registra; no hay evidencia de que Xorg o
  libinput sean la barrera primaria mientras todos los IRQ se descarten antes
  de reportar eventos. Los avisos de systemd intentando cargar `uinput` y
  `uhid` como módulos son secundarios porque se compilaron built-in.
- Para USB, desapareció por completo el fallo de pinctrl y ya no hay deferred
  probe del PTN3222. DWC3 alcanza el sondeo a 2,098 s, pero su soft reset no
  termina y acaba en `-ETIMEDOUT/-110`. El arreglo de GPIO de v0.13 fue por
  tanto correcto pero insuficiente.
- La comparación del driver mainline `phy-nxp-ptn3222.c` con el FDT/log vivo
  Samsung encontró la diferencia restante: mainline sólo habilita rails y
  quita reset. Samsung espera unos 4 ms, lee la versión `0xa2` y escribe cuatro
  overrides: valor `20` en registro `06`, `21` en `07`, `63` en `08` y `01`
  en `0a`. El FDT los publica como
  `qcom,param-override-seq=<20 06 21 07 63 08 01 0a>`.
- Se añadió `configure-nxp-ptn3222-from-dt.patch`: crea regmap I2C, valida una
  secuencia par acotada, espera 4–5 ms tras reset, escribe pares valor/registro
  y revierte rails/reset si falla. El DTS r9 reproduce la secuencia stock. El
  validador exige tanto la cadena compilada como los ocho valores del DTB.
- Los dos parches aplicaron limpiamente sobre un worktree 7.2-rc3 nuevo. La
  primera invocación de build fue cortada por el límite del runner a 124 s sin
  error de compilación; la segunda reutilizó los objetos parciales y terminó
  el enlace limpio en 439 s. No se aceptaron outputs hasta que terminó.
- Build directa v0.14: `Image.gz` SHA-256
  `c02c47ffca3e4d6eb5d9f7cae2a1cb5f1c3994dc5dc25b2c0ec54908979b5952`;
  DTB `454a804c38c6a3e5ea0406419f65c0adcc1c8d477dea50fb2b79e51d1f430d07`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
  El Image contiene los mensajes de Goodix forzado y overrides PTN3222; el
  DTB devuelve exactamente `20 6 21 7 63 8 1 a` mediante `fdtget`.
- ZIP v0.14:
  `postmarketos-edge-xfce-mainline-v0.14-goodix-force-ptn-tune-sm-x910-twrp.zip`,
  22.014.000 bytes, SHA-256
  `23cb7f066c6fecbd50d995db315906f262545ac3024af3068b3a468f947a5cfe`.
  Hashes internos: boot
  `9499d1836e2b9c7665891b46d0c13c34eea8ff2e4f7d72e8bc4a64d294a4fc4b`,
  vendor_boot
  `19c1f767c6a924a9bee4cdb0c7f70d067950327b55269f202cbb7f2c5989d904`.
  Dos generaciones fueron idénticas, pasaron Android v4/LZ4/AVB y todas las
  aserciones de hardware. Se copió a `/sdcard` y el hash remoto coincide. El
  asistente no flasheó ninguna partición.
- Reto inmediato: prueba física v0.14. El journal esperado debe mostrar layout
  Goodix 8/16 sin checksum errors y cuatro overrides PTN antes de DWC3. Si USB
  enumera, conectar por SSH; si el táctil responde, validar orientación y
  escala en LightDM antes de avanzar a DRM nativo.

## 2026-07-19 — sesión 20: resultado físico inicial v0.14

- La usuaria flasheó v0.14 y el sistema alcanzó de nuevo LightDM. El táctil
  continúa sin producir entrada utilizable.
- Windows sigue sin ADB, ACM ni NCM/RNDIS y conserva los dos dispositivos USB
  desconocidos por error de descriptor. `172.16.42.1:22` no responde.
- Se sondeó en paralelo el puerto 22 de toda `<LAN_SUBNET>`, excluyendo el
  host y los equipos conocidos `.138`/`.150`; no apareció ningún SSH nuevo
  atribuible a la tablet.
- No se puede distinguir externamente si el override Goodix no se activó, si
  cambió el checksum esperado o si la escritura PTN3222 falló/progresó sin
  resolver DWC3. Próximo paso: volver a TWRP y extraer el journal v0.14 en sólo
  lectura antes de introducir otro cambio.

## 2026-07-19 — sesión 21: journal v0.14 y bundle v0.15

- Desde TWRP se montó `/dev/block/mmcblk1p2` como `ro,norecovery`, se
  extrajeron journals, Xorg, boot y LightDM a
  `work/v014-rootfs-logs-20260719/`, y se desmontó la microSD sin escribirla.
  El journal actual tiene SHA-256
  `19d2ec68fd8d2fa3bdf30232821ba654c473f9f1ed0a7e9ed5340f970fe56e4f`;
  boot ID `7d1c4dd8eee64b67b41c876851a25cd7`.
- Goodix registra a 1,628 s `forcing 16-byte Samsung events for firmware PID
  6936`, crea `input0` y anuncia `event layout 8/16`. Ya no aparece ningún
  `touch data checksum error`: el forzado por PID de v0.14 funciona.
- Al tocar, `a90000.i2c` agota el tiempo de la transferencia GPI inicial y el
  driver termina en `failed get event head data: -110`; después el canal DMA
  puede fallar también `CH STOP`. La diferencia con v0.13 es el tamaño:
  26 bytes completaban, mientras v0.14 preleía dos registros Samsung y pedía
  42. La corrección r10 prelee sólo un contacto (26 bytes en 8/16).
- El algoritmo multitáctil conserva los dos bytes posteriores al primer
  contacto: son checksum si `n=1` o el inicio de contacto 1 si `n>1`. En este
  último caso reanuda en `header + point_len + checksum_size`, escribe desde
  `data[point_len + checksum_size]` y lee `(n - 1) * point_len`, que completa
  los contactos restantes y el checksum final sin duplicar datos.
- USB registra `ptn3222 1-004f: applied 4 register overrides` a 1,748 s. DWC3
  todavía avisa `controller soft reset failed` y devuelve `-ETIMEDOUT`; queda
  demostrado que rails, reset y tuning del repetidor ya no son la barrera.
- La comparación con `dwc3-qcom.c` identificó la omisión exacta al limitar el
  puerto a HS: el DTS borraba la SSPHY/PIPE, pero no añadía
  `qcom,select-utmi-as-pipe-clk`. Esa propiedad hace que el glue programe
  `PIPE_UTMI_CLK_SEL` antes de `dwc3_core_probe()`. Se añadió al DTS y al
  validador, sin reintroducir todavía la PHY USB3.
- El parche Goodix modificado aplica limpiamente sobre Linux 7.2-rc3. Una
  primera build limpia fue terminada a 63 s por el límite del runner, no por
  un error; la continuación incremental terminó correctamente en 478 s.
- Build v0.15: `Image.gz` SHA-256
  `1a8320c6fa49f75cafd3ec3871ce012f59270a3b1d8ba665b2ac3a35b15cd8d2`;
  DTB `13c909ec802636d7be8a6318c52be0f0b53505f6f4224e457184869ed6376c25`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
  La imagen contiene el mensaje Goodix y el DTB compilado contiene la
  propiedad booleana UTMI-PIPE.
- ZIP v0.15:
  `postmarketos-edge-xfce-mainline-v0.15-goodix-usb-pipe-sm-x910-twrp.zip`,
  22.012.201 bytes, SHA-256
  `e4f7432ed114227d238d161514796b6cc997a74029abe7ce9b079ef4216ae013`.
  Hashes internos: boot
  `837709a9e49e8ee25414c77ac80b3da803c9620bec155cf61529f2c66ee95aa2`,
  vendor_boot
  `9886dd75d9990d1656a00888bcc9559e984441fb8038cb1b7099d3f8b0a79921`.
  Dos generaciones fueron idénticas, pasaron Android v4/LZ4/AVB y todas las
  aserciones. El ZIP se copió a `/sdcard` y su hash remoto coincide; el
  asistente no flasheó ninguna partición.
- Reto inmediato: flashear manualmente v0.15 y probar un toque en LightDM. Si
  Windows enumera NCM/RNDIS, conectar por SSH y validar ambos subsistemas en
  vivo. Si alguno falla, volver a TWRP y extraer el nuevo journal en sólo
  lectura antes del siguiente cambio.

## 2026-07-19 — sesión 22: resultado físico inicial v0.15

- La usuaria flasheó v0.15 y el sistema alcanzó LightDM. La lectura Goodix
  reducida de 42 a 26 bytes queda validada físicamente: el táctil produce
  entrada por primera vez.
- La orientación aún es incorrecta. Tocar la parte superior activa la parte
  inferior, por lo que el eje vertical expuesto está invertido. El siguiente
  DTS añadirá `touchscreen-inverted-y` además de `touchscreen-swapped-x-y`.
- El host no presenta NCM/RNDIS ni otro adaptador USB de red. Permanecen dos
  dispositivos desconocidos con error de solicitud de descriptor y
  `172.16.42.1:22`/`<LAN_HOST_C>:22` no responden.
- Se sondeó el puerto 22 de toda `<LAN_SUBNET>`. Sólo respondieron `.138` y
  `.150`, ambos equipos conocidos que la usuaria pidió excluir; no existe SSH
  atribuible a la tablet.
- El resultado externo no demuestra todavía si UTMI-PIPE permitió superar el
  soft reset y el fallo está ahora en el gadget, o si DWC3 sigue en timeout.
  Próximo paso: volver a TWRP, extraer el journal v0.15 en sólo lectura y usar
  esa evidencia para el siguiente cambio USB junto con la inversión de eje.

## 2026-07-19 — sesión 23: journal v0.15 y bundle v0.16

- En TWRP se montó `/dev/block/mmcblk1p2` como `ro,norecovery`, se extrajeron
  journal, Xorg, boot y LightDM a `work/v015-rootfs-logs-20260719/`, y se
  desmontó la microSD. El journal actual tiene SHA-256
  `ab71752f62067cea8bd92d87850f42c873c9aace2090a2e6aba50c1d001f5496`;
  boot ID `50f794db540749b2bde8ed6ef92011c8`.
- Goodix registra `event layout 8/16` y no aparecen checksum, GPI-I2C ni DMA
  timeouts. Esto concuerda con la entrada física estable observada en v0.15.
- UTMI-PIPE resolvió el soft reset DWC3: ya no existe `-ETIMEDOUT`. El kernel
  registra el controlador, configfs crea el gadget y `usb0`; initramfs asigna
  `172.16.42.1` e inicia DHCP. En userspace Avahi publica esa dirección y sshd
  escucha en `0.0.0.0:22` y `[::]:22`.
- Como Windows sigue mostrando errores de descriptor, el fallo restante queda
  después del core/gadget y antes de una enumeración física correcta. No se
  debe seguir modificando userspace de red para este síntoma.
- Se comparó el driver mainline `drivers/phy/phy-snps-eusb2.c` con el Samsung
  funcional `drivers/usb/phy/phy-msm-snps-eusb2.c`. Divisores PLL, VREF y los
  cinco parámetros TX coinciden. Las dos diferencias concretas son una espera
  de 10 µs tras afirmar `POR` y `PHY_CFG_PLL_CPBIAS_CNTRL=1`; mainline omite la
  espera y usa cero.
- Se añadió `match-samsung-sm8550-eusb2-phy-init.patch` para reproducir ambos
  detalles. El DTS añade además `touchscreen-inverted-y`. El paquete sube a
  r11, actualiza hashes y el validador exige inversión e intercambio de ejes.
- Build limpia v0.16: kernel
  `e1ece41124f5f365e5a123fd7ec67531682397bb5cf1d3c3df2a088b525624be`,
  DTB `ce4ce2e2d09b0835641e95f26971188fa5be479c0d65aa626eed4cade9f87093`,
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
  La compilación limpia terminó en 585 s y las comprobaciones inspeccionaron
  fuente y DTB efectivos.
- ZIP v0.16:
  `postmarketos-edge-xfce-mainline-v0.16-touch-usb-phy-sm-x910-twrp.zip`,
  22.016.593 bytes, SHA-256
  `c0d768a2eb179cab95bc2776840828e36c8a50a2df598f7bbb1df6835c457ef9`.
  Hashes internos: boot
  `09984ff41ef3f799378c91d9572618742cce7375dcf2e37074ee39d0705794d7`,
  vendor_boot
  `1a57a0a114c63a30fb1e6e00f9850dee09acdf10da9c5b15ebe243a6b35aa5ed`.
  Dos generaciones fueron idénticas; pasó Android v4/LZ4/AVB y el hash en
  `/sdcard` coincide. El asistente no flasheó particiones.
- Reto inmediato: flashear manualmente v0.16, validar orientación táctil y
  enumeración NCM/RNDIS. Si aparece la interfaz, conectar por SSH a
  `172.16.42.1`; si no, capturar el journal y añadir lecturas diagnósticas de
  los registros PHY/PTN3222 antes de otro cambio.

## 2026-07-19 — sesión 24: resultado físico v0.16 y eje correcto

- v0.16 alcanza de nuevo LightDM, pero el ajuste de PHY no cambia el resultado
  externo: Windows conserva dos errores de solicitud de descriptor, no aparece
  NCM/RNDIS y no responde SSH en `172.16.42.1`, `172.16.42.2`, `.151` ni en un
  host nuevo de la LAN. `.138` y `.150` se excluyen por indicación de la
  usuaria porque pertenecen a otros dispositivos.
- La espera de 10 µs tras POR y CPBIAS=1 quedan por tanto descartados como
  arreglo suficiente para la enumeración. Se conserva el parche porque iguala
  la secuencia Samsung, pero el siguiente journal debe guiar instrumentación
  de registros PHY/PTN3222.
- La prueba táctil v0.16 deja ambos ejes visibles invertidos. La causa exacta es
  el orden de `touchscreen_apply_prop_to_x_y()`: aplica `inverted-x`, después
  `inverted-y` y finalmente `swapped-x-y`. Como el intercambio ya era
  necesario, `inverted-y` actuó sobre el X visible y no corrigió el Y visible.
- La fuente r12 sustituye `touchscreen-inverted-y` por
  `touchscreen-inverted-x` y conserva `touchscreen-swapped-x-y`. El validador
  se actualiza para exigir la propiedad correcta.
- Por petición de la usuaria, el flujo normal de futuras builds queda reducido
  a un empaquetado y una única comparación SHA-256 después de copiar el ZIP a
  `/sdcard`. Las validaciones repetidas se reservan para cambios de formato o
  boot chain que realmente eleven el riesgo.
- Reto inmediato: volver a TWRP, extraer el journal v0.16 en sólo lectura,
  integrar instrumentación USB y compilar un único siguiente bundle que pruebe
  tanto la orientación corregida como el siguiente paso de eUSB2.

## 2026-07-19 — sesión 25: referencia eUSB2 Samsung y bundle v0.17

- En TWRP se montó `/dev/block/mmcblk1p2` como ext4 `ro,norecovery`, se
  extrajeron journal, Xorg y LightDM a `work/v016-rootfs-logs-20260719/` y se
  desmontó la tarjeta. El `system.journal` actual tiene SHA-256
  `6dd5ee4399bbae29e56b10dbedc9d6178f7a7decca51728ec7c97c1215376f53`;
  boot ID `225ccfc4e1ac473f9c413502d1bbe026`.
- v0.16 confirma `event layout 8/16`, sin checksum/GPI/DMA; PTN3222 aplica los
  cuatro overrides, DWC3 arranca y configfs crea gadget/`usb0`/DHCP. No aparece
  un error interno nuevo que explique el fallo de descriptor del host.
- Se usó el kernel Samsung 5.15 de TWRP como referencia funcional y se montó
  debugfs temporalmente. El regmap PTN3222 `43-004f` contiene revisión `A2`,
  `06=20`, `07=21`, `08=63`, `0a=01`, `DEVICE_STATUS(0f)=09` y
  `LINK_STATUS(10)=05` mientras ADB enumera correctamente.
- La hoja de datos oficial NXP confirma que `0x0f` y `0x10` son los dos
  registros de estado. Esto permite una comparación directa y evita seguir
  cambiando tuning sin saber en qué lado del repetidor se rompe el enlace.
- Se añadió `diagnose-sm8550-eusb2-link.patch`: imprime la frecuencia de
  referencia y los controles MMIO efectivos de la PHY, y lee `00..16` del
  PTN3222 ocho segundos después de iniciar. Es diagnóstico de sólo lectura.
- El DTS r12 conserva `touchscreen-swapped-x-y` y sustituye la inversión
  errónea por `touchscreen-inverted-x`. El script de build aplica también el
  nuevo parche y el APKBUILD incluye fuente y checksum reproducibles.
- Build limpia v0.17 terminada en 541 s: kernel
  `48e91dfb2f42a665599d204a63e8633a8606011dc9dc4f18a4c1791975d12aa1`,
  DTB `8d600347ad1a826e0c0ef33fbf0fb68125d18d5a64939307ac4b93599c12bddf`,
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
- Se empaquetó una sola vez, siguiendo el flujo acordado. ZIP:
  `postmarketos-edge-xfce-mainline-v0.17-touch-usb-diagnostics-sm-x910-twrp.zip`,
  22.016.542 bytes, SHA-256
  `d86e978618bf00d182f705aa4b0704111b42b8f2f8dd8547e40255f205e30439`.
  Se copió a `/sdcard` y el único hash posterior coincide. El asistente no
  flasheó particiones.
- Reto inmediato: flash manual v0.17, validar ambos ejes táctiles y observar
  USB/SSH. Si no enumera, volver a TWRP y comparar `0f/10` mainline con la
  referencia Samsung `09/05` antes de aplicar el siguiente arreglo.

## 2026-07-19 — sesión 26: resultado físico inicial v0.17

- v0.17 arranca hasta LightDM y la usuaria confirma que el táctil funciona y
  queda correctamente orientado. Se valida físicamente la combinación
  `touchscreen-inverted-x` + `touchscreen-swapped-x-y`; el bring-up táctil se
  considera resuelto.
- Windows no enumera NCM/RNDIS y mantiene dispositivos USB con error de
  solicitud de descriptor. No responden `172.16.42.1:22`, `172.16.42.2:22` ni
  `<LAN_HOST_C>:22`.
- El barrido TCP/22 de `<LAN_SUBNET>` sólo encuentra `.138` y `.150`, ambos
  equipos conocidos que deben excluirse. No existe SSH atribuible a la tablet.
- Reto inmediato: volver a TWRP, extraer el journal v0.17 en sólo lectura y
  comparar los registros diferidos PTN3222 `DEVICE_STATUS(0f)` y
  `LINK_STATUS(10)` con la referencia Samsung funcional `09/05`.

## 2026-07-19 — sesión 27: PTN3222 descartado y bundle DWC3 v0.18

- En TWRP se montó `mmcblk1p2` como `ro,norecovery`, se extrajeron journal,
  Xorg y LightDM a `work/v017-rootfs-logs-20260719/` y se desmontó la tarjeta.
  Boot ID `66eb6939ed4649e197dcd6be06c0cd46`; SHA-256 de `system.journal`
  `201b71a79f2344904f9153b13e8826b32bd59a9a710d625a5ae868aa6193c13b`.
- La PHY mainline registra referencia de 38,4 MHz y los valores efectivos de
  sus controles. El PTN3222 queda fuera de reset (`logical=0`, `raw=1`) y sus
  registros `00..16` coinciden con TWRP byte a byte: revisión `A2`, overrides
  `06=20`, `07=21`, `08=63`, `0a=01`, estado `0f=09` y enlace `10=05`.
- Como el repetidor funcional y mainline presentan el mismo enlace, se
  descartan nuevos cambios de tuning/PHY. El host alcanza el enlace físico,
  pero Windows no obtiene VID/PID; el ámbito pasa a DWC3/UDC/EP0.
- La configuración de initramfs es la ruta estándar postmarketOS configfs:
  crea `ncm.usb0`, configura VID `18d1`/PID `d001`, enlaza `c.1` y escribe el
  primer UDC disponible. El journal no contiene errores de esos pasos.
- Se añadió `diagnose-dwc3-ep0-enumeration.patch`, que registra solicitud y
  resultado del pull-up, DCTL/DSTS/DEVTEN/event count, cada evento DWC3, estado
  EP0 y paquetes SETUP. No cambia lógica del controlador. APKBUILD r13 y script
  de build lo reproducen.
- Recompilación incremental v0.18 terminada en 58 s: kernel
  `6d1feaff85d4d50131a2fdb114f28ac6be410420d0226c22c09edf8465b4ffef`,
  DTB `8d600347ad1a826e0c0ef33fbf0fb68125d18d5a64939307ac4b93599c12bddf`,
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
- ZIP único v0.18:
  `postmarketos-edge-xfce-mainline-v0.18-dwc3-ep0-diagnostics-sm-x910-twrp.zip`,
  22.017.000 bytes, SHA-256
  `6706f3778c2df2b1384e1b225cf3c5af315ca0986056599dfb3fc4c42f8542e0`.
  Se copió a `/sdcard` y el único hash posterior coincide; no se flasheó.
- Reto inmediato: flash manual v0.18, esperar 15 s y probar USB/SSH. Si falla,
  volver a TWRP y clasificar el primer punto ausente entre pull-up, RUN/STOP,
  IRQ reset/connect, SETUP y respuesta EP0.

## 2026-07-19 — sesión 28: resultado físico inicial v0.18

- v0.18 arranca hasta LightDM y conserva el táctil funcional, pero USB no
  enumera. Windows muestra dos dispositivos `VID_0000&PID_0002` con error de
  solicitud de descriptor; no aparece adaptador NCM/RNDIS.
- No responden `172.16.42.1:22`, `172.16.42.2:22` ni `.151`. El barrido completo
  de `<LAN_SUBNET>` sólo encuentra SSH en `.138` y `.150`, ambos excluidos por
  pertenecer a otros dispositivos.
- Reto inmediato: volver a TWRP, extraer el journal v0.18 en sólo lectura y
  determinar con las trazas nuevas el primer punto ausente entre pull-up,
  RUN/STOP, IRQ reset/connect, paquete SETUP y respuesta EP0.

## 2026-07-19 — sesión 29: EP0 validado y bundle RNDIS/WCN7850 v0.19

- Se extrajo y leyó el journal v0.18 desde la microSD. Boot ID
  `47ee7c89dc374bd1baf30310b98cbef7`; SHA-256 de `system.journal`
  `ffcbcd4ebce12d857a91094c9712d442422001ab7533178a03db64c69d614edc`.
- Las trazas pasivas muestran pull-up/RUN efectivo, IRQ y una conversación
  EP0 completa: el host solicita descriptores device/config/string, asigna
  dirección, pide estado, ejecuta `SET_CONFIGURATION(1)` y
  `SET_INTERFACE(0)`. PTN3222, PHY, DWC3 y la entrega de descriptores quedan
  descartados como barrera. Windows no crea el adaptador CDC-NCM pese a haber
  configurado la función; se seleccionó `rndis.usb0` como siguiente prueba
  mínima de compatibilidad.
- El FDT vivo/stock Kiwi v2 contiene IDs 1103 y 1107; el perfil de esta placa
  es WCN7850 PCIe `17cb:1107` en PCIe0. Se confirmaron contra downstream
  WLAN_EN GPIO80, BT_EN GPIO81, PCIe PERST GPIO94 y wake GPIO96.
- El DTS r14 añade `vph_pwr`, `wcn7850-pmu`, sus diez LDO, rails PM8550VS,
  sleep clock PMK8550, pinctrl y `pcieport0/wifi@0`. El fragmento activa
  PCIe Qualcomm, `POWER_SEQUENCING_QCOM_WCN=m` y `ATH12K=m`; conserva todos
  los fixes anteriores de arranque, pantalla y táctil.
- Se extrajo `vendor.img` stock EROFS y se creó el paquete propietario
  `firmware-samsung-gts9uwifi` r1. Blobs finales y SHA-256: `amss.bin`
  `4529e42c...`, `m3.bin` `67396ffa...`, `board.bin` `9cade90a...` y
  `regdb.bin` `75cc1075...`. El script de staging exige los hashes completos y
  los binarios quedan ignorados por git.
- La primera construcción rootfs falló correctamente porque cuatro checksums
  del APKBUILD de kernel no seguían el orden posicional de `source=`. Se
  reordenaron antes de reconstruir. Firmware r1 elimina además la advertencia
  de instalar directamente en `/lib` y usa `/usr/lib` en el sistema usr-merge.
- Verificación del rootfs final: device r4, kernel `7.2_rc3-r14`, firmware r1;
  módulos `ath12k`, `ath12k_wifi7` y `pwrseq-qcom-wcn`; cuatro blobs exactos;
  RNDIS presente en deviceinfo e initramfs; DTB con PMU/GPIO/rails y
  `pci17cb,1107`.
- Imágenes Android v4 v0.19: boot
  `6d7493ffbf2f8373c86ec5936ba333601d998c0ba8ee7d78410cc40619972ab5`,
  init_boot
  `ba29d262447268a298ed192b340515417307fb5bb482bd3f2105d874dc1b59d5`,
  vendor_boot
  `392b8a3b27874405494d6b06da778a14ddf04bff04c9c6bc427e41141fa1f7c3`,
  dtbo `9f2dc02eb28fd5ffaa90745a57c4f176aa708e8a0fc67635acd4e52a7fed9e65`
  y vbmeta
  `b95e5ef931fbe588f8574c06331db56ae906b1ac91ed73204704b35cb220b3d4`.
- El empaquetador y el instalador TWRP admiten ahora un overlay opcional del
  rootfs pmOS. Antes de escribir, valida `mmcblk1p2`, ext4 y `ID=postmarketos`;
  después instala y verifica por archivo módulos, firmware y deviceinfo, sin
  tocar userdata interna, super, recovery, bootloader ni firmware Samsung.
- ZIP v0.19: 80.821.386 bytes, SHA-256
  `3ca3e44fb2a8e26bec76515381d40f565ecc6b5215b52d8b855f7513297a686e`.
  Se copió a `/sdcard` en TWRP y el único hash posterior coincide. El asistente
  no flasheó ninguna partición.
- Se comprimió también la imagen GPT limpia de 4.643.094.528 bytes como
  `postmarketos-edge-xfce-mainline-v0.19-rndis-wifi-pcie-sm-x910-sd.img.zst`:
  513.383.398 bytes, SHA-256
  `ed7a92c2645eb3ea2118a77be28afba16fee7a30bbbfb4b614026df492fd6f10`.
  Contiene los mismos paquetes r4/r14/r1 y sirve para la prueba desde cero.
- Próximo paso: flash manual v0.19. Probar RNDIS/SSH en `172.16.42.1`; en
  paralelo observar si PCIe0 enumera 17cb:1107 y si NetworkManager obtiene una
  interfaz Wi-Fi. Si no hay red, volver a TWRP para extraer el journal v0.19.

## 2026-07-19 — sesión 30: corrección del validador TWRP v0.19.1

- El intento manual de instalar v0.19 abortó con `microSD rootfs is not
  postmarketOS`. La comprobación sucede antes de los `dd`, por lo que no se
  escribió ninguna partición de arranque ni archivo del rootfs.
- Diagnóstico directo por ADB/TWRP: `/dev/block/mmcblk1p2` existe, monta como
  ext4 y `/etc/os-release` es un enlace válido a `../usr/lib/os-release`. La
  identidad real es `ID="postmarketos"`; el instalador sólo aceptaba la forma
  legal alternativa sin comillas `ID=postmarketos`.
- El validador acepta ahora exactamente cualquiera de esas dos formas. No se
  modifica ninguna imagen, módulo, blob ni contenido del overlay v0.19.
- Se reempaquetó como
  `postmarketos-edge-xfce-mainline-v0.19.1-rndis-wifi-pcie-sm-x910-twrp.zip`:
  80.821.400 bytes, SHA-256
  `3a3431c1ea994536feadc6eb18712b1de38664babadb6b45e40da467dd66f89f`.
  Copiado a `/sdcard`; el único hash posterior coincide. El asistente no lo
  flasheó.

## 2026-07-19 — sesión 31: fallo ABL v0.19.1 y restauración del appended-DTB

- Tras instalar v0.19.1, el reboot mostró la pantalla Odin/Download y no llegó
  a Linux. La usuaria volvió manualmente a TWRP; no hubo brick.
- `/proc/last_kmsg` contiene el boot fallido restaurado por `sec_log_buf`. ABL
  descomprime el kernel, pero registra `ApplyOverlay: ufdt apply overlay
  failed`, `Root Node is not found at BoardDtb`, `Invalid device tree header`
  y `Launching odin -927639495`. No existe panic ni journal nuevo porque Linux
  nunca recibió el control.
- La comparación de `BUILD-METADATA.txt` fija la regresión: v0.18 arrancable
  tenía `append_dtb_to_kernel=1` y `disable_runtime_dtbo=1`; v0.19 se generó
  accidentalmente con `0/0` al llamar al script sin las variables que antes
  aportaba el flujo de build. Esto reactivó exactamente la ruta ufdt descartada
  en v0.2/v0.3.
- El script device-specific usa ahora por defecto `1/1`. v0.19.2 reutiliza el
  mismo kernel r14, DTB WCN7850, initramfs, rootfs y overlay; sólo corrige el
  empaquetado Android para recuperar el fallback appended-DTB validado desde
  v0.4.
- Imágenes v0.19.2: boot appended-DTB
  `082a3bcb51c4b53a52b98c1d226621d57f6ce2ab6e88874e6ddc0fcd597e7e8c`;
  dtbo fallback
  `c17418be08365c03a5ce3a220af734b14ec2e6b03c0cbc1ed9721be6f21d3ef3`.
  `init_boot`, `vendor_boot` y `vbmeta` conservan respectivamente
  `ba29d262...`, `392b8a3b...` y `b95e5ef9...`. La metadata confirma ambos
  flags en uno y los primeros ocho bytes del DTBO fallback son cero.
- ZIP v0.19.2:
  `postmarketos-edge-xfce-mainline-v0.19.2-appended-dtb-rndis-wifi-sm-x910-twrp.zip`,
  80.852.094 bytes, SHA-256
  `a8a6f28ab58c594478dda11a738ba0deb90c09d2865824b2aff845c655c0b8a6`.
  Copiado a `/sdcard`; el único hash posterior coincide. El asistente no lo
  flasheó.

## 2026-07-19 — sesión 32: userspace v0.19.2, diagnóstico WCN y bundle v0.20

- v0.19.2 abandona la regresión Odin y arranca mainline desde la microSD. Las
  tres fotos corresponden a boots de systemd, no a kernel panic. Se extrajeron
  en sólo lectura los journals con IDs `214544eee54741ab86c8d276cdcefe87`,
  `e159c2334b9f4a87afb08ee8bf67301e` y
  `8773907e091e43f2b60962f4560177e1`.
- Dos boots completos superan 51 segundos. systemd alcanza graphical target;
  RNDIS crea `usb0=172.16.42.1`, NetworkManager ve carrier y OpenSSH escucha
  en todas las direcciones. Xorg abre simpledrm a 2960x1848, LightDM activa
  VT7 y slick-greeter entra en su bucle principal. No hay panic ni fallo fatal
  de X, por lo que la pantalla de consola persistente es un problema de
  presentación/VT, no de arranque.
- v0.20 retira `console=tty0` del cmdline Android y del paquete device. Se
  mantienen `ttyMSM0`, earlycon, journal persistente, `sec_log_buf` y
  `/proc/last_kmsg`, de modo que fbcon deja de competir con X sin perder la
  capacidad de diagnóstico desde TWRP o por red.
- PCIe0 v0.19.2 inicializa el controlador y enumera su root port
  `17cb:0113`, pero tras aproximadamente un segundo termina `Device not
  found`; no existe endpoint ni interfaz ath12k. `pwrseq-qcom_wcn` informa
  además que falta `vddio1p2`.
- El driver Linux 7.2-rc3 de WCN7850 pide siete rails, incluido `vddio1p2`.
  El DTS antiguo de SM8550 QRD usado como base declara sólo seis, mientras DTs
  WCN7850 posteriores conectan ese rail a un LDO de 1,2 V. El perfil stock X910
  mapea explícitamente `l3g` a RF y su pinctrl activa WLAN_EN GPIO80 como
  salida alta, pull-up y 16 mA; la versión v0.19 lo dejaba en pull-down.
- r15 añade PM8550VS-G LDO3, su alimentación desde S4G y
  `vddio1p2-supply`; GPIO80 reproduce el estado activo stock. El DTB empaquetado
  fue decompilado y confirma esas propiedades. Paquetes finales: device r5,
  kernel `7.2_rc3-r15`, firmware r1.
- Artefacto TWRP:
  `postmarketos-edge-xfce-mainline-v0.20-wcn-power-rndis-no-fbcon-sm-x910-twrp.zip`,
  80.853.798 bytes, SHA-256
  `9a73808d30e6aa9b317a7550a36a5c6a271245d8fcdff17808ecba5e17f76998`.
  Copiado a `/sdcard`; el único hash posterior coincide. No se flasheó.
- Imagen SD limpia del mismo rootfs:
  `postmarketos-edge-xfce-mainline-v0.20-wcn-power-rndis-no-fbcon-sm-x910-sd.img.zst`,
  478.250.065 bytes.
- Próxima prueba: flash manual del ZIP, esperar al menos 45 segundos y probar
  primero SSH en `172.16.42.1`; después comprobar login visible, `lspci -nn`,
  `ip link`, `nmcli` y `dmesg` de `qcom-pcie`/`ath12k`. `.138` y `.150` siguen
  excluidos por ser otros dispositivos.

## 2026-07-19 — sesión 33: bloqueo v0.20 y diagnóstico WCN v0.21

- La prueba física v0.20 queda visualmente en los pingüinos porque retiró
  `console=tty0`, pero no se detiene allí. Desde TWRP se extrajeron en sólo
  lectura `/proc/last_kmsg`, journals y logs X/LightDM a
  `work/v020-rootfs-logs-20260719/`.
- El boot v0.20 `56c2f5b944d14e2e8bc81741e54c8ef1` confirma kernel
  `#16-samsung-gts9uwifi-mainline`/paquete r15, montaje de ambas particiones,
  systemd, gadget RNDIS y socket OpenSSH. El journal se corta exactamente a
  18,987144 s tras imprimir los rangos del host `qcom-pcie 1c00000.pcie`; no
  existe panic ni oops y fue necesario un reinicio manual.
- El DT v0.20 añade además el aviso temprano `Fixed dependency cycle(s)` entre
  `/soc@0/rsc@17a00000/regulators-5` y `smps4`. Es una regresión respecto a
  v0.19.2 y coincide con el nuevo PM8550VS-G LDO3 alimentado por S4G. Se
  descarta repetir esa asignación sin antes demostrar la topología correcta.
- v0.21 revierte LDO3, `vdd-l3-supply` y `vddio1p2-supply`; el driver vuelve a
  su dummy rail conocido. GPIO80 conserva `drive-strength = <16>` y
  `bias-pull-up`, pero ya no tiene `output-high`: el secuenciador debe elevarlo
  en el orden previsto. Se restaura `console=tty0` para recuperar el verbose.
- `diagnose-wcn7850-power-sequence.patch` registra valor inicial, resultado de
  dirección y transición de WLAN_EN, además del registro del secuenciador. Se
  integra tanto en el APKBUILD como en la build directa. El módulo final fue
  inspeccionado y contiene las cadenas `SM-X910 WCN diag`.
- Build limpia verificada: device r6, kernel `7.2_rc3-r16`, firmware r1. El
  DTB decompilado no contiene el rail experimental y sí contiene GPIO80
  pull-up/16 mA y `wlan-enable-gpios`.
- ZIP TWRP generado una vez:
  `postmarketos-edge-xfce-mainline-v0.21-wcn-diagnostics-verbose-sm-x910-twrp.zip`,
  80.851.485 bytes, SHA-256
  `c46b30538b486ee1b93c938464c8f339d93b3127450d3a34f39c4861bc3f9032`.
  Usa appended-DTB, DTBO runtime deshabilitado y overlay completo. Se copió a
  `/sdcard`; el único hash posterior coincide. El asistente no flasheó.
- Próxima prueba: flash manual v0.21, dejarla al menos 45 segundos y observar
  el verbose. Si no aparece RNDIS/SSH, volver a TWRP para extraer el journal y
  localizar la última traza `SM-X910 WCN diag`; no hace falta vídeo mientras
  la persistencia de la microSD continúe funcionando.

## 2026-07-19 — sesión 34: v0.21 sí arranca y bundle visual/SSH v0.22

- La foto v0.21 parecía quedar detenida tras `SM-X910 WCN diag: power
  sequencer registered`. Se volvió manualmente a TWRP y se extrajeron en sólo
  lectura 19 journals, `last_kmsg` y logs de X/LightDM a
  `work/v021-rootfs-logs-20260719/`.
- El boot completo `f1d854a068194803b30089cb0d6554a3` usa kernel r16. El
  secuenciador adquiere los siete rails, `regulator_bulk_enable()` retorna 0 y
  WLAN_EN permanece en 1 antes/después de la transición. PCIe termina de forma
  normal un segundo después con `Device not found`; el WCN7850 aún no enumera,
  pero no existe deadlock, panic ni oops.
- Userspace continúa: RNDIS obtiene carrier, `usb0` conserva `172.16.42.1`,
  NetworkManager arranca a 21,315 s, OpenSSH a 21,318 s, LightDM a 21,555 s y
  `graphical.target` a 21,604 s. El journal sigue activo al menos hasta 51 s.
- La causa de la pantalla estática es conocida y aislada: `console=tty0`
  mantiene fbcon mostrando el último printk mientras X/greeter corre en VT7.
  Esa consola se restauró deliberadamente en v0.21 para obtener las trazas.
- v0.22 no recompila ni cambia kernel/DTB: conserva r16 y firmware r1, sube el
  device a r7 y retira `console=tty0` tanto del cmdline Android como del
  `kernel-cmdline.conf` reproducible. Se generó un rootfs limpio y se verificó
  device r7/kernel r16/firmware r1.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.22-rndis-ssh-greeter-sm-x910-twrp.zip`,
  80.851.469 bytes, SHA-256
  `85c70c79f1b0e0bb3c7facd47ac7b817807dd6159a15a4dd8d6f42f5e204f9c6`.
  Usa appended-DTB, DTBO runtime deshabilitado y overlay completo. Se copió a
  `/sdcard` y el único hash posterior coincide; el asistente no flasheó.
- Próxima prueba: flash manual v0.22, esperar 45 s, dejar el sistema vivo y
  conectado por USB. Debe aparecer el greeter; se probará inmediatamente SSH
  en `172.16.42.1` para continuar la enumeración WCN desde el sistema vivo.

## 2026-07-19 — sesión 35: carrera PCIe/WCN v0.22 y aislamiento v0.23

- La prueba v0.22 permaneció físicamente en los pingüinos pese a no contener
  `console=tty0`. Se volvió manualmente a TWRP y se extrajeron en sólo lectura
  journals, `last_kmsg` y logs gráficos a
  `work/v022-rootfs-logs-20260719/`.
- Los boots `d34857ab68a9422a9dda48d6b2467373` y
  `cbab67c1ce7241e18c49ca1523ca0d7e` usan kernel r16. Ambos montan rootfs,
  activan el gadget USB y llegan a los probes PCIe/WCN, pero el journal deja
  de progresar respectivamente a 21,727 y 19,040 s, antes de NetworkManager,
  OpenSSH y LightDM. Los cuatro ficheros X/LightDM están vacíos.
- No hay panic ni oops. El boot v0.21 `f1d854...` había completado exactamente
  la activación de siete rails, WLAN_EN, PCIe y userspace; otros boots r16 se
  detienen antes o durante esa ruta. La evidencia apunta a una carrera
  intermitente de probe/deferred-probe entre PCIe0, pci-pwrctrl y el proveedor
  WCN, no a un fallo determinista de X ni a `console=tty0`.
- El endpoint Wi-Fi sigue sin enumerar incluso en el boot completo, así que no
  aporta ninguna función al primer hito. v0.23 lo aísla como bloque: añade una
  etiqueta al `wcn7850-pmu` y marca `disabled` ese PMU, `pcie0` y `pcie0_phy`.
  Pantalla/simpledrm, Goodix, SDHC2, DWC3, RNDIS y OpenSSH no cambian.
- Build limpia verificada: device r7, kernel `7.2_rc3-r17`, firmware r1. La
  consulta directa del DTB instalado devuelve `status=disabled` para
  `/wcn7850-pmu`, `/soc@0/pcie@1c00000` y `/soc@0/phy@1c06000`; el cmdline no
  contiene `console=tty0`.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.23-stable-rndis-no-wcn-sm-x910-twrp.zip`,
  80.851.833 bytes, SHA-256
  `a050c7d88ec223619c231f102593c5ae03d0b81dccaadda6256abd2d30b43fcd`.
  Usa appended-DTB, DTBO runtime deshabilitado y overlay completo. Se copió a
  `/sdcard`; el único hash posterior coincide. El asistente no flasheó.
- Próxima prueba: flash manual v0.23 y mantenerla viva/conectada al menos 45 s.
  Validar greeter y SSH RNDIS en `172.16.42.1`; sólo entonces reintroducir
  PCIe/WCN con acceso remoto y trazas más finas.

## 2026-07-19 — sesión 36: v0.23 estable y handoff VT de v0.24

- La prueba física v0.23 volvió a parecer detenida en los pingüinos. La usuaria
  regresó manualmente a TWRP y los logs se extrajeron en sólo lectura a
  `work/v023-rootfs-logs-20260719/`; no fue necesario un vídeo del verbose.
- El boot `563abe3add6e4cd893b4ceeaceb88eea` usa kernel
  `#18-samsung-gts9uwifi-mainline`/paquete r17 y demuestra que el aislamiento
  WCN funciona: no aparecen probes WCN/PCIe0, panic, oops ni interrupción del
  journal. RNDIS crea `usb0=172.16.42.1` con carrier; NetworkManager arranca a
  21,021 s, OpenSSH a 21,024 s, LightDM a 21,316 s y los targets multi-user y
  gráfico se alcanzan a 21,373 s.
- `Xorg.0.log` tiene 11.076 bytes y no contiene fallo fatal. Xorg abre
  `/dev/dri/card0` mediante modesetting/simpledrm, selecciona 2960x1848 y usa
  VT7. `lightdm.log` tiene 3.654 bytes, lanza `slick-greeter` y lo deja en
  autenticación de `phablet`.
- La discrepancia queda aislada al scanout: LightDM registra que Plymouth sigue
  en VT1, inicia X con `vt7 -novtswitch` y luego dice `Activating VT 7`, pero la
  pantalla física conserva el framebuffer de VT1. Los logs X/LightDM de v0.11,
  que sí mostró el login, son esencialmente iguales; no hay evidencia para
  cambiar kernel, simpledrm, resolución ni greeter en esta iteración.
- v0.24 mantiene sin cambios kernel r17, DTB y aislamiento WCN. El paquete
  device sube a r8, depende explícitamente de `kbd` y añade una unidad oneshot
  posterior a LightDM. El script espera hasta 15 s el socket X0, registra la VT
  antes/después y fuerza `chvt 1`, pausa y `chvt 7` para provocar
  `LeaveVT`/`EnterVT` y un redraw de simpledrm.
- La build limpia contiene device r8, kernel `7.2_rc3-r17`, firmware r1 y
  `kbd-2.8.0-r0`. Se verificaron script ejecutable/sintácticamente válido,
  unidad habilitada, `chvt`/`fgconsole`, cmdline sin `console=tty0` y
  `status=disabled` en PMU WCN, PCIe0 y su PHY.
- Durante el empaquetado se detectó que el overlay incremental anterior sólo
  incluía módulos, firmware y deviceinfo: el paquete r8 nuevo no habría
  actualizado por sí mismo la microSD ya instalada. v0.24 transporta además el
  script, la unidad y su activación. `make-twrp-zip.py` preserva ahora los modos
  POSIX del overlay; se comprobó que el script queda `0755` dentro del ZIP.
- ZIP TWRP final:
  `postmarketos-edge-xfce-mainline-v0.24-vt-handoff-rndis-sm-x910-twrp.zip`,
  80.853.551 bytes, SHA-256
  `b7c1a8bc2e3cc6bb0b68c89a5eea8882d85ef664291e80e54e275cfa8ef37b6e`.
  Se copió a `/sdcard` y la única comparación local/remota coincide. El
  asistente no flasheó ninguna partición.
- Próxima prueba: flash manual v0.24, dejar la tablet arrancada incluso si aún
  muestra pingüinos y mantener USB conectado. Probar SSH inmediatamente en
  `172.16.42.1` y leer el journal de
  `gts9uwifi-display-handoff.service`; si el rebote automático no repinta, se
  podrá repetir en vivo y observar DRM/VT sin otro ciclo ciego.

## 2026-07-20 — sesión 37: no-op del overlay v0.24 y fallback fbdev v0.25

- La prueba física v0.24 siguió mostrando únicamente los ocho pingüinos y el
  cursor. La usuaria volvió manualmente a TWRP. Se montó `mmcblk1p2` como
  ext4 `ro,noload` y se extrajeron journals y logs gráficos a
  `work/v024-rootfs-logs-20260720/`.
- El boot nuevo `96a5a5ecfc28401a8010ad616a9a5afc` no está colgado. RNDIS
  obtiene carrier y `usb0=172.16.42.1`; NetworkManager arranca a 21,400 s,
  OpenSSH a 21,403 s y escucha desde 21,493 s, LightDM arranca a 21,791 s,
  `graphical.target` se alcanza a 21,797 s y slick-greeter continúa activo. El
  journal llega al menos a 51,296 s sin panic, oops ni stall.
- El servicio v0.24 nunca se ejecutó. A 10,892 s systemd registra literalmente
  que `graphical.target.wants/gts9uwifi-display-handoff.service` no es un
  symlink y lo ignora. La inspección del rootfs confirma que tanto la unidad
  wants como el script son ficheros regulares `0644`.
- La causa está en el instalador incremental: `make-twrp-zip.py` sí guardaba el
  script como `0755`, pero `mainline-update-binary` extraía cada miembro con
  `unzip -p` y aplicaba `chmod 0644` incondicional. La activación se había
  empaquetado como copia regular porque el overlay no preservaba symlinks. El
  rebote VT propuesto en v0.24, por tanto, no llegó a someterse a prueba.
- v0.25 amplía `ROOTFS-OVERLAY-SHA256SUMS` a `hash modo ruta`. El instalador
  acepta únicamente `0644`/`0755`, aplica el modo por miembro y, cuando existe
  la unidad de handoff, elimina la entrada anterior y crea el enlace real
  `graphical.target.wants/... -> ../gts9uwifi-display-handoff.service`.
- La comparación completa de Xorg/LightDM v0.11 frente a v0.24 no muestra una
  diferencia funcional aparte del kernel/cmdline/táctil: ambas usan Xorg
  1.21.1.23, VT7, 2960x1848, modesetting sobre simpledrm, glamor rechazado por
  llvmpipe, `ShadowFB` deshabilitado y el mismo `-novtswitch`. Sin embargo sólo
  v0.11 repintó físicamente el panel.
- Para no depender otra vez exclusivamente de ese page-flip, device r9 añade
  temporalmente `20-gts9uwifi-fbdev.conf`: fuerza el DDX fbdev y `ShadowFB`
  sobre `/dev/fb0`, que el kernel registra como `simpledrmdrmfb` y cuyo
  contenido de consola ya es visible. El handoff VT corregido se conserva como
  segunda vía de repintado.
- La build limpia v0.25 conserva kernel `7.2_rc3-r17`, firmware r1 y el
  aislamiento PMU WCN/PCIe0/PHY. Se verificaron device r9, `fbdev_drv.so`, la
  configuración X, script ejecutable, unidad/enlace, kbd y cmdline sin
  `console=tty0`.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.25-fbdev-vt-rndis-sm-x910-twrp.zip`,
  80.853.846 bytes, SHA-256
  `8834678cceb50b7fc6d85b35daabcad8c57ff8ac0c34af3e8c7eaebcee74f054`.
  El manifiesto dentro del ZIP marca el script `0755`, el instalador incluido
  contiene la creación del symlink y la configuración fbdev está presente.
  Se copió a `/sdcard` y la única comparación local/remota coincide; el
  asistente no flasheó ninguna partición.
- Próxima prueba: flash manual v0.25 y dejar el sistema vivo/conectado por USB
  aunque la imagen no cambie. Probar SSH en `172.16.42.1` antes de volver a
  TWRP; si aún falla la presentación, el journal distinguirá de forma directa
  carga del DDX fbdev, resultado del handoff y estado de `/dev/fb0`.

## 2026-07-20 — sesión 38: VT7 validada, fbdev con sombra y captura v0.26

- Tras v0.25 la imagen física siguió en los pingüinos. Windows mantuvo el USB
  como `USB descriptor failure (Code 43)` incluso después de desconectar y
  reconectar físicamente, por lo que no se creó una interfaz RNDIS accesible y
  no fue posible usar SSH. La usuaria volvió manualmente a TWRP.
- La inspección offline confirma que el instalador v0.25 sí corrigió el fallo
  anterior: `20-gts9uwifi-fbdev.conf` está presente, el script es `0755` y
  `graphical.target.wants/gts9uwifi-display-handoff.service` es un enlace real
  hacia la unidad. Los hashes coinciden con el artefacto.
- El journal nuevo se extrajo a `work/v025-rootfs-logs-20260720/`. El boot
  `4803b789a4b545ff97b0829a4bac2062` monta el rootfs, crea RNDIS internamente,
  inicia NetworkManager/OpenSSH/LightDM y llega a `graphical.target` a
  23,453 s. Continúa registrando hasta al menos 905 s; no hay cuelgue, panic,
  oops ni stall.
- La unidad de handoff se ejecuta esta vez: X0 está listo, `fgconsole` devuelve
  1 antes del rebote y 7 después. El servicio termina correctamente a
  23,447 s. Por tanto la imagen estática no se debe ya a una activación rota ni
  a que la VT lógica permanezca en la consola.
- `Xorg.0.log` confirma el DDX solicitado: `fbdev_drv.so` usa `/dev/fb0`, ve
  hardware `simpledrmdrmfb`, 21.367 KiB, 2960x1848, pitch 2960 y 32 bpp. La
  opción `ShadowFB=true` está activa y carga `libshadow.so`. Los mensajes
  `FBIOPUTCMAP: Invalid argument` se repiten al programar la paleta, pero son
  no fatales: DPMS, extensiones, Goodix, sesión LightDM y slick-greeter siguen
  inicializando.
- Las dos rutas probadas quedan separadas: modesetting/simpledrm sin sombra
  (v0.23/v0.24) y fbdev con sombra (v0.25) mantienen el scanout físico. v0.26
  cubre el cuadrante restante cambiando sólo a `ShadowFB=false`, para que X
  renderice directamente sobre el mmap de `/dev/fb0`.
- El handoff v0.26 espera cinco segundos adicionales y lee exactamente
  21.880.320 bytes (`2960*1848*4`) desde `/dev/fb0` a
  `/var/log/gts9uwifi-fb0-after-x.raw`, sincroniza el archivo y registra su
  SHA-256. Si el panel no cambia, esa captura permitirá convertir y comparar
  el contenido real de X con los pingüinos sin depender de USB ni vídeo.
- Build limpia verificada: device r10, kernel `7.2_rc3-r17`, firmware r1 y
  kbd; configuración fbdev directa, captura, script ejecutable, enlace systemd
  y aislamiento WCN/PCIe0 presentes.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.26-direct-fbdev-capture-sm-x910-twrp.zip`,
  80.854.080 bytes, SHA-256
  `e2713a80edebd9897ccbdf7a4143d83d055579fb896056b15156357816c9b876`.
  Se copió a `/sdcard` y la única comparación local/remota coincide. El
  asistente no flasheó ninguna partición.
- Próxima prueba: flash manual v0.26 y dejarla arrancada al menos 45 s. Si el
  panel sigue en los pingüinos y SSH no enumera, volver a TWRP sin necesidad de
  vídeo; extraer y convertir `gts9uwifi-fb0-after-x.raw` antes de cualquier
  cambio adicional.

## 2026-07-20 — sesión 39: framebuffer correcto y refresco KMS v0.27

- Tras v0.26 el panel siguió mostrando los pingüinos y Windows mantuvo el USB
  con Code 43, por lo que la usuaria regresó manualmente a TWRP. El asistente
  no escribió ninguna partición.
- Desde `mmcblk1p2` se recuperó
  `/var/log/gts9uwifi-fb0-after-x.raw`: mide exactamente 21.880.320 bytes
  (`2960*1848*4`) y su SHA-256 es
  `a987f44c03315694b0716b929f6d9c7bb2aeee0a3c412dd4871bc357689d6aed`.
- La conversión XRGB8888 little-endian se conserva en
  `work/v026-rootfs-logs-20260720/gts9uwifi-fb0-after-x.png`. La inspección
  visual muestra el greeter completo de LightDM, fondo XFCE, reloj, entrada de
  contraseña y teclado en pantalla. X dibuja correctamente; el panel físico
  continúa leyendo el buffer de la consola.
- La captura descarta de forma concluyente nuevos cambios ciegos en boot,
  systemd, LightDM, greeter, selección de VT o contenido de `/dev/fb0`. El
  defecto actual está entre el daño del buffer y el scanout físico de
  simpledrm.
- v0.27 cambia el DDX a `modesetting`, fija `AccelMethod=none` y
  `ShadowFB=true`. Después del handoff VT1→VT7 ejecuta con la autoridad de
  LightDM `xrandr --output None-1 --off`, espera un segundo y reactiva
  `None-1 --mode 2960x1848`, intentando forzar una copia de daño y actualización
  completa del plano KMS.
- Build limpia verificada: device r11, kernel `7.2_rc3-r17`, firmware r1 y
  kbd; configuración X, `xrandr`, script ejecutable, unidad/enlace systemd y
  nodos WCN/PCIe0/PHY deshabilitados presentes.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.27-kms-shadow-refresh-sm-x910-twrp.zip`,
  80.854.291 bytes, SHA-256
  `e665a73e8efa51198f87a3fba2dc5bed8a8839406af00a05309d04b47bd58bc8`.
  Se copió a `/sdcard` y la única comparación local/remota coincide. Pendiente
  flash manual y validación física; el asistente no flasheó la tablet.

## 2026-07-20 — sesión 40: resultado físico v0.27

- La usuaria flasheó manualmente v0.27 y dejó la tablet arrancada y conectada.
  El panel continúa mostrando únicamente los ocho pingüinos del framebuffer de
  arranque; el refresco solicitado no produjo un cambio visible.
- El host no detecta ADB. Windows vuelve a enumerar el enlace como dispositivo
  USB desconocido con error de solicitud de descriptor (Code 43), y
  `172.16.42.1:22` no responde. Por tanto no es posible consultar en vivo el
  journal ni el resultado de `xrandr`.
- Próximo paso: regresar manualmente a TWRP y extraer en sólo lectura el journal
  de v0.27. Si el servicio confirma que `xrandr` desactivó/reactivó `None-1`,
  se abandona la capa X para este defecto y se instrumenta/corrige la ruta de
  actualización dirty/scanout de simpledrm en el kernel.

## 2026-07-20 — sesión 41: causa raíz encontrada (rpmhpd sync_state) y v0.28

- Desde TWRP se montó `mmcblk1p2` como `ro,noload` y se extrajo el journal
  completo de v0.27 (boot `2cbe9bc2f5fd4beda28cceaaeb934e9b`, reconstruido a
  partir de `system.journal` más los rotados) a
  `work/v027-rootfs-logs-20260720/`, junto con `Xorg.0.log`, ambos logs de
  LightDM y la nueva captura `gts9uwifi-fb0-after-x.raw`.
- El servicio de handoff v0.27 se ejecutó íntegro: `active-before=1`,
  `active-after=7`, ambos `xrandr` sin error y captura a los 32,69 s.
  `Xorg.0.log` registra el ciclo completo: `xrandr --off` reduce la pantalla a
  320x200 y produce ~100 `failed to add fb -22` (simpledrm limita
  min/max_width al modo firmware, EINVAL esperado), y `--mode 2960x1848`
  reasigna un framebuffer nativo nuevo sin error. Aun así el panel siguió en
  los pingüinos: la capa X queda definitivamente descartada.
- La captura fb0 de v0.27 (SHA-256 `dc6c3e70...`) es negra: con el DDX
  modesetting X dibuja en su dumb buffer, no en la emulación fbdev. Es
  coherente y no aporta contradicción.
- Comparando el dmesg de v0.18 (greeter visible) con v0.27 apareció la
  regresión estructural: los kernels de v0.4–v0.18 eran builds directas con
  release `7.2.0-rc3-dirty`, de modo que `/lib/modules/7.2.0-rc3` del rootfs
  nunca casaba y ningún módulo llegó a cargar (el journal v0.18 registra
  `modprobe: FATAL: Module ext4 not found in directory
  /lib/modules/7.2.0-rc3-dirty`). Desde v0.19 el boot usa el payload APK con
  release `7.2.0-rc3` y udev coldplug carga por fin el árbol de módulos.
- La cadena causal exacta del panel congelado: `sm8550.dtsi` deja `dispcc`,
  `videocc` y `camcc` habilitados (mdss está `disabled`, `msm.ko` no carga);
  el rootfs contiene `dispcc-sm8550.ko`, `videocc-sm8550.ko`,
  `camcc-sm8550.ko` y sus alias casan con los nodos DT. `qcom-rpmhpd`
  mantiene cada dominio en su corner de arranque hasta `sync_state()`, que
  dispara cuando TODOS sus consumidores DT han sondeado; el journal muestra
  `qcom-rpmhpd ... sync_state() pending due to ade0000/aaf0000
  .clock-controller` justo antes del coldplug. Al cargar esos módulos
  (~17–20 s), rpmhpd ejecuta sync_state, suelta el voto de arranque de MMCX y
  el MDSS/DSI se apaga; el panel AMOLED en command-mode retiene el último
  frame de su GRAM: los ocho pingüinos.
- La evidencia temporal encaja al milisegundo: la foto v0.21 quedó congelada
  tras `SM-X910 WCN diag: power sequencer registered` (20,208 s), y su
  journal sitúa la carga de qcomtee/rtc/clock-controllers justo en esa
  ventana; en v0.27 esos módulos cargan entre 17 y 20,3 s, antes de que X
  arranque a los 21,6 s. En v0.11–v0.18 el mismo sync_state quedaba pendiente
  para siempre y por eso el greeter sí se veía.
- v0.28 aplica la corrección mínima reproducible: device r12 instala
  `/usr/lib/modprobe.d/gts9uwifi-display-hold.conf` con `blacklist` de
  `dispcc_sm8550`, `videocc_sm8550`, `camcc_sm8550` y `gpucc_sm8550`. Sólo
  bloquea el autoload por modalias; los módulos siguen empaquetados y el
  fichero debe eliminarse cuando exista el stack DRM/DSI real. No cambia
  kernel, DTB, cmdline, X ni el aislamiento WCN/PCIe0.
- Build limpia verificada: device r12, kernel `7.2_rc3-r17`, firmware r1 y
  kbd; blacklist con los cuatro módulos, los `.ko` conservados en el árbol,
  configuración X modesetting/sombra intacta, script/unidad/enlace de handoff
  presentes, cmdline sin `console=tty0` y los tres nodos WCN/PCIe0
  deshabilitados.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.28-hold-boot-display-sm-x910-twrp.zip`,
  80.855.122 bytes, SHA-256
  `a9b169d40400cfa0bea239138194ce36dd428a9e492a52e6e60c590ec5ddfedc`.
  El manifiesto del overlay transporta
  `usr/lib/modprobe.d/gts9uwifi-display-hold.conf` con modo `0644`. Se copió a
  `/sdcard` y la única comparación local/remota coincide; el asistente no
  flasheó ninguna partición.
- Próxima prueba: flash manual v0.28 y dejar la tablet arrancada al menos
  60 s. Si el diagnóstico es correcto, rpmhpd nunca ejecutará sync_state, el
  scanout del bootloader seguirá vivo y el greeter de LightDM debe sustituir
  físicamente a los pingüinos (con el parpadeo del rebote VT y del ciclo
  xrandr por el camino). Si sigue congelado, la siguiente iteración añadirá
  `console=tty0` para fechar el instante exacto de la congelación con el
  último printk visible y continuar el bisect de módulos (qcomtee, qcom_ice,
  icc_bwmon, icc_osm_l3).

## 2026-07-20 — sesión 42: v0.28 refuta MMCX, red USB viva y v0.29 (TZ/SCM)

- La usuaria flasheó v0.28; el panel siguió en los pingüinos. Con la tablet aún
  en pmOS se recuperó por primera vez el enlace de red USB: forzando el driver
  compuesto USB en Windows (devcon + re-scan), el gadget enumeró como
  `UsbNcm Host Device` con `172.16.42.2` en el host y `ping 172.16.42.1`
  respondiendo (1 ms, TTL 64). El sshd respondía, pero el `172.16.42.1` de esa
  prueba resultó ser OTRO dispositivo de la LAN, no la tablet; la usuaria
  confirmó que la contraseña de `phablet` es `<DEV_PASSWORD>` y movió la tablet a TWRP.
- Desde TWRP (`mmcblk1p2` `ro,noload`) se extrajo el journal de v0.28 a
  `work/v028-rootfs-logs-20260720/`. Confirmado: el fichero
  `/usr/lib/modprobe.d/gts9uwifi-display-hold.conf` está presente con su
  contenido (el `V:1-r3` del apk db es esperado: el overlay copia ficheros pero
  no reescribe la base apk).
- El blacklist FUNCIONÓ pero la hipótesis era incompleta: en el boot
  `fb59080f343b4d3bafdb6aaaa446e1b4` no aparece ningún `dispcc/videocc/camcc`
  y `qcom-rpmhpd ... sync_state() pending due to ade0000/aaf0000` sigue
  pendiente igual que en v0.11–v0.18. Aun así, pingüinos. Por tanto el voto
  MMCX/sync_state NO es el diferenciador.
- Nueva lectura decisiva: el scanout muere ~18–20 s, mucho antes de X (en v0.21
  con `console=tty0` el panel se congeló a 20,2 s). En esa ventana v0.28
  ejecuta dos drivers nuevos desde v0.19 que hacen llamadas SCM a TrustZone:
  `qcom-ice 1d88000.crypto` (18,59 s) y `qcomtee QTEE 5.2.0` (18,62 s). En este
  XBL Samsung la TZ suele ser dueña del splash; una llamada SCM puede desmontar
  el pipeline de display del bootloader. Ninguno cargaba en las builds `-dirty`
  de v0.11–v0.18 que sí mostraban el greeter. No hay ningún mensaje de display
  en el kernel tras `simpledrm fb0` (1,14 s), coherente con un teardown externo
  (TZ), no de un driver Linux.
- v0.29 (device r13) añade al blacklist `qcomtee` y `qcom_ice`. Seguro para el
  arranque: la raíz es la microSD (`sdhc_2`, `8804000.mmc`); el ICE `1d88000`
  pertenece a la UFS interna que no tocamos, y nada del bring-up usa qcomtee.
  Mantiene el blacklist de los mm clock controllers (inofensivo) y no cambia
  kernel, DTB, cmdline ni el aislamiento WCN/PCIe0.
- Build limpia verificada: device r13, kernel `7.2_rc3-r17`, firmware r1 y kbd;
  los seis módulos en el blacklist y sus `.ko` conservados. ZIP:
  `postmarketos-edge-xfce-mainline-v0.29-hold-tz-display-sm-x910-twrp.zip`,
  80.855.449 bytes, SHA-256
  `3d9ecfcc78699d7dfa47baf6ea9175b3068d8ea7c973324ab4d7641e73ecb460`,
  copiado a `/sdcard` con la única comparación local/remota coincidente. El
  asistente no flasheó ninguna partición.
- Durante esta sesión se resolvió además el acceso USB: forzar el driver
  compuesto USB de Windows (`devcon update usb.inf`) tras un re-scan hace que el
  gadget RNDIS/NCM enumere como `UsbNcm Host Device` y `172.16.42.x` quede
  enrutable. Es la primera vez que el enlace USB de pmOS es utilizable desde
  Windows (antes siempre Code 43).
- Próxima prueba: flash manual v0.29, dejar ≥60 s. Si el panel muestra el
  greeter, `qcomtee`/`qcom_ice` (SCM→TZ) eran quienes desmontaban el splash y
  el hito de escritorio queda alcanzado. Si sigue en pingüinos, la teoría TZ se
  descarta y la siguiente build restaura `console=tty0` para fechar visualmente
  el instante exacto de la congelación (técnica ya validada en v0.21).

## 2026-07-20 — sesión 43: auditoría v0.19 y baseline recuperable v0.30

- Se revisaron los cambios y la documentación dejados por el agente anterior.
  v0.27 descarta correctamente X/LightDM/VT; v0.28 bloqueó los clock
  controllers multimedia, el journal confirmó que el blacklist funcionaba y
  la prueba física refutó que MMCX/rpmhpd fuese por sí solo la causa.
- v0.29 añade `qcomtee` y `qcom_ice` por correlación temporal con 18,59–18,62 s,
  pero no se considera aún una solución demostrada. La transición v0.19 no
  activó sólo esos dos módulos: cambió del kernel directo
  `7.2.0-rc3-dirty`, sin directorio de módulos coincidente, al kernel APK
  `7.2.0-rc3` con coldplug completo, además de añadir WCN/RNDIS y modificar el
  DT. Hace falta un control total antes del bisect.
- El Xorg log físicamente funcional de v0.18 usa modesetting simpledrm por
  defecto, rechaza glamor/llvmpipe, deja `ShadowFB` deshabilitado y activa
  2960x1848 en VT7. Las configuraciones forzadas y el servicio de rebote
  VT/xrandr son posteriores y se neutralizan para el control.
- v0.30 reutiliza byte por byte las cinco imágenes de boot del ZIP v0.18:
  `boot.img=f5307277...`, `init_boot.img=bedcad22...`,
  `vendor_boot.img=a5ce2203...`, `dtbo.img=c17418be...` y
  `vbmeta.img=b95e5ef9...`. Esa combinación ya mostró físicamente LightDM y
  conserva el táctil corregido.
- El ZIP se regenera con el instalador TWRP actual para aceptar
  `ID="postmarketos"`, validar el overlay y manejar vbmeta read-only. El
  overlay deja `20-gts9uwifi-fbdev.conf` sin secciones Xorg y reemplaza el
  script de handoff por un no-op, reproduciendo el comportamiento gráfico
  anterior a v0.19 sobre el rootfs actual.
- Se añadieron `scripts/package-v018-display-baseline.sh` y
  `configs/display-baseline/` para que la build de recuperación sea
  reproducible y no un parche manual de la instalación.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.30-known-good-v018-display-sm-x910-twrp.zip`,
  22.018.867 bytes, SHA-256
  `4f4797b29559496aa678f70e2f2a51bbb510b58258a49d62f4b3355b6735c83b`.
  Se copió a `/sdcard` y la comparación local/remota coincide; el asistente no
  flasheó ninguna partición.
- Próxima prueba: flash manual v0.30 y esperar al menos 60 s. Si vuelve el
  greeter, conservar la tablet sobre esta base usable y hacer un bisect por
  grupos de los módulos que empezaron a cargar en v0.19, trasladando al kernel
  r17 únicamente la exclusión causal mínima.

## 2026-07-20 — sesión 44: v0.30 visible y aislamiento sin módulos v0.31

- La usuaria flasheó manualmente v0.30. El control funcionó: la tablet arranca,
  el táctil responde y se puede iniciar sesión hasta llegar al escritorio.
  Esto confirma que el rootfs actual no es la causa y recupera una base
  físicamente usable anterior a la regresión v0.19.
- Windows enumera además `UsbNcm Host Device #7`; el host usa
  `172.16.42.2/24` y `172.16.42.1:22` responde con OpenSSH 10.3. El usuario
  configurado sigue siendo `phablet`, pero la autenticación automatizada con
  la contraseña documentada `<DEV_PASSWORD>` fue rechazada; no se alteró el sistema vivo.
- Para separar los dos cambios simultáneos de v0.19 se construyó v0.31 con el
  kernel y DTB actuales mediante `scripts/build-mainline-kernel.sh`, pero sin
  módulos. El release embebido es `7.2.0-rc3-dirty` y el rootfs no contiene un
  directorio coincidente, reproduciendo el aislamiento de módulos de v0.18 sin
  revertir los arreglos actuales del kernel/DTS.
- El DTB v0.31 confirma `status=disabled` para WCN PMU, PCIe0 y PCIe0 PHY. El
  overlay conserva Xorg modesetting por defecto y el handoff no-op validado en
  v0.30. Se añadió `scripts/build-current-no-modules-control.sh` para hacer la
  prueba reproducible.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.31-current-kernel-no-modules-sm-x910-twrp.zip`,
  22.008.887 bytes, SHA-256
  `be37c78307d00dc065ed368ec4e35ecac434d7a11beead7b010e924ae1406d0e`.
  Se copió a `/sdcard` desde TWRP y la única comparación local/remota coincide.
  v0.30 permanece en la tarjeta como rollback visible; el asistente no flasheó
  ninguna partición.
- Interpretación prevista: si v0.31 muestra el escritorio, el culpable es uno
  de los módulos que empezaron a cargar en v0.19; si muestra pingüinos, debe
  bisectarse kernel/DTS/initramfs entre v0.18 y la base actual.

## 2026-07-20 — sesión 45: v0.31 a LightDM, Goodix completo y v0.32

- La prueba física v0.31 confirma que los ocho pingüinos son sólo el contenido
  inicial: tras unos segundos el panel cambia y aparece LightDM. El kernel y
  DTB actuales, el initramfs y el userspace quedan validados para display al
  conservar el release `7.2.0-rc3-dirty` sin módulos coincidentes. La regresión
  permanente de v0.19–v0.29 está causada exclusivamente por uno de los módulos
  que entonces empezaron a autocargarse.
- El táctil no respondió en v0.31. NCM enumeró y el puerto SSH respondió en
  `172.16.42.1`, pero la autenticación `phablet`/`<DEV_PASSWORD>` fue rechazada de nuevo,
  por lo que la usuaria regresó manualmente a TWRP.
- Se montó `mmcblk1p2` desde TWRP con `ro,noload` y se extrajeron journals,
  dmesg y logs X/LightDM a `work/v031-rootfs-logs-20260720/`. El boot relevante
  es `b3a671533e71486d949090199774a7dc`: LightDM arranca a 19,369 s y el no-op
  termina a 19,657 s. Goodix está registrado y recibe actividad, pero todos los
  paquetes se descartan como `touch data checksum error`.
- La comparación del kernel v0.18 con v0.31 localizó la diferencia. v0.18
  contiene el mensaje `forcing 16-byte Samsung events for firmware PID 6936`
  y la prelectura de un solo contacto; v0.31 no contenía el mensaje. El
  worktree directo conservaba un parche Samsung parcial y la guarda del script
  sólo buscaba `GOODIX_BERLIN_SAMSUNG_EVENT_ID_MASK`, por lo que saltaba
  incorrectamente el parche completo.
- Se añadió
  `upgrade-partial-goodix-samsung-events.patch` y se endureció
  `scripts/build-mainline-kernel.sh`: ahora exige el mensaje final exacto. Si
  detecta un estado parcial, añade `GOODIX_BERLIN_PRE_READ_TOUCHES=1`, fuerza
  16 bytes para PID 6936 y lee inicialmente un único contacto (26 bytes); si
  no encuentra ningún soporte Samsung, aplica el parche completo existente.
- El kernel v0.32 recompilado contiene el mensaje PID 6936, release
  `7.2.0-rc3-dirty` y la fuente compilada confirma la prelectura de un contacto.
  Mantiene el DT actual con WCN PMU, PCIe0 y PHY deshabilitados y sigue sin
  directorio de módulos coincidente, para cambiar una sola variable respecto a
  v0.31.
- ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.32-current-kernel-goodix-no-modules-sm-x910-twrp.zip`,
  22.007.128 bytes, SHA-256
  `c4509790f42bb6cff93e73ca0a7bdd2609d6c2b1f19eb6a6526bac263d5a67b9`.
  Se copió a `/sdcard` y la única comparación local/remota coincide. v0.30
  permanece como rollback; el asistente no flasheó ninguna partición.
- Próxima prueba: flash manual v0.32. El resultado esperado es el mismo
  handoff a LightDM de v0.31 con el táctil funcional. Si se confirma, se usará
  esta base para un bisect acumulativo de los módulos y conservar USB SSH antes
  de retomar WCN7850.

## 2026-07-20 — sesión 46: v0.32 validada y acceso SSH por clave en v0.33

- La usuaria flasheó manualmente v0.32. Arranca hasta LightDM y confirma que el
  táctil funciona sin problema. Quedan validados juntos el kernel/DTS actuales,
  display, Goodix con eventos Samsung de 16 bytes y la prelectura de un solo
  contacto. La base sin módulos es físicamente usable.
- Windows enumera `UsbNcm Host Device #7` a 426 Mbps. El host usa
  `172.16.42.2/24`, dos pings a `172.16.42.1` responden en 1 ms sin pérdidas y
  el puerto 22 acepta conexiones. El transporte USB y OpenSSH funcionan.
- La autenticación `phablet`/`<DEV_PASSWORD>` vuelve a ser rechazada. La inspección de la
  rootfs de build demuestra que el usuario tiene `/bin/ash`, ese shell es
  válido, la cuenta no está bloqueada y su hash SHA-512 sí corresponde a
  `<DEV_PASSWORD>`; sshd carga PAM. La discrepancia queda en el estado persistente de la
  rootfs física, no en la receta actual.
- Se generó una clave Ed25519 exclusiva de desarrollo. La privada queda fuera
  del repositorio en `/root/.ssh/gts9u_pmos`; sólo la pública se integra en el
  overlay. `90-gts9uwifi-development-key.conf` habilita pubkey y busca primero
  `/etc/ssh/authorized_keys/%u`, ruta root-owned compatible con el instalador
  TWRP sin depender del propietario de `/home/phablet`.
- `scripts/build-current-goodix-ssh-control.sh` reproduce v0.33. Kernel, DTB y
  las cinco imágenes Android tienen exactamente los mismos hashes que v0.32;
  sólo cambian los dos ficheros SSH del overlay. ZIP preparado:
  `postmarketos-edge-xfce-mainline-v0.33-goodix-ssh-no-modules-sm-x910-twrp.zip`,
  22.007.913 bytes, SHA-256 previo a copia
  `cc06f194a62653f731c4ef4238fed4ee047e2fbc2e173244a1f132c3eee6db71`.
- Próximo paso: volver manualmente a TWRP, copiar v0.33, comparar una sola vez
  el SHA local/remoto y flashear. Tras validar SSH por clave se hará el bisect
  de módulos responsable de apagar el scanout conservado.
- La usuaria dejó la tablet en TWRP y v0.33 se copió a `/sdcard`. La única
  comparación local/remota coincide en
  `cc06f194a62653f731c4ef4238fed4ee047e2fbc2e173244a1f132c3eee6db71`;
  queda pendiente únicamente el flash manual y el arranque.

## 2026-07-20 — sesión 47: v0.33 rechaza la clave y hardening v0.34

- La usuaria flasheó v0.33 y arrancó de nuevo la base funcional. NCM conserva
  `172.16.42.2/24` en el host, dos pings a `172.16.42.1` responden en 1 ms y el
  puerto 22 está abierto.
- El cliente ofrece la clave Ed25519 esperada, fingerprint
  `SHA256:EsZ6dkUkxnvcfUDER6tbuQOKEZ4KRc9RjfYBFnrWQ94`, pero OpenSSH 10.3 la
  rechaza y vuelve a `publickey,password,keyboard-interactive`. El ZIP sí
  contiene tanto la clave como el drop-in con bytes LF correctos.
- El instalador imponía modo a cada fichero, pero no a los directorios creados
  por `mkdir -p`. La ruta nueva `/etc/ssh/authorized_keys` podía heredar el
  `umask` permisivo de TWRP; `StrictModes` rechaza entonces la ruta completa
  aunque el fichero final sea `0644`. Es la diferencia material frente a los
  overlays anteriores, que escribían en directorios ya existentes.
- El instalador se endurece de forma general: tras crear el directorio padre
  de cada entrada aplica `chmod 0755` antes de extraerla. v0.34 mueve además la
  clave a `/etc/ssh/gts9uwifi_authorized_keys`, directamente bajo el directorio
  preexistente, y usa `00-gts9uwifi-development-key.conf` para que la primera
  definición de `AuthorizedKeysFile` gane incluso aunque el drop-in `90-*` de
  v0.33 permanezca en la microSD.
- v0.34 conserva byte por byte kernel, DTB, `boot`, `init_boot`, `vendor_boot`,
  `dtbo` y `vbmeta` de v0.32/v0.33. ZIP preparado:
  `postmarketos-edge-xfce-mainline-v0.34-goodix-ssh-flat-key-no-modules-sm-x910-twrp.zip`,
  22.007.934 bytes, SHA-256 previo a copia
  `aa92d42f62f5922a0a9713f9eccd8d15e3740942fcb27f170d19f661f8f49fa6`.
- Próximo paso: regresar a TWRP, copiar/verificar v0.34 y flashearla. Si la
  clave siguiera rechazada, extraer desde TWRP los ficheros instalados, sus
  modos/propietarios y el journal SSH antes de otra hipótesis.
- La usuaria regresó a TWRP. v0.34 se copió a `/sdcard` y la única comparación
  local/remota coincide en
  `aa92d42f62f5922a0a9713f9eccd8d15e3740942fcb27f170d19f661f8f49fa6`.
  Queda pendiente el flash manual y el arranque; el asistente no escribió
  ninguna partición.

## 2026-07-20 — sesión 48: v0.34 refuta el directorio SSH como causa única

- La usuaria flasheó manualmente v0.34 y arrancó el sistema. NCM sigue
  funcionando: el host conserva `172.16.42.2/24`, dos pings a
  `172.16.42.1` responden en 1 ms y el puerto 22 está abierto.
- El cliente ofrece la clave Ed25519 correcta en modo no interactivo, pero
  OpenSSH vuelve a responder `Permission denied
  (publickey,password,keyboard-interactive)`. Por tanto mover la clave a un
  fichero plano, ordenar el drop-in como `00-*` y fijar los padres a `0755` no
  resuelve la autenticación.
- La hipótesis de `StrictModes` sobre el directorio creado por TWRP queda
  refutada como explicación suficiente. El hardening general del instalador
  sigue siendo correcto, pero no se hará otra build basada sólo en inferencia.
- Próximo paso: regresar a TWRP y montar `mmcblk1p2` en `ro,noload`. Extraer la
  clave/configuración instaladas, `stat` de toda la ruta, passwd/shadow,
  configuración efectiva de sshd, logs del último boot y propietarios/modos
  del home. Sólo esa evidencia decidirá el siguiente arreglo.

## 2026-07-20 — sesión 49: auditoría SSH física y aislamiento de PAM v0.35

- Desde TWRP se montó `mmcblk1p2` con `ro,noload` y se extrajo una auditoría a
  `work/v034-auth-audit-20260720-2/`, incluidos los journals persistentes. La
  partición se desmontó antes de continuar.
- La instalación física es correcta: el drop-in `00-*`, la clave plana y el
  drop-in heredado `90-*` existen. `/etc/ssh` y `sshd_config.d` son
  `root:root 0755`; el drop-in nuevo y la clave plana son `root:root 0644`.
  Sólo la carpeta antigua v0.33 conserva `0777`, pero ya no aparece en la ruta
  efectiva de v0.34.
- La clave instalada tiene exactamente fingerprint
  `SHA256:EsZ6dkUkxnvcfUDER6tbuQOKEZ4KRc9RjfYBFnrWQ94`. `phablet` es UID/GID
  10000, home owned por UID 10000, shell `/bin/ash` válido, cuenta desbloqueada
  y el hash físico confirma la contraseña `<DEV_PASSWORD>`.
- Se ejecutó el binario ARM64 correcto `/usr/sbin/sshd.pam -T` dentro de la
  rootfs desde TWRP con `/dev` y `/proc` enlazados temporalmente. Su
  configuración efectiva usa la clave plana, pubkey, `StrictModes yes`, PAM,
  contraseña y keyboard-interactive. La precedencia `00-*` funciona.
- Los journals sólo registran el listener al nivel INFO; los hijos de
  autenticación no dejaron el motivo del rechazo. Un sshd temporal `-ddd` en
  el recovery se expuso mediante `adb forward tcp:2222`, pero su hijo preauth
  cerró la conexión justo después de instalar seccomp, antes de KEX. Es una
  incompatibilidad entre el userspace pmOS y el kernel TWRP, no evidencia sobre
  el fallo del boot mainline. El proceso, forward y todos los mounts se
  retiraron.
- Como clave y contraseña fallan pese a credenciales/configuración correctas,
  v0.35 aísla la fase PAM común. El drop-in fija `UsePAM no`, deshabilita los
  métodos interactivos, exige `AuthenticationMethods publickey` y eleva el log
  a `DEBUG3`, manteniendo `StrictModes yes` y la clave root-owned.
- Kernel, DTB, `boot`, `init_boot`, `vendor_boot`, `dtbo` y `vbmeta` son byte a
  byte los de v0.32. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.35-goodix-ssh-no-pam-no-modules-sm-x910-twrp.zip`,
  22.007.992 bytes, SHA-256
  `7a1de9353d6614130f545f9cdb337818ec24746c00ecdad29ef15a39894ef537`.
  Se copió a `/sdcard` y la única comparación local/remota coincide; el
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.35, arrancar y probar la clave. Si se acepta,
  PAM era la barrera y se podrá depurar en vivo; si se rechaza, extraer el
  journal DEBUG3 sin otra build intermedia.

## 2026-07-20 — sesión 50: el NCM accesible era otro pmOS, no la X910

- La usuaria flasheó v0.35 y arrancó. El host volvió a mostrar un NCM en
  `172.16.42.2/24` y un servidor en `172.16.42.1:22`; la clave fue rechazada y
  el servidor seguía ofreciendo métodos interactivos, contradictorio con la
  configuración v0.35.
- La contradicción se resolvió comparando identidades criptográficas. La host
  key Ed25519 extraída de la microSD X910 es
  `SHA256:1N9kAKdfusq7wxZmypG2PsCpqwhhDu5An+HC3SJAu0E`. El endpoint vivo
  presenta `SHA256:jPYjoVxDTlJ6jh50x+qfOlpHkFLqcEVMhJScmQgLuoM`, banner
  OpenSSH 10.3 y Windows lo resuelve como `daisy.local`. La rootfs X910 usa
  OpenSSH 10.4. No son el mismo sistema.
- Windows enumera simultáneamente dos USB: `UsbNcm Host Device #7`, parent
  `USB\\VID_18D1&PID_D001\\postmarketOS`, está funcional y pertenece al otro
  pmOS; otro dispositivo en un puerto/hub distinto figura como
  `USB\\VID_0000&PID_0002...` con error de solicitud de descriptor. Este
  último es compatible con el fallo físico externo ya observado en la X910.
- Por tanto las pruebas de contraseña/clave sobre `172.16.42.1` de
  v0.30–v0.35 no prueban nada sobre la autenticación de la tablet. Se conservan
  como válidas la prueba visual/táctil y la evidencia offline: los journals de
  la X910 demuestran que internamente configfs, `usb0`, DHCP y sshd arrancan.
- v0.35 ya está flasheada, pero su acceso key-only todavía no se ha probado
  contra la X910 real. Próximo paso: desconectar o aislar el USB del otro pmOS,
  reconectar físicamente la tablet y comprobar enumeración/host key. Si la
  X910 sigue como Code 43, retomar el defecto de descriptor desde la cadena
  DWC3/EP0 ya instrumentada, sin mezclarlo con autenticación.
- Se intentó reiniciar sólo `USB\\VID_0000&PID_0002...` y solicitar un scan
  PnP sin tocar el NCM ajeno. Ambas operaciones devolvieron `Acceso denegado`
  por falta de elevación; Windows no cambió ningún dispositivo. La siguiente
  acción es física: desconectar el otro pmOS USB si está conectado y reinsertar
  el cable de la X910 manteniendo v0.35 arrancada.
- Tras hacerlo, `UsbNcm Host Device #7`, la interfaz `172.16.42.2/24` y toda la
  ruta `172.16.42.0/24` desaparecieron. Sólo permanece el dispositivo
  desconocido `VID_0000:PID_0002` con Code 43, confirmando que el NCM era del
  otro equipo y el error de descriptor corresponde a la X910.
- La propiedad PnP sitúa la tablet detrás de
  `USB\\VID_05E3&PID_0608...`, `Port_#0004.Hub_#0003`. Antes de cambiar kernel,
  PHY o gadget se probará un puerto USB directo del PC y, si es posible, otro
  cable, manteniendo el sistema arrancado.

## 2026-07-20 — sesión 51: retirada del logging DWC3 hot-path en v0.36

- Tras la nueva reconexión Windows conserva exactamente
  `USB\\VID_0000&PID_0002\\6&375DEBFF&0&4`, parent Genesys `05e3:0608` y
  `Port_#0004.Hub_#0003`; no aparece adaptador NCM ni dirección `172.16.*`.
  La reconexión/cable no resolvió la enumeración.
- La revisión del journal v0.31 aporta una causa software concreta. DWC3
  recibe `GET_DESCRIPTOR`, `SET_ADDRESS` y descriptores device/config/string,
  pero el parche temporal de v0.18 ejecuta `dev_info` para cada evento bruto,
  cada transición EP0 y cada SETUP. Las marcas temporales muestran pausas
  repetidas de ~20–21 ms entre líneas mientras Windows reintenta los mismos
  descriptores hasta Code 43.
- Esa instrumentación está en IRQ/control hot-path y ya no es necesaria: la
  cadena física, IRQ y EP0 quedaron demostradas. Los tracepoints upstream
  `trace_dwc3_event` y `trace_dwc3_ctrl_req` siguen disponibles sin imprimir
  sincrónicamente cada paquete.
- Se añadió `remove-dwc3-hotpath-diagnostics.patch`, aplicado después del
  parche diagnóstico. Elimina sólo los tres bloques de alta frecuencia y
  conserva las dos lecturas de estado alrededor del pull-up. El build directo
  actualiza también worktrees parciales si encuentra `SM-X910 diag event raw`.
- El paquete kernel sube de r17 a r18 y su `source=`/`sha512sums` incluyen el
  cleanup. La build directa recompiló únicamente `gadget.o`, `ep0.o` y el
  enlace final. El binario v0.36 contiene el mensaje de Goodix PID 6936 y el
  diagnóstico de pull-up, pero no las cadenas `diag event`, `diag ep0` ni
  `diag setup`.
- ZIP TWRP preparado:
  `postmarketos-edge-xfce-mainline-v0.36-usb-hotpath-clean-no-modules-sm-x910-twrp.zip`,
  22.007.155 bytes, SHA-256 previo a copia
  `00ad7fb3064124e7f49d49749b44ff148b96f42b9b5d8b55308dfeda1993a387`.
- Próximo paso: volver a TWRP, copiar/verificar v0.36 y flashearla. Mantener el
  otro pmOS desconectado; aceptar SSH sólo si la host key es `1N9kAKdf...`.
- La usuaria volvió a TWRP. v0.36 se copió a `/sdcard` y la única comparación
  local/remota coincide en
  `00ad7fb3064124e7f49d49749b44ff148b96f42b9b5d8b55308dfeda1993a387`.
  Queda pendiente el flash manual; el asistente no escribió particiones.

## 2026-07-20 — sesión 52: v0.36 mantiene Code 43

- La usuaria flasheó v0.36 y arrancó manteniendo desconectado el otro pmOS.
  Windows no crea ningún adaptador NCM ni dirección `172.16.*`.
- La X910 continúa como `USB\\VID_0000&PID_0002...`, dispositivo desconocido
  por error de solicitud de descriptor. Por tanto los `printk` por evento/EP0
  agravaban el timing y debían retirarse, pero no eran la causa suficiente del
  fallo externo.
- El cleanup DWC3 se conserva: evita interferencia en IRQ/EP0 y deja los
  tracepoints upstream disponibles. No se reintroducirá el logging síncrono.
- Próximo paso: volver a TWRP y extraer el journal/kernel log de v0.36. Sin los
  mensajes hot-path, comparar pull-up, reset/conexión, PTN3222 y cualquier
  error no enmascarado con v0.31 antes de cambiar gadget, PHY o DWC3.

## 2026-07-20 — sesión 53: v0.37 aísla el bring-up WCN7850

- Se prioriza Wi-Fi como canal de control y se deja el USB Code 43 en segundo
  plano. La base física aceptada sigue siendo v0.36: LightDM y táctil correctos
  con release `7.2.0-rc3-dirty` y sin un árbol de módulos coincidente.
- La comparación del FDT stock, los journals v0.19.2/v0.21 y los DTS upstream
  SM8550 confirma WCN7850/Kiwi v2 `17cb:1107`, PCIe0, WLAN_EN GPIO80 y siete
  rails. El rail que faltaba en v0.19.2 es PM8550VS-G LDO3 a 1,2 V. El fallo
  de v0.20 no demuestra que L3G sea incorrecto: lo causó asignar al bloque de
  reguladores el padre espurio `vdd-l3-supply = <&vreg_s4g...>`. v0.37 declara
  LDO3 directamente, como los diseños upstream MTP/Q5Q.
- v0.21 registró habilitación satisfactoria de los siete inputs y WLAN_EN alto
  antes y después de la secuencia, pero nunca una transición de reset. El
  driver pwrseq preserva por diseño un GPIO heredado alto. Se añade
  `cold-reset-wcn7850-before-pcie-probe.patch`: sólo WCN7850 solicita WLAN_EN
  inicialmente bajo, lo mantiene 5–10 ms y continúa con el power-up normal.
- Para eliminar el factor que introdujo los pingüinos desde v0.19, PHY QMP
  PCIe, PCI pwrctrl/pwrseq, WCN pwrseq, MHI, QRTR, rfkill, cfg80211, mac80211,
  QMI y dependencias criptográficas quedan built-in. `ATH12K=m`; se construyen
  de forma aislada sólo `ath12k.ko.zst` y `ath12k_wifi7.ko.zst`, que se cargan
  desde la rootfs tras el arranque. Un parche Kconfig mínimo fija built-in los
  proveedores ocultos que `olddefconfig` devolvía a módulo.
- Hubo tres intentos parciales no aceptados: un hunk del parche cold-reset con
  conteos inválidos; un modpost `M=` sin `Module.symvers`; y símbolos ocultos
  que aún resolvían como módulos. Se corrigieron respectivamente regenerando
  el parche, copiando `vmlinux.symvers` para el build aislado y aplicando los
  defaults QCOM built-in. La cuarta build terminó correctamente.
- Validación final del kernel/DTB: PCIe0 y PHY `okay`, L3G directo, referencia
  `vddio1p2`, ausencia del padre erróneo, todos los proveedores requeridos en
  `=y`, exactamente dos módulos con vermagic `7.2.0-rc3-dirty`, dependencia
  `ath12k_wifi7 -> ath12k` y alias PCI `17cb:1107`.
- El overlay incluye los cuatro blobs stock exactos como `amss.bin`, `m3.bin`,
  `board.bin` y `regdb.bin`, configuración de carga tardía, control SSH y el
  handoff de display conocido. El ZIP final superó CRC, hashes internos,
  permisos POSIX, tamaños de las cinco imágenes y manifiesto del overlay.
- Artefacto:
  `artifacts/postmarketos-edge-xfce-mainline-v0.37-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.179.256 bytes, SHA-256
  `b35522406582727052ea768c564ab8c7623891726c1b5b0700cfc5d0d011af5a`.
  Se copió a `/sdcard`; la única comparación local/tablet coincide. El
  asistente no flasheó particiones.
- Próximo paso: flash manual, comprobar primero LightDM/táctil y volver a TWRP
  para extraer el journal. Buscar el cold-reset GPIO, una sola secuencia PCIe,
  endpoint `17cb:1107`, MHI/firmware ath12k e interfaz NetworkManager. Si no
  aparece el endpoint, instrumentar PERST/LTSSM/PHY sin cambiar rails a ciegas.

## 2026-07-20 — sesión 54: v0.37 no se instaló; instalador corregido en v0.38

- La usuaria informó que el sistema volvía a LightDM con táctil pero sin
  Wi-Fi. Desde TWRP se montó `mmcblk1p2` en `ro,noload`, se extrajeron los doce
  journals de sistema más recientes y los logs persistentes de recovery, y se
  desmontó la rootfs antes de continuar.
- La rootfs física no contiene `/usr/lib/modules/7.2.0-rc3-dirty` ni
  `/etc/modules-load.d/ath12k.conf`; sólo permanece el árbol antiguo
  `7.2.0-rc3`. El boot más reciente registra errores de módulos ausentes y no
  contiene ninguna traza PMU WCN, cold-reset, PCIe0 o ath12k.
- La comprobación de particiones en lectura fija la identidad de la build:
  `boot` tiene SHA-256 `bf83c827…2da7`, exactamente v0.36, y `vendor_boot`
  conserva `6793730d…e3f5`, no los hashes v0.37 `fc9171bf…919` y
  `a5f16532…c12`. `init_boot`/`dtbo` no discriminan porque son comunes.
- `last_log.gz` resuelve la contradicción: los dos intentos manuales de v0.37
  abortaron en cero segundos con `Device or resource busy` al intentar montar
  `/dev/block/mmcblk1p2` sobre `/tmp/pmos-root`. La partición seguía montada de
  una auditoría anterior. El aborto ocurrió antes del bucle que escribe
  `boot`, así que el posterior reinicio arrancó v0.36 intacta. Wi-Fi v0.37 no
  llegó a probarse.
- Se corrige `configs/twrp/mainline-update-binary`: si `mmcblk1p2` está montada
  en cualquier ruta, o si `/tmp/pmos-root` contiene otro montaje temporal, el
  instalador lo desmonta y verifica antes del montaje RW. También corrige el
  mensaje del overlay para describir configuración en vez de `deviceinfo`.
- v0.38 reconstruye de forma incremental los mismos kernel, DTB, dos módulos
  ath12k y cuatro blobs WCN de v0.37. La validación final cubre CRC, manifiestos,
  modos, imágenes, alias/dependencias de módulos, firmware y la nueva guarda
  del instalador.
- Artefacto:
  `artifacts/postmarketos-edge-xfce-mainline-v0.38-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.179.387 bytes, SHA-256
  `67c0d7bfda6e41eeca81a0d9494034c0746ee4c78735652c20884dc0e2632d5e`.
  Se copió a `/sdcard`; la única comparación local/tablet coincide. La rootfs
  está desmontada y el asistente no ha flasheado ninguna partición.
- Próximo paso: flash manual v0.38 y no reiniciar si TWRP muestra error. Tras
  un flash exitoso, arrancar y evaluar LightDM/táctil/Wi-Fi; si Wi-Fi sigue sin
  aparecer, volver a TWRP para extraer por primera vez el journal WCN real.

## 2026-07-20 — sesión 55: v0.38 valida la cadena WCN previa; diagnóstico v0.39

- La usuaria flasheó v0.38 correctamente. El sistema alcanza de nuevo el
  escritorio, el táctil conserva su funcionamiento y no aparece Wi-Fi. Al
  volver a TWRP se verificó la instalación física: `boot` tiene SHA-256
  `fc9171bfe1a33e96c71341351e76c9a94da4cbb3cddaf576004a5b14a66ab919`
  y `vendor_boot`
  `a5f165326e2659174ef0fe81b6bbe6474e0e6de84321894d0e97e4690a5b0c12`,
  ambos iguales al bundle. La rootfs contiene sólo `ath12k.ko.zst` y
  `wifi7/ath12k_wifi7.ko.zst` para release `7.2.0-rc3-dirty`, junto con
  `ath12k.conf`; por tanto v0.38 sí fue la build arrancada.
- Se extrajo en sólo lectura el journal del boot
  `5c45011802064b0d99c39349dd5265e3` a
  `work/v038-wifi-boot-20260720/` y se desmontó la rootfs. El orden es
  concluyente: PCIe0/PHY resuelven sus dependencias; el PMU adquiere siete
  regulators; `WLAN_EN cold reset value=0`; se registra el secuenciador; los
  siete rails devuelven éxito; WLAN_EN pasa de 0 a 1; iATU se inicializa; y
  unos 1,18 s después `qcom-pcie 1c00000.pcie` termina `Device not found`.
- El bus sí crea el root port Qualcomm `17cb:0113`, pero nunca enumera el
  endpoint Kiwi `17cb:1107`. `ath12k_wifi7` se inserta con éxito, aunque no
  tiene dispositivo PCI al que enlazarse. NetworkManager carga
  `NMWifiFactory` y rfkill declara Wi-Fi habilitado, pero no puede aparecer una
  interfaz. El fallo está antes de MHI, ath12k, board data y firmware.
- En DesignWare, `Device not found` tras esperar el enlace significa que el
  LTSSM sigue en `Detect.Quiet`/`Detect.Active`: el root complex funciona pero
  no percibe receptor en el endpoint. La evidencia stock relevante es GPIO80
  WLAN_EN, GPIO94 PERST, GPIO95 CLKREQ, GPIO96 WAKE y PCIe x2 Gen3.
- Se encontró una diferencia concreta en alimentación. El FDT stock X910
  vota S5G=1.000.000 µV (WLAN), S2G=980.000 µV (AON), S4E=950.000 µV (DIG),
  S4G=1.350.000 µV (RFA2), S6G=1.900.000 µV (RFA1), L15B=1.800.000 µV y
  L3G=1.200.000 µV. v0.38 fijaba L15B/L3G, pero declaraba rangos amplios para
  los cinco SMPS; el éxito de `regulator_bulk_enable()` no demostraba qué
  tensión efectiva escogió el framework.
- v0.39 fija los cinco SMPS restantes al voto stock exacto. El nuevo parche
  `diagnose-wcn7850-pcie-link.patch` registra, sin alterar la secuencia, el
  estado/tensión efectiva de cada rail, PERST lógico/raw antes y después de
  assert/deassert, y PARF LTSSM/DBI DEBUG0/DEBUG1 al iniciar training. El
  paquete kernel sube a r20; providers PCIe/WCN siguen built-in y sólo se
  construyen los dos módulos ath12k aislados.
- Build terminada: `Image.gz` SHA-256
  `9d080e225c7fb3a5b87abb318e2611e8e37912452cf6e9c6398f7233d26222f0`;
  DTB `80af01d4c3bcca50f7da9b75e4ddc892709fc45c7029ba12428b5c91a1aebbcc`;
  config `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`;
  `boot.img`
  `a5dc4e6299b7865200a5232ae2229c5dbe213dc0971e6bf2b9b7dc1ba04d6b18`;
  `vendor_boot.img`
  `5402ca5cff47603d7d73fb6759424ef768ff4db18441d6c0534a825a3766e5d6`.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.39-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.182.376 bytes, SHA-256
  `8fc0877dd30c83095aa2df404f8b52e32c8f3aa0450cbd364fbe0730cafdec18`.
  La validación inspeccionó los siete voltajes en el DTB, las trazas del
  kernel, exactamente dos módulos con vermagic/dependencia/alias correctos,
  firmware, CRC, imágenes, overlay, permisos e instalador. Se copió a
  `/sdcard` y la única comparación local/tablet coincide; el asistente no
  flasheó ninguna partición.
- Próximo paso: flash manual v0.39. Si no aparece Wi-Fi, volver a TWRP y
  extraer el journal: los criterios son los siete voltajes reales, PERST raw
  0 durante assert y 1 tras deassert, estado LTSSM y endpoint `17cb:1107`. Si
  todo salvo el endpoint es correcto, el siguiente cambio debe comparar la
  tabla PHY QMP/refclock y la secuencia stock, no ath12k ni firmware.

## 2026-07-20 — sesión 56: selectores PM8550VS corregidos en v0.40

- La usuaria flasheó v0.39. La tablet alcanza el escritorio, conserva el
  táctil y sigue sin Wi-Fi; volvió manualmente a TWRP. Se montó
  `mmcblk1p2` como `ro,noload`, se extrajeron los journals a
  `work/v039-wifi-boot-20260720/` y se desmontó la rootfs.
- La identidad física coincide con v0.39: `boot` SHA-256
  `a5dc4e6299b7865200a5232ae2229c5dbe213dc0971e6bf2b9b7dc1ba04d6b18`
  y `vendor_boot`
  `5402ca5cff47603d7d73fb6759424ef768ff4db18441d6c0534a825a3766e5d6`;
  la rootfs contiene exactamente los dos módulos `7.2.0-rc3-dirty` y
  `ath12k.conf`.
- El boot relevante es `0e4b737851aa4f3cb70529b8c17c2ea8`. A 1,068 s S4E
  registra `failed to get the current voltage: -ENOTRECOVERABLE` y el
  proveedor PM8550VS-E falla en `smps4` con `-131`; a 1,091 s sucede lo mismo
  con S4G y el proveedor PM8550VS-G. WCN queda esperando S6G y PCIe0 PHY a
  L3G. No existen cold-reset, rails, PERST ni LTSSM porque la cadena no llegó
  a ejecutarse; ath12k y NetworkManager sí cargan pero siguen sin dispositivo.
- La causa está en la tabla `pmic5_ftsmps525` del driver mainline. Admite
  `300000 + 4000*n` µV hasta 1.372.000 µV y, desde 1.376.000 µV,
  `1376000 + 8000*n` µV. Los votos nominales stock 950.000, 1.350.000 y
  1.900.000 µV no son seleccionables. Al expresarlos como `min=max`, el core
  activa `apply_uV`, no puede mapearlos y aborta el registro del proveedor.
- v0.40 traduce cada voto nominal stock al primer nivel físico superior:
  S4E=952.000 µV, S4G=1.352.000 µV y S6G=1.904.000 µV.
  S2G=980.000 µV y S5G=1.000.000 µV ya son selectores exactos; L15B/L3G
  permanecen en 1.800.000/1.200.000 µV. El paquete kernel sube a r21 y todas
  las trazas v0.39 permanecen.
- Build v0.40: `Image.gz`
  `9d080e225c7fb3a5b87abb318e2611e8e37912452cf6e9c6398f7233d26222f0`;
  DTB `2ae3b8fca09dc3f5eb7d038ade1db030ab0cb3210259649473888d3a25789866`;
  config `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`;
  `boot.img`
  `06105bda5545ec06a0b1749a07bb7b0c86932045810fea6f2f0f1c702aab0d2d`;
  `vendor_boot.img`
  `a525f2ec7b95edb9205ffafd4b1c408665259e0c4c06500e2295cb1927390892`.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.40-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.182.373 bytes, SHA-256
  `cb911bb9a68fe93c4d8bbfd61866f822d5d5ac39d1586ebf1c1740af0191225d`.
  La validación comprobó los cinco selectores SMPS, L3G, trazas, release,
  exactamente dos módulos y su dependencia/alias, firmware, imágenes, CRC,
  manifests, modos e instalador. Se copió a `/sdcard` y la única comparación
  local/tablet coincide; el asistente no flasheó particiones.
- Próximo paso: flash manual v0.40. Si sigue sin Wi-Fi, volver a TWRP para
  comprobar que los siete rails registran y leer sus voltajes efectivos,
  PERST lógico/raw, PARF/DBI LTSSM y la presencia de `17cb:1107` antes de
  decidir si la siguiente diferencia está en PHY/refclock.

## 2026-07-20 — sesión 57: v0.40 llega a Detect.Active; diagnóstico v0.41

- La usuaria flasheó v0.40. La tablet mantiene escritorio y táctil, pero no
  muestra Wi-Fi; volvió manualmente a TWRP. `boot` y `vendor_boot` coinciden
  con v0.40 (`06105bda…d2d` y `a525f2ec…892`), y la rootfs contiene sólo los
  dos módulos ath12k esperados. El journal del boot
  `f596bbdabbd344c781908d016c8bcee4` se extrajo a
  `work/v040-wifi-boot-20260720/` y la rootfs quedó desmontada.
- Los siete inputs WCN registran y quedan habilitados a 1.000.000, 1.800.000,
  1.200.000, 980.000, 952.000, 1.352.000 y 1.904.000 µV. WLAN_EN ejecuta el
  cold-reset 0→1; PERST raw es 0 afirmado y 1 liberado; iATU se inicializa.
  El root port `17cb:0113` aparece, pero no el endpoint `17cb:1107`.
- Al iniciar training, PARF `0x101` indica LTSSM habilitado en estado 1
  (`Detect.Active`), DEBUG0 vale `0xff2d01` y DEBUG1 `0x08600000`, sin bits de
  link-up/training. Tras ~0,96 s termina `Device not found`. ath12k carga como
  módulo pero no puede enlazarse: el fallo precede MHI, firmware y mac80211.
- La PHY usada es Gen3x2, como stock. Su tabla mainline coincide con la
  `qcom,phy-sequence` del FDT vivo; también coinciden PERST GPIO94, CLKREQ
  GPIO95 y WAKE GPIO96. El driver stock `cnss2.ko` extraído de `vendor_dlkm`
  confirma que para Kiwi v2 `0x1107` la secuencia genérica es rails, clocks y
  WLAN_EN. La lectura SW_CTRL y el ciclo extra de 100 ms sólo se ejecutan para
  `0x1103`, por lo que no se fuerzan GPIO82/83.
- Se añadió `diagnose-sm8550-pcie-clocks-phy.patch`, acotado por compatibles
  SM8550: registra los seis clocks QMP y sus rates, los clocks del controlador,
  registros PCS power/reset/start/status/endpoint-refclk, TLMM de GPIO80–83 y
  94–96, `TCSR_PCIE_0_CLKREF_EN` y PARF SYS/PHY/REFCLK/LTSSM. No altera rails,
  delays, muxes ni la secuencia estable. El kernel reproducible sube a r22.
- El primer empaquetado v0.41 se descartó: el build incremental aún no conocía
  el parche nuevo y produjo el mismo `Image.gz` que v0.40. Se corrigió
  `scripts/build-mainline-kernel.sh`; el intento real recompiló QMP/PCIe. Un
  error por `__clk_is_enabled` sin declarar se resolvió añadiendo
  `<linux/clk-provider.h>` al parche reproducible.
- Build válida: `Image.gz` SHA-256
  `2c111b8417a0954b597264cd292d9dcaae7dd38bd0de63e888461f046686fb9f`;
  DTB `2ae3b8fca09dc3f5eb7d038ade1db030ab0cb3210259649473888d3a25789866`;
  config `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`;
  `boot.img` `adfd2e7c51cd923e93448719d7526eecaedf19f287f6488e0e182859fbfb7f47`;
  `vendor_boot.img`
  `a525f2ec7b95edb9205ffafd4b1c408665259e0c4c06500e2295cb1927390892`.
  El binario contiene las cinco familias de trazas y la secuencia completa de
  parches se aplica limpiamente sobre upstream.
- ZIP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.41-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.181.338 bytes, SHA-256
  `78dee1a129ecdfc9e3162a093771e00c4fc78894ceda195af82ac0136d0f0ec4`.
  Se copió a `/sdcard` y la única comparación local/tablet coincide; el
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.41, arrancar y volver a TWRP. El journal debe
  mostrar si `TCSR_CLKREF`, el mux CLKREQ, los clocks QMP/controlador y PCS
  están realmente activos. Sólo entonces aplicar el arreglo eléctrico mínimo
  justificado, conservando pantalla y táctil.

## 2026-07-20 — sesión 58: v0.41 reinicia temprano; recuperación v0.42

- La usuaria flasheó v0.41, que se reinicia antes de llegar al escritorio, y
  dejó de nuevo la tablet en TWRP. La partición `boot` confirma físicamente la
  build mediante SHA-256 `adfd2e7c…fb7f47`; `vendor_boot` conserva
  `a525f2ec…892`. Se extrajeron en lectura el journal, `/proc/last_kmsg`, lista
  de módulos y hashes a `work/v041-crash-boot-20260720/`, y la rootfs quedó
  desmontada.
- No existe un boot ID nuevo después de v0.40
  (`f596bbdabbd344c781908d016c8bcee4`): v0.41 reinicia antes de que journald
  pueda persistir el kernel log. El `last_kmsg` expuesto por TWRP corresponde
  al kernel recovery Samsung y no contiene el log mainline previo; pstore está
  vacío. Por ello no es posible atribuir el reset a una lectura individual.
- DTB, vendor_boot, módulos, firmware, rails y secuencia de alimentación eran
  idénticos a v0.40. El único cambio ejecutable era la instrumentación dentro
  de QMP/PCIe (`__clk_is_enabled`, registros PCS y `ioremap` de TLMM/TCSR), por
  lo que se retira completa: no se conservarán lecturas físicas ad hoc en la
  ruta de probe. El parche se eliminó de la receta y del build incremental;
  el kernel reproducible sube a r23 para registrar la reversión.
- v0.42 recompiló QMP y PCIe tras retirar la instrumentación. Conserva las
  trazas seguras de v0.40 (rails, WLAN_EN, PERST y LTSSM) y el mismo DTB. La
  observación restante se trasladó a userspace: al alcanzar
  `graphical.target`, `gts9uwifi-display-handoff` registra en el journal el
  `clk_summary`, GPIO80–83/94–96 y su pinmux bajo el tag
  `gts9uwifi-wifi-diag`. Sólo lee debugfs y no toca MMIO ni estados del clock
  framework durante el probe.
- Build v0.42: `Image.gz`
  `ec12fd56f84515ea22ec5d65928eb9df8ded562c4b1ed58b3e5c511fc4ea9740`;
  DTB `2ae3b8fca09dc3f5eb7d038ade1db030ab0cb3210259649473888d3a25789866`;
  config `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`;
  `boot.img` `ddc4169afaddb97592a1ca15ac07e223da0e14a80cc78f226b2f1beb5ad95e85`;
  `vendor_boot.img`
  `a525f2ec7b95edb9205ffafd4b1c408665259e0c4c06500e2295cb1927390892`.
  El binario ya no contiene ninguna cadena QMP/TLMM/PARF añadida por v0.41 y
  el script userspace supera `sh -n` y está presente en el ZIP.
- Artefacto:
  `artifacts/postmarketos-edge-xfce-mainline-v0.42-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.181.773 bytes, SHA-256
  `f234352596adfcce3002d01135ac6f67939505fc75f8abd673745fa0742936e8`.
  Se copió a `/sdcard` y la única comparación local/tablet coincide. El
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.42. Debe recuperar LightDM/táctil; después
  volver a TWRP para extraer el journal y leer el snapshot
  `gts9uwifi-wifi-diag` antes de decidir el siguiente cambio de Wi-Fi.

## 2026-07-20 — sesión 59: snapshot v0.42 limpio y programación AOP/PDC v0.43

- La usuaria flasheó v0.42, que recupera escritorio y táctil, y volvió a TWRP.
  Los hashes físicos confirman la build (`boot` `ddc4169a…5e85`,
  `vendor_boot` `a525f2ec…892`) y la rootfs conserva exactamente los dos
  módulos `7.2.0-rc3-dirty`. El journal del boot
  `a56864047e844a4e8cb0f0b574595ce2` (sesión de ~28 min) se extrajo en sólo
  lectura a `work/v042-wifi-boot-20260720/` y la rootfs quedó desmontada.
- El snapshot userspace `gts9uwifi-wifi-diag` se ejecutó completo y despeja
  todas las dudas del lado SoC: `gcc_pcie_0_*` (slv/mstr/cfg/aux/ddrss/
  aggre_noc) activos, `gcc_pcie_0_pipe_clk` habilitado con `pcie0_pipe_clk` a
  125 MHz, `gcc_pcie_0_phy_rchng_clk` a 100 MHz y, crucialmente,
  `tcsr_pcie_0_clkref_en` habilitado a 38,4 MHz por `1c06000.phy`. El pinmux
  confirma GPIO80/81 reclamados por `wcn7850-pmu`, GPIO82/83 sin reclamar
  (correcto para `0x1107`), GPIO94 PERST y GPIO96 WAKE como `gpio` y GPIO95
  con función `pcie0_clk_req_n`. Los siete rails repiten sus tensiones stock y
  el enlace vuelve a morir en `Detect.Active` (`DEBUG0=0x8a6901` esta vez).
- Con clocks, refclk, CLKREQ, PERST, rails y WLAN_EN verificados, la única
  diferencia estructural restante frente a stock es el bloque AOP/PDC del
  nodo cnss: `mboxes = <&qmp_aop>`, `qcom,vreg_pdc_map` y una
  `qcom,pdc_init_table` específica de `0x1107` que cnss2 envía al AOP por el
  mailbox QMP antes del primer power-on. Sus 13 mensajes habilitan el recurso
  PDC de banda base (`{class: wlan_pdc, ss: bb, res: pdc, enable: 1}`) y
  programan los votos up/down de los rails RF. Sin esa programación, el PMU
  del WCN7850 no completa su handshake hardware de encendido y nunca presenta
  receptores PCIe: exactamente el síntoma observado. La QRD upstream funciona
  sin esto porque su AOP trae el recurso habilitado por defecto; el de Samsung
  no.
- v0.43 añade `program-wcn7850-wlan-pdc-aop.patch` (kernel r24): en el probe
  de `pwrseq-qcom-wcn`, si el DT declara `qcom,qmp`, obtiene el mailbox con
  `qmp_get()` (API mainline, `CONFIG_QCOM_AOSS_QMP=y` ya presente) y envía
  cada cadena de `qcom,wlan-pdc-init` con `qmp_send()`, registrando el
  resultado por mensaje bajo `SM-X910 WCN diag: AOP pdc`. No hay MMIO nuevo ni
  cambios en la secuencia eléctrica; sin las propiedades DT el código es un
  no-op. El DTS añade `qcom,qmp = <&aoss_qmp>` y las 13 cadenas copiadas
  literalmente del `chip_cfg@1` del FDT vivo.
- El diagnóstico userspace se amplía para listar `/sys/bus/pci/devices` con
  vendor/device/driver: el éxito se verá como una segunda entrada `17cb:1107`
  con `ath12k` enlazado, sin depender de NetworkManager.
- Build v0.43: `Image.gz`
  `09944d99929f4a0dc96189839dd1c78e7c76b3efaee5c512a04fa908f23ace96`;
  DTB `641b20ba39130a93da37cd10bd04a69d29ad1f970e1699425fa37e29746f6b4a`;
  config sin cambios
  `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`;
  `boot.img` `6cab3ea19452f6e5adb62c0c2a43b3cd64c4a7919dbf084712d10ed408a53436`;
  `vendor_boot.img`
  `37124faedba4060b190ea7c7f34808a3762f6d7de9f2b2ee77d9ec10c9252ad2`.
  La validación confirma las trazas `AOP pdc` en el binario, las 13 cadenas y
  el phandle `qcom,qmp` en el DTB compilado, los nodos WCN/PCIe0/PHY activos y
  el listado PCI en el script del overlay.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.43-wcn7850-aop-pdc-sm-x910-twrp.zip`,
  27.183.654 bytes, SHA-256
  `b4f06bcdad3e56e91dd9df33bdccdcdaaedd9593f68adfc196ab76662e58bd7c`.
  Copiado a `/sdcard`; la única comparación local/tablet coincide. El
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.43 y arrancar hasta el escritorio. En el
  journal, `SM-X910 WCN diag: AOP pdc ... ret=0` confirmará que el AOP aceptó
  cada mensaje; el snapshot listará los dispositivos PCI. Si `17cb:1107`
  enumera, continuar con MHI/ath12k/firmware; si el AOP acepta los mensajes y
  el endpoint sigue ausente, la siguiente variable es el orden temporal
  (enviar la tabla también inmediatamente antes del deassert de PERST) o el
  wake handshake GPIO96.

## 2026-07-20 — sesión 60: el AOP acepta la tabla PDC; sondas SW_CTRL v0.44

- La usuaria flasheó v0.43 (hashes físicos confirmados: `boot`
  `6cab3ea1…3436`, `vendor_boot` `37124fae…2ad2`) y sigue sin Wi-Fi. El
  journal del boot `453d3291408f4b0f934d1d4961c9c674` se extrajo en sólo
  lectura a `work/v043-wifi-boot-20260720/` y la rootfs quedó desmontada.
- Resultado central: **el AOP aceptó los 13 mensajes** (`AOP pdc ... ret=0`
  para cada uno, incluido `{class: wlan_pdc, ss: bb, res: pdc, enable: 1}`)
  a los 1,6–1,77 s, antes del power-on (rails 2,1–5,8 s, WLAN_EN 5,81 s,
  PERST liberado 5,98 s). El mailbox QMP funciona y la programación PDC stock
  está aplicada; aun así el LTSSM permanece en `Detect.Active`
  (`DEBUG0=0x71ec01`) hasta `Device not found` y el snapshot PCI sólo lista
  el root port `17cb:0113`. La hipótesis AOP queda aplicada pero no
  suficiente por sí sola.
- Con la programación del SoC agotada, la siguiente evidencia debe venir del
  propio módulo. El chip expone indicadores hardware de su PMU interno:
  SW_CTRL WLAN en GPIO83 y SW_CTRL BT en GPIO82 (`qcom,wlan-sw-ctrl-gpio` /
  `qcom,bt-sw-ctrl-gpio` del FDT vivo), que cnss2 muestrea como entradas.
  Nuestro pinmux los tenía sin reclamar. Si tras WLAN_EN suben a 1, el módulo
  completa su secuencia interna y el fallo está en el enlace (refclk/lanes);
  si permanecen a 0, el PMU del módulo nunca arranca y el problema sigue
  siendo de alimentación/handshake.
- v0.44 (kernel r25) añade `read-wcn7850-sw-ctrl-after-enable.patch`: el
  pwrseq adquiere ambos pines como entradas (`wlan-sw-ctrl-gpios`/
  `bt-sw-ctrl-gpios`, nuevos en el DTS) y, tras subir WLAN_EN, registra sus
  valores a t+0/100/300/600 ms. Los sleeps retrasan además el deassert de
  PERST en 600 ms, cubriendo de paso la hipótesis de arranque lento del
  módulo. Sin las propiedades DT el código es un no-op.
- El diagnóstico userspace añade un `echo 1 > /sys/bus/pci/rescan` seguido de
  un segundo listado PCI: el LTSSM sigue sondeando Detect tras el
  `Device not found` del probe, de modo que un chip que tarde en presentar
  receptores entrenaría el enlace en silencio y aparecería en el rescan de
  los ~16 s sin reiniciar.
- Build v0.44: `boot.img`
  `fa96297815e7c04c6d7264c501e1334553f9e092188816fc5716408b1ab79cdf`;
  `vendor_boot.img`
  `0f35ae5ffdd9bdbfe7f589a9d9b2ea7cf56d48e5f0e7565cdd35655ba07bbb05`;
  DTB `dd4ef65d0f1970954bee860ae0fb3d7c7390b24daef8f2f44a3d737c6be3b3bc`;
  config sin cambios. Validado: trazas `SW_CTRL wlan=` y `AOP pdc` en el
  binario, `wlan-sw-ctrl-gpios`=83 y `bt-sw-ctrl-gpios`=82 más las 13 cadenas
  en el DTB, nodos PCIe0/PHY activos y rescan presente en el overlay.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.44-wcn7850-sw-ctrl-probe-sm-x910-twrp.zip`,
  27.182.347 bytes, SHA-256
  `c19a833a625453e8d2fab3f521438765e571b53eaebcc2775d5aa7d3e6d0facf`.
  Copiado a `/sdcard`; la única comparación local/tablet coincide. El
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.44. El journal decidirá la rama: SW_CTRL=1
  tras WLAN_EN acota el fallo al enlace PCIe (refclk hacia el módulo, lanes,
  PHY); SW_CTRL=0 mantiene el problema en la alimentación o el handshake
  interno del módulo (candidatos: orden AOP↔power-on, BT_EN, delay). Si el
  rescan tardío enumera `17cb:1107`, el problema era sólo de tiempo y se
  corrige con un retraso/retry reproducible en el kernel.

## 2026-07-20 — sesión 61: el mux PIPE de PCIe0 está aparcado en XO; v0.45

- La usuaria flasheó v0.44 (hashes físicos `fa962978…9cdf` /
  `0f35ae5f…bb05`) y sigue sin Wi-Fi. Journal del boot
  `3e51479c021244b5b0bba4103728a7ef` extraído en sólo lectura a
  `work/v044-wifi-boot-20260720/`; rootfs desmontada.
- Las sondas responden: `SW_CTRL wlan=1 bt=1` desde t+0 y estables hasta
  t+600 ms tras WLAN_EN — el módulo señala power-good (bt=1 con BT_EN bajo
  aconseja cautela por posible pull-up, pero el rescan PCI de los ~18 s
  tampoco encuentra `17cb:1107`, descartando el arranque lento). El retraso
  añadido de 600 ms antes de PERST tampoco cambia nada: LTSSM en
  `Detect.Active` (`DEBUG0=0x75001`).
- Revisión del clk_summary de v0.42/v0.44 con el código del driver delante:
  `gcc_pcie_0_pipe_clk_src` muestra 19.200.000. En `clk-regmap-phy-mux.c` de
  7.2-rc3, `recalc_rate` LEE el registro hardware del mux (0x6b070) y sólo
  devuelve 19,2 MHz cuando el campo vale `PHY_MUX_REF_SRC`: **el mux PIPE de
  PCIe0 está físicamente aparcado en el XO**. En este kernel los ops del mux
  son sólo `recalc/determine/set_rate` (sin `.enable`), nadie en el árbol
  llama a `clk_set_rate(pipe, ULONG_MAX)` y no hay `assigned-clocks` para él:
  mainline confía en el valor de reset del registro (0 = fuente PHY). En la
  QRD eso se cumple; la cadena de arranque Samsung deja el mux aparcado
  (coherente con el manejo `clock-suppressible` downstream) y mainline nunca
  lo des-aparca.
- Mecánica completa del fallo: con el mux en REF, la interfaz PIPE MAC↔serdes
  está muerta; el LTSSM no puede ordenar receiver-detect a la PHY y permanece
  para siempre en `Detect.Active` aunque la PHY reporte ready (el PCS no
  depende del mux GCC), los clocks del controlador corran y el módulo esté
  encendido (SW_CTRL=1). Explica todos los DEBUG0 vistos y por qué ni AOP,
  ni delays, ni rescans cambiaban nada.
- v0.45 (kernel r26) añade `unpark-pcie0-pipe-mux.patch`: en
  `qmp_pcie_power_on`, tras `clk_bulk_prepare_enable(pipe_clks)`, ejecuta
  `clk_set_rate(pipe, ULONG_MAX)` — el centinela documentado de
  `clk-regmap-phy-mux` para "selecciona la fuente PHY", propagado por el
  branch con `CLK_SET_RATE_PARENT` — y registra el resultado
  (`SM-X910 PCIe diag: pipe mux unpark ret=`). Es una llamada clk normal
  (regmap GCC), sin ioremap ni MMIO crudo; no toca la secuencia eléctrica.
- Build v0.45: `boot.img`
  `f5dbc10004c6afcbe2d74aad434042c987e78d98eba4044da3b10a8ed2223341`;
  `vendor_boot.img` sin cambios
  `0f35ae5ffdd9bdbfe7f589a9d9b2ea7cf56d48e5f0e7565cdd35655ba07bbb05`;
  DTB idéntico a v0.44
  `dd4ef65d0f1970954bee860ae0fb3d7c7390b24daef8f2f44a3d737c6be3b3bc`.
  Validado: la traza `pipe mux unpark` está en el binario junto a las de
  SW_CTRL y AOP pdc.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.45-wcn7850-unpark-pipe-mux-sm-x910-twrp.zip`,
  27.179.920 bytes, SHA-256
  `4d9703f22f5f018d93c838a60f31c942bc4db2a5760fed1ffe2b6ff9761b3fee`.
  Copiado a `/sdcard`; la única comparación local/tablet coincide. El
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.45. Éxito esperado: `pipe mux unpark ret=0`,
  el LTSSM saliendo de Detect, `17cb:1107` enumerado y ath12k enlazado (el
  firmware WCN7850 ya está en la rootfs desde v0.37). Si el mux se des-aparca
  pero el enlace sigue en Detect, el siguiente sospechoso es que el registro
  vuelva a aparcarse por hardware al no recibir el pipe clock del serdes, lo
  que movería el foco a la puesta en marcha del serdes de la PHY.

## 2026-07-21 — sesión 62: ¡enlace PCIe arriba! El bloqueo pasa al firmware; v0.46

- La usuaria flasheó v0.45 (hashes físicos `f5dbc100…3341` /
  `0f35ae5f…bb05`). Journal del boot `c9aa4d98acf745e0a3202c9f285f5015`
  extraído a `work/v045-wifi-boot-20260720/`; rootfs desmontada.
- **El des-aparcado funciona y derriba la barrera de tres días**:
  `pipe mux unpark ret=0`, el clk_summary pasa a mostrar
  `gcc_pcie_0_pipe_clk_src` en la fuente PHY (ULONG_MAX), y a los 6,99 s
  aparece `qcom-pcie 1c00000.pcie: PCIe Gen.2 x2 link up`. El endpoint
  **`17cb:1107` enumera** como `0000:01:00.0`, `ath12k_wifi7_pci` se enlaza,
  MHI entra en Mission mode y QMI lee `chip_id 0x2 chip_family 0x4
  board_id 0xff soc_id 0x40170200` y `fw_version 0x2036001f` (build
  2025-03-12): el amss stock arranca. La causa raíz del mux PIPE queda
  validada físicamente.
- El fallo restante es de la capa firmware: `failed to receive wmi unified
  ready event: -110` → `failed to start core: -110` tras las descargas QMI.
  Dos errores de mapeo de firmware nuestros lo explican:
  1. `board.bin` era el `bdwlan.elf` COMPLETO. ath12k envía `board.bin`
     literal como BDF (`fetch_board_data_api_1`), así que el firmware recibía
     una cabecera ELF ARM en lugar de board data. El ELF tiene un único
     segmento PT_LOAD en offset 0x400, tamaño 0x15400: el payload real.
  2. `m3.bin` era `phy_ucode20.elf` (microcódigo PHY, otro tipo de imagen QMI
     downstream). Para `wcn7850 hw2.0` ath12k usa `m3_loader_driver` y el
     m3.bin es obligatorio; el kiwi de Samsung no trae m3 (sólo amss20,
     bdwlan, phy_ucode, regdb), y estábamos inyectando 299 KB de microcódigo
     PHY como M3.
- v0.46 corrige ambos sin tocar el kernel (Image.gz idéntico a v0.45):
  `stage-stock-wifi-firmware.sh` extrae `bdwlan-payload.bin` (parseando el
  program header del ELF; SHA-256 `191ac306…c16d`) y descarga el `m3.bin`
  canónico de linux-firmware para WCN7850 hw2.0 (SHA-256 `0e72f44d…1055`,
  verificado byte a byte contra git.kernel.org). El overlay instala
  `board.bin` = payload y `m3.bin` = oficial; el APKBUILD del firmware sube a
  r2 con el mismo mapeo. `phy_ucode20.elf` deja de usarse (mainline no tiene
  su canal QMI).
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.46-wcn7850-real-bdf-m3-sm-x910-twrp.zip`,
  27.177.636 bytes, SHA-256
  `8a28e2416814e6406235221682a87c2cc1f1ec5b1afd37c580b8bcda88e7b4e7`.
  Overlay verificado (hashes de amss/m3/board/regdb) y copiado a `/sdcard`
  con la única comparación local/tablet coincidente. El asistente no flasheó
  ninguna partición.
- Próximo paso: flash manual v0.46. Éxito esperado: BDF y M3 correctos →
  `wmi unified ready`, registro mac80211 y `wlan0` en NetworkManager. Si el
  BDF de Samsung aún fallara, el plan B es `board-2.bin` genérica de
  linux-firmware (menos óptima en RF pero válida para validar la pila).

## 2026-07-21 — sesión 63: BDF/M3 correctos no bastan; amss oficial en v0.47

- La usuaria flasheó v0.46. La inspección física confirma el firmware
  corregido en la SD (`m3.bin` `0e72f44d…`, `board.bin` `191ac306…`) y los
  hashes de boot idénticos (kernel sin cambios). Journal del boot
  `d8ae45f646754ee1aa428a7163107614` extraído a
  `work/v046-wifi-boot-20260721/`; rootfs desmontada.
- El resultado es idéntico a v0.45: enlace arriba, `17cb:1107`, MHI Mission
  mode, QMI lee chip/fw_version, descargas BDF/M3 sin error visible y
  `failed to receive wmi unified ready event: -110`. Con BDF y M3 ya
  correctos, la variable restante demostrable es el propio `amss20.bin`
  stock: es la rama downstream `WLAN.HMT.2.0.c3.1` que cnss2 alimenta con
  `phy_ucode20.elf` mediante un tipo de descarga QMI que mainline ath12k no
  implementa. Sin su microcódigo PHY, el subsistema WLAN del firmware no
  arranca y WMI nunca señala ready.
- v0.47 cambia al firmware oficial de linux-firmware para WCN7850 hw2.0,
  probado con ath12k mainline y con el ucode integrado:
  `amss.bin` oficial (SHA-256 `43aadfd3…6a68`) y `board-2.bin` oficial
  (SHA-256 `1abee713…bf4e`, contenedor API-2 que ath12k intenta primero),
  manteniendo `board.bin` = payload BDF Samsung como fallback API-1, el
  `m3.bin` oficial y el `regdb.bin` stock. El kernel no cambia.
  `stage-stock-wifi-firmware.sh` descarga y fija por hash los tres ficheros
  oficiales; el APKBUILD del firmware sube a r3 con el mismo mapeo.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.47-wcn7850-official-amss-sm-x910-twrp.zip`,
  27.250.434 bytes, SHA-256
  `9b502da2870a12bebfc7cbe4c089071afabc2bf07e48a4fdf65f0309110f4e48`.
  Overlay verificado (cinco hashes) y copiado a `/sdcard` con la única
  comparación local/tablet coincidente. El asistente no flasheó ninguna
  partición.
- Próximo paso: flash manual v0.47. Éxito esperado: el amss oficial levanta
  WLAN sin ucode externo → `wmi unified ready`, mac80211 y `wlan0`. Si
  board-2.bin no casara con `board_id 0xff`, ath12k caerá al BDF Samsung; si
  aun así fallara WMI, quedaría investigar la compatibilidad
  amss-oficial↔BDF-Samsung y probar la BDF genérica del contenedor.

## 2026-07-21 — sesión 64: el amss oficial arranca pero la BDF QMI expira; v0.48

- La usuaria flasheó v0.47. La SD contiene el set oficial verificado por
  hash (amss `43aadfd3…`, board-2 `1abee713…`, board.bin Samsung, m3
  oficial). Journal del boot `bac3eec4ddbf460bbfa138a5862453e7` extraído a
  `work/v047-wifi-boot-20260721/`; rootfs desmontada.
- El amss oficial ARRANCA: `fw_version 0x1103006c`, build 2026-03-06,
  `WLAN.HMT.1.1.c7-00108-…_UPSTREAM-3` (la rama de linux-firmware), MHI
  Mission mode y QMI cap correctos. Pero el fallo se adelanta: a los 25,0 s
  `qmi failed to load bdf file` / `qmi failed to load board data file: -110`.
  Con el amss Samsung la descarga BDF completaba y moría WMI después; con el
  oficial el firmware deja de responder durante la propia descarga de board
  data. No hay mensajes de error de fetch de fichero, así que no se puede
  saber a ciegas si ath12k eligió board-2.bin o el fallback Samsung, ni en
  qué mensaje QMI exacto se atasca.
- v0.48 es una build de diagnóstico de una sola variable: activa
  `CONFIG_ATH12K_DEBUG=y` en el fragment (kernel r27; el Image no cambia, el
  símbolo sólo afecta al módulo) y añade
  `/etc/modprobe.d/ath12k-debug.conf` con `options ath12k debug_mask=0x62`
  (WMI|BOOT|QMI). El journal del siguiente arranque mostrará el boardname
  construido, qué fichero de board se usó, cada petición/respuesta QMI y el
  punto exacto del timeout.
- Trampa de build descubierta y corregida: el build `M=` deposita los
  objetos en el worktree fuente, no en el directorio `O=`, y el cambio de
  config no forzó recompilación; los dos primeros empaquetados v0.48
  salieron byte a byte idénticos y sin las cadenas `ath12k_dbg`. Tras
  limpiar `*.o/.cmd/*.mod*` del worktree, el módulo contiene `boot using
  board name` y las cadenas QMI; el validador comprueba ahora una cadena
  real de `ath12k_dbg` en el binario.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.48-wcn7850-qmi-debug-sm-x910-twrp.zip`,
  27.287.294 bytes, SHA-256
  `6b9c41293ec94f3d159905af293f9cafd03b08b0530f075696a43e99d89f31c9`.
  Copiado a `/sdcard`; la única comparación local/tablet coincide. El
  asistente no flasheó ninguna partición.
- Próximo paso: flash manual v0.48 y arrancar hasta el escritorio. El journal
  con `debug_mask=0x62` mostrará el boardname, el fichero de board elegido
  (board-2 vs fallback Samsung), cada transacción QMI y el mensaje exacto
  donde el firmware oficial deja de responder; con eso se decidirá el
  arreglo (BDF alternativa, tamaño de segmentos, o versión de amss).

## 2026-07-21 — sesión 65: el debug QMI acota el cuelgue al formato de la BDF; v0.49

- La usuaria flasheó v0.48 (boot hash `377818da…596e`). Journal del boot
  `92bfcc8facc1433fb51ce14109e481a4` extraído a
  `work/v048-wifi-boot-20260721/` (system.journal + dos rotados); rootfs
  desmontada. El debug `0x62` funcionó y la transacción QMI quedó a la vista.
- Secuencia exacta registrada: el boardname construido es
  `bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,
  subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255`; el regdb se
  descarga entero como `bdf_type 4` sin problema; la búsqueda en el
  `board-2.bin` oficial falla (`failed to fetch board data …`), ath12k cae
  al fallback `board.bin` (payload Samsung de 87.040 bytes) y lo envía como
  `bdf_type 0` en segmentos de 6144 bytes: el firmware ACEPTA todos hasta
  `remaining 1024` y nunca responde al último segmento (el que marca fin y
  dispara el parseo) → timeout -110 a los 10 s.
- La inspección del `board-2.bin` oficial explica ambas cosas: no existe
  ninguna entrada `subsystem 17cb:1107` con `qmi-board-id=255` (sólo 44/82),
  y la entrada de referencia con board-id 255 es la QRD
  (`subsystem 17cb:3378`). Al extraerla del contenedor (88.872 bytes) resulta
  ser **un ELF ARM**, igual que el `bdwlan.elf` de Samsung: las BDF de
  WCN7850 se distribuyen con su envoltorio ELF y ath12k elige el `bdf_type`
  QMI según la magia. La corrección v0.46 de despojar el ELF era errónea:
  el payload plano se envía como tipo 0 y el firmware oficial se cuelga
  parseándolo. Coherente con v0.45/v0.46: el amss Samsung sí digería ambas
  variantes y fallaba después por el phy_ucode ausente.
- v0.49 (sólo firmware, kernel intacto): `stage-stock-wifi-firmware.sh`
  extrae reproduciblemente la entrada QRD del contenedor oficial
  (`qrd-board.bin`, SHA-256 `0ef5f6f3…26a3`) y el overlay la instala como
  `board.bin` fallback. Es exactamente la pareja amss oficial + BDF QRD que
  funciona en la QRD SM8550 con mainline; el RF queda con calibración
  genérica hasta convertir la BDF Samsung más adelante.
- ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.49-wcn7850-qrd-bdf-sm-x910-twrp.zip`,
  27.286.591 bytes, SHA-256
  `bb0e235789f629dd196c2f86961309ad2b08d3a5146a0cb6abeef00fb5ec5253`.
  El overlay instala la BDF QRD verificada por hash; copiado a `/sdcard` con
  la única comparación local/tablet coincidente. El asistente no flasheó
  ninguna partición.
- Próximo paso: flash manual v0.49. El debug seguirá activo: el journal debe
  mostrar el fallback enviándose ahora como tipo ELF y, si el firmware lo
  acepta, `wmi unified ready`, mac80211 y `wlan0` en NetworkManager.

## 2026-07-21 — sesión 66: ✅ WI-FI FUNCIONAL Y SSH EN VIVO POR WLAN

- La usuaria flasheó v0.49 y confirmó físicamente: **el Wi-Fi funciona**. La
  combinación ganadora es amss oficial de linux-firmware + m3 oficial + BDF
  QRD en su envoltorio ELF como fallback `board.bin` + regdb stock, sobre el
  enlace PCIe recuperado en v0.45 (des-aparcado del mux PIPE).
- Primer acceso de control remoto del port: la tablet aparece en la LAN como
  `<TABLET_IP>`, identificada sin ambigüedad por su host key física
  `SHA256:1N9kAKdfusq7wxZmypG2PsCpqwhhDu5An+HC3SJAu0E`, y la clave de
  desarrollo Ed25519 (instalada por el overlay desde v0.37, privada en WSL
  `/root/.ssh/gts9u_pmos`) entra como `phablet`. `nmcli` muestra `wlan0`
  conectada a `<WIFI_SSID>` con señal 65 y 270 Mbit/s.
- El journal en vivo confirma la cadena completa sana: probe `17cb:1107`,
  `MHI_CB_EE_MISSION_MODE`, servicio QMI conectado, `phy capability` con 2
  PHYs y MLO anunciado, segmentos de memoria QMI concedidos y firmware
  arrancando WLAN. Evidencia guardada en `work/v049-wifi-live-20260721/`.
- Con esto quedan cumplidos los hitos 1–5 de la estrategia (kernel mainline,
  microSD, red+SSH, pantalla+táctil, escritorio) usando exclusivamente la
  base upstream. Pendientes de pulido, ya con canal de control en vivo:
  convertir la BDF Samsung para calibración RF nativa (hoy corre la QRD),
  retirar `debug_mask` y las trazas de bring-up, reintentar `board-2.bin`
  con entrada propia, Bluetooth (mismo PMU), el USB Code 43 aplazado y el
  resto del hardware (audio, sensores, GPU/Turnip).

## 2026-07-21 — sesión 67: contenedor BDF Samsung correcto; reprobe en caliente no concluyente

- Se leyó de nuevo el README completo, las sesiones 55–66 y los doce commits
  recientes antes de intervenir. La tablet v0.49 estaba accesible como
  `<TABLET_IP>`, con host key física verificada, kernel
  `7.2.0-rc3-dirty`, `wlan0` asociada y sólo los dos módulos ath12k aislados.
- La inspección estructural del `board-2.bin` oficial fijó el formato exacto:
  magia `QCA-ATH12K-BOARD`, IEs little-endian alineados a cuatro bytes,
  boardname sin NUL y BDF ELF completa como IE DATA. Se añadió el generador
  determinista `scripts/make-ath12k-board2.py`.
- La candidata `samsung-board-2.bin` mide 88.912 bytes, SHA-256
  `9886957c549c1dfa8d48ec80f23a0af0d524389054a74aeb85fd21de4ce4fb70`.
  Contiene una sola entrada con el nombre exacto
  `bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255`
  y los 88.760 bytes del `bdwlan.elf` Samsung, conservando la magia ELF.
- Para no perder el canal de control se lanzó una prueba desacoplada mediante
  unbind/bind de `0000:01:00.0`, con copia previa del `board-2.bin` oficial y
  rollback automático. La red no reapareció durante la ventana de 90 s con la
  candidata; después el servicio restauró el fichero anterior y reintentó el
  bind, pero tampoco volvió SSH. Windows sigue viendo sólo el USB Code 43.
- El resultado es **inconcluso respecto a la compatibilidad RF**: demuestra
  que el endpoint WCN7850 no recupera operación mediante este reprobe en
  caliente, incluso tras restaurar la combinación QRD conocida, pero no separa
  un límite del reset/rebind PCI de un rechazo de la BDF HMT.2.0. La fuente de
  build continúa instalando el `board-2.bin` oficial sin entrada X910 y la QRD
  ELF probada como `board.bin`; no se promueve la candidata sin evidencia.
- `firmware-samsung-gts9uwifi` sube en fuente a r4 para corregir una deriva
  reproducible: el APKBUILD todavía instalaba el payload Samsung plano de una
  iteración anterior, mientras v0.49 realmente usa la QRD ELF. r4 declara
  `official-board-2.bin` + `qrd-board.bin`, con checksums fijados.
- Siguiente paso: reinicio físico de la tablet. El watchdog ya debió restaurar
  el fichero estable; al volver `wlan0`, leer el resultado y journal de
  `gts9uwifi-native-bdf-test`. Si el reprobe no permite concluir, preparar una
  prueba de arranque limpio con rollback autónomo a QRD y segundo reinicio,
  sin empaquetar todavía la BDF Samsung en un ZIP.

## 2026-07-21 — sesión 68: BDF Samsung RECHAZADA por firmware (RDDM); QRD es final

- Tras el reinicio físico la tablet volvió con la QRD (Wi-Fi OK). Se confirmó
  la lección de la sesión 67: el reprobe PCI en caliente (unbind/bind) NO
  puede probar una BDF porque el WCN7850 sólo hace su cold-reset (WLAN_EN
  0→1 en `pwrseq-qcom-wcn`) en un arranque real; por eso aquel test quedó
  inconcluso. La rootfs vive en la microSD y es escribible por SSH, así que
  se montó una prueba de arranque limpio en vivo, sin flashear.
- Método: por SSH se instaló `samsung-board-2.bin` como `board-2.bin`, con la
  QRD respaldada, y un guard systemd oneshot autónomo
  (`gts9uwifi-bdf-trial`) que espera hasta 90 s la asociación de `wlan0` y,
  si falla, restaura la QRD y reinicia. Se armó el marcador y se reinició.
- Resultado DEFINITIVO (journal del boot de trial
  `8d88fb41580d47229930239c9fd2c832`): el contenedor era correcto. ath12k
  registra `boot found match board data for name '…board-id=255'`,
  `boot found board data`, `using board api 2` y descarga la BDF Samsung como
  `qmi bdf_type 1`. A falta de 2.744 de 82.616 bytes el firmware emite
  **`MHI_CB_EE_RDDM`** (RAM Dump Debug Mode = crash), seguido de
  `qmi failed to load bdf file` y `-110`. El `regdb` cayó correctamente a
  `regdb.bin` (`fetched regdb`), descartando ese como problema.
- Conclusión: la BDF Samsung es de la rama downstream **HMT.2.0** y el amss
  oficial de linux-firmware es **HMT.1.1**; el firmware oficial **crashea al
  parsear la board data Samsung**. La calibración RF nativa NO es alcanzable
  con el amss oficial. La única vía sería el amss Samsung, que exige
  `phy_ucode20.elf` por un canal QMI que sólo implementa cnss2 (no mainline):
  callejón cerrado por ahora. **La QRD queda como la BDF final**; el Wi-Fi
  funciona con calibración genérica y buena señal/tasa.
- El guard autónomo cumplió: restauró la QRD y reinició sin intervención; la
  tablet nunca perdió Wi-Fi de forma permanente. Los artefactos del trial se
  eliminaron por SSH; estado v0.49 prístino verificado por hash
  (`board-2.bin` `1abee713…`, `board.bin` QRD `0ef5f6f3…`, amss `43aadfd3…`,
  m3 `0e72f44d…`).
- La fuente reproducible ya instala la combinación QRD (sin cambios). El
  generador `make-ath12k-board2.py` y la candidata se conservan documentados
  por si en el futuro se resuelve el amss Samsung. Tarea 1 (RF nativo)
  cerrada como negativa concluyente; se pasa a la Tarea 2 (limpieza del
  debug de bring-up) antes de la GPU.

## 2026-07-21 — sesión 69: build limpia sin debug de bring-up (v0.50)

- Tarea 2: retirar todo el debug de bring-up de la fuente reproducible,
  conservando intactos los arreglos funcionales. Inventario del stack de
  parches vía diff pristino↔worktree: se confirmó que `linux-mainline`
  on-disk tiene modificados (sin commitear) `phy-nxp-ptn3222.c` y
  `phy-snps-eusb2.c`, pero el worktree de build se crea desde el HEAD limpio
  `a13c140cc`; el resto de ficheros tocados estaban limpios.
- Se DROPEARON los parches puramente de diagnóstico:
  `log-probe-entry-before-call`, `diagnose-sm8550-eusb2-link`,
  `diagnose-dwc3-ep0-enumeration`, `remove-dwc3-hotpath-diagnostics`,
  `diagnose-wcn7850-power-sequence`, `diagnose-wcn7850-pcie-link`,
  `read-wcn7850-sw-ctrl-after-enable`. Se retiró `CONFIG_ATH12K_DEBUG=y` del
  fragment, el `configs/wifi/ath12k-debug.conf` y su install, y las props DTS
  `wlan-sw-ctrl-gpios`/`bt-sw-ctrl-gpios` (ya sin consumidor).
- Los parches de arreglo independientes se conservan sin tocar
  (`match-samsung-...eusb2`, `configure-nxp-ptn3222`, goodix, dtb, sec-log,
  `build-wcn-pcie-providers-in`): se aplican antes que los de diagnóstico, así
  que dropear estos no altera su contexto.
- Para los dos ficheros entrelazados se regeneraron parches funcionales-only
  contra pristino con `work/gen-clean-fix-patches.py`:
  `wcn7850-pwrseq-cold-reset-aop.patch` (consolida cold-reset WLAN_EN +
  programación AOP/PDC, reemplaza a `cold-reset-...`, `program-...-aop` y
  elimina las trazas de `diagnose-power-sequence`/`diagnose-pcie-link`/
  `read-sw-ctrl`) y `unpark-pcie0-pipe-mux.patch` (regenerado sin el
  `dev_info`; conserva `clk_set_rate(pipe, ULONG_MAX)`). El AOP mantiene el
  envío por QMP sin log por mensaje; el cold-reset conserva `OUT_LOW` +
  `usleep_range(5000,10000)` y la rama else original.
- Kernel r28. El worktree se recreó desde pristino para que sólo aplicara el
  set reducido; la build (con `set -e` + guardas) aplicó los nueve parches
  limpiamente. Validación del binario: **cero** ocurrencias de
  `SM-X910 * diag`, `delayed link state`, `effective state`, `probing %s`;
  presentes `pwrseq_qcom_wcn_program_wlan_pdc` y el arreglo Goodix; el módulo
  `ath12k.ko` ya no contiene cadenas de debug (`boot using board name` = 0).
  Verificación funcional de `pwrseq`: OUT_LOW+usleep, llamada AOP y unpark
  intactos, sin ninguna traza. Comportamiento idéntico al v0.49 funcional.
- Build v0.50: `Image.gz`
  `49bcb693767be494a416c08f3addee7af0556e9fff26944b64c55754fbdbfa3b`;
  DTB `641b20ba...` (vuelve al estado v0.43, sin sw-ctrl);
  `boot.img` `20c1e35f6cce827eeb286e0911c3dc7246f887644458dd1a2568015f8569dce3`;
  `vendor_boot.img` `37124fae...` (sin cambios). ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.50-clean-no-debug-sm-x910-twrp.zip`,
  27.252.430 bytes, SHA-256
  `bd4110d13d524792812fcee585c9917970623fcaece69b9cf54562df5f2e32f6`.
- La build no toca DTS Wi-Fi/rails ni el firmware QRD, así que el Wi-Fi debe
  seguir igual. Requiere flash (cambios built-in). Próximo paso: TWRP para
  copiar el ZIP y flash manual; después verificación EN VIVO por SSH de
  Wi-Fi, táctil y escritorio, y de que el dmesg está limpio de `SM-X910`.
- FLASH Y VALIDACIÓN FÍSICA (2026-07-21): la usuaria autorizó al asistente a
  reiniciar y flashear él mismo mientras el conjunto de particiones fuera el
  de siempre. El reinicio-a-recovery programático NO funciona en este Samsung
  (`systemctl --reboot-argument=recovery` escribe el reboot-mode nvmem de
  mainline, pero el bootloader Samsung no lo honra y arrancó de nuevo pmOS);
  la usuaria puso TWRP manualmente. `adb reboot sideload` deja TWRP en
  `recovery`, no en `sideload`, así que se usó la CLI de TWRP: `adb push` del
  ZIP a `/sdcard` (hash `bd4110d1…` verificado en el dispositivo) + `twrp
  install /sdcard/v0.50.zip` (mismo instalador que el flasheo por UI). El
  instalador escribió sólo `boot/init_boot/vendor_boot/dtbo` (+`vbmeta`
  condicional) y el overlay a `mmcblk1p2`; ninguna partición nueva.
- Verificación EN VIVO por SSH tras el arranque: kernel v0.50 corriendo
  (`#22 ... Tue Jul 21 12:26`), `dmesg`/journal con CERO ocurrencias de
  `SM-X910` y `boot using board name`, `wlan0` asociada a la red, táctil
  Goodix en `event0`, Xorg en VT7 y LightDM activos. **Tarea 2 cerrada:
  debug de bring-up retirado sin regresión alguna.** Base limpia lista para
  la Tarea 3 (GPU/DRM).

## 2026-07-21 — sesión 70: Tarea 3, Adreno 740 built-in (v0.51)

- **Reto.** La GPU (Adreno 740, `gpu@3d00000` + GMU `gmu@3d6a000`) fallaba el
  probe con `-110` porque su SMMU (`3da0000.iommu`) y el GMU no recibían reloj:
  faltaba `GPUCC_SM8550`. El objetivo de la sesión es llevar la GPU a una build
  reproducible sin tocar el arranque ni `simpledrm`.
- **Primer intento (fallido, módulo aislado).** Se probó `DRM_MSM=m` como módulo
  aislado (no autocargado, con blacklist) para poder `modprobe msm` en vivo. La
  build falló en `modpost`: `msm.ko` quedaba con símbolos indefinidos
  (`drm_exec_init`, `drm_gpuvm_bo_put`, `drm_sched_job_*`, …). Causa: los helpers
  DRM (`DRM_EXEC/GPUVM/SCHED/DISPLAY_HELPER`) son símbolos **invisibles**
  seleccionados sólo por `DRM_MSM`; con `DRM_MSM=m` quedan en `=m`, no entran en
  `vmlinux.symvers` y la build `M=` aislada no los resuelve. No hay ningún `=y`
  que los seleccione.
- **Solución: `DRM_MSM=y` built-in.** `=y` arrastra todos los helpers a `=y`
  automáticamente y no hay módulo que enlazar. Pero `olddefconfig` lo degradaba
  a `=m`: `DRM_MSM` tiene `depends on QCOM_LLCC/OCMEM || =n` y un tristate no
  puede superar una dependencia `=m` — con `QCOM_LLCC=m` y `QCOM_OCMEM=m` quedaba
  topado en `=m`. Fix en el fragment: `CONFIG_QCOM_LLCC=y` (la LLCC sí existe en
  SM8550, es el *slice* de caché de sistema de la GPU) y `# CONFIG_QCOM_OCMEM is
  not set` (OCMEM no existe en SM8550). Con eso `DRM_MSM=y` se mantiene y los
  helpers salen `=y`.
- **Cambios reproducibles.**
  - `config-gts9uwifi.fragment`: `+QCOM_LLCC=y`, `-QCOM_OCMEM`, `+GPUCC_SM8550=y`,
    `+DRM_MSM=y`. (sha512 `bbf6e8c1…`, APKBUILD r29 actualizado.)
  - `sm8550-samsung-gts9uwifi.dts`: `&gpu { status="okay"; zap-shader {
    firmware-name = "qcom/a740_zap.mdt"; }; }` (sha512 `e14dc580…`, sin cambios
    desde el intento previo). `mdss`/DPU siguen `disabled` → msm arranca headless
    y `simpledrm` conserva el scanout de arranque.
  - `scripts/stage-gpu-firmware.sh` (nuevo): copia el zap firmado por Samsung
    (`a740_zap.mdt/.b00/.b01/.b02`), `a740_sqe.fw` y `gmu_gen70200.bin` del vendor
    a la carpeta de firmware, con sha256 fijados. Blobs en `.gitignore`.
  - `scripts/build-wifi-bringup.sh`: instala el firmware GPU en
    `/usr/lib/firmware/qcom` del overlay. Se retiró la maquinaria de módulo msm
    (blacklist y build `M=`), ya innecesaria al ser built-in.
- **Verificación del binario.** `.config` final: `DRM_MSM=y`,
  `DRM_EXEC/GPUVM/SCHED/DISPLAY_HELPER=y`, `GPUCC_SM8550=y`, `SIMPLEDRM=y`.
  `modules.builtin` lista `drivers/gpu/drm/msm/msm.ko` y `System.map` tiene
  `msm_drm_init`, `adreno_gpu_init`, `a6xx_gpu_init` → msm enlazado en vmlinux.
  DTB: `gpu status=okay`, zap `qcom/a740_zap.mdt`, `mdss disabled`.
- **Build v0.51 (kernel r29).** `Image.gz`
  `a7dae79d89ef9c9e0f1b595c6973319f7e1682652ef07d344960fa92fd645b29`;
  DTB `cd4144b137626269987ed7066542c3195d5d5143373dcfdb31331087b0be5992`;
  `.config` `df7edcab8045c19105b259dac8c915a5776483873085076b4e8291ebc0d172f5`.
  ZIP TWRP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.51-adreno740-gpu-sm-x910-twrp.zip`,
  28.040.806 bytes, SHA-256
  `5b567e2ef2d6521bb077cc8a1a94a707fc48858349c80834a7b3bae9f001d3a7`.
  Sólo toca las particiones de siempre (boot/init_boot/vendor_boot/dtbo/vbmeta +
  overlay a `mmcblk1p2`); ninguna nueva.
- **Reinicio-a-recovery: re-confirmado que NO funciona.** `systemctl reboot
  recovery` no es sintaxis válida en systemd 261 («Too many arguments», sin
  reinicio); `systemctl reboot --reboot-argument=recovery` sí reinicia pero el
  bootloader Samsung ignora el reboot-mode nvmem de mainline y arrancó pmOS de
  nuevo en ~30 s (`up 0 min`, kernel `#22`, Wi-Fi OK). No puedo llevar la tablet
  a TWRP por software; requiere que la usuaria la ponga en TWRP a mano.
- **FLASH Y VALIDACIÓN DE v0.51.** La usuaria puso TWRP a mano; flasheado por
  `adb push` + `twrp install /sdcard/v051.zip` (sha256 `5b567e2e…` verificado en
  el dispositivo). Nota operativa: adb se cae durante `twrp install` («no
  devices/emulators found» al pedir reboot), pero la instalación **sí termina**;
  la tablet arrancó sola. Resultado: **kernel `#25` arrancado, sin colgarse**,
  `simpledrm` (card0) y `wlan0` intactos, y el driver `adreno` YA presente y
  ligado a `3d00000.gpu`. Es decir, msm built-in headless es seguro para el
  arranque. Pero la GPU **no** subió: `3da0000.iommu` sigue con `deferred probe
  timeout … error -110`, `3d6a000.gmu` sin ligar y **sin render node**
  (solo `card0` de simpledrm).
- **CAUSA RAÍZ del `-110` (encontrada en vivo).** El diagnóstico mostró que
  `3d90000.clock-controller` (el gpucc de la GPU) **no tenía driver ninguno**:
  en `/sys/bus/platform/drivers` sólo aparecían `sdm845-gpucc`, `sm8150-gpucc` y
  `sm8250-gpucc`. Motivo: **`CONFIG_GPUCC_SM8550` no existe como símbolo
  Kconfig**; el nombre real es **`CONFIG_SM_GPUCC_8550`** (convención
  `SM_GPUCC_<n>` en `drivers/clk/qcom/Kconfig`, `obj-$(CONFIG_SM_GPUCC_8550) +=
  gpucc-sm8550.o`). `olddefconfig` descartó la línea inventada sin avisar, y
  además ese símbolo viene por defecto en `=m`, que este port nunca autocarga.
  Sin gpucc, el SMMU de la GPU y el GMU esperaban relojes que nunca llegaban →
  deferred probe → `-110`.
- **v0.52: el arreglo.** `CONFIG_SM_GPUCC_8550=y` en el fragment. Verificado en
  el binario: `gpucc-sm8550.ko` y `msm.ko` en `modules.builtin`, `SM_GCC_8550=y`,
  `ARM_SMMU=y`, `QCOM_SCM=y`, `QCOM_MDT_LOADER=y` (carga del zap MDT),
  `SIMPLEDRM=y`. `Image.gz`
  `087b222be67385068ceb58d1fa348e3b968d468b7e130df08d594d71b90082f8`; DTB sin
  cambios (`cd4144b1…`); ZIP
  `artifacts/postmarketos-edge-xfce-mainline-v0.52-adreno740-gpucc-sm-x910-twrp.zip`,
  28.039.515 bytes, SHA-256
  `bd70b9a4e1997ae3b7e16557c5d3b2fbfb88b725d8878fc81778f9fad85ef3f0`. Sólo
  cambia `boot.img` (`0d878a77…`); dtbo/init_boot/vbmeta/vendor_boot son
  idénticos a v0.51.
- **Guarda nueva en `build-mainline-kernel.sh`.** Tras `olddefconfig` se
  comprueba que cada símbolo del fragment sobrevivió: si un símbolo es
  desconocido o quedó deshabilitado la build **falla** (es exactamente el fallo
  que dejó la GPU sin su controlador de relojes); si sólo se degradó a `=m`
  porque un `select` no puede darlo built-in, se avisa. La guarda detectó de
  inmediato el caso benigno `ATH_COMMON=y`, que bajo `ATH12K=m` sólo puede ser
  `=m` (Wi-Fi funciona igual).
- **Flashear desde pmOS es IMPOSIBLE (comprobado, sólo lectura).** Se evaluó
  escribir `boot.img` por SSH con `dd` para evitar el viaje a TWRP en cada
  iteración. No se puede: **el kernel mainline no enumera el almacenamiento
  interno UFS**. En la tablet sólo existe la microSD (`mmcblk1`: p1 `/boot`,
  p2 `/`), no hay ningún `/dev/sd*` ni controlador UFS en el log (sólo
  `sdhci_msm`), y `/dev/disk/by-partlabel/` contiene únicamente `primary` (la
  GPT de la propia SD) — no existen nodos `boot`, `init_boot`, `dtbo` ni
  `vbmeta`. Las particiones que flasheamos viven en ese UFS interno, así que
  **TWRP (kernel Android con driver UFS) es la única vía**. Dato de referencia
  del instalador: escribe por `/dev/block/by-name/<part>` (sin sufijo de slot;
  este dispositivo NO es A/B) y exige `boot` = 100.663.296 B, que es
  exactamente el tamaño de nuestro `boot.img` (escritura 1:1).
  Vía futura opcional para desbloquear el flasheo autónomo: habilitar
  `SCSI_UFS_QCOM` (+ nodo UFS y sus reguladores en el DTS), pero es un
  subsistema nuevo en el arranque y se deja fuera de la iteración de GPU para
  no arriesgar una base que funciona.
- **v0.52 VALIDADA EN VIVO: el `-110` DESAPARECE.** Flasheada por `twrp install`
  (el instalador escribió boot/init_boot/vendor_boot/dtbo y preservó el vbmeta
  de sólo lectura con AVB flags 2; overlay verificado; ninguna partición nueva).
  Kernel `#26`. Resultados: `arm-smmu 3da0000.iommu` **sondea bien**
  (`SMMUv2`, stage-1, 24 grupos de stream matching, 22 context banks);
  `3d90000.clock-controller` **ligado a `gpu_cc-sm8550`** con 21 relojes
  `gpu_cc` registrados; `3d00000.gpu` **ligado a `adreno`**; dominios
  `gpu_cc_gx_gdsc`/`gpu_cc_cx_gdsc` presentes; los seis blobs de firmware GPU
  verificados en el dispositivo; `simpledrm` y `wlan0` intactos. Nada en
  `devices_deferred` salvo un `cpufreq`/icc ajeno.
- **SEGUNDO BLOQUEO (estructural, no eléctrico): sin render node.** `3d6a000.gmu`
  aparece «unbound», lo cual es NORMAL (msm toma el GMU desde el probe de la GPU,
  no con un driver propio). El problema real está en `adreno_probe()`:

      if (of_device_is_compatible(..., "amd,imageon") || msm_gpu_no_components())
              return msm_gpu_probe(pdev, &a3xx_ops);   /* DRM propio */
      return component_add(&pdev->dev, &a3xx_ops);     /* espera un master */

  y `msm_gpu_no_components()` sólo devuelve el **parámetro de módulo
  `separate_gpu_kms`**, que por defecto es *false*. Así que `adreno` se registra
  como *componente* y espera un component master que **únicamente crea el
  display (mdss) vía `msm_drv_probe`**. Como el mdss está deshabilitado a
  propósito para no tocar `simpledrm`, ese master no existe nunca y la GPU se
  queda ligada pero inerte. Deshabilitar KMS NO lo arregla: el parámetro es el
  único interruptor, y al ser `0400` sólo puede fijarse en el arranque.
- **v0.53: `msm.separate_gpu_kms=1`.** Añadido a
  `configs/vendor_boot/cmdline.txt` (que el bundle pasa como `--vendor_cmdline`),
  para tomar la vía `msm_gpu_probe()` y dar a la GPU su propio dispositivo DRM:
  justo el montaje headless render-only que buscamos, con `simpledrm` conservando
  la pantalla. Verificado dentro de `vendor_boot.img`; config del kernel idéntica
  a v0.52 (`50106199…`), sólo cambian `boot.img` (`7db68510…`) y `vendor_boot.img`
  (`99723719…`). ZIP
  `artifacts/postmarketos-edge-xfce-mainline-v0.53-adreno740-separate-gpu-kms-sm-x910-twrp.zip`,
  28.037.746 bytes, SHA-256
  `8df8e9f4dde7209204ae107ffe84922a68e61349f0c9584ddf9ed790e18b12e9`.
- **✅ v0.53 VALIDADA: LA GPU ADRENO 740 ARRANCA.** Flasheada por `twrp install`
  (mismo conjunto de particiones; overlay verificado). Kernel `#27`. En vivo:
  - `[drm] Initialized msm 1.13.0 for 3d00000.gpu on minor 1` → **existe
    `/dev/dri/card1` y `/dev/dri/renderD128`** (render node), con
    `DRIVER=adreno` en ambos.
  - Firmware cargado: `qcom/a740_sqe.fw`, `qcom/gmu_gen70200.bin` y
    **`[drm] Loaded GMU firmware v4.1.9`**.
  - `debugfs dri/1/gpu`: `gpu-initialized: 1`, `revision: 43050a01`,
    ringbuffers con fences retirándose.
  - **Mesa/freedreno YA FUNCIONA**: Xorg levantó
    `glamor X acceleration enabled on FD740` con **contexto OpenGL 4.6**. El
    stack de userspace (msm_dri.so) está operativo sin tocar nada.
  - `simpledrm` (card0) conserva la pantalla y el Wi-Fi sigue conectado.
- **NUEVO PROBLEMA: cuelgues bajo carga sostenida.** Con glamor activo la GPU
  entra en bucle `hangcheck detected gpu lockup rb 2` → `hangcheck recover!`,
  tarea culpable `Xorg`, ~1 cada 3 s (64 cuelgues). El GPU se recupera siempre
  (el sistema sigue vivo: lightdm activo, SSH, Wi-Fi), pero el escritorio queda
  degradado.
  - **Mitigación en vivo aplicada**: `/etc/X11/xorg.conf.d/10-no-glamor.conf`
    con `Option "AccelMethod" "none"` sobre `card0` → `glamor disabled`; el
    contador de cuelgues se congela en 64 y el escritorio vuelve a ser estable.
    El render node sigue disponible para pruebas controladas. En reposo la GPU
    queda sana (`gpu-initialized: 1`, `rbbm-status: 0x00000000`).
  - Descartado: el DT no está incompleto. El nodo `gpu@3d00000` upstream de
    `sm8550.dtsi` **tampoco** define `nvmem-cells`/`speed_bin` ni
    `power-domains` (el GMU gestiona los raíles), así que la ausencia de
    speedbin es el comportamiento normal de upstream, no una regresión nuestra.
    `interconnects`, `operating-points-v2`, `qcom,gmu` y `zap-shader` sí están
    presentes en el DT vivo, y no hay ningún fallo de iommu/SMMU ni error de
    zap en el log.
  - Hipótesis pendientes para la siguiente iteración: (a) probar **Turnip
    (Vulkan)** en vez del camino GL/glamor, que suele estar más maduro para
    a7xx; (b) limitar la frecuencia máxima de GPU para comprobar si es un
    problema de DCVS/voltaje del GMU; (c) analizar el **devcoredump** (`devcd1`)
    que ya se generó y contiene los registros exactos del cuelgue.
- **Investigación del cuelgue (sesión 70, en vivo).**
  - **Turnip instalado**: `apk add mesa-vulkan-freedreno vulkan-tools mesa-demos`
    → `libvulkan_freedreno.so` + `freedreno_icd.aarch64.json`. Turnip **carga**
    (sus mensajes MESA aparecen), pero `vkcube` no puede presentar:
    `No DRI3 support detected - required for presentation` (consecuencia de haber
    desactivado la aceleración de X). `vulkaninfo` aborta en
    `vkGetPhysicalDeviceDisplayPlanePropertiesKHR` (bug de la herramienta con la
    extensión de display, no de Turnip).
  - **La GPU renderiza bien fuera de X**: `eglinfo` por **GBM** da
    `vendor: freedreno`, `renderer: FD740`, `OpenGL 4.6 (Core) Mesa 26.1.1`,
    `direct rendering: Yes`, sin ningún cuelgue.
  - **CORRECCIÓN IMPORTANTE**: se probó capar `max_freq` a 220 MHz y pareció
    eliminar los cuelgues, pero **esa conclusión era falsa**. `cur_freq` se
    quedaba en 220 MHz y los benchmarks nunca llegaron a ejecutarse (glmark2
    salía por timeout sin renderizar), así que **no hubo carga**: la aparente
    estabilidad era ausencia de trabajo, no un arreglo. La frecuencia **no**
    está demostrada como causa.
  - **Lo que sí ocurre al reactivar glamor**: Xorg **muere**:
    `(EE) Segmentation fault at address 0xaaaa00000010` /
    `Caught signal 11 ... Server aborting`, ~1 s después de
    `glamor X acceleration enabled on FD740`. O sea, la ruta glamor falla de dos
    maneras (hangcheck de GPU al arrancar y segfault de Xorg después).
  - **Estado dejado estable**: `10-no-glamor.conf` (`AccelMethod "none"`)
    reinstalado, `max_freq` de vuelta a 680 MHz, lightdm reiniciado, Xorg vivo
    sin segfault, GPU limpia (`rbbm-status: 0x0`) y `renderD128` disponible.
- **Por qué glamor sobre simpledrm es un callejón sin salida.** glamor renderiza
  con la GPU y luego **copia** a un framebuffer lineal y tonto que posee
  `simpledrm`; es una ruta cruzada entre dos dispositivos DRM con formatos/tiling
  distintos. Lo correcto es que la pantalla la lleve el propio msm (DPU+DSI), con
  la GPU pintando directamente en buffers de scanout.
- **Viabilidad de DRM/KMS nativo (evaluada).** El lado SoC está completo en
  mainline: `mdss@ae00000`, `dpu`, `mdss_dsi0@ae94000` y `mdss_dsi0_phy@ae95000`
  existen en `sm8550.dtsi`. **Lo que falta es el panel**: el display es
  `GTS9U_ANA38407_AMSA46AS02` (DDIC ANA38407, 2960x1848) y **no hay driver
  upstream** (`drivers/gpu/drm/panel/` no tiene nada que case con ANA38407 ni
  AMSA46). Haría falta escribir `panel-samsung-ana38407.c` con la secuencia de
  comandos DCS de inicialización, que vive en el kernel downstream de Samsung —
  y ese código **no está descargado** en el workspace (`sources/` sólo tiene
  abl-mirror, abl-tianocore-edk2, libufdt, mkinitfs).
- **DECISIÓN: se va a por DRM/KMS nativo** (la usuaria eligió la ruta larga).

## Panel `GTS9U_ANA38407_AMSA46AS02`: datos extraídos del DTBO stock

Hallazgo importante: **no hace falta el kernel downstream para casi nada**. El
DTBO stock ya decompilado (`work/stock-dtbo-entries/entry-0.dts`, línea 8368,
nodo bajo `/fragment@24/__overlay__/qcom,mdss_mdp@ae00000/`) contiene el nodo
completo del panel. Extraído a `work/panel-ana38407.dts` (293 líneas).

- **Identidad**: fabricante SDC, DDIC **Anapass ANA38407**, modelo AMSA46AS02.
  `samsung,anapass-power-seq`, `samsung,esc-clk-128M`.
- **Modo**: `dsi_cmd_mode` (**modo comando**, no vídeo), 4 carriles, 24 bpp,
  `rgb_swap_rgb`, TE por pin (`te-pin-select=1`, `te-dcs-command=1`),
  `rx-eot-ignore` + `tx-eot-append`, ULPS habilitado.
- **Resolución**: 0xb90 x 0x738 = **2960 x 1848** (coincide con el framebuffer
  de simpledrm). Físico: 313 x 196 mm.
- **DSC**: `compression-mode = "dsc"`, 2 encoders, slice 1480 x 77,
  8 bit/componente, 8 bit/pixel, block-prediction; `lm-split = <1480 1480>`,
  topología `<2 2 1>`. OJO: `samsung,no_qcom_pps` (PPS propio, no el de QCOM).
- **Timings 120 Hz (wqxga120hs)**: hpw 36, hbp 30, hfp 16; vpw 32, vbp 32,
  vfp 16; framerate 120; clockrate 1.524 GHz;
  phy-timings `[00 35 0d 0d 1f 27 0d 0d 0c 02 04 00 2a 12]`;
  t-clk-pre 0x28, t-clk-post 0x11; transfer-time 7533 us.
  Hay 5 modos: wqxga120hs / wqxga60hs / wqxga60phs / wqxga30hs / wqxga30phs.
- **GPIOs**: reset = 125, TE = 86, ub-con-det = 67, tcon-rdy = 88,
  esd-irq1 = 186. Secuencia de reset `<0 10 1 1>`.
- **Backlight**: `bl_ctrl_dcs`, min 1, por defecto 0xff, con tablas de candela.
- **Formato de comandos**: DSL legible, p.ej. `W 0xF0 0x5A 0x5A`, `Delay 20ms`,
  `R 0xC1 0x01` (visible entero en `samsung,ddi_fw_id_rx_cmds_revA`), y llaves
  de nivel `level0/level1 key` = `0xF0 0x5A 0x5A` / `0xF1 0x5A 0x5A`.

**LO QUE FALTA (único bloqueo)**: la secuencia DCS de encendido. La propiedad
`samsung,mdss_dsi_on_tx_cmds_revA` es una **plantilla con macros**:

    W 0x11 / Delay 120ms / ${VBP_SETTING_FOR_SDC_IP} / ${MX_IP_ENABLE} /
    ${TCON_INTR_SETTING} / ${TE_ON} / ${TSP_SYNC_ON} / ${DSC_SETTING} /
    ${DIA_SETTING} / ${BRIGHTNESS_SETTING} / ${SP_SETTING} / Delay 100ms /
    ${VRR_SETTING}

y cada macro aparece **una sola vez** en todo el overlay (sólo la referencia):
Samsung las resuelve en su toolchain, así que los bytes reales están en el
driver downstream (`ss_dsi_panel_ANA38407_AMSA46AS02.c`). Hace falta el fuente
de `opensource.samsung.com` para SM-X910; no hay mirror público en GitHub
(buscado: sólo existen mirrors de otros modelos y kernels NinjaSU compilados).

**Herramienta útil localizada**: `msm8916-mainline/linux-mdss-dsi-panel-driver-generator`
genera un driver DRM de panel mainline a partir precisamente de un device tree
MDSS DSI de Qualcomm — el formato que ya tenemos extraído.

## ✅ Secuencia DCS del panel RECUPERADA (fuente Samsung obtenido)

La usuaria descargó `SM-X910_EUR_16_Opensource.zip` (640 MB) de
opensource.samsung.com y lo dejó en la carpeta del proyecto. Estructura:
`Kernel.tar.gz` + `Platform.tar.gz`. Se extrajeron **sólo** los ficheros del
panel por streaming del tar anidado (`work/extract-panel-driver.sh`, 18
ficheros a `/root/pmos-gts9u/samsung-src/...display-drivers/msm/samsung/`):
`GTS9U_ANA38407_AMSA46AS02_panel.c/.h`, `*_PDF.h` (3.3 MB), `*.dat` (546 KB),
mdnie, SELF_DISPLAY, FW_UPDATE, `ss_dsi_panel_common.h`.

**El bloqueo está resuelto.** El framework `ss_dsi_panel` es propietario y
gigante, pero el **Panel Data File** (`*_PDF.h`) codifica las secuencias DCS
como texto en arrays `0xNN`: decodificando todos los tokens hex del fichero se
obtiene el DSL con **las macros ya expandidas** (`work/decode-pdf.sh` →
`PDF-decoded.txt`, 1797 líneas, 34 bloques). Al contrario que el DTBO (donde
eran `${MACRO}`), aquí están los bytes reales.

Secuencia de encendido reconstruida (sleep-out `0x11` +120ms → VBP/DISPLAY_ON_
DELAY/MX_IP/TCON_INTR/TE_ON/TSP_SYNC → **PPS DSC** `WT 0x0A 0x11 00 00 89 30 …`
→ brillo → `Delay 50ms` → display-on `0x29`) y de apagado (`0x28`/`0x10`/100ms)
documentadas al detalle en **`docs/panel-ana38407-bringup.md`**, con todos los
payloads DCS. Datos clave: TE **Active Low**, `samsung,no_qcom_pps` (el panel
quiere SU PPS exacto), level-keys `0xF0/0xF1 0x5A 0x5A`.

- **Siguiente paso.** Escribir `panel-samsung-ana38407.c` mainline (drm_panel +
  mipi_dsi, DSC vía `drm_dsc_config`, secuencia de primera-luz mínima: reset →
  0x11 → VBP/MX_IP/TCON_INTR/TE_ON/DSC → 0x29). Luego, en el DTS: quitar
  `simple-framebuffer`, habilitar `&mdss`/`&mdss_mdp`/`&mdss_dsi0`/`&mdss_dsi0_phy`
  y el nodo del panel bajo dsi0, con reset-gpio 125 y TE. `DRM_MSM_DPU`/`DSI` ya
  están `=y`. Riesgo asumido: pantalla negra, recuperable por TWRP.
- **IMPORTANTE (primera luz)**: para no perder el canal de control, mantener SSH
  por Wi-Fi (independiente del display) y una build de rollback a v0.53 lista.
  El overlay del panel puede ir en una fase intermedia con simpledrm todavía
  presente para comparar, aunque lo natural es sustituirlo.

## Display nativo escrito (v0.55, primera-luz pendiente de flash)

- **`panel-samsung-ana38407.c` (nuevo, mainline)**: drm_panel + mipi_dsi,
  `compatible = "samsung,ana38407-amsa46as02"`. 5 modos (120/60/30 Hz), init/exit
  DCS transcritos del PDF, **DSC** desde `drm_dsc_config` (PPS decodificado:
  DSC 1.1, 2960x1848, slice 1480x77, 8bpc, 8.0bpp, 2 slices, block-pred),
  backlight DCS 0x51 (12-bit), 4 supplies (vddio/vdd/vci/avdd) + reset.
  API 7.2-rc3: `devm_drm_panel_alloc` + `devm_regulator_bulk_get_const` (el viejo
  `drm_panel_init` ya no existe — el primer build v0.55 falló por eso y se
  corrigió; el objeto compila con `COMPILE_EXIT=0`).
- **DTS**: `&dispcc` okay; `&mdss`/`&mdss_dsi0`/`&mdss_dsi0_phy` okay; nodo
  `panel@0` bajo dsi0 con `reset-gpios = <&tlmm 125 GPIO_ACTIVE_HIGH>`,
  `data-lanes = <0 1 2 3>` y port a `mdss_dsi0_out`; `vdda`=l3e_1p2,
  `vdds`(phy)=l1e_0p88. Añadidos **dos rails PMIC que faltaban** en pm8550b:
  `vreg_l11b_1p2` (vdd) y `vreg_l13b_3p0` (vci); vddio=l12b_1p8 ya existía.
  Regulador `display_avdd` = fixed 5.5 V por `<&tlmm 202>` (ELVDD).
  **Quitado el `simple-framebuffer`** para que msm controle la pantalla. El DTB
  compila limpio (phandles/reguladores resuelven).
- **Config**: `SM_DISPCC_8550=y` (mismo caso que gpucc: venía `=m` y este port no
  autocarga módulos), `DRM_PANEL_SAMSUNG_ANA38407=y`, `BACKLIGHT_CLASS_DEVICE=y`.
- **Integración reproducible**: `build-mainline-kernel.sh` copia el `.c` y
  registra Kconfig/Makefile; APKBUILD r31 con el `.c` en source + checksums.
- **Pendiente**: flashear v0.55 desde TWRP y comprobar primera luz. Puntos
  frágiles esperables en la 1ª iteración: los RC params del DSC (relleno parcial
  de `drm_dsc_config`), el rail exacto de `vdd`, la polaridad/tiempos del reset,
  y que el DPU acepte el modo comando + DSC. Depuración por SSH (Wi-Fi), rollback
  a v0.53 por TWRP.

## Primera luz: el PIPELINE nativo funciona, falta emisión del panel (v0.55–v0.57)

Tres flasheos de primera luz. En los tres el sistema arranca sano por SSH pero
**la pantalla queda NEGRA desde el primer instante** (ni pingüinos de arranque,
porque se quitó `simple-framebuffer`). Diagnóstico incremental:

- **v0.55**: toda la cadena arriba — `dispcc`→`msm_dpu`→`dsi`→panel driver
  ligado, conector `DSI-1: connected`, CRTC escaneando 2960x1848, Xorg y lightdm
  encima. **Todos los reguladores a voltaje** (incl. ELVDD 5.5V). Pero negra.
  Bug de X: la config `10-no-glamor.conf` (era simpledrm) apuntaba a `card0`, que
  ahora es la GPU (adreno); el display es `card1` (msm_dpu). Corregido en vivo
  → Xorg arranca sin "no screens", pero sigue negra.
- **v0.56 (fix DSC)**: `drm_dsc_config` sólo tenía 8 campos; el DPU necesita las
  tablas RC estándar 8bpp (`rc_buf_thresh`, `rc_range_params`, `rc_model_size`,
  offsets…). Añadidas (modelo ilitek). El DPU hace el split de doble slice DSC
  correcto (2×1480x1848). Sigue negra, **sin errores**.
- **v0.57 (fix TE + PPS + diagnóstico)**: dos bugs reales frente a los panels de
  modo comando de mainline (visionox-r66451, lg-sw43408) y el board Samsung
  `sdm845-samsung-starqltechn`:
  1. **PPS mal enviado**: yo mandaba el PPS como DCS `0x0A` hardcodeado (tipo de
     paquete equivocado); lo correcto es `drm_dsc_pps_payload_pack()` +
     `mipi_dsi_picture_parameter_set_multi()`. Corregido.
  2. **Falta el TE**: `gpio86` debe muxearse a `mdp_vsync` por pinctrl (igual que
     el QRD, mismo gpio). Añadidos pinctrl `sde_te` + `te-gpios`. Verificado en
     vivo: `gpio86 : func1 (mdp_vsync)`.
  Sigue negra.
- **DIAGNÓSTICO DEFINITIVO (debug DRM en vivo, sin reflashear)**: con
  `drm.debug` + restart de lightdm se capturó la transacción del DPU:
  `dpu_crtc_commit_kickoff … first commit`, kickoff de modo comando, y
  **`dpu_crtc_frame_event_work crtc103 event:1` + `dsi_host_irq`** → **un frame
  se completa SIN timeout**. Es decir, el DPU **sí entrega frames** al panel por
  DSI en modo comando con DSC. Los relojes son correctos (pixel 247 MHz, byte
  185 MHz ≈ 1.48 GHz, MDP 514 MHz).
- **El DDIC ESTÁ VIVO**: el cmdline lleva `msm_drm.lcd_id=800004` — ese ID lo
  leyó el **bootloader** del propio DDIC (0x80 0x00 0x04). Mi lectura por DCS daba
  `00 00 00` sólo porque **las lecturas DCS de msm no son fiables** (BTA), NO
  porque el panel esté muerto.
- **CONCLUSIÓN**: el pipeline entero funciona (relojes, DPU, DSI, DSC, TE, entrega
  de frames) y el panel recibe los frames, pero **no emite**. El fallo está en la
  **secuencia de init del DDIC** (o en la emisión). Hipótesis para la siguiente
  iteración, por probabilidad:
  1. **Orden de la secuencia por revisión**: el stock tiene DOS secuencias — revA
     (`W 0x11` primero, luego VBP/MX_IP/…) y revC+ (`POWER_ON_PRE_SETTING`:
     VBP/DISPLAY_ON_DELAY ANTES de `W 0x11`). Mi driver usa el orden revA; el ID
     `0x800004` sugiere una revisión concreta que podría querer el orden revC.
  2. **Brillo explícito**: quité el `W 0x51` de la secuencia; el registro de
     brillo del DDIC podría estar a 0 (aunque el bump en vivo del backlight por
     0x51 no cambió nada evidente).
  3. **Modo LP vs HS** para los comandos de init (el stock marca algunos modos
     `dsi_hs_mode`).
  El pipeline es un HITO enorme: sólo falta afinar los bytes de init del DDIC,
  que es trabajo iterativo (cada intento = build + flash TWRP).

## 2026-07-22 — sesión 71: v0.58 da imagen; v0.59 habilita UFS y se valida en vivo

- **Display nativo resuelto en v0.58.** El DDIC `lcd_id=0x800004` necesitaba la
  secuencia rev-D: VBP/DISPLAY_ON_DELAY antes de `0x11`, TSP sync rev-C+, DIA
  activa y brillo explícito `0x51=0x07ff`. Con esos cambios el panel
  ANA38407/AMSA46AS02 muestra físicamente XFCE a 2960×1848 sobre el pipeline
  nativo dispcc → msm_dpu → DSI command mode + DSC + TE → panel.
- ZIP v0.58:
  `postmarketos-edge-xfce-mainline-v0.58-native-display-revd-sm-x910-twrp.zip`,
  28.051.794 bytes, SHA-256
  `3b95f08793873d6da043754399f2d61f13fcde5651f475361a365e882fea226e`.
- **UFS v0.59.** Se integran built-in `CONFIG_SCSI_UFS_QCOM=y` y
  `CONFIG_PHY_QCOM_QMP_UFS=y`, los nodos `&ufs_mem_hc`/`&ufs_mem_phy`, reset
  GPIO210 y rails L17B 2,504 V, L1G 1,2 V, L1E 0,88 V y L3E/L3G 1,2 V. El
  paquete kernel queda reproducible como r34 con checksums actualizados.
- ZIP v0.59:
  `postmarketos-edge-xfce-mainline-v0.59-ufs-selfflash-sm-x910-twrp.zip`,
  28.081.015 bytes, SHA-256
  `a5feba247bc0cc77bc0c5ce3d926f6d7c006d6377f6b847370a6d13a67d06ceb`.
  Se flasheó desde TWRP con el script autorizado `work/flash-v059.ps1`; el
  instalador alcanzó `Unmounting System...`, ADB cayó como estaba previsto y
  la tablet arrancó sola.
- **Validación en vivo v0.59 (`#32`).** `ufshcd-qcom` registra `scsi host0` y
  enumera las seis LUN UFS `sda`–`sdf`. Las particiones internas aparecen por
  nombre: `boot=/dev/sda21`, `init_boot=/dev/sda22`,
  `vendor_boot=/dev/sda24`, `dtbo=/dev/sda30`; `vbmeta=/dev/sde15` sigue
  correctamente read-only. La raíz continúa en `mmcblk1p2`.
- No hay regresión: DSI-1 está `connected`, LightDM activo, Wi-Fi asociada y
  SSH identificado por la host key física. El estado gráfico previo queda
  confirmado: cmdline con `msm.separate_gpu_kms=1`, `card0=adreno`,
  `card1=msm_dpu`; Xorg fuerza `kmsdev card1` y `AccelMethod none`, y el DPU
  avisa `no GPU device was found`. El siguiente paso es retirar la separación,
  dejar que mdss cree el master DRM unificado y habilitar glamor.

## 2026-07-22 — sesión 72: v0.60 GPU+DPU unificada falla visualmente; rollback y recuperación automática del panel

- **Preflight UFS antes de escribir.** En v0.59 se verificó por SSH que
  `boot -> /dev/sda21` y `vendor_boot -> /dev/sda24`, ambas de 100.663.296
  bytes. Sus hashes coincidían exactamente con los exports v0.59:
  `89c07cab...ed9` y `c2a85241...921`. Se guardó además un rollback completo
  en `/home/phablet/rollback-v059/` y se verificó antes del experimento.
- **v0.60 unificada.** Se retiró `msm.separate_gpu_kms=1` y Xorg dejó de fijar
  `card1`, con `AccelMethod glamor`. El boot/vendor_boot se escribieron por UFS
  y se verificaron (`c35e3b6e...306e` / `3e5096da...770a`). En vivo se obtuvo
  una única `card0=msm_dpu`, `renderD128`, DSI-1 conectado y Adreno ligado al
  component master. Xorg registró OpenGL 4.6, glamor sobre FD740 y DRI3;
  `glxinfo` confirmó aceleración directa y `glmark2` ejecutó a pantalla completa
  2960×1848, 123 FPS, sin hangcheck/fault.
- **Fallo físico decisivo:** la cámara mostró que el OLED permanecía negro,
  incluso capturando mientras `glmark2` dibujaba. La GPU ejecuta y el DPU
  acepta los buffers, pero el master unificado no produce scanout visible en
  este bring-up. No confundir un benchmark lógico exitoso con imagen física.
  Se restauraron por hash ambos exports v0.59 y `kmsdev card1` + software.
- **Segundo camino descartado, con KMS separado.** Cambiar únicamente el DPU
  (`card1`) a glamor hace que Xorg abra correctamente FD740 (`glamor X
  acceleration enabled on FD740`), pero asigna `DRI driver: msm-kms`, intenta
  cargar `/usr/lib/dri/msm-kms_dri.so` (inexistente) y termina en SEGV. Sólo
  aparece un provider XRandR (`modesetting`, sink output); `DRI_PRIME=1`
  continúa en llvmpipe con la configuración software. Se restauró el baseline.
- **Alias/override userspace descartados.** Un symlink
  `msm-kms_dri.so -> msm_dri.so` llega más lejos pero falla con `msm-kms exports
  no extensions` y vuelve a generar coredumps de Xorg. Exportar
  `MESA_LOADER_DRIVER_OVERRIDE=msm` para LightDM no altera la selección del
  nombre en esta ruta AIGLX/DRI2: sigue buscando `msm-kms_dri.so` y hace SEGV.
  El watchdog de 90 s y la restauración manual devolvieron siempre software +
  DSI visible. En el kernel, `msm_kms_driver.name` es explícitamente
  `"msm-kms"`, mientras GPU/unificado usan `"msm"`; el siguiente experimento
  controlado será renombrar sólo ese driver para que Mesa seleccione su alias
  soportado, manteniendo las dos tarjetas DRM.
- **Hallazgo de reinicio cálido del panel.** Tanto tras el rollback como en un
  reinicio normal, el primer init puede leer `panel id: 00 00 00` y dejar el
  OLED negro aunque DSI-1 esté conectado. Un ciclo explícito `xrandr DSI-1
  off -> on` fuerza reset/reinit; el segundo prepare lee `80 00 04` y devuelve
  el login inmediatamente. Esto permitió recuperar la tablet sin TWRP ni
  power-cycle.
- **Workaround reproducible validado:** el drop-in regular
  `lightdm.service.d/20-gts9uwifi-panel-reinit.conf` ejecuta
  `/usr/libexec/gts9uwifi-panel-reinit` como `ExecStartPost`. En un arranque
  limpio terminó `SUCCESS`, cambió el ID de `00 00 00` (7,84 s) a `80 00 04`
  (24,66 s), y la cámara confirmó el login visible. Se eligió el drop-in porque
  `make-twrp-zip.py` omite symlinks absolutos del overlay y una unidad regular
  dentro de `.wants` resulta `disabled`; el drop-in sí queda en el ZIP y además
  se repite al reiniciar LightDM. Xorg desactiva los cuatro temporizadores de
  blanking/DPMS.
- **v0.61 estable construida y copiada.** ZIP
  `postmarketos-edge-xfce-mainline-v0.61-stable-display-panel-reinit-sm-x910-twrp.zip`,
  28.084.177 bytes, SHA-256
  `dd25084343e923457b11c9a2908186b68654aec4910b967b174eb90438b3ceb4`.
  `BUILD_EXIT=0`; contiene KMS separado, Xorg software/no-blank, script y
  drop-in. Copiado a `/home/phablet/v061.zip` y verificado una vez por hash.
  La tablet continúa sobre los boot images v0.59 equivalentes y los overlays
  v0.61 instalados/validados en vivo; no se reflasheó el ZIP para no añadir un
  ciclo TWRP innecesario.

## 2026-07-22 — sesión 73: el KMS vacío permite reverse PRIME; r2/r3 fallan y r4 da primera imagen acelerada

- La ruta `v0.62` de renombrar el driver KMS separado a `msm` no resolvió el
  problema fundamental: el DRM Adreno creado por `msm.separate_gpu_kms=1` era
  render-only y `DRM_IOCTL_MODE_GETRESOURCES` fallaba. Xorg no lo aceptaba como
  pantalla/proveedor, por lo que no podía actuar como source de reverse PRIME.
- Se añadió `expose-separate-gpu-kms-resources.patch`. La instancia GPU conserva
  cero CRTCs/planes/connectors, pero anuncia `DRIVER_MODESET`, inicializa un
  `mode_config` vacío y, en v0.64/v0.65, recibe los hooks dumb/framebuffer y
  límites finitos 1..16384 que Xorg necesita durante `PreInit`. El boot v0.65
  quedó instalado y validado: provider Adreno `Source Output/Offload` y DPU
  `Sink Output`, sin alterar la salida DSI estable.
- Se creó un Xorg local opt-in. `AllowEmptyInitialConfiguration` permite que
  Adreno sea primary sin connector y crea un modo sintético 2960×1848.
  `PrimeSinkOffload` se exploró para la dirección DPU-primary, pero esa dirección
  dejaba el root GLX en llvmpipe; se adoptó reverse PRIME (Adreno-primary,
  DPU-secondary).
- **r2 falló** con SEGV en `xf86InitViewport`: el primary no tenía lista de
  modos. El modo CVT sintético corrigió esa caída.
- **r3 falló** con SEGV en `xf86RandR12CreateMonitors`: RandR asumía al menos un
  output en la pantalla primary. Se añadieron guardas limitadas al caso
  `num_output == 0`.
- **r4 fue la primera ruta completa de escritorio reverse PRIME**: Xorg arrancó
  glamor sobre FD740, DPU quedó como GPU screen, `xrandr
  --setprovideroutputsource` + `DSI-1-1 2960x1848` mostró XFCE físicamente. Sin
  embargo, `glxinfo` emitía DRI3 `BadAlloc` y `glmark2` ocupaba una zona negra.
  El panel y el scanout 2D funcionaban; faltaba importar el buffer 3D.

## 2026-07-22 — sesión 74: diagnóstico DRI3 r5–r9; el modifier LINEAR resuelve la geometría negra

- **r5 descartado:** deshabilitar DRI3 para intentar DRI2 eliminó `BadAlloc`,
  pero AIGLX volvió a llvmpipe. DRI2 no ofrece la ruta accelerated+reverse PRIME
  requerida en esta topología.
- **r6 diagnóstico:** instrumentación temporal en `glamor_pixmap_from_fds()`
  demostró que el cliente legacy DRI3 entregaba un dma-buf con modifier
  `DRM_FORMAT_MOD_INVALID` y que `dmabuf_capable=0`; el import devolvía false.
  El ServerFlag documentado `Debug=dmabuf_capable` activó dma-buf, pero el
  modifier continuó inválido y el import siguió fallando.
- **r7/r8 descartados:** forzar LINEAR en la negociación
  `get_drawable_modifiers` no se ejecutaba. Mesa/GLX usa aquí el entry point
  heredado DRI3 `PixmapFromBuffer`, que no consulta modifiers antes de enviar
  el FD; por eso cambiar la lista anunciada no tenía efecto.
- **r9 resolvió la causa raíz:** con un switch opt-in
  `force_linear_dri3`, glamor convierte únicamente el modifier implícito
  `INVALID` a `DRM_FORMAT_MOD_LINEAR` antes de `gbm_bo_import`. El log confirmó
  modifier 0, `dmabuf=1`, sin retorno false; `glxinfo` pasó a freedreno FD740
  acelerado sin `BadAlloc`.
- Validación visual por OBS: tras corregir la referencia de cámara, la tablet es
  el dispositivo grande central con notch; el monitor inclinado de la izquierda
  no cuenta. El OLED central estaba negro pese a DPMS On y se recuperó con un
  ciclo DSI off/on. Después `glmark2` mostró físicamente el caballo y otras
  geometrías 3D, en vez del rectángulo negro, sin GPU/IOMMU/DRM faults.

## 2026-07-22 — sesión 75: Xorg r10 limpio, arranque automático y build reproducible v0.66

- Se retiraron todos los `ErrorF("SM-X910 DRI3 …")` de diagnóstico. Xorg r10
  conserva sólo las piezas funcionales opt-in: primary connectorless, modo
  sintético, guardas RandR y conversión implícita a LINEAR. APK compilado:
  `xorg-server-999921.1.23-r10.apk`, SHA-256
  `3d734fac4e0becc32e5f6489990c84ec0b1913ced7c302303d0952c0d9afa4c5`.
- La configuración canónica ahora pone `card0` Adreno como pantalla primary
  glamor y `card1` DPU como GPUDevice sin glamor. El hook existente
  `gts9uwifi-panel-reinit` descubre dinámicamente los provider IDs y el output
  conectado, los asocia, hace DSI off/on, activa 2960×1848@120 y fuerza DPMS
  on. Esto evita hardcodear `0x3e`, `0x70` o `DSI-1-1`.
- Prueba viva con rollback: r10 actualizó r9, reinició LightDM y, sin ejecutar
  comandos xrandr manuales, devolvió imagen en el OLED central. `glxinfo`:
  freedreno/FD740/Accelerated yes; `glmark2` visible a pantalla completa,
  escenas iniciales 124–153 FPS, sin faults. Se desarmó el rollback.
- Integración reproducible: `pmaports/extra-repos/systemd/xorg-server` contiene
  APKBUILD r10 + parche; `scripts/build-custom-xorg.sh` lo construye. El ZIP
  incluye el APK y un `ExecStartPre` de LightDM que lo instala localmente antes
  de arrancar X, por lo que funciona también sobre un rootfs/microSD limpio y
  actualiza correctamente la base de datos de `apk`.
- **v0.66 construida desde worktree kernel pristino**, `BUILD_EXIT=0`. ZIP:
  `artifacts/postmarketos-edge-xfce-mainline-v0.66-reverse-prime-sm-x910-twrp.zip`,
  29.420.384 bytes, SHA-256
  `f54322f0dbd5145f57f5c138d3e52ec09ff78b6a3a6991cf1c2a77ddc87b7466`.
  La auditoría ZIP verificó APK r10, config reverse PRIME, ambos drop-ins/hooks y
  CRC de todos los miembros. El ZIP no se flasheó: se mantiene la regla de que
  la usuaria ejecuta los ZIP TWRP.
- Validación final de equivalencia instalada tras reinicio normal completo:
  SSH volvió por WLAN en ~70 s; `lightdm`, `NetworkManager` y `sshd` activos;
  `wlan0=<TABLET_IP>`; Xorg r10; DSI-1-1 2960×1848@120; FD740 acelerado;
  Goodix registrado. La cámara confirmó XFCE y después geometría `glmark2` en
  la tablet central. No hubo GPU fault, hangcheck ni error DRM/DSI.

## 2026-07-22 — sesión 76: escalado integral y 120 Hz real

- Subir únicamente Xft DPI agrandaba el texto, pero no widgets/teclado, y al
  aplicar un escalado global tardío Slick Greeter se quedaba con la geometría
  provisional 320×200 del primary Adreno sin conectores. El resultado era un
  Onboard diminuto o recortado que impedía iniciar sesión.
- Configuración final: `/Gdk/WindowScalingFactor=2`, Xft DPI 96 (sin doble
  escalado), cursor 32, panel XFCE 36, iconos de escritorio 48 y Onboard de
  usuario con dock height 230. Para el greeter: `enable-hidpi=on`, `xft-dpi=192`
  y Onboard 420. `gts9uwifi-lightdm-hidpi` prepara dconf antes de LightDM.
- El hook reverse PRIME pasó de `ExecStartPost` a
  `display-setup-script=/usr/libexec/gts9uwifi-panel-reinit`: se ejecuta después
  de que X esté listo y antes de Slick Greeter, asocia providers, hace DSI
  off/on y fija 2960×1848@120 antes de que el teclado calcule su layout.
- PRIME Synchronization=1 limitaba Present/GLX a 27–30 FPS pese a 120 Hz.
  Desactivarlo en esta topología de buffers LINEAR importados elevó `glxgears`
  a 117–118 FPS. Se conserva DSI a 120 Hz. Pruebas visuales:
  `work/obs-tablet-final-full-ui-scale.png` y
  `work/obs-tablet-final-scale-coldboot.png`.

## 2026-07-22 — sesión 77: QUP SE14 y NVM Samsung desbloquean WCN7850 Bluetooth

- Se integraron built-in `CONFIG_BT`, BREDR/RFCOMM/BNEP/HIDP,
  `BT_HCIUART`, SERDEV, H4 y QCA. El DTS modela `&uart14`/`bluetooth` con rails
  y 3,2 Mbaud. v0.67 no creó el serdev porque faltaba activar su wrapper
  `&qupv3_id_1`; añadido en v0.68.
- En este Samsung el DTB efectivo lo entrega `vendor_boot`: escribir sólo
  `boot.img` no cambia el árbol. Tras actualizar ambos aparecieron `serial0-0`,
  `hci0` y el probe WCN7850.
- Firmware extraído del vendor stock: `hmtbtfw20.tlv`, `hmtnv20.bin` y variantes
  b21/b22/b38, con hashes fijados por `stage-stock-wifi-firmware.sh`. El NVM
  genérico falla al parsear el segmento TLV (`-52`). Una prueba en vivo por
  hot-rebind con `hmtnv20.b21` completó setup y anunció
  `BTFW.HAMILTON_C.2.0.1-00280-PATCHZ-1.52014.13`; por ello el DTS fija
  `firmware-name = "hmtnv20.b21"`.

## 2026-07-22 — sesión 78: v0.69 bootloop por colisión CPIO; v0.70 recupera el arranque

- `hci_qca` es built-in y sondea antes de montar la rootfs microSD. Se añadió
  soporte `INITRAMFS_OVERLAY_DIR` para concatenar patch+NVM al vendor ramdisk.
- **Fallo v0.69:** el overlay usaba `/lib/firmware/qca`. El initramfs base tiene
  `lib -> usr/lib`; la CPIO concatenada intentó crear el directorio `lib` encima
  del symlink y el equipo se reseteó antes de journald. TWRP no encontró journal
  del boot y `last_kmsg`/ABL sólo mostraban handoff y reset, pero al desempaquetar
  la CPIO se identificó la colisión exacta. v0.69 queda prohibida.
- **Arreglo v0.70:** firmware temprano en `/usr/lib/firmware/qca`, sin tocar el
  symlink. ZIP `postmarketos-edge-xfce-mainline-v0.70-hidpi-120hz-bluetooth-b21-sm-x910-twrp.zip`,
  SHA-256 `3c12a4fd5dab9b232f34ad4e42e0ef20a7e12cf2bf71e84d22409af264ab4908`.
  Se escribieron sólo boot/vendor_boot desde TWRP y el equipo arrancó; el primer
  probe descargó patch+b21 y terminó `QCA setup on UART is completed`.

## 2026-07-22 — sesión 79: dirección nativa de EFS y descubrimiento Bluetooth

- Aunque existían sysfs/debugfs/rfkill para `hci0`, BlueZ leía una lista vacía.
  `btmgmt config` dio la prueba definitiva: `Unconfigured controller`, opción
  soportada `public-address` y opción ausente `public-address`. No era una carrera
  D-Bus: el NVM Samsung deja la BD_ADDR nula.
- UFS expone `efs=/dev/sda6`. Se montó exclusivamente con `ro,noload`, se localizó
  `/bluetooth/bt_addr`, se validó su formato sin copiarla a fuentes y se desmontó.
  `btmgmt --index 0 public-addr` convirtió el índice en Primary inmediatamente.
- Arreglo reproducible: dependencia `bluez-btmgmt`, script
  `gts9uwifi-bluetooth-address`, unidad oneshot antes de `bluetooth.service` y
  drop-in Required/After. El script espera UFS/índice, monta EFS sólo lectura,
  aplica la dirección y es idempotente. Tras reinicio limpio la unidad terminó
  SUCCESS, `missing options` quedó vacío, BlueZ encendió el controlador y un
  escaneo de 12 s detectó múltiples dispositivos BR/EDR y BLE (incluido un TV,
  un PC, una báscula y un headset). Emparejamiento/perfiles quedan pendientes.

## 2026-07-22 — sesión 80: recuperación de LightDM y build limpia v0.71

- Después del reinicio Bluetooth, Slick Greeter entró en bucle con
  `Failed to write X authority ... No space left on device`. No era DSI/HiDPI:
  `mmcblk1p2` estaba al 100 % por dos directorios temporales propios,
  `/home/phablet/v067` (192,3 MiB) y `v068` (192,0 MiB). Se borraron únicamente
  esos staging dirs, recuperando 340,8 MiB (90 % usado). LightDM quedó activo y
  la cámara confirmó login completo, teclado 2× sin recorte; evidencia
  `work/obs-v070-bt-login-fixed.png`.
- Se corrigió además `gts9uwifi-install-xorg-package`: `apk info -v` en Alpine
  actual imprime metadatos, por lo que reinstalaba r10 en cada arranque de
  LightDM. Ahora `apk list -I` comprueba la versión; test vivo por timestamp:
  `XORG_INSTALLER_IDEMPOTENT=1`.
- Build limpia v0.71 desde worktree a13c140cc: kernel, DTB y módulos ath12k
  recompilados. El primer empaquetado falló sólo porque faltaba crear
  `/usr/lib/systemd/system`; añadido al `mkdir` y reempaquetado con los outputs
  de la misma build. `BUILD_EXIT=0`.
- ZIP final:
  `artifacts/postmarketos-edge-xfce-mainline-v0.71-hidpi-120hz-bluetooth-sm-x910-twrp.zip`,
  30.269.344 bytes, SHA-256
  `ec7b7480e2c20ad3a7b06d2f82d5653c8884fa325d1a83de637a259ed365405c`.
  Imágenes: boot `56e99c74a72642bbd3a22df34bd32c505e128680279d09c9382c568d0929b6ef`,
  vendor_boot `f57571ca7a37be9e48333aa52e92f9324aff0cbb35ac4dd18066f067d417349f`.
  El ZIP no se flasheó: la tablet mantiene v0.70 boot/vendor_boot y los cambios
  userspace v0.71 ya instalados/validados en vivo.

## 2026-07-22 — sesión 81: Bluetooth E2E validado y arreglo del blanking DPMS

- **Tarea 1 (Bluetooth de extremo a extremo) — CERRADA.** El controlador `hci0`
  es Primary con la dirección nativa `<TABLET_BT_ADDR>` (de EFS), BlueZ activo y
  el servicio de dirección `SUCCESS`. Los bonds **persisten**: `Buds2 Pro de
  <OWNER>` (<PAIRED_BT_ADDR>) y el `Galaxy S24 Ultra` seguían emparejados tras
  reinicios. Conectando los Buds2 Pro se creó el sink A2DP clásico
  `bluez_sink.<PAIRED_BT_ADDR>.a2dp_sink` (s16le 2ch 44100, perfil `a2dp_sink`,
  Default Sink). Reproducción validada: `ffmpeg -f pulse -device <sink>` con la
  pista de prueba dejó el sink RUNNING→IDLE, `rc=0`, sin errores; y la usuaria
  confirmó físicamente audio real reproduciendo un vídeo de YouTube en Chromium
  por los Buds. Servidor de sonido real = **PulseAudio 17.0** (paquete
  `postmarketos-base-ui-audio-backend-pulseaudio`); PipeWire/WirePlumber corren
  también pero PulseAudio maneja el audio (por eso `wpctl` mostraba 0 sinks).
  HID no probado por falta de un ratón/teclado BT; el perfil está soportado.
- **Tarea 2 (blanking/DPMS) — BUG ENCONTRADO Y ARREGLADO.** La pantalla se puso
  negra tras ~17 min de inactividad. Diagnóstico: `card1-DSI-1 dpms=Off`, `xset`
  con `Off: 1020`. El greeter SÍ tenía los cuatro timers Xorg a 0 (de
  `10-msm-dpu.conf`), pero al iniciar sesión **xfce4-power-manager** reactivaba
  el DPMS: `xfce4-power-manager.xml` tenía `dpms-on-ac-off = 17` (min = 1020 s).
  El ANA38407 **no resume de un blank DPMS**: ni `xset dpms force on`, ni el hook
  `gts9uwifi-panel-reinit`, ni un ciclo `xrandr off/on` manual relucen el OLED
  (leen `panel id 80 00 04` pero sigue negro); sólo un `systemctl restart
  lightdm` completo lo recupera (re-ejecuta el display-setup en el contexto de
  arranque). Confirmado que hay UN solo Xorg (pid 1295, tty7, `:0`, DRM master) y
  la sesión de usuario corre en ese mismo `:0`.
- **Arreglo reproducible:** el autostart `gts9uwifi-xfce-hidpi` ahora fija por
  `xfconf-query` `xfce4-power-manager/dpms-enabled=false` y todos los timeouts de
  blank/dpms a 0, y ejecuta `xset s off -dpms`. Replicado en `configs/` y en
  `pmaports/.../device-samsung-gts9uwifi/` (device r22, checksum actualizado).
  Verificado en vivo: iniciada la sesión de phablet (por autologin temporal,
  porque la usuaria estaba lejos), `xset -q` mostró `Standby/Suspend/Off = 0` y
  `DPMS is Disabled`; el escritorio XFCE 2960×1848 con cursor 2× se ve por cámara
  OBS. El panel ya **no se apaga por inactividad**.
- **Pendiente en Tarea 2:** el suspend/resume REAL del ANA38407 (que un
  DPMS/blank pueda re-encender el OLED) sigue sin resolver; la mitigación robusta
  es mantener el blanking deshabilitado. El autologin se activó SÓLO en vivo
  (`/etc/lightdm/lightdm.conf`, con `.bak-dpmscheck`), no está en la imagen
  reproducible; decidir si se quiere permanente.
- **Nota de audio interno (Tarea 3):** no hay tarjeta ALSA (`/proc/asound/cards`
  vacío); los configs `SND_SOC_QCOM/LPASS/...` están `=m` (sin autocargar) y falta
  todo el stack ADSP(q6/GPR)+soundwire+códecs WCD/WSA+LPASS+machine card. Bring-up
  grande. Botones (Tarea 3b): sólo el táctil Goodix en input; faltan `gpio-keys`
  y `pwrkey` (añadir nodos DTS; power vía PMIC PON, volumen vía resin/gpio).

## 2026-07-23 — sesión 82: audio interno paso 1 — el ADSP arranca y autentica en mainline

Objetivo: de-riesgar la Tarea 3 (audio interno) confirmando lo más incierto —
si el firmware del ADSP de Samsung es aceptado por el secure boot del SoC bajo
mainline (como NO ocurrió con la BDF RF de Wi-Fi). Resultado: **sí lo acepta**.

**Configs remoteproc PAS a `=y`** en `config-gts9uwifi.fragment` (este port no
autocarga módulos): `CONFIG_REMOTEPROC`, `QCOM_RPROC_COMMON`, `QCOM_Q6V5_COMMON`,
`QCOM_Q6V5_PAS`, `QCOM_SYSMON`, `QCOM_PDR_HELPERS`, `QCOM_PDR_MSG`,
`RPMSG_QCOM_GLINK_SMEM`. La build aborta si un símbolo no existe (red de
seguridad). Nota: `QCOM_PDR_HELPERS/MSG` bajan a `=m` porque dependen de
`QRTR=m` (un tristate no supera su dependencia `=m`, mismo patrón que LLCC/DRM_MSM
en la GPU). No bloquea el arranque del ADSP; queda para cuando haga falta PD
restart / QMI de audio.

**DTS `&remoteproc_adsp`** (label = `remoteproc@6800000`, compatible
`qcom,sm8550-adsp-pas`): `status = "okay"` + `firmware-name = "qcom/sm8550/adsp.mdt",
"qcom/sm8550/adsp_dtb.mdt"`. El segundo elemento (índice 1) es OBLIGATORIO: el
driver tiene `dtb_pas_id = 0x24`, así que en `qcom_pas_prepare` hace
`request_firmware(adsp_dtb)` y si falla `return ret` (fatal). El driver lee la
ruta del dtb de `firmware-name` índice 1; sin él usaría `desc->dtb_firmware_name
= "adsp_dtb.mdt"` SIN el prefijo `qcom/sm8550/`. Los carveouts ya existen
(`adspslpi_mem` redefinido a 9ea00000 en el board DTS; `q6_adsp_dtb_mem` a
9e980000 upstream).

**Firmware Samsung extraído de apnhlos** (`/dev/disk/by-partlabel/apnhlos`,
vfat, `/image/`): `adsp.mdt` (ELF32 QUALCOMM DSP6) + 48 segmentos `adsp.bNN`
(~33 MB; faltan b26/b29/b37/b50 = segmentos filesz=0 que el loader mdt salta) +
`adsp_dtb.mdt` + `adsp_dtb.b00..b02`. Empaquetados en
`firmware-samsung-gts9uwifi` r6 bajo `/usr/lib/firmware/qcom/sm8550/` (loop en
`package()`), y staged en el overlay de rootfs por `build-wifi-bringup.sh`. El
`adsp.mbn` de referencia de Qualcomm NO sirve (firma Qualcomm, rechazada por el
secure boot de Samsung); el `.mdt` de Samsung sí.

**DESCUBRIMIENTO CLAVE — el ABL del X910 usa el DTB de vendor_boot, no el
anexado en boot.img.** Primer intento: reflasheé sólo `boot` (sda21). El nodo
seguía `status=disabled` en `/proc/device-tree` pese a que el DTB construido
tenía el override (verificado por `dtc`). Como `adspslpi@9ea00000` ya estaba en
v0.70, no era prueba de DTB nuevo. Al reflashear `vendor_boot` (sda24, mismo
`--dtb`) el nodo pasó a `okay`. Corrección de un supuesto de sesiones previas:
para cambios de DTS hay que reflashear **vendor_boot**, no basta boot.

**Bloqueo de interconnect (elidido).** Con el nodo activo, el probe quedaba en
`-EPROBE_DEFER` perpetuo: `of_icc_get_by_index: invalid path=-517` →
`failed to acquire interconnect path`. El nodo vota BW sobre
`<&lpass_lpicx_noc MASTER_LPASS_PROC ... &mc_virt SLAVE_EBI1 ...>`. Ambos
extremos SÍ registran (`qxm_lpinoc_dsp_axim@7430000`, `ebi@interconnect-1`) y
la cadena lpicx→lpiaon→gemnoc→llcc→ebi existe, pero `path_find` no la conecta
(grafo desconectado; `lpass_ag_noc@7e40000` está `disabled` upstream). Un bind
manual a t=279 s seguía dando -517 → no es orden de probe. Solución de bring-up:
`/delete-property/ interconnects;` en el override. `qcom_q6v5_init` trata el path
NULL como válido (`devm_of_icc_get` devuelve NULL sin la propiedad,
`icc_set_bw(NULL,...)` es no-op). Restaurar un path real cuando se arregle el
grafo LPASS.

**PAS secure-boot OK.** Con el interconnect elidido, `remoteproc0` aparece como
`adsp` (offline). El `auto_boot` dispara a ~2 s y falla con `-ENOENT`: el
firmware de ~34 MB está en el rootfs de la microSD, aún sin montar. Tras montar
el rootfs, `echo start > .../state`:
`Booting fw image qcom/sm8550/adsp.mdt` → `remote processor adsp is now up` →
`Handover signaled`, `state=running`. **El ADSP de Samsung autentica y arranca
bajo mainline.**

**Service `gts9uwifi-adsp-boot`** (`configs/audio/`, oneshot,
`After=local-fs.target`, `ConditionPathExists=.../adsp.mdt`,
`WantedBy=multi-user.target`): busca el remoteproc `name=adsp` y hace el `start`
tardío. Instalado en vivo y validado tras reboot: a t≈19.6 s el service arranca
el ADSP sin acción manual (`adsp state now running`). Cableado también en
`build-wifi-bringup.sh` (symlink en `multi-user.target.wants`). Bluetooth sigue
intacto en v0.72 (descarga `hmtbtfw20.tlv`+`hmtnv20.b21`, HFP soportado).

Estado de la tablet: v0.72 boot+vendor_boot flasheados por UFS (backups v0.70 en
`/tmp` del device, volátiles; recuperación real = ZIP v0.71 + Download Mode).
`cpufreq` sigue sin icc paths (OSM_L3=m) — preexistente, no regresión. Pendiente
del audio real: GPR/q6apm/q6afe/q6prm + LPASS macros (rx/tx/wsa/va) + soundwire
(swr0/1/2) + WCD938x + WSA88x + machine sound card → tarjeta ALSA y PCM.

## 2026-07-23 — sesión 83: hardware de audio corregido y fuentes v0.73 preparadas

Se verificó primero la tablet v0.72 por SSH, comprobando la host key de la X910:
kernel `7.2.0-rc3-dirty #43`, ADSP `state=running`, escritorio/Wi-Fi/BT estables
y aún sin `/proc/asound/cards`. No se escribió ninguna partición UFS.

**Corrección importante del mapa de hardware.** El FDT oficial Samsung de la
SM-X910 no describe WCD938x ni WSA88x. La ruta de altavoces real consta de
cuatro amplificadores Cirrus **CS35L45** en el bus Samsung I2C18 (mainline
`i2c_hub_6`), direcciones `0x30..0x33`, con alimentación compartida en TLMM19,
reset activo alto en TLMM42 e IRQ compartida activa baja en TLMM14. Reciben
audio por `PRIMARY_MI2S_RX`: TLMM126=SCK, 129=WS, 127=data0 y 128=data1. Los
micrófonos internos son DMIC directos al VA macro mediante LPI 6/7, 8/9, 12/13
y 17/18. El FDT stock confirma además `qcom,wsa-max-devs=0` y
`qcom,wcd-disabled=1`; se elimina por tanto la anterior hipótesis WCD/WSA.

El kernel 7.2-rc3 fijado ya incluye el driver CS35L45, la machine AudioReach
SM8550 y los backends q6apm. Se añadió al DTS una tarjeta
`qcom,sm8550-sndcard` llamada `Samsung-Galaxy-Tab-S9-Ultra`, enlace playback
`PRIMARY_MI2S_RX` con los cuatro CS35L45, enlace capture
`TX_CODEC_DMA_TX_3` con `lpass_vamacro`, los cuatro códecs I2C y pinctrl
correspondiente. Los configs se hacen built-in, siguiendo la regla del port de
no autocargar el árbol genérico de módulos: `SOUND/SND/SND_SOC`,
`QCOM_APR`, `SND_SOC_QCOM/QDSP6/SC8280XP`, `SOUNDWIRE`,
`SND_SOC_CS35L45_I2C` y `SND_SOC_LPASS_VA_MACRO`. `QCOM_APR=y` seleccionará
también los helpers PDR necesarios; `QRTR` ya era built-in.

**Topología AudioReach.** La inicialización de q6apm construye la ruta
`qcom/<driver_name>/<card_name>-tplg.bin`. Para esta machine y este `model` el
nombre exacto es
`qcom/sm8550/Samsung-Galaxy-Tab-S9-Ultra-tplg.bin`. Se fijó la topología
oficial `qcom/sm8550/SM8550-HDK-tplg.bin` del repositorio linux-firmware,
commit `18cf97993f06c0a28d88cee30b7b646807642acd`, que ya contiene los grafos
PRIMARY_MI2S_RX, VA/TX3 y MultiMedia playback/capture. Se instala bajo el nombre
pedido por la tarjeta; SHA-512:
`d41185a9c905571f7c234ff8caf6e6d24870161a5e6ef0316bb997bfd26cee871a483287308a0af177d39a81b256def4cfa99b0f2594b364ba7ef1104dd9caca`.
El script `stage-audioreach-topology.sh` reproduce la extracción con commit y
hash fijados.

**Firmware de amplificadores.** Del archive oficial
`SM-X910_EUR_16_Opensource.zip` se extraen reproduciblemente
`cs35l45-dsp1-spk-prot.wmfw`, `cs35l45-dsp1-spk-prot.bin` y
`cs35l45-dsp1-spk-prot-calib.bin`. `stage-stock-audio-firmware.sh` verifica sus
SHA-512 antes de empaquetarlos en `firmware-samsung-gts9uwifi` r7. El kernel
package sube a r41. `build-wifi-bringup.sh` instala tanto estos blobs como la
topología en el rootfs.

**Botones preparados en la misma DTS, pero aún no validados:** power por el
PON de PMK8550, volumen-abajo por su resin y volumen-arriba mediante
`gpio-keys` en PM8550 GPIO6 activo bajo. Los drivers correspondientes se fuerzan
a built-in.

Se conserva `/delete-property/ interconnects` en `remoteproc_adsp`. No se
reactiva `lpass_ag_noc` en esta primera iteración porque la v0.72 demuestra que
el ADSP arranca sin el voto y habilitar ese proveedor causó bloqueos anteriores.
Primero se aislará tarjeta/PCM; sólo si el DMA evidencia falta de ancho de banda
se corregirá el grafo en una iteración separada.

Preparado `work/run-build-v073.sh` para generar
`postmarketos-edge-xfce-mainline-v0.73-internal-audio-buttons-sm-x910-twrp.zip`
desde un worktree limpio. Esta sesión Codex está aislada de la distro WSL
Ubuntu-24.04 registrada por la usuaria (`wsl.exe` no enumera distribuciones y
un import privado devuelve `E_ACCESSDENIED`), por lo que no puede ejecutar la
compilación pesada. Estado honesto al cierre: fuentes y scripts preparados,
checksums de APKBUILD actualizados y `git diff --check` limpio; **v0.73 todavía
no construida, no flasheada y audio/botones no validados**.

**Continuación de la sesión 83 — build ejecutada.** Una nueva ejecución Codex
sí obtuvo acceso a la distro registrada y ejecutó `work/run-build-v073.sh`.
Worktree limpio en `a13c140cc`; el DTS compiló y Kconfig conservó built-in los
componentes requeridos. El log muestra compilación real de `q6apm`,
`audioreach`, `q6prm`, `sc8280xp`, `lpass-va-macro`, `cs35l45-i2c`,
`gpio_keys` y `pm8941-pwrkey`; el kernel enlazó sin errores. Único aviso:
`ATH_COMMON=y` queda `=m`, comportamiento conocido y correcto para los dos
módulos ath12k aislados.

Resultado:

- `BUILD_EXIT=0`;
- Image.gz SHA-256
  `20a47686d3fd0133d4d78cdb3a84925c2804a483ef945ae0c475dc566f4bb4f2`;
- DTB SHA-256
  `c93e169df2cf24cfffb6766fa25bbf3ed84fab8ab070f20951d458d643926e05`;
- boot.img SHA-256
  `b6c8774aa53caecd529a0c065d2e273be62d201ac5000a90e71766c3dab82769`;
- vendor_boot.img SHA-256
  `c2cac59d0897fbb6b8e7eebd8df14c31b3b8c4d98b91cbe7cc0236dc85d396a7`;
- ZIP `postmarketos-edge-xfce-mainline-v0.73-internal-audio-buttons-sm-x910-twrp.zip`,
  48.385.837 bytes, SHA-256
  `b7ba04b56fdc7fb581839357340567c5c159a3a67a2ee7be0422d6207cfcfbd8`.

Inspección del ZIP confirma boot/vendor_boot, los tres blobs CS35L45, la
topología de 38.540 bytes bajo el nombre exacto de la tarjeta y el firmware
ADSP. Sigue **sin flashear**: por la política de seguridad hace falta
autorización explícita antes de escribir `sda21`/`sda24`. La tablet continúa en
v0.72; tarjeta ALSA, PCM, audio acústico y botones todavía no están validados.

## 2026-07-23 — sesión 84: v0.73 en vivo y causas raíz de los probes de audio

Con autorización explícita se escribió v0.73 por UFS únicamente en
`boot=/dev/sda21` y `vendor_boot=/dev/sda24`, después de respaldar ambas
particiones en `/tmp` y verificar SHA-256 origen=destino. El script terminó con
`V073_UFS_VERIFY_OK`. La tablet reinició correctamente con
`7.2.0-rc3-dirty #45`; Wi-Fi/SSH, LightDM, Bluetooth y el service del ADSP
siguen activos, y `remoteproc adsp` queda `running`. Por tanto no hay regresión
de arranque, pantalla ni conectividad.

El primer probe todavía no crea una tarjeta ALSA. `/proc/asound/cards` muestra
`--- no soundcards ---` y `devices_deferred` separa tres causas:

- `sound`: la machine `snd-sc8280xp` no encuentra el CPU DAI de q6apm;
- `6d44000.codec`: VA macro espera el proveedor pinctrl LPI de sus DMIC;
- `0-0030..0-0033`: cada CS35L45 aplaza al pedir su reset compartido.

**AudioReach/PDR.** GLINK e IPCC están vivos y remoteproc anuncia los canales
RPMsg `IPCRTR` y `adsp_apps`; este último enlaza correctamente con
`qcom,apr` y su `of_node` GPR. No aparecen dispositivos bajo el bus APR porque
los nodos q6apm/q6prm tienen `qcom,protection-domain`: APR espera que PDR
publique `avs/audio`. El config realmente compilado reveló
`CONFIG_QRTR_SMD=m`. Como el port no instala/autocarga el árbol general de
módulos, el canal `IPCRTR` carece de transporte y PDR nunca recibe el estado del
PD. Causa raíz: QRTR core y PDR estaban built-in, pero su transporte SMD no.

**VA macro.** El config construido contiene tanto
`CONFIG_PINCTRL_LPASS_LPI=m` como `CONFIG_PINCTRL_SM8550_LPASS_LPI=m`.
Por eso el nodo `pinctrl@6e80000` no registra el proveedor solicitado por
`dmic67-default-state` y VA macro queda aplazado. Es el patrón ya conocido de
clock/pinctrl controllers que upstream deja como módulo.

**Reset CS35L45.** Se descartó un error de FDT y también una línea reservada:
la propiedad viva es `<&tlmm 42 GPIO_ACTIVE_HIGH>`, phandle 0x69 apunta a
`pinctrl@f100000`, GPIO42 es válido, está en función GPIO, entrada baja y sin
pull, y coincide exactamente con el FDT Samsung. Una kretprobe sobre
`devm_gpiod_get_optional` midió `-517` en los cuatro probes. La traza completa
de gpiolib demostró que `of_get_named_gpiod_flags` sí encuentra el gpiochip y
traduce la línea a 42; el error nace después, en
`gpio_shared_add_proxy_lookup`. Linux 7.2 detecta automáticamente las cuatro
referencias a la misma línea y marca el descriptor `GPIOD_FLAG_SHARED`, pero
`CONFIG_GPIO_SHARED_PROXY=m`. Sin ese módulo, el proxy todavía no existe y la
petición se aplaza. No se debe cambiar el GPIO ni eliminar la envoltura de
reset compartido: hay que compilar el proxy.

La fuente v0.74 sube el kernel package a r42 y fuerza exclusivamente los
proveedores comprobados:

- `CONFIG_QRTR_SMD=y`;
- `CONFIG_PINCTRL_LPASS_LPI=y`;
- `CONFIG_PINCTRL_SM8550_LPASS_LPI=y`;
- `CONFIG_GPIO_SHARED_PROXY=y` (selecciona su `AUXILIARY_BUS`).

No cambia rutas de audio, interconnects ni el DTS. Se mantiene el interconnect
del ADSP elidido hasta alcanzar un PCM y observar una necesidad real de ancho
de banda. La build reproducible v0.74 se inició desde worktree limpio mediante
`work/run-build-v074.sh`; falta registrar aquí su resultado y validación viva.

**Botones en v0.73.** `gpio-keys` aparece como `event1`, confirmando que el
nodo de volumen-arriba y su driver enlazan. Los nodos PON de power/resin no
crearon dispositivos de input y se investigarán después de estabilizar el
audio. Conforme a la petición de la usuaria, la prueba física de botones se
solicitará sólo al final.

## 2026-07-24 — sesión 85: v0.74 elimina los defers iniciales, pero descubre dos bloqueos reales

La build reproducible v0.74 terminó con kernel `#46`; su ZIP es
`postmarketos-edge-xfce-mainline-v0.74-audio-probe-fixes-sm-x910-twrp.zip`
(SHA-256 `eb16ed8322728a623c785cefe69b939e1620cf3165e1e7d4b4a40ec2197551f0`)
y el `boot.img` es
`f72bbb3ef082399756968b6c042cc8dd3dc81ebea1c7a1ffbc967b20b5a9e02a`.
Con autorización vigente se escribió **sólo** `boot=/dev/sda21`: copia previa
en `/tmp/boot-v073-before-v074.img`, `dd conv=fsync` y SHA de los primeros 96
MiB igual al origen (`V074_BOOT_VERIFY_OK`). Tras reiniciar, SSH volvió por la
host key de la X910 y Wi-Fi, pantalla, BT, LightDM y ADSP `running` siguen sin
regresión.

El kernel vivo confirma `CONFIG_QRTR_SMD=y`,
`CONFIG_PINCTRL_LPASS_LPI=y`, `CONFIG_PINCTRL_SM8550_LPASS_LPI=y` y
`CONFIG_GPIO_SHARED_PROXY=y`. Los cuatro clientes I2C aparecen en
`0-0030..0-0033` y ya tienen driver `cs35l45`; esto confirma que el arreglo del
proxy compartido eliminó el `-EPROBE_DEFER` de GPIO42. No obstante,
`/proc/asound/cards` continúa vacío por dos bloqueos independientes:

1. `6e80000.pinctrl` permanece deferred con razón desconocida; el VA macro
   espera `dmic67-default-state`. El nodo LPI pide sus clocks a `q6prmcc`, pero
   no existe aún dispositivo q6prm bajo APR. Los drivers q6apm/q6prm están
   registrados, pero la protección de dominio sigue esperando que PDR publique
   `avs/audio`. Subir QRTR-SMD por sí solo no lo ha conseguido; la siguiente
   diagnosis debe inspeccionar el transporte QRTR/servreg y el camino PDR, no
   asumir que la causa ya está resuelta.
2. Los cuatro CS35L45 ahora llegan a inicializarse, pero vencen el sondeo de
   `CS35L45_IRQ1_EINT_4` con `Timeout waiting for OTP boot` (-110). La
   referencia Samsung confirma reset GPIO42 activo-alto compartido y el rail
   fixed `dummy_vreg` por GPIO19. El DTS mainline reproduce ambas señales como
   `speaker_vdd`; hay que contrastar de forma no destructiva el nivel real del
   rail/reset y las diferencias de secuencia del driver upstream frente al
   downstream. No cambiar todavía la polaridad ni retirar el reset sin una
   traza que lo justifique.

La machine `sound` permanece deferred porque su DAI CPU q6apm aún no existe;
no es una cuarta causa. Tampoco se reactivó el interconnect LPASS: ya causó
bloqueos históricos y aún no hay un PCM que demuestre necesitarlo. Botones y
la prueba acústica siguen aplazados hasta que aparezca una tarjeta ALSA.

## 2026-07-24 — sesión 86: v0.75 desbloquea AudioReach vía pd-mapper; el I2C de los CS35L45 sigue mudo

### Bloqueo 1 (PDR / `avs/audio`) — RESUELTO Y REPRODUCIBLE

La sesión 85 dejó abierto por qué no aparecía `q6prmcc` pese a `QRTR_SMD=y`. El
diagnóstico en vivo lo cerró: el transporte estaba **bien** — `qcom_smd_qrtr`
enlazado al canal `IPCRTR` y `qcom,apr` a `adsp_apps` — pero `/sys/bus/apr/devices`
estaba vacío y el log no daba ningún error: PDR esperaba en silencio. La causa es
que **nada en el kernel responde al servicio QMI *servreg locator***; ese servicio
lo provee el daemon de espacio de usuario **`pd-mapper`**, que no estaba instalado
(ni binario, ni proceso, ni unidad, ni paquete). Subir QRTR-SMD a built-in nunca
podía bastar; queda descartada esa vía.

Instalado `pd-mapper` (Alpine `pd-mapper-1.1-r0` + `pd-mapper-systemd`), fallaba
con `no pd maps available`. Un `strace` reveló su algoritmo real, que no son rutas
fijas: abre `/sys/class/remoteproc`, lee `remoteproc0/firmware`
(= `qcom/sm8550/adsp.mdt`), toma su **directorio** y busca ahí los `*.jsn`:

```
openat("/lib/firmware/postmarketos/qcom/sm8550") = -1 ENOENT
openat("/lib/firmware//qcom/sm8550")            = 4   (56 entradas)
getdents64 -> ningún .jsn -> "no pd maps available"
```

(Nótese que `firmware_class.path` vale `/lib/firmware/postmarketos`, que pd-mapper
prueba primero y descarta.) Colocar los mapas en `/lib/firmware/` o
`/lib/firmware/qcom/` NO sirve: deben ir **junto a `adsp.mdt`**.

Los mapas están en el apnhlos de Samsung: `adspr.jsn`, `adsps.jsn`, `adspua.jsn`
y `cdspr.jsn`. El decisivo es `adspua.jsn`, que declara
`sr_domain{domain:"adsp", subdomain:"audio_pd", qmi_instance_id:74}` y el servicio
`provider:"avs", service:"audio"` — exactamente el
`qcom,protection-domain = "avs/audio", "msm/adsp/audio_pd"` que llevan `service@1`
y `service@2` del nodo GPR.

Con los cuatro `.jsn` en `/usr/lib/firmware/qcom/sm8550/` y pd-mapper corriendo, la
cadena se desbloqueó en cascada:

- `qcom,apr ...: Adding APR/GPR dev: gprsvc:service:2:1` y `:2:2`;
- `6e80000.pinctrl` enlaza `qcom-sm8550-lpass-lpi-pinctrl` (ya tiene sus clocks de
  q6prmcc);
- `6d44000.codec` enlaza `va_macro`;
- `devices_deferred` pierde pinctrl y codec;
- la razón de `sound` cambia de «error getting cpu dai name» a
  **«codec dai not found»**: el CPU DAI de q6apm ya existe y sólo faltan los códecs.

Hecho reproducible en v0.75: los `.jsn` se empaquetan en
`firmware-samsung-gts9uwifi` r8 bajo `/usr/lib/firmware/qcom/sm8550/` y los instala
también `build-wifi-bringup.sh`; `pd-mapper` entra en los `depends` del paquete de
dispositivo; y un drop-in `configs/audio/10-gts9uwifi-adsp-order.conf` ordena
`pd-mapper.service` **después** de `gts9uwifi-adsp-boot.service`, porque pd-mapper
necesita el remoteproc arriba tanto para hallar los mapas como para tener a quién
servir (este port arranca el ADSP tarde, ya que auto_boot dispara antes de montar
la microSD). Validado tras reinicio: el desbloqueo persiste.

### Bloqueo 2 (CS35L45) — NO resuelto; causa acotada por eliminación

`Timeout waiting for OTP boot` (-110) en los cuatro amplificadores. Lo primero fue
descartar la lectura obvia: **el -110 no es el timeout del poll OTP sino del bus
I2C**. Un ftrace de `i2c`+`regmap` durante un bind muestra una única transacción y
su resultado:

```
regmap_hw_read_start: 0-0030 reg=e01c
i2c_write: i2c-0 a=030 l=4 [00-00-e0-1c]
i2c_read:  i2c-0 a=030 l=4
i2c_result: i2c-0 n=2 ret=-110      (1,017 s después)
```

Es decir, el chip no contesta en absoluto; el poll del OTP ni siquiera llega a
iterar. Ese -110 nace de `wait_for_completion_timeout` (XFER_TIMEOUT = 1 s).

Descartado con evidencia, para no repetirlo:

- **Bus equivocado — NO.** El DT stock sitúa los cuatro `cs35l45-*@30..33` dentro
  de `i2c@998000`, y `ext-dev-names = "cs35l45.18-0030..."` confirma que el I2C18
  de Samsung es ese controlador, o sea nuestro `i2c_hub_6`.
- **Reset mal manejado — NO.** Un ftrace de `gpio` durante el bind muestra
  `gpio 578 (tlmm42) set 0` → `direction out(0)` → `set 1` con los 2 ms de hold, y
  la primera transferencia 2,1 ms después. El gpio-shared-proxy funciona; al fallar
  el probe el driver vuelve a dejar reset a 0 (por eso un `i2cdetect` posterior
  siempre da `-- -- -- --`: no es información nueva).
- **Rail apagado — NO.** `tlmm19` está `out high` y `speaker_vdd` aparece
  `enabled`. El DT stock confirma que `dummy_vreg` (tlmm19, activo-alto) es la
  **única** alimentación declarada; no hay ningún LDO de audio/spk/amp ni en el
  stock ni en mainline.
- **Pinmux — NO.** `pin 8/9 -> device 998000.i2c function i2chub0_se6`; los
  `i2chub0_se6_l0/l1` del stock son la misma función hardware (func1) que mainline
  expone unificada.
- **IRQ no entregada — NO.** `/proc/interrupts` línea 154 (GICv3 502 = SPI 470,
  coincide con el DT) incrementa durante cada transferencia.
- **Relojes apagados — NO.** El `enable_cnt=0` de `gcc_qupv3_i2c_core_clk` y
  `gcc_qupv3_i2c_s6_clk` es sólo runtime-suspend; el trace muestra escrituras a
  `100000.clock-controller` inmediatamente antes de la transferencia.
- **Drive-strength — PROBADO Y NEGATIVO.** Único delta real hallado contra el
  stock: mainline pide `drive-strength = <2>` en `hub_i2c6_data_clk` mientras
  Samsung usa `<8>` en `qupv3_hub_i2c6_{sda,scl}_active`, con el bus a 1 MHz
  (Fast-Mode Plus). Se igualó al stock en v0.75 (override `&hub_i2c6_data_clk`) y
  el DTB lo lleva (`drive-strength = <0x08>`), pero **el síntoma es idéntico**. El
  cambio se conserva por fidelidad al stock, no como arreglo.

No se pudo usar dynamic debug (no compilado) para ver si el GENI reporta NACK
—el driver lo registra con `dev_dbg`— ni escribir pinconf en caliente
(`pinconf-config` no existe; sólo `pinmux-select` es escribible).

Pista para la próxima iteración: en el DT stock `gpio19` aparece además en estados
pinctrl junto a `gpio18` (líneas 5711/5716) y junto a `gpio14`+`gpio86`
(7407/7412), lo que sugiere una secuencia de pines de audio propia de Samsung que
mainline no reproduce. Conviene también contrastar si el bootloader deja los amps
en un estado que mainline altera, y probar un retardo post-reset mayor.

### Build, flasheo y estado

`work/run-build-v075.sh` desde worktree limpio: `BUILD_EXIT=0`, kernel r43,
firmware r8. ZIP
`postmarketos-edge-xfce-mainline-v0.75-pdmaps-i2c-drive-sm-x910-twrp.zip`
(48.404.071 bytes, SHA-256
`f7f9da8b138dbe8aa44f487f2c742e0cab248248a3b4b91c92145d71d59437da`);
Image.gz `570717a6…`, DTB `af51a856…`, boot.img `318d3431…`,
vendor_boot.img `0b47b3b7…`.

Como v0.75 sólo cambia el DTS, se escribió **únicamente** `vendor_boot=/dev/sda24`
(el ABL consume de ahí el DTB); `boot` sigue en v0.74. Backup previo en
`/tmp/vendor_boot-v074-before-v075.img`, `dd conv=fsync` y SHA origen=destino:
`V075_VENDORBOOT_VERIFY_OK`. Tras reiniciar, sin regresiones: Wi-Fi/SSH, LightDM,
Bluetooth, táctil y ADSP `running`; `pd-mapper` activo y el desbloqueo de la
cadena AudioReach persiste. `/proc/asound/cards` sigue vacío y `devices_deferred`
queda reducido a `sound` («codec dai not found») más el `17d91000.cpufreq`
preexistente (OSM_L3=m, no es regresión).

Sigue sin reactivarse el interconnect LPASS: no hay aún un PCM que demuestre
necesitarlo. Botones y prueba acústica continúan aplazados hasta que exista tarjeta
ALSA.

## 2026-07-24 — sesión 87: causa raíz del I2C de los CS35L45 = el GENI i2c-master-hub no clockea en modo PIO

Continuación del bloqueo 2. Objetivo: por qué los cuatro CS35L45 dan `-110` en
I2C. Se instrumentó el driver GENI (builds de diagnóstico v0.76–v0.79, sólo
`boot`) y se llegó a una causa raíz precisa. **No hay fix aún**; la tablet quedó
restaurada al v0.75 limpio (kernel r43, sin parches de diagnóstico), con el fix de
`pd-mapper` intacto (`va_macro` y el pinctrl LPI siguen enlazados).

**El `-110` es del bus, y el SE acepta el comando pero no conduce el bus.** Un
ftrace i2c+regmap ya mostró una única transacción `i2c_result ret=-110` (1,017 s =
`XFER_TIMEOUT = HZ`), sin NACK (`-ENXIO`) ni ARB_LOST (`-EAGAIN`). Promoviendo el
volcado de registros del driver (`geni_i2c_err`, que sólo usaba `dev_dbg`) a
`dev_err` en el camino `GENI_TIMEOUT`, el estado a mitad de cuelgue (capturado
ANTES del `geni_se_abort_m_cmd`) es:

- `geni_status = 0x41` = `M_GENI_CMD_ACTIVE` (comando aceptado, nunca termina);
- `m_irq_status = 0x0` (NINGÚN interrupt: ni `M_CMD_DONE` ni `M_GP_IRQ`);
- `geni_ios = 0x7` en el primer amp sobre bus limpio = **SDA=1, SCL=1, bus en
  reposo**: el maestro nunca condujo el bus. (Los amps 2-4 muestran `0x2` porque
  el abort del primero deja el bus contaminado.)

Un chip no puede dejar ambas líneas altas; por tanto es el **SE/maestro**, no el
esclavo. Descarta definitivamente la teoría de "chip presente que hace
clock-stretch".

**Firmware del SE presente e idéntico al bus que funciona.** `geni_se_read_proto`
(reg `FW_REVISION_RO`) da `proto=3` (GENI_SE_I2C) y `fw_rev=0x303` tanto en el bus
de los amps (998000) como en el del táctil (a90000). No es firmware del SE.

**La diferencia real: modo de transferencia.** `GENI_IF_DISABLE_RO`: táctil
`if_disable=0x1` → FIFO deshabilitado → usa **GPI DMA** (`gpi_mode=true`); amps
`if_disable=0x0` + el desc `i2c_master_hub` fuerza `no_dma` → **FIFO/PIO**. El bus
que funciona usa DMA; el que falla usa PIO. En PIO el secuenciador del SE necesita
que el reloj **core** del QUP esté corriendo.

**El reloj core del hub.** `gcc_qupv3_i2c_core_clk` y `gcc_qupv3_i2c_s_ahb_clk`
son `clk_branch` `BRANCH_HALT_VOTED` (enable_reg 0x52008, bits 8 y 7). En vivo,
DURANTE el cuelgue, ambos están `enable=1` pero **rate=0**, mientras `s6` (el SE)
sí va a 19,2 MHz. OJO: el bus del táctil (qup1) también tiene su
`gcc_qupv3_wrap1_core_clk` a rate=0 — pero funciona porque usa DMA, que no depende
del secuenciador PIO. El core lo gestiona `bcm_qup0` (keepalive, buswidth=4) vía
RPMh a partir del voto de interconnect `qup-core`.

**El voto de BW NO es el arreglo (probado y negativo).** Para el hub,
`geni_i2c_probe` sólo vota `GENI_DEFAULT_BW = Bps_to_icc(1000)` en core/config y
nada en DDR (`icc_ddr=NULL`). Se probó votar el core proporcional a la velocidad
(v0.78, `Bps_to_icc(1e6)`≈250 kHz de core): el PRIMER amp pasó a
`status=0x0`/`m_irq=0x1` (M_CMD_DONE, ¡el SE ejecutó!) aunque aún falló el OTP;
los otros tres siguieron atascados. Se subió el voto a ~600 MB/s (v0.79): **todos**
volvieron a `status=0x41`. Como el resultado no es monótono con la magnitud, el
"éxito" del primer amp en v0.78 se atribuye a **calor de arranque**: el ABL de
Samsung usa estos amps para el sonido de arranque y deja el core del QUP caliente;
la primera transacción de mainline lo aprovecha y luego decae. El voto de
`avg_bw` no controla de forma útil el rate del core aquí.

**Conclusión.** El SM8550 i2c-master-hub bajo mainline no ejecuta transacciones en
modo PIO: el reloj core del QUP-i2c no queda corriendo (sólo lo dejó el
bootloader, transitoriamente). Los buses que funcionan lo evitan usando GPI DMA,
opción no disponible para el hub (FIFO-only). El arreglo correcto es de
GCC/interconnect (hacer que el core del i2c-hub corra para PIO), no del DTS ni del
driver CS35L45. Pistas de continuación: (a) revisar cómo el downstream/otros SoC
SM8550 mainline con i2c-hub encienden el core (¿`assigned-clock-rates`,
`CLK_IS_CRITICAL`, un clock que falta en el wrapper `9c0000.geniqup`?); (b) probar
mantener el core vivo evitando el runtime-suspend del hub; (c) comparar el
`clk_summary` del core justo tras el ABL (caliente) vs tras un ciclo de suspend.

**No repetir (ya descartado con evidencia):** que sea el chip/OTP (el maestro no
conduce el bus), reset/polaridad, rail (`dummy_vreg`/tlmm19 es la única
alimentación también en el stock), pinmux, IRQ (línea 154 incrementa),
firmware del SE (proto=3), drive-strength (v0.75, sin efecto) y el voto de BW del
core (v0.78/v0.79, no monótono). Interconnect LPASS sigue sin reactivarse.

Estado reproducible sin cambios de código nuevos: v0.75 sigue siendo el artefacto
bueno (kernel r43, firmware r8, device r23; pd-mapper + mapas). Los parches
GENIDIAG/COREBWFIX fueron sólo de diagnóstico, viven únicamente en el worktree
caliente y no están en fuentes versionadas ni empaquetadas.

## 2026-07-24 — sesión 88: audio interno — ¡tarjeta ALSA! El i2c-hub a 400 kHz desbloquea los CS35L45

El bloqueo 2 (sesión 87) quedó como "el GENI i2c-master-hub no ejecuta en modo
PIO a 1 MHz". La pieza que faltaba se encontró comparando con los DTs upstream:
**todos** los boards SM8550 que ponen dispositivos reales en el i2c-hub lo corren a
≤400 kHz — `sm8550-hdk`/`mtp`/`qrd` (typec mux, por defecto) y sobre todo
`sm8550-sony-xperia-yodo-pdx234` (`i2c_hub_2` con un PMIC slg51000 a
`clock-frequency = <400000>`). Ninguno a 1 MHz. Nuestro DTS heredaba el 1 MHz del
stack downstream (que usa su propio driver del hub). El SE del hub en PIO/FIFO no
sostiene Fast-Mode-Plus bajo mainline.

**Fix (v0.80): `&i2c_hub_6 { clock-frequency = <400000>; }`** (antes 1000000).
Un único cambio de una línea en el DTS, respaldado por el board Sony. Resultado en
vivo tras flashear `vendor_boot` (sda24):

```
cs35l45 0-0030: Cirrus Logic CS35L45: REVID A0 OTPID 0B
cs35l45 0-0031..0033: idem
0 [SamsungGalaxyTa]: sm8550 - Samsung-Galaxy-Tab-S9-Ultra
```

- Los cuatro CS35L45 completan el OTP boot y reportan DEVID/REVID (antes: `-110`).
- Aparece la **tarjeta ALSA** `Samsung-Galaxy-Tab-S9-Ultra`, card 0:
  - playback: `MultiMedia1/2/6 Playback`;
  - capture: `MultiMedia3/4 Capture`.
- `amixer -c 0` expone los controles por amplificador (Front/Rear Left/Right):
  `AMP Enable`, `Amplifier Mode`, `DSP1 Firmware/Preload`, rutas `ASP_TX*`/`DSP_RX*`.
- `devices_deferred` ya sólo tiene `17d91000.cpufreq` (OSM_L3=m, preexistente); la
  machine `sound` ya NO está aplazada.
- Sin regresiones: NetworkManager/lightdm/bluetooth/pd-mapper/adsp-boot activos,
  ADSP `running`, y `pd-mapper` (bloqueo 1) sigue haciendo su trabajo.

Confirmado que los parches de diagnóstico GENIDIAG/COREBWFIX de las sesiones 86-87
NO están en la build (worktree limpio; `grep -c GENIDIAG` = 0). El cambio de código
reproducible desde v0.75 es únicamente el `clock-frequency` del DTS. Kernel r44.

Artefacto: `postmarketos-edge-xfce-mainline-v0.80-i2chub-400khz-sm-x910-twrp.zip`
(48.401.792 bytes, SHA-256
`648a86c097aa1298d4f8b3a6141634d6e0e5357da456fac4f76de35c374f2e35`);
vendor_boot.img SHA-256 `3b323593c399f0d8f7db67edbc3039b2c3e12054c30a9ed8c1ccab4e1b3c45d3`.
`boot` sigue en v0.75 (el cambio es sólo de DTS → sólo vendor_boot). Backup previo
en `/tmp/vendor_boot-v075-...` del device; `V080_VB_OK`.

**Aprendizaje clave (no repetir):** el timeout `-110` del i2c-hub bajo mainline se
resuelve corriendo el bus a ≤400 kHz, NO tocando el chip, el reset, el rail, el
drive-strength ni el voto de interconnect. La causa es el modo PIO del hub a FM+.

Pendiente para tener SONIDO real: montar la ruta ALSA (habilitar los amps, rutar
`MultiMedia1 Playback` → `PRIMARY_MI2S_RX` → CS35L45), cargar/gestionar el firmware
DSP de protección de altavoz de Cirrus (o modo passthrough), y UCM. Luego la prueba
acústica (altavoces captados por el micro de los cascos BT; micros de la tablet
grabando lo que suena en los cascos). Botones y sensores después.

## 2026-07-25 — sesión 89: la tarjeta ALSA no produce sonido; el fallo está en el puerto I2S del LPASS

**Corrección de la sesión 88.** Allí se afirmó que los altavoces sonaban basándose
sólo en el DAPM (`AMP: On`) y en que el PCM estaba `RUNNING`. **Era falso.** La
usuaria no oía nada y exigió verificación acústica propia; al medirla, los
altavoces están mudos. Queda como norma: **el DAPM no es prueba de audio; sólo
vale una medida acústica**.

### El instrumento de medida, primero

El método acordado (micro de los cascos junto a la tablet) falló dos veces por
causas del propio instrumento, y ambas se detectaron midiendo, no suponiendo:

1. El micro de los cascos estaba al **0 % de volumen** en Windows: entregaba
   silencio digital (-91 dB planos) mientras el micro del PC captaba ruido de sala
   normal (-76 dB). Corregido por la API de audio (`SetMicVolume.ps1`, ahora 100 %).
2. Aun al 100 %, el micro de los cascos entrega una señal **constante** de
   -56,70 dB (varianza ~0,01 dB entre ventanas) incluso reproduciendo un tono por
   los propios auriculares: **no capta**. El micro del PC (HD Audio) sí varía
   (-36,0…-36,3 dB con +40 dB de ganancia) y es el instrumento válido.

Con el micro del PC: **cero energía a 1 kHz en 22 s** (baseline -122 dB, sin una
sola ventana por encima), con el tono a amplitud 30000/32768 y los cuatro amps
habilitados. Los altavoces **no emiten**. Analizador propio por Goertzel en
ventanas de 0,5 s (`work/analyze-hda.sh`).

### Dónde está exactamente el fallo

La cadena digital está entera y verificada **leyendo el chip por I2C**, no por
DAPM: `DEVID=0x0035a460`, `GLOBAL_ENABLES=1`, `ASP_ENABLES1=0x00010000`
(ASP_RX1_EN), `BLOCK_ENABLES2=0x08000010` (ASP_EN), `GLOBAL_SAMPLE_RATE=0x03`
(48 kHz), `REFCLK_INPUT=0x370` (PLL para BCLK 1,536 MHz, habilitado). Sin fallos:
`IRQ1_EINT_1=0`.

Pero **`PLL_LOCK_FLAG` (bit 1 de `IRQ1_EINT_3`) nunca se activa**: el PLL del
amplificador jamás engancha ⇒ **no le llega bit clock**. Y la reproducción de un
tono de 16 s termina en ~4 s: el frontend se vacía sin *pacing* real, lo que
confirma que el puerto no marca reloj.

Del lado del SoC, en cambio, todo se **configura** bien (instrumentación
`I2SDIAG`/`TRIGDIAG` en `audioreach.c` y `q6apm-lpass-dais.c`, sólo diagnóstico):

```
I2SDIAG lpaif_type=0 intf_idx=0 sd_line=1 ws_src=1 rate=48000 width=16 ch=2
TRIGDIAG start dai=16 cmd=1 ret=0
```

es decir: interfaz PRIMARY, LPASS como maestro de WS/BCLK (`ws_src=1` = interno),
48 kHz/16 bits/2 canales, y el grafo del backend **arranca con éxito** (`ret=0`).
Los pines están muxeados (`pin 126→i2s0_sck`, `127→i2s0_data0`, `128→i2s0_data1`,
`129→i2s0_ws`). Y aun así el SoC **no conduce ninguna línea de datos**: muestreando
los pads durante la reproducción, `gpio127` alterna pero está en dirección
**entrada** (lo excitan los amplificadores con su feedback) y `gpio128` está
quieto y también como entrada.

### Hallazgo lateral: la línea SD de la topología

Del DT stock de Samsung: `tdm0_din` = **gpio127** = `i2s0_data0` (entrada al SoC,
feedback de los amps) y `tdm0_dout` = **gpio128** = `i2s0_data1` (salida del SoC =
playback). La topología del SM8550-HDK que reutilizamos fija el módulo I2S sink
con `sd_line = I2S_SD0 (1)` = gpio127, **la línea de entrada**. Lo correcto para
la X910 es `I2S_SD1 (2)` = gpio128.

Se probó: parche quirúrgico de **un solo byte** en el binario de topología
(offset 12513, token `AR_TKN_U32_MODULE_SD_LINE_IDX`=256 del único módulo
`MODULE_ID_I2S_SINK` en 12432), verificado con `cmp -l` (un byte, 1→2). Tras
reiniciar, `I2SDIAG` confirma `sd_line=2`… pero **sigue sin haber sonido ni reloj**
y `gpio128` sigue sin ser conducido. La corrección es coherente con el hardware,
pero por sí sola no basta; se **revirtió** para no versionar un blob modificado sin
validar. (Aviso: una primera versión del parche buscó el patrón de bytes sin
alinear y tocó 16 sitios; se restauró desde la copia pristina del overlay v0.80.)

### Descartado con evidencia en esta sesión (no repetir)

- **Falta `set_sysclk` en la machine driver — NO.** Se probó (v0.81) y **rompió**
  la apertura del PCM con `-ENOTSUPP`: q6apm no implementa `.set_sysclk`. En
  AudioReach el puerto lo programa el ADSP (`PARAM_ID_I2S_INTF_CFG`). Los boards
  de referencia (`qcom,qcs615-sndcard`, misma `sc8280xp.c`) usan MI2S sin pedir
  reloj.
- **Runtime PM / hibernación del amp — no es la causa** (aunque sí explica que el
  chip pierda registros cuando se suspende: con `power/control=on` los conserva).
- **Configuración del amp — no es la causa**: se escribió a mano por I2C la
  configuración completa (PLL, sample rate, ASP RX, GLOBAL_EN) y se verificó
  leyendo el chip; sigue sin sonar.
- **Módulo I2S ausente de la topología — no**: hay un `MODULE_ID_I2S_SINK` y el
  grafo arranca.

### Estado y siguiente paso

Cambio reproducible bueno de esta sesión: `set-mi2s-codec-dai-format.patch` para
`sc8280xp.c` — la machine driver fija el formato del **lado CPU** en MI2S pero
nunca el del códec, así que un códec I2S se quedaba con su default de reset;
ahora se le fija `CBC_CFC | I2S | NB_NF`. Es correcto y necesario, pero no es
suficiente para que haya sonido.

La tablet quedó **restaurada al estado limpio v0.80** (kernel commiteado sin
instrumentación, topología pristina): tarjeta ALSA presente, cuatro CS35L45
enlazados, Wi-Fi/pantalla/BT/ADSP y `pd-mapper` sin regresiones.

Siguiente hipótesis a atacar: el puerto MI2S del LPASS no se pone a generar reloj
pese a que el ADSP acepta la configuración y arranca el grafo. Líneas de trabajo:
(a) construir una **topología propia** para la X910 (la del HDK puede tener mal no
sólo la línea SD sino el `lpaif_type`/instancia LPAIF a la que están cableados los
pines TLMM i2s0); (b) comprobar si el LPASS necesita además reloj/pinctrl por la
vía LPI (`6e80000.pinctrl`) o relojes de `q6prmcc` para el puerto; (c) contrastar
con `qcs615`/talos-evk, que sí tiene MI2S funcionando con esta misma machine
driver, qué difiere en su topología.

## 2026-07-25 — sesión 90: AUDIO COMPLETO (altavoces, sistema, micrófono) y botones

Sesión larga y con varios diagnósticos falsos por el camino; lo que sigue es el
estado verificado físicamente por la usuaria y por medida.

### Altavoces — ✅ SUENAN

Hacían falta **dos cosas a la vez**, y por eso cada una por separado parecía no
servir:

1. **Topología: `sd_line` = `I2S_SD1` (2), no `I2S_SD0` (1).** El DT de Samsung
   nombra `tdm0_din` = gpio127 = `i2s0_data0` (entrada al SoC, feedback de los
   amplificadores) y `tdm0_dout` = gpio128 = `i2s0_data1` (**salida** = el
   playback). La topología del SM8550-HDK que reutilizamos apunta a SD0, que es
   la línea de entrada, así que el ADSP transmitía a ninguna parte. Confirmado
   comparando con **TALOS-EVK (qcs615)**, el único board de linux-firmware que
   usa MI2S de verdad con esta misma machine driver: su módulo I2S es
   token-por-token idéntico al nuestro **salvo `SD_LINE_IDX`, que vale 2**. Los
   SM8550/8650/8750 usan 1 porque su módulo I2S es un vestigio que no emplean.
   Reproducible: `stage-audioreach-topology.sh` descarga la del HDK (hash pinado,
   verificado), reapunta ese único token con un parche de **un byte** y verifica
   el hash resultante.
2. **La machine driver nunca configuraba el códec.** `sc8280xp_snd_init()` fija
   el formato del lado CPU en MI2S pero al códec no le decía nada: ni formato ni,
   sobre todo, **el bit clock al que enganchar su PLL**. Sin eso el CS35L45 no
   engancha y no saca audio. `set-mi2s-codec-dai-format.patch` añade en el
   startup de enlaces MI2S `snd_soc_dai_set_fmt(CBC_CFC|I2S|NB_NF)` **y**
   `snd_soc_dai_set_sysclk(codec_dai, 0, 1536000, SND_SOC_CLOCK_IN)`, que es lo
   que hace `cs35l45_asp_set_sysclk()` para programar el PLL. OJO: el sysclk va
   en el **códec**, no en el CPU DAI — probarlo en el CPU (v0.81) rompió la
   apertura del PCM con `-ENOTSUPP` porque q6apm no implementa `.set_sysclk`; en
   AudioReach el puerto lo programa el ADSP.
3. **Los amplificadores perdían la configuración al hibernar.**
   `cs35l45_runtime_suspend()` los hiberna y `cs35l45_set_pll()` sale antes de
   tiempo si la **caché** dice que el PLL ya está puesto; tras hibernar el chip
   vuelve con el PLL borrado pero la caché no, así que nunca se reprograma.
   Regla udev `90-gts9uwifi-cs35l45-no-hibernate.rules` los mantiene fuera de
   runtime suspend (en `/usr/lib/udev/rules.d`, que es el directorio que existe
   en este rootfs; `/etc/udev/rules.d` no).

### Audio de sistema — ✅

Sin UCM, PulseAudio veía una tarjeta que no sabía rutar y se quedaba en
`auto_null`: nada sonaba en las aplicaciones. El perfil propio
(`conf.d/sm8550/Samsung-Galaxy-Tab-S9-Ultra.conf` +
`Qualcomm/sm8550/GTS9U/HiFi.conf`) describe la ruta real (nada que ver con la del
HDK, que asume WSA/WCD) y con él PulseAudio expone
`alsa_output.platform-sound.HiFi__Speaker__sink` («Built-in speakers (4x
CS35L45)») y `..HiFi__Mic__source`. El volumen del escritorio funciona.

Ajustes de nivel: el volumen digital de cada amplificador estaba al 80 % =
**−10,75 dB**, de ahí que sonara bajo; se fija alto en el `BootSequence`, con
margen deliberado porque **no está cargado el firmware de protección de altavoces
de Cirrus** (upstream capa sus altavoces por el mismo motivo). Y se limita el
deslizador del panel a 100 % (`volume-max`), porque XFCE deja amplificar por
software por encima de 0 dB y eso satura.

### Micrófono — ✅ CAPTA

Tres causas encadenadas, todas de DT:

1. **Backend equivocado**: el enlace de captura apuntaba a `TX_CODEC_DMA_TX_3`
   (el carril del TX macro, de donde los boards de referencia sacan sus micros
   soundwire, que esta tablet no tiene). El VA macro tiene su propio carril DMA:
   **`VA_CODEC_DMA_TX_0`**. Con el equivocado, `arecord` daba `-EIO`.
2. **Sin reloj de DMIC**: faltaba `qcom,dmic-sample-rate`; el driver lo avisa
   (`dt entry missing`) y sin él no deriva el divisor. Puesto a `4800000`, como
   el resto de boards mainline con DMIC en el VA macro.
3. **Micrófonos sin alimentar**: el VA macro declara `vdd-micb` como
   `SND_SOC_DAPM_REGULATOR_SUPPLY` **pero no lo mete en ninguna ruta**, así que el
   widget nunca se enciende. Medido: el rail seguía con `use=0` con la captura
   corriendo y el pin de reloj DMIC estático. Samsung lo alimenta desde `ldob10`
   a 1,8 V → añadido `vreg_l10b_1p8` (mainline no lo define), enlazado como
   `vdd-micb-supply` y marcado `regulator-always-on` hasta que el driver lo rute.

Resultado medido con música de fondo: **−30,6 dBFS de media, pico 6307, ambos
canales vivos** (antes: cero absoluto, `peak=0`).

### Botones

- **vol+ / vol− ✅.** Sólo vol+ funcionaba porque va por `gpio-keys` (PM8550
  GPIO6, built-in). `pwrkey` y `resin` son **hijos** del nodo `pon@1300`, cuyo
  padre lo maneja `qcom-pon.c` (`POWER_RESET_QCOM_PON`), que estaba en `=m`: el
  mismo patrón que ya mordió a Wi-Fi, GPU, pinctrl LPI y el proxy de GPIO — este
  port no autocarga módulos. Built-in y aparecen `pmic_pwrkey`/`pmic_resin`.
- **power ✅.** El hardware siempre funcionó (contador de IRQ subiendo), pero
  `xfce4-power-manager` toma un inhibidor `block` de logind sobre la tecla y no
  tenía acción configurada, así que se la comía en silencio. Configurado a
  **suspender** (`power-button-action = 1`). Aviso: el valor 4 en XFCE 4.20
  resultó ser **apagado directo**, no el diálogo.

### Nota de método

La usuaria pidió expresamente que todo sea **replicable en builds**, no parches
sobre la instalación viva. Todo lo anterior está en fuentes versionadas: DTS,
fragment de config, parche del kernel (aplicado por `build-mainline-kernel.sh`),
`stage-audioreach-topology.sh`, `configs/audio/` (UCM + udev, instalados por
`build-wifi-bringup.sh`) y `configs/display-native/gts9uwifi-xfce-hidpi` (ajustes
xfconf). Kernel r46, firmware r9, device r24.

**Artefacto v0.90 (build limpia desde worktree pristino).** `BUILD_EXIT=0`.
Comprobaciones automáticas sobre lo que salió: `POWER_RESET_QCOM_PON=y`, el
parche del sysclk del códec aplicado, **cero restos de la instrumentación de
diagnóstico** (GENIDIAG/I2SDIAG a 0), i2c hub a 400 kHz, carril de captura del VA
macro, `qcom,dmic-sample-rate`, `vdd-micb-supply`, UCM y regla udev en el overlay,
y la topología con el hash del retarget a SD1 (`0c362136…`).

- ZIP `postmarketos-edge-xfce-mainline-v0.90-internal-audio-buttons-sm-x910-twrp.zip`,
  48.411.346 bytes, SHA-256
  `5fa93ad3f205cf26a28a20a6ec969f1f591c49c77549fb8d15a05d18a4bdc96f`
- boot.img SHA-256 `1e45072482b5502536bca30b0ad86752171d4bfbe52a26e2c6fef710e5df71f4`
- vendor_boot.img SHA-256 `5b14de5b678a69e0af4a6a9e6a92fdd95923fa550486f6962b55d1120eca5e96`

La tablet quedó corriendo los incrementales v0.88 (boot+vendor_boot), que son
funcionalmente equivalentes; v0.90 es el artefacto reproducible para reinstalar.

## Sesión 91 — pantalla en negro tras reinicio: rootfs al 100 %, no el panel

Síntoma reportado: la tablet se queda en negro tras el logo de Samsung, con el
guion parpadeando arriba a la izquierda. Parecía un fallo de arranque.

No lo era. El SSH respondía con normalidad (kernel `7.2.0-rc3-dirty`, uptime
normal), el panel se inicializaba bien (`ana38407 panel id: 80 00 04`), y
`card1-DSI-1` figuraba como `connected`. Lo que fallaba era la sesión gráfica:

    lightdm.service: Scheduled restart job, restart counter is at 236
    lightdm[1779]: Error writing X authority: Failed to write X authority
                   /home/phablet/.Xauthority: No space left on device

`/dev/mmcblk1p2` (3.6 G) estaba al **100 %, 0 bytes disponibles**. Cada arranque
de Xorg llegaba hasta reservar el framebuffer 2960x1848, la sesión no podía
escribir `~/.Xauthority`, salía con código 1 y systemd reiniciaba lightdm
indefinidamente cada ~3.5 s — de ahí el `panel id` repetido en dmesg cada 3.4 s,
que es la huella del ciclo de reinicio, no de un fallo del panel.

Qué había llenado el disco:

| ruta | tamaño |
|---|---|
| `/var/log/journal` | 778 MB (journal sin límite) |
| `/home/phablet/{v060,v065,rollback-v065}` | ~384 MB en boot/vendor_boot antiguos |
| `.cache/chromium` + `.config/chromium` | ~230 MB |

Arreglo aplicado (solo datos regenerables; las imágenes de rollback se
conservan como red de seguridad del usuario):

- `journalctl --vacuum-size=64M` → liberó 722 MB.
- Caché de Chromium borrada.
- Resultado: 80 % de uso, 702 MB libres; `NRestarts=0`, `xfce4-session` y
  `xfdesktop` vivos.

Verificación objetiva del escritorio, no solo del estado de systemd: captura de
la ventana raíz con `xwd` y análisis de píxeles → 2960x1848 bpp=24, 205 valores
distintos, 52 % de píxeles no negros. **El escritorio pinta.**

Reproducible: `configs/development-ssh/10-gts9uwifi-journal-cap.conf`
(`SystemMaxUse=64M`) instalado por `build-wifi-bringup.sh` en
`/etc/systemd/journald.conf.d/`, para que una sesión larga de depuración no
pueda repetir esto en una instalación nueva.

Pendiente de decisión de la usuaria: la partición raíz son solo 3.6 G. Ampliarla
implicaría reparticionar la microSD y no se ha tocado.


## Sesión 92 — batería y estado de carga: driver propio para el Silicon Mitus SM5714

**El camino Qualcomm está cerrado.** `pmic_glink` + `qcom_battmgr` es como
SM8550 reporta batería normalmente, pero `pmic_glink_adsp_data` exige el
dominio de protección `msm/adsp/charger_pd` vía PDR, y el firmware de Samsung
solo publica cuatro mapas: `adspr.jsn` (root_pd), `adsps.jsn` (sensor_pd),
`adspua.jsn` (audio_pd) y `cdspr.jsn`. Nada en `apnhlos` menciona `charger_pd`.
El DT stock lo confirma: usa `samsung,sec-battery`, `samsung,sm5714-charger` y
`samsung,sec-direct-charger`, todo desde el AP.

**Hardware real:** Silicon Mitus SM5714, un combo PMIC. Direcciones (de
`sm5714-private.h`): cargador `0x49`, fuel gauge `0x71`, MUIC `0x25`, y el
bloque USB-PD en `0x33`. Mainline no tiene NINGÚN driver para el SM5714 (solo
`extcon-sm5502` para sm5502/5504/5703), así que hay que escribirlo.

**Error de lectura del DT que costó una build (v0.89):** puse el chip en
`i2c_hub_9` (0x9a4000) porque en el volcado `sm5714@49` aparecía justo encima
de `i2c@9a4000`. Estaba en el nodo ANTERIOR. `i2cdetect` lo zanjó: en el bus de
hub_9 responde `0x33` — el bloque USB-PD, que en el DT stock SÍ cuelga de
9a4000 — y nada en 0x49. El chip está en **`i2c@9a0000` = `i2c_hub_8`**. Lección:
en un volcado plano, confirmar el nodo padre contando llaves, no por cercanía;
y `i2cdetect` sobre el bus resuelve la duda en un minuto.

**Driver** `sm5714_battery.c` (nuevo, en `drivers/power/supply/`, integrado como
el panel: `.c` versionado + Kconfig/Makefile parcheados por el APKBUILD y por
`build-mainline-kernel.sh`). Es deliberadamente **de solo lectura**: la carga ya
la gestiona el propio chip y el boot chain, y no merece la pena arriesgarse a
mal-programar un cargador en hardware real. Enlaza en 0x49 y crea un cliente
dummy para el fuel gauge en 0x71. Registra dos power supplies: `sm5714-battery`
y `sm5714-usb`.

Conversiones (del `sm5714_fuelgauge.c` downstream). El fuel gauge expone sus
medidas por una ventana SRAM: se escribe la dirección en `RADDR` (0x8c) y se lee
`RDATA` (0x8d), en registros de 16 bits:

| valor | SRAM | conversión |
|---|---|---|
| SOC | 0x00 | Q8.8 sin signo, `(raw*10)>>8` en 0,1 % |
| VBAT | 0x03 | offset 2700 mV, pasos de 10/109 mV |
| corriente | 0x05 | signo-magnitud, 1/2044 A, bit15 = descarga |
| temperatura | 0x07 | `((raw&0x7fff)*10*2989)>>11>>8` en 0,1 °C |
| OCV | 0x01 | `(raw*1000)>>11` mV |

**Bug propio detectado y corregido (v0.91).** Escribí los getters devolviendo el
valor o un errno en el mismo `int`, así que cualquier corriente NEGATIVA — es
decir, la batería descargando, el caso normal — se interpretaba como fallo de
E/S: `power_supply sm5714-battery: driver failed to report 'current_now'
property: -129000`. Corregido pasando el valor por puntero y reservando el
retorno para errores reales. Lo mismo aplicaba a la temperatura bajo cero.

**Validado en la tablet** (v0.91, kernel r47, solo se escribió `boot` porque el
DTS no cambió): `capacity=97%`, `status=Full`, `voltage_now=4,378 V`,
`current_now=+239 mA`, `temp=35,4 °C`, `sm5714-usb/online=1`. UPower expone
`battery_sm5714_battery` y `line_power_sm5714_usb`, con `state: fully-charged`,
`percentage: 97%` y estimación de autonomía. Sin líneas de error en dmesg.

**Los 45 W: NO, y se sabe por qué.** Leyendo los registros del cargador en vivo
(`i2cget -f -y 1 0x49`): `VBUSCNTL=0x44` da límite de entrada **1800 mA**,
`CHGCNTL2=0x86` da carga rápida 2093 mA, `STATUS1=0x01` (VBUS_POK),
`STATUS2=0x38` (CHG_ON + top-off). A 5 V eso son **~9 W**, o sea USB por
defecto sin negociar nada. Dos razones estructurales:

1. El DT stock declara para este cargador `battery,max_input_voltage = 9000 mV`
   y `max_input_current = 3000 mA`, o sea **27 W de techo** por esta vía.
2. Los 45 W reales van por `samsung,sec-direct-charger` (carga directa 2:1) y
   requieren negociar **PD PPS**, lo que necesita el bloque USB-PD del SM5714 en
   `0x33` de `i2c_hub_9`, sin driver en mainline. Por eso `i2c_hub_9` queda
   documentado en el DTS pero deshabilitado.

No se ha podido medir la potencia de pico de carga porque la tablet está al 97 %
y en top-off (entran ~250 mA, ~1 W). Para medirlo de verdad hay que repetir la
lectura con la batería baja.

## Sesión 94 — reinstalación completa desde firmware stock: verificada

Prueba end-to-end pedida por la usuaria: flashear firmware stock, arrancar One UI,
volver a TWRP y reinstalar el port desde cero para comprobar que nada se había
quedado dependiendo de ajustes en vivo.

**Artefacto:** `postmarketos-edge-xfce-mainline-v0.92-battery-sm-x910-twrp.zip`,
48.411.085 bytes, SHA-256
`f0a1d83b74d5cfef2caed373a48727290ab6c7485407078142c0e321c83c0ee2`.
Se construyó nuevo porque el ZIP más reciente (v0.90) era anterior al driver de
batería, al arreglo `i2c_hub_8` del DTS y al tope del journal. Verificado por
dentro antes de instalar: el DTB contiene `siliconmitus,sm5714`, `simple-battery`
y `9a0000`; el overlay trae las 10 piezas recientes; y el `Image.gz` dentro de
`boot.img` es exactamente el kernel r47 recién compilado.

**Comprobaciones previas en TWRP (solo lectura), que confirmaron dos predicciones:**

1. `vbmeta` conservaba **flags 2** (verity desactivado), así que el instalador lo
   preservó en vez de abortar. El riesgo identificado no se materializó.
2. **El rootfs de la microSD sobrevivió intacto al flasheo stock** (`postmarketOS
   edge`, 81 % usado): Odin escribe solo particiones UFS y la tarjeta es un
   dispositivo físico aparte. Confirmado que no hace falta reflashear la SD para
   reinstalar.

Instalación por `twrp install` vía adb. Arranque a SSH en **40 s**.

### Resultado: todo el hardware sigue funcionando

Pantalla 2960×1848@120 con el escritorio pintando (verificado con `xwd`: 128
valores distintos), `lightdm` con `NRestarts=0`, táctil Goodix, `pmic_pwrkey`,
`pmic_resin` y `gpio-keys`, `wlan0` con IP, ADSP `running`, `pd-mapper` vivo, UFS
enumerada, tope del journal aplicado, y la batería reportando correctamente.

Bluetooth: `hci0` Primary **powered**, dirección nativa de EFS
`<TABLET_BT_ADDR>`, y —dato interesante— **los bonds sobrevivieron al flasheo
stock**, porque viven en el rootfs de la microSD, no en la UFS.

Audio: los cuatro CS35L45 responden con DEVID `0x0035a460`, cuatro componentes
ASoC, la tarjeta `Samsung-Galaxy-Tab-S9-Ultra` con 6 PCMs, y el sink por defecto
del escritorio es `alsa_output.platform-sound.HiFi__Speaker__sink`.

### Tres falsos negativos de mi propio script de verificación

Merece la pena anotarlos porque los tres son trampas reutilizables:

1. **CS35L45 «0 de 4»** — leía `/sys/kernel/debug/asoc/components` sin `sudo`.
   Con permisos salen los cuatro.
2. **«sink de PulseAudio ausente»** y `Default Sink: auto_null` — ejecutar
   `pactl` por SSH **sin `XDG_RUNTIME_DIR`** no consulta el PulseAudio del
   escritorio, sino que arranca/consulta otra instancia distinta. El log lo
   delata: `Unable to autolaunch a dbus-daemon without a $DISPLAY for X11`.
   Con `XDG_RUNTIME_DIR=/run/user/10000` el sink correcto aparece.
3. **«bluetooth hci0 caído»** — `hciconfig` **ya no existe** en BlueZ 5. Hay que
   usar `btmgmt info`.

REGLA: un fallo en el script de verificación no es un fallo del sistema. Antes de
reportar una regresión, comprobar que la herramienta de medida es válida — el
mismo error que ya costó una sesión con el micro de los cascos.

`deferred probe pending: snd-sc8280xp: ... error getting cpu dai name` en t=27 s
es **transitorio y normal**: el ADSP sube a t=21 s y la tarjeta se registra
después. No es la regresión que parecía.

### Carga: evidencia concreta del techo de 9 W

Con el cargador conectado, la corriente oscila entre **+130 mA y −1075 mA** con
`status=Charging` y `VBUSCNTL=0x44` (límite de entrada 1800 mA). No es un bug del
driver: a 5 V el cargador da ~9 W y la tablet con la pantalla encendida a 40 °C
consume más, así que la batería complementa. Es la demostración práctica de que
**sin USB-PD no se puede cargar de forma fiable con la pantalla encendida**.

### Pendiente inmediato

El rootfs sigue al **86 %, 502 MB libres**. La microSD es de 29,72 GiB con
**27,3 GB sin particionar**. Esta prueba NO valida una instalación limpia: el
rootfs es el acumulado de muchas sesiones. Eso llega con el paso a GNOME +
tarjeta entera, donde el crecimiento debe leer el tamaño real del disco y no
codificar 32 GB.

## Sesión 96 — GNOME no arranca: gdm necesita systemd-userdbd, que Alpine no compila

Instalación limpia con GNOME sobre la microSD entera. Tres fallos encadenados,
dos míos y uno upstream.

### 1. GPT de respaldo obsoleta (mío)

Al estirar la partición con `sfdisk`, la GPT de respaldo quedó al final de los
29,7 GB. Escribir después una imagen de 5,5 GB pone una GPT primaria nueva pero
**no borra la de respaldo del final**. La tarjeta quedó con dos tablas
contradictorias y cada kernel resolvía una distinta: el del initramfs veía el
diseño de la imagen (p2 = 4,6 GB) y el de TWRP el antiguo (p2 = 29,2 GB). Los
sistemas de ficheros se leían en offsets equivocados: `invalid block`,
`gzip: invalid magic`, y arranque a la shell de depuración.

Perseguí durante un buen rato hipótesis falsas (tarjeta muerta, imagen corrupta,
lector defectuoso) porque comparaba hashes de regiones que cada kernel situaba
en sitios distintos. Descartadas con medidas: la tarjeta escribe y retiene bien
en dos zonas distintas, y la imagen pasa `e2fsck` limpio.

**REGLA:** antes de escribir una imagen pequeña sobre una tarjeta que tuvo
particiones mayores, `sgdisk --zap-all`. Y **verificar el hash de lo escrito
antes de reiniciar** — el paso que faltó y que habría ahorrado horas.

Escritura buena: `sgdisk --zap-all`, `adb push` de la imagen a `/tmp` (tmpfs de
7,1 GB), `dd` y `sha256sum` de los 5250 MiB escritos contra la imagen. Coincide.

### 2. El servicio de crecimiento rompía el arranque (mío)

`gts9uwifi-grow-rootfs` corría `Before=local-fs.target`. Reescribir la tabla de
particiones hace que udev retire y recree todos los dispositivos del disco —
justo mientras systemd esperaba `/dev/disk/by-uuid/…` de la partición de
arranque:

    16:52:24.903  Expecting device /dev/disk/by-uuid/b645a225-…
    16:52:25.673  gts9uwifi-grow-rootfs: growing partition 2 …
    16:53:53.316  Timed out waiting for device
                  local-fs.target: Job failed with result 'dependency'

`graphical.target`: **cero menciones**. La pantalla negra parecía mutter
fallando con la topología GPU/DPU partida y no lo era: GNOME no llegó a
ejecutarse. Arreglado moviendo la unidad a `After=local-fs.target` /
`WantedBy=multi-user.target` y añadiendo `udevadm settle`. ext4 redimensiona en
caliente, así que no había nada que ganar ejecutándolo pronto.

**El crecimiento en sí FUNCIONA**: 4,6 GB → 29,2 GB, sistema de ficheros de 28 G
al 7 %, sin nada hardcodeado, verificado en hardware.

### 3. gdm no puede arrancar (upstream, no nuestro)

Con lo anterior resuelto el sistema llega a `multi-user.target`, `sshd` responde
y **gnome-shell llega a ejecutarse e inicializa KMS**
(`Added device '/dev/dri/card0' (msm)`, `KMS thread`). Pero gdm entra en bucle;
este par de mensajes aparece **75.120 veces** en un journal de 240 MB:

    Gdm: Failed to allocate UID for greeter: User 'gdm-greeter-2'
         not preallocated and system lacks userdb
    Gdm: GdmDisplay: Session never registered, failing
    → gdm.service: Failed with result 'core-dump'

Causa comprobada en el rootfs: **systemd 261.2-r0 de Alpine no incluye
`systemd-userdbd`** — no existe el binario `/usr/lib/systemd/systemd-userdbd`,
ni unidad, ni `userdbctl`. GDM 50 (`999950.0-r5`) lo necesita para el usuario
dinámico del greeter. No es habilitable: no está.

Segundo problema, independiente y menor: **falta el firmware de la GPU**
(`a740_sqe.fw`, error -40, y `MESA: get-param failed! -6`). Lo instala el
**overlay del ZIP**, no el paquete de dispositivo, y una instalación limpia de
tarjeta no lo recibe. Recordatorio: instalar la imagen del rootfs es SIEMPRE de
dos pasos — tarjeta + ZIP.

### Acceso a una instalación limpia

Un rootfs recién instalado no tiene ni Wi-Fi ni `authorized_keys`, así que no
hay SSH. Canales usados esta sesión, por orden de utilidad:

- **TWRP + adb**: el más fiable; monta la tarjeta y permite leer journals.
- **Consola serie por USB**: sólo la ofrece la *shell de depuración del
  initramfs* (COM6 a 115200). `setup_usb_storage_configfs` reconfigura el gadget
  y **se lleva por delante el puerto serie** — no ejecutarlo si es tu único
  canal.
- **IPv6 link-local sobre RNDIS**: el sistema real expone RNDIS; el vecino
  `fe80::…%<idx>` responde a ping y `sshd` contesta, aunque sin DHCP. Windows
  necesita asignar a mano el driver *Remote NDIS Compatible Device*.

## Sesión 97 — ✅ GNOME FUNCIONANDO, confirmado por la usuaria

Escritorio GNOME sobre Wayland en la Tab S9 Ultra, con **todo lo anterior
intacto**: Wi-Fi, Bluetooth, audio, botones, batería, GPU y brillo. La usuaria
confirma que el escalado se pone solo al **200 % y se ve perfecto**.

### La causa del bloqueo, sacada del binario

`strings /usr/sbin/gdm` da el mecanismo exacto. GDM ≥ 47 tiene un
`GdmDynamicUserStore` (`../daemon/gdm-dynamic-user-store.c`) que necesita una
cuenta por pantalla llamada **`gdm-greeter-<N>`** (formato `%s-%lu`) y la
resuelve por dos vías:

1. `getpwnam()` — si la cuenta existe ya, es *preallocated* y la usa.
2. Si no, pide a **`systemd-userdbd`** que la cree al vuelo.

**Alpine compila systemd sin `userdbd`** (systemd 261.2-r0: sin binario
`/usr/lib/systemd/systemd-userdbd`, sin unidad, sin `userdbctl`; ningún paquete
de pmOS/Alpine lo provee, comprobado contra los cuatro índices). Y el
`.pre-install` del paquete gdm sólo crea `gdm-greeter` **sin número**, que nunca
es el nombre que GDM busca. Resultado: `User 'gdm-greeter-2' not preallocated
and system lacks userdb` en bucle — 75.120 veces en un journal de 240 MB — y
`gdm.service: Failed with result 'core-dump'`.

**Arreglo:** pre-crear las cuentas numeradas, que es exactamente lo que espera
la vía 1. Diez cuentas `gdm-greeter-1..10` con UID/GID en **61184-65519**, el
rango que systemd reserva para usuarios dinámicos, así que no colisionan con
nada de Alpine. Home en `/var/lib/gdm-greeter-N`: GDM aborta explícitamente si
el home está en `/home` o en la raíz (`Dynamic user home '%s' is in /home or is
root! Aborting.`). Reproducible en el paquete de dispositivo r27:
`gts9uwifi-gdm-greeter-users` + unidad oneshot `Before=display-manager.service`
con `ConditionPathExists=/usr/sbin/gdm`, así que las imágenes XFCE la ignoran.

Bug propio por el camino: la primera versión del script topaba la búsqueda de
IDs libres en 1000 y devolvía siempre el mismo, dejando UID duplicados del 5 al
10. Lo cazó la comprobación de duplicados del propio script.

### Segundo problema: firmware de GPU ausente

`adreno 3d00000.gpu: failed to load a740_sqe.fw` (-40) y `MESA: get-param
failed! -6`. El firmware del Adreno lo instala el **overlay del ZIP**, no el
paquete de dispositivo, y una tarjeta recién escrita no lo tiene. Tras aplicar
el ZIP: `loaded qcom/a740_sqe.fw` y `loaded qcom/gmu_gen70200.bin`.

**Instalar este port son SIEMPRE dos pasos: tarjeta + ZIP.** Documentado en el
README.

### Hallazgo importante: mutter no necesita reverse PRIME

    gnome-shell: Added device '/dev/dri/card0' (msm) using non-atomic mode setting
    gnome-shell: Added device '/dev/dri/card1' (msm-kms) using atomic mode setting
    gnome-shell: Created gbm renderer for '/dev/dri/card0'
    gnome-shell: Created gbm renderer for '/dev/dri/card1'

**Mutter maneja la topología GPU/DPU partida por sí solo**, abriendo las dos
tarjetas. Todo el andamiaje de X11 (paquete Xorg parcheado r10,
`--setprovideroutputsource`, el hook de LightDM) es innecesario en Wayland. Era
el riesgo que más me preocupaba y resultó ser lo más sencillo.

### Estado

`systemctl is-system-running` = **degraded** por tres unidades inocuas:
`proc-sys-fs-binfmt_misc` (módulo no compilado) y `nftables.service` (sin
reglas). No afectan a nada; pendientes de limpiar si molestan.

Tablet en `<TABLET_IP>`, conectada sola por el perfil Wi-Fi escrito en la
tarjeta. Disco: 28,3 G al 12 %.

## Sesión 98 — brillo arreglado; el panel negro en frío sigue abierto

### ✅ Brillo: un solo barrido

El deslizador recorría el panel de oscuro a brillante **dos veces**. El driver
declaraba `max_brightness = 4095` (12 bits) pero **DCS 0x51 lleva 11 bits
significativos** en este DDIC: la propia secuencia de encendido de Samsung
programa `0x51, 0x07, 0xff` = `0x07FF` = 2047 como brillo máximo, y cualquier
valor con el bit 11 puesto vuelve al fondo del rango. Con `max_brightness =
0x07ff` queda un barrido único. **Verificado en la tablet.**

### 🔴 Pantalla negra en arranque en frío: NO resuelto

Síntomas reportados: negra tras el logo hasta pulsar el power varias veces; al
suspender, también hacen falta 2-3 pulsaciones; y a veces artefactos en los
primeros instantes.

**Señal fiable encontrada:** en arranque en frío el DDIC responde `00 00 00`;
tras un suspender/reanudar responde `80 00 04`. Medido repetidamente.

**Cuatro hipótesis probadas y DESCARTADAS** (no repetir):

1. **Reintentar la secuencia de encendido conmutando el reset** — sigue
   `00 00 00` en los tres intentos.
2. **Ciclo completo de alimentación del panel** (apagar los cuatro raíles 50 ms
   y volver a subirlos, imitando unprepare/prepare) — sigue `00 00 00`.
3. **Secuenciar los raíles como el fabricante**: el DT stock
   (`dsi_panel_pwr_supply`) define `vddio` → `qcom,supply-post-on-sleep = 0x14`
   (20 ms) → `vdd` → `vci`, y nuestro driver encendía los cuatro a la vez con
   `regulator_bulk_enable` y dormía **después** — el orden opuesto. **El cambio
   es objetivamente correcto y se ha dejado**, pero NO arregla ninguno de los
   síntomas: ni el arranque en frío, ni las pulsaciones múltiples, ni los
   artefactos.
4. **Apaño por RTC** (`rtcwake -m mem -s 5` al arrancar, para forzar el ciclo
   sin tocar el botón) — inviable: `Lockdown: hibernation is restricted` y,
   sobre todo, **no hay dispositivo RTC** (`/dev/rtc*` y `/sys/class/rtc/`
   vacíos), así que no existe fuente de despertado por reloj.

**Dato que descarta una pista falsa:** la ausencia de pingüinos y de texto de
arranque NO es síntoma del panel muerto, es configuración. El bootloader de
Samsung añade `console=null` **después** de nuestro `console=ttyMSM0` en la
línea de comandos, y la última gana.

**Dato sobre las pulsaciones múltiples:** con una sola pulsación medida por SSH,
el sistema **sí despierta** (`PM: suspend exit`), el panel lee `80 00 04`, el
conector queda `enabled` y el backlight encendido. Es decir, el wakeup funciona;
lo que falla es que la imagen no aparece. Sospecha razonable: cada pulsación de
más vuelve a suspender, así que la percepción de "no responde" se realimenta.

**Dónde está el problema, con la evidencia actual:** lo único que hace el resume
y no hace el arranque es **reinicializar el host DSI y la PHY desde cero**, en
vez de heredar el estado que dejó el bootloader tras pintar su logo. Eso está en
`msm_dsi`/`dsi_phy`, no en el driver del panel. Siguiente paso para quien lo
retome: comparar el camino de `probe`/primer `enable` con el de resume dentro
del host DSI, buscando qué reset de PHY se omite en frío.

## Sesión 99 — el flag de dominios no es la causa; ciclo explícito de MDSS preparado

Se recuperó el acceso a la X910 por SSH tras el experimento fallido de
`unbind`/`bind`. La identidad se confirmó con la clave de desarrollo exclusiva
del dispositivo: hostname `gts9u`, postmarketOS edge, kernel
`7.2.0-rc3-dirty #74`. La host key cambió después de la reinstalación limpia,
pero no se confundió con los otros equipos pmOS de la LAN.

### Medida de partida

En un arranque frío, antes de provocar ningún suspend:

- `msm_dpu` enlaza `ae94000.dsi` y registra `card1`;
- las tres lecturas DCS devuelven `Invalid response cmd`;
- el DDIC da `00 00 00`;
- GDM está activo, el conector figura `connected/enabled` y el backlight está
  encendido;
- una sola transición `PM: suspend entry (deep)` → `PM: suspend exit` cambia
  inmediatamente la lectura a `80 00 04`.

El código upstream aclara una imprecisión del diagnóstico anterior:
`msm_mdss_reset()` se llama únicamente desde `msm_mdss_init()` durante probe.
El resume profundo no vuelve a invocarlo. Lo exclusivo del suspend es:
`drm_mode_config_helper_suspend()` desmonta atómicamente el pipeline, los
callbacks runtime de DPU/DSI/PHY lo apagan y genpd puede colapsar el
`MDSS_GDSC`; el resume recorre el camino inverso.

### v0.99: retirar `pd_ignore_unused` — negativo

Se construyó una variante de empaquetado que conservaba el kernel y el overlay
validados de v0.92 y retiraba **solo** `pd_ignore_unused` del cmdline de
`vendor_boot`. Se escribió exclusivamente `/dev/sda24`, con backup y
verificación:

- anterior/backup:
  `c8373ce42c0658c21a4ef9138cf320cfcfd801932401b3d0cbee7659b1f8e262`;
- v0.99 escrita:
  `a50807b337b5bbcd9de4130faaa8552e7087085e1e7f1acc321ec5e5738bcce3`.

El arranque confirmó que el flag estaba ausente, pero el DDIC volvió a dar
`00 00 00`. Hipótesis descartada. El apagado de dominios sin consumidores se
produce demasiado tarde: MDSS ya está reclamado por el display. Se restauró el
backup v0.92 y se verificó su hash antes de reiniciar.

### v1.00: ciclo runtime PM del padre antes de crear los hijos — preparada

La siguiente prueba sí reproduce la diferencia estructural sin tocar MMIO ni
desmontar un display activo:

1. una propiedad opt-in `qcom,initial-power-cycle` solo en el nodo `&mdss` del
   X910;
2. `msm_mdss` hace `pm_runtime_resume_and_get()` seguido de
   `pm_runtime_put_sync_suspend()` antes de `of_platform_populate()`;
3. así genpd puede llevar `MDSS_GDSC` a off antes de que existan DPU, DSI y PHY;
   el primer runtime-get de los hijos debe reconstruir la jerarquía desde un
   estado conocido.

Queda reproducible en
`power-cycle-mdss-before-populating-children.patch`, DTS y kernel r49. Build
completa v1.00 con `BUILD_EXIT=0`; el DTB contiene la propiedad y DRM/MSM y el
panel siguen built-in. Artefacto:
`postmarketos-edge-gnome-mainline-v1.00-mdss-initial-power-cycle-sm-x910-twrp.zip`,
SHA-256
`35b8b74061592f7bf555751ec132ccc1e9c1d4a4e67cf562b6298cf9a950ccba`.

Validación en hardware: se escribieron solo `boot` y `vendor_boot`, con backup
y hash antes y después. El kernel nuevo `#75` arrancó, GDM y SSH subieron, y el
cmdline/DTS eran los esperados. Resultado: otra vez tres
`msm_dsi_host_cmd_rx:Invalid response cmd` y DDIC `00 00 00`. Por tanto, un
colapso del padre **antes** de construir el pipeline tampoco reproduce el
resume. Se restauraron ambas imágenes anteriores y sus hashes se verificaron.
El parche y la propiedad se retiran de la siguiente revisión; no repetir.

### Siguiente instrumento: `pm_test=devices`

El kernel r48 no expone `/sys/power/pm_test` porque `CONFIG_PM_DEBUG` está
deshabilitado. Activarlo proporciona el nivel `devices`: al escribir
`devices` y solicitar `mem`, el núcleo ejecuta los callbacks completos de
suspend/resume de los dispositivos y vuelve automáticamente tras unos
segundos, sin RTC ni pulsación física. Es la prueba más directa de la secuencia
que falta, con DRM ya construido.

En paralelo se prepara recuperar el diagnóstico visual. ABL añade
`console=null` después del vendor cmdline; por eso no hay verbose ni pingüinos,
independientemente del fallo del DDIC. La siguiente build añade un parámetro
opt-in `ignore_console_null`, vuelve a declarar `console=tty0` y conserva la
consola serie. El comportamiento estándar de printk no cambia sin ese
parámetro.

## Sesión 100 — ✅ recuperación automática del panel antes de GDM

### v1.01: consola restaurada e instrumento PM disponible

Kernel r50 (`#76`) con `CONFIG_PM_DEBUG=y`; `PM_SLEEP_DEBUG` queda seleccionado
automáticamente. El cmdline declara `console=tty0 console=ttyMSM0` y
`ignore_console_null`; el pequeño parche de printk hace que el
`console=null` que ABL añade después sea un no-op solo cuando se pide
explícitamente.

Validación:

- `/sys/class/tty/console/active` = `tty0 ttyMSM0`;
- `/proc/consoles` marca ambas como enabled;
- no aparece `ttynull`;
- `/sys/power/pm_test` ofrece `core processors platform devices freezer`.

Que aun así no se vieran pingüinos ni verbose no fue un fallo de esta parte:
el panel seguía con ID `00 00 00`, así que ninguna consola podía hacer visible
su framebuffer. El sistema, audio y botones estaban activos detrás de la
pantalla negra, tal como observó la usuaria desde el principio.

### La frontera exacta: `devices` falla, `platform` funciona

Pruebas en arranque frío, sin pulsar power:

1. `pm_test=devices` volvió solo después de la espera interna de cinco segundos,
   pero las tres lecturas DCS siguieron fallando y el ID quedó `00 00 00`.
2. Tras otro arranque frío, `pm_test=platform` volvió solo en ocho segundos y
   la primera lectura del panel fue **`80 00 04`**.

Por tanto no basta con suspender los drivers. La fase mínima que repara el
handoff de Samsung incluye los callbacks de plataforma, pero no necesita
desconectar CPUs, entrar en el core suspend real, RTC ni wake físico.

### v1.02: servicio reproducible

Se añadió `gts9uwifi-panel-coldboot-recover` y su unidad systemd al paquete de
dispositivo r28, a `configs/display-native/` y al overlay del ZIP:

- `After=local-fs.target`;
- `Before=display-manager.service`;
- espera dos segundos;
- selecciona `platform`, escribe `mem`, vuelve automáticamente y restaura
  siempre `pm_test=none`;
- solo se ejecuta si existe `/sys/power/pm_test`.

Primer arranque automático medido:

```text
19:00:39  panel id: 00 00 00
19:00:44  recovery: running the automatic platform suspend/resume cycle
19:00:57  recovery: platform cycle returned
19:00:57  panel id: 80 00 04
19:00:57  PM: suspend exit
```

La unidad terminó `Result=success`, `ExecMainStatus=0`; después arrancó GDM. Al
final: `pm_test=[none]`, DSI `enabled`, backlight activo, Wi-Fi/SSH operativo.
El arreglo ya no depende de una modificación manual de la instalación: está en
el paquete y en el ZIP v1.02.

**Confirmación física final de la usuaria:** en el siguiente arranque la
pantalla se encendió sola, sin pulsar power. El display vuelve a figurar como
✅ en el README.

## Sesión 101 — SSC/ADSP: aparecen los sensores reales del X910

El bring-up se hizo sobre el mismo ADSP ya usado por audio, pero arrancando su
protección `sensorspd` mediante FastRPC. El primer bloqueo seguía el patrón
repetido de este port: `CONFIG_QCOM_FASTRPC=m` no sirve porque no se instala ni
autocarga el árbol genérico de módulos. Al pasarlo a `=y` apareció
`/dev/fastrpc-adsp` y `hexagonrpcd` pudo adjuntar `INIT_ATTACH_SNS`.

El árbol HexagonFS se genera reproduciblemente con
`stage-stock-sensor-hexagonfs.sh`: copia la configuración Samsung, ejecuta
`sscregistrygen -p MTP -s 519`, fija la identidad del SoC que mainline no
publica con las rutas Android y añade únicamente los skels del DSP cuyos hashes
están fijados. No incorpora `persist`, calibraciones por dispositivo ni blobs
al repositorio. El servicio usa una variante empaquetada de `hexagonrpcd`
0.4.0-r4 que implementa las escrituras mínimas de registro que espera el
firmware Samsung, siempre confinadas al directorio de la microSD.

Dos detalles de placa fueron necesarios:

- los raíles stock de sensores PM8550B L1=1,8 V y L16=3,0 V quedan votados
  mientras no exista soporte de suministros auxiliares en q6v5 PAS;
- el `remoteproc_adsp` selecciona el pinctrl stock de los hubs I²C SE3/SE4,
  pero los controladores GENI del AP permanecen deshabilitados. Activarlos
  entregaba los buses a Linux y el SE3 veía el SM5440, pero ninguno de los
  STK31610 respondía: SSC, no el AP, es el propietario correcto.

La publicación es lenta. El QMI aparece antes de que termine el descubrimiento
de registro/hardware y un iio-sensor-proxy arrancado demasiado pronto sale con
`No sensors`. `gts9uwifi-wait-sensor-proxy` espera una medida real de
acelerómetro antes de iniciarlo. Tras suspensión profunda, sensorspd se detiene
y libssc 0.4.4 no reconecta el cliente QMI existente; un hook posterior vuelve
a arrancar la protección, espera SSC y reinicia SensorProxy.

Medidas reales, no solo atributos:

- acelerómetro LSM6DSO con muestras continuas;
- giroscopio con valores que cambian al mover la tablet;
- magnetómetro AK0991x y brújula con rumbo real (aproximadamente 140° en una
  de las pruebas).

## Sesión 102 — Hall de la funda y política de suspensión

El FDT Samsung identifica el Hall principal de la funda en TLMM GPIO107,
activo bajo y con debounce de 50 ms. Se añadió al `gpio-keys` ya usado por
volumen como un interruptor estándar `SW_LID`, con wakeup. Los eventos de
cierre y apertura se midieron repetidamente en el dispositivo y la usuaria
confirmó que cerrar la tapa puede apagar/suspender la tablet.

La aparente intermitencia de los cierres siguientes tenía una causa en
userspace: logind aplica por defecto `HoldoffTimeoutSec=30`, pensado para
descubrir bases/docks durante el arranque o resume. En una tablet con un Hall
directo solo descarta cierres válidos. La política de placa fija el holdoff a
cero y aplica `HandleLidSwitch=suspend` también con alimentación externa,
docked y en el greeter. El helper de display ya existente vuelve a encender el
panel después del resume. Falta todavía repetir físicamente suficientes ciclos
en el greeter para dar por totalmente estable el despertar al abrir; por eso
la funda queda 🟡, no ✅.

## Sesión 103 — autorrotación GNOME: dos carreras de Mutter y matriz X910

iio-sensor-proxy 3.9-r3 publica ahora la actualización completa de propiedades
cuando termina el descubrimiento lento de SSC. Sin ella GNOME cacheaba
`HasAccelerometer=false` y nunca sabía que debía reclamar el sensor.

Mutter 50.2-r4 corrige tres problemas observados:

1. `meta_orientation_manager_uninhibit_tracking()` podía decrementar el
   contador desde cero cuando el panel ya estaba gestionado, dejándolo
   negativo y sin volver a sincronizar la reclamación D-Bus.
2. Después de suspender, un nuevo owner de SensorProxy no puede heredar la
   reclamación del proceso anterior; se reinician los estados cacheados para
   emitir un `ClaimAccelerometer` real.
3. Si el sensor aparece después de que el panel integrado ya esté gestionado,
   la ruta de compatibilidad de la primera orientación añadía un inhibidor
   sintético que nunca tendría una transición posterior capaz de retirarlo.
   El síntoma exacto era girar una vez y quedarse bloqueado. Esa ruta se
   conserva únicamente cuando el panel sigue sin gestionar.

Con lo anterior la rotación era continua, pero todas las posiciones estaban
desplazadas 90° a la derecha. El registro SSC entrega una matriz nula y libssc
cae correctamente a identidad. Una regla de placa aplica a
`fastrpc-adsp` la matriz empírica
`0,1,0;-1,0,0;0,0,1` en la segunda etapa de iio-sensor-proxy.

**Confirmación física de la usuaria:** la tablet ya gira correctamente en todas
las posiciones. Esta matriz queda validada y no debe sustituirse por una
deducción teórica de los JSON stock.

## Sesión 104 — ALS STK31610: servicio visible, pero sin muestras

SSC descubre exactamente un SUID `ambient_light`, nombre `stk_stk31610`,
fabricante Sensortek, rango anunciado 5 Hz y estado available. GNOME ve
`HasAmbientLight=true`, pero `LightLevel` permanece en 0 lux y el brillo no
cambia al tapar físicamente el sensor ni al apagar la luz de la habitación.

Se probaron y descartaron:

- petición normal `on-change`;
- registro `is_dri=1` y modo de polling `is_dri=0`;
- seleccionar otro SUID (solo existe uno);
- una variante diagnóstica de libssc que fuerza la petición continua estándar
  de 5 Hz. El DSP aceptó la configuración QMI pero no envió ninguna indicación
  de medida durante 30 segundos.

Para descartar que `sscregistrygen` hubiese perdido datos, se montó la
partición `persist` **solo lectura con `ro,noload`**, se copió fuera de Git su
registro de sensores y se desmontó. El registro nativo contiene 148 ficheros y
el generado 136; los 12 ausentes son exclusivamente tablas dinámicas de
calibración del giroscopio. Todos los ficheros STK31610 están presentes y sus
únicas diferencias son la representación JSON equivalente `1`/`1.0` y
`5000`/`5000.0`. Copiar `persist` no arreglaría el ALS y además rompería la
separación de calibraciones privadas.

La variante diagnóstica de libssc fue retirada y el dispositivo volvió a
`libssc=0.4.4-r0`. El brillo automático queda pendiente por debajo de GNOME,
iio-sensor-proxy y el formato del registro. `proximity` devuelve
`Unable to initialize ... UNKNOWN`; la configuración Samsung del X910 no crea
un hijo proximity para el STK31610, así que no se anuncia como hardware
disponible.

### Consolidación v1.07

La build limpia v1.07 terminó con `BUILD_EXIT=0` y validación dirigida
`V107_VALIDATION_OK`. El overlay contiene la matriz, la política de funda, los
hooks de resume y solo los paquetes de producción; no contiene ningún APK
libssc diagnóstico. Hashes:

- `Image.gz`:
  `85d4b60f7814e24087948411de541c4ec9811bb5d1c2ea61b6cd9b449f7b8294`;
- DTB:
  `e89bf016e1040416cc84f910ad83cdd7110a720b54d0d39c0531685da7d3dec8`;
- `boot.img`:
  `c7ccbc8a3a1e290142b07b70e15a566e1899ca38d325d16864063710f9147a82`;
- `vendor_boot.img`:
  `ce3bd326c2de4444177141b4e5a742f55840ae0f8904856469a9002f431de380`;
- ZIP de 51.762.561 bytes:
  `postmarketos-edge-gnome-mainline-v1.07-sensors-autorotation-lid-sm-x910-twrp.zip`,
  SHA-256
  `548b4bfe714e2624a83fe6694bbe9f8de24a898fab77fed82d3ac71a6039f6e0`.

Con la autorización permanente limitada a `boot` y `vendor_boot`, se
respaldaron ambas particiones, se comprobaron las rutas exactas
`sda21`/`sda24`, se escribieron con `conv=fsync` y la lectura posterior
coincidió con los hashes anteriores. El overlay reproducible se aplicó a la
microSD y el equipo reinició por sí solo.

Validación en vivo de v1.07, kernel `#81`:

- GDM, NetworkManager, SSH, sensorspd e iio-sensor-proxy activos;
- el ciclo de panel cambió `00 00 00` a `80 00 04` antes de GDM;
- FastRPC + SSC listos tras dos intentos y acelerómetro con medidas reales;
- pinctrl SE3/SE4 reclamado por `6800000.remoteproc`;
- matriz udev efectiva
  `ACCEL_MOUNT_MATRIX=0,1,0;-1,0,0;0,0,1`;
- logind efectivo con `HandleLidSwitch=suspend` y `HoldoffTimeoutSec=0`;
- `gpio-keys` expone `SW=1`;
- paquetes de producción: hexagonrpcd r4, iio-sensor-proxy r3, Mutter r4 y
  libssc oficial r0.

La rotación correcta ya estaba confirmada físicamente por la usuaria con esta
misma regla. Falta solo repetir el despertar al abrir la funda después de esta
consolidación para subir su estado de 🟡 a ✅.

## Sesión 105 — v1.08: carrera de wake y `DISPLAY_ON` diferido

### Evidencia física recibida

La usuaria confirmó que cerrar la funda suspende de forma consistente tanto
en el greeter como dentro de la sesión. La apertura todavía fallaba a veces,
especialmente al abrir antes de 2–3 segundos. También aparecían ocasionalmente
artefactos al despertar con la funda o con power.

La fotografía `20260727_140432.jpg` muestra ruido cromático en casi toda la
superficie, pero la barra superior de GNOME permanece legible. Por tanto la
GPU/composición no estaba muerta: el patrón apunta al contenido de GRAM o al
flujo DSC de comando desincronizado durante el encendido del DDIC.

### El Hall no pierde la apertura; el wake gráfico sí tenía una carrera

El journal de v1.07 contiene aperturas rápidas correctamente recibidas. Un
caso extremo:

```text
[10601.344] PM: suspend entry (deep)
[10601.470] Lid opened.
[10603.572] PM: suspend exit
[10604.008] ana38407 panel id: 80 00 04
```

El problema medido estaba después: el hook creaba un timer anónimo con
`systemd-run --on-active=1s`, pero algunas ejecuciones llegaron 7–16 segundos
después. En secuencias rápidas quedaron wakes del ciclo anterior activos
durante el cierre siguiente; se observan dos helpers simultáneos y prepares
adicionales.

El hook reproducible usa ahora `gts9uwifi-display-wake.service`. En `pre`
detiene la unidad (incluido su `ExecStartPre=/bin/sleep 1`) y en `post` la
reinicia sin bloquear. Así solo la reanudación más reciente puede solicitar
`PowerSaveMode=0`.

### Respeto de `samsung,delayed-display-on`

El FDT stock del X910 declara explícitamente `samsung,delayed-display-on`.
Hasta v1.07 el driver enviaba `0x29 DISPLAY_ON` al final de `.prepare`, antes
de que la cadena DRM llegase a `.enable`. Se separó el ciclo igual que en
paneles Samsung DSC mainline:

- `.prepare`: alimentación, reset, secuencia rev-D, TE y PPS;
- `.enable`: `DISPLAY_ON`, después de que DPU/DSI estén preparados;
- `.disable`: `DISPLAY_OFF`;
- `.unprepare`: sleep-in y apagado.

La pausa stock previa a display-on también pasa de 50 a 100 ms. El objeto del
panel compila aislado y la compilación completa desde worktree limpio terminó
con `BUILD_EXIT=0`.

### Build e instalación

Paquetes: kernel r54 y dispositivo r36. La validación real terminó con
`V108_VALIDATION_OK`, incluido CRC del ZIP:

- `Image.gz`: `706363f2eef47e767b38f4b1961c85a834434269216133c33011257b95941e95`;
- DTB sin cambios:
  `e89bf016e1040416cc84f910ad83cdd7110a720b54d0d39c0531685da7d3dec8`;
- `boot.img`: `8b12cde37b0610d09017d41a866e69f2fa4b3e0e5c24a307826166dc2199279a`;
- ZIP `postmarketos-edge-gnome-mainline-v1.08-panel-resume-lid-sm-x910-twrp.zip`:
  `19d79d44f693d5991acac15f07e513823f4418598c5ba650679dcf0c772b4c32`.

Con la autorización permanente se escribió únicamente `boot` (`sda21`), tras
backup y verificación, y se aplicó el overlay a la microSD. `vendor_boot` no
se tocó porque el DTB no cambió. En vivo:

- kernel `7.2.0-rc3-dirty #82`;
- hash leído de `sda21` idéntico al origen;
- recuperación fría automática `00 00 00 → 80 00 04`;
- GDM, NetworkManager y SSH activos;
- un ciclo `pm_test=platform` posterior produjo una sola lectura
  `80 00 04`, un único servicio wake y ningún timer residual.

El SSH se interrumpió durante la prueba porque WLAN se suspende y reapareció
automáticamente después; no fue una caída del sistema. Los artefactos y las
aperturas rápidas quedan pendientes de confirmación física antes de marcar
display/funda como ✅.

## Sesión 106 — v1.09: recuperación SSC serializada tras resume

### Validación física final de v1.08

La usuaria confirmó que ya no aparecen los artefactos cromáticos, que cerrar
la funda suspende de forma consistente y que abrirla vuelve a encender el
panel. El intervalo visible de 2–3 segundos no es una pérdida del evento Hall:
coincide con la duración medida del `PM: suspend exit`, la reanudación de DRM y
el segundo de margen del compositor. Display, suspend y funda pasan a ✅.

### Regresión de rotación y causa raíz

Durante las pruebas repetidas de tapa desaparecieron la autorrotación y su
control de GNOME. No era una regresión de Mutter ni de la matriz. La evidencia
en vivo fue:

- `iio-sensor-proxy` inactivo y sin owner D-Bus;
- `ssccli` devolvía `SSC QMI Service not found`;
- la unidad inicial había agotado sus 45 intentos;
- el journal contenía muchas unidades
  `gts9uwifi-sensors-resume-<timestamp>` simultáneas;
- dos de ellas intentaron arrancar sensorspd mientras `suspend.target` lo
  estaba deteniendo y fallaron con `Transaction ... is destructive`;
- las restantes reiniciaron repetidamente sensorspd y agotaron sus ventanas
  de descubrimiento.

El hook de sensores repetía el mismo antipatrón que se había eliminado del
wake gráfico: un `systemd-run --on-active=2s` anónimo por cada resume. La
apertura y cierre rápidos permitían que sobreviviesen varios a la vez.

### Arreglo reproducible

El paquete de dispositivo r37 convierte
`gts9uwifi-wait-sensor-proxy.service` en la única unidad de recuperación:

- el hook `pre` la detiene, cancelando también su espera o descubrimiento;
- el hook `post` reinicia esa misma unidad sin bloquear;
- la unidad arranca después de
  `gts9uwifi-panel-coldboot-recover.service` y antes del display manager;
- `gts9uwifi-sensors-resume` reinicia, no solo arranca, sensorspd, porque una
  protección marcada `active` puede conservar un cliente FastRPC/QMI obsoleto
  tras una prueba PM.

Tras instalar exactamente esos ficheros desde las fuentes y reiniciar:

- la recuperación fría del panel terminó a 29,8 s;
- sensorspd se reinició de forma limpia a 35,2 s;
- SSC entregó una medida real al primer intento a 37,1 s;
- SensorProxy publicó `HasAccelerometer=true`;
- GDM, NetworkManager, SSH, sensorspd e iio-sensor-proxy quedaron activos;
- no existía ninguna unidad transitoria antigua.

Un ciclo adicional `pm_test=platform` volvió con una sola recuperación, SSC
listo al primer intento y ningún conflicto. Un segundo suspend solicitado solo
un segundo después fue correctamente rechazado por systemd con `Action suspend
already in progress`; el script de prueba dejó temporalmente `pm_test=platform`
al abortar, se corrigió inmediatamente a `[none]` y se verificó el estado. Esto
también acota por qué una apertura física necesita unos segundos.

### Build v1.09

El kernel y el DTB no cambian respecto a v1.08; se reutilizaron byte a byte y
se regeneraron el overlay, bundle y ZIP. La validación dirigida terminó con
`V109_VALIDATION_OK`, incluido CRC:

- `Image.gz`:
  `706363f2eef47e767b38f4b1961c85a834434269216133c33011257b95941e95`;
- DTB:
  `e89bf016e1040416cc84f910ad83cdd7110a720b54d0d39c0531685da7d3dec8`;
- `boot.img`:
  `8b12cde37b0610d09017d41a866e69f2fa4b3e0e5c24a307826166dc2199279a`;
- `vendor_boot.img`:
  `809fb3fb62ca99bff4bbc2e2069140e02b3800a7dafcb0edf2b828897d14493e`;
- ZIP
  `postmarketos-edge-gnome-mainline-v1.09-sensor-resume-sm-x910-twrp.zip`:
  `e7afb90084b248e9091279b015177098dd9c5dc39adfecd5b58e5322b4c12ce6`.

La instalación viva ya contiene los mismos tres ficheros del overlay; no fue
necesario escribir ninguna partición UFS. El ZIP queda para instalaciones
limpias y para reproducir el estado completo.

**Confirmación física final:** tras el reinicio volvió a aparecer el control
de bloqueo de rotación y GNOME autorrota correctamente en todas las posiciones.
La regresión queda cerrada.

## Sesión 107 — diagnóstico físico del STK31610

### Peticiones estándar y registro descartados

SSC descubre dos instancias Sensortek `stk_stk31610`, `ambient_light` y
`ambient_light_sub`, con buses de registro 3/4 y dirección `0x48`. Ninguna
entrega una muestra con on-change, continuo a 5 Hz, polling forzado o DRI. Los
ficheros STK31610 extraídos de `persist` en solo lectura y los generados desde
la configuración Samsung son semánticamente iguales; las únicas ausencias de
la caché generada son calibraciones de giroscopio ajenas al ALS.

Se reprodujo además la prueba física exacta de Samsung, deducida del binario
`factory.ssc`: mensaje SSC 10 y protobuf `08 04` (tipo de prueba 4). Tanto el
sensor principal como el secundario aceptan la petición QMI, pero no publican
el evento de resultado. El `adsp_dtb` autenticado solo contiene datos de
batería/USB-PD de la plataforma Qualcomm y no describe la topología de
sensores.

### Experimento negativo v1.10 y rollback

El downstream Samsung asocia `sensor_vdd`/`sensor_vddio` del ADSP a PM8550B L1
y L16. Se preparó una prueba reproducible que quitaba `regulator-always-on` y
dejaba que PAS votase esos raíles durante la vida del remoteproc. La primera
compilación falló por un encabezado de diff manual mal contado y se corrigió
antes de generar imágenes.

La v1.10 válida produjo kernel `#83`, boot
`1c3f7c1f…`, vendor_boot `d0530d6d…` y ZIP SHA-256 `a0db69dc…`. Tras escribir
solo boot/vendor_boot con backup y verificación, los raíles aparecieron
habilitados a 1,8/3,0 V con un consumidor, pero el servicio QMI SSC completo
dejó de publicarse aunque el ADSP figuraba `running`. No había por tanto
acelerómetro, rotación ni ALS. Se restauraron y verificaron inmediatamente las
imágenes estables:

- boot `8b12cde37b0610d09017d41a866e69f2fa4b3e0e5c24a307826166dc2199279a`;
- vendor_boot `ce3bd326c2de4444177141b4e5a742f55840ae0f8904856469a9002f431de380`.

El parche v1.10 se retiró por completo de las fuentes. Los raíles de sensores
deben seguir `always-on`; no repetir esta hipótesis sin una medida nueva.

### SMP2P no era el fallo del bus

Con SensorProxy parado, el contador de handover permanece quieto. Al suscribir
el ALS, `q6 ready` y `handover` suben juntos unas 5,2 veces por segundo y el
kernel imprime `Handover signaled, but it already happened`. Ftrace muestra
`smp2p_notify_in status=0x6 val=0x6`: los dos bits quedan afirmados y el IRQ
anidado vuelve a entregarlos al circular tráfico. No hay watchdog, SSR ni
pérdida del QMI. Es ruido del manejo mainline de una línea de nivel, no prueba
de que el STK haya bloqueado el bus.

Las cadenas de los segmentos ADSP confirman que el firmware contiene el driver
STK completo y sus rutas de error: `STK3A6X HW absent`,
`sns_scp_register_com_port fail`, `i2c_open failure`,
`i2c_power_on failure` e `i2c_transfer failed`. El bloqueo actual es obtener
cuál de ellas ocurre en el DSP, porque mainline no expone `/dev/diag` ni una
traza remoteproc.

### Protocolo de fábrica recuperado

El header oficial Android 16 `adsp_ft_common.h` fija
`GET_DUMP_REGISTER=9` y `GET_DHR_INFO=12`. La descompilación de
`factory.ssc` demuestra que para el ALS se convierten en mensajes SSC 609 y
612 con payload de test físico tipo 4; las respuestas esperadas son eventos
709/712, y el DHR de luz lleva 16 enteros. Se construyó fuera del producto
`libssc-0.4.4-r7` (SHA-256
`4a92ebc2f3c73109e26f92a617ea40555c86ee56c9edec17b2d0361794542267`)
para emitir ambos mensajes sobre cada SUID y volcar cualquier respuesta en
hexadecimal. No se incorpora al paquete del dispositivo: es un instrumento
temporal y restaura libssc r0 al terminar.

## Sesión 108 — frontera final del ALS y descarte de referencias externas

### Respuesta DHR real: transporte correcto, datos nulos

El instrumento r7 recibió las respuestas previstas para los dos STK31610:
evento 709 para `GET_DUMP_REGISTER` y 712 para `GET_DHR_INFO`. En ambos casos
el protobuf contiene un bloque de 64 bytes completamente a cero, tanto para
`ambient_light` como para `ambient_light_sub`. Esto corrige la observación
preliminar de la sesión anterior: el DSP sí responde al protocolo de fábrica,
pero no devuelve registros ni diagnóstico físico útil.

Se probaron además tres variantes de recursos, siempre con rollback:

- v1.11 mantuvo votados los clocks QUP SE3/SE4;
- v1.12 registró los controladores AP de `i2c_hub_3`/`i2c_hub_4` sin que
  reclamasen los pines;
- v1.13 mantuvo votados los clocks AHB, core, SE3 y SE4.

Ninguna produjo una indicación de lux ni datos DHR distintos de cero. En vivo
se confirmó que PM8550B L1/L16 permanecen habilitados a 1,8/3,0 V y que el
pinctrl es coherente con el FDT Samsung: GPIO4/5 pertenecen a
`6800000.remoteproc` con función `i2chub0_se4`, y GPIO22/23 con
`i2chub0_se3`. Por tanto no hay evidencia para que el AP tome esos buses ni
para mantener votos de reloj artificiales. Los nodos de v1.12/v1.13 se
retiraron de las fuentes; kernel r56 representa ese rollback reproducible.

### Registro DSP descartado como instrumento

Se construyó `hexagonrpcd` r5 para activar FARF. La primera implementación
sincronizaba la apertura del logger y bloqueó el daemon; la variante asíncrona
ya no bloqueó, pero el DSP rechazó la sesión porque no existe
`libadspmsgd_adsp_skel.so` en el firmware distribuido. Se restauraron
`hexagonrpcd` r4 y `libssc` r0. No se conserva el parche r5 ni se añade una
biblioteca propietaria inexistente al producto.

### Avisos de panel Samsung: prueba negativa y configuración oficial

El fuente oficial `light_factory.c` permite que algunos productos Samsung
envíen al ALS mensajes propietarios de estado del panel, LCD y brillo. Un
cliente diagnóstico r9 envió en la misma conexión SSC, justo antes de la
activación estándar, los payloads de `OPTION_TYPE_SET_PANEL_STATE`,
`OPTION_TYPE_LCD_ONOFF` y la notificación de brillo. Los dos sensores siguieron
sin producir configuración ni medida.

Para no depender solo de ese resultado se extrajo la configuración embebida
del `boot.img` oficial del X910 (Linux Samsung 5.15.153). No contiene
`CONFIG_SUPPORT_DDI_COPR_FOR_LIGHT_SENSOR`,
`CONFIG_SUPPORT_BRIGHTNESS_NOTIFY_FOR_LIGHT_SENSOR` ni
`CONFIG_TABLET_MODEL_CONCEPT`: esas ramas condicionales no formaban parte del
kernel distribuido para esta tablet. No se añadirá COPR al driver mainline del
ANA38407.

### A52/A72 y Xiaomi Pad 6 no son implementaciones transferibles

Se revisaron las páginas, paquetes y cambios de pmaports indicados como
referencia:

- la recomendación de la familia Galaxy A52/A72 de desactivar el brillo
  automático documenta artefactos del panel al cambiar el backlight; sus
  cambios no incluyen `libssc`, SensorProxy ni un ALS Qualcomm funcional;
- Xiaomi Pad 6 sí usa HexagonFS/libssc, que es la misma arquitectura ya
  instalada en el X910, pero sus sensores son TCS3701/TSL2522/BU27030. Sus
  valores `is_dri=0,res_idx=1` contradicen el registro Samsung nativo del
  STK31610 (`is_dri=1,res_idx=0`) y la variante polling equivalente ya se
  había probado sin resultado.

No se copió configuración de ninguno de los dos dispositivos. La coincidencia
de fabricante o de transporte no acredita compatibilidad eléctrica ni de
firmware.

### Ruta IIO directa y estado final

El driver mainline `drivers/iio/light/stk3310.c` solo declara compatibilidad
con STK3013/STK3310/STK3311/STK3335 y no conoce el identificador ni el mapa de
registros STK31610/STK3A6. No existe un datasheet público fiable con el que
añadirlo, y además los buses pertenecen al SSC. Instanciarlo como STK3310
inventaría compatibilidad y arriesgaría la rotación ya estable, así que se
descarta.

Tras todas las pruebas se validó el estado vivo de producción:
`hexagonrpcd-0.4.0-r4`, `libssc-0.4.4-r0`, SensorProxy activo,
`HasAccelerometer=true`, `HasAmbientLight=true` y `LightLevel=0`. GNOME,
NetworkManager y el display manager siguen activos; no se flasheó ninguna
partición y no se generó build porque ningún cambio funcional sobrevivió.

El bloqueo queda dentro de la transacción I²C ejecutada por el driver STK del
DSP. Para avanzar hace falta una traza DSP válida o documentación/registros del
STK31610; seguir alterando recursos AP sin una observación nueva solo repetiría
experimentos ya medidos.

## Sesión 109 — v1.14: bloqueo de giro persistente y carga SM5714 real

### Bloqueo de giro: carrera entre el ajuste y el panel

El síntoma era muy concreto: si GNOME arrancaba con
`orientation-lock=true`, el control visual aparecía bloqueado pero había que
activarlo y desactivarlo una vez para que el bloqueo se aplicase realmente.
No era una pérdida del valor en dconf: se verificó `true` antes y después de
reiniciar.

La causa estaba en `MetaOrientationManager`. Mutter sumaba al mismo
`inhibited_count` tanto el bloqueo persistente del usuario como los inhibidores
temporales del panel. En esta tablet el acelerómetro aparece tarde. La
transición posterior a panel administrado ejecutaba un `uninhibit` y consumía
el conteo que representaba el bloqueo del usuario; la UI seguía mostrando el
valor guardado, pero el compositor ya no estaba inhibido hasta el doble toggle.

Mutter r5 conserva `orientation_locked` como condición independiente en
`sync_accelerometer_claimed()` y usa el contador solo para inhibidores
anónimos. Los cambios del ajuste llaman directamente a la sincronización. El
parche se aplicó sobre Mutter 50.2 y el paquete ARM64 compiló correctamente.

La primera instalación viva de r5 pareció correcta, pero tras reiniciar volvió
a aparecer r4. La causa no era el parche: el rootfs conservaba
`gts9uwifi-install-sensor-packages` r4 y reinstalaba silenciosamente sus cuatro
APK durante cada arranque. Se actualizaron de forma reproducible el instalador
y el contenido de `/usr/share/gts9uwifi/packages`; después de otro reinicio se
verificó `mutter-999950.2-r5` y el valor persistente seguía en `true`. El ZIP
v1.14 contiene ya esa misma combinación. Queda la confirmación física
interactiva tras entrar en la sesión, porque la tablet estaba en el greeter al
cerrar esta iteración.

### La carga no era solo una indicación tardía

Con el cable conectado, el estado inicial medido era:

- `sm5714-usb/online=1`, pero batería `Not charging`;
- corriente de batería alrededor de −0,6 A;
- MUIC `DEVICE_TYPE1=0x04`, es decir DCP;
- cargador `CNTL1=0x64`: `ENQ4FET` apagado;
- `VBUSCNTL=0x10` (500 mA) y `CHGCNTL2=0x07` (mínimo);
- watchdog deshabilitado, por lo que no era el culpable.

Samsung deja ese estado seguro al apagar y el driver mainline anterior era
deliberadamente de solo lectura, así que nunca cerraba el camino de carga. Una
prueba viva reprodujo la rampa del downstream: bajar primero el límite de
entrada, programar la corriente rápida, esperar, activar Q4 y restaurar el
límite DCP. La corriente pasó de descarga a +1,07…1,25 A de forma sostenida.

El driver r57 añade:

- cliente MUIC en 0x25 y clasificación `SDP`/`CDP`/`DCP`;
- límites conservadores por tipo de fuente;
- para DCP, los valores stock medidos `VBUSCNTL=0x44` (1800 mA) y
  `CHGCNTL2=0x86` (2100 mA);
- restauración de Q4 tanto en probe como desde el sondeo;
- sondeo cada segundo y `power_supply_changed()` para USB y batería;
- cancelación/reinicio del delayed work en suspend/resume, eliminando la
  transferencia I²C que antes aparecía con el bus suspendido.

Hubo tres errores de desarrollo que se detectaron antes de cerrar la sesión:

1. la primera compilación usó la API antigua de `power_supply_desc` con un
   array y `num_usb_types`; Linux 7.2 usa una máscara `u32 usb_types`. Se
   corrigió y el objeto compiló;
2. el primer script de escritura UFS canalizaba la contraseña y el script
   remoto por el mismo stdin. Terminó con código cero sin escribir. La auditoría
   posterior detectó el hash antiguo y kernel `#82`, así que no se dio por
   válido. El script corregido copia primero un fichero remoto, verifica
   backup/origen/destino y solo después reinicia;
3. la revisión final encontró que el work se reprogramaba accidentalmente con
   retardo cero en vez de `SM5714_POLL_INTERVAL_MS`. Funcionalmente cargaba,
   pero habría martilleado I²C y consumido CPU. Se corrigió a 1000 ms, se
   relinkó y volvió a validar antes del commit.

La primera conversión de 2093 mA produjo `0x85` por truncamiento. Aunque ya
cargaba, se ajustó a 2100 mA para reproducir exactamente el `0x86` que programa
el bootloader stock. La prueba final inyectó de nuevo el estado averiado
(`CNTL1=0x64`, `0x10`, `0x07`): en dos segundos el propio driver restauró
`CNTL1=0x6c`, `0x44`, `0x86`, publicó `Charging` y registró
`enabled charging for USB type 2 (1800 mA input, 2100 mA fast)`. UPower pasó a
`state: charging` con una actualización nueva.

### Build y estado vivo

Paquetes: kernel r57, device r38 y Mutter r5. La build completa partió de un
worktree limpio, terminó con `BUILD_EXIT=0` y pasó la validación dirigida y CRC.
Después del ajuste exacto de corriente se relinkó el kernel y se reempaquetó el
mismo número de versión:

- `Image.gz`: `8f1908922c84d7edb19f1d2d61889982ce9466e26c26307ceb11c60dc88a72f5`;
- `boot.img`: `f268b293fee52c786cdb4e6d9adabc91fc4919738c84ba09b78ea74d0e766eb6`;
- `vendor_boot.img`: `6f40db1800e272880187730573f48d91c92d99fdbaca8489618888e176278bfd`;
- ZIP `postmarketos-edge-gnome-mainline-v1.14-rotation-charge-sm-x910-twrp.zip`:
  `fe9857f0831f41dd2d7324cacd2ab162aad853512e1400abc28fdf8741ec7f3d`.

Con la autorización permanente se escribió únicamente `boot` (`sda21`), con
backup y hash de lectura idéntico. La tablet corre kernel `#89`, reconoce el
MUIC, clasifica el cable como DCP, muestra `Charging` y conserva Mutter r5 tras
reiniciar. No se tocó `vendor_boot` porque el DTB no cambió. El brillo
automático queda aparcado; el siguiente reto es terminar USB y eliminar la
enumeración intermitente `VID_0000&PID_0002` / Code 43.

## Sesión 110 — v1.32: USB-PD/PPS y carga directa SM5440 estables

La indicación de carga de v1.14 era correcta, pero la medida física con el
cargador Samsung de 45 W demostró que la vía conmutada seguía siendo demasiado
lenta. Se implementó la cadena que faltaba sin reutilizar el framework
downstream `sec-battery`:

- `sm5714_usbpd.c` registra el bloque SM5714 de `i2c_hub_9` como TCPC de Linux;
- TCPM descubre los PDO fijos y el APDO PPS del EP-T4510, hasta 11 V/5 A;
- `sm5440_direct.c` controla la bomba 2:1 de `i2c_hub_3`, mantiene Linux TCPM
  como dueño de la política PD y vuelve siempre a la carga conmutada ante fallo;
- el SM5714 abre Q4 durante carga directa y su sondeo no puede cerrarlo por una
  notificación concurrente.

### Dos conflictos de hardware resueltos

El SM5440 solo respondió con el SE3 del hub QUP en modo GSI. El intento previo
con el controlador PIO hacía visible el chip, pero robaba a remoteproc los
pines `hub_i2c3_data_clk`: el ADSP no arrancaba y desaparecían sensores y audio.
La solución reproducible mantiene GSI y elimina únicamente ese grupo SE3 del
`pinctrl-0` del ADSP; tras reiniciar coexistieron SM5440, ADSP, sensores y ALSA.

La temperatura publicada inicialmente procedía del dado del fuel gauge
SM5714. Subía 44→52 °C en segundos al conmutar Q4 y provocaba ciclos térmicos
falsos. El DT Samsung confirmó el termistor real de batería en PMK8550
ADC5 Gen3, canal virtual `0x144` (PM8550 SID1, `ADC7_AMUX_THM1_100K_PU`).
Se añadió el ADC built-in y el driver usa ahora su lectura IIO; el pack se
mantuvo entre 34 y 35,2 °C durante todas las pruebas de carga directa.

### Fallos medidos y por qué no deben repetirse

Las v1.23–v1.30 fueron útiles como escalones, pero no son builds finales:

1. Con 8,46 V/1,8 A la bomba arrancó y cayó casi inmediatamente con
   `IBUSLIM`, `VOUTOVP_ALM`, `VBUSUVLO` y `REVBLK`.
2. Con 8,78–10,4 V y 1,8 A el VBUS bajo carga caía a 8,4–8,7 V. Subir voltaje
   sin regular el punto 2:1 elevó el dado a 60–64 °C y no solucionó el apagado.
3. Se descubrió una carrera real: escribir `VOLTAGE_NOW` en la power_supply
   PPS termina antes de que el adaptador alcance físicamente la tensión. El
   driver ahora habilita primero el ADC y espera hasta tres segundos a que
   VBUS esté dentro de 500 mV del objetivo antes de `CHG_ON`.
4. Incluso a 1 A, con VBUS, IBUS y temperatura estables, la bomba se apagaba
   siempre a los cinco segundos. El código Samsung dio la causa exacta:
   `support_pd_remain` reenvía el Request PPS cada 2,5 s. Nuestra única petición
   caducaba, el adaptador volvía hacia 9 V y el SM5440 disparaba `REVBLK`.
   v1.31/v1.32 refrescan corriente y tensión cada dos segundos.

Una prueba separada con la bomba apagada confirmó que el PPS no era inestable:
10,4 V solicitados se mantuvieron físicamente entre 10,19 y 10,28 V durante
10 s. La caída era consecuencia del punto de operación y, finalmente, de la
caducidad del Request.

### Resultado físico

Con el punto de entrada inspirado en el downstream
`2×VBAT + 700 mV`, límite SM5440 de 1,8 A y keepalive:

- PPS permaneció activo durante más de cuatro minutos por prueba;
- a 78–82 % se midieron aproximadamente 2,8 A netos hacia la batería;
- al 86–87 %, ya en transición CV, se mantuvieron 1,84–2,05 A;
- VBUS físico quedó alrededor de 9,15–9,22 V, IBUS 1,84–1,96 A;
- dado SM5440 alrededor de 47 °C y pack estable en 34,4–35,2 °C;
- no aparecieron nuevos `REVBLK`, thermal shutdown ni fallback;
- la batería avanzó de 76 a 87 % durante las iteraciones.

La prueba se dejó continuar: al alcanzar el umbral del 90 % el driver apagó
la bomba, puso TCPM de `online=2` (PPS) a `online=1` y restauró el contrato fijo
9 V/1,66 A y Q4. A 93 % la batería seguía publicando `Charging` a unos 0,46 A,
sin quedarse en un estado falso ni descargarse. Queda validado también el
final de sesión y no solo la entrada a carga directa.

El pico real con batería baja queda por cuantificar; no se afirma haber medido
45 W. Sí quedan demostrados en hardware el contrato PPS, la bomba 2:1, la
corriente neta mejorada, las protecciones y el fallback seguro.

### Nombres comerciales y build final

Fastfetch usa una configuración específica del dispositivo y muestra
`Qualcomm Snapdragon 8 Gen 2` y `Qualcomm Adreno 740`. GNOME Control Center
lleva un parche limitado al compatible `samsung,gts9uwifi`, por lo que no
falsea la identidad de otros equipos. El APK personalizado compiló y se incluye
en el overlay reproducible.

La primera instalación real del APK r1 falló en `pre-upgrade` con
`Exec format error`: en el fuente Alpine ese fichero era un enlace a
`pre-install`, pero el checkout de Windows lo había materializado como una
línea de texto sin shebang. No se aceptó el mero éxito de compilación. Se
sustituyó por un script POSIX real, se incrementó a r2, se recompiló y la
actualización viva terminó sin errores. Esta es otra razón para probar la
instalación del APK, no solo su presencia dentro del ZIP.

Paquetes finales: kernel r75, device r40, GNOME Control Center r2 y firmware
r10. La tablet corre
kernel `#107`; solo se escribió `boot` (`sda21`) con backup y SHA idéntico.
El DTS ya validado no cambió, por lo que no fue necesario escribir
`vendor_boot`.

- `Image.gz`: `2ea4b867b7b74346250fb57c673b6f440d653d1a70fbbd8ecd8c6179001829c3`;
- `boot.img`: `2a8e9c8bf39acd66ad3815399037870ca27d6573db97bf5999a5ccf6695f5f66`;
- `vendor_boot.img`: `2f5322ad06520d9c8b9a6a4f319c5303c55462f7179e7bd4d84a8663c57db844`;
- ZIP `postmarketos-edge-gnome-mainline-v1.32-sm5440-direct-charge-sm-x910-twrp.zip`:
  `cc506b82c82c7a687c9edcb2d31ed40a80d888e538528db29d27e8f917843ca3`.

El siguiente reto vuelve a ser USB. Ahora hay una base TCPM/Type-C real, así
que gadget, orientación y DP altmode deben integrarse sobre el SM5714 ya
funcional. También se añadió el motor de vibración a la tabla pública como
hardware pendiente.

## Sesión 111 — v1.33–v1.37: dual-role USB, PS5169 y aislamiento de la regresión DRM

La auditoría en vivo de v1.32 confirmó que el gadget RNDIS ya funciona a High
Speed. El bloqueo observado en Windows no era siempre un fallo eléctrico:
Windows conservaba el controlador Google ADB para el dispositivo compuesto y
había que asignar manualmente **Remote NDIS Compatible Device**. El kernel, sin
embargo, seguía forzado a `dr_mode = "peripheral"`, sin `usb_role_switch`, PHY
SuperSpeed ni host drivers.

### v1.33: base host/OTG reproducible

Se implementó el camino dual-role sobre el SM5714 usando los valores exactos
del fuente GPL Samsung:

- `set_cc` y `start_toggling` por hardware DRP (`CC_CNTL1=0x40`), evitando el
  bucle TCPM por software que llegó a provocar I²C durante suspend;
- boost OTG del SM5714 en modo `0x7`, `BSTCNTL1=0x46` (5,1 V/900 mA) y Q4
  abierto, excluyente con carga normal y PPS directa;
- `usb-role-switch`, PDO source de 5 V/900 mA y roles dual/dual;
- almacenamiento, UAS, RTL8152, ASIX, CDC Ethernet/NCM y audio USB built-in.

v1.33 arrancó y conservó el panel interno, pero la validación física de un
dongle host quedó pendiente porque el cable seguía conectado al PC.

### v1.34/v1.35: USB3/DP enlaza, pero el grafo DRM bloquea DSI

El FDT y fuente oficial identificaron el PS5169 en QUP SE12/I²C12, con tuning
stock `50=10`, `51=70`, `54=02`, `5d=40`, SBU mediante GPIO183 active-low y
GPIO180 de orientación. Se añadieron QMP USB3/DP, `mdss_dp0`, rail L3F de
0,88 V, el mux SBU y un driver mainline Type-C propio para PS5169.

La prueba viva de v1.34 midió:

- PS5169 enlazado en `4-0028`, ID real `69:87`;
- QMP combo en `88e8000.phy`;
- UDC con capacidad SuperSpeed;
- `mdss_dp0` diferido y ausencia de `card1`, por lo que tampoco arrancó el
  display manager.

La causa no era el panel ni el PHY. QMP registra un `drm_aux_bridge` y el
primer intento hizo lo mismo en PS5169. El segundo bridge busca otro bridge en
`port@0`, pero allí solo existe `usb-c-connector`, que no registra un bridge
DRM. El resultado es `-EPROBE_DEFER`; como DP forma parte del mismo component
master MSM, también retiene el DPU/DSI interno. v1.35 añadió explícitamente el
bridge en PS5169, pero solo creó un segundo `aux_bridge` diferido y repitió el
fallo. No repetir esa topología.

### v1.36 fallida y v1.37 candidata de recuperación

v1.36 convirtió PS5169 en bridge DRM terminal. Compiló y el hash escrito sobre
`boot` (`sda21`) coincidió (`77a21be8…`). La primera búsqueda por SSH rechazó
la host key renovada y llevó a diagnosticar erróneamente que no había llegado
a userspace. El journal recuperado después desde TWRP demostró lo contrario:
kernel `#110`, OpenSSH, Wi-Fi, graphical target y más de 1.300 s de uptime. El
fallo real era gráfico: los dos `aux_bridge` seguían diferidos y GNOME terminó
con `No GPUs with outputs found`. No repetir el bridge terminal ni usar la
ausencia de una sesión SSH aceptada como prueba de fallo de boot. Solo se
escribió `boot`; `vendor_boot` y el rootfs permanecieron intactos.

La alternativa v1.37 elimina por completo el bridge DRM del PS5169. El retimer
y la orientación siguen en el framework Type-C, independientemente de DRM. Un
parche mínimo en `msm_dp_display_probe_tail()` trata `-EPROBE_DEFER` igual que
la ausencia de bridge **solo para DP externo**; eDP sigue exigiendo su panel.
Así MSM DP conserva sus propios callbacks HPD/detect/EDID/modos y no retiene el
master compartido por una cola opcional que termina en USB-C.

La build v1.37 terminó con `BUILD_EXIT=0`, aplicó el parche y pasó CRC:

- `boot.img`: `17ad56e9bdc8d9597426feeeffa5c19c1cec1c07dd95c4169594329deec45117`;
- `vendor_boot.img`: `f36bebc33357e5904ff38371bf9e9055d02365e964571a89a5c557a652d9deb7`;
- ZIP `postmarketos-edge-gnome-mainline-v1.37-usb3-dp-no-defer-sm-x910-twrp.zip`:
  `fc05f7d498612ce5e13bdea3a80e8c240707d56c38bfb7f10cdd5b16a9a17045`.

Queda pendiente entrar en TWRP, flashear v1.37 y validar primero arranque,
`card1`/DSI, Wi-Fi y PS5169/QMP. Solo después se probarán un dongle host sin
alimentación, uno alimentado y una pantalla USB-C/DP real.

## Sesión 112 — v1.37–v1.39: DRM recuperado y Type-C real sincronizado

### v1.37 valida la separación entre DP y la cola USB-C opcional

Desde TWRP se escribió únicamente `boot` y la lectura completa verificó
`17ad56e9bdc8d9597426feeeffa5c19c1cec1c07dd95c4169594329deec45117`.
La tablet arrancó con kernel `#114` y se midió:

- `card0` Adreno, `card1` DPU y `renderD128`;
- `card1-DSI-1=connected` y `card1-DP-1=disconnected`;
- DPU enlazado simultáneamente a DSI y `ae90000.displayport-controller`;
- GNOME Shell y GDM activos, panel recuperado y Wi-Fi/SSH disponibles;
- QMP combo enlazado, PS5169 en `4-0028` con ID `69:87`;
- UDC configurado a High Speed con capacidad SuperSpeedPlus;
- drivers host built-in registrados para UAS, almacenamiento, RTL8152, ASIX,
  CDC Ethernet/NCM, HID y audio USB.

Sigue apareciendo un `aux_bridge` diferido en la cola opcional del conector,
pero ya no retiene el master DRM. Esto valida el alcance mínimo del parche de
MSM DP: eDP sigue estricto y solo DP externo tolera esa cola ausente.

### v1.38: causa raíz de CC físicamente desconectado

Aunque el gadget funcionaba por el rol inicial, Type-C publicaba
`orientation=unknown`, no existía `port0-partner` y el SM5714 no podía cambiar
automáticamente a host. La comparación con el GPL Samsung encontró una
omisión concreta:

- TCPM llama primero a `set_cc(OPEN)`, que escribe `CC_CNTL3=0x88` y apaga los
  comparadores CC;
- nuestro `start_toggling()` seleccionaba DRP con `CC_CNTL1=0x40`, pero no
  retiraba aquel latch;
- Samsung restaura explícitamente `CC_CNTL3=0x80` al volver a operación normal.

v1.38 incorporó esa escritura. Tras arrancar kernel `#115`, debugfs midió
`CC_CNTL1=0x40`, `CC_CNTL3=0x80` y `CC_STATUS=0x31`: partner source con Rp 3 A,
cable invertido/CC2. El hardware ya detectaba el cable, pero TCPM aún quedaba
sin partner. El contador del IRQ físico subió de 3 a 9 durante transiciones,
por lo que la línea GPIO133 tampoco estaba muerta.

Durante la escritura de v1.38 el primer script verificó por error solo 64 MiB
de una imagen `boot.img` de 96 MiB y, correctamente, se negó a reiniciar. El
backup v1.37 ya estaba a salvo. Se repitió la lectura con 24 bloques de 4 MiB,
el hash completo coincidió y solo entonces se reinició. Los scripts posteriores
conservan esa longitud exacta.

### v1.39: carrera de attach inicial resuelta

La secuencia de probe explicaba la última discrepancia: `tcpm_register_port()`
puede iniciar el DRP antes de que el threaded IRQ haya sido solicitado, y los
comparadores necesitan un breve tiempo después de `CC_CNTL3=0x80`. El primer
edge de attach podía perderse aunque `CC_STATUS` quedara correcto.

El driver r82 añade un único `delayed_work` que, 250 ms después de habilitar el
DRP, resincroniza CC y VBUS mediante `tcpm_cc_change()` y
`tcpm_vbus_change()`. Se cancela limpiamente en remove; no sondeo registros de
forma periódica ni sustituye los IRQ posteriores.

Build y escritura:

- `boot.img`:
  `7418d905c37ced6053809dd2f13fad2d92adb225d1541d22ce8ba1a9519fc862`;
- ZIP `postmarketos-edge-gnome-mainline-v1.39-usb-typec-resync-sm-x910-twrp.zip`:
  `38b851b4014ac51ee9338ae9b3ff6ee8809eeb24984bd1e23c65c228e7ec6b78`;
- backup completo de v1.38:
  `c15048dee7b5f5bb4d2b46eb4e640e84d875aba2a70383f86be9daee18779c46`;
- solo `boot`/`sda21`, con hash origen y lectura final idénticos.

Kernel `#116` arrancó con GDM/GNOME, Wi-Fi, DSI, DPU+DP, QMP y PS5169 sin
regresiones. Por primera vez el cable físico produce:

- `/sys/class/typec/port0-partner`;
- `orientation=reverse`;
- power role sink, data role device;
- role switch DWC3 en `device`;
- gadget configurado a High Speed.

El control-plane Type-C queda validado como sink. El reto inmediato es la
prueba física de un dongle sin alimentación: debe pasar a source/host,
habilitar el boost SM5714 de 5,1 V/900 mA y enumerar un periférico. Después se
repite con hub alimentado y, por último, con un adaptador/pantalla DP-altmode.

## Sesión 113 — v1.40–v1.45: host estable y frontera USB2 downstream

La primera prueba física con un dongle USB-C pasivo y receptor de ratón
descubrió dos problemas distintos. El control Type-C oscilaba y, aun cuando
xHCI aparecía, TCPM desmontaba el host antes de enumerar el receptor.

### v1.40–v1.44: estabilización de Type-C source/host

- v1.40 añadió una resincronización única de CC tras probe. Detectaba
  `CC_STATUS=0x42`, pero alternaba host/device y desmontaba xHCI.
- v1.41 cambió la publicidad a Rp default, tal como hace Samsung al aceptar un
  accesorio OTG. No resolvió el ciclo.
- El bit 6 de `CC_STATUS` identifica el cable con Ra. v1.42 lo publica a TCPM
  en el CC inactivo; TCPM pide VCONN y el SM5714 escribe el valor stock
  `CC_CNTL5=0x19/0x1a`. Tampoco bastó.
- La traza focal v1.43 encontró la causa del `DETACH`: después de VCONN, boost
  y `set_roles(source,host)`, TCPM llamaba `set_cc(RP_1_5)` y el driver forzaba
  `CC_CNTL1=0x49`, `CC_CNTL3=0x81`. El IRQ de detach llegaba inmediatamente.
  Samsung solo usa esos valores en un role-swap forzado; en un attach natural
  deja a la máquina DRP en `0x40/0x80`.
- v1.44 conserva la conexión DRP natural y solo ajusta los bits Rp. Tras una
  reconexión física desapareció el bucle: existen `port0-partner`,
  `orientation=normal`, `source/host`, VCONN, boost 5,1 V/900 mA y los dos
  root hubs xHCI permanecen registrados. El receptor, sin embargo, no aparece
  en USB ni crea un input.

La medición del PTN3222 acota la nueva frontera. Con el dongle conectado:

- revisión e I2C/tuning correctos (`A2`, `06=20`, `07=21`, `08=63`,
  `0a=01`);
- `DEVICE_STATUS=0x0e`: repetidor en rol host;
- `LINK_STATUS=0x01`: `Connect Detect`, sin pull-up downstream;
- DWC3, PHY eUSB2, QMP y xHCI permanecen activos.

Por tanto, ya no es un problema de rol TCPM ni de registro del host: falta que
el periférico sea eléctricamente visible en D+/D−.

### v1.45: pulso OTG-detect exacto del stock

El GPL Samsung y el FDT X910 contienen una acción que faltaba:
`usbpd,otg_det = GPIO89`. En cada attach source, el driver stock lo eleva
durante 130 ms y lo baja mientras enciende VCONN/VBUS. v1.45:

- añade `otg-det-gpios = <&tlmm 89 GPIO_ACTIVE_HIGH>` y su pinctrl stock;
- adquiere el GPIO opcional desde el driver SM5714;
- inicia el pulso al entrar en `set_vbus(on)` y lo cancela/limpia al salir;
- conserva intactas la política TCPM y la secuencia de boost ya medida.

Build y escritura autorizada únicamente sobre `boot=/dev/sda21`:

- kernel r88, `Image.gz`
  `c80ec391b5117dd78fa34d8f30768ae2eade21311629d8a95f81c3c5b81f2190`;
- `boot.img`
  `23f77e8431ddd57271190a265cba3cfc359165a302f6123f7e6da21d372393f6`;
- ZIP `postmarketos-edge-gnome-mainline-v1.45-usb-host-otg-det-sm-x910-twrp.zip`
  `2e8790e01a8025281d5636aec0959099152d78ec152726dba3145911000412cc`;
- backup completo v1.44
  `52ce08f846e28ffa9d367bec2a34d6c8dbf3fc38be84d33e47ea933cfe33d9e1`;
- lectura completa posterior idéntica al hash de v1.45.

La tablet arrancó con kernel `#123`, GNOME/DSI/Wi-Fi/SSH sin regresiones. Con
el dongle mantenido conectado durante el reboot, TCPM volvió a source/host y
xHCI quedó activo, pero el receptor siguió sin enumerar y PTN3222 permaneció
en `0e/01`. Un cambio lógico de `port_type` mientras el Rd físico seguía
presente fue rechazado correctamente con `I/O error`; la siguiente prueba
necesita un unplug de al menos cinco segundos y un replug físico para producir
un attach nuevo y validar el pulso GPIO89. No se ha hecho commit ni se ha
declarado USB host funcional.

## Sesión 114 — v1.46–v1.49: hub alimentado, HID real y recuperación de xHCI

La prueba siguiente cambió una variable física importante: se conectó el
cargador Samsung de 45 W a la entrada PD del hub USB-C, manteniendo el receptor
Logitech en un puerto downstream. El receptor apareció por primera vez como
`046d:c54d`; con ello quedó probado que GPIO89/PTN3222/DWC3 sí podían cerrar el
enlace USB2 cuando el hub tenía alimentación.

### v1.46: `usbhid` no era todavía un dispositivo de entrada

Las tres interfaces HID enlazaban a `usbhid`, pero `/proc/bus/input/devices`
no contenía el receptor. La causa era el patrón recurrente de este port:
`CONFIG_HID_GENERIC=m` y no se instala ni autocarga un árbol genérico de
módulos. v1.46 fuerza `CONFIG_HID_GENERIC=y` (kernel r89). Tras arrancar,
`hid-generic` creó:

- un ratón `Logitech USB Receiver` con `event*`/`hidraw0`;
- un teclado con `kbd`, `event*`/`hidraw1`;
- la tercera interfaz de control como `hidraw2`.

ZIP:
`postmarketos-edge-gnome-mainline-v1.46-usb-hid-sm-x910-twrp.zip`,
SHA-256
`7864a7499d3baf94fc16aeca03efb5c20676323a32113d7aaeb2d37e14f9e48e`.

### v1.47: la resincronización inicial ocurría demasiado pronto

Con el hub alimentado durante un reboot, el SM5714 quedaba físicamente en
`CC_STATUS=0x11`, pero TCPM no publicaba partner. Su log de estados mostró que
la resincronización de 250 ms se consumía dentro de `PORT_RESET_WAIT_OFF`; el
controlador no regresaba a `TOGGLING` hasta aproximadamente 1,02 s y el edge
de attach ya había ocurrido antes del registro del IRQ.

v1.47 (kernel r90) retrasa esa única resincronización a 1.500 ms. TCPM detectó
entonces CC y VBUS, inició PD y recibió del hub el primer header `0x0143`.
El ZIP
`postmarketos-edge-gnome-mainline-v1.47-usb-tcpm-resync-sm-x910-twrp.zip`
tiene SHA-256
`1f63c09bff75b055f13d6f76fcbc74c51aaf0a09cd2c97f73e6609ab898f05c2`.

### v1.48: dock Source/UFP retenido y host mientras carga

El header no era corrupto: el dock alimentado se declaraba **Source/UFP**.
Suministra energía a la tablet, pero es el periférico en el enlace USB. La
tablet había arrancado como Sink/UFP, de modo que TCPM diagnosticaba
`Data role mismatch` y repetía el reset.

Se añadió una extensión opt-in mínima a `tcpc_dev`,
`adopt_retained_source_ufp`. Solo el SM5714 X910 la activa. Si el primer
mensaje SOP de un partner retenido anuncia Source/UFP mientras la tablet es
Sink/UFP, TCPM adopta DFP local antes de procesarlo. No se fuerza host por
estado de carga y no se altera el camino PC/RNDIS.

La build directa falló una vez porque `build-mainline-kernel.sh` todavía no
aplicaba el parche nuevo aunque el APKBUILD sí lo enumeraba. Se añadió al
listado explícito con guarda, se regeneró el parche contra el árbol exacto y
la tercera ejecución terminó con `BUILD_EXIT=0`.

La v1.48 arrancada físicamente produjo:

- partner Type-C estable, tablet Sink/DFP y `usb_role=host`;
- contrato PD fijo de 9 V / 1.660 mA;
- identidad del dock `2d79:e001` y SVIDs `ff01` (DisplayPort) y `2d79`;
- ambos root hubs xHCI;
- receptor Logitech y sus tres dispositivos HID.

Solo se escribió `boot=/dev/sda21`, con backup y hash completo posterior. El
`boot.img` validado es
`65aa22b9ab7b2cdf1222b5a8d2a55d903467b5845f1e38c8108b76db8d7f4ce3`.
El ZIP v1.48 tiene SHA-256
`5e433fff1d28c89dcd078927c2194ccc6f3a9e3aaacaab73fddec0854ea82926`.

### v1.49: el suspend de recuperación del panel destruía xHCI

El host funcionaba al principio del arranque, pero a los ~20 segundos el ciclo
automático `pm_test=platform` usado para recuperar el ANA38407 registraba:

```text
port-1 HS-PHY not in L2
xHCI Host System Error
```

El receptor se desconectaba. Una alternancia local del role-switch
`device → host` volvía a registrar xHCI y reenumeraba el mismo HID. El arreglo
reproducible añade `/usr/libexec/gts9uwifi-usb-host-resume` y lo invoca:

1. al terminar el ciclo frío específico del panel;
2. desde un hook `system-sleep` después de futuros resumes.

El helper sale sin hacer nada salvo que el rol actual sea exactamente `host`;
por tanto no interrumpe gadget/RNDIS cuando la tablet es dispositivo de un PC.
En la prueba fría, el HSE ocurrió como antes, el helper recreó xHCI un segundo
después y el receptor volvió a aparecer. Más de 40 s después seguían presentes
el ratón, teclado e interfaces hidraw. `loginctl seat-status seat0` los enumera
y el proceso GNOME Shell tiene abiertos `/dev/input/event5` y `event6`, por lo
que la ruta llega también al compositor, no solo al kernel. La tablet mantuvo
a la vez el contrato PD de 9 V / 1,66 A.

Versiones finales: kernel r91, device r41, firmware r10. El empaquetado v1.49
pasó CRC y verificó los tres ficheros del overlay. Artefacto:

- `postmarketos-edge-gnome-mainline-v1.49-usb-host-resume-sm-x910-twrp.zip`;
- 61.946.434 bytes;
- SHA-256
  `c0f85920a3210e3992ab4579fe643c8eec10c3363e1dd85772ff385170ee0072`;
- `boot.img`
  `65aa22b9ab7b2cdf1222b5a8d2a55d903467b5845f1e38c8108b76db8d7f4ce3`;
- `vendor_boot.img`
  `beea1c07abe681b6ebf55dfb3fa279864590cc8a271f8c18bbd6a5161cff2e34`.

Queda por confirmar visualmente el movimiento del cursor y probar clases
adicionales con hardware real: accesorio pasivo, almacenamiento/UAS y
DisplayPort altmode. La negociación PD por el hub no resuelve por sí sola la
carga: la usuaria sigue observando desconexiones lógicas y una estimación de
unas cinco horas al 10 %, incluso conectando el cargador oficial directamente.
Ese diagnóstico queda deliberadamente después de cerrar las pruebas USB host.

### v1.50: el receptor era Lightspeed y necesitaba DJ/HID++

La presencia de `hid-generic` aún no equivalía a movimiento real. Dos ventanas
de lectura sobre el evento genérico no recibieron paquetes. La búsqueda por el
ID exacto encontró `046d:c54d` en la tabla upstream de
`hid-logitech-dj.c` como `NANO_RECEIVER_LIGHTSPEED_1_4`. La configuración viva
explicó por qué el receptor seguía agregado:

```text
CONFIG_HID_LOGITECH=m
CONFIG_HID_LOGITECH_DJ=m
CONFIG_HID_LOGITECH_HIDPP=m
CONFIG_LEDS_CLASS_MULTICOLOR=m
```

El port no instala esos módulos. v1.50 los fuerza todos a `=y` y sube kernel a
r92. La build terminó con `BUILD_EXIT=0`; el log acredita la compilación de
`hid-lg`, `hid-logitech-dj` y `hid-logitech-hidpp`.

La escritura autorizada se limitó de nuevo a `boot=/dev/sda21`. La herramienta
local agotó su timeout mientras la tablet ya estaba reiniciando, así que no se
repitió a ciegas. Tras volver SSH, el kernel `#127` y la lectura completa de
96 MiB confirmaron exactamente:

`02abad11624b8984430a0e7196ea03706768ee62cb7082ea81f72b64baa364e1`.

Después del HSE esperado y de la recuperación host-only, el receptor volvió a
enumerar. Esta vez la cadena real es:

```text
046d:c54d → logitech-djreceiver
eQUAD Lightspeed, slot 1
046d:40b8 → logitech-hidpp-device
Logitech PRO X 2 DEX
```

El único evento resultante tiene `REL_X/REL_Y`, botones, rueda, LED y otros
ejes; GNOME Shell mantiene abierto su nodo. No llegaron eventos durante dos
ventanas de escucha de 20 s, de modo que aún falta que la usuaria confirme que
el ratón estaba encendido y moviéndose en esas ventanas, y confirmar el cursor
visualmente. El software ya no confunde el receptor con el dispositivo
emparejado.

Artefacto final:

- `postmarketos-edge-gnome-mainline-v1.50-usb-lightspeed-sm-x910-twrp.zip`;
- 61.997.786 bytes;
- SHA-256
  `961ab5ae10fe4b063f37b2e972edda91d9da973fb4687e06f147de9f36a4d4d4`;
- `boot.img`
  `02abad11624b8984430a0e7196ea03706768ee62cb7082ea81f72b64baa364e1`;
- `vendor_boot.img`
  `ea3f4d185b1e5a219f0a54f04acbec81fdf0ae85b395c2c9e1bb2fca551098de`.

## Sesión 115 — v1.51–v1.55: PR_SWAP estable, ratón repetible y rotación con puntero

### El ratón era funcional, pero conectarlo desactivaba la orientación

La usuaria confirmó movimiento real del cursor, no solo nodos de input. El
hub alimentado mantenía a la tablet como Sink/DFP y el Logitech Lightspeed
funcionaba, pero GNOME ocultaba el control de rotación y dejaba de girar al
conectar el ratón.

La regla udev específica del hijo HID++ corrigió su clasificación engañosa
como teclado integrado, pero no la política final. Mutter usa como fallback
`clutter_seat_get_touch_mode()`: cualquier puntero hace que una slate sin
switch de modo deje de considerarse tablet. El paquete específico de la X910
sube Mutter a r6 y mantiene `PanelOrientationManaged` siempre que existan el
acelerómetro y el panel integrado. Con el mouse presente se midieron
simultáneamente:

```text
HasAccelerometer = true
PanelOrientationManaged = true
```

El instalador persistente de la microSD conservaba todavía los APK r5 y
degradaba r6 después de cada reinicio. Se actualizaron tanto los cuatro APK
del overlay como `/usr/libexec/gts9uwifi-install-sensor-packages`; r6 permanece
instalado tras boot.

### PR_SWAP Source→Sink sin perder el dock

Al enchufar el cargador a un hub que la tablet ya alimentaba, el primer driver
abría brevemente ambos CC al cambiar de Source a Sink. El dock desaparecía
antes de completar el intercambio. La comparación con el driver Samsung dio
la secuencia exacta:

1. congelar el estado detectado en `CC_CNTL3`;
2. cambiar el pull in-place con el bit 0 de `CC_CNTL7`;
3. liberar el hold al recibir `PS_RDY`.

v1.53 implementa esa secuencia solo cuando el paquete PD recibido es
`PR_SWAP`, sin reutilizar el estado CC bruto como heurístico. Tres ciclos
físicos de desconectar y reconectar el hub con el cargador mantenido
recuperaron 9 V/1,66 A y el receptor al primer intento. Una transición posterior
desde hub sin alimentar a alimentado volvió a enumerar el receptor en unos
1,2 segundos.

### El dock probado no transmite datos alimentado por bus

Sin cargador, la ruta de la tablet sí llega a su estado esperado:

```text
power_role = source
data_role = host
SM5714 boost = 5.1 V / 900 mA
PTN3222 DEVICE_STATUS = 0x0e
PTN3222 LINK_STATUS = 0x01
```

Sin embargo, el RDO del partner declara `USB_COMM=false` y nunca aparece el
pull-up downstream. Solo enumeran los root hubs xHCI; no aparecen ni el
controlador del hub ni el receptor. Esto ya no es una ausencia de VBUS, un rol
TCPM erróneo ni una carrera de GPIO89.

Al retirar el cargador en caliente, el dock deja de enviar su `PS_RDY`. v1.54
probó una extensión opt-in a TCPM que completaba localmente el PR_SWAP
Sink→Source al medir VSAFE0V. La transición bajó del timeout de 920 ms a unos
20 ms, pero el dock siguió sin presentar datos y TCPM necesitó hard-reset y
varios Source_Capabilities porque el partner ya se había apagado. Al no aportar
funcionalidad y saltarse una fase normativa, el experimento se eliminó de
v1.55. Queda pendiente probar un adaptador OTG pasivo o un hub distinto que se
sepa que soporta datos sin alimentación externa.

### Build limpia: dos trampas reproducibles encontradas

El primer intento de v1.55 se descartó antes de flashear: aunque se había
retirado el parche v1.54 de las fuentes, el worktree conservaba la modificación
aplicada. Se eliminó el worktree y el `O=` completo. El nuevo build demostró
otra dependencia que los objetos antiguos ocultaban: un `M=` aislado no puede
enlazar `.ko` en un árbol limpio hasta ejecutar `modules_prepare`, porque falta
`scripts/module.lds`. `build-mainline-kernel.sh` lo hace ahora explícitamente y
usa la ruta absoluta del subárbol ath12k.

La primera escritura de `boot` v1.55 arrancó escritorio, táctil y resto del
hardware, pero no Wi-Fi. El journal recuperado desde TWRP dio la causa exacta:

```text
Lockdown: unsigned module loading is restricted
Failed to insert module 'ath12k_wifi7': Operation not permitted
```

Al regenerar un `O=` limpio también se había generado una nueva clave de firma.
Se actualizó `boot`, pero la microSD conservaba los módulos firmados por la
clave anterior. En TWRP se montó `mmcblk1p2`, se guardó una copia persistente
del directorio anterior y se instalaron los dos módulos producidos por la misma
build v1.55. Sus hashes se verificaron antes de reiniciar:

- `ath12k.ko.zst`:
  `5eb4e012bb876638fe46b40e6c7b1b48799be644adf9e9b9b5a3caeed2615eb7`;
- `ath12k_wifi7.ko.zst`:
  `db18ca706e59eb89ae907ceaba6c0d04c4c1f13bdc00e25cfaa16f1abf2a0ee9`.

El siguiente arranque cargó ambos módulos, creó `wlan0`, NetworkManager volvió
a `connected` y SSH reapareció. Esto fija una regla nueva: con kernel lockdown,
una iteración desde build limpio no puede actualizar solo `boot`; debe aplicar
también los módulos del mismo bundle. El ZIP ya cumple esa propiedad porque
lleva ambos en su overlay.

### Artefacto v1.55

- kernel r97, device r42, firmware r10, Mutter r6;
- `Image.gz`:
  `3fc2e92508f7d36669b77c87b2d5634419d2392e6516cafef9d29aa1aac949c2`;
- `boot.img`:
  `031df649c81e1f71804dad47d0e2347fffaeecdbae0f6dded2fefb8264cee039`;
- `vendor_boot.img`:
  `07e1df2960729ad5fd09cb8eef711d94e3e25ccaf50dc616d7cbc70e274a7498`;
- ZIP
  `postmarketos-edge-gnome-mainline-v1.55-usb-host-rotation-stable-sm-x910-twrp.zip`,
  61.995.173 bytes, SHA-256
  `365b98801c71ddb9954bf24d629aa9d21a36d78b22c8becb287cdca13e12e806`.

La validación final de la tablet arrancada confirma kernel `#1`, Wi-Fi/SSH,
display manager, SensorProxy y Mutter r6. Quedan para hardware distinto:
host pasivo, almacenamiento/UAS y DisplayPort altmode.

### Validación física final del build limpio v1.55

Con la tablet ya arrancada sobre el kernel limpio y los dos módulos ath12k
firmados por esa misma build, se conectó de nuevo el hub con su entrada PD de
45 W y el receptor Lightspeed. No hizo falta repetir la conexión:

- TCPM quedó en `power_role=sink`, `data_role=host`;
- el contrato convergió a 9 V / 1,66 A;
- xHCI registró el receptor `046d:c54d` y el hijo de input Logitech en unos
  1,5 segundos desde el attach;
- `wlan0` siguió `UP/LOWER_UP` y SSH permaneció accesible;
- con el ratón presente, SensorProxy/Mutter publicaron simultáneamente
  `HasAccelerometer=true` y `PanelOrientationManaged=true`.

Esto valida el artefacto v1.55 final, no solo el binario intermedio v1.53. La
única frontera USB observada sigue siendo el modo sin alimentación de este dock
concreto, cuyo RDO anuncia `USB_COMM=false`; no se generaliza esa conducta a
otros adaptadores pasivos todavía no probados.

## Sesión 116 — v1.56–v1.60: hub USB alimentado por la tablet

### El dato faltante estaba en el MUIC, no en TCPM ni en el repetidor

Se conectó un segundo hub que no dispone de entrada de alimentación. En v1.55
la X910 alcanzaba Source/Host, activaba el boost SM5714 a 5,1 V/900 mA y
mantenía ambos root hubs xHCI, pero no aparecía ningún hijo USB. El PTN3222
seguía en `DEVICE_STATUS=0x0e`, `LINK_STATUS=0x01`: host en Connect Detect sin
pull-up downstream.

La comparación con el GPL Samsung encontró una pieza que no estaba modelada:
el SM5714 MUIC de `i2c2@0x25` contiene el conmutador físico D-/D+. En
`ATTACHED_DEV_OTG_MUIC`, Samsung:

- desactiva BC1.2 poniendo el bit 1 de `CNTL` (`0x05`);
- selecciona manualmente la ruta USB escribiendo `MANUAL_SW=0x89` (`0x06`).

Una prueba reversible en vivo cambió `0x24/0x00 → 0x26/0x89`. Sin reiniciar ni
recrear xHCI aparecieron inmediatamente:

```text
05e3:0610  GenesysLogic USB2.0 Hub
0bda:8153  Realtek USB 10/100/1000 LAN
046d:c54d  Logitech USB Receiver
```

Esto demuestra que VBUS, CC, DWC3, xHCI y PTN3222 ya estaban bien; faltaba
cerrar el camino eléctrico USB2.

### v1.56–v1.58: el falso culpable de los 500 ms

v1.56 integró la ruta MUIC antes del boost. v1.57 la movió al callback de roles
y v1.58 la aplazó un segundo mediante `delayed_work`. Las tres parecían
regresionar: Source/Host desaparecía unos 500 ms después del attach. Una prueba
que restauró MUIC a automático inmediatamente tampoco evitó la caída, por lo
que la escritura temprana no podía ser la causa.

El log interno de TCPM dio la evidencia exacta:

```text
vbus:=1 charge=0
pending state change SRC_ATTACHED -> SRC_UNATTACHED @ 480 ms
VBUS off
VBUS VSAFE0V
state change SRC_ATTACHED -> SRC_UNATTACHED [delayed 480 ms]
```

`sm5714_usbpd_get_vbus()` solo leía `STATUS1.VBUS_POK`. Ese bit detecta una
fuente externa, pero permanece a cero cuando el propio bloque cargador genera
VBUS mediante el boost OTG. TCPM aplicaba correctamente `tSrcTurnOn=480 ms` y
desmontaba una fuente que físicamente sí estaba activa.

### v1.59: VBUS correcto, pero orden de datos todavía incorrecto

v1.59 añadió `sm5714_battery_is_otg_active()` y hace que `get_vbus()` devuelva
verdadero si existe VBUS entrante **o** si el cargador confirma OTG activo.
En la tablet:

```text
pending state change SRC_ATTACHED -> SRC_UNATTACHED @ 480 ms
VBUS on
state change SRC_ATTACHED -> SRC_STARTUP
```

El host permaneció vivo y el trabajo MUIC llegó a ejecutarse al segundo. Sin
embargo, el hub no enumeró: D-/D+ se abrían después del pulso OTG-detect y de
crear xHCI. Repetir la escritura MUIC y recrear xHCI en vivo tampoco produjo un
nuevo pull-up en ese estado. Además, una prueba propia `port_type=sink → dual`
dejó TCPM atascado en `SRC_ATTACH_WAIT`; se recuperó reinicializando solo el
driver SM5714 USB-PD. Esa manipulación no forma parte del arreglo.

### v1.60: ruta MUIC síncrona y validación completa

v1.60 elimina el `delayed_work`. `sm5714_battery_set_otg(true)` abre primero la
ruta MUIC (`0x26/0x89`), después programa boost y marca OTG activo. El callback
USB-PD ya había iniciado el pulso stock GPIO89 y TCPM crea el host una vez que
la ruta física está conectada.

El hub permaneció conectado durante el arranque. La secuencia medida fue:

- boost OTG a los 12,88 s;
- Genesys enumerado a los 13,45 s;
- RTL8153 a los 17,35 s;
- receptor Logitech a los 18,37 s y su hijo HID++ `046d:40b8` a los 19,22 s;
- HSE esperado durante `pm_test=platform`;
- helper host-only recreó xHCI;
- Genesys, RTL8153 y Logitech volvieron a enumerar entre 36,26 y 38,07 s.

A los 79 s seguían presentes los tres dispositivos, `usb_role=host`, MUIC
`0x26/0x89` y PTN3222 `DEVICE_STATUS=0x0a`, `LINK_STATUS=0x05`. El receptor
creó el input `Logitech PRO X 2 DEX`; `loginctl seat-status` lo atribuye a
`seat0`. Con el puntero presente se midieron a la vez:

```text
HasAccelerometer = true
PanelOrientationManaged = true
```

Por tanto, el hub sin alimentación externa y la política de rotación quedan
validados por el sistema real. El movimiento físico del cursor ya estaba
confirmado con el mismo receptor en el hub alimentado; esta sesión valida su
misma cadena HID y asignación a GNOME en modo bus-powered.

El RTL8153 enumera pero registra:

```text
unable to load firmware patch rtl_nic/rtl8153a-3.fw (-2)
```

La interfaz Ethernet no se declara funcional hasta incluir firmware y medir
tráfico. También siguen pendientes almacenamiento/UAS y DisplayPort altmode.

Build final:

- kernel r102;
- `Image.gz`:
  `f7750b820bc41e2c4a153dbb3ddf83e35fd8609e68d92abb2354b0c21eff01f2`;
- `boot.img`:
  `2096237ac05acda8fdd61f5c9f6470a36469819c6015ab7093dbf53d645db854`;
- ZIP:
  `postmarketos-edge-gnome-mainline-v1.60-usb-passive-host-sm-x910-twrp.zip`;
- ZIP SHA-256:
  `0498a8ffdc73315ad91ea7cdd6987cca111fba733811ad4e157cad43da4d7c66`.

Solo se escribió `boot=/dev/sda21`, con backup v1.59
`a656c1755c8e875a239e4e9c39922e6add184b263b4b89b8dacf5b6964de1363`
y lectura posterior idéntica al origen. Los módulos ath12k de v1.60 mantienen
los hashes de la pareja firmada instalada, así que Wi-Fi/SSH siguieron activos.

## Sesión 117 — firmware RTL8153 y builds limpias reparadas

El RTL8153 integrado en el hub pasivo había enumerado en v1.60, pero r8152
registraba:

```text
Direct firmware load for rtl_nic/rtl8153a-3.fw failed with error -2
unable to load firmware patch rtl_nic/rtl8153a-3.fw (-2)
```

La primera hipótesis de paquete fue incorrecta:
`linux-firmware-realtek` no contiene `rtl_nic/`. El paquete Alpine correcto es
`linux-firmware-rtl_nic`. Se instaló temporalmente en el sistema vivo y se
reenlazó únicamente `1-1.2:1.0` con r8152. La medida posterior fue:

```text
driver: r8152
firmware-version: rtl8153a-3 v2 02/07/20
bus-info: usb-xhci-hcd.1.auto-1.2
Link detected: no
```

Por tanto, el firmware sí está cargado. `Link detected: no` es el resultado
esperado sin cable Ethernet; enlace y tráfico siguen pendientes y Ethernet no
se marca todavía como funcional. Para instalaciones reproducibles, device r44
añade `linux-firmware-rtl_nic` como dependencia.

### Dos fallos de build limpia descubiertos y corregidos

La construcción forzada del paquete de dispositivo obligó a reconstruir el
kernel desde el tarball limpio y encontró que `ignore-console-null.patch`
declaraba 16 líneas nuevas en un hunk que contiene 15. El pipeline directo lo
había tolerado, pero `abuild` lo rechazaba como parche malformado. Kernel r103
corrige los contadores del hunk y sus metadatos sin cambiar el código
resultante. El parche pasa ahora `patch --dry-run` contra Linux 7.2-rc3 limpio.

Después de completar kernel r103, el primer intento de device r43 falló porque
su `package()` creaba el enlace de
`gts9uwifi-compile-sensor-schemas.service` antes de crear
`multi-user.target.wants/`. La instalación viva ocultaba el fallo porque el
directorio ya existía. Device r44 crea el directorio explícitamente antes del
primer enlace.

La validación final terminó con `BUILD_EXIT=0`:

- kernel r103 APK:
  `3ca6181335d056b9a72e722b349beee70c27247d967e5e9d9a3d618aff2a27f7`;
- device r44 APK:
  `ea44c5a1238fb7daa1a3065105bdcdb933e709ae79f947d72d8d73c8ae96baea`;
- `.PKGINFO` de device r44 confirma
  `depend = linux-firmware-rtl_nic`.

No se escribió ninguna partición en esta sesión. La tablet siguió ejecutando
v1.60, con hub pasivo, RTL8153 y receptor Logitech presentes, rol USB host,
acelerómetro disponible y orientación administrada.

## Sesión 118 — almacenamiento USB 2.0 validado

Se conectó un pendrive USB 2.0 real al hub pasivo, sin alimentación externa.
La topología mantuvo simultáneamente el hub Genesys, el RTL8153 y el receptor
Logitech. El nuevo dispositivo `346d:5678` se enlazó mediante
`usb-storage`, creó un disco SCSI removible de 14,6 GiB y una partición FAT32.
GNOME la automontó en la sesión de `phablet`; la usuaria confirmó que la unidad
parecía funcionar desde la interfaz.

La validación no destructiva fue:

```text
usb-storage 1-1.3:1.0: USB Mass Storage device detected
scsi host1: usb-storage 1-1.3:1.0
sd 1:0:0:0: [sdg] Attached SCSI removable disk
32+0 records in
32+0 records out
134217728 bytes copied, 6.277328 seconds, 20.4MB/s
```

Se leyeron directamente 128 MiB desde el disco hacia `/dev/null`; no hubo
errores de E/S ni se escribió en la unidad. El automontaje de GNOME ya existía
al comenzar la prueba y estaba en modo lectura/escritura, pero el procedimiento
de validación solo realizó sondeos de metadatos y lecturas.

Esto valida almacenamiento masivo USB clásico sobre el hub alimentado por la
tablet. No valida UAS: el pendrive solo anuncia una interfaz
`usb-storage`. El driver UAS sí está built-in, pero hace falta un SSD/carcasa
que ofrezca ese protocolo para medirlo.

## Sesión 119 — v1.61–v1.64: DisplayPort físico y arranque con dock

### El altmode existía, pero HPD no llegaba al conector DRM

Con el dock USB-C, cargador y una capturadora HDMI reales, el partner anunció
SVID DisplayPort `ff01`, seleccionó la asignación de pines D y elevó HPD. El
SM8550 ya tenía QMP combo PHY, `mdss_dp0`, el mux SBU y el PS5169 funcionando,
pero `card1-DP-1` seguía en `disconnected`.

v1.61 añadió al conector el altmode DP local que exige el framework Type-C.
Después de ello el driver genérico `typec_displayport` enlazó
automáticamente, pero el estado DRM no cambió. v1.62 añadió la asociación
documentada `displayport = <&mdss_dp0>`. Una traza ftrace al alternar el
altmode midió llamadas reales a:

```text
drm_connector_oob_hotplug_event <- dp_altmode_vdm
drm_connector_oob_hotplug_event <- dp_altmode_status_update
```

No aparecía ninguna llamada a `msm_dp_bridge_hpd_notify`. La causa estaba en
el extremo DRM: el puente terminal creado por MSM DP no conservaba el
`of_node` del controlador, de modo que el conector generado carecía del
fwnode con el que `drm_connector_oob_hotplug_event()` intenta encontrarlo.

v1.63 añade un parche mínimo a `msm_dp_bridge_init()`:

```c
bridge->of_node = msm_dp_display->pdev->dev.of_node;
```

Conectando el dock después de arrancar se midió:

- altmode activo, pin D y HPD=1;
- `card1-DP-1=connected` y `enabled`;
- EDID de 256 bytes;
- modos 4096×2160, 3840×2160, 2560×1440 y 1920×1080, entre otros;
- GNOME identificó el sink de captura y seleccionó 1920×1080 a 60 Hz;
- el panel interno permaneció a 2960×1848 a 120 Hz.

La cámara virtual de OBS mostró físicamente el escritorio azul de GNOME en la
salida de la capturadora. Por tanto, DisplayPort USB-C queda validado en
hardware, no inferido solo por sysfs.

### Regresión de arranque descubierta con HPD ya activo

Reiniciar v1.63 con el dock conectado produjo cinco arranques de unos cinco
segundos. Al retirar el dock, el mismo arranque terminó y el hotplug posterior
volvió a dar vídeo. Los journals persistentes acotaron la regresión:

```text
dpu_encoder_frame_done_timeout
PM: suspend entry (deep)
```

Cada intento alcanzaba la unidad
`gts9uwifi-panel-coldboot-recover.service`, pero no llegaba a
`PM: suspend exit`. Con el enlace DP ausente, el mismo ciclo sí retornaba y el
DDIC cambiaba de `00 00 00` a `80 00 04`. No era un bootloop del ABL ni un
fallo del rootfs: el encoder externo activado por el HPD interfería con el
único suspend de plataforma que necesita el panel interno.

Se probó enviar `Exit Mode` (`active=no`) antes de un ciclo manual. En una
sesión gráfica ya activa la tablet terminó reiniciándose; además el dock
conservó el estado de salida hasta un nuevo flanco físico CC. No se usa como
arreglo y no debe repetirse con GNOME usando el monitor externo.

### v1.64: aplazar HPD hasta el primer resume

El arreglo conserva la negociación Type-C y el USB host, pero impide que MSM
DP active su encoder antes de la recuperación del ANA38407. Una propiedad
específica del DTS X910,
`qcom,defer-hpd-until-first-resume`, hace que el puente guarde el último estado
HPD. Un notificador PM libera el bloqueo en `PM_POST_SUSPEND` y reproduce el
evento tres segundos después, dejando terminar antes la recreación host-only
de xHCI.

La primera validación con v1.64 fue:

```text
[24.432] PM: suspend entry (deep)
[39.338] ana38407 panel id: 80 00 04
[39.339] PM: suspend exit
[42.204] replaying deferred Type-C DP HPD after first resume
```

Solo hubo un boot, GDM quedó activo y SSH volvió. Esto corrige la regresión de
reinicios. La prueba anterior de `Exit Mode` había dejado el dock sin un
partner Type-C registrado; ni reiniciar ni reenlazar en vivo el driver SM5714
generó un nuevo flanco CC, por lo que la validación final de vídeo y ratón tras
un arranque con el dock ya activo requiere una única desconexión/reconexión
física y un segundo reinicio.

Build v1.64:

- kernel r107;
- `boot.img`:
  `1c00dc1d1280211fe83b9d354b0108d55d6a60d0af26b0eac3d0c2252b0ae2d9`;
- `vendor_boot.img`:
  `a2b575a7acf7929fe180ce80184e5ef3d1c0810a2fbdcec27670293ff70149c6`;
- ZIP:
  `postmarketos-edge-gnome-mainline-v1.64-dp-coldboot-sm-x910-twrp.zip`;
- ZIP SHA-256:
  `00275b0d3b06cb5953c6e22f4fe90b7975246cebb470f216d2083d08f008d754`.

Se escribieron únicamente `boot` y `vendor_boot`, con backups temporales y
lectura posterior idéntica a los orígenes. Los dos módulos ath12k resultantes
son byte a byte idénticos a los instalados, por lo que no se modificó la
microSD.

## Sesión 120 — v1.65–v1.71: dock DP conservado a través de reinicios

### El problema no era ya el encoder

v1.64 evitó el bootloop aplazando HPD hasta después de la recuperación del
panel, pero un dock alimentado conservaba una combinación válida y poco común:
el X910 era Sink de alimentación y DFP/Host de datos, mientras el dock era
Source/UFP. En un reboot el SM5714 retenía esos bits aunque el nuevo TCPM
partía desde unattached. Las iteraciones aislaron el problema sin romper el
hotplug ya validado:

- v1.65 capturó el rol retenido antes de registrar TCPM;
- v1.66 conservó Host durante hard reset. xHCI y el Logitech sobrevivían, pero
  el dock no reenviaba Source_Capabilities ni recreaba altmodes;
- v1.67 generó un detach CC físico local (Rp 200 ms, open 50 ms) antes de
  arrancar DRP. En un boot recuperó contrato y altmode, pero el HPD aplazado no
  alcanzó MSM DP;
- v1.68 reprodujo el HPD directamente con `msm_dp_bridge_hpd_notify()`;
- v1.69 hizo que `connected` ganase sobre un `disconnected` temporal durante
  el aplazamiento;
- v1.70 retrasó de 1,5 a 3 s la resincronización one-shot después del detach.
  No era la causa: el boot acabó Sink/Device, sin PD, altmode, xHCI ni vídeo.

Las trazas TCPM de v1.70 mostraron la frontera exacta. Se recibía un mensaje
`Source_Capabilities` de siete objetos. Los cuatro primeros eran utilizables
(5 V/3 A, 9 V/2,44 A, 15 V/2,66 A y 20 V/2 A), mientras los tres últimos se
decodificaban como PDO fijos absurdos y desordenados. Tras unos 659 ms, antes
de que saliese `Request`, aparecía `Received hard reset` y se reiniciaba la
negociación. Retrasar la resincronización no cambió nada.

### v1.71: vaciar RX como hace Samsung

El driver GPL downstream de Samsung contiene una operación que faltaba en el
transporte mainline: `sm5714_protocol_layer_reset()` escribe
`RX_BUF_ST=0x10` para vaciar el buffer antes de resetear el protocolo. v1.71
reproduce únicamente esa operación en `sm5714_usbpd_init()`. Es segura tanto
para cold boot como para hotplug porque ocurre antes de habilitar los IRQ y de
que TCPM arranque DRP.

El primer boot con el dock inmóvil produjo:

- kernel `#17`, Wi-Fi/SSH e imagen interna normales;
- `power_role=Sink`, `data_role=Host`, modo `usb_power_delivery`;
- contrato 9 V/1,66 A y el receptor Logitech con `PRO X 2 DEX` en el árbol
  input;
- altmode DP activo, pin D, HPD=1;
- `card1-DP-1=connected` y `enabled`, EDID de 256 bytes;
- greeter gris visible físicamente en la captura OBS a 1920×1080.

La traza sigue mostrando los tres PDO finales malformados, por lo que el flush
no «corrige» ni inventa capacidades. La diferencia medida es que TCPM procesa
inmediatamente los cuatro PDO fijos válidos, solicita 9 V/1,66 A, recibe
Accept/PS_RDY y completa Discover Identity/SVID/Modes/Enter Mode. Esto apunta a
estado RX/protocolo retenido —incluido el hard reset pendiente— como la causa
del bloqueo, no al contenido final de esos APDO.

Se hizo un segundo reinicio consecutivo sin tocar dock, cargador, HDMI ni
ratón. Repitió exactamente el mismo resultado: PD, Sink/Host, Logitech,
altmode activo y `DP-1 connected/enabled`. Tras una regeneración final de la
misma fuente se instaló el kernel `#18` y un tercer reinicio inmóvil repitió
PD, Host, ratón, altmode, EDID y greeter gris en OBS. El hotplug físico ya
validado no se modifica por este cambio.

Artefactos v1.71:

- kernel package r114;
- `boot.img`:
  `cb13c0fabbd9d28931d9a21c5c47360e9f27c9b6c1c4727cc99c6358cc4fea3f`;
- `vendor_boot.img` (sin cambios funcionales en esta iteración):
  `c4b93f02ced734c12d19448e0cd2fa724d382ee6d4ac6d55f95b6b8b1e36f79c`;
- ZIP:
  `postmarketos-edge-gnome-mainline-v1.71-dp-dock-coldboot-sm-x910-twrp.zip`;
- ZIP SHA-256:
  `10c6d6c811230b6c52e59f5e6f9ed41ed29ae7d285e3c8d1679c582db5695097`;
- módulos ath12k conservados:
  `c8bd1b4c…` y `897614d3…`.

Se escribió únicamente `boot` (`/dev/sda21`), dentro de la autorización
permanente de la usuaria para `boot`/`vendor_boot`, con backup temporal
final `/tmp/boot-before-v171-20260731-044946.img` y hash de lectura posterior
idéntico al origen. El backup contiene la primera build funcional v1.71,
`1ad33143…`; no se escribió ninguna otra partición ni la microSD.

## Sesión 121 — congelación de la baseline y preparación del relevo a Ubuntu

Se cerró postmarketOS v1.71 como baseline reproducible para iniciar un segundo
repositorio con userspace Ubuntu 24.04 LTS. No se cambió el kernel, el rootfs ni
la tablet física en esta sesión.

La portada había acumulado el detalle de varias sesiones de USB, DisplayPort,
carga y sensores. Se creó `docs/hardware-status.md` como referencia canónica
del estado actual y de las invariantes que debe heredar otra distribución. El
README queda reducido a una presentación, una matriz breve y enlaces a los
documentos técnicos. `development-notes.md` conserva sus tablas y actualizaciones
antiguas como archivo explícito, no como estado vigente.

También se actualizó `boot-strategy.md` con la cadena que funciona realmente:
rootfs ext4 en microSD, imágenes Android v4 en UFS, instalación en dos pasos,
iteración segura de `boot`/`vendor_boot` y recuperación por TWRP/Odin. Las guías
`testing-mainline-v0.md` y `upstream-audit.md` se marcaron como históricas para
que un agente nuevo no confunda los límites del prototipo v0.6 con v1.71.

Por último se vaciaron los directorios locales ignorados `artifacts/` y
`work/`, conservando sus ficheros de control versionados, y se retiró la copia
local regenerable del archivo fuente Samsung. Eran aproximadamente 26 GiB de
ZIP, imágenes, logs y scratch; no se eliminó ninguna fuente versionada. El hash
del ZIP v1.71 se conserva en `artifacts/README.md` y toda imagen debe volver a
generarse mediante los scripts y blobs verificados, no recuperarse de una
colección de builds obsoletas.
