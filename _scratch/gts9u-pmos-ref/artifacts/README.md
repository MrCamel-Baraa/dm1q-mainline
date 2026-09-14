# Artefactos generados

Este directorio se mantiene deliberadamente vacío en Git. Las imágenes de
microSD, ZIP de TWRP, imágenes de partición y logs de build son productos
regenerables, ocupan mucho espacio y pueden contener firmware propietario.
Nunca deben publicarse en este repositorio.

La última baseline físicamente validada al congelar postmarketOS es v1.71:

- nombre: `postmarketos-edge-gnome-mainline-v1.71-dp-dock-coldboot-sm-x910-twrp.zip`;
- SHA-256: `10c6d6c811230b6c52e59f5e6f9ed41ed29ae7d285e3c8d1679c582db5695097`;
- estado: Wi-Fi, escritorio, táctil, audio, sensores, USB host y DisplayPort
  restaurados en dos arranques consecutivos con el dock ya conectado.

El fichero binario no se conserva aquí: debe regenerarse desde las fuentes y
los scripts versionados, obteniendo los blobs mediante los helpers
`scripts/stage-stock-*.sh`. El historial de cada build y sus resultados está en
[`docs/porting-log.md`](../docs/porting-log.md), especialmente la sesión 120
para v1.71.
