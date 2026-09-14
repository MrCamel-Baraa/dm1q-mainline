# Notas de desarrollo

Este documento recoge el cuerpo del antiguo README, que durante el bring-up
funcionó como documento vivo: objetivo, estrategia, hechos de hardware
confirmados, reglas de seguridad, entorno de trabajo y —lo más útil— el
inventario de **lo que ha funcionado** y **lo que no hay que repetir**.

El historial cronológico sesión a sesión está en
[porting-log.md](porting-log.md). La portada del proyecto es el
[README](../README.md). El estado técnico vigente y la matriz de compatibilidad
canónica están en [hardware-status.md](hardware-status.md); las tablas e hitos
que siguen se conservan como contexto histórico del bring-up.

---

## Objetivo

Conseguir un Linux orientado al escritorio en la Samsung Galaxy Tab S9 Ultra
Wi-Fi (SM-X910, `gts9uwifi`, Qualcomm SM8550/kalama), con postmarketOS como
entorno de bring-up. El objetivo inmediato es arrancar un escritorio ligero,
mostrar correctamente la imagen y disponer de SSH. El objetivo de largo plazo
es un stack Linux convencional con DRM/KMS, Mesa/Turnip y la mayor
compatibilidad posible con software de escritorio ARM64, FEX y Proton.

Ubuntu Touch queda congelado como baseline de referencia en `../port/`; este
proyecto no modifica sus fuentes ni artefactos. Desde 2026-07-18 la usuaria no
requiere conservar la instalación física de UT: se prioriza evitar un brick y
mantener TWRP/Download Mode/Odin, no preservar su boot chain o userdata.

## Estrategia

Se adopta una estrategia **mainline-first**. El kernel upstream, DRM/KMS y
Mesa/Turnip serán la única base de ejecución del nuevo port. El kernel Samsung
5.15.153 funcional no se adaptará como etapa intermedia: se usará como
referencia documental para reconstruir el hardware de la placa (panel, DTBO,
GPIO, reguladores, táctil, firmware y secuencias de alimentación).

Esta decisión puede retrasar la primera salida gráfica, pero evita construir un
segundo sistema atrapado en KGSL/libhybris. Los hitos se aceptan en este orden:

1. kernel mainline arrancando con consola/logs;
2. almacenamiento y rootfs en microSD;
3. red y SSH, inicialmente incluso sin pantalla;
4. DRM/DSI, panel y táctil;
5. escritorio ligero y Turnip;
6. resto del hardware.

La opción preferida de prueba es conservar el sistema en la microSD y cambiar
el mínimo de particiones internas. Antes de afirmar que esto es posible hay que
verificar que el controlador de la microSD y el filesystem elegido estén
integrados en el kernel o disponibles en el initramfs. En Samsung normalmente
no existe `fastboot boot`; no se asumirá que hay arranque temporal hasta
demostrarlo en este dispositivo.

## Estado consolidado durante el bring-up (archivo)

> Esta tabla refleja hitos acumulados en distintas versiones y no debe usarse
> como resumen vigente. Para el estado final v1.71 consulta
> [hardware-status.md](hardware-status.md).

| Componente | Estado |
|---|---|
| Workspace y documentación | ✅ Inicializados |
| Baseline Ubuntu Touch | 📚 Fuentes intactas; boot físico ya reemplazado en la prueba mainline |
| Identidad y boot chain SM-X910 | ✅ Inventariadas desde firmware X910XXS5CYG1 |
| Kernel downstream 5.15.153 | 📚 Sólo referencia de hardware; no será la base pmOS |
| Kernel mainline SM8550 | ✅ v0.45 validada físicamente: el des-aparcado del mux PIPE levanta el enlace (`PCIe Gen.2 x2 link up`) y `17cb:1107` enumera con ath12k |
| DTS `gts9uwifi` | ✅ v0.73 validada en vivo: además de WCN7850, Goodix, GPU, DSI/DSC y UFS, describe cuatro CS35L45, PRIMARY_MI2S, VA DMIC y power/volumen; los nodos aparecen y sus bloqueos actuales son proveedores kernel identificados |
| Acceso temprano a microSD | ✅ Mainline enumera físicamente `mmcblk1`, `mmcblk1p1` y `mmcblk1p2` |
| Paquetes pmaports | ✅ v1.71 validada físicamente con kernel r114/device r44. Kernel r114 integra la cadena DP cold-boot y el vaciado de RX del SM5714; device r44 añade `linux-firmware-rtl_nic` más la creación explícita de `multi-user.target.wants`. Firmware r10, GNOME Control Center r2, Mutter r6, iio-sensor-proxy r3 y Xorg r10 siguen reproducibles. Solo ath12k/ath12k_wifi7 se instalan como módulos aislados en el release directo; SM5714 TCPM, USB host, HID genérico/Logitech, QMP combo, PS5169 y DP permanecen built-in |
| Rootfs postmarketOS | ✅ v0.27 limpio generado con XFCE4/OpenSSH y módulos completos; el ZIP actualiza la SD física existente |
| Escritorio | ✅ XFCE/LightDM a 2960×1848@120; escalado integral 2× (GTK, greeter, Onboard, panel, iconos y cursor), login completo y Adreno acelerada por reverse PRIME |
| Wi-Fi | ✅ **v0.49 validada físicamente**: amss oficial + BDF QRD en ELF → `wlan0` conectada (señal 65, 270 Mbit/s). RF nativo Samsung DESCARTADO: su BDF HMT.2.0 crashea el amss oficial HMT.1.1 (MHI RDDM); la QRD es final |
| SSH | ✅ **Acceso en vivo por WLAN**: `<TABLET_IP>`, host key `1N9kAKdf…` verificada, clave de desarrollo Ed25519 como `phablet`. El canal USB (Code 43) queda como secundario |
| Táctil | ✅ v0.32 validada físicamente: responde correctamente con el arreglo Goodix completo |
| Bundle Android v4 | ✅ v0.27 empaquetado con appended-DTB, LZ4 legacy/AVB y overlay con modos POSIX para la microSD existente |
| Restauración Ubuntu Touch | ✅ ZIP boot-only v8/DTBO stock generado y validado |
| Imagen/paquete de prueba | ✅ **v1.71 validada**: conserva host USB alimentado y pasivo, almacenamiento clásico y DisplayPort. Dos reinicios consecutivos con el dock alimentado sin mover restauraron contrato PD 9 V/1,66 A, Sink/Host, Logitech, altmode DP y salida 1920×1080 por capturadora. Un pendrive USB 2.0/FAT32 automonta y lee 128 MiB a 20,4 MB/s sin errores. Faltan enlace Ethernet y UAS |
| Display nativo | ✅ ANA38407/AMSA46AS02 2960×1848@120, DSI command mode + DSC + TE. El hook LightDM descubre providers/output, asocia reverse PRIME y fuerza un ciclo DSI; validado visualmente después de reinicio completo |
| UFS interno | ✅ **v0.59**: `ufshcd-qcom` enumera las seis LUN `sda`–`sdf`; `boot=/dev/sda21`, `vendor_boot=/dev/sda24`, `dtbo=/dev/sda30` accesibles desde pmOS |
| GPU Adreno 740 | ✅ **Aceleración del display resuelta**: `card0=adreno` es el X screen glamor/FD740 y `card1=msm_dpu` el Sink Output reverse PRIME. DRI3 importa dma-bufs implícitos como LINEAR; `glxinfo` confirma aceleración y `glmark2` se ve físicamente a pantalla completa sin faults |
| Bluetooth WCN7850 | ✅ **Validado de extremo a extremo (sesión 81)**: QUP SE14, firmware `hmtbtfw20.tlv`, NVM Samsung `hmtnv20.b21`, dirección pública nativa de EFS. Bonds persistentes (Buds2 Pro + móvil), sink A2DP clásico creado y audio real confirmado (YouTube en Chromium por los Buds). Servidor de sonido = PulseAudio 17. HID sin probar por falta de periférico BT |
| Audio interno | ✅ **COMPLETO (v0.88)**: los cuatro CS35L45 suenan y los DMIC captan, confirmado físicamente. Claves: topología reapuntada a `I2S_SD1` (el playback sale por gpio128/`tdm0_dout`, no por SD0), la machine driver ahora fija formato **y sysclk** del códec (programa el PLL del amplificador) y una regla udev evita que los amps hibernen y pierdan la configuración. Micro: carril `VA_CODEC_DMA_TX_0`, `qcom,dmic-sample-rate` y el rail de bias `vreg_l10b_1p8` always-on (el driver declara `vdd-micb` pero no lo rutea) |
| Audio de sistema | ✅ Perfil **UCM** propio → PulseAudio expone «Built-in speakers (4x CS35L45)» y el micro; todas las apps suenan y el volumen del escritorio funciona. Deslizador limitado a 100 % (XFCE amplifica por software por encima de 0 dB) y volumen de hardware con margen: **no está cargado el firmware de protección de altavoces** de Cirrus |
| Botones | ✅ vol+/vol−/power. `pwrkey` y `resin` son hijos del nodo PON, cuyo padre (`POWER_RESET_QCOM_PON`) estaba `=m`; built-in los crea. El power lo capturaba xfce4-power-manager sin acción asignada → configurado a suspender |
| Carga rápida | ✅ v1.32: SM5714 USB-PD + TCPM negocian PPS con el EP-T4510 y el SM5440 trabaja como bomba 2:1. Keepalive PPS cada 2 s, termistor externo real y fallback automático a carga conmutada. Medidos ~2,8 A netos a batería al 78–82 %, sin calentamiento del pack |
| Nombres comerciales | ✅ Fastfetch y GNOME About muestran «Qualcomm Snapdragon 8 Gen 2» y «Qualcomm Adreno 740» sin sustituir la identidad técnica global del kernel |

## Resumen histórico de hitos (archivo)

> Las entradas siguientes eran actualizaciones del «reto en curso» en el
> momento en que se escribieron. Se mantienen porque documentan decisiones y
> resultados negativos, pero el foco vigente está en
> [hardware-status.md](hardware-status.md).

**Actualización sesión 120:** v1.71 cierra el arranque con el dock DP ya
conectado. El SM5714 y el partner conservan estado a través de un reinicio; las
v1.65–v1.70 demostraron que conservar solo Host, retrasar la resincronización o
reproducir un HPD obsoleto no bastaba. La solución final combina un flanco CC
real con el vaciado `RX_BUF_ST=0x10` que usa el driver GPL de Samsung antes de
reiniciar el protocolo. En dos reinicios seguidos sin tocar el cable aparecieron
el contrato 9 V/1,66 A, Sink/Host, el Logitech, el altmode pin D con HPD alto,
EDID de 256 bytes y `DP-1 connected/enabled`; OBS mostró el greeter por la
capturadora. El siguiente frente es UAS con un SSD capaz y luego la carga
inestable con batería baja.

**Actualización sesión 117:** v1.60 cierra el host USB sin alimentación externa.
El SM5714 abre la ruta D-/D+ del MUIC antes del boost y TCPM reconoce el VBUS
generado por el propio cargador; el hub Genesys, RTL8153 y Logitech enumeran
desde arranque y tras recrear xHCI. GNOME mantiene
`PanelOrientationManaged=true`. Device r44 añade
`linux-firmware-rtl_nic`; tras instalarlo en vivo y reenlazar r8152,
`ethtool -i` confirma `rtl8153a-3 v2 02/07/20`. Falta medir enlace/tráfico con
cable.

La build limpia también queda reparada: kernel r103 corrige los contadores
malformados de `ignore-console-null.patch`, y device r44 crea
`multi-user.target.wants/` antes de su primer enlace. Ambos paquetes se
construyen de principio a fin. El almacenamiento masivo clásico queda validado:
un pendrive USB 2.0 crea su disco SCSI, GNOME automonta FAT32 y una lectura
directa de 128 MiB termina a 20,4 MB/s sin errores. UAS sigue pendiente porque
esa unidad solo anuncia `usb-storage`. El reto inmediato es una pantalla
DP-altmode y, si aparece un SSD compatible, UAS; después se reabre la carga a
batería baja, que el contrato PD del hub no valida.

**Actualización sesiones 111–113:** USB gadget/RNDIS funciona a High Speed cuando
Windows usa el driver RNDIS y no el ADB. v1.33 añade DRP/host, boost OTG
SM5714 a 5,1 V/900 mA y drivers built-in para almacenamiento, UAS, Ethernet y
audio USB. v1.34 habilita QMP USB3/DP, SBU y PS5169 (`69:87` medido), pero una
cadena DRM transparente sin terminador difirió `mdss_dp0` y bloqueó también el
DSI interno. v1.35 repitió el bloqueo. El journal recuperado de v1.36 corrigió
el diagnóstico inicial: sí llegó a userspace y a Wi-Fi, pero GNOME no encontró
ninguna GPU con salida por la cadena DRM rota. v1.37 elimina ese bridge y
permite que el bridge nativo MSM DP continúe cuando solo falta la cola DRM
opcional de USB-C; DPU enlaza DSI+DP y GNOME vuelve a arrancar. v1.38 restaura
`CC_CNTL3=0x80` al salir de `OPEN`, tal como hace Samsung. v1.39 resuelve la
carrera de attach inicial con una resincronización diferida de TCPM: se han
medido `CC_STATUS=0x31`, `port0-partner`, `orientation=reverse`, sink/device y
gadget configurado. v1.40–v1.44 estabilizan el rol source/host con un dongle
pasivo: VCONN y boost 5,1 V/900 mA permanecen encendidos y xHCI conserva sus
dos root hubs. El receptor no enumera y el PTN3222 queda en host
`Connect Detect` (`0f=0e`, `10=01`), por lo que falta el evento eléctrico
downstream. v1.45 reproduce el pulso stock `usbpd,otg_det` de GPIO89 durante
130 ms; queda pendiente validarlo tras un unplug/replug físico. Después se
medirán dongles alimentados y finalmente DP altmode con una pantalla real.

✅ Los hitos de arranque, microSD, Wi-Fi/SSH, táctil, escritorio, DRM/DSI,
Turnip y ahora el controlador Bluetooth están cumplidos sobre Linux mainline
7.2-rc3. La tablet está arrancada con v0.72; el login es visible a
2960×1848@120 con escalado 2×, Wi-Fi/SSH/BT funcionan y el ADSP queda `running`.

Trabajo actual (con canal de control en vivo por SSH y UFS):

1. **Bluetooth de extremo a extremo — ✅ CERRADO (sesión 81).** Bonds
   persistentes; sink A2DP clásico de los Buds2 Pro creado y audio real
   confirmado (YouTube en Chromium). Servidor = PulseAudio 17. HID sin probar por
   falta de un ratón/teclado BT. No reinvestigar UART/firmware/dirección.
2. **Brillo — ✅ funciona** (`/sys/class/backlight/ae94000.dsi.0`, 0..4095, DCS
   0x51; atenuación verificada por cámara). **Blanking DPMS — ✅ arreglado
   (sesión 81):** xfce4-power-manager reactivaba el DPMS (`dpms-on-ac-off=17`) y
   el ANA38407 no resume de un blank → warm-black irrecuperable salvo reinicio de
   lightdm. El autostart HiDPI ahora deshabilita el DPMS de xfce4-power-manager;
   verificado `DPMS is Disabled` en la sesión de usuario. **Pendiente:** el
   suspend/resume REAL del panel (que un blank pueda re-encender el OLED).
3. **Audio interno (Tarea 3) — 🟡 EN CURSO, v0.73 diagnosticada en vivo y
   v0.74 en build (sesión 84).** El
   **ADSP arranca y autentica** en mainline: configs remoteproc PAS `=y`
   (`QCOM_Q6V5_PAS/COMMON`, `RPROC_COMMON`, `SYSMON`, `RPMSG_QCOM_GLINK_SMEM`),
   nodo `&remoteproc_adsp` con `firmware-name = "qcom/sm8550/adsp.mdt",
   "qcom/sm8550/adsp_dtb.mdt"` (el `adsp_dtb` es obligatorio: `dtb_pas_id=0x24`).
   Firmware Samsung extraído de apnhlos → paquete `firmware-samsung-gts9uwifi` r6
   y rootfs. PAS secure-boot lo acepta (a diferencia de la BDF de Wi-Fi):
   `remote processor adsp is now up`. Lo arranca el service
   `gts9uwifi-adsp-boot` tras montar el rootfs. **Descubrimiento clave:** el ABL
   del X910 aplica el DTB de **vendor_boot** (no el anexado en boot.img) → para
   cambios de DTS hay que reflashear `vendor_boot` (sda24), no basta `boot`.
   El FDT oficial de la X910 demuestra que el hardware es **4× Cirrus CS35L45**
   sobre I2C18 + PRIMARY_MI2S (GPIO126/129/127/128), con DMIC directos al VA
   macro; la hipótesis WCD938x/WSA88x queda descartada. v0.73 fuerza
   `SND_SOC`, GPR/AudioReach q6apm, VA macro, machine SM8550 y CS35L45 a `=y`;
   añade los cuatro códecs y la tarjeta al DTS; empaqueta el firmware DSP
   Samsung y `SM8550-HDK-tplg.bin` como el nombre exacto que solicita q6apm:
   `qcom/sm8550/Samsung-Galaxy-Tab-S9-Ultra-tplg.bin`. El interconnect LPASS se
   mantiene elidido hasta observar si el PCM DMA realmente lo necesita: habilitar
   `lpass_ag_noc` ya causó bloqueos históricos y no se mezclará con el primer
   arranque ALSA. v0.73 se escribió con verificación por UFS y arranca sin
   regresiones, pero no crea tarjeta ALSA. v0.74 puso built-in `QRTR_SMD`, los
   pinctrl LPASS-LPI y `GPIO_SHARED_PROXY`, lo que quitó los `-EPROBE_DEFER`
   iniciales pero dejó dos bloqueos reales.
   **v0.75 (sesión 86) resuelve el primero — PDR.** El transporte QRTR ya estaba
   bien (`qcom_smd_qrtr` en `IPCRTR`, `qcom,apr` en `adsp_apps`); lo que faltaba
   es que **nada en el kernel responde al servicio QMI *servreg locator***: lo
   provee el daemon de espacio de usuario **`pd-mapper`**, que no estaba
   instalado. Y `pd-mapper` no busca los mapas en rutas fijas: lee
   `/sys/class/remoteproc/*/firmware` y escanea **ese mismo directorio**, así que
   los `*.jsn` deben ir junto a `adsp.mdt`. Con `adspr/adsps/adspua/cdspr.jsn`
   del apnhlos en `/usr/lib/firmware/qcom/sm8550/` (`adspua.jsn` mapea
   `avs/audio` → `msm/adsp/audio_pd`) aparecen `gprsvc:service:2:1/2:2`, enlazan
   `qcom-sm8550-lpass-lpi-pinctrl` y `va_macro`, y `sound` pasa de «error getting
   cpu dai name» a «codec dai not found». Reproducible: firmware r8 empaqueta los
   mapas, `pd-mapper` entra en `depends` del paquete de dispositivo y un drop-in
   lo ordena tras `gts9uwifi-adsp-boot.service`.
   **Sigue abierto el segundo — el I2C de los CS35L45.** El `-110` es un timeout
   del **bus** (`wait_for_completion_timeout`, 1 s), no del poll OTP: un ftrace
   muestra una sola transacción con `i2c_result ret=-110`. Descartados con
   evidencia: bus equivocado (el DT stock pone los amps en `i2c@998000` =
   `i2c_hub_6`), reset (ftrace: `gpio 578` 0→1 con sus 2 ms), rail (`tlmm19` out
   high, `dummy_vreg` es la única alimentación también en el stock), pinmux
   (`i2chub0_se6` func1), IRQ (línea 154 incrementa), relojes (GCC se escribe
   antes de cada transferencia) y drive-strength (igualado a los 8 mA del stock en
   v0.75, sin cambio). **Pendiente inmediato:** por qué los amplificadores no
   contestan; pista: el DT stock agrupa `gpio19` con `gpio18` y con
   `gpio14`+`gpio86` en estados pinctrl que mainline no reproduce. Obtener tarjeta
   ALSA y PCM antes de probar altavoces y micrófonos acústicamente. No reactivar
   aún el interconnect LPASS.
4. **Botones (Tarea 3).** v0.73 añade power vía PMK8550 PON,
   volumen-abajo por resin y volumen-arriba por PM8550 GPIO6. `gpio-keys`
   aparece como `event1`; PON power/resin todavía no crean input. Sólo tras
   estabilizar el audio se pedirá a la usuaria la prueba física.
   Después: sensores, USB Code 43 y cámaras. UFS permite iterar por SSH sobre
   `boot`/`vendor_boot`; TWRP/Download Mode quedan como recuperación.
5. **Batería y carga (Tarea 5) — RESUELTO en v1.32 (sesión 110).** El camino
   Qualcomm (`pmic_glink`/`qcom_battmgr`) está descartado: exige el dominio
   `msm/adsp/charger_pd` por PDR y el firmware Samsung no lo publica. El
   hardware real es un **Silicon Mitus SM5714** en `i2c_hub_8` (0x9a0000):
   cargador 0x49, fuel gauge 0x71, MUIC 0x25; el bloque USB-PD está aparte en
   `i2c_hub_9` 0x33. Mainline no tiene driver, así que se añade
   `sm5714_battery.c` con el mapa de registros del fuente downstream de
   Samsung. La primera versión era solo lectura, pero se demostró que el
   shutdown de Samsung puede dejar `ENQ4FET=0`, límite de entrada 500 mA y
   corriente rápida mínima: VBUS seguía presente mientras la batería se
   descargaba. v1.14 clasifica SDP/CDP/DCP por el MUIC, reproduce la rampa
   segura de Samsung y restaura para DCP `VBUSCNTL=0x44` (1800 mA) y
   `CHGCNTL2=0x86` (2100 mA). El sondeo de un segundo actualiza UPower y se
   cancela durante suspend para no transferir por I2C con el bus apagado.
   Validado inyectando el estado averiado: en dos segundos volvió
   `CNTL1=0x6c`, `Charging` y corriente positiva.
   v1.32 añade un TCPC propio para el SM5714 y registra el puerto en TCPM.
   Descubre correctamente el cargador Samsung EP-T4510 (PDO fijos y APDO PPS
   hasta 11 V/5 A). El SM5440 está en `i2c_hub_3` por GSI, porque reutilizar el
   controlador PIO rompía el SSC. Su driver configura la bomba 2:1, abre Q4,
   solicita un punto PPS próximo a `2×VBAT+700 mV`, espera que el ADC confirme
   el VBUS físico y refresca la petición cada dos segundos. Ese keepalive es
   obligatorio: sin él el adaptador abandonaba PPS a los cinco segundos y
   `REVBLK` apagaba la bomba. En hardware se midieron unos 2,8 A netos hacia la
   batería al 78–82 %, pack estable alrededor de 35 °C y transición normal a
   CV cerca del 85 %. Al 90 % apagó la bomba, devolvió TCPM a 9 V fijo y
   restauró Q4; al 93 % siguió cargando a unos 0,46 A. El límite de 1,8 A del
   SM5440 queda conservador; falta
   cuantificar la potencia pico con la batería baja, no demostrar que PPS o la
   bomba funcionen.
6. **Rotación persistente y punteros externos — RESUELTO en Mutter r6.** Mutter usaba
   un solo `inhibited_count` tanto para el ajuste del usuario como para las
   transiciones temporales de panel administrado. Si
   `orientation-lock=true` se cargaba antes de que apareciese el acelerómetro,
   el `uninhibit` tardío del panel consumía el bloqueo; la UI seguía bloqueada
   pero había que activar y desactivar de nuevo el control. El booleano
   `orientation_locked` ya existía: r5 lo convierte en condición independiente
   de `sync_accelerometer_claimed()` y deja el contador solo para inhibidores
   anónimos. El instalador persistente y los cuatro APK del overlay deben
   coincidir en r6; de lo contrario el servicio de arranque reinstala una
   versión anterior. r6 modifica además `update_panel_orientation_managed()`:
   la X910 es una slate fija, así que la presencia de un ratón no debe convertir
   el heurístico del asiento en «portátil sin modo tablet». Mientras existan el
   acelerómetro y el panel integrado, conserva
   `PanelOrientationManaged=true`.

Hito recién cerrado — **HiDPI/120 Hz y Bluetooth reproducibles (sesiones 76–80)**:

- El escalado correcto no es subir sólo Xft DPI: se fija GTK window scale 2,
  cursor 32, panel 36, iconos 48, Onboard de usuario 230 y Slick Greeter con
  HiDPI real/Onboard 420. `display-setup-script` ejecuta el hook reverse PRIME
  antes del greeter, evitando el teclado recortado por la geometría 320×200.
- PRIME Synchronization queda en 0 para esta topología de dos DRM: a 1 limitaba
  GLX a 27–30 FPS; a 0 `glxgears` mide 117–118 FPS mientras DSI escanea a 120 Hz.
- Bluetooth usa QUP SE14 con `&qupv3_id_1` activo. El NVM genérico falla con
  `-52`; `hmtnv20.b21` es el NVM Samsung validado. Al ser `hci_qca` built-in,
  patch+b21 viven temprano en el vendor ramdisk bajo **`/usr/lib/firmware/qca`**.
- La dirección del NVM es nula. `gts9uwifi-bluetooth-address.service`, ordenado
  antes de BlueZ, monta `efs` con `ro,noload`, valida `bluetooth/bt_addr`, desmonta
  y la aplica con `btmgmt public-addr`. Tras reinicio, `hci0` es Primary,
  `missing options` está vacío y un escaneo de 12 s detectó equipos BR/EDR y BLE.
- v0.69 **NO DEBE FLASHEARSE**: el overlay temprano se colocó en `/lib`, pero el
  initramfs tiene `lib -> usr/lib`; la segunda CPIO intentó crear un directorio
  sobre ese symlink y provocó reset antes de journald. v0.70 lo corrigió usando
  `/usr/lib/firmware/qca` y recuperó el arranque.
- Un posterior bucle de LightDM no era una regresión gráfica: la rootfs estaba
  al 100 % por `/home/phablet/v067` y `v068` (192 MiB cada uno), por lo que el
  greeter no podía escribir `.Xauthority`. Se retiraron sólo esos temporales y
  quedaron 341 MiB libres; el login volvió completo. El instalador Xorg ahora
  usa `apk list -I` y es idempotente.

Hito recién cerrado — **aceleración del display nativo (sesiones 73–75)**:

- Se conserva `msm.separate_gpu_kms=1`: un pequeño parche kernel hace que la
  DRM render-only Adreno exponga recursos KMS vacíos, límites 16384×16384,
  dumb buffers y framebuffer funcs. Esto basta para que Xorg la acepte como
  primary connectorless; el DPU separado queda como provider Sink Output.
- Xorg r10 añade, de forma opt-in, `AllowEmptyInitialConfiguration`, un modo
  sintético 2960×1848 y guardas RandR para cero outputs. El primary Adreno usa
  glamor; el hook de LightDM asocia dinámicamente Source/Sink y activa el DSI.
- La barrera final era DRI3: Mesa usa el `PixmapFromBuffer` heredado y entrega
  modifier implícito `INVALID`. Con `dmabuf_capable` y el switch específico
  `force_linear_dri3`, Xorg lo trata como `DRM_FORMAT_MOD_LINEAR`; el import GBM
  funciona y desaparece `BadAlloc`. La instrumentación temporal r6–r9 se retiró
  del r10 de producción.
- Validación física: `glxinfo` → freedreno FD740, `Accelerated: yes`; `glmark2`
  2960×1848 visible en el OLED central (no en el monitor del PC), 113–153 FPS
  en las primeras escenas y sin GPU fault/hangcheck/DRM error. Tras un reinicio
  completo volvieron solos Wi-Fi/SSH, LightDM, DSI, Goodix y la aceleración.
- v0.66 lleva el APK r10 dentro del overlay y un `ExecStartPre` local que lo
  instala antes de LightDM, por lo que el arreglo no depende de la instalación
  viva y también se aplica sobre una microSD/rootfs limpia.

Historial de tareas anteriores:

1. RF nativo Samsung — **CERRADO NEGATIVO** (sesión 68): un arranque limpio de
   prueba en vivo (con rollback autónomo) demostró que la BDF Samsung se
   encuentra y descarga bien, pero el amss oficial HMT.1.1 **crashea (MHI
   RDDM)** al parsear la board data HMT.2.0. La QRD queda como BDF final.
2. Retirar el debug de bring-up — **✅ HECHO Y VALIDADO FÍSICAMENTE (v0.50,
   kernel r28)**: dropeados los parches de diagnóstico y `CONFIG_ATH12K_DEBUG`,
   consolidados los arreglos WCN en `wcn7850-pwrseq-cold-reset-aop.patch`
   funcional-only. Flasheado por `twrp install`; en vivo el kernel corre
   limpio (dmesg sin `SM-X910`) con Wi-Fi, táctil y escritorio intactos.
3. GPU + DRM/KMS nativo (Adreno 740, panel DSI, Mesa/Turnip) — **✅ CERRADO EN
   v0.66**. El bloque siguiente conserva los primeros hallazgos históricos de
   v0.52/v0.53 que desbloquearon el render node:
   - **`-110` (resuelto en v0.52)**: el gpucc no tenía driver porque
     `CONFIG_GPUCC_SM8550` *no existe* — el símbolo real es
     **`CONFIG_SM_GPUCC_8550`**, y además venía en `=m` (este port no autocarga
     módulos). Con `=y`, en vivo: `3da0000.iommu` sondea (`SMMUv2`, 22 context
     banks), `gpu_cc-sm8550` ligado con 21 relojes, `adreno` ligado a
     `3d00000.gpu`. La build ahora **falla** si un símbolo del fragment es
     desconocido o queda deshabilitado, para que no se repita.
   - **Sin render node (v0.53)**: `adreno_probe()` sólo crea su propio DRM si
     `msm_gpu_no_components()`, que devuelve el parámetro de módulo
     `separate_gpu_kms` (false por defecto); si no, hace `component_add()` y
     espera un component master que **sólo crea el mdss**, deshabilitado aquí a
     propósito. Solución: `msm.separate_gpu_kms=1` en la cmdline.
   Sigue aplicando: `DRM_MSM` no sube a `=y` mientras `QCOM_LLCC/OCMEM` sean `=m`
   (un tristate no supera una dependencia `=m`) → `QCOM_LLCC=y` + `QCOM_OCMEM=n`.
   El reinicio-a-recovery por software no funciona en este Samsung y **el kernel
   mainline no ve el UFS interno**, así que cada flash necesita TWRP a mano.

Pendientes posteriores: Bluetooth (mismo PMU WCN7850, `bt-enable` GPIO81), el
USB Code 43 como canal secundario, audio y sensores.

- sesión 67 construye de forma determinista `samsung-board-2.bin` con el
  boardname exacto X910 y el `bdwlan.elf` completo. Su estructura API-2 se
  validó contra el contenedor oficial. La primera prueba por unbind/rebind
  PCI en vivo no recuperó `wlan0`; el watchdog restauró el fichero estable,

- sesión 67 construye de forma determinista `samsung-board-2.bin` con el
  boardname exacto X910 y el `bdwlan.elf` completo. Su estructura API-2 se
  validó contra el contenedor oficial. La primera prueba por unbind/rebind
  PCI en vivo no recuperó `wlan0`; el watchdog restauró el fichero estable,
  pero el reenlace en caliente tampoco devolvió SSH. Esto no demuestra aún
  incompatibilidad de la BDF: el WCN7850 puede no admitir reprobe sin un
  power-cycle limpio. Hace falta reiniciar, recuperar SSH con la QRD y leer
  `gts9uwifi-native-bdf-test` antes de decidir una prueba de arranque limpio;

- v0.11 queda validada físicamente: ejecuta `/init`, monta `pmOS_boot` y
  `pmOS_root`, arranca systemd, LightDM y XFCE4, y conserva correctamente el
  framebuffer del bootloader. El arreglo LZ4 era la barrera exacta;
- el journal v0.12 extraído en sólo lectura demuestra que `gpi_dma1` ya permite
  sondear I2C4: Goodix registra `Goodix Berlin Capacitive TouchScreen` como
  `input0`. Cada paquete se rechaza después con `touch data checksum error`;
- el journal v0.13 corrige la hipótesis anterior: el firmware PID `6936`
  anuncia `event layout 8/8`, pero los dumps muestran que el checksum está
  después de 16 bytes y el driver Samsung usa incondicionalmente ese tamaño.
  v0.14 fuerza 16 sólo para PID 6936 y conserva el formato upstream normal;
- el journal v0.12 fija la cadena USB diferida en PTN3222 y registra
  `pin_config_group_set op failed for group 3`. El reset PM8550VS-D GPIO4
  copiaba `drive-strength`, no aceptado por `qcom-spmi-gpio`; v0.13 reproduce
  el estado stock con `qcom,drive-strength`, `power-source`, entrada/salida,
  push-pull y bias deshabilitado;
- la prueba física v0.13 sigue llegando a LightDM, pero el táctil no responde.
  Windows no enumera ADB, ACM ni NCM/RNDIS y conserva dos errores de descriptor;
  tampoco responde `172.16.42.1:22` ni apareció otro SSH en la LAN, excluyendo
  expresamente `.138` y `.150`, que son otros dispositivos conocidos;
- el journal v0.13 demuestra que el pinctrl ya funciona y el PTN3222 deja de
  estar diferido, pero DWC3 falla el soft reset. El driver mainline sólo saca
  el repetidor de reset; Samsung además escribe `06=20`, `07=21`, `08=63` y
  `0a=01`. v0.14 aplica esa secuencia I2C exacta tras esperar 4–5 ms;
- la prueba física v0.14 vuelve a LightDM, pero el táctil no responde. Windows
  conserva dos errores de descriptor, sin ADB/ACM/NCM/RNDIS; no responde
  `172.16.42.1:22` ni apareció otro SSH en la LAN al excluir `.138` y `.150`;
- el journal v0.14 extraído en sólo lectura confirma `event layout 8/16` y
  elimina por completo los errores de checksum. Al tocar, la lectura inicial
  de 42 bytes bloquea GPI-I2C con `-ETIMEDOUT`; las lecturas de 26 bytes de
  v0.13 sí completaban. v0.15 prelee sólo un contacto (26 bytes para Samsung)
  y recupera el resto únicamente cuando el contador indica multitáctil;
- el mismo journal confirma `applied 4 register overrides` en PTN3222, pero
  DWC3 sigue fallando `DCTL.CSFTRST`. Como el DTS elimina la PHY SuperSpeed,
  faltaba `qcom,select-utmi-as-pipe-clk`: el glue Qualcomm la usa para
  alimentar PIPE desde UTMI antes de registrar el core. v0.15 lo añade;
- la prueba física v0.15 confirma que Goodix ya reporta toques: tocar arriba
  activa abajo, por lo que falta invertir el eje Y tras el intercambio de ejes.
  USB no enumera NCM/RNDIS, conserva dos errores de descriptor y no hay SSH en
  `172.16.42.1`, `.151` ni en la LAN excluyendo `.138`/`.150`;
- el journal v0.15 extraído en sólo lectura demuestra que UTMI-PIPE resolvió el
  soft reset: no hay error DWC3, configfs enlaza el gadget, existe `usb0` con
  `172.16.42.1`, DHCP arranca y `sshd` escucha en todas las interfaces. El fallo
  restante está en la señal física/PHY porque Windows no puede leer descriptor;
- el driver Samsung funcional difiere del mainline sólo en dos detalles de esa
  inicialización relevante: espera 10 µs tras afirmar `POR` y programa
  `PHY_CFG_PLL_CPBIAS_CNTRL=1`; mainline no espera y escribe cero. v0.16 porta
  ambos y añade `touchscreen-inverted-y`;
- la prueba física v0.16 no crea NCM/RNDIS, conserva los dos errores de
  descriptor de Windows y no expone SSH en USB ni en la LAN. La espera POR y
  CPBIAS=1 no bastan para arreglar la señal eUSB2;
- v0.16 añadió `touchscreen-inverted-y`, pero el helper del kernel aplica las
  inversiones antes de `touchscreen-swapped-x-y`: esto invirtió el X visible y
  dejó invertido el Y visible. La corrección exacta en r12 es
  `touchscreen-inverted-x` + `touchscreen-swapped-x-y`, sin `inverted-y`;
- el journal v0.16 extraído en sólo lectura confirma de nuevo que PTN3222,
  DWC3, configfs, `usb0`, DHCP y `sshd` arrancan sin error interno nuevo;
- TWRP ofrece una referencia funcional del mismo hardware: PTN3222 revisión
  `A2`, overrides efectivos `06=20`, `07=21`, `08=63`, `0a=01`, y con ADB
  enumerado registra `DEVICE_STATUS=09` y `LINK_STATUS=05`;
- v0.17 registra el reloj y los controles efectivos de la PHY al inicializar,
  y ocho segundos después lee `00..16` del PTN3222. La comparación de
  `0f/10` distinguirá el lado eUSB2/repetidor del gadget/EP0;
- la prueba física v0.17 valida completamente la orientación táctil. USB sigue
  sin enumerar NCM/RNDIS, `172.16.42.1:22` no responde y el barrido de la LAN
  sólo encuentra `.138`/`.150`, dispositivos excluidos conocidos;
- el journal v0.17 muestra exactamente los mismos `00..16` del PTN3222 que el
  kernel Samsung funcional, incluidos `0f=09`, `10=05`, revisión `A2` y los
  cuatro overrides. Reset lógico/físico y reloj PHY de 38,4 MHz son coherentes;
- por tanto no se debe volver a cambiar PHY, repetidor, alimentación o tuning.
  El host alcanza el enlace pero no recibe ni VID/PID: el fallo queda en
  DWC3/UDC/EP0 o en la entrega del descriptor;
- v0.18 registra el pull-up solicitado/efectivo, DCTL/DSTS/DEVTEN/event count,
  todos los eventos DWC3, transiciones EP0 y cada paquete SETUP decodificado;
- la prueba física v0.18 vuelve a LightDM pero no enumera: Windows conserva dos
  errores de descriptor, no hay NCM/RNDIS ni SSH en `172.16.42.1/.2`, y la LAN
  sólo expone los equipos excluidos `.138`/`.150`;
- el journal v0.18 demuestra que DWC3 ejecuta pull-up/RUN y recibe por EP0
  `GET_DESCRIPTOR` de dispositivo/configuración/string, `SET_ADDRESS`,
  `GET_STATUS`, `SET_CONFIGURATION(1)` y `SET_INTERFACE(0)`. Hardware,
  PTN3222, PHY, IRQ, EP0 y entrega de descriptores quedan demostrados; no se
  debe volver a retocar esa cadena para el síntoma actual;
- Windows no enlaza la función CDC-NCM aunque completa la configuración. v0.19
  cambia explícitamente el gadget a `rndis.usb0`, manteniendo
  `172.16.42.1`/DHCP/OpenSSH como transporte de compatibilidad;
- en paralelo, v0.19 describe el WCN7850 (`PCI 17cb:1107`) en PCIe0 con PMU,
  reguladores, sleep clock, WLAN_EN GPIO80, BT_EN GPIO81, PERST GPIO94 y wake
  GPIO96. Incluye `ath12k`, `pwrseq-qcom-wcn` y los cuatro blobs Kiwi v2 stock;
- el ZIP v0.19 actualiza además el árbol completo de módulos 7.2.0-rc3,
  `deviceinfo` y firmware en `mmcblk1p2`, tras verificar que es un rootfs pmOS.
  La misma configuración está integrada en la imagen SD limpia;
- v0.19.2 sí completa el arranque: tres journals persistentes no contienen
  panic y dos boots llegan a systemd, RNDIS, NetworkManager, OpenSSH, Xorg,
  LightDM y slick-greeter. X configura simpledrm a 2960x1848 y activa VT7;
- la consola visible de las fotos de v0.19.2 no era un bloqueo de systemd.
  v0.20 retiró `console=tty0` para separar fbcon de X, pero v0.21 la restaura
  temporalmente porque el diagnóstico visual es prioritario durante el
  bring-up del Wi-Fi;
- PCIe0 v0.19.2 crea el root port `17cb:0113`, pero termina `Device not found`:
  el DT omitía el séptimo rail exigido por `pwrseq-qcom-wcn` y dejaba WLAN_EN
  en pull-down. v0.20 ensayó PM8550VS-G LDO3 como `vddio1p2-supply` y forzó
  GPIO80 alto;
- el journal v0.20 demuestra que el kernel r15 sí monta rootfs, arranca systemd,
  RNDIS y OpenSSH, pero deja de escribir exactamente a los 18,987144 s tras
  los rangos del host PCIe0. No hay panic ni oops. El DTB registra antes un
  ciclo de dependencias entre `regulators-5` y `smps4`, evidencia que acota la
  regresión al rail real/orden de alimentación nuevo;
- v0.21 revierte PM8550VS-G LDO3 y `vddio1p2-supply`, deja que el driver use el
  dummy regulator conocido de v0.19.2 y conserva sólo la parte eléctrica
  justificada de GPIO80 (`bias-pull-up`, 16 mA). Elimina `output-high` para que
  `pwrseq-qcom-wcn` eleve WLAN_EN en su secuencia normal;
- el journal v0.21 demuestra que no existe cuelgue: el boot
  `f1d854a068194803b30089cb0d6554a3` activa sin error los siete rails,
  conserva WLAN_EN alto, completa el sondeo PCIe con `Device not found`,
  inicia NetworkManager/OpenSSH/LightDM y alcanza `graphical.target` a los
  21,604 s. Continúa registrando actividad más allá de 51 s;
- la pantalla permanece en el último printk sólo porque v0.21 volvió a añadir
  `console=tty0`. v0.22 reutiliza exactamente kernel r16/DTB/firmware, sube el
  device a r7 y retira únicamente esa consola de framebuffer tanto del bundle
  Android como del paquete reproducible;
- v0.22 retira correctamente `console=tty0`, pero dos boots nuevos
  (`d34857ab68a9422a9dda48d6b2467373` y
  `cbab67c1ce7241e18c49ca1523ca0d7e`) dejan de progresar a 21,727 y 19,040 s
  durante sondeos repetidos PCIe/WCN, antes de LightDM; los cuatro ficheros
  X/LightDM quedan vacíos. Comparado con el boot v0.21 que sí completa la misma
  secuencia, el fallo es intermitente y está acotado a esa carrera de probe;
- v0.23 deshabilita como unidad `wcn7850-pmu`, `pcie0` y `pcie0_phy`. El DTB
  instalado confirma los tres `status = "disabled"`; firmware, módulos y
  fuentes se conservan para reactivarlos después. No se modifica pantalla,
  táctil, SD, DWC3, RNDIS ni OpenSSH;
- el boot aislado v0.23 `563abe3add6e4cd893b4ceeaceb88eea` no se cuelga:
  NetworkManager y OpenSSH arrancan a 21,021/21,024 s, LightDM a 21,316 s y
  `graphical.target` a 21,373 s. Xorg abre simpledrm a 2960x1848 en VT7 y
  slick-greeter queda ejecutándose; no hay panic, oops ni probes WCN/PCIe0;
- la imagen física permanece en los pingüinos aunque LightDM registra
  `Plymouth is running on VT 1`, lanza X con `-novtswitch` y declara
  `Activating VT 7`. Los logs de v0.11, que sí mostró el greeter, son
  esencialmente iguales; el defecto queda acotado al handoff/repintado de VT;
- el boot v0.24 `96a5a5ecfc28401a8010ad616a9a5afc` vuelve a completar
  userspace: OpenSSH escucha desde 21,493 s, LightDM arranca a 21,791 s,
  `graphical.target` a 21,797 s y slick-greeter está activo. El fallo no es un
  cuelgue del kernel ni de pmOS;
- el handoff v0.24 no llegó a ejecutarse: el instalador TWRP imponía `0644` a
  todos los ficheros del overlay y la entrada regular copiada en
  `graphical.target.wants` fue ignorada por systemd por no ser un enlace. El
  journal lo registra explícitamente a 10,892 s;
- v0.25 cambia el manifiesto incremental a `hash modo ruta`, restaura `0755`
  al script y crea un symlink systemd real durante la instalación. Además
  fuerza temporalmente el DDX `fbdev` con `ShadowFB` sobre `/dev/fb0`: así X
  escribe directamente en el framebuffer que ya muestra los pingüinos y no
  depende del cambio de scanout del DDX modesetting/simpledrm;
- v0.25 demuestra que no queda un fallo de activación: el boot
  `4803b789a4b545ff97b0829a4bac2062` llega a OpenSSH/LightDM/greeter, el
  handoff se ejecuta y registra `active-before=1`, `active-after=7`. Xorg usa
  `/dev/fb0` a 2960x1848, pero con `using shadow framebuffer`; el panel sigue
  conservando los pingüinos pese a más de 900 s de userspace estable;
- v0.26 cambia únicamente `ShadowFB` a `false`, de modo que X renderiza sobre
  la memoria fbdev sin depender de la copia de daños. Cinco segundos después
  del handoff guarda exactamente 21.880.320 bytes de `/dev/fb0` en
  `/var/log/gts9uwifi-fb0-after-x.raw` y registra su SHA-256;
- tras el flash manual v0.26, mantenerla encendida y conectada por USB aunque
  la imagen no cambie. Si RNDIS vuelve a fallar en Windows, regresar a TWRP:
  la captura raw permitirá determinar si el framebuffer contiene el greeter o
  todavía los pingüinos, separando definitivamente renderizado y scanout.

El DTS v0 no incluye DRM/DSI nativo. Mantiene el scanout del bootloader y usa
simpledrm para separar el primer arranque del futuro driver dual-DSI del panel.

No se flasheará la tablet automáticamente. Todo artefacto debe validarse
estáticamente y acompañarse de instrucciones de restauración antes de pedir una
prueba física.

Para las builds ordinarias siguientes se evita repetir baterías de hashes y
dos empaquetados reproducibles: tras compilar y empaquetar una vez, se copia el
ZIP a `/sdcard/` y se hace una única comparación SHA-256 entre el archivo local
y el ya copiado. Las comprobaciones adicionales se reservan para cambios de
boot chain, formato o particiones con riesgo especial.

## Hechos de hardware y firmware confirmados

- Modelo: Samsung SM-X910; codename Android `gts9uwifi`.
- SoC: Qualcomm SM8550/kalama; GPU Adreno 740.
- Dispositivo no A/B.
- Firmware base disponible: X910XXS5CYG1, One UI 7 / Android 15 userspace,
  kernel Samsung 5.15.153 con KMI Android 13.
- Boot image header v4. Particiones relevantes:
  - `boot`: 96 MiB;
  - `init_boot`: 8 MiB;
  - `vendor_boot`: 96 MiB;
  - `dtbo`: 16 MiB, overlay stock `board-id,03`;
  - `recovery`: 104.5 MiB;
  - `super`: 11,744,051,200 bytes.
- Panel: `GTS9U_ANA38407_AMSA46AS02`.
- Táctil: Goodix Berlin/GT9916 (confirmado en el FDT vivo).
- WLAN: Qualcomm Kiwi v2.
- TWRP 3.7.1_12-0 monta una microSD de 238 GB como `/external_sd`.
- Esa tarjeta actual está en exFAT, al 96 % y contiene datos: no se usará para
  pruebas destructivas. Hace falta otra microSD.
- Linux mainline identifica la ranura como `sdhc_2`; el DT vivo confirma
  detección PM8550 GPIO12, VMMC L9B y VQMMC L8B.
- El táctil es Goodix GT9916 en I2C4 `0x5d`, con driver Berlin upstream.
- La X910 usa repetidor NXP eUSB2 y controlador Type-C/PD SM5714, no el diseño
  PMIC GLINK de las placas Qualcomm de referencia.
- El port UT demuestra que el kernel downstream, los blobs stock y la DTBO
  pueden proporcionar pantalla, GPU, táctil, Wi-Fi, audio y sensores.

## Reglas de seguridad

- La usuaria flashea manualmente; las herramientas de build nunca escriben en
  la tablet.
- No tocar bootloader, PIT, EFS, persist, modem ni calibraciones.
- No escribir `super` para el bring-up si puede evitarse.
- Conservar siempre las imágenes stock y hashes antes de generar derivados.
- No reutilizar imágenes X710: panel, táctil, WLAN y overlays no son
  intercambiables con el SM-X910.
- Cada procedimiento de prueba debe incluir vuelta atrás mediante TWRP/Odin.

## Estructura del proyecto

```text
PostmarketOS/
├── README.md                  # este documento vivo
├── docs/
│   ├── porting-log.md         # historial detallado por sesiones
│   ├── upstream-audit.md      # soporte mainline/pmOS y fuentes reutilizables
│   ├── boot-strategy.md       # boot chain, microSD, riesgos y recuperación
│   └── testing-mainline-v0.md # procedimiento manual de prueba y rollback
├── configs/                   # cmdline, bootconfig y fuentes DTBO no-op
├── pmaports/                  # device/kernel packages locales de pmbootstrap
├── scripts/                   # build, empaquetado y validación reproducible
├── sources/                   # repos/clones necesarios o manifiestos fijados
├── work/                      # temporales, logs y scripts de entorno
└── artifacts/                 # imágenes finales, hashes e instrucciones
```

Los firmware e imágenes grandes no se duplican: se referencian desde
`../port/firmware-extracted/` y desde la carpeta oficial de firmware situada al
lado del workspace.

## Entorno de trabajo

- Las distribuciones WSL `Ubuntu` y `Ubuntu-24.04` existen para el usuario de
  Windows, pero no son visibles desde el usuario aislado del sandbox. Las
  invocaciones WSL deben ejecutarse con el contexto autorizado del usuario.
- Los comandos complejos no deben pasarse con `bash -lc` desde PowerShell: las
  comillas y expansiones se deforman. Escribirlos en `work/*.sh` y ejecutar el
  fichero con `bash` dentro de WSL.
- Las builds pesadas se harán en filesystem Linux y en una ruta sin espacios;
  el workspace de Windows contendrá fuentes fijadas, configuración, scripts y
  artefactos finales.
- Entorno fijado: `Ubuntu-24.04`, `/root/pmos-gts9u/`; pmbootstrap 3.11.1,
  pmaports `b7681d0...` y Linux `a13c140cc...` (`v7.2-rc3`).
- En `Ubuntu` (Python 3.10) pmbootstrap actual falla por `tomli/tomllib`; usar
  `Ubuntu-24.04` para este proyecto.
- La documentación oficial de pmbootstrap sigue marcando WSL como no
  soportado por su uso de loop devices. En este WSL2 concreto, tras instalar
  `kpartx`, kernel APK, loop/mount, rootfs y export han funcionado. No se
  extrapola esa observación a otros entornos.

## Lo que ha funcionado

- Reutilización del inventario completo y conocimiento de hardware del port UT.
- Acceso autorizado a las distribuciones WSL reales del usuario.
- Confirmación previa de que TWRP reconoce y monta la microSD.
- Captura del FDT vivo X910 como `work/live-device-tree.dtb` y decompilación a
  DTS; hash SHA-256 del blob: `7f02a5bb18f1ca2ff086e3038780d372463ff82062b5ef029401398b938cac83`.
- Auditoría upstream: SM8550, SDHC2, GT9916, A740 y simpledrm tienen base
  mainline utilizable. Linux 7.2-rc3 coincide con el paquete pmOS actual.
- Inspección binaria local de la DTBO stock: dos entradas y todos sus
  selectores exactos confirmados. Se han creado equivalentes no-op.
- Dependencias de kernel instaladas en `Ubuntu-24.04` y worktree/build fuera de
  la ruta Windows con espacios.
- DTS autónomo X910 y paquetes `device-samsung-gts9uwifi` /
  `linux-samsung-gts9uwifi-mainline` creados con checksums fijados.
- Compilado Linux 7.2-rc3 directo y como APK. El DTB resultante conserva
  framebuffer/splash, reservas, SDHC2, GT9916, UART, USB experimental y
  ramoops; los controladores críticos para root SD y diagnóstico son built-in.
- `pmbootstrap install` funciona en WSL2 con `kpartx`. Se creó una imagen GPT
  de 4.634.705.920 bytes con `pmOS_boot` ext2 y `pmOS_root` ext4, XFCE4,
  systemd, LightDM, NetworkManager y OpenSSH.
- Separar `initramfs-extra` en la partición boot reduce el initramfs de
  15,15 MiB a 2.133.928 bytes; cabe en `init_boot` de 8 MiB con 6.254.680 bytes
  de margen bruto antes del footer AVB.
- El `vmlinuz` instalado por `zinstall` es EFI zboot. Se valida su cabecera y
  se extrae su payload gzip (`0237f8a...`) para Android `boot.img`, garantizando
  que kernel y módulos proceden de la misma compilación y release 7.2.0-rc3.
- Bundle Android v4 regenerado dos veces con hashes idénticos y validado byte a
  byte: headers, offsets, DTB, selectores DTBO, AVB y tamaños correctos.
- La primera instalación física confirmó la SD `pmOS_boot` ext2 y escribió
  correctamente `boot`, `init_boot`, `vendor_boot` y `dtbo`. El ZIP v0 falló
  sólo al intentar escribir `vbmeta`: TWRP expone `/dev/block/sde15` (128 KiB)
  con flag RO. Su contenido seguía intacto y ya tenía AVB `Algorithm: NONE`,
  `Flags: 2`, por lo que no necesita reemplazo para esta prueba.
- Generados y validados los artefactos mainline v0.1: imagen SD comprimida
  `592deff2...` y ZIP TWRP `aaef2bb5...`. El instalador valida `vbmeta` antes
  de escribir nada y lo conserva sólo si el RO existente tiene flags 2.
- Regenerado `artifacts/restore-ubuntu-touch-v8-boot-sm-x910.zip` (SHA-256
  `eee755c73105ce55311e63eb4a8a50dff42ca6338b1930c017825c510a563e06`):
  restaura las cuatro particiones boot escribibles y `vbmeta` si recovery lo
  permite; nunca reescribe `super`. Pasó CRC, modo y hashes internos.
- El primer reboot con v0.1 no llegó a Linux: la pantalla con datos RPMB y
  código de barras era Odin lanzado por ABL. `/proc/last_kmsg` conserva la
  causa exacta: ABL descomprime el kernel, registra `No match found for Soc
  Dtb type` y `Appended Soc Device Tree blob not found`, y entra en Odin.
  `pstore` está vacío porque el kernel nunca recibió el control.
- Comparar el DTB mainline con el FDT vivo reveló que la raíz mainline sólo
  tenía `samsung,gts9uwifi`/`qcom,sm8550`; faltaban los selectores downstream
  que Samsung ABL usa antes de arrancar. El DTS contiene ahora, exactamente,
  `qcom,kalama-mtp`, `qcom,kalama`, `qcom,mtp`, los cuatro pares
  `qcom,msm-id` y `qcom,board-id = <0x10008 0x03>`.
- Generado el ZIP v0.2, SHA-256
  `9288af69c694fdc84b7b1f9694265152c5f7959a880d338f98b2e3d106c0f65c`.
  Conserva kernel, initramfs, DTBO, vbmeta y rootfs de v0.1; sólo cambia
  `vendor_boot` por el DTB corregido. El validador comprueba también los
  selectores de ABL extraídos del propio `vendor_boot`. El ZIP se copió a
  `/sdcard/` y se verificó allí el mismo hash; no se flasheó.
- El arranque v0.2 confirmó que los selectores son correctos: desapareció por
  completo `No match found for Soc Dtb type` y ABL ejecutó `FindBestMatch`.
  La siguiente barrera fue `ApplyOverlay: ufdt apply overlay failed`, seguida
  de `Root Node is not found at BoardDtb`, `Invalid device tree header` y Odin.
  El fallo se reprodujo dos veces y Linux tampoco llegó a ejecutarse.
- El DTB Samsung funcional contiene `/__symbols__`; v0.2 no lo contenía porque
  upstream no compila este DTB como base de overlays. Se añadió
  `DTC_FLAGS_sm8550-samsung-gts9uwifi := -@`. El DTB v0.3 exporta 474 símbolos
  y tanto `fdtoverlay` como `ufdt_apply_overlay` oficial aplican correctamente
  el overlay no-op board03 sobre él.
- Generado el ZIP v0.3, SHA-256
  `0a0d5b0e749c17155a0503e1c6a14e340ea3b9b437a3fbbcfbd77d9219bde240`.
  De nuevo conserva kernel, initramfs, DTBO, vbmeta y rootfs; sólo cambia el DTB
  dentro de `vendor_boot`. Se reprodujo byte a byte, se copió a `/sdcard/` y
  se verificó allí el mismo hash; no se flasheó.
- El arranque v0.3 volvió a fallar exactamente en `ufdt_apply_overlay`, con
  los mismos mensajes y unos 10,6 ms que v0.2. Por tanto `/__symbols__` no era
  suficiente para el fork Samsung. Se deja de iterar sobre el overlay no-op.
- El flujo Qualcomm ABL de referencia (`BootLinux.c`, commit `2a0c8e97...`)
  demuestra una segunda ruta: si `dtbo` no es una tabla Android válida, ABL
  no invoca ufdt y busca un FDT concatenado justo después del miembro gzip del
  kernel. Esta ruta no necesita adivinar PMIC IDs ni fusionar nodos downstream.
- Generado el ZIP v0.4, SHA-256
  `2083daf1ad515b32634a8f5686adc4972064ff8fd03153da0e6654d49f97a679`.
  `boot` contiene el payload empaquetado original seguido byte a byte por el
  DTB mainline; `dtbo` conserva tamaño/footer AVB correctos pero empieza por
  cero para forzar el fallback. `vendor_boot` mantiene otra copia del DTB. El
  ZIP se reprodujo, se copió a `/sdcard/` y se verificó allí; no se flasheó.
- El arranque físico v0.4 superó por primera vez toda la cadena ABL: apareció
  la salida verbose y el logo de Linux mediante el framebuffer conservado.
  Después el SoC se reinició; por tanto el fallback appended-DTB queda validado
  y el fallo actual ya está dentro de Linux/firmware, no en el cargador.
- Desde TWRP se guardaron `/proc/last_kmsg`, dmesg y pstore en
  `work/v04-linux-crash-20260718/`. Pstore estaba vacío, pero el registro de
  reset identifica `TZBSP_ERR_FATAL_NOC_ERROR`; Samsung cifra el detalle del
  maestro/esclavo NoC y no permite atribuirlo a un driver concreto.
- Comparar el DTB v0.4 compilado con el FDT vivo reveló que al evitar la DTBO
  stock faltaban carveouts de placa que ABL no reconstruye: UH/KASLR,
  `chipinfo`, `sec_xbl`, LLCC y casi 180 MiB de memoria alta de
  bootloader/depuración segura. Sólo `sec_log_buf` estaba reservado. Linux
  podía tratar las demás zonas protegidas como RAM ordinaria, causa coherente
  con el fatal NoC.
- El DTS v0.5 replica los rangos fijos exactos del FDT vivo y amplía
  `hwfence-shbuf` al tamaño X910. El DTB de 152.392 bytes tiene SHA-256
  `78397ab9c916084a68b37a5b19de2d1cd2619691201552f1ecc60a483ab44cd0`;
  el validador exige individualmente los 15 carveouts críticos.
- ZIP v0.5:
  `postmarketos-edge-xfce-mainline-v0.5-sm-x910-twrp.zip`, 21.885.945 bytes,
  SHA-256
  `1ae10d4effba444a3d970e9c6a68bd11f9304692a7bffcf309633b9063388314`.
  Headers, AVB, appended DTB, reservas, tamaños, CRC, manifiestos y reproducción
  byte a byte pasaron. Se copió a `/sdcard/` y se verificó allí el mismo hash;
  no se flasheó.
- El arranque v0.5 volvió a mostrar Linux y terminó con el mismo fatal NoC.
  TWRP confirmó `restart_reason = 0x5023a01` y
  `TZBSP_ERR_FATAL_NOC_ERROR`; por tanto los carveouts quedan conservados por
  corrección, pero no eran el desencadenante inmediato del reset.
- El vídeo `20260718_033322.mp4` permite leer el final de `initcall_debug`.
  A `26.772 s` regresan correctamente `7400000.interconnect` y
  `7430000.interconnect`; el siguiente proveedor según `sm8550.dtsi` es
  `lpass_ag_noc@7e40000`, pero nunca aparece su retorno antes del apagado.
- v0.6 deshabilita sólo `lpass_ag_noc`, innecesario para SD/pantalla/SSH. Los
  otros dos NOC LPASS permanecen activos porque la evidencia demuestra que sus
  probes terminan. Se añade además una consola built-in que escribe el printk
  en el ring Samsung `sec_log_buf` con cabecera `LOGM`, legible por el siguiente
  TWRP mediante `/proc/last_kmsg`.
- Se reconstruyeron el APK `linux-samsung-gts9uwifi-mainline-7.2_rc3-r4`,
  módulos, initramfs y rootfs. Release y vermagic son `7.2.0-rc3`; el payload
  empaquetado contiene la consola persistente y el DTB instalado marca
  `7e40000` como `disabled`.
- Artefactos v0.6 reproducidos byte a byte: imagen SD comprimida SHA-256
  `6250db18ed8afaad2afd8d98dad376305fccefa0518be806c3cf08af0791939e`
  y ZIP TWRP SHA-256
  `0890bbe1160aa5b03d40963209ae2a5193d7857531ee2518f0adbaf522d31a9a`.
  El ZIP se copió a `/sdcard/` y se verificó allí; no se flasheó.
- El arranque físico v0.6 volvió a reiniciar con
  `TZBSP_ERR_FATAL_NOC_ERROR`; por tanto `lpass_ag_noc@7e40000` no era el
  desencadenante. La consola `LOGM` sí funcionó: TWRP expuso un
  `/proc/last_kmsg` de 453.717 bytes con el log completo de Linux desde
  `Linux version 7.2.0-rc3` hasta deferred probe. Ya no hacen falta vídeos
  para las iteraciones normales.
- El último retorno es de nuevo `7430000.interconnect` a 26,813 s. Antes,
  `8804000.mmc` había devuelto `-EPROBE_DEFER`, por lo que su reintento es el
  siguiente candidato por orden del DT. La v0.7 instrumenta
  `really_probe_debug()` para persistir dispositivo y driver antes de entrar
  en `->probe()`.
- ZIP diagnóstico v0.7 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.7-probe-trace-sm-x910-twrp.zip`,
  22.012.743 bytes, SHA-256
  `1362e7f9ecf4cedd082af4cbabb963a651215292a7bcd847007978bf5bd3c2be`.
  Pasó bundle Android v4, AVB, appended-DTB, tamaños, hashes internos y CRC;
  se copió y verificó con el mismo hash en `/sdcard`. No requiere reescribir
  la SD v0.6 y el asistente no lo flasheó.
- El arranque v0.7 confirmó el valor de la traza: tras completar
  `7430000.interconnect`, la última línea mainline es
  `probing f100000.pinctrl with driver sm8550-tlmm`; no existe retorno y el
  siguiente XBL registra `TZBSP_ERR_FATAL_NOC_ERROR`. `8804000.mmc` queda
  descartado como desencadenante de este reset.
- El FDT vivo/DTBO Samsung marca GPIO36–39 como reservados en TLMM. Esa
  información faltaba en el DTS mainline; la placa mainline Fold5 usa el mismo
  patrón con `gpio-reserved-ranges`. v0.8 añade exactamente `<36 4>`, sin
  importar los GPIO50–51 que son específicos del Fold5.
- ZIP v0.8 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.8-tlmm-reserved-sm-x910-twrp.zip`,
  22.012.795 bytes, SHA-256
  `74607d30076c92cc7fcae787534e26d9ea083a4da60280c551e0a75e87788c92`.
  Bundle Android v4, AVB, appended-DTB, propiedad compilada, tamaños, hashes
  internos y CRC pasaron; el ZIP se copió y verificó en `/sdcard`. No requiere
  reescribir la SD v0.6 y el asistente no lo flasheó.
- El arranque físico v0.8 ya no reinició por TrustZone: quedó detenido en un
  kernel panic normal hasta que la usuaria reinició manualmente a TWRP. Esto
  valida físicamente `gpio-reserved-ranges = <36 4>` y elimina el fatal NoC
  que bloqueaba todas las versiones v0.4–v0.7.
- El `/proc/last_kmsg` posterior contenía 2.097.136 bytes del recovery anterior,
  no el panic mainline. El reinicio manual no ejecutó la ruta Samsung que
  actualiza `previous_index`; nuestro ring sólo avanzaba `index`. v0.9 actualiza
  ambos índices en cada escritura para preservar el log en esta situación.
- ZIP v0.9 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.9-panic-log-sm-x910-twrp.zip`,
  22.012.505 bytes, SHA-256
  `e7a2d8b3264cc94cdf6863d8abdbbd5c90e6515d1c4577b4f3fd3651fd680375`.
  Conserva el DTB v0.8, initramfs, módulos y SD; sólo cambia el kernel built-in
  del logger. Pasó bundle, AVB, appended-DTB, tamaños, hashes internos y CRC;
  se copió y verificó en `/sdcard`. El asistente no lo flasheó.
- La primera captura posterior a v0.9 se realizó con TWRP a 1.026 s de uptime.
  `/proc/last_kmsg` ya medía el máximo de 2.097.136 bytes y sólo contenía el
  recovery actual: sus mensajes habían dado una vuelta completa al ring y
  sobrescrito el panic. No requiere otra build; se repetirá el mismo v0.9 y se
  extraerá el fichero inmediatamente después de volver a TWRP.
- Repetir v0.9 y capturar a los 146 s tampoco recuperó mainline. El ring muestra
  `XBL(28, restored from storage)`: el reset forzado desde el panic restaura la
  copia persistida del recovery anterior y descarta el `sec_log_buf` mainline;
  no era sólo una carrera contra el volumen de printk.
- El driver Samsung moderno confirma que `last_kmsg` copia el ring usando
  `idx` al arrancar y después registra el logger actual. La solución práctica
  es conservar RAM mediante un reinicio caliente del propio kernel.
- ZIP v0.10 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.10-auto-panic-sm-x910-twrp.zip`,
  22.012.502 bytes, SHA-256
  `47331b9616f68048f381b61d52e9a6e1ff74f3ab35dcb46addae5d39e7ae372a`.
  Sólo cambia la cmdline de `vendor_boot`: `panic=10`, sin `initcall_debug` y
  con `loglevel=7`. Kernel, DTB, initramfs, módulos y SD no cambian. Pasó AVB,
  bundle, hashes, tamaños, CRC y reproducción; se verificó en `/sdcard`.
- Las pruebas físicas de v0.10 no recuperaron mainline en `last_kmsg`: el
  fichero de 2.097.136 bytes vuelve a contener recovery/XBL restaurado. La
  inspección completa del initramfs reveló que su ruta de fallo no hace panic:
  crea `PMOS_LOGS`, entra en shell y queda en un bucle infinito.
- Se reinició la v0.10 ya instalada sin reflashear y se sondeó el host durante
  más de 80 s. No aparecieron almacenamiento masivo, ACM ni red USB; sí dos
  instancias de dispositivo USB desconocido por fallo al solicitar descriptor.
  Esto confirma actividad física parcial del enlace, pero no un gadget usable.
- La foto fija de v0.10 hizo legible el diagnóstico que faltaba: Linux imprime
  `Initramfs unpacking failed: invalid magic at start of compressed archive`,
  espera root, lista `mmcblk1`, `mmcblk1p1` y `mmcblk1p2`, y finalmente hace
  panic por `unknown-block(0,0)`. No llegó a ejecutar `/init`; la hipótesis del
  bucle de `fail_halt_boot()` queda descartada para esta versión.
- TWRP confirma que la misma SD tiene `pmOS_boot` ext2 y `pmOS_root` ext4;
  puede montar `p1`, y un `e2fsck -n` recorre sus cinco pasadas. El fallo no es
  ausencia de tarjeta ni de particiones.
- El ramdisk genérico v0.10 es un gzip válido de 2.134.007 bytes que expande a
  un CPIO válido de 7.168.248 bytes. El kernel tiene todos los descompresores
  `CONFIG_RD_*`, pero stock empaqueta ambos ramdisks Android v4 con LZ4 legacy.
- El generador usa ahora LZ4 legacy por defecto para `init_boot`; el validador
  exige la magia stock, prueba ambos streams y compara el CPIO descomprimido
  con el initramfs pmOS original.
- ZIP v0.11 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.11-lz4-initramfs-sm-x910-twrp.zip`,
  21.988.029 bytes, SHA-256
  `9cdc1bdd4d6be730a3b64fd66c5413794889f6cc1c0fcc25ea1977604a3713f1`.
  Sólo cambia `init_boot.img` (SHA-256
  `bedcad22a49dbf442641dcaf13e3290edd87b221cbca6fb8f47b8f2460c16922`);
  se validó, reprodujo, copió a `/sdcard` y verificó allí. El asistente no lo
  flasheó.
- La prueba física v0.11 supera completamente el panic: monta las dos
  particiones pmOS de la microSD, arranca systemd y muestra LightDM/XFCE4 a
  resolución completa mediante simpledrm. Es el primer escritorio mainline
  arrancado en la SM-X910.
- El sondeo del host con el sistema vivo no encontró NCM/RNDIS, ACM ni SSH en
  `172.16.42.1`. Windows conserva dos errores de descriptor y la consola de
  Linux muestra que DWC3 no inicializa el core por timeout. Pantalla y SD son
  independientes de este fallo.
- Desde TWRP se montó `/dev/block/mmcblk1p2` exclusivamente en lectura y se
  extrajo el journal persistente v0.11 a
  `work/v011-rootfs-logs-20260719/`. USB falla exactamente durante el soft
  reset de DWC3 (`a600000.usb`, `-ETIMEDOUT`) y `a90000.i2c` queda diferido al
  no obtener su canal TX DMA. No se modificó el rootfs de la tarjeta.
- La auditoría de Linux 7.2-rc3 encontró el soporte upstream exacto
  `drivers/phy/phy-nxp-ptn3222.c` y su binding. El DTS v0.12 reproduce del FDT
  X910 el PTN3222 en I2C6 `0x4f`, LDO5B a 3.104 V, LDO15B a 1.8 V y reset
  PM8550VS-D GPIO4 activo-bajo; la PHY HS lo referencia mediante `phys`.
- El primer intento de compilación v0.12 usó por error la etiqueta inexistente
  `gpi_dma0` y falló al compilar el DT. SM8550 agrupa I2C4 e I2C6 bajo
  `gpi_dma1`; se corrigió a ese único controlador y no se conservará la
  referencia `gpi_dma0`.
- La configuración r7 integra `CONFIG_QCOM_GPI_DMA`,
  `CONFIG_PHY_NXP_PTN3222`, `CONFIG_INPUT_UINPUT` y `CONFIG_UHID`. La build
  directa resultante tiene `Image.gz` SHA-256
  `195608d3dcb49c896e48f57510bf65327190be4939c8e1995d119375b803443c`
  y DTB SHA-256
  `6f5fb0944a3438a48c09a8deaec2540c862b4fa11970595c806fb5b1337467ea`.
- ZIP v0.12 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.12-usb-touch-sm-x910-twrp.zip`,
  22.009.191 bytes, SHA-256
  `bf8067a1eb652b0154b8c8614ce254720a94cce96b428f465371890eb01fa5f2`.
  El validador comprueba además GPI DMA, ambos I2C a 400 kHz, compatible,
  supplies/reset/phandle del PTN3222 y USB peripheral/HS. Dos generaciones
  fueron idénticas y el hash remoto en `/sdcard` coincide; el asistente no lo
  flasheó.
- Desde TWRP se montó de nuevo `mmcblk1p2` como `ro,norecovery` y se extrajo
  el journal v0.12 a `work/v012-rootfs-logs-20260719/`. GPI DMA funciona:
  `a90000.i2c` sondea el GT9916 y registra `input0`, pero todos los eventos se
  descartan con `touch data checksum error`. USB queda diferido en
  `88e3000.phy` porque el proveedor PTN3222 `1-004f` no llega a estar listo.
- El FDT stock y el driver Samsung fijan las dos causas. El reset del PTN3222
  necesita la semántica PMIC Qualcomm (`qcom,drive-strength` y
  `power-source = <1>`), mientras que el Goodix Samsung usa cabecera de ocho
  bytes y puntos de 16 bytes. El driver Berlin upstream sí lee
  `point_struct_len` de `IC_INFO`, pero antes de v0.13 no lo utilizaba.
- La fuente r8 incorpora `support-samsung-goodix-16-byte-events.patch`, que
  conserva el formato upstream de ocho bytes y selecciona dinámicamente el
  Samsung de 16; también integra `CONFIG_INPUT_EVDEV=y`, corrige el área
  activa a 1848×2960 y reproduce el pinctrl stock del reset PTN3222.
- Build directa v0.13: `Image.gz` SHA-256
  `7cd3f980dab521874823d2a066b616cbfe39f13e6309c39ed0aa06a2b88f5c8b`;
  DTB `f38a0cfd5f5ed3430f210b2c8533f836871038992ee7b318f28577e1ca74a60f`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
- ZIP v0.13 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.13-goodix-ptn-reset-sm-x910-twrp.zip`,
  22.018.623 bytes, SHA-256
  `c69e7b53db8e176eca2396fea4137e26c1ccdf6e8dce8fab1f166ca8e74a0b98`.
  El validador inspecciona el payload de kernel, EVDEV, el parche Goodix, las
  dimensiones táctiles y todo el estado pinctrl del reset. Dos generaciones
  finales fueron idénticas; el ZIP se copió a `/sdcard` y su hash remoto
  coincide. El asistente no lo flasheó.
- Desde TWRP se extrajeron en sólo lectura los journals v0.13 a
  `work/v013-rootfs-logs-20260719/` y se desmontó la raíz. El journal actual
  tiene SHA-256
  `e4d2d9a437b122c83360653cfe926e20c29c9e8f5e9e8d7eb9a3343d7bd2c51a`.
  Goodix registra `event layout 8/8`, pero cada toque vuelve a fallar checksum;
  los dumps de 10/18 bytes prueban que el supuesto checksum es todavía parte
  del evento Samsung de 16 bytes.
- La corrección r9 identifica la metadata defectuosa por el PID de firmware
  `6936` y fuerza el layout 8/16. Para USB, el pinctrl ya no falla ni queda una
  cadena de deferred probe: DWC3 alcanza directamente el soft reset y termina
  en `-ETIMEDOUT`. Se comparó entonces el driver mainline con el log y FDT
  Samsung, que programan los registros PTN3222 `06=20`, `07=21`, `08=63` y
  `0a=01`; mainline no escribía ninguno.
- `configure-nxp-ptn3222-from-dt.patch` añade regmap y aplica la propiedad
  stock `qcom,param-override-seq` tras 4–5 ms de salida de reset. Ambos parches
  aplican limpiamente a Linux 7.2-rc3. Build limpia v0.14: `Image.gz` SHA-256
  `c02c47ffca3e4d6eb5d9f7cae2a1cb5f1c3994dc5dc25b2c0ec54908979b5952`;
  DTB `454a804c38c6a3e5ea0406419f65c0adcc1c8d477dea50fb2b79e51d1f430d07`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
- ZIP v0.14 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.14-goodix-force-ptn-tune-sm-x910-twrp.zip`,
  22.014.000 bytes, SHA-256
  `23cb7f066c6fecbd50d995db315906f262545ac3024af3068b3a468f947a5cfe`.
  Dos generaciones fueron idénticas, el validador confirmó las cadenas del
  kernel, la secuencia DT, Android v4 y AVB, y el hash copiado a `/sdcard`
  coincide. El asistente no lo flasheó.
- El journal v0.14 se extrajo desde TWRP con la raíz microSD montada como
  `ro,norecovery`; SHA-256
  `19d2ec68fd8d2fa3bdf30232821ba654c473f9f1ed0a7e9ed5340f970fe56e4f`.
  Goodix fuerza correctamente 8/16 y ya no genera errores de checksum. Los
  toques disparan en cambio timeouts GPI-I2C sobre la lectura inicial de 42
  bytes, mientras que las lecturas anteriores de 26 bytes sí completaban.
- El mismo journal acredita que PTN3222 aplica sus cuatro overrides antes de
  DWC3. El soft reset continúa en `-ETIMEDOUT`, lo que descarta el repetidor
  como barrera restante. Al operar sin SSPHY faltaba seleccionar UTMI como
  reloj PIPE, ruta implementada explícitamente por `dwc3-qcom`.
- La fuente r10/v0.15 prelee un único contacto Goodix: 18 bytes en el formato
  upstream o 26 en Samsung. Para multitáctil, la segunda lectura empieza tras
  contacto 0 más los dos bytes ya recibidos y completa contactos/checksum. El
  DTS añade `qcom,select-utmi-as-pipe-clk`; el validador lo exige en el DTB.
- Build limpia v0.15: `Image.gz` SHA-256
  `1a8320c6fa49f75cafd3ec3871ce012f59270a3b1d8ba665b2ac3a35b15cd8d2`;
  DTB `13c909ec802636d7be8a6318c52be0f0b53505f6f4224e457184869ed6376c25`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
  Se comprobó la ruta Goodix en la fuente/imagen y la propiedad UTMI-PIPE en
  el DTB compilado.
- ZIP v0.15 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.15-goodix-usb-pipe-sm-x910-twrp.zip`,
  22.012.201 bytes, SHA-256
  `e4f7432ed114227d238d161514796b6cc997a74029abe7ce9b079ef4216ae013`.
  Pasó Android v4, LZ4, AVB, appended-DTB y todas las aserciones. Se copió a
  `/sdcard` y el hash remoto coincide; el asistente no flasheó particiones.
- La prueba física v0.15 valida la corrección de lectura corta: el táctil
  produce entrada por primera vez. La geometría está escalada, pero el eje
  vertical queda invertido (`arriba → abajo`), corrección declarativa pendiente
  mediante `touchscreen-inverted-y`.
- El cambio UTMI-PIPE no produjo aún un gadget utilizable. Windows mantiene dos
  errores de descriptor, no crea NCM/RNDIS y no existe SSH en USB ni en la LAN;
  se requiere el journal v0.15 para saber si DWC3 superó el soft reset.
- El journal v0.15 se extrajo con la raíz como `ro,norecovery`; SHA-256
  `ab71752f62067cea8bd92d87850f42c873c9aace2090a2e6aba50c1d001f5496`,
  boot ID `50f794db540749b2bde8ed6ef92011c8`. Goodix no registra fallos y DWC3 ya
  supera el soft reset. Configfs crea gadget/`usb0`, asigna `172.16.42.1`,
  Avahi lo publica y OpenSSH escucha en `0.0.0.0:22`/`[::]:22`.
- La comparación directa entre `phy-snps-eusb2.c` mainline y
  `phy-msm-snps-eusb2.c` Samsung encontró dos diferencias antes del PLL:
  downstream espera 10 µs tras `POR` y usa CPBIAS=1; mainline omite la espera
  y usa cero. El resto de divisores PLL y cinco parámetros TX coincide.
- La fuente r11 integra `match-samsung-sm8550-eusb2-phy-init.patch`, que porta
  esas dos diferencias, y el DTS añade `touchscreen-inverted-y`. Ambos parches
  aplican limpiamente sobre Linux 7.2-rc3.
- Build limpia v0.16: `Image.gz` SHA-256
  `e1ece41124f5f365e5a123fd7ec67531682397bb5cf1d3c3df2a088b525624be`;
  DTB `ce4ce2e2d09b0835641e95f26971188fa5be479c0d65aa626eed4cade9f87093`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
  Fuente y DTB compilados se verificaron antes de empaquetar.
- ZIP v0.16 reproducido byte a byte:
  `postmarketos-edge-xfce-mainline-v0.16-touch-usb-phy-sm-x910-twrp.zip`,
  22.016.593 bytes, SHA-256
  `c0d768a2eb179cab95bc2776840828e36c8a50a2df598f7bbb1df6835c457ef9`.
  Pasó Android v4/LZ4/AVB/appended-DTB, se copió a `/sdcard` y el hash remoto
  coincide. El asistente no flasheó ninguna partición.
- La prueba física v0.16 vuelve a LightDM, pero no resuelve USB: Windows
  mantiene los dos fallos de solicitud de descriptor, no crea NCM/RNDIS y no
  hay SSH atribuible a la tablet en USB ni en la LAN (`.138` y `.150` siguen
  excluidos por ser otros dispositivos).
- El táctil de v0.16 queda invertido en ambos ejes visibles. La inspección de
  `touchscreen_apply_prop_to_x_y()` demuestra que el kernel invierte antes de
  intercambiar ejes. Con el `swap` necesario para este panel, invertir el Y
  visible requiere `touchscreen-inverted-x`; r12 elimina `inverted-y` y añade
  `inverted-x`.
- El journal v0.16 se extrajo como `ro,norecovery`; `system.journal` tiene
  SHA-256 `6dd5ee4399bbae29e56b10dbedc9d6178f7a7decca51728ec7c97c1215376f53`
  y el boot actual es `225ccfc4e1ac473f9c413502d1bbe026`. Confirma el mismo
  estado USB interno de v0.15 y no muestra fallos Goodix nuevos.
- En TWRP, el regmap del PTN3222 funcional identifica revisión `0xA2` y deja
  `06=20`, `07=21`, `08=63`, `0a=01`, `0f=09`, `10=05`. Según la
  [hoja de datos oficial de NXP](https://www.nxp.com/docs/en/data-sheet/PTN3222_CUK.pdf),
  `0x0f` es `DEVICE_STATUS` y `0x10` es `LINK_STATUS`.
- `diagnose-sm8550-eusb2-link.patch` imprime los controles efectivos de la PHY
  y lee `00..16` del PTN3222 ocho segundos después de iniciar el enlace, sin
  cambiar ningún registro. La fuente r12 lo integra en todas las builds.
- Build limpia v0.17: `Image.gz` SHA-256
  `48e91dfb2f42a665599d204a63e8633a8606011dc9dc4f18a4c1791975d12aa1`;
  DTB `8d600347ad1a826e0c0ef33fbf0fb68125d18d5a64939307ac4b93599c12bddf`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
- ZIP v0.17 generado una vez:
  `postmarketos-edge-xfce-mainline-v0.17-touch-usb-diagnostics-sm-x910-twrp.zip`,
  22.016.542 bytes, SHA-256
  `d86e978618bf00d182f705aa4b0704111b42b8f2f8dd8547e40255f205e30439`.
  Se copió a `/sdcard` y una única comprobación posterior dio el mismo hash;
  el asistente no lo flasheó.
- La prueba física v0.17 confirma que el táctil queda correctamente orientado
  y alineado. Windows aún muestra errores de solicitud de descriptor, no crea
  NCM/RNDIS y no hay SSH por USB ni en un host nuevo de la LAN; `.138` y `.150`
  siguen siendo los dos únicos SSH y pertenecen a otros dispositivos.
- El journal v0.17 extraído en sólo lectura tiene boot ID
  `66eb6939ed4649e197dcd6be06c0cd46`; `system.journal` SHA-256
  `201b71a79f2344904f9153b13e8826b32bd59a9a710d625a5ae868aa6193c13b`.
  PTN3222 mainline coincide byte a byte en `00..16` con TWRP: `0f=09`,
  `10=05`, revisión `A2` y overrides correctos. La PHY usa 38,4 MHz y registra
  todos sus controles efectivos sin errores.
- `diagnose-dwc3-ep0-enumeration.patch` añade trazas pasivas a pull-up,
  registros DWC3, eventos, EP0 y SETUP. El APKBUILD sube a r13 y el build
  directo aplica el parche en futuras compilaciones.
- Build incremental v0.18: `Image.gz` SHA-256
  `6d1feaff85d4d50131a2fdb114f28ac6be410420d0226c22c09edf8465b4ffef`;
  DTB sin cambios
  `8d600347ad1a826e0c0ef33fbf0fb68125d18d5a64939307ac4b93599c12bddf`;
  config `c2060ed1d41547e469cbeb07c87f39be1f810ccf6e55ecc0c53f6df7546d3b86`.
- ZIP v0.18 generado una vez:
  `postmarketos-edge-xfce-mainline-v0.18-dwc3-ep0-diagnostics-sm-x910-twrp.zip`,
  22.017.000 bytes, SHA-256
  `6706f3778c2df2b1384e1b225cf3c5af315ca0986056599dfb3fc4c42f8542e0`.
  Copiado a `/sdcard`; la única comprobación posterior coincide. No se flasheó.
- La prueba física v0.18 no cambia el síntoma externo: dos errores de solicitud
  de descriptor, sin NCM/RNDIS y sin SSH USB. El barrido LAN sólo encuentra
  `.138` y `.150`, que pertenecen a otros dispositivos. Se requiere su journal
  para explotar las nuevas trazas DWC3/EP0.
- El journal v0.18 (`47ee7c89dc374bd1baf30310b98cbef7`, SHA-256
  `ffcbcd4ebce12d857a91094c9712d442422001ab7533178a03db64c69d614edc`)
  prueba una enumeración EP0 completa hasta `SET_CONFIGURATION(1)` y
  `SET_INTERFACE(0)`. El problema externo restante es compatible con el
  binding CDC-NCM de Windows, no con un fallo de PHY, repetidor o DWC3.
- El FDT stock identifica Kiwi v2/WCN7850 con PCI ID `17cb:1107`; confirma
  WLAN_EN GPIO80, BT_EN GPIO81, PERST GPIO94 y wake GPIO96. Linux 7.2-rc3 ya
  contiene soporte ath12k WCN7850 y la infraestructura PMU/PCIe de SM8550.
- Se añadió `firmware-samsung-gts9uwifi` r1. El script
  `stage-stock-wifi-firmware.sh` extrae del `vendor.img` oficial y verifica
  `amss20.bin`, `phy_ucode20.elf`, `bdwlan.elf` y `regdb.bin`; no se versionan
  los blobs propietarios. Se instalan como los nombres upstream bajo
  `/usr/lib/firmware/ath12k/WCN7850/hw2.0`.
- Rootfs v0.19 verificado: device r4, kernel `7.2_rc3-r14`, firmware r1,
  `CONFIG_USB_CONFIGFS_RNDIS=y`, `CONFIG_ATH12K=m` y
  `CONFIG_POWER_SEQUENCING_QCOM_WCN=m`. El initramfs contiene
  `deviceinfo_usb_network_function="rndis.usb0"` y el DTB final contiene el
  PMU/reguladores y `wifi@0` compatible `pci17cb,1107`.
- ZIP único v0.19:
  `postmarketos-edge-xfce-mainline-v0.19-rndis-wifi-pcie-sm-x910-twrp.zip`,
  80.821.386 bytes, SHA-256
  `3ca3e44fb2a8e26bec76515381d40f565ecc6b5215b52d8b855f7513297a686e`.
  Incluye 2.011 archivos de overlay (69 MiB sin comprimir): árbol completo de
  módulos, firmware WCN7850 y deviceinfo. Se copió a `/sdcard` y el único hash
  posterior coincide; el asistente no lo flasheó.
- El primer intento manual de instalar ese ZIP abortó antes de cualquier `dd`:
  la microSD se montó correctamente, pero Alpine publica
  `ID="postmarketos"` y el validador exigía `ID=postmarketos` sin comillas. La
  fuente v0.19.1 acepta exactamente ambas formas; no cambia kernel, rootfs ni
  overlay.
- ZIP correctivo v0.19.1:
  `postmarketos-edge-xfce-mainline-v0.19.1-rndis-wifi-pcie-sm-x910-twrp.zip`,
  80.821.400 bytes, SHA-256
  `3a3431c1ea994536feadc6eb18712b1de38664babadb6b45e40da467dd66f89f`.
  Copiado a `/sdcard`; el único hash posterior coincide. Pendiente de flash
  manual.
- La instalación v0.19.1 terminó, pero el reboot no llegó a Linux. El
  `last_kmsg` restaurado por TWRP registra `ApplyOverlay: ufdt apply overlay
  failed`, `Invalid device tree header` y `Launching odin`. La metadata reveló
  `append_dtb_to_kernel=0` y `disable_runtime_dtbo=0`: al invocar directamente
  el empaquetador se omitieron los flags que todas las builds arrancables usan
  desde v0.4. No es un fallo del nuevo DTB Wi-Fi.
- `build-android-v4-bundle.sh` usa ahora por defecto la ruta físicamente
  validada de la X910: DTB anexado al kernel y DTBO runtime deshabilitado. La
  siguiente v0.19.2 sólo regenera las imágenes Android; kernel, initramfs,
  rootfs, módulos y firmware permanecen idénticos.
- ZIP v0.19.2:
  `postmarketos-edge-xfce-mainline-v0.19.2-appended-dtb-rndis-wifi-sm-x910-twrp.zip`,
  80.852.094 bytes, SHA-256
  `a8a6f28ab58c594478dda11a738ba0deb90c09d2865824b2aff845c655c0b8a6`.
  Metadata comprobada `append_dtb_to_kernel=1` y
  `disable_runtime_dtbo=1`; copiado a `/sdcard` y el único hash posterior
  coincide. Pendiente de flash manual.
- Imagen SD limpia v0.19 comprimida:
  `postmarketos-edge-xfce-mainline-v0.19-rndis-wifi-pcie-sm-x910-sd.img.zst`,
  513.383.398 bytes, SHA-256
  `ed7a92c2645eb3ea2118a77be28afba16fee7a30bbbfb4b614026df492fd6f10`.
  Es la salida del mismo rootfs verificado y permite validar una instalación
  desde cero sin depender del overlay incremental.
- La prueba física v0.19.2 alcanza userspace completo. Los boots
  `214544eee54741ab86c8d276cdcefe87` y
  `e159c2334b9f4a87afb08ee8bf67301e` continúan más de 51 segundos; LightDM
  activa VT7 y slick-greeter muestra su ventana. Xorg usa simpledrm a
  2960x1848 sin errores fatales. La consola que permanece visible no implica
  un cuelgue del kernel ni de systemd.
- En esos boots `usb0` tiene `172.16.42.1`, RNDIS queda configurado,
  NetworkManager detecta carrier y OpenSSH escucha en IPv4/IPv6. Falta probar
  desde Windows antes de afirmar que RNDIS ya es utilizable externamente.
- Wi-Fi v0.19.2 no enumera: PCIe0 crea el root port Qualcomm `17cb:0113`, pero
  no aparece el endpoint `17cb:1107` y registra `Device not found`. El driver
  WCN7850 avisaba además `supply vddio1p2 not found`.
- La fuente r15 corrige dos diferencias demostrables con el DT stock X910:
  añade PM8550VS-G LDO3 a 1,2 V como `vddio1p2-supply` y configura WLAN_EN
  GPIO80 como salida alta, pull-up y 16 mA. El DTB instalado en el rootfs fue
  inspeccionado y contiene ambas propiedades efectivas.
- Build limpia v0.20: device r5, kernel `7.2_rc3-r15` y firmware r1. Se retiró
  `console=tty0` tanto del bundle Android como del paquete device para que X
  sea el único consumidor visual del framebuffer; la consola serie y todos
  los mecanismos de log permanecen disponibles.
- ZIP v0.20:
  `postmarketos-edge-xfce-mainline-v0.20-wcn-power-rndis-no-fbcon-sm-x910-twrp.zip`,
  80.853.798 bytes, SHA-256
  `9a73808d30e6aa9b317a7550a36a5c6a271245d8fcdff17808ecba5e17f76998`.
  Incluye el overlay completo de módulos/firmware/deviceinfo, usa appended-DTB
  y DTBO runtime deshabilitado. Copiado a `/sdcard`; el único hash posterior
  coincide. El asistente no flasheó particiones.
- Imagen SD limpia v0.20:
  `postmarketos-edge-xfce-mainline-v0.20-wcn-power-rndis-no-fbcon-sm-x910-sd.img.zst`,
  478.250.065 bytes. Procede del mismo rootfs r5/r15/r1 y sirve para una
  instalación desde cero.
- Los logs v0.20 se extrajeron de la microSD en sólo lectura a
  `work/v020-rootfs-logs-20260719/`. El boot
  `56c2f5b944d14e2e8bc81741e54c8ef1` usa kernel r15, monta rootfs y boot,
  inicializa el gadget RNDIS y el socket OpenSSH, pero el journal termina
  bruscamente a 18,987144 s durante los rangos de `qcom-pcie 1c00000.pcie`.
  No contiene panic ni oops; la usuaria tuvo que reiniciar manualmente.
- La regresión v0.20 coincide con un nuevo aviso temprano de ciclo fijo entre
  `/soc@0/rsc@17a00000/regulators-5` y `smps4`. v0.21 retira completamente el
  LDO3/`vddio1p2-supply` experimental, restaura `console=tty0` y mantiene
  GPIO80 como pull-up/16 mA sin `output-high`.
- `diagnose-wcn7850-power-sequence.patch` añade trazas pasivas al módulo
  `pwrseq-qcom-wcn`: valor inicial/dirección/transición de WLAN_EN y registro
  del secuenciador. El módulo empaquetado contiene esas cadenas y el DTB final
  fue decompilado para comprobar que ya no conserva el rail experimental.
- Build limpia v0.21: device r6, kernel `7.2_rc3-r16` y firmware r1. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.21-wcn-diagnostics-verbose-sm-x910-twrp.zip`,
  80.851.485 bytes, SHA-256
  `c46b30538b486ee1b93c938464c8f339d93b3127450d3a34f39c4861bc3f9032`.
  Incluye overlay completo, appended-DTB y DTBO runtime deshabilitado. Se
  copió a `/sdcard` y la única comprobación posterior coincide; el asistente
  no flasheó ninguna partición.
- Los logs v0.21 se extrajeron en sólo lectura a
  `work/v021-rootfs-logs-20260719/`. El boot
  `f1d854a068194803b30089cb0d6554a3` prueba que la aparente congelación era
  exclusivamente visual: los siete rails retornan 0, WLAN_EN permanece en 1,
  PCIe devuelve `Device not found`, pero RNDIS obtiene carrier,
  NetworkManager y OpenSSH arrancan, LightDM se inicia a 21,555 s y
  `graphical.target` se alcanza a 21,604 s. No hay hang, panic ni oops.
- Build limpia v0.22: device r7, kernel r16 y firmware r1. Sólo se retira
  `console=tty0` del cmdline Android y del paquete device para entregar el
  framebuffer a X; UART, earlycon, journal y todas las trazas permanecen.
- ZIP TWRP v0.22:
  `postmarketos-edge-xfce-mainline-v0.22-rndis-ssh-greeter-sm-x910-twrp.zip`,
  80.851.469 bytes, SHA-256
  `85c70c79f1b0e0bb3c7facd47ac7b817807dd6159a15a4dd8d6f42f5e204f9c6`.
  Copiado a `/sdcard`; la única comparación posterior local/remota coincide.
  El asistente no flasheó ninguna partición.
- Los logs v0.22 se extrajeron en sólo lectura a
  `work/v022-rootfs-logs-20260719/`. Sus dos boots nuevos terminan antes de
  LightDM durante los sondeos repetidos de PCIe0/WCN; `Xorg.0.log`, su `.old`
  y ambos logs LightDM tienen cero bytes. No hay panic ni oops, pero tampoco
  progreso de systemd tras 21,727/19,040 s. El boot completo v0.21 demuestra
  que la misma ruta puede terminar, por lo que se trata como carrera
  intermitente y no como fallo del framebuffer.
- v0.23 aísla temporalmente el subsistema que aún no funciona: marca
  `wcn7850-pmu`, `pcie0` y `pcie0_phy` como deshabilitados. Build limpia
  verificada: device r7, kernel `7.2_rc3-r17`, firmware r1; el DTB instalado
  devuelve `status=disabled` para los tres nodos y mantiene fuera
  `console=tty0`.
- ZIP TWRP v0.23:
  `postmarketos-edge-xfce-mainline-v0.23-stable-rndis-no-wcn-sm-x910-twrp.zip`,
  80.851.833 bytes, SHA-256
  `a050c7d88ec223619c231f102593c5ae03d0b81dccaadda6256abd2d30b43fcd`.
  Incluye overlay completo, appended-DTB y DTBO runtime deshabilitado. Copiado
  a `/sdcard`; la única comprobación local/remota coincide. El asistente no
  flasheó ninguna partición.
- Los logs v0.23 se extrajeron en sólo lectura a
  `work/v023-rootfs-logs-20260719/`. El boot
  `563abe3add6e4cd893b4ceeaceb88eea` prueba que el aislamiento estabiliza el
  sistema: RNDIS tiene carrier y `usb0=172.16.42.1`, NetworkManager/OpenSSH
  arrancan a 21,021/21,024 s, LightDM a 21,316 s y los targets multi-user y
  gráfico a 21,373 s. No existe panic, oops ni actividad WCN/PCIe0.
- `Xorg.0.log` confirma modesetting sobre `/dev/dri/card0` simpledrm a
  2960x1848 y VT7; slick-greeter se ejecuta. LightDM observa Plymouth en VT1,
  arranca X con `-novtswitch` y después registra `Activating VT 7`, pero el
  panel sigue mostrando el último framebuffer de VT1. Por tanto los pingüinos
  ya no representan un fallo de boot, SSH, X ni greeter.
- v0.24 añade `gts9uwifi-display-handoff.service`, habilitada por el paquete
  device r8. Después de que LightDM cree `/tmp/.X11-unix/X0`, registra
  `fgconsole` y fuerza VT1→VT7 para provocar el repintado. El overlay TWRP
  incluye explícitamente script, unidad y activación para actualizar también
  la microSD existente. El ZIP conservaba el modo ejecutable, pero la prueba
  posterior demostró que el instalador lo reemplazaba por `0644` al extraerlo.
- Build v0.24 verificada: device r8, kernel `7.2_rc3-r17`, firmware r1 y
  `kbd-2.8.0-r0`; script ejecutable, unidad habilitada, cmdline sin
  `console=tty0` y los tres nodos WCN/PCIe0 aún deshabilitados. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.24-vt-handoff-rndis-sm-x910-twrp.zip`,
  80.853.551 bytes, SHA-256
  `b7c1a8bc2e3cc6bb0b68c89a5eea8882d85ef664291e80e54e275cfa8ef37b6e`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. El
  asistente no flasheó ninguna partición.
- Los logs v0.24 se extrajeron en sólo lectura a
  `work/v024-rootfs-logs-20260720/`. El boot
  `96a5a5ecfc28401a8010ad616a9a5afc` llega de nuevo a RNDIS/NetworkManager,
  OpenSSH, LightDM, Xorg y slick-greeter; `graphical.target` se alcanza a
  21,797 s y el journal continúa más allá de 51 s. No hay panic ni hang.
- La causa exacta del no-op v0.24 está registrada por systemd:
  `graphical.target.wants/gts9uwifi-display-handoff.service is not a symlink,
  ignoring`. La inspección offline confirma además modo `0644` en el script.
  El instalador TWRP extraía todos los miembros con ese modo fijo aunque el ZIP
  declarase `0755`; por tanto el rebote VT nunca fue probado físicamente.
- v0.25 usa un manifiesto `SHA-256 modo ruta`; el instalador valida `0644` o
  `0755`, aplica el modo declarado y sustituye la entrada wants por un enlace
  real a la unidad. Como segundo cambio independiente y justificado, añade
  `20-gts9uwifi-fbdev.conf`: X usará `fbdev` + `ShadowFB` sobre `/dev/fb0` en
  lugar de depender del page-flip modesetting/simpledrm que deja visible VT1.
- Build v0.25 verificada: device r9, kernel `7.2_rc3-r17`, firmware r1 y kbd;
  `fbdev_drv.so`, configuración fbdev, script ejecutable y enlace systemd
  presentes; cmdline sin `console=tty0` y WCN/PCIe0 aún aislado. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.25-fbdev-vt-rndis-sm-x910-twrp.zip`,
  80.853.846 bytes, SHA-256
  `8834678cceb50b7fc6d85b35daabcad8c57ff8ac0c34af3e8c7eaebcee74f054`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. El
  asistente no flasheó ninguna partición.
- Los logs v0.25 se extrajeron en sólo lectura a
  `work/v025-rootfs-logs-20260720/`. El boot
  `4803b789a4b545ff97b0829a4bac2062` llega a `graphical.target` a 23,453 s y
  permanece activo al menos 905 s. El handoff corre sin error, espera X0 y
  cambia la VT lógica de 1 a 7; los pingüinos no son ya una VT incorrecta.
- Xorg v0.25 carga explícitamente `fbdev_drv.so`, abre `/dev/fb0`, detecta
  `simpledrmdrmfb`, 2960x1848, 32 bpp y 21.367 KiB. La opción `ShadowFB=true`
  queda efectiva y X informa `using shadow framebuffer`; los repetidos
  `FBIOPUTCMAP: Invalid argument` no terminan el servidor ni el greeter.
- v0.26 prueba la ruta fbdev restante con `ShadowFB=false`. El mismo servicio
  guarda después de X una captura exacta de 21.880.320 bytes en
  `/var/log/gts9uwifi-fb0-after-x.raw`, por lo que una futura extracción podrá
  mostrar qué dibujó X aunque falle USB o el scanout físico.
- Build v0.26 verificada: device r10, kernel `7.2_rc3-r17`, firmware r1 y kbd;
  fbdev directo, script ejecutable con captura, enlace systemd y WCN/PCIe0
  aislado. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.26-direct-fbdev-capture-sm-x910-twrp.zip`,
  80.854.080 bytes, SHA-256
  `e2713a80edebd9897ccbdf7a4143d83d055579fb896056b15156357816c9b876`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. El
  asistente no flasheó ninguna partición.
- La captura v0.26 recuperada desde la microSD mide exactamente 21.880.320
  bytes y tiene SHA-256
  `a987f44c03315694b0716b929f6d9c7bb2aeee0a3c412dd4871bc357689d6aed`.
  Interpretada como XRGB8888 de 2960x1848 muestra completo y correcto el
  greeter de LightDM, el fondo XFCE y el teclado en pantalla. La conversión se
  conserva en `work/v026-rootfs-logs-20260720/gts9uwifi-fb0-after-x.png`.
- Esta evidencia descarta un fallo de boot, LightDM, X, VT o dibujo en fbdev:
  el panel sigue escaneando el buffer de la consola aunque `/dev/fb0` ya
  contiene otro frame. v0.27 vuelve al DDX `modesetting`, desactiva glamor con
  `AccelMethod=none`, activa `ShadowFB=true` y, tras el rebote VT1→VT7, ejecuta
  `xrandr` para desactivar y reactivar `None-1` a 2960x1848. El objetivo es
  obligar a simpledrm a enviar daño completo y actualizar el plano KMS.
- Build v0.27 verificada: device r11, kernel `7.2_rc3-r17`, firmware r1 y kbd;
  `modesetting` software, script 0755, unidad/enlace systemd y aislamiento
  WCN/PCIe0 presentes. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.27-kms-shadow-refresh-sm-x910-twrp.zip`,
  80.854.291 bytes, SHA-256
  `e665a73e8efa51198f87a3fba2dc5bed8a8839406af00a05309d04b47bd58bc8`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. El
  asistente no flasheó ninguna partición.
- La prueba física v0.27 sigue mostrando los ocho pingüinos. Con la tablet
  arrancada, Windows sólo enumera `Dispositivo USB desconocido (Error de
  solicitud de descriptor de dispositivo)`, Code 43; no hay ADB ni respuesta
  SSH en `172.16.42.1:22`.
- El journal v0.27 extraído en sólo lectura (boot
  `2cbe9bc2f5fd4beda28cceaaeb934e9b`) demuestra que el handoff completo se
  ejecutó: VT1→VT7, ambos `xrandr` sin error y captura fb0 a los 32,69 s.
  `Xorg.0.log` registra el apagado a 320x200 (con los `failed to add fb -22`
  esperables, simpledrm fija min/max al modo firmware) y la reactivación con
  un framebuffer nativo nuevo. La capa X queda definitivamente descartada.
- La comparación de dmesg v0.18↔v0.27 identifica la causa raíz del panel
  congelado: los kernels arrancados en v0.4–v0.18 eran builds directas con
  release `-dirty` que jamás cargaron módulos (`modprobe: FATAL ...
  7.2.0-rc3-dirty` en el journal), mientras que desde v0.19 udev coldplug sí
  carga `dispcc/videocc/camcc-sm8550.ko`. Con esos consumidores sondeados,
  `qcom-rpmhpd` ejecuta `sync_state()` y suelta el voto de arranque de MMCX;
  el MDSS se apaga y el panel retiene el último frame en su GRAM. La foto
  v0.21 (congelada tras `power sequencer registered`, 20,208 s) coincide al
  milisegundo con esa ventana de coldplug.
- v0.28 (device r12) aplica la corrección mínima:
  `/usr/lib/modprobe.d/gts9uwifi-display-hold.conf` bloquea el autoload de
  `dispcc_sm8550`, `videocc_sm8550`, `camcc_sm8550` y `gpucc_sm8550`. ZIP:
  `postmarketos-edge-xfce-mainline-v0.28-hold-boot-display-sm-x910-twrp.zip`,
  80.855.122 bytes, SHA-256
  `a9b169d40400cfa0bea239138194ce36dd428a9e492a52e6e60c590ec5ddfedc`, copiado
  a `/sdcard` con la única comparación local/remota coincidente. Pendiente de
  flash manual; si el greeter aparece, el fichero se retirará cuando exista el
  stack DRM/DSI nativo.
- La auditoría posterior no acepta v0.29 como solución confirmada: el cambio
  v0.19 activó todo el árbol de módulos, no sólo `qcomtee` y `qcom_ice`, y la
  correlación temporal no demuestra todavía que una llamada SCM apague el
  scanout. Para evitar más iteraciones ciegas, v0.30 vuelve al control exacto
  de v0.18 y recupera primero la interfaz físicamente conocida.
- v0.30 contiene las mismas imágenes `boot/init_boot/vendor_boot/dtbo/vbmeta`
  y los mismos hashes internos que v0.18, pero usa el instalador actual, que
  reconoce `ID="postmarketos"`, conserva vbmeta read-only correctamente y
  valida el overlay. El overlay sustituye la configuración X forzada por un
  fichero neutro y convierte el handoff posterior en un no-op; LightDM vuelve
  a usar modesetting simpledrm por defecto como en el Xorg log de v0.18.
- El empaquetado queda reproducible mediante
  `scripts/package-v018-display-baseline.sh` y los dos ficheros de
  `configs/display-baseline/`. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.30-known-good-v018-display-sm-x910-twrp.zip`,
  22.018.867 bytes, SHA-256
  `4f4797b29559496aa678f70e2f2a51bbb510b58258a49d62f4b3355b6735c83b`.
  Copiado a `/sdcard`; la comparación local/remota coincide. El asistente no
  flasheó ninguna partición.
- La prueba física v0.30 confirma el resultado esperado: arranca hasta
  LightDM, el táctil responde y la usuaria puede entrar al escritorio. Queda
  demostrado que el rootfs actual es compatible y que la regresión se limita
  al conjunto de cambios de boot introducido desde v0.19.
- v0.30 también enumera `UsbNcm Host Device` en Windows; el host recibe
  `172.16.42.2/24` y el puerto 22 de `172.16.42.1` responde con OpenSSH 10.3.
  La autenticación automática de `phablet` con `<DEV_PASSWORD>` fue rechazada, por lo
  que no se modificó la sesión viva.
- v0.31 compila el kernel/DTS actuales mediante la ruta directa y conserva
  `Linux version 7.2.0-rc3-dirty`; como el rootfs no contiene
  `/usr/lib/modules/7.2.0-rc3-dirty`, ningún módulo puede cargarse. El DTB
  confirma WCN PMU, PCIe0 y PHY deshabilitados, y el overlay conserva Xorg por
  defecto y el handoff no-op. ZIP:
  `postmarketos-edge-xfce-mainline-v0.31-current-kernel-no-modules-sm-x910-twrp.zip`,
  22.008.887 bytes, SHA-256
  `be37c78307d00dc065ed368ec4e35ecac434d7a11beead7b010e924ae1406d0e`.
  Copiado a `/sdcard`; la comparación local/remota coincide. v0.30 permanece
  también en la tarjeta como retorno inmediato a la base visible.
- La prueba física v0.31 muestra primero los pingüinos del arranque y después
  llega a LightDM. Esto demuestra que kernel, DTS, initramfs y userspace
  actuales sí pueden presentar el greeter; la congelación permanente de
  v0.19–v0.29 sólo aparece al habilitar la autocarga de módulos. NCM vuelve a
  exponer `172.16.42.1:22`, aunque `phablet`/`<DEV_PASSWORD>` sigue siendo rechazado.
- El táctil de v0.31 no responde. El journal del boot
  `b3a671533e71486d949090199774a7dc`, extraído en sólo lectura a
  `work/v031-rootfs-logs-20260720/`, confirma que Goodix registra el
  dispositivo y recibe datos, pero repite `touch data checksum error`.
- La causa es reproducible: el worktree directo contenía sólo el decodificador
  Samsung inicial. `scripts/build-mainline-kernel.sh` comprobaba únicamente
  `GOODIX_BERLIN_SAMSUNG_EVENT_ID_MASK`, lo consideraba completo y omitía el
  forzado de 16 bytes para PID 6936 y la prelectura de un contacto/26 bytes.
  El guard ahora exige el mensaje final exacto y aplica
  `upgrade-partial-goodix-samsung-events.patch` cuando encuentra el estado
  parcial; los worktrees limpios siguen usando el parche completo original.
- v0.32 conserva el kernel actual `7.2.0-rc3-dirty`, DTS con WCN/PCIe0/PHY
  deshabilitados, Xorg neutro, handoff no-op y ausencia deliberada de módulos.
  El binario contiene el forzado PID 6936 y la fuente compilada usa
  `GOODIX_BERLIN_PRE_READ_TOUCHES=1`. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.32-current-kernel-goodix-no-modules-sm-x910-twrp.zip`,
  22.007.128 bytes, SHA-256
  `c4509790f42bb6cff93e73ca0a7bdd2609d6c2b1f19eb6a6526bac263d5a67b9`.
  Se copió a `/sdcard` y la única comparación local/remota coincide; el
  asistente no flasheó ninguna partición. v0.30 permanece como rollback.
- La prueba física v0.32 valida el resultado esperado: llega a LightDM y el
  táctil responde correctamente. NCM enumera como `UsbNcm Host Device #7`, el
  host obtiene `172.16.42.2/24`, hay ping sin pérdidas a `172.16.42.1` y
  OpenSSH escucha en el puerto 22. La contraseña `phablet/<DEV_PASSWORD>` continúa
  rechazada.
- La rootfs de build sí contiene un hash SHA-512 desbloqueado que valida
  `<DEV_PASSWORD>`, `/bin/ash` figura en `/etc/shells` y sshd usa PAM. Para no modificar
  a ciegas la contraseña persistente de la microSD, v0.33 añade una clave
  Ed25519 de desarrollo mediante `AuthorizedKeysFile
  /etc/ssh/authorized_keys/%u`; la clave privada sólo existe en WSL bajo
  `/root/.ssh/gts9u_pmos` y no se versiona.
- v0.33 reutiliza byte por byte el kernel, DTB y las cinco imágenes Android de
  v0.32; únicamente amplía el overlay de rootfs. ZIP preparado:
  `postmarketos-edge-xfce-mainline-v0.33-goodix-ssh-no-modules-sm-x910-twrp.zip`,
  22.007.913 bytes, SHA-256 previo a la copia
  `cc06f194a62653f731c4ef4238fed4ee047e2fbc2e173244a1f132c3eee6db71`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. Pendiente
  flash manual; el asistente no flasheó ninguna partición.
- La prueba física v0.33 mantiene LightDM, táctil y NCM, pero la clave ofrecida
  (`SHA256:EsZ6dkUkxnvcfUDER6tbuQOKEZ4KRc9RjfYBFnrWQ94`) es rechazada por
  sshd. El ZIP contiene la clave y el drop-in correctos; la nueva carpeta
  `/etc/ssh/authorized_keys` es el único componente cuyo modo no fijaba el
  instalador, y OpenSSH `StrictModes` rechazaría la ruta si TWRP la hubiese
  creado escribible por otros. v0.34 prueba específicamente esa hipótesis.
- v0.34 corrige el defecto general del instalador fijando `0755` en el
  directorio padre de cada fichero extraído. Además evita depender de una
  carpeta nueva: usa `/etc/ssh/gts9uwifi_authorized_keys` y un drop-in `00-*`
  que se procesa antes que la política pmOS y el viejo `90-*` persistente.
  Kernel, DTB e imágenes Android siguen siendo idénticos a v0.32. ZIP:
  `postmarketos-edge-xfce-mainline-v0.34-goodix-ssh-flat-key-no-modules-sm-x910-twrp.zip`,
  22.007.934 bytes, SHA-256 previo a la copia
  `aa92d42f62f5922a0a9713f9eccd8d15e3740942fcb27f170d19f661f8f49fa6`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. Pendiente
  flash manual; el asistente no flasheó ninguna partición.
- La prueba física v0.34 conserva la red USB (`172.16.42.2/24` en el host),
  ping a `172.16.42.1` en 1 ms y OpenSSH 10.3 escuchando en el puerto 22, pero
  vuelve a rechazar la clave ofrecida. Esto refuta que el único bloqueo fuese
  el modo de `/etc/ssh/authorized_keys`. Antes de otra build se inspeccionará
  desde TWRP la rootfs física y el estado real de la cuenta.
- La auditoría offline se conserva en
  `work/v034-auth-audit-20260720-2/`. La rootfs física contiene la clave
  Ed25519 esperada y ambos drop-ins; `/etc/ssh`, el drop-in `00-*` y
  `/etc/ssh/gts9uwifi_authorized_keys` son `root:root` con modos
  `0755/0644/0644`. `phablet` es UID 10000, usa `/bin/ash`, no está bloqueado
  y su hash físico valida `<DEV_PASSWORD>`.
- Ejecutar el propio `/usr/sbin/sshd.pam -T` ARM64 desde TWRP confirma la
  configuración efectiva: `PubkeyAuthentication yes`, `StrictModes yes`,
  `AuthorizedKeysFile /etc/ssh/gts9uwifi_authorized_keys`, contraseña y
  keyboard-interactive habilitados y `AuthenticationMethods any`. No queda un
  error de instalación o precedencia de configuración.
- El intento de ejecutar sshd en `-ddd` dentro del kernel TWRP acepta la
  conexión redirigida por ADB, pero el hijo preauth muere justo después de
  instalar su filtro seccomp, antes del intercambio KEX. Es una incompatibilidad
  del entorno recovery y no reproduce la autenticación del kernel mainline;
  se cerró el proceso y se desmontaron `/run`, `/proc`, `/dev` y la rootfs.
- v0.35 prueba la fase común restante: el drop-in fija `UsePAM no`, deshabilita
  contraseña/keyboard-interactive, exige `AuthenticationMethods publickey` y
  activa `LogLevel DEBUG3`; `StrictModes` permanece habilitado. Kernel, DTB y
  las cinco imágenes Android son idénticos a v0.32. ZIP TWRP:
  `postmarketos-edge-xfce-mainline-v0.35-goodix-ssh-no-pam-no-modules-sm-x910-twrp.zip`,
  22.007.992 bytes, SHA-256
  `7a1de9353d6614130f545f9cdb337818ec24746c00ecdad29ef15a39894ef537`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. Pendiente
  flash manual; el asistente no flasheó ninguna partición.
- La prueba externa posterior no era contra la X910. La host key extraída de
  su microSD es
  `SHA256:1N9kAKdfusq7wxZmypG2PsCpqwhhDu5An+HC3SJAu0E`; el servidor en
  `172.16.42.1` presenta
  `SHA256:jPYjoVxDTlJ6jh50x+qfOlpHkFLqcEVMhJScmQgLuoM`, banner OpenSSH 10.3 y
  resolución `daisy.local`. Es el otro dispositivo pmOS conocido, no la
  tablet.
- Windows confirma dos dispositivos simultáneos: el NCM ajeno es
  `USB\\VID_18D1&PID_D001...`, mientras la X910 aparece como
  `USB\\VID_0000&PID_0002...` con error de solicitud de descriptor en otro
  puerto/hub. Se retiran como falsas todas las conclusiones de autenticación
  externa v0.30–v0.35; siguen válidos los journals offline que demuestran
  `usb0`, DHCP y sshd internos. v0.35 está flasheada, pero su clave no ha sido
  probada contra la tablet real.
- `pnputil /restart-device` sobre el USB desconocido y `/scan-devices` no se
  ejecutaron porque Windows exige elevación y devolvió `Acceso denegado`; el
  estado no cambió. Hace falta aislar el otro USB y reconectar físicamente el
  cable de la X910 mientras v0.35 permanece arrancada.
- Al desconectar el otro pmOS y reconectar la tablet desaparecen por completo
  el NCM, la ruta `172.16.42.0/24` y la dirección host `172.16.42.2`. Sólo
  queda `USB\\VID_0000&PID_0002...` con Code 43: queda demostrado que ésa es
  la X910. Su parent es un hub Genesys `USB\\VID_05E3&PID_0608...`, puerto 4;
  la próxima prueba física es conexión directa al PC, sin ese hub.
- La reconexión posterior no cambia instancia, parent ni ubicación PnP y la
  X910 sigue en Code 43. La instrumentación v0.18 aún imprime cada evento
  DWC3, transición EP0 y SETUP mediante `dev_info`; el journal v0.31 muestra
  huecos repetidos de unos 20–21 ms y reintentos de los mismos descriptores.
- v0.36 añade `remove-dwc3-hotpath-diagnostics.patch`: elimina 18 líneas de
  `printk` en IRQ/EP0, mantiene los dos mensajes de pull-up y los tracepoints
  DWC3. La ruta directa aplica el cleanup a worktrees ya parcheados y el
  paquete pmaports sube a kernel r18. El binario conserva el arreglo Goodix y
  no contiene ya `SM-X910 diag event/ep0/setup`. ZIP preparado:
  `postmarketos-edge-xfce-mainline-v0.36-usb-hotpath-clean-no-modules-sm-x910-twrp.zip`,
  22.007.155 bytes, SHA-256 previo a copia
  `00ad7fb3064124e7f49d49749b44ff148b96f42b9b5d8b55308dfeda1993a387`.
  Copiado a `/sdcard`; la única comparación local/remota coincide. Pendiente
  flash manual; el asistente no flasheó ninguna partición.
- La prueba física v0.36 sigue mostrando en Windows únicamente
  `USB\\VID_0000&PID_0002...` con error de solicitud de descriptor; no aparece
  NCM ni dirección `172.16.*`. Retirar los `printk` del hot path no basta para
  resolver la enumeración. Se mantiene el cleanup y se extraerá el journal
  nuevo antes de modificar de nuevo DWC3, gadget o PHY.

- La auditoría Wi-Fi posterior identifica una diferencia concreta frente al
  FDT stock. WCN7850/Kiwi v2 es `17cb:1107`, usa GPIO80 como WLAN_EN y necesita
  siete rails; el séptimo es L3G 1,2 V. Los DTS upstream SM8550 declaran ese
  LDO3 directamente bajo PM8550VS-G, sin el `vdd-l3-supply` que introdujo el
  ciclo de dependencias de v0.20.
- El journal v0.21 ya demostraba que los siete rails se habilitaban y que
  WLAN_EN empezaba y permanecía alto, pero no que existiera un reset. El
  pwrseq upstream conserva deliberadamente un enable heredado. v0.37 limita al
  compatible WCN7850 un cold-reset: solicita WLAN_EN bajo, espera 5–10 ms y
  después ejecuta la subida normal antes del probe PCIe.
- Para no repetir la regresión de los pingüinos de v0.19, v0.37 integra en el
  kernel PHY QMP PCIe, pwrctrl/pwrseq, QRTR, MHI, rfkill, cfg80211 y mac80211.
  Sólo construye e instala `ath12k.ko.zst` y
  `wifi7/ath12k_wifi7.ko.zst`; `modules.dep` contiene únicamente esa relación
  y `modules.alias` mapea `17cb:1107` al driver Wi-Fi 7.
- La build incremental v0.37 superó dos fallos de herramienta antes de ser
  aceptada: el primer parche manual tenía conteos de hunk inválidos y el build
  `M=` aislado necesitaba copiar `vmlinux.symvers` a `Module.symvers`. Además,
  dos símbolos Kconfig ocultos volvían a `m`; un parche mínimo les da default
  built-in en `ARCH_QCOM`. No se aceptó ninguno de esos intentos parciales.
- El resultado usa release `7.2.0-rc3-dirty`. La validación final confirma el
  DTB (PMU/PCIe0/PHY/L3G), todos los proveedores built-in, exactamente dos
  módulos con vermagic correcto, orden de carga y cadena de dependencias. El
  ZIP supera CRC, manifiestos de imágenes/overlay, modos POSIX, tamaños de las
  cinco imágenes, firmware y alias PCI.
- ZIP TWRP preparado:
  `postmarketos-edge-xfce-mainline-v0.37-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.179.256 bytes, SHA-256
  `b35522406582727052ea768c564ab8c7623891726c1b5b0700cfc5d0d011af5a`.
  Se copió a `/sdcard` y la única comparación local/tablet coincide. El
  asistente no flasheó ninguna partición. Los dos intentos manuales posteriores
  abortaron antes de escribir imágenes porque la rootfs seguía montada en
  `/tmp/pmos-root`; el arranque observado era todavía v0.36.

- La lectura de las particiones desde TWRP confirma ese diagnóstico: `boot`
  conserva el hash v0.36 `bf83c827…2da7` y `vendor_boot` el hash común anterior
  `6793730d…e3f5`; la rootfs no contiene ni
  `/usr/lib/modules/7.2.0-rc3-dirty` ni `ath12k.conf`. El journal carece, como
  corresponde, de PMU WCN, PCIe0 y cold-reset.
- El `last_log.gz` de TWRP registra ambos intentos v0.37 con el mismo aborto:
  `Device or resource busy` al montar `mmcblk1p2` en `/tmp/pmos-root`. El
  instalador no había escrito aún `boot`, por lo que reiniciar no dañó ni
  probó la build nueva.
- v0.38 endurece el instalador: detecta el dispositivo o mountpoint temporal
  ya montado, lo desmonta con comprobación y sólo después monta la rootfs en
  escritura. Kernel, DTB, módulos y firmware son los de v0.37. ZIP:
  `postmarketos-edge-xfce-mainline-v0.38-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.179.387 bytes, SHA-256
  `67c0d7bfda6e41eeca81a0d9494034c0746ee4c78735652c20884dc0e2632d5e`.
  CRC, manifiestos, permisos, imágenes, overlay e instalador están validados;
  se copió a `/sdcard` y la única comparación local/tablet coincide.

- La prueba física v0.38 confirma que el instalador nuevo sí escribió todas
  las imágenes y el overlay. `boot`/`vendor_boot` coinciden con el bundle y la
  rootfs contiene exactamente los dos módulos `7.2.0-rc3-dirty` y su
  configuración de carga. La tablet alcanza el escritorio y conserva el
  táctil, por lo que el aislamiento de módulos evita la regresión visual.
- El boot `5c45011802064b0d99c39349dd5265e3` prueba el cold-reset y la cadena
  previa al driver: `WLAN_EN cold reset value=0`, siete rails habilitados,
  WLAN_EN final en 1, iATU inicializada y root port `17cb:0113`. PCIe termina
  `Device not found`; no aparece `17cb:1107`. `ath12k_wifi7` se inserta pero
  queda sin dispositivo. NetworkManager/rfkill funcionan en userspace.
- La diferencia restante demostrable con stock eran cinco votos de tensión
  expresados como rangos. v0.39 fija S5G=1,000 V, S2G=0,980 V, S4E=0,950 V,
  S4G=1,350 V y S6G=1,900 V; conserva L15B=1,800 V y L3G=1,200 V. Añade
  lecturas pasivas de tensión real, PERST lógico/raw y PARF/DBI LTSSM.
- Build v0.39: kernel `Image.gz`
  `9d080e225c7fb3a5b87abb318e2611e8e37912452cf6e9c6398f7233d26222f0`,
  DTB `80af01d4c3bcca50f7da9b75e4ddc892709fc45c7029ba12428b5c91a1aebbcc`,
  config `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`.
  El DTB final contiene los siete valores exactos y el kernel las trazas
  nuevas; los dos módulos conservan release/vermagic y dependencia correctos.
- ZIP TWRP v0.39:
  `postmarketos-edge-xfce-mainline-v0.39-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.182.376 bytes, SHA-256
  `8fc0877dd30c83095aa2df404f8b52e32c8f3aa0450cbd364fbe0730cafdec18`.
  Pasó CRC, imágenes, overlay, permisos, firmware, módulos y aserciones DTB;
  se copió a `/sdcard` y la única comparación local/tablet coincide.
- La prueba física v0.39 conserva escritorio y táctil, pero no prueba los
  nuevos valores de PERST/LTSSM: S4E 950 mV y S4G 1350 mV fallan antes con
  `devm_regulator_register()=-131`; WCN espera a S6G y la PHY PCIe0 a L3G. El
  proveedor FTSMPS525 sólo admite `300000 + 4000*n` µV hasta 1,372 V y luego
  `1376000 + 8000*n` µV. Los tres votos nominales no representables deben
  redondearse al primer selector superior.
- v0.40 fija S4E=952 mV, S4G=1352 mV y S6G=1904 mV; S2G=980 mV y S5G=1000 mV
  no cambian. Build: `Image.gz`
  `9d080e225c7fb3a5b87abb318e2611e8e37912452cf6e9c6398f7233d26222f0`,
  DTB `2ae3b8fca09dc3f5eb7d038ade1db030ab0cb3210259649473888d3a25789866`,
  config `f20f2ca0c058cad4772bf5af52ff6041c02b2bd5ff74bfc60e25c2fc2af9a42f`.
- ZIP TWRP v0.40:
  `postmarketos-edge-xfce-mainline-v0.40-wcn7850-pcie-cold-reset-sm-x910-twrp.zip`,
  27.182.373 bytes, SHA-256
  `cb911bb9a68fe93c4d8bbfd61866f822d5d5ac39d1586ebf1c1740af0191225d`.
  Kernel/DTB, exactamente dos módulos, alias, firmware, CRC, manifests,
  imágenes, permisos e instalador pasaron; se copió a `/sdcard` y la única
  comparación local/tablet coincide.

## Sensores Qualcomm SSC y funda

- Los sensores integrados no son dispositivos IIO/I²C del AP. Corren dentro de
  la protección `sensorspd` del ADSP y se alcanzan por FastRPC + QMI SSC.
  `CONFIG_QCOM_FASTRPC` debe ser `=y`: como módulo no existe
  `/dev/fastrpc-adsp` en este port.
- El árbol HexagonFS se genera desde los JSON stock con los selectores reales
  `MTP`/SoC 519 y los skels DSP verificados. La caché escrita por Samsung queda
  en el directorio de placa de la microSD; nunca se monta `persist` para
  escritura ni se versionan calibraciones por dispositivo.
- SSC es dueño de SE3/SE4. El `remoteproc_adsp` debe seleccionar sus pinctrl,
  pero no hay que habilitar los controladores GENI I²C del AP: hacerlo disputa
  los buses sin producir muestras del ALS.
- El descubrimiento de SSC tarda más que la publicación inicial de QMI.
  Esperar una **muestra real** de acelerómetro antes de iniciar
  iio-sensor-proxy evita que este salga prematuramente con `No sensors`.
- La suspensión profunda apaga sensorspd. libssc 0.4.4 no recupera su cliente
  QMI, por lo que tras resume hay que arrancar de nuevo la protección, esperar
  SSC y reiniciar SensorProxy. Mutter debe reclamar el nuevo owner D-Bus.
- La recuperación de SSC debe usar una sola unidad systemd cancelable. Un
  `systemd-run --on-active` anónimo por resume deja varias instancias vivas en
  ciclos rápidos; estas compiten con `suspend.target`, reinician sensorspd de
  forma solapada y terminan en `SSC QMI Service not found`. El hook `pre`
  detiene `gts9uwifi-wait-sensor-proxy.service` y el `post` reinicia esa misma
  unidad. En arranque debe ejecutarse después de la recuperación fría del
  panel y reiniciar sensorspd aunque figure activo. v1.09 restaura físicamente
  tanto el control de bloqueo de GNOME como la autorrotación continua.
- Acelerómetro, giroscopio, magnetómetro y brújula producen datos reales.
  GNOME autorrota correctamente con
  `ACCEL_MOUNT_MATRIX=0,1,0;-1,0,0;0,0,1`. Es una medida física validada;
  conservarla aunque la lectura aislada de los JSON stock sugiera otra etapa
  de coordenadas.
- Mutter 50.2 necesita el parche r4 de este port: protege el contador de
  inhibidores, invalida la reclamación cuando cambia el owner de SensorProxy y
  no añade el inhibidor inicial sintético si el panel ya estaba gestionado.
  Sin la tercera parte rota una vez y se detiene.
- El Hall de la funda es TLMM GPIO107 activo bajo y se publica como `SW_LID`.
  `HoldoffTimeoutSec=0` es necesario: el valor por defecto de 30 segundos hace
  que cierres válidos parezcan intermitentes. Cerrar suspende y abrir despierta
  de forma físicamente validada tanto en el greeter como en sesión. La demora
  visible de 2–3 segundos es la duración del resume profundo y del wake de DRM,
  no un evento Hall perdido.
- El ALS Sensortek STK31610 se descubre, pero no produce lux. Se descartaron
  on-change, polling/DRI, petición continua a 5 Hz y divergencias del registro
  nativo. El registro `persist` y el generado son semánticamente iguales para
  todos los ficheros STK31610. La petición física Samsung exacta (mensaje 10,
  protobuf `08 04`) tampoco devuelve un evento, tanto en `ambient_light` como
  en `ambient_light_sub`.
- El ABI de fábrica ya no es una incógnita: el `adsp_ft_common.h` oficial
  enumera `GET_DUMP_REGISTER=9` y `GET_DHR_INFO=12`; `factory.ssc` los traduce
  respectivamente a mensajes SSC 609 y 612 con el test físico de tipo 4. El
  evento esperado es 709/712 y el DHR de luz contiene 16 enteros. Usar esta
  vía para obtener el fallo del STK antes de modificar más recursos.
- Los mensajes repetidos `Handover signaled, but it already happened` no
  prueban un reinicio del bus: con ftrace se observa que los bits SMP2P
  `ready` y `handover` permanecen afirmados y el IRQ anidado vuelve a
  entregarlos al circular tráfico; ADSP, sensorspd y QMI continúan vivos.
- El X910 no expone un sensor proximity: el SSC devuelve UNKNOWN y sus JSON
  stock solo configuran el hijo `ambient_light`.

## USB host con hub alimentado

- Un hub USB-C con alimentación pasante puede conservar su rol PD
  **Source/UFP** mientras la tablet se reinicia: suministra energía, pero en el
  plano de datos sigue siendo el periférico. Si la X910 vuelve como Sink/UFP,
  ambos extremos reclaman UFP y TCPM entra en `Data role mismatch`. El SM5714
  activa de forma explícita la adopción de DFP únicamente para este primer
  mensaje retenido; no se fuerza host por el mero hecho de estar cargando.
- La resincronización inicial de CC/VBUS debe ocurrir después del
  `PORT_RESET_WAIT_OFF` de TCPM. A 250 ms se consumía dentro del reset de
  aproximadamente 1,02 s y se perdía el attach previo al registro del IRQ.
  Una única resincronización a 1.500 ms recupera el partner sin crear un bucle
  de sondeo.
- Este port no instala el árbol genérico de módulos. `usbhid` enlazado a las
  interfaces no basta: `CONFIG_HID_GENERIC=y` crea los nodos base. En un
  receptor Logitech Lightspeed tampoco basta el genérico: el ID `046d:c54d`
  está en la tabla de `hid-logitech-dj` y necesita DJ + HID++ para demultiplexar
  el dispositivo emparejado. v1.50 los integra y descubre el PRO X SUPERLIGHT
  2 DEX `046d:40b8` con `REL_X/REL_Y`, botones y rueda.
- El ciclo `pm_test=platform` que recupera el panel provoca en DWC3 host
  `HS-PHY not in L2` seguido de `xHCI Host System Error`. El role-switch local
  `host → device → host` vuelve a registrar xHCI y reenumera el receptor. v1.49
  automatiza exactamente eso al terminar la recuperación fría y tras futuros
  resumes, pero solo si el rol local ya era `host`; RNDIS/device no se toca.
- Con el hub alimentado se midió simultáneamente Sink/DFP, contrato PD de
  9 V / 1,66 A, xHCI vivo y los inputs HID. Esto valida la coexistencia de
  alimentación y datos host, no la estabilidad de carga rápida a batería baja.
  v1.53 añade la secuencia exacta de Samsung para un PR_SWAP Source→Sink:
  congela CC antes de retirar VBUS, conmuta `CC_CNTL7` sin abrir la conexión y
  libera el hold al recibir `PS_RDY`. Tres ciclos físicos completos recuperaron
  alimentación y ratón al primer intento.
- El hub probado no es un instrumento válido para demostrar datos sin
  alimentación externa. En ese modo la X910 sí publica Source/Host, activa
  boost a 5,1 V/900 mA y conserva xHCI, pero el propio partner declara
  `USB_COMM=false`; PTN3222 acaba en `DEVICE_STATUS=0x0e`,
  `LINK_STATUS=0x01`, sin pull-up downstream. Un atajo v1.54 que completaba el
  PR_SWAP Sink→Source en VSAFE0V pese a no llegar `PS_RDY` redujo la transición
  de 920 a 20 ms, pero produjo el mismo resultado eléctrico y reintentos PD.
  Se retiró de la v1.55 estable.
- Conectar un ratón no debe cambiar la política de orientación de esta slate.
  Mutter r6 ignora `clutter_seat_get_touch_mode()` únicamente en el paquete
  específico de la X910; con el Lightspeed presente se midieron a la vez
  `HasAccelerometer=true` y `PanelOrientationManaged=true`.
- Siguen pendientes una prueba pasiva con hardware distinto,
  almacenamiento/UAS y DP-altmode.

## Lo que no ha funcionado / no repetir

- No volver a forzar `CC_CNTL1=0x49/0x59` y `CC_CNTL3=0x81` después de una
  conexión source/host natural. La traza v1.43 demostró que esa escritura
  genera un `DETACH` inmediato. En DRP natural hay que conservar `0x40/0x80`
  y modificar únicamente la selección Rp.
- No considerar host USB resuelto porque TCPM publique un rol y xHCI cree sus
  root hubs. v1.44 cumplía eso, pero el PTN3222 seguía en `Connect Detect`.
  La prueba válida llegó en v1.48/v1.49: enumeración downstream y dispositivos
  `event*`/`hidraw*` reales después del ciclo de plataforma.
- No omitir el pulso stock `usbpd,otg_det` de GPIO89 al entrar en source. El
  kernel Samsung lo mantiene alto 130 ms antes/en paralelo al boost; v1.45 lo
  reproduce como GPIO opcional.
- No dejar `CONFIG_HID_GENERIC=m` ni aceptar que `usbhid` enlazado equivale a
  un ratón funcional: sin el módulo genérico no aparecen inputs en este port.
- Para Lightspeed `046d:c54d`, tampoco detenerse cuando `hid-generic` crea
  ratón/teclado genéricos del receptor: los reportes del dispositivo emparejado
  están multiplexados. `HID_LOGITECH`, `HID_LOGITECH_DJ`,
  `HID_LOGITECH_HIDPP` y su dependencia `LEDS_CLASS_MULTICOLOR` deben ser
  built-in. La prueba válida es el hijo HID++ `046d:40b8`.
- No volver a programar la resincronización CC a 250 ms. La traza de v1.47
  demuestra que TCPM sigue entonces dentro de `PORT_RESET_WAIT_OFF`.
- No interpretar Source/UFP de un hub alimentado como un paquete PD inválido:
  describe un dock que alimenta a la tablet pero es periférico de datos. La
  solución es adoptar DFP en la tablet de forma opt-in, no resetear PD.
- No alternar roles después de cada resume si el rol actual es `device`: eso
  cortaría RNDIS/SSH hacia un PC. La recuperación de xHCI de v1.49 está
  condicionada a que el role-switch ya diga `host`.
- No seguir cambiando VBUS, PTN3222 o TCPM para obligar al hub `2d79:e001` a
  transmitir datos sin alimentación externa. En ese modo el partner declara
  explícitamente `USB_COMM=false` y nunca presenta pull-up downstream aunque
  la tablet entregue 5,1 V/900 mA. Probar otro adaptador.
- No conservar el experimento `complete_pr_swap_on_vsafe0v`: saltarse el
  `PS_RDY` ausente del hub acortó el cambio de rol pero no habilitó sus datos y
  añadió hard-reset/reintentos. La v1.55 vuelve al estado TCPM estándar.
- No usar el `touch-mode` global de Mutter como sinónimo de postura en la
  X910. Cualquier puntero externo lo desactiva y, sin r6, también oculta el
  bloqueo y detiene la autorrotación.
- No escribir solo `boot` después de recrear el árbol `O=`. El kernel genera
  una clave de firma nueva y lockdown rechaza los ath12k antiguos con
  `Operation not permitted`. Sincronizar siempre los dos módulos de la misma
  build en la microSD; el ZIP ya lo hace mediante su overlay.
- No asumir que un `M=` aislado funciona porque quedaron objetos antiguos.
  En un árbol limpio falta `scripts/module.lds` hasta ejecutar
  `modules_prepare`; el pipeline lo invoca explícitamente antes de ath12k.

- No gestionar `vreg_l1b_1p8`/`vreg_l16b_3p0` desde PAS como primer arreglo
  del ALS. La prueba v1.10 reprodujo el ciclo downstream y dejó ambos raíles
  votados a 1,8/3,0 V, pero el servicio QMI SSC dejó de publicarse aunque el
  remoteproc figurase `running`. Se revirtió a los raíles `always-on` y al
  boot/vendor_boot estables; rotación y sensores volvieron. Tampoco interpretar
  el spam de handover SMP2P como evidencia de un crash.

- No dejar `dev_info` por evento dentro de `dwc3_process_event_entry()`,
  `dwc3_ep0_interrupt()` ni el parser SETUP: la traza ya cumplió su propósito y
  el coste síncrono coincide con los reintentos/timeout del host. Usar los
  tracepoints existentes para futuros diagnósticos de alta frecuencia.
- No asumir que retirar esos `dev_info` resuelve por sí solo Code 43: v0.36
  elimina las cadenas del binario y el fallo externo persiste. Hace falta
  comparar el journal limpio y la secuencia efectiva del host.
- No identificar un endpoint SSH sólo por `172.16.42.1`: varios dispositivos
  pmOS reutilizan esa subred USB. Antes de atribuir cualquier resultado a la
  X910 hay que comparar su host key física
  `SHA256:1N9kAKdfusq7wxZmypG2PsCpqwhhDu5An+HC3SJAu0E` y el banner OpenSSH
  10.4. `daisy.local`, OpenSSH 10.3 y fingerprint `jPYjoVxD...` pertenecen al
  otro dispositivo.
- No atribuir el rechazo de la clave únicamente al modo del directorio creado
  por TWRP: v0.34 usa un fichero plano bajo `/etc/ssh`, fija el padre a `0755`
  y el rechazo persiste. El hardening del instalador se conserva, pero falta
  auditar cuenta, configuración efectiva y ficheros físicos antes de concluir
  la causa de autenticación.
- No usar la presencia de un marcador antiguo del parche Goodix como prueba de
  que el arreglo está completo. El worktree directo puede contener el
  decodificador Samsung sin el forzado PID 6936 ni la prelectura de un solo
  contacto; la guarda debe exigir la cadena final exacta y actualizar el
  estado parcial.
- Ejecutar WSL desde el usuario de sandbox: devuelve
  `WSL_E_DISTRO_NOT_FOUND` aunque las distros sí existen para la usuaria.
- Pasar una línea compleja con paréntesis, `$()` y comillas mediante
  `wsl ... bash -lc`: PowerShell/WSL altera el quoting. Usar scripts.
- No dejar `/dev/block/mmcblk1p2` montada en `/tmp/pmos-root` antes de flashear
  un ZIP con overlay. v0.37 abortó correctamente antes de escribir imágenes y
  el reinicio arrancó v0.36, creando una falsa prueba Wi-Fi. Desde v0.38 el
  instalador limpia de forma explícita ese montaje temporal.
- No interpretar `regulator_bulk_enable() = 0` como prueba de que WCN recibe
  los votos stock: sólo acredita que los proveedores aceptaron habilitarse.
  Comprobar las tensiones efectivas de los siete rails, como instrumenta v0.39.
- No fijar directamente 950000, 1350000 o 1900000 µV como `min=max` en un
  PM8550VS FTSMPS525 mainline: no son selectores válidos y el proveedor entero
  falla con `-ENOTRECOVERABLE`. Usar 952000, 1352000 y 1904000 µV,
  respectivamente, que son el redondeo físico hacia arriba de esos votos.
- No depurar firmware, board data ni ath12k mientras PCIe no enumere
  `17cb:1107`. v0.38 inserta el módulo y carga el plugin Wi-Fi, pero el fallo
  ocurre antes, durante la detección eléctrica del endpoint por el LTSSM.
- No ordenar los `sha512sums` de un APKBUILD de forma distinta a `source=`:
  abuild empareja ambas listas por posición. La primera construcción rootfs
  r14 detectó el orden incorrecto de cuatro parches aunque la build directa
  los aplicaba; se corrigió antes de aceptar el paquete.
- No confiar sólo en los bits POSIX almacenados por ZIP para un overlay TWRP:
  `unzip -p > destino` no los aplica y el instalador v0.24 imponía después
  `0644`. Tampoco copiar un fichero normal dentro de un directorio `.wants`:
  systemd exige un enlace y lo ignora explícitamente. Desde v0.25 el manifiesto
  transporta el modo y el instalador crea el symlink de activación.
- No asumir que `ID` en `/etc/os-release` carece de comillas. El rootfs físico
  usa `ID="postmarketos"`; el validador TWRP debe aceptar las dos
  representaciones exactas antes de rechazar la microSD.
- No invocar el bundle X910 con `APPEND_DTB_TO_KERNEL=0` o
  `DISABLE_RUNTIME_DTBO=0`: ABL vuelve a su fork ufdt, rechaza el DTB base y
  entra en Odin antes de Linux. Desde v0.19.2 ambos valores seguros son los
  defaults del script y cualquier experimento debe quedar explícito.
- No volver a declarar `vdd-l3-supply = <&vreg_s4g...>` en el contenedor de
  reguladores PM8550VS-G ni sustituir el reset por un `output-high` estático:
  esa combinación de v0.20 crea el ciclo y el bloqueo a 18,987144 s. LDO3 sí
  es el rail real de 1,2 V, pero debe declararse directamente como hacen los
  DTS upstream SM8550; WLAN_EN necesita una transición baja→alta controlada.
- No mantener PCIe0/WCN habilitado mientras se valida el primer hito estable:
  v0.21 completa una vez la secuencia, pero boots posteriores v0.21/v0.22 se
  detienen intermitentemente antes de LightDM durante los probes repetidos.
  v0.23 ya valida los tres nodos aislados y completa userspace; reactivarlos
  sólo como un bloque desde esta base estable con SSH.
- No interpretar una pantalla inmóvil en los pingüinos como cuelgue del kernel
  sin consultar el journal persistente o probar RNDIS. v0.23 llega a
  `graphical.target`, Xorg/greeter y OpenSSH; su síntoma visual es un fallo de
  handoff/repintado entre VT1 y VT7 separado del estado de userspace.
- No seguir atribuyendo la imagen estática a boot, LightDM, X, greeter, VT ni
  al contenido dibujado en fbdev: el
  servicio corregido ejecuta `chvt 1`/`chvt 7` y `fgconsole` confirma VT7. El
  DDX fbdev abre `/dev/fb0` y v0.26 demuestra con una captura completa que el
  greeter correcto ya está en sus 21.880.320 bytes mientras el panel conserva
  los pingüinos. v0.27 ejecutó además un ciclo completo de apagado y
  reactivación KMS sin efecto físico: no queda nada que corregir en X ni en
  las VT.
- La hipótesis MMCX/rpmhpd quedó REFUTADA por v0.28: con
  `dispcc/videocc/camcc/gpucc-sm8550` bloqueados el journal confirma que no
  cargan y que `qcom-rpmhpd ... sync_state() pending` sigue reteniendo los
  dominios, pero el panel sigue en los pingüinos. Bloquearlos no basta; se
  mantienen en el blacklist sólo porque no tienen uso antes del stack msm
  nativo, no como arreglo del scanout.
- El scanout físico muere ~18–20 s, antes de X (v0.21 con `console=tty0` se
  congeló a 20,2 s). El sospechoso real son las llamadas SCM a TrustZone de
  `qcom-ice` y `qcomtee` (18,59/18,62 s), nuevas desde v0.19 y ausentes en las
  builds `-dirty` que mostraban el greeter. En XBL Samsung la TZ suele ser
  dueña del splash. v0.29 las bloquea; si no arregla, `console=tty0` fechará el
  punto exacto.
- No aceptar todavía la hipótesis SCM de v0.29 como causa raíz: que
  `qcom_ice`/`qcomtee` aparezcan cerca de la ventana de congelación es una
  correlación, y v0.19 activó simultáneamente todo el árbol de módulos. v0.30
  recupera primero el control pre-v0.19 exacto; sólo después se hará un bisect
  acumulativo de módulos desde una imagen físicamente visible.
- No usar `Set-Content`/`Out-File` de PowerShell para scripts que ejecuta bash
  en WSL: escriben CRLF y `set -euo pipefail` falla con `invalid option name`.
  Usar la herramienta Write (LF) o `dos2unix`.
- No comparar sólo configuraciones y DTS al buscar regresiones entre builds:
  verificar también el release del kernel arrancado frente a
  `/lib/modules/`. v0.4–v0.18 corrían `7.2.0-rc3-dirty` sin ningún módulo y
  eso ocultaba efectos que sólo aparecen cuando el árbol de módulos casa
  (v0.19+).
- Asumir que `fastboot boot` existe por tratarse de un dispositivo Android;
  Samsung suele exponer Download Mode/Odin, no fastboot estándar.
- Capturar recursivamente todo `/sys/firmware/devicetree/base` por SSH tardó
  demasiado y dejó un árbol parcial. `capture-live-fdt.sh`, que obtiene
  `/sys/firmware/fdt`, es la vía correcta.
- Incluir directamente `sm8550-samsung-q5q.dts` fue descartado antes de
  compilar: el Fold5 redefine carveouts MPSS propios. El DTS X910 debe incluir
  `sm8550.dtsi` y sólo trasladar datos contrastados de nuestra placa.
- El primer parche del Makefile contenía los caracteres `\\t` en lugar de un
  tabulador real y no aplicó. Está corregido.
- Una compilación que pedía también todos los módulos excedió los diez minutos
  del runner y fue terminada. El script directo construye ahora sólo
  `Image.gz` y el DTB; los módulos completos quedan para el package pmOS.
- Usar una sola partición rootfs deja un initramfs de unos 15,15 MiB, imposible
  para `init_boot` de 8 MiB. `pmbootstrap` además impide `initramfs-extra` con
  `--single-partition`; la solución validada es la imagen estándar de dos
  particiones, no recortar módulos tempranos necesarios.
- El primer package device falló por mantenedor no RFC822, dependencia ausente
  de `android-tools` y falta de `deviceinfo_flash_pagesize`; están corregidos.
- No usar directamente `/boot/vmlinuz` en Android: `zinstall` genera un wrapper
  EFI zboot. Tampoco mezclar el `Image.gz` de la build directa con módulos del
  APK. El bundle extrae y verifica el payload del zboot empaquetado.
- Los AVB salts aleatorios y un CPIO vacío con timestamps variables hacían
  cambiar los hashes. Los salts derivan ahora del SHA-256 de la imagen y el
  vendor ramdisk vacío usa timestamp cero y `cpio --reproducible`.
- `zipfile.writestr()` añadía la hora actual a dos miembros y cambiaba el SHA
  del ZIP aunque las imágenes fueran idénticas. Todos los miembros usan ahora
  época ZIP fija; dos paquetes mainline y dos rollback resultaron idénticos.
- No asumir que una partición presente bajo `/dev/block/by-name` es escribible.
  En este TWRP `vbmeta` apunta correctamente a `sde15`, pero el kernel la marca
  RO y `blockdev --setrw` no lo cambia. El instalador debe prevalidar el flag RO
  y los bytes AVB flags antes de escribir las demás particiones.
- No interpretar la pantalla Samsung con overlay RPMB/código de barras como
  un panic de Linux. En la prueba v0.1 fue Odin iniciado deliberadamente por
  ABL tras rechazar el DTB, y el diagnóstico fiable estaba en
  `/proc/last_kmsg`, no en `pstore`.
- No usar un DTB mainline con sólo compatibles upstream en esta cadena de
  arranque Samsung. ABL necesita además sus compatibles Qualcomm legacy,
  `qcom,msm-id` y `qcom,board-id` en la raíz.
- No dar por suficiente que un overlay funcione con `fdtoverlay` de libfdt.
  El fork ufdt de ABL falló con el DTB v0.2 sin `/__symbols__`, aunque el
  overlay usaba `target-path = "/"` y las herramientas estándar lo aceptaban.
  Todo DTB destinado a `vendor_boot` debe compilarse con `-@` y el validador
  debe exigir `/__symbols__`.
- No seguir modificando el no-op para el fork ufdt Samsung: v0.2 sin símbolos
  y v0.3 con 474 símbolos fallaron en el mismo punto. v0.4 evita por completo
  esa ruta mediante el fallback appended-DTB documentado en ABL.
- No considerar v0.4 un arranque completo: aunque ABL entregó el control y
  simpledrm mostró Linux, el firmware reinició el SoC con
  `TZBSP_ERR_FATAL_NOC_ERROR` antes de demostrar rootfs, SD o red. Pstore quedó
  vacío y el bloque NoC del log Samsung está cifrado.
- No omitir los carveouts Samsung al usar appended-DTB. El `sm8550.dtsi` base
  cubre las reservas Qualcomm comunes, pero no las reservas específicas que
  normalmente aporta el overlay X910; v0.5 las incorpora explícitamente.
- No asumir que esos carveouts resolvían el reset: v0.5 reproduce el mismo
  fatal NoC que v0.4. La evidencia nueva del vídeo sitúa el corte durante el
  probe de los interconnects LPASS, inmediatamente antes de `7e40000`.
- No esperar que pstore v0.4/v0.5 aparezca automáticamente en TWRP: recovery
  arranca con su propio DT y no registra el backend ramoops mainline. v0.6 usa
  en su lugar el formato `sec_log_buf` nativo que el recovery sí entiende.
- No seguir atribuyendo el fatal a `lpass_ag_noc`: v0.6 lo deshabilitó y el
  reset persistió. Tampoco inferir el culpable sólo por la última línea de
  retorno; v0.7 registra el inicio de cada probe antes del acceso peligroso.
- No atribuir el fatal v0.7 a `sdhc_2`: la traza previa demuestra que la última
  llamada es `sm8550-tlmm`. Tampoco copiar las reservas `<36 4>, <50 2>` del
  Fold5: el FDT X910 sólo acredita GPIO36–39.
- No asumir que `/proc/last_kmsg` conserva el boot anterior tras cualquier tipo
  de reinicio: en v0.8 el reinicio manual dejó `previous_index` apuntando al
  recovery previo. v0.9 mantiene ese índice sincronizado desde mainline.
- No dejar TWRP esperando antes de extraer el log: su kernel downstream es muy
  verboso y llena los 2 MiB en aproximadamente 17 minutos.
- No seguir usando `sec_log_buf`/`last_kmsg` para este panic: v0.10 acaba en
  `XBL(... restored from storage)` y no conserva mainline. La foto de la
  consola es la evidencia fiable hasta disponer de pstore o USB.
- No asumir que `export_logs()` garantiza una captura USB. En la prueba v0.10
  no enumeró `PMOS_LOGS`, ACM ni NCM/RNDIS; el host sólo vio errores de
  descriptor. Hasta arreglar USB, usar pantalla y persistencia en la SD.
- No empaquetar el initramfs genérico X910 como gzip aunque sea un stream
  válido y mainline tenga `CONFIG_RD_GZIP`. Con el vendor ramdisk LZ4, Samsung
  ABL produjo un initrd que falló por magia inválida. Ambos deben usar LZ4
  legacy como el firmware stock y el validador lo exige desde v0.11.
- No confiar en que ABL deje el repetidor NXP eUSB2 listo para mainline. v0.11
  llega al userspace pero DWC3 termina en `-ETIMEDOUT` y el host sólo ve
  errores de descriptor. Hay que describir, alimentar, sacar de reset e
  inicializar explícitamente el NXP por I2C antes del core USB.
- No considerar suficiente la descripción upstream inicial del PTN3222 ni
  integrar GPI DMA sin comprobar el hardware: v0.12 arranca hasta LightDM,
  pero físicamente siguen sin funcionar táctil ni enumeración USB. El journal
  persistente debe decidir el siguiente cambio y no se añadirán overrides a
  ciegas.
- No usar la propiedad genérica `drive-strength` en un GPIO del controlador
  `qcom-spmi-gpio`: el probe falla con `pin_config_group_set`. Para este reset
  hay que reproducir `qcom,drive-strength` y el resto del estado PMIC stock.
- No asumir que `point_struct_len` del IC_INFO sea fiable en firmware Samsung.
  El GT9916/PID 6936 anuncia ocho pero emite 16; confiar en esa metadata hace
  que bytes del propio evento se interpreten como checksum.
- No considerar completa la inicialización del PTN3222 porque el driver
  mainline controle rails y reset. En la X910 son obligatorias cuatro
  escrituras I2C de tuning acreditadas por el FDT y los logs Samsung.
- No aumentar la primera lectura Goodix Samsung a dos contactos. v0.14 pide
  42 bytes y bloquea el canal GPI-I2C; preleer sólo uno mantiene la transferencia
  en 26 bytes y permite completar el resto únicamente si el contador lo exige.
- No eliminar la PHY SuperSpeed del nodo DWC3 sin seleccionar UTMI como PIPE.
  El core USB necesita ese reloj para liberar el soft reset incluso cuando el
  enlace se limita deliberadamente a `high-speed`.
- No seguir tratando v0.15 como un fallo de DWC3 o userspace de red: el journal
  demuestra core, gadget, `usb0`, DHCP y SSH activos. El fallo externo de
  descriptor queda acotado a PHY/repetidor/señal física.
- No volver a atribuir el síntoma USB de v0.18 a PHY, PTN3222, DWC3, IRQ o EP0:
  el host completa todos los requests de control hasta configurar la función.
  La siguiente variable justificada es el tipo de función de red; v0.19 prueba
  RNDIS explícito por compatibilidad con Windows.
- No dejar `CONFIG_INPUT_EVDEV=m` en una build directa que no instala módulos:
  el dispositivo puede registrarse como `input0` sin crear `/dev/input/event*`.
  Desde r8 EVDEV es built-in y el validador lo exige.
- No retirar `pd_ignore_unused` esperando que eso fuerce un ciclo temprano de
  `MDSS_GDSC`: v0.99 arrancó con el flag realmente ausente, pero la primera
  lectura del DDIC siguió siendo `00 00 00`. El apagado de dominios no usados
  ocurre demasiado tarde, cuando el display ya ha reclamado MDSS.
- No interpretar el suspend/resume como una llamada adicional a
  `msm_mdss_reset()`: ese helper solo se ejecuta durante `probe`. La diferencia
  relevante es el suspend atómico del pipeline seguido por el runtime PM de
  DPU/DSI/PHY y el colapso genpd del padre MDSS.
- No repetir `unbind`/`bind` de `msm_dsi`: no recupera el DDIC y desmonta el
  display sin ofrecer una ruta de recuperación en vivo.
- No basta con colapsar `MDSS_GDSC` antes de `of_platform_populate()`: v1.00
  ejecutó un ciclo runtime PM explícito del padre antes de crear DPU/DSI/PHY,
  arrancó con el kernel nuevo y aun así el primer ID fue `00 00 00`. El orden
  que repara el panel necesita que el pipeline DRM completo ya exista.
- `pm_test=devices` NO recupera el panel: vuelve automáticamente pero el ID
  sigue en `00 00 00`. `pm_test=platform` SÍ lo recupera a `80 00 04`; esa es
  la frontera mínima medida. No hace falta RTC porque el propio modo de prueba
  espera cinco segundos y retorna.
- Aunque `ignore_console_null` consigue que `tty0` y `ttyMSM0` queden activas,
  no puede mostrar verbose mientras el DDIC siga en `00 00 00`: el framebuffer
  console funciona, pero el panel físico aún no acepta imagen. No volver a
  confundir ausencia visual con ausencia de consola.
- No forzar el STK31610 de `on-change` a continuo esperando que aparezcan
  medidas: el DSP acepta la petición estándar de 5 Hz pero no entrega ni una
  indicación en 30 segundos. La variante de libssc era diagnóstica y fue
  retirada.
- No copiar el registro de sensores completo desde `persist`: para STK31610 es
  semánticamente idéntico al generado; las únicas 12 entradas ausentes son
  calibraciones dinámicas del giroscopio. Además, `persist` contiene datos
  propios del dispositivo y se mantiene siempre `ro,noload`.
- No habilitar los controladores AP de los hubs I²C SE3/SE4 para buscar el ALS.
  Esos buses pertenecen a SSC; Linux puede inicializar el SE3 y ver otro
  periférico, pero los STK31610 no responden y el firmware deja de ser el dueño
  coherente del bus.
- No interpretar una apertura rápida fallida como pérdida del evento Hall:
  se midió `Lid opened` incluso 0,13 s después de `PM: suspend entry` y el
  kernel completó el resume. El fallo observado estaba en la cola gráfica.
- No volver a usar timers anónimos `systemd-run --on-active` para despertar el
  display. Se retrasaron entre 7 y 16 segundos y una petición antigua llegó a
  solaparse con el siguiente suspend. Desde v1.08 hay una sola unidad
  cancelable: `pre` la detiene y `post` la reinicia.
- El ANA38407 stock declara `samsung,delayed-display-on`. Mostrarlo desde
  `prepare` permite que el panel vea el flujo DSC antes de que el bridge esté
  habilitado y puede dejar ruido de colores en GRAM. v1.08 mantiene `0x29` en
  `.enable`, `0x28` en `.disable` y reserva sleep-in/rails para `.unprepare`.
- No mantener votos fijos de los clocks QUP del hub de sensores. Se probaron
  SE3/SE4 y después AHB/core/SE3/SE4 sin obtener lux ni cambiar los 64 bytes a
  cero de DHR; el pinctrl ya acredita que SSC posee ambas líneas.
- No usar el logger FARF de `hexagonrpcd` como si fuese una traza disponible:
  la variante síncrona bloquea el daemon y la asíncrona necesita
  `libadspmsgd_adsp_skel.so`, ausente del firmware X910. Se conserva r4.
- No añadir al panel mainline avisos COPR o de brillo para intentar despertar
  el ALS. La configuración extraída del `boot.img` oficial X910 5.15.153 no
  compiló esas opciones y enviarlas por el mismo cliente SSC tampoco generó
  muestras.
- No copiar la configuración ALS de Xiaomi Pad 6. Comparte transporte
  HexagonFS/libssc, no sensor: TCS3701/TSL2522/BU27030 usan parámetros que
  contradicen el registro nativo del STK31610. La nota A52/A72 sobre brillo
  automático describe artefactos de panel y no aporta un ALS SSC funcional.
- No instanciar STK31610 como `sensortek,stk3310`. El driver IIO mainline no
  declara STK31610/STK3A6 ni existe documentación pública fiable de su mapa de
  registros; además el bus pertenece al DSP.
- El SM5714 MUIC contiene el conmutador físico D-/D+ del USB-C. Para OTG sin
  VBUS entrante hay que desactivar BC1.2 (`CNTL[1]=1`) y seleccionar USB manual
  (`MANUAL_SW=0x89`). Source/Host, boost y xHCI pueden existir sin que ningún
  periférico sea visible si se omite esta ruta.
- `SM5714_REG_STATUS1.VBUS_POK` solo refleja una fuente externa. Mientras el
  propio SM5714 genera VBUS con su boost OTG sigue a cero; `tcpc.get_vbus()`
  debe combinarlo con el estado OTG del cargador. De lo contrario TCPM imprime
  `VBUS off` y desmonta `SRC_ATTACHED` exactamente tras `tSrcTurnOn=480 ms`.
- No retrasar la ruta MUIC hasta después de crear xHCI. v1.58 conservó el
  attach gracias al arreglo de VBUS, pero dejó el hub sin pull-up. v1.60 abre
  D-/D+ de forma síncrona dentro de `set_otg(true)`, antes del boost y de que
  TCPM exponga host. En hardware enumera Genesys `05e3:0610`, RTL8153
  `0bda:8153` y Logitech `046d:c54d` alimentados solo por la tablet.
- El ciclo `pm_test=platform` del panel todavía provoca un HSE de xHCI; el
  helper host-only existente lo recrea y, con el MUIC ya bien encaminado, los
  tres dispositivos se reenumeran. PTN3222 mide `0a/05` después, frente a
  `0e/01` cuando solo había Connect Detect.
- El RTL8153 del hub solicita `rtl_nic/rtl8153a-3.fw`. El paquete correcto no
  es `linux-firmware-realtek`, sino `linux-firmware-rtl_nic`; device r44 lo
  incluye como dependencia. Tras instalarlo en vivo y reenlazar r8152,
  `ethtool -i` informa `rtl8153a-3 v2 02/07/20`. No declarar Ethernet
  funcional hasta medir enlace y tráfico con un cable conectado.
- Una build limpia de kernel r102 descubrió que
  `ignore-console-null.patch` tenía una cabecera de hunk mal contada
  (`+16` frente a 15 líneas reales). El pipeline directo había tolerado el
  contenido, pero `abuild` lo rechazó como parche malformado. Kernel r103
  corrige únicamente los contadores/metadatos del parche; el código resultante
  no cambia.
- El almacenamiento USB 2.0 clásico funciona a través del hub pasivo:
  `usb-storage` crea un disco SCSI removible de 14,6 GiB, GNOME automonta su
  partición FAT32 y una lectura directa de 128 MiB alcanza 20,4 MB/s sin
  errores. No declarar UAS validado: la unidad `346d:5678` no ofrece una
  interfaz UAS.
- El HPD DisplayPort de esta placa llega fuera de banda dentro del Status VDO
  de Type-C. Para que `drm_connector_oob_hotplug_event()` encuentre el
  conector bridge de MSM DP, el puente terminal debe conservar el `of_node`
  del controlador. Con ello el dock real selecciona pin D, entrega un EDID de
  256 bytes y GNOME muestra físicamente 1920×1080 a 60 Hz en la capturadora.
- El HPD de un dock presente durante el arranque NO puede activar el encoder
  DP antes del `pm_test=platform` usado para recuperar el ANA38407. v1.63
  terminaba cada journal en `PM: suspend entry` y reiniciaba a los cinco
  segundos. El DTS X910 y el puente MSM DP de v1.64 guardan el primer HPD y lo
  reproducen después de `PM_POST_SUSPEND`; el panel pasa a `80 00 04`, el
  ciclo retorna y GDM arranca.
- No usar `active=no` como solución de arranque mientras GNOME ya conduce el
  monitor externo. La prueba desmontó el pipeline en uso, acabó reiniciando y
  dejó el dock en Exit Mode sin un nuevo flanco CC; ni un reboot de la tablet
  ni un rebind del SM5714 equivalen a desconectar físicamente el partner.
- No conservar únicamente Host ni retrasar más la resincronización TCPM para
  recuperar un dock alimentado tras reboot. v1.66 conservó xHCI pero el partner
  no volvió a anunciar PD/altmodes; v1.69/v1.70 siguieron acabando Sink/Device.
  El SM5714 necesita un flanco CC real y, después, vaciar `RX_BUF_ST` antes del
  reset de protocolo. Sin ese flush, el primer Source_Capabilities podía quedar
  seguido por un hard reset retenido antes de que TCPM enviase Request.
- Los siete objetos que el SM5714 expone para este cargador/dock incluyen cuatro
  PDO fijos válidos y tres entradas finales malformadas. No inventar ni reescribir
  APDOs: TCPM negocia de forma estable el PDO fijo de 9 V/1,66 A cuando el
  transporte RX está limpio. Corregir el framing largo queda separado y no es
  requisito para DisplayPort.

## Referencias locales

- `../port/README.md`: estado final del port Ubuntu Touch.
- `../port/docs/porting-log.md`: investigación y bring-up detallados.
- `../port/docs/sm-x910-x910xxs5cyg1-firmware-inventory.md`: boot chain y
  firmware.
- `../port/docs/source-compatibility-matrix.md`: kernel y módulos Samsung
  probados.
- `../port/sources/samsung-gts9u/`: adaptación downstream funcional.
