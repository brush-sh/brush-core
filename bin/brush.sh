#!/usr/bin/env bash

# https://stackoverflow.com/a/28776166/644945
sourced() {
    local sourced=0

    if [[ -n "${BRUSH_SOURCED:-}" ]]; then
        BRUSH_SOURCED=1
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        case $ZSH_EVAL_CONTEXT in *:file) sourced=1 ;; esac
    elif [[ -n "$BASH_VERSION" ]]; then
        (return 0 2>/dev/null) && sourced=1
    else
        case ${0##*/} in sh | -sh | dash | -dash) sourced=1 ;; esac
    fi

    return $sourced
}

import() {
    local import="$1"
    local name="${import%%@*}"
    local version="${import##*@}"
    local install_dir="$BRUSH_DEPS"

    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid version specified during import: $import" >&2
        exit 1
    fi

    local lib="$name@$version"
    local dir="$install_dir/$lib"

    if [[ ! -d "$dir" ]]; then
        echo "Downloading $lib" >&2
        mkdir -p "$dir"
        curl -sL "https://github.com/${name}/archive/refs/tags/${version}.tar.gz" |
            tar -xz -C "$dir" --strip-components=1
    fi

    pushd "$dir" >/dev/null

    for script in *.sh; do
        # shellcheck disable=SC1090
        BRUSH_SOURCED=1 source "$script"
    done

    popd >/dev/null
}

is_version() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

brush_dep_dir() {
    if [[ -n "${BRUSH_DEPS:-}" ]]; then
        echo "$BRUSH_DEPS"
    elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "$(git rev-parse --show-toplevel)/.brush/deps"
    else
        echo "${HOME}/.cache/brush/deps"
    fi
}

bootstrap_brush() {
    local version="$1"

    # force use of strict mode
    set -euo pipefail

    # expose import function
    declare -f import
    echo "export -f import"

    # configure brush deps dir
    echo "export BRUSH_DEPS=\"$(brush_dep_dir)\""

    # import brush itself
    echo "import \"expelledboy/brush@$version\""
}

main() {
    local version="$1"

    if is_version "$1"; then
        bootstrap_brush "$1"
    else
        echo "Usage: brush <version>" >&2
        exit 1
    fi
}

if sourced; then
    echo "Brush is not meant to be sourced, please run it as a script." >&2
    exit 1
else
    main "$@"
fi
