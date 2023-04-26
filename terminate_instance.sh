#!/bin/bash
set -euo pipefail

function pause(){
   echo ""
   read -p "$*"
   echo ""
}

INSTANCE_NAME=ougn-amp

INSTANCE_ID=$(oci compute instance list -c $C --display-name "${INSTANCE_NAME}" --query "data[?\"lifecycle-state\"=='RUNNING'].{id:id} |[0].id" --raw-output)
# delete compute instance
oci compute instance terminate --instance-id "${INSTANCE_ID}" --force
