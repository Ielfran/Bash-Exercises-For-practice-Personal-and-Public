#!/bin/bash

# ██╗░░██╗██╗░░░██╗███████╗████████╗░██████╗████████╗██╗░░██╗██╗░░░░░██╗░░░░░
# ██║░░██║██║░░░██║██╔════╝╚══██╔══╝██╔════╝╚══██╔══╝██║░░██║██║░░░░░██║░░░░░
# ███████║██║░░░██║█████╗░░░░░██║░░░╚█████╗░░░░██║░░░███████║██║░░░░░██║░░░░░
# ██╔══██║██║░░░██║██╔══╝░░░░░██║░░░░╚═══██╗░░░██║░░░██╔══██║██║░░░░░██║░░░░░
# ██║░░██║╚██████╔╝███████╗░░░██║░░░██████╔╝░░░██║░░░██║░░██║███████╗███████╗
# ╚═╝░░╚═╝░╚═════╝░╚══════╝░░░╚═╝░░░╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚══════╝╚══════╝
#
# A custom shell wrapper to make your terminal experience more advanced.
# Author: An AI Assistant
# Version: 1.0

# --- CONFIGURATION ---
HISTORY_FILE=~/.custom_shell_history
CONFIG_DIR=~/.custom_shell
PLUGINS_DIR="$CONFIG_DIR/plugins"

# --- COLORS & STYLING ---
# Use tput to make it compatible with most terminals
C_RESET=$(tput sgr0)
C_BOLD=$(tput bold)
C_USER=$(tput setaf 6) # Cyan
C_AT=$(tput setaf 7)   # White
C_HOST=$(tput setaf 2) # Green
C_COLON=$(tput setaf 7) # White
C_DIR=$(tput setaf 4)   # Blue
C_GIT=$(tput setaf 1)    # Red
C_PROMPT=$(tput setaf 7) # White

# --- CORE FUNCTIONS ---

# Function to parse Git branch and status
#- Displays branch name.
# - Shows '*' if there are unstaged changes.
# - Shows '+' if there are staged changes.
function parse_git_branch() {
    local git_status
    git_status=$(git status 2> /dev/null)
    if [[ $? -ne 0 ]]; then # Not a git repo
        return
    fi

    local branch
    branch=$(echo "$git_status" | grep 'On branch' | sed -e 's/On branch //')
    local dirty
    if [[ $(echo "$git_status" | grep 'Changes not staged for commit') ]]; then
        dirty="*"
    fi
    local staged
    if [[ $(echo "$git_status" | grep 'Changes to be committed') ]]; then
        staged="+"
    fi
    
    echo " ($C_GIT${branch}${staged}${dirty}$C_RESET)"
}

# Function to build and update the prompt
function update_prompt() {
    local user="${C_USER}${USER}${C_RESET}"
    local at="${C_AT}@${C_RESET}"
    local host="${C_HOST}${HOSTNAME%%.*}${C_RESET}"
    local dir="${C_BOLD}${C_DIR}${PWD/#$HOME/~}${C_RESET}"
    local git_branch
    git_branch=$(parse_git_branch)
    local prompt_char="${C_PROMPT}\$ ${C_RESET}"
    
    # PS1 is the primary prompt string. We build it here.
    PS1="${user}${at}${host}${C_COLON}:${C_RESET}${dir}${git_branch}\n${prompt_char}"
}

# Load plugins from the plugins directory
function load_plugins() {
    if [ -d "$PLUGINS_DIR" ]; then
        for plugin in "$PLUGINS_DIR"/*.sh; do
            if [ -r "$plugin" ]; then
                # shellcheck source=/dev/null
                source "$plugin"
            fi
        done
        # echo "Loaded plugins from $PLUGINS_DIR"
    fi
}

# Show help for custom commands
function shell_help() {
    echo -e "${C_BOLD}Custom Shell Help${C_RESET}"
    echo "-------------------"
    echo -e "${C_BOLD}help${C_RESET}      - Shows this help message."
    echo -e "${C_BOLD}exit${C_RESET}      - Exits the shell."
    echo -e "${C_BOLD}history${C_RESET}   - Shows command history (using fc)."
    echo -e "${C_BOLD}take <dir>${C_RESET} - Creates a directory and cds into it."
    echo ""
    echo "You can add your own functions by creating .sh files in ${PLUGS_DIR}"
}


# --- INITIALIZATION ---

# Display a welcome banner
clear
cat << "EOF"

 ___   ___   _    _____  _____   __ _  _ __
|_ _| | __| | |   |  _| | | | | / _` || '_ \
 | |  | _|  | |_  | |_  | |=| || (_| || | | |
|___| |___| |___| |_|   |_| |_| \__,_||_| |_|

EOF
echo "Welcome, ${USER}! Type 'help' for custom commands."
echo "----------------------------------------------------"


# Setup history
# Merges history from previous sessions and enables saving for this session
history -a # Append to history file from this session
history -c # Clear the current session's history in memory
history -r "$HISTORY_FILE" # Read history from the file into memory
PROMPT_COMMAND="history -a '$HISTORY_FILE'; $PROMPT_COMMAND"

# Load smart aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'


# Load all plugins
load_plugins

# --- MAIN SHELL LOOP ---
# The core of our custom shell. It reads a command, executes it, and repeats.
# We're using bash's own read and execution capabilities, but with our custom prompt.

# Trap Ctrl-C and do nothing, to prevent killing the shell
trap '' INT

while true; do
    # 1. Set the prompt
    update_prompt

    # 2. Read user input
    #    -e: enables readline for arrow keys, history search, etc.
    #    -p: displays the prompt string (our PS1)
    if ! read -e -p "$(echo -ne "$PS1")" CMD; then
        # This triggers on Ctrl+D (EOF)
        echo -e "\nexit"
        break
    fi

    # 3. If command is empty, just show a new prompt
    [[ -z "$CMD" ]] && continue
    
    # 4. Add command to history (in-memory)
    history -s "$CMD"

    # 5. Execute the command
    # We use 'eval' to correctly handle pipes, redirection, and complex commands.
    # WARNING: 'eval' can be a security risk if you run scripts from untrusted sources.
    # For a personal shell, this is generally acceptable.
    
    # Handle built-in commands first to avoid subshell issues
    # `cd` MUST be handled this way, otherwise it only affects a subshell.
    first_word=$(echo "$CMD" | awk '{print $1;}')
    case "$first_word" in
        "exit")
            break
            ;;
        "cd")
            # Extract the directory path. `eval` is safe here because we're just
            # expanding potential variables like ~ or $HOME.
            dir=$(eval echo "$(echo "$CMD" | cut -d' ' -f2-)")
            if [ -z "$dir" ]; then
                cd "$HOME" || echo "bash: cd: $HOME: No such file or directory"
            else
                cd "$dir" || echo "bash: cd: $dir: No such file or directory"
            fi
            ;;
        "help")
            shell_help
            ;;
        *)
            # For all other commands, use eval
            eval "$CMD"
            ;;
    esac

done

# --- CLEANUP ---
# Save the history one last time before exiting
history -w "$HISTORY_FILE"
echo "Goodbye!"
