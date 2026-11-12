# Integrazione di un progetto con il frontend web AGESCI Campania

Istruzioni per chi sviluppa o mantiene una piattaforma pubblicata su `*.agescicampania.org`
(Sestante, Plancia, nota spese, Tana, …), **in particolare per gli agenti Claude Code che
lavorano nei repository dei singoli progetti**. Leggere per intero prima di modificare
Docker Compose, nginx, impostazioni HTTP/HTTPS o script di deploy di un progetto.

Sorgente: `docs/INTEGRAZIONE.md` nel repo
[`AGESCI-Campania/agesci-campania-web-frontend`](https://github.com/AGESCI-Campania/agesci-campania-web-frontend).
Versione sempre aggiornata, leggibile senza autenticazione:
<https://raw.githubusercontent.com/AGESCI-Campania/agesci-campania-web-frontend/main/docs/INTEGRAZIONE.md>

---

## 1. Architettura

Sul server gira **un solo reverse proxy, Caddy**, che è l'unico container a esporre porte
su Internet (80, 443). Caddy termina TLS con certificati **Let's Encrypt** ottenuti e
rinnovati automaticamente, e inoltra il traffico ai progetti attraverso la rete Docker
condivisa `agesci-proxy`.

```
Internet ──443──► Caddy ──rete agesci-proxy──► sestante-server:9000
                                          ├──► plancia-nginx:80
                                          ├──► notaspese-nginx:80
                                          └──► tana-nginx:80
```

Ogni progetto vive nel proprio repo, clonato sul server in `/opt/<nome-repo>`, con il
proprio `docker-compose.yml`. Gli nginx interni ai progetti restano (file statici, buffering,
proxy verso gunicorn/uvicorn), ma parlano **solo HTTP** e solo sulla rete Docker.

## 2. Regole obbligatorie per ogni progetto

### 2.1 Rete e nome del container d'ingresso

- Il container che riceve il traffico (di solito `nginx`, oppure direttamente l'app) si
  collega alla rete **esterna** `agesci-proxy` con un **alias univoco**
  `<progetto>-<servizio>` (es. `plancia-nginx`). Caddy lo raggiunge con quel nome.
- Solo il container d'ingresso va su `agesci-proxy`. Database, cache, worker restano sulla
  rete `default` del progetto.
- Va fatto in `docker-compose.override.yml` (o nel compose del progetto), così:

```yaml
services:
  nginx:
    networks:
      default:
      agesci-proxy:
        aliases:
          - plancia-nginx

networks:
  agesci-proxy:
    external: true
```

### 2.2 Nessuna porta pubblicata

- **Non** usare `ports:` verso `0.0.0.0`. Solo Caddy pubblica porte.
- È ammesso, per debug dal server, pubblicare su loopback: `"127.0.0.1:<porta>:80"`.
  Scegliere una porta non usata da altri progetti (vedi tabella in fondo).

### 2.3 Niente TLS nel progetto

- Niente certbot, niente certificati, niente `listen 443` negli nginx interni, niente
  redirect HTTP→HTTPS nel progetto: lo fa Caddy.
- L'nginx interno ascolta su `80` in HTTP.

### 2.4 Header inoltrati (il punto più facile da sbagliare)

Caddy invia al progetto `Host` originale, `X-Forwarded-Proto: https`,
`X-Forwarded-Host` e `X-Forwarded-For`. L'nginx interno deve **passare i valori ricevuti
da Caddy**, non ricalcolarli: `$scheme` dentro il container vale `http`.

```nginx
location / {
    proxy_pass http://app:8000;
    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;   # NON $scheme
    proxy_set_header X-Forwarded-Host  $http_x_forwarded_host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
}
```

Sintomi se è sbagliato: redirect infiniti, errori CSRF ("Origin checking failed"),
callback OIDC/OAuth generate con `http://`, cookie `Secure` non impostati.

WebSocket: Caddy li inoltra senza configurazione; l'nginx interno, se presente, deve
avere i consueti `proxy_http_version 1.1` + header `Upgrade`/`Connection`.

Dimensione upload: Caddy non impone limiti; il limite effettivo è `client_max_body_size`
dell'nginx interno.

### 2.5 Applicazioni Django

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
ALLOWED_HOSTS = ["plancia.agescicampania.org"]
CSRF_TRUSTED_ORIGINS = ["https://plancia.agescicampania.org"]
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
# SECURE_SSL_REDIRECT non necessario (lo fa Caddy); se attivo funziona solo con
# SECURE_PROXY_SSL_HEADER configurato come sopra.
```

Altri framework: configurare l'equivalente "trust proxy headers" limitandolo alle reti
private Docker (`172.16.0.0/12`).

### 2.6 Il blocco sito in Caddy

La configurazione Caddy di ogni progetto è un file `caddy/sites/<progetto>.caddy` **in
questo repo** (`agesci-campania-web-frontend`), non nel repo del progetto:

```caddy
# Plancia — https://github.com/AGESCI-Campania/plancia
plancia.agescicampania.org {
	import comune
	reverse_proxy plancia-nginx:80
}
```

- `import comune` è obbligatorio (compressione, HSTS, log JSON su stdout).
- Il nome dopo `reverse_proxy` è l'alias del § 2.1, con la porta interna del container.
- **Un agente che lavora nel repo di un progetto non modifica questo repo**: prepara il
  contenuto del file e lo propone all'utente (o apre una PR qui se l'utente lo chiede).
- Il file va aggiunto e deployato (`scripts/aggiorna.sh` di questo repo) **dopo** che il
  container del progetto è attivo sulla rete e il DNS punta al server.

## 3. Script di installazione e aggiornamento (obbligatori)

Ogni progetto ha due script in `scripts/`, eseguiti sul server dalla root del repo
(`/opt/<repo>`). Possono riusare le funzioni di `scripts/_comune.sh` di questo repo
(copiandolo nel progetto: rete, `.env`, attesa healthcheck, controllo variabili nuove).

### `scripts/installa.sh` — prima installazione

1. `#!/usr/bin/env bash` + `set -euo pipefail`, `cd` nella root del repo, messaggi in italiano.
2. Verifica prerequisiti: `docker`, `docker compose` v2, eventuali altri comandi usati,
   **esistenza della rete `agesci-proxy`** (se manca: errore "installare prima
   agesci-campania-web-frontend").
3. Se `.env` non esiste: lo crea da `.env.template`, genera i segreti con
   `openssl rand -base64 …` (mai valori fissi o deboli), `chmod 600`. **Non sovrascrive mai
   un `.env` esistente.**
4. Prepara cartelle/permessi necessari.
5. `docker compose pull` / `build`, `docker compose up -d`.
6. Passi applicativi di primo avvio (migrazioni, `collectstatic`, dati iniziali, …).
7. Attende che i servizi siano `healthy` (servono `healthcheck` nel compose).
8. Stampa i passi manuali residui, **incluso il blocco `caddy/sites/<progetto>.caddy`** da
   aggiungere a questo repo.

### `scripts/aggiorna.sh` — aggiornamento a una nuova release

1. Rifiuta di procedere se ci sono modifiche locali non committate (il server rispecchia git).
2. `git pull --ff-only`, poi **ri-esegue se stesso** (`exec "$0" --dopo-pull`): il pull può
   aver cambiato lo script in esecuzione.
3. Segnala le variabili presenti in `.env.template` ma assenti in `.env` e si ferma.
4. **Backup del database** prima di qualunque migrazione (in una cartella in `.gitignore`).
5. `pull`/`build`, `up -d`, migrazioni, `collectstatic`, …
6. Attende `healthy`; in caso di errore indica come consultare i log.

Entrambi: idempotenti dove possibile, `shellcheck` senza errori, eseguibili (`chmod +x`,
committati con il bit eseguibile).

## 4. Procedura di messa in produzione di un progetto

1. Sul server, `agesci-campania-web-frontend` già installato (rete `agesci-proxy` esistente).
2. DNS: `<sottodominio>.agescicampania.org` → IP del server.
3. `git clone` del progetto in `/opt/<repo>` e `scripts/installa.sh`.
4. Aggiungere `caddy/sites/<progetto>.caddy` a questo repo, commit e push, poi sul server
   `/opt/agesci-campania-web-frontend/scripts/aggiorna.sh`.
5. Verificare: `curl -I https://<sottodominio>.agescicampania.org`, login, redirect, upload.

Se il progetto usa il login SSO di **Sestante** (`https://auth.agescicampania.org`), il
Provider OIDC si configura nel repo `AGESCI-Campania/sestante` come blueprint: chiedere
all'utente, non crearlo a mano.

## 5. Checklist per l'agente del progetto

- [ ] container d'ingresso su rete esterna `agesci-proxy` con alias `<progetto>-<servizio>`
- [ ] nessuna porta pubblicata su `0.0.0.0`
- [ ] nessuna configurazione TLS / certbot nel progetto
- [ ] nginx interno: `X-Forwarded-Proto $http_x_forwarded_proto`, `Host $host`
- [ ] app: proxy SSL header, host consentiti, origini CSRF con `https://`
- [ ] `healthcheck` sui servizi nel compose
- [ ] `scripts/installa.sh` e `scripts/aggiorna.sh` conformi al § 3
- [ ] blocco `caddy/sites/<progetto>.caddy` preparato e consegnato all'utente

## 6. Registro progetti

| Progetto | Sottodominio | Alias su `agesci-proxy` | Porta debug su 127.0.0.1 |
|---|---|---|---|
| Sestante | `auth.agescicampania.org` | `sestante-server:9000` | 9000 |
| Plancia | `plancia.agescicampania.org` | da definire | — |

Aggiornare la tabella quando si aggiunge un progetto (stesso commit del file in `sites/`).
