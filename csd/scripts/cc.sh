#!/usr/bin/env bash
set -xefu -o pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. $DIR/common.sh

deploy() {
    # Load properties form existing configuration files
    default=$(get_peers ../root-ca-config)
    local port=$(get_property ../root-ca-config "${default}:port")
    export CFSSL_DEFAULT_HOST_PORT=${default}:${port}

    CFSSL_AUTH_DEFAULT_KEY_BASE64=$(get_property ../root-ca-config "$default:CFSSL_AUTH_DEFAULT_KEY_BASE64")
    export CFSSL_DEFAULT_AUTH_KEY=$DEST_PATH/../default.auth_key
    echo -n "$(base64_to_hex $CFSSL_DEFAULT_AUTH_KEY_BASE64)" > $CFSSL_DEFAULT_AUTH_KEY
    chmod 600 $CFSSL_DEFAULT_AUTH_KEY
    CFSSL_DEFAULT_AUTH_KEY=file:${CFSSL_DEFAULT_AUTH_KEY}

    envsubst_all CFSSL_DEFAULT

    load_vars CFSSL_GW gw
    CFSSL_GW_TRUSTSTORE_PASSWORD=${CFSSL_GW_TRUSTSTORE_PASSWORD:-changeit}

    cfssl info -config ca-client.json | jq -r .certificate > cfssl-default.crt
    keytool -import -noprompt  \
        -file cfssl-default.crt \
        -alias cfssl-default \
        -keystore truststore.jks \
        -storepass "${CFSSL_GW_TRUSTSTORE_PASSWORD}"

    if [ ! -z ${CFSSL_GW_TRUSTSTORE_LOCATION+x} ]; then
        if [ -f ${CFSSL_GW_TRUSTSTORE_LOCATION} ]; then
            keytool -delete -noprompt \
                -alias cfssl-default \
                -keystore "${CFSSL_GW_TRUSTSTORE_LOCATION}" \
                -storepass "${CFSSL_GW_TRUSTSTORE_PASSWORD}"
        fi
        keytool -import -noprompt \
            -file cfssl-default.crt \
            -alias cfssl-default \
            -keystore "${CFSSL_GW_TRUSTSTORE_LOCATION}" \
            -storepass "${CFSSL_GW_TRUSTSTORE_PASSWORD}"
    fi

    anchors_dir=/etc/pki/ca-trust/source/anchors
    if [ ${CFSSL_GW_UPDATE_CA_TRUST} == "true" ]; then
        cp cfssl-default.crt ${anchors_dir}
    else
        rm -f ${anchors_dir}/cfssl-default.crt
    fi
    update-ca-trust
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
