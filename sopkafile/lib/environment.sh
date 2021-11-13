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
  export NODE_ENV=production
  export RAILS_ENV=production

  # export APP_DIR="example-project-main" # if not defined, value of APP_NAME will be used
  export APP_DOMAINS="www.example.com, example.com"
  export APP_NAME=example-project
  export APP_USER=example-user

  local REMOTE_ENV="NODE_ENV RAILS_ENV APP_DOMAINS APP_NAME APP_DIR APP_USER APP_RELEASE"
  local REMOTE_USER="root"

  "$@"
)}

production::env::as-app-user() {
  local REMOTE_UMASK=0027
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
