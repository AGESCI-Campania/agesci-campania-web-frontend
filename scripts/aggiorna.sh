#!/usr/bin/env bash
# Aggiorna il reverse proxy: scarica l'ultima versione da git, valida la configurazione,
# aggiorna l'immagine se cambiata e ricarica i siti senza downtime.
#
# Uso:  scripts/aggiorna.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_comune.sh

richiedi_comandi docker git
[[ -f .env ]] || errore ".env mancante: eseguire prima scripts/installa.sh"
docker network inspect "$RETE_PROXY" >/dev/null 2>&1 || errore "Rete $RETE_PROXY mancante: eseguire prima scripts/installa.sh"

# git pull può modificare questo stesso script: dopo il pull si riparte con la versione nuova
if [[ "${1:-}" != "--dopo-pull" ]]; then
	richiedi_albero_pulito
	info "Scarico gli aggiornamenti da git."
	git pull --ff-only
	exec "$0" --dopo-pull
fi

controlla_var_nuove

# Validazione prima di toccare il container in esecuzione: un Caddyfile errato non va mai in produzione
info "Valido la configurazione Caddy."
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

docker compose pull
docker compose up -d   # ricrea il container solo se immagine o compose sono cambiati
attendi_salute 60 caddy

info "Ricarico la configurazione (nuovi siti / modifiche ai sites/*.caddy)."
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

info "Aggiornamento completato. Log: docker compose logs -f caddy"
