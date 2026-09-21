# Observabilidad de Magnus y troncales

## Objetivo

Documentar la arquitectura utilizada para:

1. Capturar señalización SIP de Magnus/Asterisk.
2. Visualizar llamadas en HOMER.
3. Registrar eventos operativos y disponibilidad de troncales en Loki/Grafana.
4. Preparar alertas cuando los troncales cambien a `UNREACHABLE`.

## Arquitectura actual

```text
Magnus/Asterisk (srv-pbx-cystech)
  ├─ SIP en 5060
  ├─ Heplify captura en enp2s0
  │    └─ HEP/UDP hacia 100.100.2.64:9060
  │         └─ HOMER en docker02
  └─ Logs y estado de troncales
       └─ Alloy (pendiente de configuración)
            └─ HTTP hacia Loki en 100.100.2.64:3100
```

HOMER y Loki cumplen funciones diferentes:

- HOMER recibe paquetes HEP y permite analizar llamadas SIP.
- Loki almacena registros de texto y eventos operativos.
- El agente de logs no debe enviar tráfico SIP crudo a Loki.

## Servidores y direcciones

| Componente | Host/IP | Función |
|---|---|---|
| Magnus proveedor | `srv-pbx-cystech` | Asterisk y captura SIP |
| Tailscale Magnus | `100.81.97.59` | Conectividad privada |
| Docker/HOMER/Loki | `docker02` / `100.100.2.64` | Recepción y visualización |
| HEP | `100.100.2.64:9060/udp` | Transporte de captura SIP |
| Loki | `http://100.100.2.64:3100` | Recepción de logs |

## Estado implementado

### Tailscale

Magnus está unido al tailnet con el nombre:

- Hostname: `magnus-erick`
- IP Tailscale: `100.81.97.59`

La comunicación hacia Docker02 fue validada desde Magnus:

```bash
curl -i http://100.100.2.64:3100/ready
```

Resultado esperado:

```text
HTTP/1.1 200 OK
ready
```

### Heplify

Heplify instalado en:

```text
/usr/local/bin/heplify
```

Versión registrada durante la instalación:

```text
2.0.28
```

Servicio:

```text
/etc/systemd/system/heplify.service
```

Configuración operativa:

- Interfaz de captura: `enp2s0`
- Puerto SIP observado: `5060`
- Transporte HEP: UDP
- Servidor HEP: `100.100.2.64:9060`
- Hostname HEP: `magnus-proveedor`
- Exclusiones: `OPTIONS,NOTIFY`

Las exclusiones evitan llenar la vista principal de HOMER con mensajes de mantenimiento SIP. Las llamadas reales continúan enviándose a HOMER.

Comandos de verificación:

```bash
systemctl is-active heplify
journalctl -u heplify -n 50 --no-pager
```

En los logs se validó:

- conexión al servidor HEP;
- captura en `enp2s0`;
- envío de paquetes SIP;
- estadísticas `sip > 0`.

### Loki

Loki corre en Docker02, publicado en el puerto TCP 3100.

Validaciones realizadas:

```bash
curl -i http://127.0.0.1:3100/ready
curl -sS http://127.0.0.1:3100/loki/api/v1/status/buildinfo
curl -sS http://127.0.0.1:3100/loki/api/v1/labels
```

Estado confirmado:

- Loki listo: `HTTP 200`;
- anillo en estado `ACTIVE`;
- versión observada: `3.7.7`;
- conexión remota desde Magnus validada por Tailscale.

## Alloy

Al inicio de esta documentación no había Alloy ni Promtail instalado en Magnus. La instalación prevista es Alloy como agente único de logs.

El agente debe enviar únicamente:

- logs de Asterisk;
- logs de Heplify;
- logs del monitor de troncales;
- eventos de cambio de estado de los troncales.

No debe enviar:

- paquetes SIP crudos;
- tráfico HEP;
- credenciales;
- tokens;
- información innecesaria del sistema.

La configuración final de Alloy se documentará aquí después de validar la instalación y hacer una prueba de envío.

## Troncales a monitorear

El grupo principal está compuesto por:

```text
50422427780
50422427781
50422427782
50422427783
50422427784
50422427785
50422427786
50422427787
50422427788
50422427789
```

Estado actual observado mediante Asterisk:

```bash
sudo asterisk -rx "sip show peers"
```

Los estados `OK` indican que el peer responde al qualify. `UNKNOWN` o `UNREACHABLE` deben investigarse según el tipo de autenticación, red y configuración del trunk.

## Separación de funciones

| Flujo | Puerto/destino | Propósito |
|---|---|---|
| SIP de Asterisk | UDP/TCP 5060 local | Telefonía |
| HEP de Heplify | UDP 9060 en Docker02 | HOMER |
| Logs hacia Loki | HTTP 3100 en Docker02 | Auditoría y alertas |
| Tailscale | Red 100.x | Transporte privado |

El agente de logs no modifica el flujo SIP ni participa en el establecimiento de llamadas.

## Seguridad

- No publicar Loki directamente en Internet.
- Mantener la comunicación Magnus–Docker02 por Tailscale.
- No guardar tokens de Telegram, claves SSH ni contraseñas en GitHub.
- Usar permisos restrictivos para archivos de configuración con secretos.
- Enviar a Loki solo los logs necesarios.

## Reversión

Para detener Alloy sin afectar Asterisk ni Heplify:

```bash
systemctl disable --now alloy
```

Para quitarlo, si fuera necesario:

```bash
apt remove alloy
```

La reversión de Alloy no elimina HOMER, Loki, Heplify ni la configuración de Asterisk.

## Pendientes

- [ ] Confirmar instalación de Alloy en Magnus.
- [ ] Crear configuración de envío a Loki.
- [ ] Validar etiquetas en Grafana.
- [ ] Crear monitor de los diez troncales.
- [ ] Registrar cambios `OK` / `UNREACHABLE`.
- [ ] Configurar alertas de Telegram.
- [ ] Crear dashboard operativo de disponibilidad.
