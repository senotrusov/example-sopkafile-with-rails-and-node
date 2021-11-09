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

# shellcheck disable=2030,2031,2034

local-staging::env() {(
  local REMOTE_HOST="staging-server.local"
  production::env::template "$@"
)}

production::env() {(
  local REMOTE_HOST="example.com"
  production::env::template "$@"
)}

production::env::template() {(
  # TODO: remove this and just copy .ssh/authorized_keys from root
  export MY_GITHUB_USERNAME="" # import ssh key from this github profile to the ${APP_USER} account

  export NODE_ENV=production
  export RAILS_ENV=production

  export APP_NAME=example-project

  export APP_DIR="${APP_NAME}" # TODO: Should not have nested directories, fix other TODOs to make it happen
  export APP_USER=example-user

  export LETSENCRYPT_CERT_NAME="${APP_NAME}"
  export LETSENCRYPT_DOMAINS="www.example.com, example.com"

  local REMOTE_ENV="NODE_ENV RAILS_ENV APP_NAME APP_DIR APP_USER APP_RELEASE LETSENCRYPT_CERT_NAME LETSENCRYPT_DOMAINS"
  local REMOTE_USER="root"

  "$@"
)}

production::env::as-app-user() {
  local REMOTE_UMASK=27
  local REMOTE_USER="${APP_USER}"

  "$@"
}

production::database-source::env() {
  # a) specify some other database source (e.g. legacy system)
  # local REMOTE_HOST=example.com
  # local REMOTE_USER=example-user

  # b) take db from production server
  production::env production::env::as-app-user "$@"
}
