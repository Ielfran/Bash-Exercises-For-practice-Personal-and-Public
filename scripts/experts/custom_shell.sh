#!/bin/bash

HISTORY_FILE=~/.custom_shell_history
CONFIG_DIR=~/.custom_shell
PLUGINS_DIR="$CONFIG_DIR/plugins"

C_RESET=$(tput sgr0)
C_BOLD=$(tput bold)
C_USER=$(tput setaf 6) # Cyan
C_AT=$(tput setaf 7)   # White
C_HOST=$(tput setaf 2) # Green
C_COLON=$(tput setaf 7) # White
C_DIR=$(tput setaf 4)   # Blue
C_GIT=$(tput setaf 1)    # Red
C_PROMPT=$(tput setaf 7) # White

function parse_git_branch() {
    local git_status
    git_status=$(git status 2> /dev/null)
    if [[ $? -ne 0 ]]; then 
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

function update_prompt() {
    local user="${C_USER}${USER}${C_RESET}"
    local at="${C_AT}@${C_RESET}"
    local host="${C_HOST}${HOSTNAME%%.*}${C_RESET}"
    local dir="${C_BOLD}${C_DIR}${PWD/#$HOME/~}${C_RESET}"
    local git_branch
    git_branch=$(parse_git_branch)
    local prompt_char="${C_PROMPT}\$ ${C_RESET}"
    
    PS1="${user}${at}${host}${C_COLON}:${C_RESET}${dir}${git_branch}\n${prompt_char}"
}

function load_plugins() {
    if [ -d "$PLUGINS_DIR" ]; then
        for plugin in "$PLUGINS_DIR"/*.sh; do
            if [ -r "$plugin" ]; then
                source "$plugin"
            fi
        done
    fi
}

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


clear
cat << "EOF"

 ___   ___   _    _____  _____   __ _  _ __
|_ _| | __| | |   |  _| | | | | / _` || '_ \
 | |  | _|  | |_  | |_  | |=| || (_| || | | |
|___| |___| |___| |_|   |_| |_| \__,_||_| |_|

EOF
echo "Welcome, ${USER}! Type 'help' for custom commands."
echo "----------------------------------------------------"


history -a 
history -c 
history -r "$HISTORY_FILE"
PROMPT_COMMAND="history -a '$HISTORY_FILE'; $PROMPT_COMMAND"

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


load_plugins


trap '' INT

while true; do
    update_prompt

    if ! read -e -p "$(echo -ne "$PS1")" CMD; then
        echo -e "\nexit"
        break
    fi

    [[ -z "$CMD" ]] && continue
    
    history -s "$CMD"

    first_word=$(echo "$CMD" | awk '{print $1;}')
    case "$first_word" in
        "exit")
            break
            ;;
        "cd")
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
            eval "$CMD"
            ;;
    esac

done
history -w "$HISTORY_FILE"
echo "Goodbye!"
