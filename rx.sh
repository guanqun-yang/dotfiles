_rx_ensure_dependency() {
  local cmd="$1"
  local package="$2" # Sometimes the package name differs from the command (rare, but good practice)

  if ! command -v "$cmd" &> /dev/null; then
    echo "⚠️  Command '$cmd' is required but not found."

    # Determine the install command based on available package manager
    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install $package"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get update && sudo apt-get install -y $package"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S $package"
    else
      echo "❌ Could not detect a supported package manager (brew/apt/pacman)."
      echo "   Please install '$package' manually."
      return 1
    fi

    echo "   To install, run: $install_cmd"
    read -p "   Do you want to install '$package' now? (y/N) " -n 1 -r
    echo "" # New line

    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "📦 Running: $install_cmd"
      eval "$install_cmd"
    else
      echo "❌ Dependency missing. Aborting."
      return 1
    fi
  fi
}

# Fuzzy search and copy the frequently used regex stored in dotfiles/data/regex.json
rx() {
  # 1. Dependency Checks
  # We check for 'jq' and 'fzf'. If missing, we ask to install.
  _rx_ensure_dependency "jq" "jq" || return 1
  _rx_ensure_dependency "fzf" "fzf" || return 1

  # 2. Locate Data File
  local json_file="$HOME/dotfiles/data/regex.json"
  
  if [[ ! -f "$json_file" ]]; then
    echo "Error: Regex library not found at $json_file"
    return 1
  fi

  # 3. The Logic
  local selection=$(jq -r '.[] | "\(.desc)\t\(.pattern)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=40% --layout=reverse --border \
        --header="Select Regex (Enter to copy)" \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local pattern=$(echo "$selection" | awk -F'\t' '{print $2}')
    
    # Platform-agnostic clipboard
    if [[ "$OSTYPE" == "darwin"* ]]; then
      echo -n "$pattern" | pbcopy
    elif command -v wl-copy > /dev/null; then
      echo -n "$pattern" | wl-copy
    elif command -v xclip > /dev/null; then
      echo -n "$pattern" | xclip -selection clipboard
    else
      echo "⚠️  No clipboard tool found (pbcopy/wl-copy/xclip)."
      echo "   Here is your pattern:"
    fi

    echo "✅ Copied to clipboard!"
    echo "$pattern"
  fi
}
