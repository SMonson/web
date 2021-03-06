#!/bin/sh
#
# Copyright 2012 Square Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# Runs all specs under the following environments:
#
# * MRI and JRuby
# * LDAP-based and password-based authentication
# * LDAP authentication with and without a bind DN
#rvm
# All specs are run with JIRA and PagerDuty enabled.
#
# Note: This will take a long time, and requires that you have JRuby and MRI
# environments set up appropriately. See the script for details.
#
# Also note: This script temporarily writes changes to the test config files.
# It must be run with a clean `config/environments/test` directory. If it is
# aborted partway through, you will need to clean up the files yourself.

# Change this to test only certain spec files
COMMAND="rspec spec"

TESTDIR="config/environments/test"
AUTHFILE="${TESTDIR}/authentication.yml"
CONCFILE="${TESTDIR}/concurrency.yml"

function reset_config() {
    # JIRA
    cat > ${TESTDIR}/jira.yml <<YAML
---
disabled: false
YAML

    # PagerDuty
    cat > ${TESTDIR}/pagerduty.yml <<YAML
---
disabled: false
YAML

    # Authentication
    cat > ${AUTHFILE} <<YAML
---
strategy: password
password:
  salt: abc123
YAML

    # Mailer
    cat > ${TESTDIR}/mailer.yml <<YAML
---
from: squash@example.com
domain: example.com
default_url_options:
  host: "test.host"
  protocol: http
YAML

    # Concurrency
    cat > ${CONCFILE} <<YAML
---
background_runner: Multithread
multithread:
  priority_threshold: 50
  pool_size: 20
  max_threads: 100
  priority:
    CommentNotificationMailer: 80
    DeployFixMarker: 70
    DeployNotificationMailer: 80
    JiraStatusUpdater: 20
    ObfuscationMapWorker: 60
    OccurrenceNotificationMailer: 80
    OccurrencesWorker: 40
    PagerDutyAcknowledger: 20
    PagerDutyNotifier: 80
    PagerDutyResolver: 20
    ProjectRepoFetcher: 30
    SourceMapWorker: 60
    SymbolicationWorker: 60
YAML
}

##### Cleanliness checks
function check_clean() {
    if [[ `git status --porcelain -- ${TESTDIR}` ]]; then
        echo This script must be run with a clean ${TESTDIR} directory.
        exit 1
    fi
}

##### 1. MRI (password auth)
function run_password() {
    reset_config
    rvm 2.0.0@squash --create exec bundle && ${COMMAND}

    echo
    echo "***** That was MRI with password auth ******"
    echo
}

##### 2. MRI (password auth w/registration disabled)
function run_reg_disabled() {
    reset_config
    cat > ${AUTHFILE} <<YAML
---
strategy: password
password:
  salt: abc123
registration_enabled: false
YAML
    rvm 2.0.0@squash exec bundle && ${COMMAND}

    echo
    echo "***** That was MRI with password auth w/registration disabled ******"
    echo
}

##### 3. JRuby (password auth)
function run_jruby() {
    reset_config
    rvm jruby@squash --create exec bundle && ${COMMAND}

    echo
    echo "***** That was JRuby with password auth ******"
    echo
}

##### 4. LDAP authentication, no bind DN (MRI)
function run_ldap() {
    reset_config
    cat > ${AUTHFILE} <<YAML
---
strategy: ldap
ldap:
  host: my.ldap.server
  port: 389
  ssl: false
  tree_base: cn=users,dc=mycompany,dc=com
  search_key: uid
YAML
    rvm 2.0.0@squash exec bundle && ${COMMAND}

    echo
    echo "***** That was MRI with LDAP auth, no bind DN ******"
    echo
}

##### 5. LDAP authentication, with bind DN (MRI)
function run_ldap_bind_dn() {
    reset_config
    cat > ${AUTHFILE} <<YAML
---
strategy: ldap
ldap:
  host: my.ldap.server
  port: 389
  ssl: false
  tree_base: cn=users,dc=mycompany,dc=com
  search_key: uid
  bind_dn: cn=admins,ou=System,dc=mycompany,dc=com
  bind_password: password123
YAML
    rvm 2.0.0@squash exec bundle && ${COMMAND}

    echo
    echo "***** That was MRI with LDAP auth + bind DN ******"
    echo
}

##### 6. Resque integration (MRI)
function run_resque() {
    reset_config
    cat > ${CONCFILE} <<YAML
---
background_runner: Resque
resque:
  development: "localhost:6379"
  production: "localhost:6379"
  test: "localhost:6379"
  pool:
    squash: 2
YAML
    rvm 2.0.0@squash exec bundle && ${COMMAND}

    echo
    echo "***** That was MRI with Resque ******"
    echo
}

##### 7. MRI 1.9 (password auth)
function run_mri19() {
    reset_config
    rvm 1.9.3@squash --create exec bundle && ${COMMAND}

    echo
    echo "***** That was MRI 1.9 with password auth ******"
    echo
}

##### Reset configuration
function restore() {
    git checkout ${TESTDIR}
    git clean -df -- ${TESTDIR}
}

check_clean

run_password
run_reg_disabled
run_jruby
run_ldap
run_ldap_bind_dn
run_resque
run_mri19

restore
