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

deploy-base-parts-with-root-privileges(){
  # shellcheck disable=2034
  local SOPKA_TASK_STDERR_FILTER=task::install-filter

  # perform autoremove, update and upgrade
  task::run apt::autoremove-lazy-update-and-maybe-dist-upgrade || fail

  # install tools to use by the rest of the script
  task::run apt::install-sopka-essential-dependencies || fail

  # install terminal software
  task::run install-terminal-software || fail

  # install display-if-restart-required dependencies
  task::run apt::install-display-if-restart-required-dependencies || fail

  # install benchmark
  task::run benchmark::install::apt || fail

  # install build dependencies
  task::run install-build-dependencies || fail
  task::run ruby::install-dependencies::apt || fail

  # install and configure servers
  task::run install-and-configure-servers || fail

  # configure imagemagick
  task::run configure-imagemagick || fail

  # programming languages
  task::run install-and-update-python || fail
}

deploy-base-parts-with-application-privileges(){
  # shellcheck disable=2034
  local SOPKA_TASK_STDERR_FILTER=task::install-filter

  # install programming languages
  task::run install-nodejs || fail
  task::run-with-rubygems-fail-detector install-and-update-ruby || fail

  # activate and allow direnv
  shellrc::install-direnv-rc || fail
  direnv allow . || fail
}

# terminal software
install-terminal-software() {
  apt::install \
    apache2-utils \
    awscli \
    certbot \
    direnv \
    git \
    htop \
    imagemagick \
    iperf3 \
    mc \
    ncdu \
    rclone \
    restic \
    ssh-import-id \
    tmux \
      || fail
}

# build dependencies
install-build-dependencies(){
  apt::install \
    build-essential \
    libssl-dev \
      || fail
}

# servers
install-and-configure-servers(){
  apt::install memcached || fail
  apt::install postgresql postgresql-contrib libpq-dev || fail
  apt::install redis-server || fail
  apt::install letsencrypt nginx || fail

  # postgresql
  sudo systemctl --now enable postgresql || fail
  postgresql::create-role-if-not-exists "${APP_USER:-"${USER}"}" WITH CREATEDB LOGIN || fail
}

# imagemagick
configure-imagemagick() {
  imagemagick::set-policy::resource width 64KP || fail
  imagemagick::set-policy::resource height 64KP || fail

  # ((64 * 1024) * (64 * 1024) * 4) / 1024 / 1024 = 16384
  imagemagick::set-policy::resource disk 16GiB || fail
}

# python
install-and-update-python() {
  python::install-and-update::apt || fail
  apt::install python2 || fail # used by node-sass
}

# nodejs
install-nodejs() {
  nodejs::install::nodenv || fail
  npm install --global yarn || fail
  nodenv rehash || fail
}

# ruby
install-and-update-ruby() {
  ruby::dangerously-append-nodocument-to-gemrc || fail
  ruby::install-without-dependencies::rbenv || fail

  # TODO: newer ruby versions already contains bundler, remove it eventually
  gem install bundler --conservative || fail
  rbenv rehash || fail
}

# production mode for ruby packages
set-production-mode-for-ruby-packages() {
  ruby::load-rbenv || fail

  bundle config --local deployment true || fail
  bundle config --local without "development test" || fail
  bundle config --local path "${HOME}/.cache/ruby-bundle" || fail
}

# nodejs and ruby packages
install-nodejs-and-ruby-packages() {
  nodejs::load-nodenv || fail
  ruby::load-rbenv || fail

  bundle install --retry=6 || fail
  rbenv rehash || fail

  yarn --frozen-lockfile --non-interactive || fail
}

# install rails master key
install-master-key() {
  bitwarden::write-password-to-file-if-not-exists "example project rails master key" "config/master.key" || fail "Unable to get master.key from bitwarden"
}
