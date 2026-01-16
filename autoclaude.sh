# Run Claude Code autonomously in tmux with session management
autoclaude() {
    _autoclaude_main "$@"
}

# Show detailed documentation for autoclaude command
autoclaude-help() {
    cat <<'EOF'
AUTOCLAUDE - Run Claude Code Autonomously in tmux

SYNOPSIS
    autoclaude [options] "prompt"
    autoclaude -f <instruction_file>
    autoclaude <command>

DESCRIPTION
    autoclaude runs Claude Code in a detached tmux session, allowing you to
    start long-running AI tasks and check back later. It captures all output
    to JSON files for later analysis.

OPTIONS
    -f, --file <file>       Read instructions from a file (plain text or markdown)
    -s, --session <name>    Set tmux session name (default: claude-task)
    -o, --output <dir>      Set output directory (default: ./claude-outputs)
    -t, --tools <tools>     Comma-separated allowed tools
    -m, --mode <mode>       Permission mode: default|acceptEdits|bypassPermissions|plan
    -n, --max-turns <n>     Max conversation turns (0 = unlimited)
    --skip-permissions      Bypass all permissions (DANGEROUS - isolated env only)
    -h, --help              Show brief help message

COMMANDS
    --status                Show running Claude sessions
    --attach                Attach to the tmux session (Ctrl+B, D to detach)
    --kill                  Kill the tmux session
    --logs                  Tail the latest log file
    --list                  List all output files
    --list-tmux             List all running autoclaude tmux sessions
    --resume [session_id]   Resume the last session (or specify session ID)
    --continue "prompt"     Continue last session with a new prompt
    --sessions              List all saved session IDs

ENVIRONMENT VARIABLES
    CLAUDE_SESSION_NAME     tmux session name
    CLAUDE_OUTPUT_DIR       Output directory
    CLAUDE_ALLOWED_TOOLS    Comma-separated tools
    CLAUDE_PERMISSION_MODE  Permission mode
    CLAUDE_MAX_TURNS        Max conversation turns
    CLAUDE_SKIP_PERMISSIONS Set to 'true' to bypass all permissions

EXAMPLES
    # Simple prompt
    autoclaude "Implement a REST API for user authentication"

    # From instruction file
    autoclaude -f instructions.md

    # With specific tools and mode
    autoclaude -f task.txt --mode acceptEdits --tools "Read,Write,Edit"

    # Check on running task
    autoclaude --status
    autoclaude --attach

    # Resume previous session
    autoclaude --resume
    autoclaude --continue "Now add unit tests"

WORKFLOW
    1. Start a task:     autoclaude "your task description"
    2. Detach if needed: (it runs in background automatically)
    3. Check progress:   autoclaude --status
    4. View live output: autoclaude --attach (Ctrl+B, D to detach)
    5. See results:      autoclaude --logs

FAQ
    Q: Where should I run this command?
    A: Run it from the root of your project directory. Claude Code operates
       relative to the current working directory, so it will read/write files
       within that project. The working directory is preserved in the tmux session.

    Q: Can I resume a session using Claude Code's /resume command?
    A: Yes! autoclaude captures session IDs in the JSON output. Use:
       - 'autoclaude --resume' to resume the last session in tmux
       - 'autoclaude --sessions' to list all session IDs
       - Or run 'claude --resume <session_id>' directly in your terminal

    Q: When does the autonomous session stop?
    A: The session is fully autonomous and stops when:
       - Claude determines the task is complete
       - Claude encounters an error it cannot resolve
       - Max turns is reached (if set with -n/--max-turns)
       - You manually kill it with 'autoclaude --kill'

    Q: How do I see real-time progress?
    A: Use 'autoclaude --attach' to attach to the tmux session. You'll see
       Claude's live output. Press Ctrl+B, then D to detach without stopping
       the session. Alternatively, use 'autoclaude --logs' to tail the JSON
       output file.

    Q: Can I run multiple sessions at once?
    A: Yes, but you must use different session names with -s/--session:
         autoclaude -s "backend" "Implement the API"
         autoclaude -s "frontend" "Build React components"
       Then use the same -s flag for other commands:
         autoclaude -s "backend" --attach
         autoclaude -s "frontend" --status
       Use 'autoclaude --list-tmux' to see all running sessions.

BILLING
    This tool automatically unsets ANTHROPIC_API_KEY to prevent API billing.
    It will either use your Claude subscription (Pro/Max/Team/Enterprise) or
    fail with an authentication error if no subscription is configured.

    If you WANT to use API billing, set AUTOCLAUDE_ALLOW_API_BILLING=true.

    Autonomous sessions can consume many tokens quickly.
    Use --max-turns to limit token consumption.

NOTES
    - Requires: tmux, claude (Claude Code CLI), jq (optional, for session IDs)
    - Dependencies are auto-installed on first run if missing
    - Output files are saved as JSON in the output directory
    - Session can be resumed even after the tmux session ends
EOF
}

# ============================================
# Configuration (internal)
# ============================================
_AUTOCLAUDE_SESSION_NAME="${CLAUDE_SESSION_NAME:-claude-task}"
_AUTOCLAUDE_OUTPUT_DIR="${CLAUDE_OUTPUT_DIR:-./claude-outputs}"
_AUTOCLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-Read,Write,Edit,Bash(git *),Bash(npm *),Bash(python *)}"
_AUTOCLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE:-acceptEdits}"
_AUTOCLAUDE_MAX_TURNS="${CLAUDE_MAX_TURNS:-0}"
_AUTOCLAUDE_SKIP_PERMISSIONS="${CLAUDE_SKIP_PERMISSIONS:-false}"

# ============================================
# Colors (internal)
# ============================================
_AUTOCLAUDE_RED='\033[0;31m'
_AUTOCLAUDE_GREEN='\033[0;32m'
_AUTOCLAUDE_YELLOW='\033[1;33m'
_AUTOCLAUDE_BLUE='\033[0;34m'
_AUTOCLAUDE_NC='\033[0m'

# ============================================
# Helper functions (hidden from list_cmds)
# ============================================
_autoclaude_log_info() {
    echo -e "${_AUTOCLAUDE_BLUE}[INFO]${_AUTOCLAUDE_NC} $1"
}

_autoclaude_log_success() {
    echo -e "${_AUTOCLAUDE_GREEN}[OK]${_AUTOCLAUDE_NC} $1"
}

_autoclaude_log_warn() {
    echo -e "${_AUTOCLAUDE_YELLOW}[WARN]${_AUTOCLAUDE_NC} $1"
}

_autoclaude_log_error() {
    echo -e "${_AUTOCLAUDE_RED}[ERROR]${_AUTOCLAUDE_NC} $1"
}

_autoclaude_usage() {
    cat <<EOF
Usage: autoclaude [options] "prompt"
       autoclaude -f <instruction_file>
       autoclaude <command>

Options:
  -f, --file <file>       Read instructions from a file
  -s, --session <name>    Set tmux session name (default: claude-task)
  -o, --output <dir>      Set output directory (default: ./claude-outputs)
  -t, --tools <tools>     Comma-separated allowed tools
  -m, --mode <mode>       Permission mode: default|acceptEdits|bypassPermissions|plan
  -n, --max-turns <n>     Max conversation turns (0 = unlimited)
  --skip-permissions      Bypass all permissions (DANGEROUS)
  -h, --help              Show this help message

Commands:
  --status                Show running Claude sessions
  --attach                Attach to the tmux session
  --kill                  Kill the tmux session
  --logs                  Tail the latest log file
  --list                  List all output files
  --list-tmux             List all running autoclaude tmux sessions
  --resume [session_id]   Resume the last session (or specify session ID)
  --continue "prompt"     Continue last session with a new prompt
  --sessions              List all saved session IDs

Run 'autoclaude-help' for detailed documentation and examples.
EOF
}

_autoclaude_check_command() {
    local cmd="$1"
    local install_hint="$2"

    if ! command -v "$cmd" &> /dev/null; then
        _autoclaude_log_error "'$cmd' is not installed."
        echo ""
        echo "$install_hint"
        echo ""
        echo -n "Would you like to install '$cmd' now? [y/N] "
        read -r REPLY
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 1
        else
            _autoclaude_log_error "Cannot continue without '$cmd'. Please install it manually."
            return 2
        fi
    fi
    return 0
}

_autoclaude_install_tmux() {
    _autoclaude_log_info "Installing tmux..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install tmux
        else
            _autoclaude_log_error "Homebrew not found. Please install tmux manually:"
            echo "  brew install tmux"
            return 1
        fi
    elif [[ -f /etc/debian_version ]]; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif [[ -f /etc/redhat-release ]]; then
        if command -v dnf &> /dev/null; then
            sudo dnf install -y tmux
        else
            sudo yum install -y tmux
        fi
    elif [[ -f /etc/arch-release ]]; then
        sudo pacman -S --noconfirm tmux
    elif [[ -f /etc/alpine-release ]]; then
        sudo apk add tmux
    else
        _autoclaude_log_error "Unknown OS. Please install tmux manually."
        return 1
    fi

    if command -v tmux &> /dev/null; then
        _autoclaude_log_success "tmux installed successfully."
    else
        _autoclaude_log_error "Failed to install tmux."
        return 1
    fi
}

_autoclaude_install_claude() {
    _autoclaude_log_info "Installing Claude Code..."

    if ! command -v npm &> /dev/null; then
        _autoclaude_log_error "npm is required to install Claude Code."
        echo ""
        echo "Please install Node.js first:"
        echo "  - Visit: https://nodejs.org/"
        echo "  - Or use nvm: https://github.com/nvm-sh/nvm"
        return 1
    fi

    npm install -g @anthropic-ai/claude-code

    if command -v claude &> /dev/null; then
        _autoclaude_log_success "Claude Code installed successfully."
        echo ""
        _autoclaude_log_warn "You may need to run 'claude' once to authenticate."
    else
        _autoclaude_log_error "Failed to install Claude Code."
        return 1
    fi
}

_autoclaude_install_jq() {
    _autoclaude_log_info "Installing jq..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install jq
        else
            _autoclaude_log_error "Homebrew not found. Please install jq manually."
            return 1
        fi
    elif [[ -f /etc/debian_version ]]; then
        sudo apt-get update && sudo apt-get install -y jq
    elif [[ -f /etc/redhat-release ]]; then
        if command -v dnf &> /dev/null; then
            sudo dnf install -y jq
        else
            sudo yum install -y jq
        fi
    elif [[ -f /etc/arch-release ]]; then
        sudo pacman -S --noconfirm jq
    elif [[ -f /etc/alpine-release ]]; then
        sudo apk add jq
    else
        _autoclaude_log_error "Unknown OS. Please install jq manually."
        return 1
    fi

    if command -v jq &> /dev/null; then
        _autoclaude_log_success "jq installed successfully."
    else
        _autoclaude_log_error "Failed to install jq."
        return 1
    fi
}

_autoclaude_check_dependencies() {
    _autoclaude_log_info "Checking dependencies..."

    # Check tmux
    if ! _autoclaude_check_command "tmux" "tmux is a terminal multiplexer required for background sessions."; then
        _autoclaude_install_tmux || return 1
    fi

    # Check claude
    if ! _autoclaude_check_command "claude" "Claude Code CLI is required. Install via: npm install -g @anthropic-ai/claude-code"; then
        _autoclaude_install_claude || return 1
    fi

    # Check jq (optional but recommended)
    if ! command -v jq &> /dev/null; then
        _autoclaude_log_warn "'jq' is not installed. It's recommended for parsing JSON output."
        echo -n "Would you like to install 'jq'? [y/N] "
        read -r REPLY
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            _autoclaude_install_jq
        fi
    fi

    _autoclaude_log_success "All required dependencies are installed."
}

_autoclaude_ensure_output_dir() {
    mkdir -p "$_AUTOCLAUDE_OUTPUT_DIR"
}

_autoclaude_read_instruction_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        _autoclaude_log_error "Instruction file not found: $file"
        return 1
    fi

    _AUTOCLAUDE_COMMAND="$(cat "$file")"

    if [[ -z "$_AUTOCLAUDE_COMMAND" ]]; then
        _autoclaude_log_error "Instruction file is empty: $file"
        return 1
    fi

    _autoclaude_log_info "Loaded instructions from: $file"
    _autoclaude_log_info "Instructions length: ${#_AUTOCLAUDE_COMMAND} characters"
}

_autoclaude_start_session() {
    _autoclaude_check_dependencies || return 1
    _autoclaude_ensure_output_dir

    local timestamp="$(date +%Y%m%d-%H%M%S)"
    local json_output="${_AUTOCLAUDE_OUTPUT_DIR}/claude-${timestamp}.json"

    if [[ -z "$_AUTOCLAUDE_COMMAND" ]]; then
        _autoclaude_log_error "No instructions provided."
        echo "Use: autoclaude \"prompt\" or autoclaude -f <file>"
        return 1
    fi

    echo ""
    _autoclaude_log_info "Starting Claude Code autonomous session..."
    echo "  Session:  $_AUTOCLAUDE_SESSION_NAME"
    echo "  Output:   $json_output"
    echo "  Mode:     $_AUTOCLAUDE_PERMISSION_MODE"
    echo "  Tools:    $_AUTOCLAUDE_ALLOWED_TOOLS"
    if [[ "$_AUTOCLAUDE_SKIP_PERMISSIONS" == "true" ]]; then
        _autoclaude_log_warn "  SKIP_PERMISSIONS is enabled!"
    fi
    echo ""
    echo "  Instructions preview:"
    echo "  ─────────────────────"
    echo "$_AUTOCLAUDE_COMMAND" | head -10 | sed 's/^/    /'
    if [[ $(echo "$_AUTOCLAUDE_COMMAND" | wc -l) -gt 10 ]]; then
        echo "    ... (truncated)"
    fi
    echo ""

    # Kill existing session if it exists
    if tmux has-session -t "$_AUTOCLAUDE_SESSION_NAME" 2>/dev/null; then
        _autoclaude_log_warn "Session '$_AUTOCLAUDE_SESSION_NAME' already exists."
        echo -n "Kill existing session and start new one? [y/N] "
        read -r REPLY
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            tmux kill-session -t "$_AUTOCLAUDE_SESSION_NAME"
        else
            _autoclaude_log_info "Aborted. Use --attach to connect to existing session."
            return 0
        fi
    fi

    # Create a temporary script file to handle complex commands
    local tmp_script="${_AUTOCLAUDE_OUTPUT_DIR}/.claude-run-${timestamp}.sh"
    local working_dir="$(pwd)"

    # Write the instruction to a temp file to avoid escaping issues
    local instruction_tmp="${_AUTOCLAUDE_OUTPUT_DIR}/.claude-instruction-${timestamp}.txt"
    echo "$_AUTOCLAUDE_COMMAND" > "$instruction_tmp"

    # Build optional arguments
    local max_turns_arg=""
    if [[ "$_AUTOCLAUDE_MAX_TURNS" -gt 0 ]]; then
        max_turns_arg="--max-turns $_AUTOCLAUDE_MAX_TURNS"
    fi

    local skip_perm_arg=""
    if [[ "$_AUTOCLAUDE_SKIP_PERMISSIONS" == "true" ]]; then
        skip_perm_arg="--dangerously-skip-permissions"
    fi

    cat > "$tmp_script" <<SCRIPT
#!/bin/bash
cd "$working_dir"

# Unset API key to prevent API billing unless explicitly allowed
if [[ "\${AUTOCLAUDE_ALLOW_API_BILLING:-false}" != "true" ]]; then
    unset ANTHROPIC_API_KEY
fi

INSTRUCTION="\$(cat "$instruction_tmp")"

claude -p "\$INSTRUCTION" \\
    --allowedTools "$_AUTOCLAUDE_ALLOWED_TOOLS" \\
    --permission-mode "$_AUTOCLAUDE_PERMISSION_MODE" \\
    $max_turns_arg \\
    $skip_perm_arg \\
    --verbose \\
    --output-format stream-json \\
    2>&1 | tee "$json_output"

exit_code=\${PIPESTATUS[0]}
echo ""
echo "════════════════════════════════════════"
echo "Claude Code finished with exit code: \$exit_code"
echo "Output saved to: $json_output"
echo "════════════════════════════════════════"
echo "Press Enter to close this session..."
read

rm -f "$instruction_tmp"
SCRIPT

    chmod +x "$tmp_script"

    # Start new tmux session with remain-on-exit so it stays open
    tmux new-session -d -s "$_AUTOCLAUDE_SESSION_NAME"
    tmux set-option -t "$_AUTOCLAUDE_SESSION_NAME" remain-on-exit on
    tmux send-keys -t "$_AUTOCLAUDE_SESSION_NAME" "bash '$tmp_script'" Enter

    _autoclaude_log_success "Session started!"
    echo ""
    echo "Commands to interact:"
    echo "  autoclaude --attach   # Attach to session (Ctrl+B, D to detach)"
    echo "  autoclaude --status   # Check status"
    echo "  autoclaude --logs     # View output"
    echo "  autoclaude --kill     # Stop session"
}

_autoclaude_show_status() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Claude Code Session Status"
    echo "═══════════════════════════════════════════"

    if tmux has-session -t "$_AUTOCLAUDE_SESSION_NAME" 2>/dev/null; then
        _autoclaude_log_success "Session '$_AUTOCLAUDE_SESSION_NAME': RUNNING"
    else
        _autoclaude_log_warn "Session '$_AUTOCLAUDE_SESSION_NAME': NOT RUNNING"
    fi

    echo ""

    local latest
    latest=$(ls -t "$_AUTOCLAUDE_OUTPUT_DIR"/claude-*.json 2>/dev/null | head -1)

    if [[ -n "$latest" ]]; then
        echo "Latest output: $latest"
        echo "Size: $(du -h "$latest" | cut -f1)"
        echo ""
        echo "Last 15 lines:"
        echo "─────────────────────────────────────────"
        tail -15 "$latest"
    else
        _autoclaude_log_info "No output files found in $_AUTOCLAUDE_OUTPUT_DIR"
    fi
}

_autoclaude_attach_session() {
    if tmux has-session -t "$_AUTOCLAUDE_SESSION_NAME" 2>/dev/null; then
        _autoclaude_log_info "Attaching to session '$_AUTOCLAUDE_SESSION_NAME'..."
        _autoclaude_log_info "Press Ctrl+B, then D to detach."
        tmux attach -t "$_AUTOCLAUDE_SESSION_NAME"
    else
        _autoclaude_log_error "No session named '$_AUTOCLAUDE_SESSION_NAME' found."
        return 1
    fi
}

_autoclaude_kill_session() {
    if tmux kill-session -t "$_AUTOCLAUDE_SESSION_NAME" 2>/dev/null; then
        _autoclaude_log_success "Session '$_AUTOCLAUDE_SESSION_NAME' killed."
    else
        _autoclaude_log_warn "No session named '$_AUTOCLAUDE_SESSION_NAME' found."
    fi
}

_autoclaude_show_logs() {
    local latest
    latest=$(ls -t "$_AUTOCLAUDE_OUTPUT_DIR"/claude-*.json 2>/dev/null | head -1)

    if [[ -n "$latest" ]]; then
        _autoclaude_log_info "Tailing: $latest"
        _autoclaude_log_info "Press Ctrl+C to stop."
        echo "═══════════════════════════════════════════"
        tail -f "$latest"
    else
        _autoclaude_log_error "No log files found in $_AUTOCLAUDE_OUTPUT_DIR"
        return 1
    fi
}

_autoclaude_list_outputs() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Claude Code Output Files"
    echo "═══════════════════════════════════════════"

    if [[ -d "$_AUTOCLAUDE_OUTPUT_DIR" ]]; then
        ls -lah "$_AUTOCLAUDE_OUTPUT_DIR"/claude-*.json 2>/dev/null || _autoclaude_log_info "No output files found."
    else
        _autoclaude_log_info "Output directory does not exist: $_AUTOCLAUDE_OUTPUT_DIR"
    fi
}

_autoclaude_list_tmux() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Running Autoclaude tmux Sessions"
    echo "═══════════════════════════════════════════"

    if ! command -v tmux &> /dev/null; then
        _autoclaude_log_error "tmux is not installed."
        return 1
    fi

    local sessions
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "^claude" || true)

    if [[ -z "$sessions" ]]; then
        _autoclaude_log_info "No running autoclaude sessions found."
        echo ""
        echo "Start a new session with:"
        echo "  autoclaude \"your task\""
        echo "  autoclaude -s \"session-name\" \"your task\""
    else
        echo ""
        printf "  %-20s %s\n" "SESSION NAME" "STATUS"
        printf "  %-20s %s\n" "------------" "------"
        for session in $sessions; do
            printf "  %-20s %s\n" "$session" "running"
        done
        echo ""
        echo "To attach: autoclaude -s \"<session-name>\" --attach"
        echo "To kill:   autoclaude -s \"<session-name>\" --kill"
    fi
}

_autoclaude_get_last_session_id() {
    local latest
    latest=$(ls -t "$_AUTOCLAUDE_OUTPUT_DIR"/claude-*.json 2>/dev/null | head -1)

    if [[ -n "$latest" ]] && command -v jq &> /dev/null; then
        jq -r 'select(.session_id != null) | .session_id' "$latest" 2>/dev/null | tail -1
    else
        echo ""
    fi
}

_autoclaude_list_sessions() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Claude Code Session IDs"
    echo "═══════════════════════════════════════════"

    if ! command -v jq &> /dev/null; then
        _autoclaude_log_error "jq is required to extract session IDs. Please install it."
        return 1
    fi

    if [[ -d "$_AUTOCLAUDE_OUTPUT_DIR" ]]; then
        for file in "$_AUTOCLAUDE_OUTPUT_DIR"/claude-*.json; do
            if [[ -f "$file" ]]; then
                local session_id
                session_id=$(jq -r 'select(.session_id != null) | .session_id' "$file" 2>/dev/null | tail -1)
                if [[ -n "$session_id" ]]; then
                    local filename=$(basename "$file")
                    local timestamp=$(echo "$filename" | sed 's/claude-\([0-9-]*\)\.json/\1/')
                    echo "  $session_id  ($timestamp)"
                fi
            fi
        done
    else
        _autoclaude_log_info "No sessions found in $_AUTOCLAUDE_OUTPUT_DIR"
    fi
}

_autoclaude_resume_session() {
    local session_id="$1"
    local continue_prompt="$2"

    _autoclaude_check_dependencies || return 1
    _autoclaude_ensure_output_dir

    local timestamp="$(date +%Y%m%d-%H%M%S)"
    local json_output="${_AUTOCLAUDE_OUTPUT_DIR}/claude-${timestamp}.json"

    # If no session ID provided, get the last one
    if [[ -z "$session_id" ]]; then
        session_id=$(_autoclaude_get_last_session_id)
        if [[ -z "$session_id" ]]; then
            _autoclaude_log_error "No previous session found to resume."
            _autoclaude_log_info "Use --sessions to list available sessions."
            return 1
        fi
        _autoclaude_log_info "Resuming last session: $session_id"
    fi

    echo ""
    _autoclaude_log_info "Resuming Claude Code session..."
    echo "  Session ID:  $session_id"
    echo "  Output:      $json_output"
    if [[ -n "$continue_prompt" ]]; then
        echo "  Prompt:      $continue_prompt"
    fi
    echo ""

    # Kill existing tmux session if it exists
    if tmux has-session -t "$_AUTOCLAUDE_SESSION_NAME" 2>/dev/null; then
        _autoclaude_log_warn "Session '$_AUTOCLAUDE_SESSION_NAME' already exists."
        echo -n "Kill existing session and start resume? [y/N] "
        read -r REPLY
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            tmux kill-session -t "$_AUTOCLAUDE_SESSION_NAME"
        else
            _autoclaude_log_info "Aborted."
            return 0
        fi
    fi

    # Create resume script
    local tmp_script="${_AUTOCLAUDE_OUTPUT_DIR}/.claude-resume-${timestamp}.sh"
    local working_dir="$(pwd)"

    # Build optional arguments
    local max_turns_arg=""
    if [[ "$_AUTOCLAUDE_MAX_TURNS" -gt 0 ]]; then
        max_turns_arg="--max-turns $_AUTOCLAUDE_MAX_TURNS"
    fi

    local skip_perm_arg=""
    if [[ "$_AUTOCLAUDE_SKIP_PERMISSIONS" == "true" ]]; then
        skip_perm_arg="--dangerously-skip-permissions"
    fi

    if [[ -n "$continue_prompt" ]]; then
        local instruction_tmp="${_AUTOCLAUDE_OUTPUT_DIR}/.claude-instruction-${timestamp}.txt"
        echo "$continue_prompt" > "$instruction_tmp"

        cat > "$tmp_script" <<SCRIPT
#!/bin/bash
cd "$working_dir"

# Unset API key to prevent API billing unless explicitly allowed
if [[ "\${AUTOCLAUDE_ALLOW_API_BILLING:-false}" != "true" ]]; then
    unset ANTHROPIC_API_KEY
fi

INSTRUCTION="\$(cat "$instruction_tmp")"

claude --resume "$session_id" -p "\$INSTRUCTION" \\
    --allowedTools "$_AUTOCLAUDE_ALLOWED_TOOLS" \\
    --permission-mode "$_AUTOCLAUDE_PERMISSION_MODE" \\
    $max_turns_arg \\
    $skip_perm_arg \\
    --verbose \\
    --output-format stream-json \\
    2>&1 | tee "$json_output"

exit_code=\${PIPESTATUS[0]}
echo ""
echo "════════════════════════════════════════"
echo "Claude Code finished with exit code: \$exit_code"
echo "Output saved to: $json_output"
echo "════════════════════════════════════════"
echo "Press Enter to close this session..."
read

rm -f "$instruction_tmp"
SCRIPT
    else
        cat > "$tmp_script" <<SCRIPT
#!/bin/bash
cd "$working_dir"

# Unset API key to prevent API billing unless explicitly allowed
if [[ "\${AUTOCLAUDE_ALLOW_API_BILLING:-false}" != "true" ]]; then
    unset ANTHROPIC_API_KEY
fi

claude --resume "$session_id"
echo ""
echo "Press Enter to close this session..."
read
SCRIPT
    fi

    chmod +x "$tmp_script"

    # Start tmux session with remain-on-exit so it stays open
    tmux new-session -d -s "$_AUTOCLAUDE_SESSION_NAME"
    tmux set-option -t "$_AUTOCLAUDE_SESSION_NAME" remain-on-exit on
    tmux send-keys -t "$_AUTOCLAUDE_SESSION_NAME" "bash '$tmp_script'" Enter

    _autoclaude_log_success "Resume session started!"
    echo ""
    echo "Commands to interact:"
    echo "  autoclaude --attach   # Attach to session"
    echo "  autoclaude --status   # Check status"
    echo "  autoclaude --logs     # View output"
    echo "  autoclaude --kill     # Stop session"
}

_autoclaude_main() {
    # Reset state for each invocation
    _AUTOCLAUDE_SESSION_NAME="${CLAUDE_SESSION_NAME:-claude-task}"
    _AUTOCLAUDE_OUTPUT_DIR="${CLAUDE_OUTPUT_DIR:-./claude-outputs}"
    _AUTOCLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-Read,Write,Edit,Bash(git *),Bash(npm *),Bash(python *)}"
    _AUTOCLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE:-acceptEdits}"
    _AUTOCLAUDE_MAX_TURNS="${CLAUDE_MAX_TURNS:-0}"
    _AUTOCLAUDE_SKIP_PERMISSIONS="${CLAUDE_SKIP_PERMISSIONS:-false}"
    _AUTOCLAUDE_COMMAND=""
    local instruction_file=""

    if [[ $# -eq 0 ]]; then
        _autoclaude_usage
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--file)
                instruction_file="$2"
                shift 2
                ;;
            -s|--session)
                _AUTOCLAUDE_SESSION_NAME="$2"
                shift 2
                ;;
            -o|--output)
                _AUTOCLAUDE_OUTPUT_DIR="$2"
                shift 2
                ;;
            -t|--tools)
                _AUTOCLAUDE_ALLOWED_TOOLS="$2"
                shift 2
                ;;
            -m|--mode)
                _AUTOCLAUDE_PERMISSION_MODE="$2"
                shift 2
                ;;
            -n|--max-turns)
                _AUTOCLAUDE_MAX_TURNS="$2"
                shift 2
                ;;
            --skip-permissions)
                _AUTOCLAUDE_SKIP_PERMISSIONS="true"
                shift
                ;;
            --status)
                _autoclaude_show_status
                return 0
                ;;
            --attach)
                _autoclaude_attach_session
                return $?
                ;;
            --kill)
                _autoclaude_kill_session
                return 0
                ;;
            --logs)
                _autoclaude_show_logs
                return $?
                ;;
            --list)
                _autoclaude_list_outputs
                return 0
                ;;
            --list-tmux)
                _autoclaude_list_tmux
                return $?
                ;;
            --sessions)
                _autoclaude_list_sessions
                return $?
                ;;
            --resume)
                local resume_id=""
                if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                    resume_id="$2"
                    shift
                fi
                _autoclaude_resume_session "$resume_id" ""
                return $?
                ;;
            --continue)
                if [[ -z "${2:-}" ]]; then
                    _autoclaude_log_error "--continue requires a prompt argument"
                    return 1
                fi
                _autoclaude_resume_session "" "$2"
                return $?
                ;;
            -h|--help)
                _autoclaude_usage
                return 0
                ;;
            -*)
                _autoclaude_log_error "Unknown option: $1"
                echo "Use 'autoclaude --help' for usage."
                return 1
                ;;
            *)
                if [[ -z "$instruction_file" ]]; then
                    _AUTOCLAUDE_COMMAND="$1"
                fi
                shift
                ;;
        esac
    done

    # Read from instruction file if specified
    if [[ -n "$instruction_file" ]]; then
        _autoclaude_read_instruction_file "$instruction_file" || return 1
    fi

    _autoclaude_start_session
}
