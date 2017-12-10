#!/usr/bin/env bash
set -efu -o pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. ${DIR}/common.sh

move_aux_files() {
    local suffix=envsubst.json

    mv_if_exists aux/ca-csr.${suffix} ${CONF_DIR}/root-ca-csr.${suffix}
    mv_if_exists aux/ca-server.${suffix} ${CONF_DIR}/root-ca-config.${suffix}
}

create_root_ca_csr_json() {
    # Load/Edit Vars
    load_vars PKI root-ca-csr

    # Get Aux Files
    move_aux_files

    # Render
    envsubst_all PKI_

    # Clean optional lines
    in=root-ca-csr.json
    grep -v '${PKI_.*}' $in > ${in}.clean && mv ${in}.clean ${in}
}

root_ca_init() {
    create_root_ca_csr_json
    cfssl gencert --initca=true root-ca-csr.json | cfssljson -bare ~/ca
}

create_root_ca_config_json() {
    load_vars PKI root-ca-config
    move_aux_files
    envsubst_all PKI_

    # Clean optional lines
    in=root-ca-config.json
    grep -v '${PKI_.*}' $in > ${in}.clean && mv ${in}.clean ${in}
}

root_ca_run() {
    create_root_ca_config_json

    export PKI_AUTH_DEFAULT_KEY_HEX=$(base64_to_hex $PKI_AUTH_DEFAULT_KEY_BASE64)
    exec cfssl serve \
           -address 0.0.0.0 \
           -port $PKI_CA_PORT \
           -ca ~/ca.pem \
           -ca-key ~/ca-key.pem \
           -config $CONF_DIR/root-ca-config.json
}

program=$1
shift
case "$program" in
    root-ca-init)
        root_ca_init "$@"
        ;;
    root-ca-run)
        root_ca_run "$@"
        ;;
    *)
        echo "Usage control.sh <root-ca-init|root-ca-run> ..."
        ;;
esac
