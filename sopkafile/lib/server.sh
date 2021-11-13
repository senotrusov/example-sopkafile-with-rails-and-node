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

# deploy
sopka-menu::add local-staging::env server::deploy || fail
sopka-menu::add production::env server::deploy || fail

server::deploy() {
  export APP_RELEASE

  # base part with root privileges
  ssh::task-with-install-filter deploy-base-parts-with-root-privileges || fail

  # postgresql dictionaries
  ssh::task-with-remote-temp-copy db/tsearch_data postgresql::install-dictionaries || fail

  # deploy-secrets
  server::deploy-secrets || fail

  # server part with root privileges
  ssh::task-with-install-filter server::deploy-parts-with-root-privileges || fail

  # server part with application privileges
  production::env::as-app-user ssh::task-with-install-filter server::deploy-parts-with-application-privileges || fail

  # create new release
  production::env::as-app-user server::create-application-release || fail

  # deploy within release dir
  production::env::as-app-user app-release::with-release-remote-dir server::deploy-within-application-release || fail

  # create or update nginx config
  SOPKA_RSYNC_DELETE_AND_BACKUP=true task::run rsync::sync-to-remote sopkafile/nginx/ /etc/nginx || fail
  ssh::task server::create-nginx-directories || fail

  # relink and restart
  ssh::task server::switch-to-next-application-version || fail

  # cleanup legacy releases
  production::env::as-app-user ssh::task app-release::cleanup || fail
}

server::deploy-secrets() {(
  # install rails master key
  install-master-key || fail

  # make ~/.keys
  ssh::task dir::make-if-not-exists-and-set-permissions ".keys" 700 || fail

  # install leaseweb api key
  bitwarden::use password "example project leaseweb api key" bitwarden::remote-file ".keys/leaseweb.key" || fail
)}

server::deploy-parts-with-root-privileges() {
  # timezone & locale
  linux::set-timezone UTC || fail
  linux::set-locale en_US.UTF-8 || fail

  # sshd
  sshd::disable-password-authentication || fail
  sudo systemctl reload ssh || fail

  # add app user
  linux::add-user "${APP_USER}" || fail
  linux::assign-user-to-group "${APP_USER}" www-data || fail
  ssh::copy-authorized-keys-to-user "${APP_USER}" || fail
  
  # enable systemd user instance without the need for the user to login
  sudo loginctl enable-linger "${APP_USER}" || fail

  # install sopka for use in letsencrypt
  sopka::install-as-repository-clone || fail

  # run letsencrypt
  letsencrypt::certonly || fail
}

server::deploy-parts-with-application-privileges() {
  # shellrc
  shellrc::install-loader ".bash_profile" || fail
}

server::create-application-release() {
  # shellcheck disable=2034
  local SOPKA_TASK_STDERR_FILTER=task::install-filter

  # init dir layout
  ssh::task app-release::init || fail
  ssh::task app-release::change-app-dir-group www-data || fail

  # push local repo
  task::run app-release::push-local-repo-to-remote || fail

  # make release dir
  APP_RELEASE="$(ssh::call app-release::make-with-group www-data)" || fail 

  # clone to that release dir
  ssh::task app-release::clone || fail

  # put rails master key
  app-release::sync-to-remote "config/master.key" || fail

  # link shared files
  ssh::task app-release::link-shared-file db/dumps || fail
}

server::deploy-within-application-release() {
  # base parts with app privileges
  ssh::task deploy-base-parts-with-application-privileges || fail

  # packages
  ssh::task server::set-production-mode-for-ruby-packages || fail
  ssh::task install-packages-for-nodejs-and-ruby || fail

  # write NODE_ENV & RAILS_ENV values to app-env
  ssh::task app-env::write-env runtime-env NODE_ENV RAILS_ENV || fail

  # database
  server::deploy-database || fail

  # precompile assets
  ssh::task server::precompile-assets || fail

  # allow nginx to see public files
  ssh::task chgrp --recursive www-data public || fail
}

server::deploy-database() {
  # save db config to app-env
  ssh::task database::with-config database::save-config-to-app-env || fail

  # return if db exists
  if ssh::call database::with-config postgresql::is-database-exists; then
    log::notice "Database is already exists, restore skipped"
    return
  fi

  # upload latest db dump to remote  
  task::run database::sync-to-remote || fail

  # create db
  ssh::task database::with-config createdb || fail

  # add unaccent extension to the db
  # In PostgreSQL 13 unaccent would be a trusted extension and this lines would be unnecessary
  local dbName; dbName="$(ssh::call database::with-config database::get-database-name)" || fail
  REMOTE_USER="root" REMOTE_DIR="" ssh::task postgresql::psql-su-run "CREATE EXTENSION unaccent" "${dbName}" || fail

  # restore db
  ssh::task database::with-config database::restore || fail
}

server::set-production-mode-for-ruby-packages() {
  rbenv::load-shellrc || fail

  bundle config --local deployment true || fail
  bundle config --local without "development test" || fail
  bundle config --local path "${HOME}/.cache/ruby-bundle" || fail
}

server::precompile-assets() {
  # load node & rails
  nodenv::load-shellrc || fail
  rbenv::load-shellrc || fail

  # precompile rails assets 
  bin/rake assets:precompile || fail
}

server::create-nginx-directories() {
  dir::sudo-make-if-not-exists /var/cache/nginx/ 750 www-data www-data || fail
  dir::sudo-make-if-not-exists /var/cache/nginx/example-cache 750 www-data www-data || fail
}

server::switch-to-next-application-version() {
  # check for nginx config correctness
  nginx -t -q || fail "nginx config file syntax incorrect"

  # TODO: run database migrations

  # create or update systemd units
  units::create-all || fail

  # link release as current
  app-release::link-as-current || fail

  # restart app servers
  units::all app-units::restart-services || fail

  # reload nginx
  systemctl reload-or-restart nginx.service || fail
}
