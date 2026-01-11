#!/bin/sh
echo -ne '\033c\033]0;SentinelPrototype\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/SentinelServer.x86_64" "$@"
