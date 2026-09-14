# Estrategia actual de arranque y recuperación

Última revisión: 2026-07-31, baseline postmarketOS v1.71.

## Cadena de arranque demostrada

- El SM-X910 no usa slots A/B y Samsung ofrece Download Mode/Odin, no un
  `fastboot boot` utilizable.
- La cadena Android usa boot header v4.
- Samsung ABL carga el kernel desde `boot`, el initramfs desde `init_boot` y el
  DTB, cmdline y bootconfig desde `vendor_boot`.
- El rootfs Linux vive en una microSD ext4. ABL no busca el kernel en esa
  tarjeta.
- La DTBO stock contiene interfaces downstream y no se aplica sobre el DTB
  mainline. El bundle instala dos overlays no-op que conservan los selectores
  de placa Samsung.
- TWRP lleva su propio DTB/DTBO de recovery y sigue siendo recuperable aunque
  cambien las imágenes del sistema mainline.

## Particiones utilizadas

| Partición | Tamaño exacto | Contenido |
|---|---:|---|
| `boot` | 100663296 | `Image.gz`, header v4, sin ramdisk ni DTB |
| `init_boot` | 8388608 | initramfs postmarketOS |
| `vendor_boot` | 100663296 | DTB X910, cmdline, bootconfig y fragmento vendor vacío |
| `dtbo` | 16777216 | overlays no-op con los selectores Samsung |
| `vbmeta` | 131072 | AVB con verification/verity desactivados (`flags=2`) |

La instalación normal no toca `super`, `userdata`, recovery, bootloader, PIT,
EFS, persist, modem/modemst ni calibraciones. En el TWRP usado durante el port,
`vbmeta` es de solo lectura: el instalador verifica que ya contiene `flags=2`
y lo conserva.

## Instalación reproducible

La instalación siempre tiene dos pasos:

1. Borrar metadatos GPT antiguos de una microSD sacrificable con
   `sgdisk --zap-all`, escribir la imagen rootfs y verificar mediante hash lo
   leído de vuelta. La partición raíz se expande al primer arranque.
2. Flashear el ZIP TWRP correspondiente. Escribe `boot`, `init_boot`,
   `vendor_boot` y `dtbo`, y aplica sobre la tarjeta el overlay que contiene
   configuración y firmware generado localmente.

El firmware de GPU, ADSP y audio no forma parte de una imagen rootfs recién
creada. Hasta completar el segundo paso no se debe esperar aceleración ni
paridad de hardware.

`scripts/build-android-v4-bundle.sh` extrae `Image.gz` del EFI zboot instalado
por el mismo paquete que produjo los módulos. Reproduce los offsets validados,
añade footers AVB, comprueba tamaños de partición y genera hashes. El script de
build nunca flashea por sí solo.

## Iteración sobre un sistema arrancado

Los cambios de kernel o DTS pueden probarse escribiendo únicamente la imagen
estrictamente necesaria desde el sistema vivo, siempre con autorización:

- `boot` para el kernel;
- `vendor_boot` para DTS, cmdline o bootconfig;
- ambos cuando el kernel y los módulos ath12k formen un nuevo conjunto
  firmado.

Antes de cada escritura se hace un backup temporal, se comprueba el tamaño, se
usa `dd conv=fsync` y se compara el SHA-256 de origen y destino. Nunca se
codifican números `sdaN`: se usan enlaces estables de
`/dev/disk/by-partlabel/`. El kernel lockdown exige que `boot` y los módulos
ath12k aislados instalados en la microSD coincidan.

## Particularidades de arranque

- El panel ANA38407 no queda accesible tras el hand-off frío de Samsung. Antes
  de iniciar el display manager, el paquete de dispositivo ejecuta un único
  suspend/resume de plataforma que recupera DDIC, DPU y sesión gráfica.
- Si hay un dock DisplayPort ya conectado, su HPD se aplaza hasta terminar esa
  recuperación. v1.71 restaura después PD, USB host y salida DP sin reenchufar.
- La consola visible temprana no es un requisito funcional: ABL puede añadir
  `console=null` al cmdline. Diagnóstico persistente, journal y TWRP son las
  fuentes fiables.
- Los proveedores críticos del kernel se compilan built-in. Este port no
  instala ni autocarga un árbol general de módulos; solo distribuye los dos
  módulos ath12k firmados de forma aislada.

## Recuperación

Las vías de recuperación, por orden, son:

1. TWRP y `adb`, para montar la microSD, extraer journal y restaurar imágenes;
2. Download Mode y Odin con el firmware oficial;
3. ZIP estable anterior generado por el proyecto.

Las copias se restauran mediante `/dev/block/by-name/<partición>`, nunca con
números de LUN codificados. EFS solo puede montarse `ro,noload` para leer la
dirección Bluetooth; jamás se escribe.

## Futuro: rootfs en UFS y dual boot

La UFS enumera correctamente, pero el port estable mantiene el rootfs en
microSD. Un Ubuntu instalado en UFS o un dual boot requerirá antes un diseño
separado de layout, selector y recuperación. No se reparticionará UFS ni se
reutilizará `super` hasta que el nuevo userspace Ubuntu alcance paridad desde
microSD y exista un procedimiento reversible probado.

La historia del bring-up inicial y de sus fallos tempranos se conserva en
[testing-mainline-v0.md](testing-mainline-v0.md) y
[porting-log.md](porting-log.md); no describe el procedimiento actual.
