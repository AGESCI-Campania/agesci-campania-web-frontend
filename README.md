# agesci-campania-web-frontend

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Caddy](https://img.shields.io/badge/Caddy-2.11-1F88C0.svg)
![Let's Encrypt](https://img.shields.io/badge/TLS-Let's%20Encrypt-003A70.svg)
![Docker Compose](https://img.shields.io/badge/deploy-Docker%20Compose-2496ED.svg)

Reverse proxy unico ([Caddy](https://caddyserver.com)) per le piattaforme web di AGESCI
Campania su `*.agescicampania.net`: termina HTTPS con certificati Let's Encrypt automatici e
inoltra il traffico ai progetti (Sestante, Plancia, …) tramite la rete Docker `agesci-proxy`.

## Struttura

| Percorso | Contenuto |
|---|---|
| `docker-compose.yml` | Servizio Caddy (versione fissata), rete esterna `agesci-proxy` |
| `caddy/Caddyfile` | Opzioni globali (ACME) e snippet `comune` |
| `caddy/sites/*.caddy` | Un file per piattaforma |
| `scripts/installa.sh` | Prima installazione: rete, `.env`, avvio |
| `scripts/aggiorna.sh` | `git pull`, validazione, aggiornamento immagine, reload senza downtime |
| `docs/INTEGRAZIONE.md` | **Regole per collegare un progetto** (da dare agli agenti degli altri repo) |

## Installazione sul server

Da eseguire per primo, prima di qualunque altro progetto:

```bash
git clone https://github.com/AGESCI-Campania/agesci-campania-web-frontend.git /opt/agesci-campania-web-frontend
/opt/agesci-campania-web-frontend/scripts/installa.sh
```

Prerequisiti: Docker con Compose v2, porte 80/tcp, 443/tcp, 443/udp aperte, DNS dei
sottodomini puntato al server.

## Aggiornamento

```bash
/opt/agesci-campania-web-frontend/scripts/aggiorna.sh
```

## Collegare un nuovo progetto

Vedi [`docs/INTEGRAZIONE.md`](docs/INTEGRAZIONE.md). Per farlo leggere a un agente Claude
Code che lavora in un altro repo, indicargli questo URL:

<https://raw.githubusercontent.com/AGESCI-Campania/agesci-campania-web-frontend/main/docs/INTEGRAZIONE.md>

## Licenza

MIT © Andrea Bruno
