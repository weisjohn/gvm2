# shell_compat.sh
#
# shellcheck shell=bash
# vi: set ft=bash
#
# Shell compatiblity glue functions.
#

# source once and only once!
[[ ${GVM_SHELL_COMPAT:-} -eq 1 ]] && return || readonly GVM_SHELL_COMPAT=1

# load dependencies
dep_load()
{
    local srcd="${BASH_SOURCE[0]}"; srcd="${srcd:-${(%):-%x}}"
    local base="$(builtin cd "$(dirname "${srcd}")" && builtin pwd)"
    local deps; deps=(
        "locale_text.sh"
    )
    for file in "${deps[@]}"
    do
        source "${base}/${file}"
    done

    # zsh fixups
    if [[ -n "${ZSH_VERSION// /}" ]]
    then
        # add bash word split emulation for zsh
        #
        # see: http://zsh.sourceforge.net/FAQ/zshfaq03.html
        #
        setopt shwordsplit

        # force zsh to start arrays at index 0
        setopt KSH_ARRAYS
    fi
}; dep_load; unset -f dep_load &> /dev/null || unset dep_load

# __gvm_is_function()
# /*!
# @abstract Returns whether or not a named function exists in the shell.
# @param func_name Name of the function to check
# @return Returns success (status 0) if the named function exists or failure
#   (status 1).
# */
__gvm_is_function()
{
    local func_name="${1}"

    [[ "x${func_name}" == "x" ]] && return 1

    # using 'declare -f' is the most reliable way for both bash and zsh!
    builtin declare -f "${1}" >/dev/null

    return $?
}

__gvm_callstack()
{
    local index=${1}

    if [[ "x${BASH_VERSION}" != "x" ]]
    then
        echo "${FUNCNAME[index]}"
    elif [[ "x${ZSH_VERSION}" != "x" ]]
    then
        echo "${FUNCNAME[index+1]}"
    else
        echo "unknown caller"
        return 1
    fi

    return 0
}

# __gvm_resolve_path()
# /*!
# @abstract Returns a resolved absolute path
# @discussion Elements of the path will be resolved for dot and tilde chars.
# @param string Path string
# @return Returns string containing path with all elements resolved on success
#   (status 0), otherwise an empty string on failure (status 1).
# @note Also sets global variable RETVAL to the same return value.
# @note Requires shwordsplit and KSH_ARRAYS are enabled (via setopt) for KSH.
# @note Double dot relative references are not supported and will be passed
#   through unmodified.
# */
__gvm_resolve_path() {
    local path_in="${1-$PATH}"
    local path_in_ary; path_in_ary=()
    local path_out=""
    local path_out_ary; path_out_ary=()
    local defaultIFS="$IFS"
    local IFS="$defaultIFS"
    local spaceChar=$' '
    unset RETVAL

    [[ -z "${path_in// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    # convert path into an array of elements, encode spaces
    IFS=':' path_in_ary=( ${path_in//$spaceChar/%2f} ) IFS="$defaultIFS"

    local _path
    for _path in "${path_in_ary[@]}"
    do
        case "${_path}" in
            ".."/* | "."* )
                ;;
            "."/* )
                _path="${PWD}"/"${_path#"./"}"
                ;;
            "."* )
                _path="${PWD}"
                ;;
            "~+"/* )
                _path="${PWD}"/"${_path#"~+/"}"
                ;;
            "~-"/* )
                _path="${OLDPWD}"/"${_path#"~-/"}"
                ;;
            "~"/* )
                _path="${HOME}"/"${_path#"~/"}"
                ;;
            "~"* )
                local __user="${_path%%/*}"
                local __path_home="$(bash -c "echo ${__user}")"
                if [[ "${_path}" == */* ]]
                then
                    _path="${__path_home}"/"${_path#*/}"
                else
                    _path="${__path_home}"
                fi
                unset __path_home user
                ;;
        esac
        path_out_ary+=( "${_path}" )
    done
    unset _path

    # convert path elements array into path string, decode spaces
    IFS=":" path_out="${path_out_ary[*]}" IFS="$defaultIFS"

    RETVAL="${path_out//%2f/$spaceChar}"

    if [[ -z "${RETVAL// /}" ]]
    then
        RETVAL="" && echo "${RETVAL}" && return 1
    fi

    echo "${RETVAL}" && return 0
}

# __gvm_progress()
# /*!
# @abstract Returns a progress message
# @discussion The progress message will be localized if a localization exists.
# @param string Progress message
# @return Returns string containing progress message on success (status 0),
#   otherwise an empty string on failure (status 1).
# @note Also sets global variable RETVAL to the same return value.
# */
__gvm_progress()
{
    local message="${1}"
    local l_message="${message}"
    unset RETVAL

    [[ -z "${message// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    # localize if possible
    __gvm_locale_text_for_key "${message}" > /dev/null
    [[ -n "${RETVAL}" ]] && l_message="${RETVAL}"

    RETVAL="-> ${l_message}"

    echo "${RETVAL}"; return 0
}

# __gvm_prompt_confirm()
# /*!
# @abstract Confirm a user action. Input case insensitive
# @discussion
# Read a simple case-insensitive [y]es or [N]o prompt, where "No" is the default
#   if no answer is entered by the user. If no prompt is provided, the default
#   (localized) prompt will be used.
# @param prompt [optional] Message to precede the confirmation menu
# @return Returns string containing "yes" on success (status 0), otherwise  "no"
#   (status 1).
# @note Also sets global variable RETVAL to the same return value.
# */
__gvm_prompt_confirm()
{
    local prompt="${1}"
    local response
    unset RETVAL

    if [[ -z "${prompt// /}" ]]
    then
        __gvm_locale_text_for_key "are_you_sure_prompt" > /dev/null
        prompt="${RETVAL}"
    fi

    while true
    do
        read -r -n 1 -p "${prompt} ([y]es or [N]o): " response
        __gvm_str_lower "${response}"

        case "${RETVAL}" in
            y|yes)
                RETVAL="yes"; echo "${RETVAL}"
                return 0
                ;;
            n|no)
                RETVAL="no"; echo "${RETVAL}"
                return 1
                ;;
            *)
                ;;
        esac
    done
}

# __gvm_pwd()
# /*!
# @abstract Get the present working directory
# @return Returns directory string on success (status 0), otherwise an empty
#   string on failure (status 1).
# @note Also sets global variable RETVAL to the same return value.
# */
__gvm_pwd()
{
    local pwd=""
    unset RETVAL

    if [[ "x${BASH_VERSION}" != "x" ]]
    then
        printf -v pwd "%s" "$(builtin pwd)"
    elif [[ "x${ZSH_VERSION}" != "x" ]]
    then
        pwd="$(builtin pwd)"
    fi

    [[ -z "${pwd// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    RETVAL="${pwd}"

    echo "${RETVAL}"; return 0
}

# __gvm_rematch()
# /*!
# @abstract Provide a cross-platform regex rematcher.
# @discussion
# This function implements consistent regex rematch functionality for bash and
#   zsh shells. The result is similar to the output expected using the '=~'
#   pattern match operator in bash: matching results will be written to an array
#   stored in the var_name provided or 'GVM_REMATCH' (the default).
#
# Rematch results can be accessed beginning with index 1: GVM_REMATCH[1] and
#   subsequent matches (if any) appear in later indexes. The match at index 1
#   consists of the entire matched string while later matches are related to
#   specified capture groups noted in the regex pattern.
# @param string The string to match against the regex pattern
# @param regex The regex pattern
# @param var_name [optional] The name of the variable into which the resulting
#   rematch array will be set.
# @return Returns success (status 0) if the string matches the regex pattern,
#   otherwise failure (status 1).
# */
__gvm_rematch()
{
    local string="${1}"; shift
    local regex="${1}"; shift
    local var_name="${1:-GVM_REMATCH}"
    local rematch_ary; rematch_ary=()

    [[ ${#string} -eq 0 ]] && return 1
    [[ ${#regex} -eq 0 ]] && return 1

    # perform regex - same on bash and ksh
    [[ "${string}" =~ $regex ]]
    [[ $? -ne 0 ]] && return 1

    # support bash and zsh
    #
    # NOTE: 'setopt KSH_ARRAYS' must be set for zsh to force array indexes to
    # start at 0, like bash.
    #
    if [[ "x${BASH_VERSION}" != "x" ]]
    then
        rematch_ary+=( "${BASH_REMATCH[@]}" )
    elif [[ "x${ZSH_VERSION}" != "x" ]]
    then
        rematch_ary+=( "$MATCH" "${match[@]}" )
    else
        return 1
    fi

    if [[ "${var_name}" != "$" ]]
    then
        # assign to passed var
        eval "${var_name}=( \"\${rematch_ary[@]}\" )"
    fi

    return 0
}

# __gvm_setenv()
# /*!
# @abstract Set an environment variable
# @discussion
# Variable names are uppercased before they are set. Setting an empty value will
#   remove the environment variable.
# @param variable Name of the variable to set
# @param value Value of the variable
# @return Returns success (status 0) or failure (status 1).
# */
__gvm_setenv()
{
    local name="${1}"; shift
    local value="${1}"

    __gvm_str_upper "${name}" > /dev/null
    name="${RETVAL}"

    [[ ${#name} -eq 0 ]] && return 1

    if [[ ${#value} -eq 0 ]]
    then
        unset "${name}"
        # verify var removed or return error
        [[ "x${name}" != "x" ]] && return 1
        # success!
        return 0
    fi

    export "${name}=${value}"

    # value not set?
    [[ "x${name}" == "x" || "${name}" != "${value}" ]] && return 1

    return 0
}

# __gvm_str_lower()
# /*!
# @abstract Convert a string to lowercase
# @param string String to convert
# @return Returns converted string on success (status 0), otherwise an empty
#   string on failure (status 1).
# @note Also sets global variable RETVAL to the same return value.
# */
__gvm_str_lower()
{
    local string="${1}"
    local string_lower=""
    unset RETVAL

    [[ -z "${string// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    if [[ -n "${BASH_VERSION// /}" ]]
    then
        if [[ "${BASH_VERSION:0:1}" -gt 3 ]]
        then
            string_lower="${string,,}"
        else
            string_lower="$(tr '[:upper:]' '[:lower:]' <<< "${string}")"
        fi
    elif [[ -n "${ZSH_VERSION// /}" ]]
    then
        string_lower="${string:l}"
    fi

    [[ -z "${string// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    RETVAL="${string_lower}"

    echo "${RETVAL}"; return 0
}

# __gvm_str_upper()
# /*!
# @abstract Convert a string to uppercase
# @param string String to convert
# @return Returns converted string on success (status 0), otherwise an empty
#   string on failure (status 1).
# @note Also sets global variable RETVAL to the same return value.
# */
__gvm_str_upper()
{
    local string="${1}"
    local string_upper=""
    unset RETVAL

    [[ -z "${string// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    if [[ -n "${BASH_VERSION// /}" ]]
    then
        if [[ "${BASH_VERSION:0:1}" -gt 3 ]]
        then
            string_upper="${string^^}"
        else
            string_upper="$(tr '[:lower:]' '[:upper:]' <<< "${string}")"
        fi
    elif [[ -n "${ZSH_VERSION// /}" ]]
    then
        string_upper="${string:u}"
    fi

    [[ -z "${string// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    RETVAL="${string_upper}"

    echo "${RETVAL}"; return 0
}

# __gvm_str_trim()
# /*!
# @abstract Trim leading and trailing whitespace from a string
# @param string String to trim
# @return Returns converted string on success (status 0), otherwise an empty
#   string on failure (status 1).
# @note Also sets global variable RETVAL to the same return value.
# */
__gvm_str_trim()
{
    local string="${1}"
    local string_trim=""
    local defaultIFS="$IFS"
    local IFS="$defaultIFS"
    unset RETVAL

    [[ -z "${string// /}" ]] && RETVAL="" && echo "${RETVAL}" && return 1

    IFS=$' '
    read -r string_trim <<< "${string}"
    IFS="${defaultIFS}"

    RETVAL="${string_trim}"

    echo "${RETVAL}"; return 0
}
