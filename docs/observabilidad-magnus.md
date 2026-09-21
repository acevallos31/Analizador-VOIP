# Observabilidad de Magnus y troncales

## Repositorios relacionados

El despliegue base de HOMER 7 se conserva en el repositorio:

- [acevallos31/homer7-docker](https://github.com/acevallos31/homer7-docker)

Ese repositorio contiene las recetas Docker/Compose base de HOMER. En la implementación actual, el stack de HOMER en Docker02 también incluye servicios complementarios de observabilidad, como Loki, Grafana, Prometheus y Alertmanager. Este documento describe la operación actual y su integración con Magnus/Asterisk.

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
       └─ Alloy (systemd)
            └─ HTTP hacia Loki en 100.100.2.64:3100
```

Loki sí forma parte del stack desplegado junto con HOMER, pero cumple una función complementaria:

- HOMER recibe paquetes HEP y permite analizar llamadas SIP.
- Loki almacena registros de texto y eventos operativos.
- Grafana consulta Loki para visualizar esos registros.
- El agente de logs no debe enviar tráfico SIP crudo a Loki.
- Loki no participa en el establecimiento ni enrutamiento de llamadas.

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

Resultado observado:

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

Loki es parte del stack de observabilidad desplegado junto con HOMER en Docker02. Está publicado en el puerto TCP 3100, pero no es el motor de captura SIP ni reemplaza a HOMER.

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

Alloy quedó instalado y habilitado en Magnus como agente único para logs. Su configuración se valida antes de reiniciar el servicio y conserva una copia de seguridad del archivo anterior.

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

La configuración se puede instalar de forma reproducible con [`scripts/install-alloy-magnus.sh`](../scripts/install-alloy-magnus.sh). El script instala Alloy desde el repositorio oficial de Grafana, agrega el usuario `alloy` al grupo `systemd-journal`, valida la conectividad a Loki, crea la configuración y habilita el servicio. Se pueden personalizar `LOKI_URL`, `NODE_LABEL` y `MAX_AGE` mediante variables de entorno.

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

- [x] Instalar Alloy en Magnus.
- [x] Crear configuración de envío a Loki.
- [ ] Confirmar streams y consultas en Loki después de generar nuevos eventos.
- [ ] Validar visualización de etiquetas en Grafana.
- [ ] Crear monitor de los diez troncales.
- [ ] Registrar cambios `OK` / `UNREACHABLE`.
- [ ] Configurar alertas de Telegram.
- [ ] Crear dashboard operativo de disponibilidad.

## Monitor replicable de troncales

La primera fase del monitor quedó preparada para reutilizarse en otros servidores Magnus:

- [check-magnus-trunks.sh](../scripts/check-magnus-trunks.sh): consulta los peers SIP y registra cambios de estado.
- [install-trunk-monitor.sh](../scripts/install-trunk-monitor.sh): instala el agente y el temporizador systemd.
- [trunk-monitor.example.env](../config/trunk-monitor.example.env): parámetros y troncales seleccionables.
- [trunk-monitor.service](../systemd/trunk-monitor.service): ejecución del chequeo.
- [trunk-monitor.timer](../systemd/trunk-monitor.timer): ejecución cada cinco minutos.
- [alloy-trunk-monitor.alloy](../config/alloy-trunk-monitor.alloy): fuente Alloy para enviar los eventos a Loki.

Instalación en un nuevo Magnus:

```bash
git clone https://github.com/acevallos31/Analizador-VOIP.git
cd Analizador-VOIP
sudo bash scripts/install-trunk-monitor.sh
sudo nano /etc/trunk-monitor/config.env
sudo systemctl start trunk-monitor.service
```

El archivo `config.env` permite seleccionar los troncales sin modificar el script. La ejecución permanece local al Magnus; solo los eventos operativos se envían posteriormente a Loki. Los paquetes SIP continúan siendo responsabilidad de Heplify/HOMER.

### Despliegue con Ansible/Semaphore

Para replicar el monitor en varios Magnus se incluye:

- [install-magnus-monitor.yml](../ansible/install-magnus-monitor.yml)

El inventario de Semaphore debe definir un grupo `magnus`. Las variables principales son:

- `magnus_node_label`
- `loki_url`
- `monitor_trunks`

La fuente de verdad del agente continúa siendo `/etc/trunk-monitor/config.env`. Ansible instala el script, la unidad systemd, el temporizador y la fuente de Alloy. La interfaz web futura modificará estos mismos parámetros; no tendrá una lógica diferente.

### Decisión sobre la interfaz web

La solución queda funcional inicialmente mediante configuración declarativa y Ansible/Semaphore. Esto permite validar el monitoreo sin exponer un endpoint web con permisos para ejecutar Asterisk.

La interfaz web se puede agregar después como una capa administrativa para:

- descubrir troncales;
- seleccionar troncales;
- modificar el intervalo;
- cambiar el destino Loki;
- ejecutar una prueba.

La interfaz no reemplazará al agente ni ejecutará comandos directamente; generará la configuración que consume el agente.
