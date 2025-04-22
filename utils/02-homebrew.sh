# Wiederhole den Befehl bei Fehlern bis zu N Mal mit Delay
retry() {
  local -r -i max_tries="${1:-3}"  # Default 3 Versuche
  local -r -i delay="${2:-5}"      # Default 5 Sekunden Pause
  shift 2                          # Die ersten beiden Argumente sind max_tries und delay
  local -i attempt=1

  until "$@"; do
    if (( attempt >= max_tries )); then
      print_error "Befehl '$*' nach $attempt Versuchen fehlgeschlagen."
      return 1
    else
      print_error "Versuch $attempt/$max_tries für '$*' fehlgeschlagen – warte $delay s und retry..."
      sleep "$delay"
      (( attempt++ ))
    fi
  done

  print_success "Befehl '$*' erfolgreich nach $attempt Versuch(en)."
}

print_info "Homebrew & Bundle mit Retries"

if ! command -v brew &>/dev/null; then
  print_info "Installing Homebrew…"
  retry 3 10 NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || exit 1
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  print_success "Homebrew already installed."
fi

print_info "Running brew bundle…"
retry 3 5 brew bundle --file="$ROOT_DIR/core/Brewfile" || exit 1

print_info "Cleanup, upgrade & update…"
retry 2 5 brew cleanup
retry 2 5 brew upgrade
retry 2 5 brew update

if brew doctor; then
  print_success "brew doctor OK"
else
  print_error "brew doctor found issues"
fi
