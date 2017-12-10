create_csr_json() {
    local prefix=$1

    # Load/Edit Vars
    export PKI_CSR_CN=$(hostname -f)
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
    local host=$(get_peers root-ca-config)
    local port=$(get_property root-ca-config "${host}:port")
    local auth_key_base64=$(get_property root-ca-config "${host}:auth_key_base64")

    export PKI_DEFAULT_HOST_PORT=${host}:${port} 
    export PKI_DEFAULT_AUTH_KEY=$(base64_to_hex $auth_key_base64)

    # Render
    envsubst_all PKI_DEFAULT ca-client
}

pki_init() {
    create_csr_json client-csr
    create_ca_client_json

    cfssl info -config ca-client.json | jq -r .certificate > cdhpki-default.crt
    cfssl gencert -config ca-client.json client-csr.json | cfssljson -bare client
}
