#!/usr/bin/env bash
set -efu -o pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. ${DIR}/common.sh
. ${DIR}/client.sh

move_aux_files() {
    local suffix=envsubst.json
}

root_ca_init() {
    pushd pki-conf
    create_csr_json cdhpki-server-csr
    popd
    cfssl gencert --initca=true pki-conf/cdhpki-server-csr.json | cfssljson -bare ~/ca
}

root_ca_renew() {
    cfssl gencert -renewca -ca ~/ca.pem -ca-key ~/ca-key.pem
}

create_cdhpki_server_json() {
    # Load/Edit Vars
    load_vars PKI cdhpki-server

    # Render
    envsubst_all PKI_ cdhpki-server

    # Clean optional lines
    in=cdhpki-server.json
    grep -v '${PKI_.*}' $in > ${in}.clean && mv ${in}.clean ${in}
}

root_ca_run() {
    create_cdhpki_server_json

    export PKI_DEFAULT_AUTH_KEY=$(base64_to_hex $PKI_DEFAULT_AUTH_KEY_BASE64)
    exec cfssl serve \
           -address 0.0.0.0 \
           -port $PKI_CA_PORT \
           -ca ~/ca.pem \
           -ca-key ~/ca-key.pem \
           -config $CONF_DIR/cdhpki-server.json
}

program=$1
shift
case "$program" in
    root-ca-init)
        root_ca_init "$@"
        ;;
    root-ca-renew)
        root_ca_renew "$@"
        ;;
    root-ca-run)
        root_ca_run "$@"
        ;;
    *)
        echo "Usage control.sh <root-ca-init|root-ca-run> ..."
        ;;
esac
