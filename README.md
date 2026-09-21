# Analizador VOIP

Documentación operativa para captura, análisis y monitoreo de señalización SIP con Magnus/Asterisk, Heplify, HOMER, Loki y Grafana.

## Repositorios relacionados

- [homer7-docker](https://github.com/acevallos31/homer7-docker): recetas Docker originales/base para desplegar HOMER 7.
- Este repositorio: documentación operativa, captura multi-Magnus, monitoreo y alertas.

## Documentación

- [Observabilidad de Magnus y troncales](docs/observabilidad-magnus.md)

> Los secretos, tokens, contraseñas y claves privadas no deben almacenarse en este repositorio.

## Instalación reproducible

El instalador de Alloy para Magnus está en [scripts/install-alloy-magnus.sh](scripts/install-alloy-magnus.sh). Ejecutarlo como root:

```bash
sudo LOKI_URL=http://100.100.2.64:3100 \\
  NODE_LABEL=magnus-erick \\
  bash scripts/install-alloy-magnus.sh
```

El script crea copias de seguridad, valida Alloy y habilita el servicio. No modifica Asterisk, Heplify ni el flujo SIP.
