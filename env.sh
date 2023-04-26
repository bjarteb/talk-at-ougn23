#!/bin/bash


# env-tenant exposes these variables:
# export OCI_CLI_PROFILE=TENANTNAME
# export T=<ocid> tenant
# export C=<ocid> compartment
# export NS=<ocid> namespace
. ~/code/oci/cli/env-tenant.sh
. ~/projects/linux/dotfiles/.ocirc
export VCN_ID=<ocid> - you need to provision your own VCN before any instance can be launced
