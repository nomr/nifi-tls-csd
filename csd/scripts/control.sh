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

load_vars() {
    local prefix=$1
    local file=$2.vars
 
    eval $(sed -e 's/ /\\ /g' \
               -e 's/"/\\"/g' \
               -e 's/^/export ${prefix}_/' $file)
}

move_aux_files() {
    local in=aux/ca-csr.envsubst.json
    local out=${CONF_DIR}/root-ca-csr.envsubst.json
    mv_if_exists $in $out
}

create_root_ca_csr_json() {
    load_vars CFSSL root-ca-csr
    move_aux_files
    envsubst_all

    # Clean optional lines
    grep -v '${CFSSL_.*}' root-ca-csr.json > root-ca-csr.json.clean
    mv root-ca-csr.json.clean root-ca-csr.json
}

root_ca_init() {
    create_root_ca_csr_json
    cfssl gencert --initca=true root-ca-csr.json | /opt/cloudera/parcels/CFSSL/bin/cfssljson -bare ~/ca
}

root_ca_run() {
    return 0
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
