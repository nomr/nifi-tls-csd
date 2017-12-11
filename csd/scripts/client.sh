create_csr_json() {
    local prefix=$1

    # Load/Edit Vars
    export PKI_CSR_CN=${PKI_CSR_CN:-$(hostname -f)}
    load_vars PKI default-csr
    load_vars PKI $prefix

    # Render
    envsubst_all PKI $prefix

    # Clean optional lines
    grep -v '${PKI_.*}' ${prefix}.json > ${prefix}.clean \
      && mv ${prefix}.clean ${prefix}.json
}

create_ca_client_json() {
    # Load/Edit Variables
    local host=$(get_peers cdhpki-servers)
    local port=$(get_property cdhpki-servers "${host}:port")
    local auth_key_base64=$(get_property cdhpki-servers "${host}:auth_key_base64")

    export PKI_DEFAULT_HOST_PORT=${host}:${port} 
    export PKI_DEFAULT_AUTH_KEY=$(base64_to_hex $auth_key_base64)

    # Render
    envsubst_all PKI_DEFAULT cdhpki-client
}

create_truststore() {
    ${CFSSL_HOME}/bin/cfssl info \
      -config pki-conf/cdhpki-client.json \
      | jq -r .certificate > pki-conf/cdhpki-default.crt

    if [ -z ${PKI_TRUSTSTORE_LOCATION+x} ]; then
        return 0
    fi
    PKI_TRUSTSTORE_PASSWORD=${PKI_TRUSTSTORE_PASSWORD:-changeit}

    if [ -f ${PKI_TRUSTSTORE_LOCATION} ]; then
        keytool -delete -noprompt \
                -alias cdhpki-default \
                -keystore "${PKI_TRUSTSTORE_LOCATION}" \
                -storepass:env PKI_TRUSTSTORE_PASSWORD
    fi

    keytool -importcert -noprompt \
        -file pki-conf/cdhpki-default.crt \
        -alias cdhpki-default \
        -keystore "${PKI_TRUSTSTORE_LOCATION}" \
        -storepass:env PKI_TRUSTSTORE_PASSWORD
}

create_keystore() {
    ${CFSSL_HOME}/bin/cfssl gencert \
      -config pki-conf/cdhpki-client.json \
      pki-conf/client-csr.json \
      | ${CFSSL_HOME}/bin/cfssljson -bare pki-conf/client

    if [ -z ${PKI_KEYSTORE_LOCATION+x} ]; then
        return 0
    fi

    openssl pkcs12 -export \
        -in pki-conf/client.pem \
        -inkey pki-conf/client-key.pem \
        -CAfile pki-conf/cdhpki-default.crt \
        -caname cdhpki-default \
        -out ${PKI_KEYSTORE_LOCATION%.jks}.p12 \
        -passout env:PKI_KEYSTORE_PASSWORD \
        -name client

    keytool -importkeystore \
        -srckeystore ${PKI_KEYSTORE_LOCATION%.jks}.p12 \
        -srcstoretype PKCS12 \
        -srcstorepass:env PKI_KEYSTORE_PASSWORD \
        -srckeypass:env PKI_KEYSTORE_PASSWORD \
        -srcalias client \
        -destkeystore ${PKI_KEYSTORE_LOCATION} \
        -deststoretype JKS \
        -deststorepass:env PKI_KEYSTORE_PASSWORD \
        -destkeypass:env PKI_KEYSTORE_PASSWORD \
        -destalias client \
        -noprompt
}

pki_get_default_subject_suffix() {
    pushd pki-conf 1>&2
    load_vars PKI default-csr
    popd 1>&2

    [ ! -z ${PKI_CA_O+x} ] && echo -n ", O=${PKI_CA_O}"
    [ ! -z ${PKI_CA_L+x} ] && echo -n ", L=${PKI_CA_L}"
    [ ! -z ${PKI_CA_ST+x} ] && echo -n ", ST=${PKI_CA_ST}"
    [ ! -z ${PKI_CA_C+x} ] && echo -n ", C=${PKI_CA_C}"

    echo ""
}

pki_init() {
    pushd pki-conf 1>&2
    create_ca_client_json
    create_csr_json client-csr
    popd 1>&2

    create_truststore
    create_keystore
}
