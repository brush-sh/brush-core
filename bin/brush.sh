#!/usr/bin/env bash

# https://stackoverflow.com/a/28776166/644945
sourced() {
    local sourced=0

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        case $ZSH_EVAL_CONTEXT in *:file) sourced=1 ;; esac
    elif [[ -n "$BASH_VERSION" ]]; then
        (return 0 2>/dev/null) && sourced=1
    else
        case ${0##*/} in sh | -sh | dash | -dash) sourced=1 ;; esac
    fi

    return $sourced
}

import() (
    # strict mode
    set -euo pipefail

    local import="$1"
    local name="${import%%@*}"
    local version="${import##*@}"
    local install_dir=${BRUSH_DEPS:-.brush/deps}

    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid version specified during import: $import" >&2
        exit 1
    fi

    local lib="$name@$version"
    local dir="$install_dir/$lib"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        curl -sL "https://github.com/${name}/archive/refs/tags/${version}.tar.gz" |
            tar -xz -C "$dir" --strip-components=1
    fi

    for file in "$dir"/*.sh; do
        # shellcheck disable=SC1090
        source "$file"
    done
)

is_version() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bootstrap() {
    local version="$1"

    declare -f import

    echo "import \"expelledboy/brush@$1\""
}

main() {
    if is_version "$1"; then
        echo "Bootstraping brush $1" >&2
        bootstrap "$1"
    else
        echo "Usage: brush <version>" >&2
        exit 1
    fi
}

if ! sourced; then
    main "$@"
fi
