# Fuzzy search and connect to SSH locations stored in dotfiles/data/ssh.json
sshto() {
  # 1. Dependency Checks (reuse helper from rx.sh)
  _rx_ensure_dependency "jq" "jq" || return 1
  _rx_ensure_dependency "fzf" "fzf" || return 1

  # 2. Locate Data File
  local json_file="$HOME/dotfiles/data/ssh.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: SSH config not found at $json_file"
    return 1
  fi

  # 3. Build selection list (desc + cmd)
  local selection=$(jq -r '.[] | "\(.desc)\t\(.cmd)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=40% --layout=reverse --border \
        --header="Select SSH destination (Enter to connect)" \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local cmd=$(echo "$selection" | awk -F'\t' '{print $2}')
    echo "Connecting: $cmd"
    eval "$cmd"
  fi
}
