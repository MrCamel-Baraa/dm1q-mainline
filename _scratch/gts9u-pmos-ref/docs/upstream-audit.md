# Auditoría upstream para SM8550/gts9uwifi

> **AUDITORÍA HISTÓRICA INICIAL.** Refleja el conocimiento disponible antes del
> bring-up físico. Muchas carencias enumeradas aquí ya fueron resueltas. El
> estado vigente está en [hardware-status.md](hardware-status.md) y la evidencia
> cronológica en [porting-log.md](porting-log.md).

Fecha de corte: 2026-07-17.

## Kernel elegido

El primer prototipo queda fijado a Linux mainline `v7.2-rc3`, commit
`a13c140cc289c0b7b3770bce5b3ad42ab35074aa`. Es el mismo release que empaqueta
`linux-postmarketos-mainline` en el snapshot de pmaports
`b7681d0e857d395edfaa6c8e5cd0d89e4315fd3f`, lo que reduce diferencias entre
la compilación directa y la de pmbootstrap.

Existe una alternativa conservadora muy válida: el kernel oficial Qualcomm
`qcom-6.18.y`, tag `qcom-6.18.y-20260714`, commit
`48143db58c4c1d9800cc12dd7fc7a9b1799232a`. Es LTS y contiene backports útiles
para SM8550. No se usa en la primera imagen para mantener el prototipo sobre
el árbol Torvalds puro; se probará si aparece una regresión atribuible a un RC
o si sus mejoras UHS-I/ath12k resultan necesarias.

## Placas de referencia

- `sm8550-samsung-q5q.dts` (Galaxy Z Fold5) demuestra que Samsung ABL puede
  arrancar un DT mainline y mantener un `simple-framebuffer`.
- `sm8550-mtp.dts` aporta el patrón upstream de `sdhc_2`; sus GPIO y rails
  coinciden con el DT vivo de la X910.
- Xiaomi Pad 6S Pro (`xiaomi-sheng`) demuestra que SM8550 puede tener pantalla,
  táctil, GPU, audio, Wi-Fi, Bluetooth, USB, UFS y sensores con mainline. Sus
  paquetes son una referencia de pmOS, no una descripción de nuestra placa.
- No se incluye el DTS completo de q5q: sus carveouts MPSS y otros recursos
  pertenecen al Fold5. El DTS X910 es autónomo y sólo toma patrones contrastados.

## Hardware ya expresable upstream

| Bloque | Evidencia y decisión inicial |
|---|---|
| CPU, clocks, RPMh, interconnect e IOMMU | Soporte SM8550 upstream; integrado por la config genérica pmOS. |
| Framebuffer | ABL reserva `0xb8000000 + 0x2b00000`; se declara 2960×1848, stride 11840, `a8r8g8b8`. |
| microSD | `sdhc_2`, PM8550 GPIO12, L9B 2.96–3.0 V, L8B 1.8–3.0 V; controlador y ext4 built-in. |
| UART | `uart7`/QUP SE7 en `0xa9c000`, GPIO26/27, 115200 baud. Puede no estar físicamente expuesta. |
| Táctil | Goodix GT9916, driver Berlin I2C upstream; I2C4 `0xa90000`, IRQ25, reset24, L14B/L12B. |
| GPU | A740 soportada por MSM/Freedreno/Turnip; se habilitará después de confirmar el arranque base. |
| UFS | Patrón muy cercano a q5q; se habilitará inicialmente sólo para enumeración/lectura. |
| Wi-Fi | WCN7850/ath12k upstream; puede faltar el BDF Samsung en `board-2.bin`. |

## Bloqueos específicos de Samsung

### USB-C

La X910 no usa el PMIC GLINK Type-C de MTP/QRD. Lleva SM5714 para USB-PD, un
redriver PS5169 y un repetidor NXP eUSB2 en I2C `0x4f`. Linux 7.2-rc3 no tiene
el driver del repetidor NXP ni el control Type-C completo del SM5714.

El primer DTS fuerza `usb_1` a USB2 peripheral y deja el repetidor en el estado
inicializado por ABL. Esto es experimental. El acceso inicial no debe depender
exclusivamente de USB; también se conservan consola gráfica, UART y ramoops.

### Panel nativo

`GTS9U_ANA38407_AMSA46AS02` es un panel command-mode dual DSI con DSC y VRR.
La infraestructura MSM soporta dual DSI sincronizado, pero no existe driver
upstream para este panel/ANAPASS. El primer escritorio se apoya en simpledrm;
el driver DSI nativo será un hito separado.

### Wi-Fi

Aunque ath12k soporta WCN7850, hay que observar el QMI board-id real. Si el
firmware genérico no encuentra datos de placa, se extraerá el BDF del firmware
oficial X910 y se construirá un `board-2.bin` específico.

## Referencias externas

- Linux Qualcomm mainline status: <https://linux-msm.github.io/mainline-status/>
- DTS Samsung q5q upstream:
  <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8550-samsung-q5q.dts>
- Qualcomm kernel development:
  <https://docs.qualcomm.com/bundle/publicresource/topics/80-80022-3/kernel-development.html>
- Driver Freedreno/Turnip: <https://docs.mesa3d.org/drivers/freedreno.html>
- Driver ath12k: <https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath12k.html>
