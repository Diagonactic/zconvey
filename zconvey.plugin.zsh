#
# No plugin manager is needed to use this file. All that is needed is adding:
#   source {where-zconvey-is}/zconvey.plugin.zsh
#
# to ~/.zshrc.
#

0="${(%):-%N}" # this gives immunity to functionargzero being unset
ZCONVEY_REPO_DIR="${0%/*}"
ZCONVEY_CONFIG_DIR="$HOME/.config/zconvey"

#
# Update FPATH if:
# 1. Not loading with Zplugin
# 2. Not having fpath already updated (that would equal: using other plugin manager)
#

if [[ -z "$ZPLG_CUR_PLUGIN" && "${fpath[(r)$ZCONVEY_REPO_DIR]}" != $ZCONVEY_REPO_DIR ]]; then
    fpath+=( "$ZCONVEY_REPO_DIR" )
fi

#
# Load configuration
#

typeset -gi ZCONVEY_ID
typeset -hH ZCONVEY_FD
() {
    setopt localoptions extendedglob
    typeset -gA ZCONVEY_CONFIG

    local check_interval
    zstyle -s ":plugin:zconvey" check_interval check_interval || check_interval="2"
    [[ "$check_interval" != <-> ]] && check_interval="2"
    ZCONVEY_CONFIG[check_interval]="$check_interval"

    local use_zsystem_flock
    zstyle -s ":plugin:zconvey" use_zsystem_flock use_zsystem_flock || use_zsystem_flock="1"
    [[ "$use_zsystem_flock" != <-> ]] && use_zsystem_flock="1"
    ZCONVEY_CONFIG[use_zsystem_flock]="$use_zsystem_flock"
}

#
# Compile myflock
#

# Binary flock command that supports 0 second timeout (zsystem's
# flock in Zsh ver. < 5.3 doesn't) - util-linux/flock stripped
# of some things, compiles hopefully everywhere (tested on OS X,
# Linux).
if [ ! -e "${ZCONVEY_REPO_DIR}/myflock/flock" ]; then
    echo "\033[1;35m""psprint\033[0m/\033[1;33m""zconvey\033[0m is building small locking command for you..."
    make -C "${ZCONVEY_REPO_DIR}/myflock"
fi

#
# Acquire ID
#

() {
    local LOCKS_DIR="${ZCONVEY_CONFIG_DIR}/locks"
    mkdir -p "${LOCKS_DIR}" "${ZCONVEY_CONFIG_DIR}/io"

    integer idx res
    local fd
    
    # Supported are 100 shells - acquire takes ~330ms max
    ZCONVEY_ID="-1"
    for (( idx=1; idx <= 100; idx ++ )); do
        touch "${LOCKS_DIR}/zsh_nr${idx}"
        exec {ZCONVEY_FD}<"${LOCKS_DIR}/zsh_nr${idx}"
        "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "${ZCONVEY_FD}"
        res="$?"

        if [ "$res" = "101" ]; then
            exec {ZCONVEY_FD}<&-
        else
            ZCONVEY_ID=idx
            break
        fi
    done

}

#
# Function to check for input commands
#

function __convey_on_period_passed() {
    local fd lockfile="${ZCONVEY_CONFIG_DIR}/io/${ZCONVEY_ID}.io.lock"

    touch "$lockfile"
    if zsystem flock -t 1 -f fd -r "$lockfile"; then
        echo "Got at command"
        zsystem flock -u "$fd"
    fi

    sched +"${ZCONVEY_CONFIG[check_interval]}" __convey_on_period_passed
}

#
# Startup, other
#

# Not called ideally at say SIGTERM, but
# at least when "exit" is enterred
function __convey_zshexit() {
    exec {ZCONVEY_FD}<&-
}

if ! type sched 2>/dev/null 1>&2; then
    if ! zmodload zsh/sched 2>/dev/null; then
        echo "zsh/sched module not found, Zconvey cannot work with this Zsh build"
        return 1
    fi
fi

if [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "1" ]; then
    if ! zmodload zsh/system 2>/dev/null; then
        echo "Zconvey plugin: \033[1;31mzsh/system module not found, will use own flock implementation\033[0m"
        echo "Zconvey plugin: \033[1;31mDisable this warning via: zstyle \":plugin:zconvey\" use_zsystem_flock \"0\"\033[0m"
        ZCONVEY_CONFIG[use_zsystem_flock]="0"
    elif ! zsystem supports flock; then
        echo "Zconvey plugin: \033[1;31mzsh/system module doesn't provide flock, will use own implementation\033[0m"
        echo "Zconvey plugin: \033[1;31mDisable this warning via: zstyle \":plugin:zconvey\" use_zsystem_flock \"0\"\033[0m"
        ZCONVEY_CONFIG[use_zsystem_flock]="0"
    fi
fi

sched +"${ZCONVEY_CONFIG[check_interval]}" __convey_on_period_passed
autoload -Uz add-zsh-hook
add-zsh-hook zshexit __convey_zshexit
