#!/usr/bin/env bash
# Prima installazione del reverse proxy Caddy sul server.
# Va eseguito PRIMA di installare qualunque altro progetto: crea la rete condivisa agesci-proxy.
#
# Uso:  scripts/installa.sh            (chiede l'email ACME se .env non esiste)
#       ACME_EMAIL=x@y scripts/installa.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_comune.sh

richiedi_comandi docker git

# --- Rete condivisa ---
if docker network inspect "$RETE_PROXY" >/dev/null 2>&1; then
	info "Rete $RETE_PROXY già presente."
else
	info "Creo la rete $RETE_PROXY."
	docker network create "$RETE_PROXY" >/dev/null
fi

# --- .env ---
if [[ -f .env ]]; then
	info ".env già presente, non lo modifico."
else
	info "Creo .env da .env.template."
	cp .env.template .env
	chmod 600 .env
	email="${ACME_EMAIL:-}"
	[[ -n "$email" ]] || read -rp "Email per Let's Encrypt (ACME): " email
	[[ -n "$email" ]] || errore "ACME_EMAIL obbligatoria."
	imposta_var ACME_EMAIL "$email"
fi
[[ -n "$(leggi_var ACME_EMAIL)" ]] || errore "ACME_EMAIL vuota in .env."

# --- Avvio ---
info "Valido la configurazione Caddy."
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

docker compose pull
docker compose up -d
attendi_salute 60 caddy

cat <<EOF

Caddy è attivo. Promemoria:
  - firewall: porte 80/tcp, 443/tcp e 443/udp aperte verso Internet
  - DNS: ogni sottodominio in caddy/sites/ deve puntare a questo server, altrimenti
    Let's Encrypt non può emettere il certificato (vedi: docker compose logs -f caddy)
  - poi installare i progetti (es. /opt/sestante/scripts/installa.sh)
EOF
