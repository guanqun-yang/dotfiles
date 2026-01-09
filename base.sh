# List all available custom commands and their descriptions
list_cmds() {
    local dir="$HOME/dotfiles"
    
    # Header
    printf "\033[1;34m%-20s %-25s %s\033[0m\n" "Source File" "Command" "Description"
    printf "\033[1;34m%-20s %-25s %s\033[0m\n" "-----------" "-------" "-----------"

    for file in "$dir"/*.sh; do
        [ -e "$file" ] || continue
        filename=$(basename "$file")
        
        # Parse file for functions and comments using awk
        # Logic:
        # 1. Store comment lines starting with #
        # 2. If a function definition is found, print the stored comment (if any) and the function name
        # 3. Reset comment buffer on non-comment/non-function lines
        
        awk -v fname="$filename" '
            # Accumulate comments
            /^#/ { 
                # Remove leading # and space
                sub(/^# ?/, "", $0)
                if (doc == "") doc = $0
                else doc = doc " " $0
                next 
            }
            
            # Match standard function definition: func() {
            # Skip helper functions starting with _
            /^[a-zA-Z0-9_-]+\(\) *\{/ {
                cmd = $1
                sub(/\(\).*/, "", cmd)
                if (cmd !~ /^_/) {
                    printf "%-20s %-25s %s\n", fname, cmd, doc
                }
                doc = ""
                next
            }

            # Match bash function definition: function func { or function func() {
            # Skip helper functions starting with _
            /^function [a-zA-Z0-9_-]+/ {
                cmd = $2
                sub(/\(\)/, "", cmd) # Remove () if present
                if (cmd !~ /^_/) {
                    printf "%-20s %-25s %s\n", fname, cmd, doc
                }
                doc = ""
                next
            }
            
            # If line is empty, keep doc (allow one empty line maybe? for now let reset)
            # Actually, standard is usually attached.
            # If line is not a comment and not a function, reset doc.
            !/^[ \t]*$/ { doc = "" }
        ' "$file"
    done
}
