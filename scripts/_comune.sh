# Funzioni condivise da installa.sh e aggiorna.sh — non eseguire direttamente.
# shellcheck shell=bash

# shellcheck disable=SC2034  # usata dagli script che includono questo file
RETE_PROXY="agesci-proxy"

info()   { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
avviso() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
errore() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

richiedi_comandi() {
	local cmd
	for cmd in "$@"; do
		command -v "$cmd" >/dev/null 2>&1 || errore "Comando richiesto non trovato: $cmd"
	done
	docker compose version >/dev/null 2>&1 || errore "Serve Docker Compose v2 (docker compose)"
}

# Valore di una variabile in .env (vuoto se assente)
leggi_var() {
	sed -n "s/^$1=//p" .env | tail -n 1
}

# Imposta (o aggiunge) KEY=VALUE in .env senza sed -i, portabile e sicuro con / e + nei valori
imposta_var() {
	local chiave="$1" valore="$2" tmp
	tmp="$(mktemp)"
	awk -v k="$chiave" -v v="$valore" '
		BEGIN { trovata = 0 }
		index($0, k "=") == 1 { print k "=" v; trovata = 1; next }
		{ print }
		END { if (!trovata) print k "=" v }
	' .env > "$tmp"
	cat "$tmp" > .env
	rm -f "$tmp"
}

# Segnala le variabili presenti in .env.template ma mancanti in .env
controlla_var_nuove() {
	local mancanti
	mancanti="$(comm -23 \
		<(sed -n 's/^\([A-Z0-9_]*\)=.*/\1/p' .env.template | sort -u) \
		<(sed -n 's/^\([A-Z0-9_]*\)=.*/\1/p' .env | sort -u))"
	if [[ -n "$mancanti" ]]; then
		avviso "Variabili nuove in .env.template non presenti in .env:"
		# shellcheck disable=SC2001  # indentazione di ogni riga, non una sostituzione semplice
		sed 's/^/      /' <<< "$mancanti" >&2
		avviso "Aggiungerle a .env (vedi i commenti in .env.template) e rilanciare."
		return 1
	fi
}

richiedi_albero_pulito() {
	if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
		errore "Ci sono modifiche locali non committate: il server deve rispecchiare git. Annullarle o committarle prima."
	fi
}

# Attende che tutti i servizi indicati siano "healthy" (timeout in secondi)
attendi_salute() {
	local timeout="$1"; shift
	local fine=$((SECONDS + timeout)) servizio id stato tutti_ok
	info "Attendo che i servizi siano healthy: $*"
	while (( SECONDS < fine )); do
		tutti_ok=1
		for servizio in "$@"; do
			id="$(docker compose ps -q "$servizio")"
			stato="$( [[ -n "$id" ]] && docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" || echo assente)"
			[[ "$stato" == "healthy" ]] || tutti_ok=0
		done
		(( tutti_ok )) && { info "Tutti i servizi sono healthy."; return 0; }
		sleep 5
	done
	docker compose ps >&2
	errore "Timeout: servizi non healthy dopo ${timeout}s. Controllare: docker compose logs"
}
