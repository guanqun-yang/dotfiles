# Dotfiles

A simple, version-control-friendly approach to organizing your custom bash commands.

## The Problem

Dumping custom scripts directly into `~/.bashrc` creates two headaches:

1. **Clutter**: Your `.bashrc` becomes an unreadable mess of aliases, functions, and configurations.
2. **Version control risks**: You can't safely commit your scripts to Git without exposing sensitive data like `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or other credentials mixed into the same file.

## The Solution

- Step 1: Store your scripts in a dedicated folder (e.g., `~/dotfiles`) and source them automatically.

- Step 2: Add this snippet to your `~/.bashrc`:
    ```bash
    # Source all .sh files in ~/dotfiles
    if [ -d ~/dotfiles ]; then
        for file in ~/dotfiles/*.sh; do
            [ -r "$file" ] && source "$file"
        done
    fi
    ```
- Step 3: Organize scripts by purpose (`git.sh`, `docker.sh`, `aliases.sh`, etc.)
- Step 4: Enjoy! Now you can version control everything cleanly with confidence.

## Examples

```bash
# check current available custom commands
list_cmds
```