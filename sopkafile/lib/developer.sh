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

sopka-menu::add developer::deploy || fail
sopka-menu::add developer::dump-source-database || fail
sopka-menu::add developer::sync-from-source-database || fail

developer::deploy(){
  # cleanup cache
  rm -rf node_modules public/packs/* tmp/cache/* || fail

  # install shellrc loader
  shellrc::install-loader "${HOME}/.bashrc" || fail

  # base parts with root privileges
  deploy-base-parts-with-root-privileges || fail

  # postgresql dictionaries
  postgresql::install-dictionaries db/tsearch_data || fail

  # install rails master key
  install-master-key || fail

  # base parts with app privileges
  deploy-base-parts-with-application-privileges || fail

  # packages
  install-nodejs-and-ruby-packages || fail

  # database
  production::database-source::env database::with-config developer::deploy-database || fail
}

developer::sync-from-source-database(){
  production::database-source::env task::run database::sync-from-remote || fail
}

developer::dump-source-database(){
  production::database-source::env ssh::task database::dump-source-database || fail
}

developer::deploy-database() {
  # save db config to app-env
  database::save-config-to-app-env || fail

  # return if db exists
  if postgresql::is-database-exists; then
    log::notice "Database is already exists, restore skipped"
    return
  fi
  
  # get latest db dump from remote
  task::run database::sync-from-remote || fail

  # create db
  task::run createdb || fail

  # restore db
  task::run database::restore || fail
}
