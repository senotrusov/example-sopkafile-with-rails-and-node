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
  # perform autoremove, update and upgrade
  apt::autoremove-lazy-update-and-maybe-dist-upgrade || fail

  # install tools to use by the rest of the script
  apt::install-sopka-essential-dependencies || fail

  # install display-if-restart-required dependencies
  apt::install-display-if-restart-required-dependencies || fail

  # install benchmark
  benchmark::install::apt || fail

  # install terminal software
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

  # install build dependencies
  ruby::install-dependencies::apt || fail #!
  apt::install \
    build-essential \
    libssl-dev \
      || fail

  # install servers
  apt::install memcached || fail
  apt::install postgresql postgresql-contrib libpq-dev || fail
  apt::install redis-server || fail
  apt::install letsencrypt nginx || fail

  # configure and run postgresql
  sudo systemctl --quiet --now enable postgresql || fail
  postgresql::create-role-if-not-exists "${APP_USER:-"${USER}"}" WITH CREATEDB LOGIN || fail

  # configure imagemagick
  imagemagick::set-policy::resource width 64KP || fail
  imagemagick::set-policy::resource height 64KP || fail
  imagemagick::set-policy::resource disk 16GiB || fail # ((64 * 1024) * (64 * 1024) * 4) / 1024 / 1024 = 16384

  # python
  python::install-and-update::apt || fail
  apt::install python2 || fail # used by node-sass
}

deploy-base-parts-with-application-privileges(){
  # install nodejs
  nodejs::install::nodenv || fail
  npm install --global yarn || fail
  nodenv rehash || fail

  # install ruby
  ruby::dangerously-append-nodocument-to-gemrc || fail
  ruby::install-without-dependencies::rbenv || fail

  # activate and allow direnv
  shellrc::install-direnv-rc || fail
  direnv allow . || fail
}

# nodejs and ruby packages
install-packages-for-nodejs-and-ruby() {
  nodejs::load-nodenv || fail
  ruby::load-rbenv || fail

  bundle install --retry=6 || fail # TODO: Do I need task::run-with-rubygems-fail-detector here?
  rbenv rehash || fail

  yarn --frozen-lockfile --non-interactive || fail
}

# install rails master key
install-master-key() {
  bitwarden::write-password-to-file-if-not-exists "example project rails master key" "config/master.key" || fail "Unable to get master.key from bitwarden"
}
