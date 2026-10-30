# Avisador de stock de VPS (OVH y Hetzner)

Avisa al móvil (con [ntfy](https://ntfy.sh)) y al Mac cuando OVH vuelve a tener **VPS-2 o
VPS-3 con Linux** en un centro de datos europeo, o Hetzner tiene **CX33 o CAX21** en
Falkenstein, Núremberg o Helsinki. Mira las APIs cada 10 minutos y sólo avisa del cambio
(agotado → disponible), no en cada pasada.

## Hetzner

Su API pide un token incluso para leer la disponibilidad. Créalo de **sólo lectura**:
Hetzner Console → tu proyecto → **Security → API tokens → Generate API token**, permiso
**Read**. Guárdalo como secreto `HCLOUD_TOKEN` del repo (Settings → Secrets and variables
→ Actions → New repository secret) y, si quieres probar en el Mac, en `config.env`.
Sin token, Hetzner se salta y OVH sigue funcionando igual.

- Mira `server_types[].locations[].available`. ⚠️ `/datacenters` ya no sirve: Hetzner lo
  retiró el 1-10-2026.
- `cax21` es ARM: Coolify y las imágenes de Node funcionan, pero comprueba que todo lo que
  despliegues tenga imagen para ARM.
- El aviso de Hetzner es de prioridad alta y abre la consola: su stock barato dura horas.

## OVH

- Si aparece en `HOME_DC` (tu centro), el aviso es de prioridad alta: es el único donde
  podrías **subir tu VPS-1** sin migrar, porque la mejora sólo funciona dentro del mismo
  centro.
- Si aparece en otro centro, aviso normal: valdría para contratar uno nuevo allí.
- Comprueba `linuxStatus`, no `status`: el 30-10-2026 el VPS-2 salía «available» en tres
  centros, pero sólo con Windows.

## Puesta en marcha (5 minutos)

1. **App en el móvil:** instala **ntfy** (App Store o Google Play).
2. **Inventa un tema** largo y raro (quien lo conozca puede leer los avisos):
   ```bash
   echo "ovh-denis-$(openssl rand -hex 6)"
   ```
   En la app: **+** → escribe ese tema → **Subscribe**.
3. **Configura el avisador:**
   ```bash
   cd ~/Developer/personal/ovh-stock-alert
   cp config.env.example config.env
   open -e config.env      # pega el tema en NTFY_TOPIC= y guarda
   ```
4. **Prueba que llega:**
   ```bash
   ./check-ovh-stock.sh --test
   ```
5. **Que se ejecute solo cada 10 minutos** (tarea de usuario de macOS, `launchd`):
   ```bash
   cp com.denisvs.ovh-stock-alert.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.denisvs.ovh-stock-alert.plist
   ```
   Lo que hace: macOS lanza el script cada 10 minutos mientras tu sesión está abierta.
   No pide permisos de administrador ni toca nada del sistema; el registro va a
   `check.log`.

## Consultas y mantenimiento

```bash
./check-ovh-stock.sh --status    # qué hay disponible ahora mismo
tail -f check.log                # qué ha ido comprobando
```

**Quitarlo** (cuando ya tengas tu VPS-2, o si molesta):
```bash
launchctl bootout gui/$(id -u)/com.denisvs.ovh-stock-alert
rm ~/Library/LaunchAgents/com.denisvs.ovh-stock-alert.plist
```

## Sin el Mac: GitHub Actions (recomendado)

`.github/workflows/check.yml` pasa el mismo script en los servidores de GitHub cada 10
minutos (con algún minuto de retraso, GitHub no garantiza la hora exacta). Gratis:

- **Repositorio público:** minutos ilimitados. El tema de ntfy no queda a la vista: va en
  un secreto. ⚠️ GitHub desactiva los workflows programados tras **60 días sin actividad**
  en el repo; avisa por correo y se reactiva en la pestaña Actions.
- **Repositorio privado:** 2.000 minutos al mes, y cada pasada cuenta como un minuto
  entero. Cada 10 minutos serían ~4.300 y no caben: cambia el cron a `*/30 * * * *`.

Para activarlo: crear el repo, subirlo y añadir el secreto `NTFY_TOPIC` en Settings →
Secrets and variables → Actions. Se puede lanzar a mano desde la pestaña Actions con
**Run workflow**. Si usas Actions, no instales también la tarea del Mac (avisarían los dos).

## Limitación de la tarea del Mac: sólo vigila con el Mac despierto

Con la tapa cerrada o el Mac apagado no comprueba nada, y un VPS repuesto puede volver a
agotarse en horas. Cuando tengas el VPS-1, **muévelo allí** (Ubuntu necesita `jq`):

```bash
sudo apt install -y jq
crontab -e
# añade esta línea (ajusta la ruta):
*/10 * * * * /opt/ovh-stock-alert/check-ovh-stock.sh >> /opt/ovh-stock-alert/check.log 2>&1
```
En el servidor no hay notificación de macOS: sólo llega la de ntfy al móvil.

## Cambiar qué vigila

En `config.env`: `HOME_DC` (tu centro), `PLANS` (códigos del catálogo, p. ej.
`vps-2027-model2`) y `DATACENTERS`. Los códigos se sacan de
`https://eu.api.ovh.com/v1/order/catalog/public/vps?ovhSubsidiary=ES`.
