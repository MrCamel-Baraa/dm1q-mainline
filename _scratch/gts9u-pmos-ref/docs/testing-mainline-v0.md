# Prueba física de mainline v0.6

> **ARCHIVO HISTÓRICO.** Esta guía describe la primera prueba experimental
> v0.6 y no debe usarse para instalar la versión actual. Consulta el
> [README](../README.md), [boot-strategy.md](boot-strategy.md) y
> [hardware-status.md](hardware-status.md). Se conserva porque documenta los
> fallos tempranos y el procedimiento de recuperación que permitió resolverlos.

Esta es una prueba **experimental de bring-up**, no una versión utilizable.
La compilación y las validaciones estáticas han pasado.
La v0.1 demostró que ABL puede descomprimir el kernel, pero rechazó el DTB por
carecer de sus selectores legacy. La v0.2 corrigió la selección, pero el ufdt
de ABL no pudo aplicar el overlay sobre un DTB mainline sin `/__symbols__`.
v0.3 añadió los símbolos pero el fork ufdt Samsung falló exactamente igual.
v0.4 evitó esa ruta mediante appended-DTB y llegó físicamente a Linux: mostró
verbose y el logo, pero TrustZone reinició después el SoC por un fatal NoC.
v0.5 mantuvo esa ruta y añadió los carveouts Samsung, pero repitió el fatal.
Su vídeo termina justo antes del probe de `lpass_ag_noc@7e40000`. v0.6
deshabilita ese proveedor e incorpora un printk persistente legible desde
TWRP. Todavía no sabemos si llegará a montar la raíz de la microSD o si el USB2
del X910 sobrevivirá a la transición desde el bootloader.

La prueba no modifica `super`, `userdata`, recovery, bootloader, PIT, EFS ni
firmware. Reemplaza temporalmente `boot`, `init_boot`, `vendor_boot` y `dtbo`.
En este TWRP conserva `vbmeta`, que está RO, después de comprobar que ya tiene
AVB flags 2. Conviene mantener el ZIP de restauración accesible desde TWRP.

## Material necesario

- Una microSD sacrificable de **8 GB o más**. Todo su contenido se borrará.
- `postmarketos-edge-xfce-mainline-v0.6-sm-x910-sd.img.zst`.
- `postmarketos-edge-xfce-mainline-v0.6-sm-x910-twrp.zip`.
- `restore-ubuntu-touch-v8-boot-sm-x910.zip` como vuelta atrás.
- TWRP ya instalado/arrancable en la tablet.

No uses la tarjeta exFAT de 238 GB que está casi llena: contiene datos y queda
expresamente fuera de esta prueba.

## 1. Verificar los ficheros

Comprueba los SHA-256 publicados en `artifacts/SHA256SUMS-mainline-v0.6.txt` y en
`artifacts/README.md`. Si un hash no coincide, no continúes.

## 2. Preparar la microSD

Descomprime el fichero `.img.zst` con 7-Zip o `zstd`. El resultado es una
imagen raw de 4.634.705.920 bytes. Escríbela completa en la microSD con una
herramienta de imágenes raw, por ejemplo Rufus en modo DD o Win32 Disk Imager.

Selecciona la unidad con mucho cuidado: la operación destruye todas las
particiones y datos del dispositivo elegido. El proyecto no incluye ningún
comando automático que seleccione o escriba discos físicos.

La imagen contiene GPT y dos particiones:

1. `pmOS_boot`, ext2, aproximadamente 487 MiB, con `initramfs-extra`;
2. `pmOS_root`, ext4, aproximadamente 3,8 GiB, con postmarketOS/XFCE.

## 3. Instalar el boot mínimo

1. Copia a un almacenamiento visible desde TWRP tanto el ZIP mainline como el
   ZIP de restauración.
2. Apaga la tablet e inserta la microSD preparada.
3. Arranca TWRP.
4. Flashea únicamente
   `postmarketos-edge-xfce-mainline-v0.6-sm-x910-twrp.zip`.
5. Comprueba que TWRP anuncia que `vbmeta` es RO, que ya tiene AVB flags 2 y
   que lo conservará. Después debe escribir exactamente `boot`, `init_boot`,
   `vendor_boot` y `dtbo` y terminar sin error.
6. No hagas wipes ni formatees `data`. Reinicia manualmente a System.

En v0.6 el instalador escribe una `dtbo` deliberadamente no válida como tabla
Android. TWRP no depende de esa partición porque recovery lleva su propio
DTB/DTBO. Si el fallback no funcionase, vuelve a TWRP y usa el ZIP de rollback,
que restaura la DTBO stock completa.

## 4. Qué esperar

Espera al menos tres minutos en el primer arranque. El resultado ideal es el
splash conservado por ABL, consola/simpledrm y después LightDM/XFCE a
2960×1848. Las credenciales son:

- usuario: `phablet`;
- contraseña: `<DEV_PASSWORD>`;
- hostname: `gts9u`.

OpenSSH y NetworkManager están habilitados, pero **Wi-Fi aún no está descrito
en el DTS v0**. La primera red depende del USB NCM experimental. Conecta USB al
PC y observa si aparece una nueva interfaz de red; si aparece, busca la IP del
host `gts9u` o la concesión DHCP e intenta `ssh phablet@<IP>`.

Informa exactamente de:

- si cambia el splash, aparece consola, parpadeo o pantalla negra;
- cuánto tarda y si llega a LightDM/XFCE;
- si el PC detecta un nuevo dispositivo USB o interfaz de red;
- si la tablet reinicia sola o permanece encendida.

No se debe interpretar una pantalla negra como prueba de que el kernel no
arrancó: el panel dual-DSI todavía no tiene driver mainline y simpledrm depende
de que ABL preserve el framebuffer.

## 5. Restaurar Ubuntu Touch

Si no arranca o cuando termine la prueba:

1. Fuerza el apagado y vuelve a TWRP con la combinación habitual.
2. Flashea `restore-ubuntu-touch-v8-boot-sm-x910.zip`.
3. Retira la microSD de prueba.
4. Reinicia a System.

El ZIP de vuelta atrás restaura las cuatro particiones de boot escribibles de
Ubuntu Touch v8/firmware stock y conserva el `vbmeta` RO si ya tiene flags 2.
No reescribe `super` ni `userdata`. Si TWRP no fuese accesible,
Download Mode y el firmware Odin oficial siguen siendo la última vía de
recuperación; no flashees PIT ni marques repartition.

## Diagnóstico posterior

Tras un fallo reproducible, vuelve primero a TWRP sin restaurar ni borrar nada.
Se recogerán `/proc/last_kmsg` y los logs del recovery antes de ajustar el
DTS/cmdline. v0.6 escribe la consola mainline en el ring Samsung `LOGM` que el
recovery usa para construir `last_kmsg`; pstore queda como fuente secundaria.
No conviene probar variantes al azar: esos registros
distinguen entre rechazo de ABL, kernel temprano, montaje de la SD y fallo
gráfico. En v0.6 es esperable que ABL registre una magia DTBO inválida: ésa es
la señal que activa el fallback. Si después aparece `Appended Device Tree blob
not found`, se revisarán el offset final del miembro gzip y la disposición del
campo kernel en `boot.img` antes de generar otra variante.
