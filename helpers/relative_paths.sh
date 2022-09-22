#!/bin/bash

MYFULL="$(realpath "$0")"
MYPATH="$(dirname "$MYFULL")"

export ANSIBLE_CONFIG="${MYPATH}"/ansible.cfg
export MYPATH="$MYPATH"