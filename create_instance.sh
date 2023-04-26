#!/bin/bash
set -euo pipefail

function pause(){
   echo ""
   read -p "$*"
   echo ""
}

################################################################################
# SETTINGS
################################################################################

VCN_NAME=DemoVCN
PUBLIC_KEY_FILENAME=~/.ssh/id_rsa_oci.pub
INSTANCE_NAME=ougn-amp

################################################################################
# NETWORK
################################################################################

# set virtual cloud network id
VCN_ID=$(oci network vcn list -c $C --query "data [?\"display-name\"==\`$VCN_NAME\`] | [0].id" --raw-output)
# set subnet id
SUBNET_ID=$(oci network subnet list -c $C --vcn-id $VCN_ID --query "data[?\"display-name\"=='DemoComputeSubnet']|[0].id" --raw-output)
# set availability domain
AD_NAME=$(oci iam availability-domain list -c $C --query "data[0].name" --raw-output)


################################################################################
# COMPUTE
################################################################################

oci compute shape list -c $C --output table --query "sort_by(data[?contains("shape",'VM.Standard.A1.Flex')],&\"shape\") [*].{ShapeName:shape,Memory:\"memory-in-gbs\",CPUcores:ocpus}"

OPERATING_SYSTEM="Oracle Linux"
OPERATING_SYSTEM_VERSION=9
SHAPE="VM.Standard.A1.Flex"

IMAGE_ID=$(oci compute image list \
  --compartment-id $C \
  --region eu-frankfurt-1 \
  --operating-system "${OPERATING_SYSTEM}" \
  --operating-system-version "${OPERATING_SYSTEM_VERSION}" \
  --shape ${SHAPE} \
  --sort-by TIMECREATED \
  --query 'data[0].id' \
  --raw-output)

echo -e "VCN_NAME: ${VCN_NAME}\nVCN_ID: ${VCN_ID}\nSUBNET_ID: ${SUBNET_ID}\nAD_NAME: ${AD_NAME}\nIMAGE_ID: ${IMAGE_ID}\n"

# create instance
INSTANCE_ID=$(oci compute instance launch \
  --display-name "${INSTANCE_NAME}" \
  --availability-domain "${AD_NAME}" \
  -c $C \
  --subnet-id "${SUBNET_ID}" \
  --image-id "${IMAGE_ID}" \
  --shape "${SHAPE}" \
  --shape-config '{"memory_in_gbs":"8", "ocpus":"1"}' \
  --ssh-authorized-keys-file "${PUBLIC_KEY_FILENAME}" \
  --assign-public-ip true \
  --wait-for-state RUNNING \
  --query 'data.id' \
  --hostname-label "${INSTANCE_NAME}" \
  --is-pv-encryption-in-transit-enabled true \
  --user-data-file ./worker.yaml \
  --raw-output)

# based on INSTANCE_ID, get the IP_ADDRESS
export IP_ADDRESS=$(oci compute instance list-vnics --instance-id "${INSTANCE_ID}" --query "data[0].{public:\"public-ip\"} | public")

# ssh connection string. create connect.sh script for convenience
echo "ssh -i ~/.ssh/id_rsa_oci -oStrictHostKeyChecking=no opc@${IP_ADDRESS}" | tee connect.sh
chmod 755 ./connect.sh
