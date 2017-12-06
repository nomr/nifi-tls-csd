#!/usr/bin/env bash

set -efu -o pipefail

. ${COMMON_SCRIPT}

export PATH=$CFSSL_HOME/bin:$PATH

append_and_delete() {
    local in=$1
    local out=$2
    if [ -e $in ]; then
      cat $in >> $out
      rm -f $in
    fi
}

mv_if_exists() {
    if [ -e $1 ]; then
      mv $1 $2
    fi
}

get_property() {
    local file=$1
    local key=$2
    local line=$(grep "$key=" ${file}.properties | tail -1)
    echo "${line/$key=/}"
}

envsubst_all() {
    local shell_format="\$CONF_DIR,\$ZK_QUORUM"
    for i in ${!CFSSL_*}; do
        shell_format="${shell_format},\$$i"
    done

    for i in $(find . -maxdepth 1 -type f -name '*.envsubst*'); do
        cat $i | envsubst $shell_format > ${i/\.envsubst/}
        rm -f $i
    done
}

base64_to_hex() {
    base64 -d \
      | od -t x8 \
      | cut -s -d' ' -f2- \
      | sed -e ':a;N;$!ba;s/\n/ /g' -e 's/ //g' <<< $1
}

load_vars() {
    local prefix=$1
    local file=$2.vars

    eval $(sed -e 's/ /\\ /g' \
               -e 's/"/\\"/g' \
               -e 's/^/export ${prefix}_/' $file)
}

move_aux_files() {
    local suffix=envsubst.json

    mv_if_exists aux/ca-csr.${suffix} ${CONF_DIR}/root-ca-csr.${suffix}
    mv_if_exists aux/ca-server.${suffix} ${CONF_DIR}/root-ca-config.${suffix}
}

create_root_ca_csr_json() {
    load_vars CFSSL root-ca-csr
    move_aux_files
    envsubst_all

    # Clean optional lines
    in=root-ca-csr.json
    grep -v '${CFSSL_.*}' $in > ${in}.clean && mv ${in}.clean ${in}
}

root_ca_init() {
    create_root_ca_csr_json
    cfssl gencert --initca=true root-ca-csr.json | /opt/cloudera/parcels/CFSSL/bin/cfssljson -bare ~/ca
}

create_root_ca_config_json() {
    load_vars CFSSL root-ca-config
    move_aux_files
    envsubst_all

    # Clean optional lines
    in=root-ca-config.json
    grep -v '${CFSSL_.*}' $in > ${in}.clean && mv ${in}.clean ${in}
}
root_ca_run() {
    create_root_ca_config_json

    export CFSSL_AUTH_DEFAULT_KEY_HEX=$(base64_to_hex $CFSSL_AUTH_DEFAULT_KEY_BASE64)
    exec cfssl serve -ca ~/ca.pem -ca-key ~/ca-key.pem -config $CONF_DIR/root-ca-config.json
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
