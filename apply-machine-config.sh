#!/bin/bash
#
# Apply a MachineConfiguration to a given $ROLE.
# Requires script set-ethernet-features in the same location.
# A backup of the generated MachineConfiguration will be saved to the /tmp/enable-restricted-forwarding
# directory.
#
# Usage: ./apply-machine-config.sh <ROLE> "FEATURES" "EXCLUDE_INTERFACES" "ONLY_INTERFACES"
#
# 2024-04-16, Andreas Karis <akaris@redhat.com>

set -eux

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SCRIPT_NAME="set-ethernet-features"
SCRIPT="${DIR}/${SCRIPT_NAME}"
OUTPUT_DIR="/tmp/enable-restricted-forwarding"

if ! [ -f "${SCRIPT}" ]; then
    echo "Missing dependency, could not find script ${SCRIPT}"
    exit 1
fi

if [ $# -lt 2 ]; then
    echo 'Usage: ./apply-machine-config.sh <ROLE> <FEATURES> <POD_SELECTOR>'
    exit 1
fi

ROLE="${1}"
FEATURES="${2}"
POD_SELECTOR="${3:-}"

mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/${ROLE}.yaml"

cat <<EOF | tee "${OUTPUT_FILE}" | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${ROLE}
  name: 99-${ROLE}-${SCRIPT_NAME}
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(base64 -w0 < "${SCRIPT}")
        filesystem: root
        mode: 0750
        path: /usr/local/bin/${SCRIPT_NAME}
    systemd:
      units:
      - contents: |
          [Service]
          Type=simple
          Environment="FEATURES=${FEATURES}"
          Environment="POD_SELECTOR=${POD_SELECTOR}"
          ExecStart=/usr/local/bin/${SCRIPT_NAME} off
        enabled: false
        name: ${SCRIPT_NAME}.service
      - contents: |
          [Unit]
          Description="Run ${SCRIPT_NAME} every minute"

          [Timer]
          OnBootSec=5min
          Unit=${SCRIPT_NAME}.service
          OnCalendar=*-*-* *:*:00

          [Install]
          WantedBy=timers.target
        enabled: true
        name: ${SCRIPT_NAME}.timer
EOF
echo "Backup saved to ${OUTPUT_FILE}"
