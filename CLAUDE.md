# CLAUDE.md — agesci-campania-web-frontend

Riferimento di continuità per Claude Code.

## Cos'è

Reverse proxy unico (Caddy in Docker) del server che ospita le piattaforme
`*.agescicampania.net`: Sestante (SSO, Authentik), Plancia, nota spese, Tana e future.
Server dedicato configurato da zero, senza Virtualmin; ogni progetto è clonato in
`/opt/<nome-repo>`. Questo repo contiene solo configurazione, nessuna applicazione.

## Decisioni prese (non rimetterle in discussione senza confermare con l'utente)

- **Caddy** come unico punto d'ingresso: solo lui pubblica le porte 80/443.
- Certificati **solo Let's Encrypt** (`acme_ca` esplicito, niente fallback ZeroSSL).
- Rete Docker esterna condivisa **`agesci-proxy`**, creata da `scripts/installa.sh` di questo
  repo; i progetti vi collegano solo il container d'ingresso, con alias
  `<progetto>-<servizio>`.
- Gli nginx interni dei progetti restano, solo HTTP, e inoltrano `X-Forwarded-Proto` ricevuto
  da Caddy (non `$scheme`).
- Ogni progetto (anche questo) ha `scripts/installa.sh` e `scripts/aggiorna.sh`.
- `docs/INTEGRAZIONE.md` è il contratto verso gli altri progetti: se cambia una regola qui
  (rete, alias, header, script), aggiornarlo nello stesso commit.

## Convenzioni

- Licenza MIT, copyright Andrea Bruno. README con badge shields.io. Testi in italiano.
- Mai committare `.env` né segreti.
- Versione immagine Caddy fissata in `docker-compose.yml` (mai `:latest`); prima di
  aggiornarla verificare l'ultima release su https://github.com/caddyserver/caddy/releases e
  che il tag `-alpine` esista su Docker Hub.
- Script bash: `set -euo pipefail`, funzioni condivise in `scripts/_comune.sh`, verificati con
  `shellcheck`, bit eseguibile committato.
- Sintassi Caddyfile: indentazione con tab; validare con
  `docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`.
- `{$VAR:default}` in Caddy usa il default solo se la variabile **non è definita**: in `.env`
  le variabili opzionali vanno commentate, non lasciate vuote.

## Aggiungere un sito

1. `caddy/sites/<progetto>.caddy` con `import comune` e `reverse_proxy <alias>:<porta>`.
2. Aggiornare la tabella "Registro progetti" in `docs/INTEGRAZIONE.md`.
3. Commit + push; sul server `scripts/aggiorna.sh` (valida e ricarica senza downtime).

## Cosa NON fare

- Non modificare direttamente i repo degli altri progetti (es. Plancia): fornire istruzioni
  scritte all'utente.
- Non pubblicare porte di altri servizi su `0.0.0.0`.
- Non rimuovere il volume `caddy_data` (contiene certificati e account ACME).
