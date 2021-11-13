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

# APP_RELEASE
# APP_USER
# APP_NAME
# RAILS_ENV
# NODE_ENV

units::write-unit-file() {
  local serviceName="$1"
  local execStart="$2"

  local serviceUnitFile="${APP_NAME}-${serviceName}.service"
  local appDir; appDir="$(app-release::get-absolute-app-dir)" || fail

  local defaultPath; defaultPath="$(linux::get-default-path-variable)" || fail
  local nodenvPath; nodenvPath="$(nodenv::path-variable "${APP_USER}")" || fail
  local rbenvPath; rbenvPath="$(rbenv::path-variable "${APP_USER}")" || fail

  # It works, but systemd logs a warning, so I'm not 100% sure that changing the command string is a right way
  # "Current command vanished from the unit file, execution of the command list won't be resumed."
  local appReleasePath="${appDir}/releases/${APP_RELEASE}" # option "a" (with warning)
  # local appReleasePath="${appDir}/current" # option "b" (without warning, but relies on a symlink and could potentially create a race condition somewhere)

  systemd::write-system-unit "${serviceUnitFile}" <<SHELL || fail
[Unit]
Description=${APP_NAME} ${serviceName}

After=local-fs.target remote-fs.target network.target nss-lookup.target time-sync.target

Requires=postgresql.service memcached.service redis-server.service
After=   postgresql.service memcached.service redis-server.service

${requires:+"Requires=${requires}"}
${wants:+"Wants=${wants}"}

[Service]
Type=simple
ExecStart=${appReleasePath}/${execStart}
RestartSec=10ms
RuntimeMaxSec=5d
Restart=always

User=${APP_USER}
WorkingDirectory=${appReleasePath}
SyslogIdentifier=${APP_NAME}-${serviceName}

Environment=PATH=${rbenvPath}:${nodenvPath}:${defaultPath}
Environment=NODE_ENV=${NODE_ENV}
Environment=RAILS_ENV=${RAILS_ENV}
Environment=RAILS_LOG_TO_STDOUT=true

ProtectSystem=full
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true

${serviceLines}

[Install]
WantedBy=multi-user.target
SHELL
}

units::create-service() {
  local serviceName="$1"
  local serviceUnitFile="${APP_NAME}-${serviceName}.service"

  units::write-unit-file "$@" || fail
  systemctl --quiet reenable "${serviceUnitFile}" || fail
}

units::create-resque-service() {
  local serviceLines="Environment=QUEUE=*"
  units::create-service "resque" "bin/rake resque:work" || fail
}

units::create-rails-service() {
  local serviceName="$1"

  local appDir; appDir="$(app-release::get-absolute-app-dir)" || fail

  local socketsDir="${appDir}/sockets"
  local socketPath="${socketsDir}/${serviceName}.socket"

  local socketUnitFile="${APP_NAME}-${serviceName}.socket"
  local serviceUnitFile="${APP_NAME}-${serviceName}.service"

  dir::make-if-not-exists "${socketsDir}" || fail
  chgrp www-data "${appDir}" || fail
  chgrp www-data "${socketsDir}" || fail

  # create a rails service
  local wants="${APP_NAME}-resque.service"
  local requires="${socketUnitFile}"
  local serviceLines="Environment=PUMA_BIND=unix://${socketPath}"

  units::write-unit-file "${serviceName}" "bin/puma" || fail

  # write unit file
  systemd::write-system-unit "${socketUnitFile}" <<SHELL || fail
[Unit]
Description=${APP_NAME} ${serviceName} socket

[Socket]
ListenStream=${socketPath}
SocketUser=${APP_USER}

# The same as in Puma
# NoDelay=true # Only for TCP sockets
ReusePort=true
Backlog=1024

[Install]
WantedBy=sockets.target
SHELL

  systemctl --quiet reenable "${serviceUnitFile}" "${socketUnitFile}" || fail
}

# shellcheck disable=2034
units::all() {
  local appUnits=(
    resque.service
    webserver.service
    webserver.socket
  )
  "$@"
}

units::create-all() {
  units::create-resque-service || fail
  units::create-rails-service webserver || fail
}

app-units::sopka-menu::add-all::remote production::env units::all || fail
app-units::sopka-menu::add-all::remote local-staging::env units::all || fail
