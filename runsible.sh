#!/bin/bash

VENV="venv"
INTERPRETER="$( which python3 )"

REQUIREMENTS=( pip3 flock realpath dirname git logger "$INTERPRETER" )
VENV_REQUIREMENTS=( bin/ansible bin/ansible-playbook bin/ansible-galaxy bin/ansible-lint )

if [ -z "$INTERPRETER" ]; then
    echo "Python3 not found, bootstrapping from apt"
    sudo apt install python3 python3-pip
fi

SELF="$0"
if [ "$SELF" == '-bash' ] || [ "$SELF" == 'bash' ] || [[ "$SELF" == *"/bash" ]] ; then
    SELF="$BASH_SOURCE"
fi

MYFULL="$(realpath -- "$SELF")"
MYPATH="$(dirname -- "$MYFULL")"
[ -z "${MYPATH}" ] && echo "Could not find my path" && exit 1 
INSTANCE="$(basename -- "$MYPATH")"
BASE_LIBRARY="$MYPATH/helpers/_lib.sh"

# shellcheck source=helpers/_lib.sh
if [ -e "$BASE_LIBRARY" ]; then 
    source "$BASE_LIBRARY"
else
    echo "Library not found: '$BASE_LIBRARY'"
    exit 1
fi

GALAXY_REQUIREMENTS="${MYPATH}/galaxy-requirements.yml"
GALAXY_LOCAL_REQUIREMENTS="${MYPATH}/galaxy-requirements.local.yml"

RUNSIBLE_CONF="${MYPATH}/runsible.yml"

PIP_REQUIREMENTS="${MYPATH}/requirements.txt"
PIP_LOCAL_REQUIREMENTS="${MYPATH}/requirements.local.txt"

CMD_INVOKED="$( basename -- "$SELF" )"

function flagname() {
    THISPATH="$1"
    if [ -f "$THISPATH" ]; then
        DIRNAME="$( dirname "$THISPATH" )"
        FILENAME="$( basename "$THISPATH" )"
        FLAG="${DIRNAME}/.flag.${FILENAME}"
    elif [ -d "$THISPATH" ]; then
        FLAG="$THISPATH/.dflag"
    fi
    echo "$FLAG"
}

function any_has_changed() {
    for FILE in "$@"; do
        FLAG="$( flagname "$FILE" )"
        if [ -e "$FILE" ]; then
            [ ! -f "$FLAG" ] && return 0
            [ "$FILE" -nt "$FLAG" ] && return 0
        fi
    done
    return 1
}

function flag() {
    for FILE in "$@"; do
        FLAG="$( flagname "$FILE" )"
        [ -e "$FILE" ] && touch "$FLAG"
    done    
}

function build_pip_requirements() {
    echo "# START Global requirements from $PIP_REQUIREMENTS"
    cat "$PIP_REQUIREMENTS"
    echo ""
    echo "# END "
    if [ -f "$PIP_LOCAL_REQUIREMENTS" ]; then
        echo ""
        echo "# START local requirements from $PIP_LOCAL_REQUIREMENTS"
        cat "$PIP_LOCAL_REQUIREMENTS"
        echo ""
        echo "# END "        
        echo ""
    else
        cat >>"$PIP_LOCAL_REQUIREMENTS" <<EOF
# put your local requirements here, they will be honored as stated here.

EOF
    fi
}

function pvenv() {
    ARGS=( "${@}")

    PVENV="$( which virtualenv )"
    if [ -z "$PVENV" ]; then
        if "$INTERPRETER" -c 'import venv'; then
            "$INTERPRETER" -m venv "${ARGS[@]}"
        else
            echo "neither virtualenv nor python3 module 'venv' were found"
            exit 1
        fi
    else
        $PVENV -p "$INTERPRETER" "${ARGS[@]}"
    fi
}

function _runsible_complete_bash() {
    BIT="$2"
    FLAG="$3"

    if [ "$FLAG" == "-p" ]; then
        for CANDIDATE in "$MYPATH/playbooks/"*.yml; do
            PBNAME="$( basename "$CANDIDATE" .yml )"
            if [[ "$PBNAME" == "$BIT"* ]]; then
                COMPREPLY+=("$PBNAME")
            fi
        done
    fi
    if [ "$FLAG" == '-t' ]; then
        if [[ "$BIT" == */* ]]; then
            # role mode
            ROLEBIT="${BIT##*/}"
            HOSTBIT="${BIT%%/*}"
            RBIT="${ROLEBIT##*,}"
            if [[ "$ROLEBIT" == *,* ]]; then
                LBIT="${ROLEBIT%%,"$RBIT"},"
            else
                LBIT=""
            fi
            for ROLE_DIR in "$MYPATH/roles/"*; do
                ROLE="$( basename "$ROLE_DIR" )"
                [ -e "$ROLE_DIR/tasks/main.yml" ] || continue

                if [[ "$ROLE" == "$RBIT"* ]]; then 
                    COMPREPLY+=( "$HOSTBIT/$LBIT$ROLE" )
                fi
            done

        else
            # hostname mode
            # only match the last bit
            RBIT="${BIT##*,}"
            if [[ "$BIT" == *,* ]]; then
                LBIT="${BIT%%,"$RBIT"},"
            else
                LBIT=""
            fi
            while read -r NAME; do
                if [[ "$NAME" == "$RBIT"* ]]; then 
                    COMPREPLY+=( "$LBIT$NAME/" )
                fi
            done <<<"$(  grep -e '.:[[:space:]]*\(null\)\?$' "$MYPATH"/hosts | grep -v -e '__' -e '^[[:space:]]*\(#.*\)$' -e '\(children\|hosts\|vars\):' | sed -e 's/^[[:space:]]*//' -e 's/:.*//' | sort -u)"
        fi
    fi
}

if [ "$CMD_INVOKED" == "runsible_complete_bash" ] || [ "$CMD_INVOKED" == "-bash" ]; then
    complete -F _runsible_complete_bash runsible
    complete -F _runsible_complete_bash runsible.sh
    return 0
fi

mkdir -p "${MYPATH}/playbooks/tasks/"
touch "${MYPATH}/playbooks/tasks/fact_groups.yml"

LOCK_MODE=""
LOCK_EXIT=253
LOCK_GLOBAL=""

VENV_PATH="${MYPATH}/${VENV}/"

ANSIBLE_VERSION_CANARIES=(
    "$VENV_PATH/bin/ansible"
)

TMP_INCLUDE=$( mktemp )
[ -f "$RUNSIBLE_CONF" ] || { 
    cp "$MYPATH/runsible.example.yml" "$RUNSIBLE_CONF"
    echo "Created $RUNSIBLE_CONF with defaults"
}
if "$MYPATH/helpers/conf_to_env.py" >"$TMP_INCLUDE"; then
    source "$TMP_INCLUDE"
    if [ "$MYPATH" != "$PYTHON_MYPATH" ]; then
        echo "Python found another path as bash."
        echo "Something is amiss:"
        echo "  - Python: $PYTHON_MYPATH"
        echo "  - Bash:   $MYPATH"
    fi
else
    echo "Error reading and finding config file 'runsible.yml'"
    exit 1
fi
rm "$TMP_INCLUDE" 2>/dev/null 

PLAYBOOKS=()
ANS_ARGS=()
QUIET=""



function check_requirement() {
    REQ="$1"

    LOC="$( which "$REQ")"

    if [ -z "$LOC" ]; then
        return 1
    else
        return 0
    fi
}

function error_filter() {
    grep -E -i '(fatal|error|failed)' | grep -v "unreachable=0.*failed=0"
}

function highest() {
    OLD="$1"
    NEW="$2"

    [ -z "$OLD" ] && OLD="255"
    [ -z "$NEW" ] && NEW="255"
    
    if [ "$OLD" -gt "$NEW" ]; then
        echo "$OLD"
    else
        echo "$NEW"
    fi
}

function mkrole() {
    ROLE="$1"
    [ -z "$ROLE" ] && return 1
    ROLEDIR="$MYPATH/roles/$ROLE"

    [ -d "$ROLEDIR" ] && {
        echo "Role '$ROLE' exists. Not doing anything."
        return 2
    }

    echo "Creating role skeleton in '$ROLEDIR'..."
    for subdir in defaults tasks handlers files templates; do
        mkdir -pv "$ROLEDIR/$subdir"
    done

    for subdir in defaults tasks handlers; do
        touch "$ROLEDIR/$subdir/main.yml"
    done

    echo ""
    return 0
}

function cache_output() {
    FOLD=800
    TMPFILE=$( mktemp )
    RETFILE=$( mktemp )
    if [ -n "$TMPFILE" ] || [ -n "$RETFILE" ]; then
        ( "$@"; echo "$?" >"$RETFILE" ) 2>&1 | tee -a "$TMPFILE" >/dev/null
        RET=$(cat "$RETFILE")
        if [ "$RET" != "0" ]; then
            echo "Command returned with an error code != 0:"
            echo ""
            echo "CMD:  '$*'"
            echo "RET:   $RET"
            wc "$TMPFILE" | while read -r lines _ bytes _; do
                echo "BYTES: $bytes"
                echo "LINES: $lines"
            done

            echo ""
            echo ""

            echo "---- begin error lines (filtered) - $FOLD characters ----"
            error_filter <"$TMPFILE" | fold -w "$FOLD" -b -s
            echo "---- end error lines ----"
            echo ""
            echo ""
            echo "---- begin output (stdout/stderr mixed) - $FOLD characters ----"
            fold -w "$FOLD" -b -s <"$TMPFILE"
            echo "---- end output ----"
        fi

        [ -f "$TMPFILE" ] && rm "$TMPFILE"
        [ -f "$RETFILE" ] && rm "$RETFILE"

        return "$RET"
    else
        echo "Error creating tempfile, not executing '$*'"
        return 1
    fi
}

function find_facts_path() {
    CONFIG="${MYPATH}/ansible.cfg"

    if [ -z "$ANSIBLE_CACHE_PLUGIN_CONNECTION" ]; then 
        FACTS_PATH="$(grep "^ *fact_caching_connection *= *" "${CONFIG}" | sed -e "s/^ *fact_caching_connection *= *//" )"
        FACTS_PATH="${FACTS_PATH/#\~/$HOME}"
        FACTS_PATH="$( realpath "${FACTS_PATH}")"
    else
        FACTS_PATH="$ANSIBLE_CACHE_PLUGIN_CONNECTION"
    fi
    mkdir -p "$FACTS_PATH" &>/dev/null
    [ -d "$FACTS_PATH/.git" ] || git init "$FACTS_PATH" &>/dev/null

    echo "$FACTS_PATH"
}

function commit_facts() {
    MSG="$*"
    FACTS="$(find_facts_path)"
    if [ -d "${FACTS}/.git" ]; then
        GIT_PATH="${FACTS}"
        git -C "$GIT_PATH" add "$GIT_PATH"
        git -C "$GIT_PATH" commit -a -m "$MSG" &>/dev/null
        git -C "$GIT_PATH" remote | grep -q origin &>/dev/null && git -C "$GIT_PATH" push origin &>/dev/null
    fi
}

function commit_log_plays() {
    LOG_REPO="$ANSIBLE_LOG_FOLDER"
    if [ -n "$LOG_REPO" ]; then
        MSG="$*"
        if [ -d "${LOG_REPO}/.git" ]; then
            GIT_PATH="${LOG_REPO}"
            git -C "$GIT_PATH" add "$GIT_PATH"
            git -C "$GIT_PATH" commit -a -m "$MSG" &>/dev/null
            git -C "$GIT_PATH" remote | grep -q origin &>/dev/null && git -C "$GIT_PATH" push origin &>/dev/null
        fi
    fi
}

function abandon_ship() {
    echo "$@"
    exit 1
}

function find_activator() {
    for FILE in "bin/activate.$(basename "$SHELL")" "bin/activate"; do
        FN="$VENV_PATH/$FILE"
        [ -f "$FN" ] && {
            echo "$FN"
            return 0
        }
    done
    return 1
}

function refresh_configs() {
    if any_has_changed "${ANSIBLE_VERSION_CANARIES[@]}"; then
        ansible-config list -t all >"${MYPATH}/ansible.cfg.reference"
        ansible-config init -t all --disabled >"${MYPATH}/ansible.cfg.new"
        flag "${ANSIBLE_VERSION_CANARIES[@]}"
    fi
}

function activate() {
    ensure_venv

    REFPATH="${MYPATH}/helpers/relative_paths.sh"
    if [ -f "${REFPATH}" ]; then 
        # shellcheck source=venv/bin/activate
        source "${REFPATH}"
    else
        abandon_ship "Could not find ansible config reference in '${REFPATH}'"
    fi

    refresh_configs
}

function update_venv() {
    OLDTMP="$( mktemp )"
    NEWTMP="$( mktemp )"
    pip freeze >"$OLDTMP"


    echo "Upgrading pip..."
    pip install -U pip
    echo ""
    echo "Packages:"
    echo ""
    sed -e 's/^/  /' < <( build_pip_requirements )
    echo ""
    echo ""
    echo "Calling pip to update installed modules"
    echo ""
    pip install -U -r <( build_pip_requirements )
    echo "" 
    
    pip freeze >"$NEWTMP"

    DIFF="$( diff -U0 "$OLDTMP" "$NEWTMP" | grep -E -v -- "^(\+\+\+|---)" | grep "^[-+]" )"

    if [ -n "$DIFF" ]; then
        echo "Changed packages:"
        echo "-----------------"
        echo "$DIFF"
        echo "-----------------"
    fi

    rm "$OLDTMP"
    rm "$NEWTMP"

    echo ""
    echo "Updating Galaxy Requirements"
    echo ""
    ensure_galaxy_requirements 'force'

    refresh_configs
}

function ensure_galaxy_requirements() {
    EXTRA=()
    FORCE="$1"
    [ -n "$FORCE" ] && EXTRA+=( "--force" )

    FLAGS=()

    # global requirements
    if [ -n "$FORCE" ] || any_has_changed "$GALAXY_REQUIREMENTS" "$RUNSIBLE_CONF"; then
        echo "Installing global requirements"
        ansible-galaxy install "${EXTRA[@]}" -r "$GALAXY_REQUIREMENTS"
        RC=$?
        if [ "$RC" -gt 0 ]; then
            return "$RC"
        else
            FLAGS+=( "$GALAXY_REQUIREMENTS" "$RUNSIBLE_CONF" )
        fi
    fi


    if [ ! -f "$GALAXY_LOCAL_REQUIREMENTS" ]; then
        cat >"$GALAXY_LOCAL_REQUIREMENTS" <<EOF
# your local ansible-galaxy requirements.
# 
# please make sure to use the combined format for roles and collections:
roles:

collections:

# EOF
EOF
    else
        if [ -n "$FORCE" ] || any_has_changed "$GALAXY_LOCAL_REQUIREMENTS" "$RUNSIBLE_CONF"; then
            echo "Installing local requirements"
            ansible-galaxy install "${EXTRA[@]}" -r "$GALAXY_LOCAL_REQUIREMENTS"
            RC=$?
            if [ "$RC" -gt 0 ]; then
                return "$RC"
            else
                FLAGS+=( "$GALAXY_LOCAL_REQUIREMENTS" "$RUNSIBLE_CONF" )
            fi
        fi
    fi
    flag "${FLAGS[@]}"
}

function ensure_pip3() {
    pip3 -V | grep -q "python 3"
}

function ensure_venv() {
    ACTIVATOR="$( find_activator )"

    if [ -z "${ACTIVATOR}" ]; then
        pvenv "${VENV_PATH}"
    fi
    (
        source "$( find_activator )" || abandon_ship "Something went wrong when creating venv '${VENV_PATH}'"
        if "${MYPATH}/helpers/check_requirements.py" --requirements <( build_pip_requirements ); then
            true
            # requirements are satisfied
        else
            # shellcheck source=venv/bin/activate
            if ensure_pip3; then
                pip3 install -r <( build_pip_requirements ) || abandon_ship "Something went wrong when installing modules"
            else
                abandon_ship "venv in '${VENV_PATH} is not python3.'"
            fi
        fi
        ensure_galaxy_requirements ""
    )
    for REQUIRED_FILE in "${VENV_REQUIREMENTS[@]}"; do
        if [ ! -f "${VENV_PATH}/$REQUIRED_FILE" ]; then
            abandon_ship "failed to construct meaningful venv. '$REQUIRED_FILE' is missing from '$VENV_PATH'."
        fi
    done

    # shellcheck source=venv/bin/activate
    source "$( find_activator )" || abandon_ship "Something went wrong when entering venv '${VENV_PATH}'"

}


function upload_mode() {
    echo "upload mode"
    cd "$MYPATH" || abandon_ship "Could not enter directory '${MYPATH}'"
    git add .
    git commit -m "$COMMIT_MSG"
    git push || abandon_ship "Could not push..."
    exit
}

function download_mode() {
    echo "download mode"
    cd "$MYPATH" || abandon_ship "Could not enter directory '${MYPATH}'"
    git pull || { cd "$OLDPWD" || true; abandon_ship "Could not pull..."; }

    if [ "$( id -u )" == "0" ]; then
        echo "Restarting cron"
        systemctl restart cron
    else
        echo "We are not restarting cron, we are not root"
    fi
}

function fact_check_mode() {
    FACT_CHECK="${MYPATH}/helpers/check_fact.py"
    FACTS_DIR="$( find_facts_path )"
    RM_ARGS=""
    MY_ARGS=""
    if [ -n "$QUIET" ]; then
        MY_ARGS="-c"
    else  
        RM_ARGS="-v"
    fi
    ERRORTAG="$(mktemp)"

    find "${FACTS_DIR}" -mindepth 1 -maxdepth 1 -type f | while read -r FILE; do
        "${FACT_CHECK}" -q -f "$FILE" -c "$RUNSIBLE_FACT_CACHE"
        RC=$?
        FN="$( basename "$FILE" )"
        
        case "$RC" in
            0)
                # there is no modification
                # shellcheck disable=SC2030
                [ -n "$QUIET" ] || echo "Fact    OK: $FN"
            ;;
            1)
                echo "Fact ERROR: $FN"
                rm $RM_ARGS "$FILE"
                rm "$ERRORTAG"
            ;;
            2)
                echo "Fact  FAIL: fopen() failed on '$FN'"
            ;;
            *)
                echo "Fact  FAIL: Unknown error while calling fact check for file '$FILE'"
            ;;
        esac
    done

    if [ ! -e "$ERRORTAG" ]; then
        # there is no modification
        # shellcheck disable=SC2031
        [ -n "$QUIET" ] || echo "Found facts with errors, updating facts"
        $MYFULL $MY_ARGS -p update_facts
    else
        rm "$ERRORTAG"
    fi
    commit_facts "Facts after fact check"
}

MISSING_REQ=()
for REQ in "${REQUIREMENTS[@]}"; do
    if ! check_requirement "$REQ"; then
        MISSING_REQ+=( "$REQ" )
    fi
done

if [ "${#MISSING_REQ[@]}" -gt 0 ]; then
    echo "The following required programs were not found in path"
    echo "${MISSING_REQ[*]}"
    exit 1
fi

MKROLES=()
MKROLES_MODE=''
MODE=manual
CLEAN=()
PLAYBOOK_MAP=()
V_COUNT=0

function cleanup() {
    for FN in "${CLEAN[@]}"; do
        rm "$FN"
    done
}

trap cleanup EXIT INT

function usage() {
    cat <<EOF
    $PRODUCT - Version $VERSION
    $RELEASE_DATE by $AUTHOR

    Usage: $SELF ... 

        -L <name>
                Lock all operations after this flag using the given name. Jobs using 
                the same name will immediately fail to run. Use this e.g. to lock cron jobs
                against each other.
                Playbooks, up and download are always locked when this option is used - no matter where.
                Can be used multiple times to lock certain aspects of the platform.
                Works only for locking jobs locally.
        -l 
                before running a playbook, acquire a lock for running it
                playbooks wait $LOCK_WAIT seconds for the lock and exit with $LOCK_EXIT
                if the lock can not be acquired. Existence of a lock file does not 
                necessarily mean the playbook is locked.
        -p <playbook> [-p <playbook>] ... 
                run named ansible playbooks - option can be repeated
                calls playbooks in the order mentioned in the arguments 
        -t <hostspec>/<rolespec> [-t <hostspec>/<rolespec>] ...
                run roles nanes in rolespec (role1,role2,role3) on hosts
                mentioned in hostspec (eg. vpngw*,http*,specific.host.name)
        -r <rolename>
                create directory structure for new role
        -u
                Upload current state of repository to git
        -m  <message>
                Use <message> as commit message
        -d
                Pull from git server before run
        -v
                run Ansible with '-v' - can be repeated
        -c
                cron mode - only output if something went wrong - use before -L or -l
        -C
                Run ansible in Check mode (all other aspects of this script ignore this option)
        -D
                Run ansible in Diff mode and output small changes
        -I
                Clean fact cache and remove hosts no longer in inventory
        -e
                Enter virtualenv and start a shell
        -i <inventory-file>
                Read ansible inventory from this file
        -f
                Set number of forks for Ansible
        -F
                Check fact cache for errors
        -U
                Update all pip modules in the created venv
        -P
                Package mode. Create archive of wrapper in current directory

        -h
                this message.

EOF
if [ -d '/etc/bash_completion.d/' ]; then
    cat <<EOF
        Tab completion for -p and -t is available by
          ln -s '$MYFULL' '/etc/bash_completion.d/runsible_complete_bash'
EOF
fi
if [ -L '/etc/bash_completion.d/runsible_complete_bash' ]; then
cat <<EOF
          (link is installed)
EOF
fi 
}

while getopts "hL:lPf:t:Fvei:uUcICdDsp:m:r:" OPT; do
    case "$OPT" in
        L)
            mkdir -p "$LOCK_PATH"

            LOCK_GLOBAL="$OPTARG"
            LOCK_GLOBAL_FILE="${LOCK_PATH}/namedLock_${LOCK_GLOBAL}.global_lock"
            LOCK_GLOBAL_INFO="${LOCK_PATH}/namedLock_${LOCK_GLOBAL}.global_info"
            
            exec {FD}<>"$LOCK_GLOBAL_FILE"
            LOCK_GLOBAL_FD="$FD"
            [ -z "${CRONIC}" ] && echo "Using global lock file '$LOCK_GLOBAL_FILE' as fd $LOCK_GLOBAL_FD"
            if flock -x -n "$LOCK_GLOBAL_FD"; then
                [ -z "${CRONIC}" ] && echo "Lock acquired..."
                { 
                    echo "# started on $( date )"
                    echo "DATE='$( date )'"
                    echo "STAMP='$( date +%s )'"
                    echo -n "CMD=( '$SELF'"
                    for arg in "$@"; do
                     echo -n " '$arg'"
                    done
                    echo " )"
                    echo "PID='$$'"
                } >"$LOCK_GLOBAL_INFO"
            else
                echo "Error - failed to acquire exclusive lock on '$LOCK_GLOBAL_FILE'"
                echo ""
                PID=''
                STAMP=''
                source <( grep -e "^\(PID\|STAMP\)='[0-9]\+'$"  "$LOCK_GLOBAL_INFO" )
                echo "Process $PID is holding the lock"
                if [ -n "$PID" ] && [ "$PID" -gt 0 ]; then
                    if [ -d "/proc/$PID/" ]; then
                        echo "Process $PID is alive"
                    else
                        echo "Process $PID is dead but lock is held."
                        echo " -- Please have a look, this should not happen."
                    fi
                fi
                if [ -n "$STAMP" ] && [ "$STAMP" -gt 0 ]; then
                    AGE=$(( $(date +%s) - STAMP ))
                    echo "Process $PID is $AGE seconds old"
                fi
                echo ""
                echo " -- Lock info:"
                cat "$LOCK_GLOBAL_INFO"
                echo " --"
                exit 1
            fi
        ;;
        l)
            LOCK_MODE="yes"
            mkdir -p "$LOCK_PATH"
        ;;
        P)
            TAR_DEST="runsible_$VERSION.tar.gz"
            echo "Package mode - packaging to '$TAR_DEST'"
            if [ -e "$TAR_DEST" ]; then
                echo "Not overwriting existing package '$TAR_DEST'."
            else
                tar -C "${MYPATH}" -czvf "$TAR_DEST" "${RUNSIBLE_TAR_FILES[@]}"
            fi
        ;;
        p)
            PLAYBOOKS+=("${OPTARG}")
        ;;
        t)
            TARGET="${OPTARG%/*}"
            ROLES="${OPTARG##*/}"
            # we can not use bash replaces here
            # shellcheck disable=SC2001
            ROLES="$( sed -e 's/ *, */__SEP__    - /g' <<<"$ROLES" )"
            PBDIR="${MYPATH}/playbooks/"

            TPB="$( mktemp -p "$PBDIR" __TEST_AUTOGEN.XXXXXXXXXXX.yml)"
            CLEAN+=("$TPB")
            sed -e "s#DEFINITION#$OPTARG#" -e "s/TARGET/$TARGET/" -e "s/__placeholder_role/$ROLES/" -e 's/__SEP__/\n/g' "$PBDIR/__TEST.yml" >"$TPB"
            TPB_BASE="$( basename "$TPB" '.yml' )"
            PLAYBOOKS+=("$TPB_BASE")

            PLAYBOOK_MAP+=("$TPB_BASE=====$OPTARG")
        ;;
        r)
            MKROLES_MODE='yes'
            MKROLES+=("${OPTARG}")
        ;;
        m)
            COMMIT_MSG="${OPTARG}"
        ;;
        v)
            V_COUNT="$(( V_COUNT + 1 ))"
        ;;
        C)
            ANS_ARGS+=(-C)
        ;;
        D)
            ANS_ARGS+=(-D)
        ;;
        i)
            ANS_ARGS+=("-i" "$OPTARG")
            INVENTORY="$OPTARG"
        ;;
        c)
            CRONIC="cache_output"
            QUIET="yes"
            MODE="cron"
        ;;
        I)
            if [ -n "${CRONIC}" ]; then
                ${CRONIC} "$SELF" -I
            else 
                FACTS="$(find_facts_path)"
                [ -z "$INVENTORY" ] && INVENTORY="${MYPATH}/hosts"
                echo "Checking facts"
                find "${FACTS}" -maxdepth 1 -type f | while read -r FILE; do
                    HOSTNAME="$(basename "${FILE}")"
                    if grep -v "^ *#" "${INVENTORY}" | grep -v "\[" | grep -q "^ *${HOSTNAME} *:"; then
                        # Host is still in inventory
                        touch "${FILE}"
                    else
                        echo " [facts] stale facts in '${FACTS}/${HOSTNAME}' - cleaning" >&2
                        rm "${FILE}" >&2
                    fi 
                done
                for DIR_FRAGMENT in 'host_vars' 'group_vars'; do
                    if [ -d "${MYPATH}/${DIR_FRAGMENT}" ]; then
                        echo "Checking $DIR_FRAGMENT"
                        find "${MYPATH}/${DIR_FRAGMENT}" -mindepth 1 -maxdepth 1 -type d | while read -r FILE; do
                            HOSTNAME="$(basename "${FILE}")"
                            if grep -v "^ *#" "${INVENTORY}" | grep -v "\[" | grep -q "^ *${HOSTNAME} *:"; then
                                # is still in inventory
                                true
                            else
                                echo " [$DIR_FRAGMENT] possibly stale $DIR_FRAGMENT in '${DIR_FRAGMENT}/${HOSTNAME}' - have a look" >&2
                            fi 
                        done
                    fi
                done
                commit_facts "Facts after inventory fact cleanup"
            fi
        ;;
        e)
            activate
            cd "$MYPATH" || echo "Error entering Ansible path '$MYPATH'"
            export _ANSIBLE_VENV=1
            PS1="\[\033[01;34m\]$INSTANCE\[\033[00m\] \[\033[01;95m\](runsible)\[\033[00m\] \w > " bash --noprofile --norc -i
            exit $?
        ;;
        d)
            DOWNLOAD="yes"
        ;;
        u)
            UPLOAD="yes"
        ;;
        f)
            export ANSIBLE_FORKS="$OPTARG"
        ;;
        F)
            CHECK_FACT="yes"
        ;;
        U)
            echo "PIP install/upgrade mode"
            activate
            ensure_pip3 && update_venv
                
        ;;
        h)
            usage
            exit 0
        ;;
        *)
            usage
            abandon_ship "Invalid argument '$OPT'"
        ;;
    esac
done

# Modes not requiring python
[ -n "$DOWNLOAD" ] && $CRONIC download_mode
[ -n "$UPLOAD" ] && $CRONIC upload_mode

if [ -n "$MKROLES_MODE" ]; then
    for ROLE in "${MKROLES[@]}"; do
        mkrole "$ROLE"
    done
fi

activate

# Modes requiring python
[ -n "$CHECK_FACT" ] && fact_check_mode

logger -t "runsible ($INSTANCE) [$MODE]" "run using YAML config file '$CONFIG_YAML'"
if [ ${#PLAYBOOKS[@]} -gt 0 ]; then
    ERRORS=()
    OK=()
    RUN=()
    TIMES=()
    HIGHEST="0"

    VARG=""
    if [ "$V_COUNT" -gt 0 ]; then
        VARG="-"
        for _ in $( seq 1 "$V_COUNT" ); do 
            VARG="${VARG}v"
        done
    fi

    for PB in "${PLAYBOOKS[@]}"; do
        PBN="$PB"

        LOCK_OVERRIDE=""
        if [ ${#PLAYBOOK_MAP[@]} -gt 0 ]; then
            for MAP in "${PLAYBOOK_MAP[@]}"; do
              ORIG="${MAP%=====*}"
              DEF="${MAP#*=====}"
              if [ "$ORIG" == "$PB" ]; then 
                PBN="${PBN/$ORIG/$DEF}"
                LOCK_OVERRIDE="yes"
              fi
            done
        fi
        
        PBF="${MYPATH}/playbooks/${PB}.yml"

        LOCK_CMD=()
        if [ -n "$LOCK_MODE" ] && [ -z "$LOCK_OVERRIDE" ] ; then
            LOCK="$PBF"
            LOCK_CMD+=( flock ) 
            LOCK_CMD+=( -x ) 
            LOCK_CMD+=( -w "$LOCK_WAIT" )
            LOCK_CMD+=( -E "$LOCK_EXIT" )
            LOCK_CMD+=( "$LOCK" )
            [ -z "${CRONIC}" ] && echo "Waiting max $LOCK_WAIT seconds for lock on '$LOCK'"
        fi
        if [ -n "$LOCK_OVERRIDE" ] && [ -n "$LOCK_MODE" ]; then
            [ -z "${CRONIC}" ] && echo "Warning: can not lock dynamically generated playbook '$PBN'"
        fi


        logger -t "runsible ($INSTANCE) [$MODE]" "Started run with playbook '$PBN' from '$PBF'"
        START="$(date +%s)"
        ${CRONIC} "${LOCK_CMD[@]}" ansible-playbook $VARG "${ANS_ARGS[@]}" --vault-password-file "${MYPATH}/vault_password" "$PBF"
        RET="$?"
        HIGHEST="$( highest "$HIGHEST" "$RET" )"

        if [ -n "$LOCK_MODE" ] && [ "$LOCK_EXIT" == "$RET" ]; then
            echo "Error - Failed to acquire exclusive lock on '$LOCK'"
            RETN="LOCK"
        else
            RETN="$RET"
        fi

        if [ "$RET" != "0" ]; then
            ERRORS+=("$PBN:($RETN)")
        else
            OK+=("$PBN")
        fi

        RUN+=("$PBN")
        END="$(date +%s)"
        DURATION="$(( END - START ))"
        TIMES+=("$DURATION $PBN")
        logger -t "runsible ($INSTANCE) [$MODE]" "finished run with playbook '$PBN' from '$PBF' after $DURATION secs. Return code $RET"

        commit_facts "Facts after runsible ($INSTANCE) [$MODE] finished run with playbook '$PBN' from '$PBF' after $DURATION secs. Return code $RET"
        commit_log_plays "Logs after runsible ($INSTANCE) [$MODE] finished run with playbook '$PBN' from '$PBF' after $DURATION secs. Return code $RET"

    done

    if [ "${#ERRORS[@]}" -gt 0 ] || [ -z "$CRONIC" ]; then
        echo "Playbooks run:         ${RUN[*]}"
        echo "Playbooks ok:          ${OK[*]}"
        echo "Playbooks with errors: ${ERRORS[*]}"
        echo ""
        echo "Runtimes:"
        TOTAL=0
        for STAT in "${TIMES[@]}"; do
            while read -r S_DUR S_PBN; do
                printf '  + %5dsec - %s\n' "$S_DUR" "$S_PBN" 
                TOTAL="$(( TOTAL + S_DUR ))"
            done < <( echo "$STAT" )
        done
        printf '=== %5s    - %s\n' "" "" 
        printf '    %5dsec - %s\n' "$TOTAL" "TOTAL" 

    fi
    exit "$HIGHEST"
fi
