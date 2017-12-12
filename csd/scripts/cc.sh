#!/usr/bin/env bash
set -xefu -o pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. $DIR/common.sh

deploy() {
    # Load properties form existing configuration files
    default=$(get_peers cdhpki-servers)
    local port=$(get_property cdhpki-servers "${default}:port")
    export PKI_DEFAULT_HOST_PORT=${default}:${port}

    PKI_AUTH_KEY_BASE64=$(get_property cdhpki-servers "$default:auth_key_base64")
    export PKI_DEFAULT_AUTH_KEY=$(dirname $DEST_PATH)/default.auth_key
    echo -n "$(base64_to_hex $PKI_AUTH_KEY_BASE64)" > $PKI_DEFAULT_AUTH_KEY
    chmod 600 $PKI_DEFAULT_AUTH_KEY
    PKI_DEFAULT_AUTH_KEY=file:${PKI_DEFAULT_AUTH_KEY}

    envsubst_all PKI_DEFAULT

    load_vars PKI_GW gw
    PKI_GW_TRUSTSTORE_PASSWORD=${PKI_GW_TRUSTSTORE_PASSWORD:-changeit}

    cfssl info -config cdhpki-client.json | jq -r .certificate > cdhpki-default.crt
    keytool -import -noprompt  \
        -file cdhpki-default.crt \
        -alias cdhpki-default \
        -keystore truststore.jks \
        -storepass "${PKI_GW_TRUSTSTORE_PASSWORD}"

    if [ ! -z ${PKI_GW_TRUSTSTORE_LOCATION+x} ]; then
        if [ -f ${PKI_GW_TRUSTSTORE_LOCATION} ]; then
            keytool -delete -noprompt \
                -alias cdhpki-default \
                -keystore "${PKI_GW_TRUSTSTORE_LOCATION}" \
                -storepass "${PKI_GW_TRUSTSTORE_PASSWORD}"
        fi
        keytool -import -noprompt \
            -file cdhpki-default.crt \
            -alias cdhpki-default \
            -keystore "${PKI_GW_TRUSTSTORE_LOCATION}" \
            -storepass "${PKI_GW_TRUSTSTORE_PASSWORD}"
    fi

    anchors_dir=/etc/pki/ca-trust/source/anchors
    if [ ${PKI_GW_UPDATE_CA_TRUST} == "true" ]; then
        cp cdhpki-default.crt ${anchors_dir}
    else
        rm -f ${anchors_dir}/cdhpki-default.crt
    fi
    update-ca-trust

    rm -f gw.vars
    rm -f cdhpki-servers.pvars
}

case "$1" in
    deploy)
        deploy $@
        exit 0
        ;;
    *)
        echo "Usage cc {deploy}"
        ;;
esac
