#!/bin/bash
set -euo pipefail

FILE="molecule/aio/prepare.yml"

# Check if the "Create fake devices for Ceph" section is commented out
if grep -q '^- name: Create fake devices for Ceph' "$FILE"; then
    echo "#########################################"
    echo "###  ERROR: Ceph fake devices not commented out!  ###"
    echo "#########################################"
    exit 1
elif grep -q '^#- name: Create fake devices for Ceph' "$FILE"; then
    echo "OK: Ceph fake devices block is already commented out."
else
    echo "WARNING: Could not find Ceph fake devices section in $FILE"
    exit 2
fi
