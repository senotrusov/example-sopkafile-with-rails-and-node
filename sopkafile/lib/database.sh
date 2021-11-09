#!/usr/bin/env bash

#  Copyright 2012-2021 Stanislav Senotrusov <stan@senotrusov.com>
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# shellcheck disable=2030,2031

# wrapper script to perform something with db config loaded
database::with-config() {(
  ruby::load-rbenv || fail
  export PGDATABASE; PGDATABASE="$(rails::get-database-config database)" || fail
  "$@"
)}

# write db name to app-env
database::save-config-to-app-env() {
  app-env::write-env database PGDATABASE || fail
}

database::get-database-name() {
  echo "${PGDATABASE}"
}

database::sync-from-remote() {
  # shellcheck disable=SC2034
  local SOPKA_RSYNC_ARGS=(--delete)

  # sync remote db dump from remote
  rsync::sync-from-remote "${APP_DIR}"/current/db/dumps/latest db/dumps || fail
}

database::sync-to-remote() {
  # shellcheck disable=SC2034
  local SOPKA_RSYNC_ARGS=(--delete)
  
  # sync local db dump to remote
  app-release::sync-to-remote db/dumps/latest db/dumps || fail
}

database::restore(){
  # get cpu count
  local cpuCount; cpuCount="$(linux::get-cpu-count)" || fail

  # restore db
  pg_restore \
    --dbname="${PGDATABASE}" \
    --jobs="${cpuCount}" \
    --no-owner \
    db/dumps/latest

  # pg_restore could have errors, we just ignore them
  return 0
}

# TODO: check if that function is in proper environment to do it's work
database::dump-source-database(){
  cd "${APP_DIR}/current" || fail
  
  local tempDir; tempDir="$(mktemp -d db/dumps/latest-XXXXXXXXXX)" || fail

  pg_dump \
    --compress=0 \
    --file="${tempDir}" \
    --format=directory \
    --jobs=1 \
    --quote-all-identifiers \
    --serializable-deferrable || fail
  
  mv db/dumps/latest db/dumps/latest-to-remove || fail
  mv "${tempDir}" db/dumps/latest || fail
  rm -rf db/dumps/latest-to-remove || fail
}
