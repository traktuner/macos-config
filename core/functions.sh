#!/usr/bin/env bash
set -euo pipefail

# — Benutzer­abfragen
answer_is_yes()    { [[ "$REPLY" =~ ^[Yy]$ ]]; }
ask_for_confirmation() {
  printf "\e[0;33m 🤔  %s (y/n) \e[0m" "$1"
  read -n1 -r; printf "\n"
}
ask_for_sudo() {
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# — Druck­funktionen
print_info()    { printf "\n\e[0;34m 👊  %s\e[0m\n" "$1"; }
print_success() { printf "\e[0;32m 👍  %s\e[0m\n" "$1"; }
print_error()   { printf "\e[0;31m 😡  %s\e[0m\n" "$1"; }

# — Symlink mit Bestätigung
symlink_from_to() {
  local FROM="$1" TO="$2"
  if [[ ! -e "$TO" ]]; then
    ln -fs "$FROM" "$TO" && print_success "Symlinked $(basename "$TO")"
  elif [[ "$(readlink "$TO")" == "$FROM" ]]; then
    print_success "$(basename "$TO") already linked"
  else
    ask_for_confirmation "$(basename "$TO") exists. Overwrite?"
    if answer_is_yes; then rm -rf "$TO"; ln -fs "$FROM" "$TO"; print_success "Re-symlinked"; 
    else print_info "Skipped $(basename "$FROM")"; fi
  fi
}

# — Text-Manipulation
modify_file() {
  [[ ! -f "$3" ]] && print_error "File not found:" "$3" && return 1
  grep -qF "$2" "$3" || awk "/$1/{print;print \"$2\";next}1" "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}

modify_line() {
  awk "{gsub(\"$1\",\"$2\")}1" "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}

insert_to_file_after_line_number() {
  awk -v ins="$1" '1; NR=='"$2"'{print ins}' "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}

uncomment_line() {
  sed -i '' "/$1/s/^#//" "$2"
}

prepend_string_to_file() {
  printf "%s\n" "$1" | cat - "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}

line_exists() { grep -qFx "$1" "$2"; }

add_config() {
  local file="$1" path="$2" content="$3" cfg="$path/$file"
  mkdir -p "$path"
  if [[ -f "$cfg" ]]; then
    while IFS= read -r line; do
      if line_exists "$line" "$cfg"; then print_info "Already in $file: $line"; return; fi
    done <<< "$content"
    printf "%s\n" "$content" >> "$cfg"
    print_success "Appended to $file"
  else
    printf "%s\n" "$content" > "$cfg"
    print_success "Created $file"
  fi
}

get_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo arm64 || echo x64
}
