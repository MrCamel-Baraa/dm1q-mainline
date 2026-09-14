# Estado técnico consolidado del SM-X910

Última actualización: 2026-07-31, build postmarketOS v1.71.

Este documento es la referencia corta y actual del soporte de hardware. El
detalle cronológico, incluyendo intentos fallidos, está en
[`porting-log.md`](porting-log.md); las reglas, hechos permanentes y la lista
«no repetir» están en [`development-notes.md`](development-notes.md).

## Base validada

- Dispositivo: Samsung Galaxy Tab S9 Ultra Wi-Fi, SM-X910, `gts9uwifi`.
- SoC: Qualcomm Snapdragon 8 Gen 2, SM8550/kalama; GPU Adreno 740.
- Kernel: Linux mainline 7.2-rc3, commit fijado
  `a13c140cc289c0b7b3770bce5b3ad42ab35074aa`.
- Última build probada: v1.71, kernel package r114, device r44 y firmware r10.
- Escritorio probado: GNOME sobre Wayland; XFCE/Xorg queda como alternativa.
- Rootfs: microSD. Samsung ABL carga `boot` y el DTB/cmdline de `vendor_boot`
  desde la UFS interna.
- Recuperación: TWRP, Download Mode y Odin siguen disponibles.

Todo lo marcado como funcional fue comprobado en la tablet física. Que un
driver enlace o aparezca en sysfs no se considera una validación suficiente.

## Matriz detallada

| Componente | Estado | Implementación y límites relevantes |
|---|---|---|
| Arranque | ✅ | Android boot header v4, kernel mainline en `boot`, DTB/cmdline en `vendor_boot`, rootfs ext4 en microSD |
| Pantalla interna | ✅ | ANA38407/AMSA46AS02, 2960×1848 a 120 Hz, DSI command mode, DSC y TE. Necesita un suspend/resume de plataforma automático antes del display manager para recuperar el DDIC después de un cold boot |
| GPU | ✅ | Adreno 740 con Mesa/Freedreno/Turnip y OpenGL 4.6. GNOME usa `card0` como renderer y `card1` DPU para KMS |
| Brillo/blanking | ✅ | Backlight DCS y blanking de pantalla. El brillo automático no funciona |
| Táctil | ✅ | Goodix Berlin/GT9916 con layout Samsung de eventos de 16 bytes |
| UFS | ✅ | Las seis LUN `sda`–`sdf` enumeran. Se usa para las particiones de arranque, no como rootfs |
| microSD | ✅ | `sdhc_2`, rootfs actual en `mmcblk1p2`; el instalador puede ampliar la partición al primer arranque |
| Wi-Fi | ✅ | WCN7850/ath12k. Requiere des-aparcar el mux PIPE PCIe, firmware oficial y BDF QRD en ELF. La BDF Samsung HMT.2.0 no es compatible con el amss HMT.1.1 |
| Bluetooth | ✅ | WCN7850 por QUP SE14, firmware/NVM Samsung, dirección pública leída de EFS en solo lectura, bonds persistentes y A2DP verificado |
| Audio | ✅ | Cuatro CS35L45 por PRIMARY_MI2S, DMIC por VA macro, topología AudioReach y perfil UCM. Altavoces y micrófono comprobados acústicamente |
| Protección de altavoces | ❌ | No se carga todavía el firmware DSP de protección Cirrus; el volumen de hardware se mantiene conservador |
| Botones | ✅ | Power y volumen; el botón power suspende |
| Batería | ✅ | SM5714: porcentaje, voltaje, corriente y temperatura real del pack |
| Carga USB-PD/PPS | 🟡 | SM5714 TCPM + SM5440 2:1. Se midieron PPS y unos 2,8 A netos a batería al 78–82 %, pero a batería baja todavía se observan indicación intermitente y estimaciones lentas |
| USB gadget | ✅ | RNDIS a High Speed. En Windows hay que asignar manualmente el driver «Remote NDIS Compatible Device» en vez del driver ADB |
| USB host | ✅ | Hubs alimentados y bus-powered, HID Logitech, almacenamiento USB clásico y RTL8153 enumeran. El MUIC SM5714 debe encaminar D-/D+ antes del boost OTG |
| DisplayPort USB-C | ✅ | Altmode DP, pin D, HPD, EDID y 1920×1080@60 por capturadora. v1.71 conserva PD/Host/DP durante reinicios con el dock conectado |
| Ethernet por hub | 🟡 | RTL8153 con firmware cargado; falta probar enlace y tráfico con cable |
| UAS | ❓ | No probado: el pendrive disponible solo anuncia `usb-storage` |
| Suspensión | ✅ | Deep suspend/resume. El wake tarda normalmente 2–3 s. La funda y el botón power están probados |
| Funda/Hall | ✅ | GPIO107 expone `SW_LID`; cerrar suspende y abrir despierta, incluidos ciclos rápidos |
| Sensores de movimiento | ✅ | SSC/ADSP expone LSM6DSO y AK0991x; acelerómetro, giroscopio, magnetómetro, brújula y autorrotación están probados |
| Luz ambiental | ❌ | El SSC descubre dos STK31610 pero nunca emite lux. Registry, rails, modos de streaming y pruebas Samsung se agotaron sin resultado |
| Proximidad | — | El firmware SSC stock del X910 no instancia un sensor de proximidad |
| S Pen | ❌ | Wacom en I²C 0x56; falta adaptar/conectar `wacom_i2c` |
| Teclado pogo | ❌ | STM32 en I²C 0x2a; no hay driver mainline |
| Huella | ❌ | EgisTec EL7xx por SPI; no hay driver mainline |
| Vibración/hápticos | ❌ | Hardware aún no identificado ni descrito |
| Flash/linterna | ❌ | PM8350C; candidato `leds-qcom-flash` |
| Cámaras | ❌ | No iniciadas |
| Módem | — | No aplica al modelo Wi-Fi |

## Particularidades que debe heredar otra distribución

El soporte no depende de Alpine salvo las piezas explícitamente indicadas. Un
rootfs Ubuntu debe reutilizar:

1. el kernel, DTS, drivers y parches de
   `pmaports/device/testing/linux-samsung-gts9uwifi-mainline/`;
2. la config de kernel de ese paquete, manteniendo built-in todos los
   proveedores necesarios;
3. los blobs obtenidos mediante `scripts/stage-stock-*.sh`, nunca copiados al
   repositorio público;
4. UCM, reglas udev, servicios de recuperación del panel/SSC, Bluetooth y
   demás overlays que hoy se ensamblan desde `configs/` y el paquete de
   dispositivo;
5. el empaquetado Android v4 de `scripts/build-android-v4-bundle.sh` y el ZIP
   TWRP reproducible.

Piezas específicas de postmarketOS/Alpine que no deben copiarse sin revisar:

- APKBUILD, `pmbootstrap`, dependencias APK y hooks de instalación Alpine;
- el workaround de cuentas `gdm-greeter-*`, necesario porque Alpine compila
  systemd sin `systemd-userdbd`; Ubuntu 24.04 debe probar GDM nativo primero;
- parches Xorg/reverse PRIME si se usa GNOME/Wayland, porque Mutter maneja la
  topología GPU/DPU partida directamente;
- perfiles y nombres de paquetes: deben traducirse a paquetes Debian/Ubuntu.

## Invariantes y trampas

- Este port no instala un árbol general de módulos. Un proveedor que quede en
  `=m` normalmente no aparece; los componentes críticos son built-in y solo
  ath12k/ath12k_wifi7 se distribuyen como módulos aislados firmados.
- Cambiar el DTS exige actualizar `vendor_boot`: el ABL del X910 usa ese DTB,
  no el anexado a `boot.img`.
- `boot` y los módulos ath12k son un conjunto firmado bajo kernel lockdown.
- El panel necesita la recuperación cold-boot antes de iniciar GDM. Un HPD DP
  temprano debe permanecer aplazado hasta después de ese ciclo.
- No reactivar `lpass_ag_noc`: produjo bloqueos y el audio funciona sin él.
- No usar una BDF Wi-Fi Samsung despojada de su envoltorio ELF ni mezclarla con
  el amss oficial incompatible.
- El firmware propietario nunca se versiona. Los scripts fijan hashes y lo
  extraen del propio dispositivo o de la fuente Samsung.
- Nunca escribir PIT, EFS, persist, modem/modemst ni calibraciones. EFS solo se
  monta `ro,noload` cuando hace falta leer la dirección Bluetooth.

## Estado al congelar postmarketOS

La base pmOS v1.71 queda estable y reproducible. Los frentes de hardware que
merecerían trabajo adicional son, por prioridad aproximada:

1. revalidar carga rápida/estado de carga con batería baja;
2. UAS y Ethernet real;
3. S Pen, hápticos y accesorios pogo;
4. protección DSP de altavoces;
5. flash y cámaras;
6. ALS, únicamente si aparece una vía nueva para observar el bus dentro del
   DSP.

El siguiente proyecto cambia el userspace a Ubuntu 24.04 LTS manteniendo esta
base de hardware y el rootfs en microSD. Una instalación en UFS y un dual boot
quedan como diseño futuro, no como requisito inicial.
