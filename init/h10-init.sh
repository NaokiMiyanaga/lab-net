#!/usr/bin/env bash
set -euo pipefail
source /init/_common.sh

prepare_ansible_tmp

tail -f /init/start.log
