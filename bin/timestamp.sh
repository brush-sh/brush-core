#!/usr/bin/env bash

timestamp() (
    date -u +"%Y-%m-%dT%H:%M:%SZ"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    timestamp
fi
