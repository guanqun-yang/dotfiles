_prompt_ensure_dependency() {
  local cmd="$1"
  local package="$2"

  if ! command -v "$cmd" &> /dev/null; then
    echo "Warning: Command '$cmd' is required but not found."

    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install $package"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get update && sudo apt-get install -y $package"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S $package"
    else
      echo "Error: Could not detect a supported package manager (brew/apt/pacman)."
      echo "   Please install '$package' manually."
      return 1
    fi

    echo "   To install, run: $install_cmd"
    read -p "   Do you want to install '$package' now? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Running: $install_cmd"
      eval "$install_cmd"
    else
      echo "Error: Dependency missing. Aborting."
      return 1
    fi
  fi
}

# Fuzzy search and copy frequently used prompts stored in dotfiles/data/prompts.json
prompt() {
  _prompt_ensure_dependency "jq" "jq" || return 1
  _prompt_ensure_dependency "fzf" "fzf" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Prompt library not found at $json_file"
    return 1
  fi

  # Use base64 encoding to handle multi-line prompts
  local selection=$(jq -r '.[] | "\(.desc)\t\(.prompt | @base64)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=50% --layout=reverse --border \
        --header="Select Prompt (Enter to copy)" \
        --preview='echo {} | cut -f2 | base64 -d' \
        --preview-window=down:5:wrap \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local prompt_text=$(echo "$selection" | cut -f2 | base64 -d)

    # Platform-agnostic clipboard
    if [[ "$OSTYPE" == "darwin"* ]]; then
      echo -n "$prompt_text" | pbcopy
    elif command -v wl-copy > /dev/null; then
      echo -n "$prompt_text" | wl-copy
    elif command -v xclip > /dev/null; then
      echo -n "$prompt_text" | xclip -selection clipboard
    else
      echo "Warning: No clipboard tool found (pbcopy/wl-copy/xclip)."
      echo "   Here is your prompt:"
      echo "$prompt_text"
      return 0
    fi

    echo "Copied to clipboard!"
    echo "$prompt_text"
  fi
}

# Add a new prompt to the library
prompt_add() {
  _prompt_ensure_dependency "jq" "jq" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  if [[ ! -f "$json_file" ]]; then
    echo "[]" > "$json_file"
  fi

  local editor="${EDITOR:-vim}"

  # First editor: title
  local title_file="${TMPDIR:-/tmp}/prompt_title_$$.txt"
  echo "# Enter prompt title (single line)" > "$title_file"
  "$editor" "$title_file"
  local desc=$(grep -v '^#' "$title_file" | tr -d '\n')
  rm -f "$title_file"

  if [[ -z "$desc" ]]; then
    echo "Cancelled: No title."
    return 1
  fi

  # Second editor: prompt content
  local content_file="${TMPDIR:-/tmp}/prompt_content_$$.md"
  : > "$content_file"
  "$editor" "$content_file"
  local prompt_text=$(cat "$content_file")
  rm -f "$content_file"

  if [[ -z "$prompt_text" ]]; then
    echo "Cancelled: No prompt content."
    return 1
  fi

  # Add new prompt to JSON file
  local json_tmp=$(mktemp)
  jq --arg desc "$desc" --arg prompt "$prompt_text" \
    '. += [{"desc": $desc, "prompt": $prompt}]' "$json_file" > "$json_tmp" && \
    mv "$json_tmp" "$json_file"

  echo "Prompt added: $desc"
}

# List all prompts
prompt_list() {
  _prompt_ensure_dependency "jq" "jq" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Prompt library not found at $json_file"
    return 1
  fi

  jq -r '.[] | "[\(.desc)]"' "$json_file"
}
