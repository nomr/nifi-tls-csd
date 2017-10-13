#!/bin/sh
#
#    Licensed to the Apache Software Foundation (ASF) under one or more
#    contributor license agreements.  See the NOTICE file distributed with
#    this work for additional information regarding copyright ownership.
#    The ASF licenses this file to You under the Apache License, Version 2.0
#    (the "License"); you may not use this file except in compliance with
#    the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# Script structure inspired from Apache Karaf and other Apache projects with similar startup approaches

set -efu -o pipefail

. ${COMMON_SCRIPT}

warn() {
    echo "${PROGNAME}: $*"
}

die() {
    warn "$*"
    exit 1
}

unlimitFD() {
    # Use the maximum available, or set MAX_FD != -1 to use that
    MAX_FD=${MAX_FD:="maximum"}

    # Increase the maximum file descriptors if we can
    MAX_FD_LIMIT=$(ulimit -H -n)
    if [ "${MAX_FD_LIMIT}" != 'unlimited' ]; then
        if [ $? -eq 0 ]; then
            if [ "${MAX_FD}" = "maximum" -o "${MAX_FD}" = "max" ]; then
                # use the system max
                MAX_FD="${MAX_FD_LIMIT}"
            fi

            ulimit -n ${MAX_FD} > /dev/null
            # echo "ulimit -n" `ulimit -n`
            if [ $? -ne 0 ]; then
                warn "Could not set maximum file descriptor limit: ${MAX_FD}"
            fi
        else
            warn "Could not query system maximum file descriptor limit: ${MAX_FD_LIMIT}"
        fi
    fi
}

locate_java8_home() {
    if [ -z "${JAVA_HOME}" ]; then
        BIGTOP_JAVA_MAJOR=8
        locate_java_home
    fi

    JAVA="${JAVA_HOME}/bin/java"
    TOOLS_JAR=""

    # if command is env, attempt to add more to the classpath
    if [ "$1" = "env" ]; then
        [ "x${TOOLS_JAR}" =  "x" ] && [ -n "${JAVA_HOME}" ] && TOOLS_JAR=$(find -H "${JAVA_HOME}" -name "tools.jar")
        [ "x${TOOLS_JAR}" =  "x" ] && [ -n "${JAVA_HOME}" ] && TOOLS_JAR=$(find -H "${JAVA_HOME}" -name "classes.jar")
        if [ "x${TOOLS_JAR}" =  "x" ]; then
             warn "Could not locate tools.jar or classes.jar. Please set manually to avail all command features."
        fi
    fi
}

#TODO: replace with sed
insert_if_not_exists() {
    LINE=$1
    FILE=$2
    if ! grep -c "${LINE}" ${FILE} > /dev/null; then
        echo "${LINE}" >> ${FILE}
    fi
}

close_xml_file() {
    XML_TAG=$1
    FILE=$2

    if [ ! -e $FILE ]; then
        return 0
    elif ! tail ${FILE} | grep -c "^</${XML_TAG}>$" > /dev/null; then
        echo "</${XML_TAG}>" >> ${FILE}
    fi
}


init() {
    # Unlimit the number of file descriptors if possible
    unlimitFD

    # NiFi 1.4.0 was compiled with 1.8.0
    locate_java8_home $1

    # Init configuration files
    init_bootstrap
    init_logback_xml
 
    # close aux generated config files
    close_xml_file "services" bootstrap-notification-services.xml
    close_xml_file "loginIdentityProviders" login-identity-providers.xml

    [ -e 'state-management.xml' ] || create_state_management_xml
    [ -e 'authorizers.xml' ] || create_authorizers_xml
}

create_authorizers_xml() {
    merge=aux/merge.xslt
    
    # Transform all hadoop_xml files
    xslt=aux/authorizers.xslt
    for h_xml in `find . -type f -name 'authorizers-*.hadoop_xml'`; do
        local in=${h_xml}
        local out=${h_xml//hadoop_xml/xml}
        xsltproc -o ${out} ${xslt} ${in}
        rm -f ${in}
    done

    # Close all all safety-valve files
    for sv_xml in `find . -type f -name 'authorizers-*safety-valve.xml'`; do
        close_xml_file "authorizers" ${sv_xml}
    done

     
    # Merge with User Group Providers
    prefix=authorizers-user-group-provider
    in_a=${prefix}-file.xml
    in_b=${prefix}-safety-valve.xml
    out=${prefix}.xml
    xsltproc -o ${out} \
             --param with "'${in_b}'" \
             --param dontmerge "'userGroupProvider'" \
             ${merge} ${in_a}
    rm -f ${in_a} ${in_b}

    # Merge with Access Policy Providers
    prefix=authorizers-access-policy-provider
    in_a=${out}
    in_b=${prefix}-file.xml
    out=${prefix}-1.xml
    xsltproc -o ${out} \
             --param with "'${in_b}'" \
             ${merge} ${in_a}
    rm -f ${in_a} ${in_b}

    in_a=${out}
    in_b=${prefix}-safety-valve.xml
    out=${prefix}.xml
    xsltproc -o ${out} \
             --param with "'${in_b}'" \
             --param dontmerge "'accessPolicyProvider'" \
             ${merge} ${in_a}
    rm -f ${in_a} ${in_b}

    # Merge with Authorizers
    prefix=authorizers-authorizer
    in_a=${out}
    in_b=${prefix}-managed.xml
    out=${prefix}-1.xml
    xsltproc -o ${out} \
             --param with "'${in_b}'" \
             ${merge} ${in_a}
    rm -f ${in_a} ${in_b}
 
    in_a=${out}
    in_b=${prefix}-safety-valve.xml
    out=authorizer.xml
    xsltproc -o ${out} \
             --param with "'${in_b}'" \
             --param dontmerge "'authorizer'" \
             ${merge} ${in_a}
    rm -f ${in_a} ${in_b}
}

create_state_management_xml() {

    xsltproc -o state-management-local-provider.xml aux/state-management.xsl state-management-local-provider.hadoop_xml \
        && rm -f state-management-local-provider.hadoop_xml
    xsltproc -o state-management-zk-provider.xml aux/state-management.xsl state-management-zk-provider.hadoop_xml \
        && rm -f state-management-zk-provider.hadoop_xml
    close_xml_file "stateManagement" state-management-safety-valve.xml

    xsltproc -o state-management-local-zk-providers.xml --param with "'state-management-zk-provider.xml'" aux/merge.xslt state-management-local-provider.xml  \
        && rm -f state-management-{local,zk}-provider.xml
    xsltproc -o state-management.xml --param with "'state-management-safety-valve.xml'" aux/merge.xslt state-management-local-zk-providers.xml \
        && rm -f state-management-local-zk-providers.xml state-management-safety-valve.xml
}

init_bootstrap() {
    BOOTSTRAP_CONF="${CONF_DIR}/bootstrap.conf";
    BOOTSTRAP_LIBS=`find "${CDH_NIFI_HOME}/lib/bootstrap" -maxdepth 1 -name '*.jar' | tr "\n" ":"`
    #BOOTSTRAP_LIBS="${CDH_NIFI_HOME}/lib/bootstrap/*"

    BOOTSTRAP_CLASSPATH="${CONF_DIR}:${BOOTSTRAP_LIBS}"
    if [ -n "${TOOLS_JAR}" ]; then
        BOOTSTRAP_CLASSPATH="${TOOLS_JAR}:${BOOTSTRAP_CLASSPATH}"
    fi

    #setup directory parameters
    BOOTSTRAP_LOG_PARAMS="-Dorg.apache.nifi.bootstrap.config.log.dir='${NIFI_LOG_DIR}'"
    BOOTSTRAP_PID_PARAMS="-Dorg.apache.nifi.bootstrap.config.pid.dir='${NIFI_PID_DIR}'"
    BOOTSTRAP_CONF_PARAMS="-Dorg.apache.nifi.bootstrap.config.file='${BOOTSTRAP_CONF}'"

    BOOTSTRAP_DIR_PARAMS="${BOOTSTRAP_LOG_PARAMS} ${BOOTSTRAP_PID_PARAMS} ${BOOTSTRAP_CONF_PARAMS}"

    update_bootstrap_conf

    echo
    echo "Java home: ${JAVA_HOME}"
    echo "NiFi home: ${NIFI_HOME}"
    echo
    echo "Bootstrap Config File: ${BOOTSTRAP_CONF}"
    echo
}

update_bootstrap_conf() {
    # Update bootstrap.conf
    insert_if_not_exists "lib.dir=${CDH_NIFI_HOME}/lib" ${BOOTSTRAP_CONF}
    insert_if_not_exists "conf.dir=${CONF_DIR}" ${BOOTSTRAP_CONF}

    # Disable JSR 199 so that we can use JSP's without running a JDK
    insert_if_not_exists "java.arg.1=-Dorg.apache.jasper.compiler.disablejsr199=true" ${BOOTSTRAP_CONF}
    # JVM memory settings
    insert_if_not_exists "java.arg.2=-Xms512m" ${BOOTSTRAP_CONF}
    insert_if_not_exists "java.arg.3=-Xmx512m" ${BOOTSTRAP_CONF}

    # Enable Remote Debugging
    #java.arg.debug=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=8000

    insert_if_not_exists "java.arg.4=-Djava.net.preferIPv4Stack=true" ${BOOTSTRAP_CONF}

    # allowRestrictedHeaders is required for Cluster/Node communications to work properly
    insert_if_not_exists "java.arg.5=-Dsun.net.http.allowRestrictedHeaders=true" ${BOOTSTRAP_CONF}
    insert_if_not_exists "java.arg.6=-Djava.protocol.handler.pkgs=sun.net.www.protocol" ${BOOTSTRAP_CONF}

    # The G1GC is still considered experimental but has proven to be very advantageous in providing great
    # performance without significant "stop-the-world" delays.
    insert_if_not_exists "java.arg.13=-XX:+UseG1GC" ${BOOTSTRAP_CONF}

    #Set headless mode by default
    insert_if_not_exists "java.arg.14=-Djava.awt.headless=true" ${BOOTSTRAP_CONF}

    # Sets the provider of SecureRandom to /dev/urandom to prevent blocking on VMs
    insert_if_not_exists "java.arg.15=-Djava.security.egd=file:/dev/urandom" ${BOOTSTRAP_CONF}
}

init_logback_xml() {
    sed -i 's/<configuration>/<configuration scan="true" scanPeriod="30 seconds">/' logback.xml
}

run() {
    run_nifi_cmd="'${JAVA}' -cp '${BOOTSTRAP_CLASSPATH}' -Xms12m -Xmx24m ${BOOTSTRAP_DIR_PARAMS} org.apache.nifi.bootstrap.RunNiFi $@"

    if [ "$1" = "run" ]; then
      # Use exec to handover PID to RunNiFi java process, instead of foking it as a child process
      run_nifi_cmd="exec ${run_nifi_cmd}"
    fi

    eval "cd ${CONF_DIR} && ${run_nifi_cmd}"
    EXIT_STATUS=$?

    # Wait just a bit (3 secs) to wait for the logging to finish and then echo a new-line.
    # We do this to avoid having logs spewed on the console after running the command and then not giving
    # control back to the user
    sleep 3
    echo
}

main() {
    init "$1"
    run "$@"
}


case "$1" in
    stop|run|status|dump|env)
        main "$@"
        ;;
    *)
        echo "Usage nifi {stop|run|status|dump|env}"
        ;;
esac
