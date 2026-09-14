# Panel ANA38407 / AMSA46AS02 — datos para el driver DRM mainline

Fuente: `SM-X910_EUR_16_Opensource.zip` → `Kernel.tar.gz` →
`vendor/qcom/opensource/display-drivers/msm/samsung/GTS9U_ANA38407_AMSA46AS02/`.
El framework downstream (`ss_dsi_panel_*`) es propietario y enorme, pero el
**Panel Data File** (`*_PDF.h`) codifica las secuencias DCS como texto: se
decodifica juntando todos los tokens `0xNN` del fichero y pasándolos a bytes
(durante el bring-up se hizo en scratch y quedó registrado en la sesión 57 de
`porting-log.md`: 1797 líneas, 34 bloques de comandos con las macros YA
expandidas, al contrario que el DTBO, donde eran `${MACRO}` sin resolver). El
ZIP y esos temporales se retiraron al congelar v1.71; la implementación
reproducible vigente es
`pmaports/device/testing/linux-samsung-gts9uwifi-mainline/panel-samsung-ana38407.c`.

## Identidad y timings (del DTBO, confirmado)

- SDC / Anapass **ANA38407**, modelo AMSA46AS02, **modo comando** DSI, 4 carriles,
  24 bpp, TE por pin. Reset GPIO 125, TE GPIO 86. Reset seq `<0 10 1 1>`.
- Resolución de scanout usada por simpledrm: **2960 x 1848**.
- **DSC** obligatorio. OJO: hay dos parametrizaciones:
  - PPS del driver (`DSC_SETTING` en el PDF): comentario `W=2800 H=1752
    Slice_W=1400 Slice_H=12`, PPS real en el comando `WT 0x0A ...` (ver abajo).
  - Modos del DTBO `wqxga*`: 2960x1848 slice 1480x77, 2 encoders. 
  Para la primera luz conviene fijar UN modo y su PPS coherentes; validar cuál
  encaja con 2960x1848 (probablemente el PPS del DTBO, no el del PDF).

## Secuencia de ENCENDIDO (reconstruida, expandiendo macros)

Orden efectivo de `samsung,mdss_dsi_on_tx_cmds` (DTBO) +
`POWER_ON_PRE/POST_SETTING` (PDF). Formato DSL: `W`=DCS write,
`WT`=write long, `R`=read, `Delay Nms`. Las parejas `0xF0 0x5A 0x5A` /
`0xF1 0x5A 0x5A` son las *level keys* (unlock), y `0xA5 0xA5` las cierra.

```
# --- sleep out ---
W 0x11                       # DCS SLEEP_OUT
Delay 120ms

# --- VBP_SETTING_FOR_SDC_IP ---
W 0xF0 0x5A 0x5A
W 0xF1 0x5A 0x5A
W 0xC1 0x0A
W 0xB0 0x03
W 0xC0 0x0F 0x00 0x00 0x00 0x09 0xFD 0x81
W 0xF0 0xA5 0xA5
W 0xF1 0xA5 0xA5

# --- DISPLAY_ON_DELAY_SETTING ---
W 0xF0 0x5A 0x5A
W 0xF1 0x5A 0x5A
W 0xC1 0x23
W 0xB0 0x03
W 0xC0 0x0F 0x00 0x00 0x00 0x01 0x04 0x81
W 0xF0 0xA5 0xA5
W 0xF1 0xA5 0xA5

# --- MX_IP_ENABLE ---
W 0xF0 0x5A 0x5A
W 0xF1 0x5A 0x5A
W 0xC1 0x23
W 0xB0 0x03
W 0xC0 0x0F 0x00 0x00 0x00 0x09 0xB2 0x81
W 0xF0 0xA5 0xA5
W 0xF1 0xA5 0xA5

# --- TCON_INTR_SETTING (0xC1 0x02 = TE Active Low) ---
W 0xF0 0x5A 0x5A
W 0xF1 0x5A 0x5A
W 0xC1 0x02
W 0xB0 0x03
W 0xC0 0x0F 0x00 0x00 0x00 0x14 0x46 0x81
W 0xC1 0x13
W 0xB0 0x03
W 0xC0 0x0F 0x00 0x00 0x00 0x08 0xCF 0x81
W 0xC1 0x05
W 0xB0 0x03
W 0xC0 0x0F 0x00 0x00 0x00 0x09 0xCD 0x81
W 0xF0 0xA5 0xA5
W 0xF1 0xA5 0xA5

# (rev B-a-B) UPIM_SSCG_SETTING  -> ver PDF líneas 262-278

# --- TE_ON ---
W 0xF0 0x5A 0x5A
W 0x35 0x00                  # DCS SET_TEAR_ON
W 0xF0 0xA5 0xA5

# --- TSP_SYNC_ON (revA) / TSP_SYNC_SETTING (revC+) --- ver PDF 288-307

# --- DSC_SETTING (PPS) ---
W 0xF0 0x5A 0x5A
WT 0x07 0x01                 # DCS COMPRESSION_MODE = on
WT 0x0A 0x11 0x00 0x00 0x89 0x30 0x80 0x07 0x38 0x0B 0x90 \
       0x00 0x4D 0x05 0xC8 0x05 0xC8 0x02 0x00 0x03 0xE5 \
       0x00 0x20 0x0B 0x07 0x00 0x14 0x00 0x0C 0x01 0x44 \
       0x00 0x7A 0x18 0x00 0x10 0xD0 0x03 0x0C 0x20 0x00 \
       0x06 0x0B 0x0B 0x33 0x0E 0x1C 0x2A 0x38 0x46 0x54 \
       0x62 0x69 0x70 0x77 0x79 0x7B 0x7D 0x7E 0x01 0x02 \
       0x01 0x00 0x09 0x40 0x09 0xBE 0x19 0xFC 0x19 0xFA \
       0x19 0xF8 0x1A 0x38 0x1A 0x78 0x1A 0xB6 0x2A 0xF6 \
       0x2B 0x34 0x2B 0x74 0x3B 0x74 0x6B 0xF4
W 0xF0 0xA5 0xA5

# DIA_SETTING (W 0x91 0x02=on/0x00=off), BRIGHTNESS_SETTING, SP_SETTING (0xC3 0x02)
Delay 50ms
# VRR_SETTING  -> ver PDF 61-90

# --- POWER_ON_POST_SETTING (display on) ---
W 0xF0 0x5A 0x5A
W 0x29                       # DCS SET_DISPLAY_ON
W 0xF0 0xA5 0xA5
```

## Secuencia de APAGADO

```
W 0x28                       # DCS SET_DISPLAY_OFF
W 0x10                       # DCS SLEEP_IN
Delay 100ms
```

## Notas para el driver mainline

- El `WT 0x0A ...` es el **PPS de DSC** (comando DCS 0x0A). En mainline, msm/DPU
  envía el PPS por su cuenta a partir de `drm_dsc_config`; probablemente NO haya
  que mandar este PPS a mano si se rellena `drm_dsc_config` con estos parámetros.
  Pero `samsung,no_qcom_pps` sugiere que el panel espera SU PPS exacto → puede
  que sí haya que enviarlo tal cual. Validar en primera luz.
- Los `0xC0/0xC1/0xB0` son accesos indirectos a registros internos del DDIC
  (secuencia gpara). Se copian tal cual como payloads DCS long-write.
- TE es **Active Low** (`0xC1 0x02` en TCON_INTR) — importante para la config
  del TE en el DPU.
- Faltan por transcribir (están en el PDF, se harán al escribir el driver):
  UPIM_SSCG, TSP_SYNC, DIA, BRIGHTNESS, VRR. Para PRIMERA LUZ estática se pueden
  omitir las de brillo/VRR y quedarnos con: reset → 0x11 → (VBP, DISPLAY_ON_DELAY,
  MX_IP, TCON_INTR, TE_ON, DSC) → 0x29.

## Fuente original y reproducibilidad

Los ficheros temporales `*_panel.c/.h`, `*_PDF.h`, `PDF-decoded.txt` y
`ss_dsi_panel_common.h` no se conservan en el repositorio. Si hay que auditar de
nuevo la transcripción, se descarga otra vez el paquete oficial desde
opensource.samsung.com y se repite la extracción descrita en la sesión 57 del
`porting-log.md`. El código de kernel es GPL-2.0; los datos `.dat`/mdnie son
calibraciones propietarias y nunca se versionan.

## Resultado físico final (v0.58)

- El pipeline SoC ya completaba frames en v0.57; la ausencia de emisión era la
  secuencia del DDIC. El `lcd_id=0x800004` corresponde a revisión D.
- v0.58 aplica el orden rev-C/D `POWER_ON_PRE_SETTING`: VBP y
  DISPLAY_ON_DELAY se programan **antes** de `SLEEP_OUT (0x11)`.
- Usa `TSP_SYNC_SETTING` rev-C+, habilita DIA (`0x91 0x02`) y fija brillo no
  nulo con `0x53 0x28` + `0x51 0x07 0xff` antes de `DISPLAY_ON (0x29)`.
- Resultado validado físicamente: el panel emite el escritorio XFCE a
  2960×1848 mediante DPU → DSI command mode → DSC → ANA38407. v0.59 conserva
  exactamente esta secuencia y añade UFS sin regresión visual.

## Reinicio cálido y recuperación del DDIC (sesión 72)

- Tras las pruebas v0.60 y también al volver por `systemctl reboot` a v0.59,
  el primer `prepare` puede terminar con lectura `ana38407 panel id: 00 00 00`:
  DRM registra `DSI-1 connected`, Xorg hace modeset, pero el OLED queda negro.
- Un disable/enable completo desde X (`xrandr --output DSI-1 --off`, pausa de
  3 s, y `--mode 2960x1848 --rate 120`) fuerza `unprepare/prepare`, repite el
  reset y toda la secuencia rev-D. El segundo intento lee el ID real
  `80 00 04` y recupera inmediatamente la imagen; validado por cámara.
- El drop-in de LightDM `20-gts9uwifi-panel-reinit.conf` ejecuta ese ciclo como
  `ExecStartPost`. En la prueba de reinicio normal terminó con `status=0/SUCCESS`, el
  ID cambió de `00 00 00` a `80 00 04` a los 24,5 s y el login quedó visible.
- Xorg fija además `BlankTime`, `StandbyTime`, `SuspendTime` y `OffTime` a cero
  mientras el suspend/resume real del panel no sea fiable.

## Reverse PRIME y recuperación automática (sesión 75)

- Con la topología DRM separada final, el output del DPU aparece en Xorg como
  `DSI-1-1`, no necesariamente `DSI-1`. El script ya no hardcodea ese nombre:
  primero asocia los providers Source Output (Adreno) y Sink Output (DPU),
  después elige el primer output `connected`.
- El ciclo off/on sigue siendo necesario después de algunos reinicios de Xorg:
  DRM puede reportar `enabled` y DPMS `On` mientras el OLED físico está negro.
  El disable/enable fuerza otra lectura `80 00 04` y repite la secuencia rev-D.
- El hook actualizado se validó tras un reinicio completo con Xorg r10 reverse
  PRIME: recuperó por sí solo XFCE a 2960×1848@120. Después `glmark2` acelerado
  por FD740 se vio físicamente en el panel, sin error DSI/DRM.

## Encendido diferido y carreras de resume (sesión 105, v1.08)

La usuaria confirmó que `SW_LID` suspende de forma consistente tanto en GDM
como dentro de GNOME, pero una apertura antes de 2–3 segundos podía no devolver
imagen. Algunas reanudaciones por funda o power mostraban ruido de colores en
casi todo el panel, mientras la barra superior de GNOME seguía siendo legible.
Ese patrón es coherente con GRAM/flujo DSC desincronizado, no con un fallo de
composición, alimentación o identificación del DDIC.

El journal mostró dos problemas independientes:

- la apertura rápida sí llegaba al kernel y provocaba `PM: suspend exit`; no se
  estaba perdiendo el evento Hall;
- los `systemd-run --on-active=1s` anónimos podían ejecutarse 7–16 segundos
  después y sobrevivir hasta el siguiente cierre. En ciclos rápidos llegaron a
  coincidir dos peticiones `PowerSaveMode=0` y dos nuevos `prepare`.

v1.08 reemplaza esos timers por un único servicio cancelable: el hook `pre`
detiene cualquier wake pendiente y el `post` reinicia la unidad, cuya espera
de un segundo también queda cancelada por el siguiente suspend.

Además, el DT stock declara `samsung,delayed-display-on`. El driver mainline
enviaba hasta v1.07 `0x29 DISPLAY_ON` dentro de `prepare`, antes de la fase
`enable` del bridge. v1.08 separa el ciclo según la API DRM y otros paneles
Samsung DSC mainline:

1. `prepare`: rails, reset, sleep-out, configuración rev-D, TE y PPS DSC;
2. `enable`: `DISPLAY_ON` cuando el pipeline DPU/DSI ya está listo;
3. `disable`: `DISPLAY_OFF`;
4. `unprepare`: sleep-in, reset y apagado de rails.

La primera prueba automática de v1.08 dejó una sola lectura `80 00 04`, un
solo servicio de wake y ningún timer residual. La validación física posterior
confirmó que los artefactos cromáticos desaparecieron y que abrir la funda
vuelve a encender el panel de forma fiable. La demora visible de 2–3 segundos
coincide con el resume profundo, la reanudación de DRM y el margen del
compositor; no se pierde el evento Hall.
