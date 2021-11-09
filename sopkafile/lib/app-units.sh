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

# APP_DIR
# APP_RELEASE?
# APP_USER
# APP_NAME
# RAILS_ENV

# Production
# ----------
# start/stop
sopka-menu::add production::env ssh::task app-units::disable-and-stop-everything || fail
sopka-menu::add production::env ssh::task app-units::disable-everything || fail
sopka-menu::add production::env ssh::task app-units::full-restart || fail
sopka-menu::add production::env ssh::task app-units::full-stop || fail
sopka-menu::add production::env ssh::task app-units::hot-restart || fail

# status and log
sopka-menu::add production::env ssh::task-verbose app-units::display-statuses || fail
sopka-menu::add "production::env ssh::run app-units::display-logs || true" || fail

# Local staging
# ----------
# start/stop
sopka-menu::add local-staging::env ssh::task app-units::disable-and-stop-everything || fail
sopka-menu::add local-staging::env ssh::task app-units::disable-everything || fail
sopka-menu::add local-staging::env ssh::task app-units::full-restart || fail
sopka-menu::add local-staging::env ssh::task app-units::full-stop || fail
sopka-menu::add local-staging::env ssh::task app-units::hot-restart || fail

# status and log
sopka-menu::add local-staging::env ssh::task-verbose app-units::display-statuses || fail
sopka-menu::add "local-staging::env ssh::run app-units::display-logs || true" || fail

# write units
# ===========

app-units::write-service() {
  local serviceName="$1"
  local execStart="$2"

  # If I choose to use the path with the ${APP_RELEASE} then I got systemd error:
  # "Current command vanished from the unit file, execution of the command list won't be resumed."
  # it still works, but I'm not sure - is it a right way or not
  # local appReleasePath="/home/${APP_USER}/${APP_DIR}/releases/${APP_RELEASE}"

  local appReleasePath="/home/${APP_USER}/${APP_DIR}/current"

  systemd::write-system-unit "${APP_NAME}-${serviceName}.service" <<SHELL || fail
[Unit]
Description=${APP_NAME} ${serviceName}
Requires=local-fs.target remote-fs.target network.target nss-lookup.target time-sync.target postgresql.service memcached.service redis-server.service ${requires:-}
After=   local-fs.target remote-fs.target network.target nss-lookup.target time-sync.target postgresql.service memcached.service redis-server.service ${after:-}

[Service]
Type=simple
ExecStart=${appReleasePath}/${execStart}
RestartSec=10ms
RuntimeMaxSec=5d
Restart=always

User=${APP_USER}
WorkingDirectory=${appReleasePath}
SyslogIdentifier=${APP_NAME}-${serviceName}

Environment=PATH=/home/${APP_USER}/.rbenv/shims:/home/${APP_USER}/.rbenv/bin:/home/${APP_USER}/.nodenv/shims:/home/${APP_USER}/.nodenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
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

  systemctl --quiet reenable "${APP_NAME}-${serviceName}.service" || fail
}

app-units::write-resque-service() {
  local serviceLines="Environment=QUEUE=*"
  app-units::write-service "resque" "bin/rake resque:work" || fail
}

app-units::write-rails-service() {
  local serviceName="$1"
  
  local socketsDir="/home/${APP_USER}/${APP_DIR}/sockets"
  local socketPath="${socketsDir}/${serviceName}.socket"

  local requires="${APP_NAME}-resque.service ${APP_NAME}-${serviceName}.socket"
  local after="${APP_NAME}-resque.service"
  local serviceLines="Environment=PUMA_BIND=unix://${socketPath}"

  dir::make-if-not-exists "${socketsDir}" || fail

  chgrp www-data "/home/${APP_USER}/${APP_DIR}" || fail # TODO: This will not produce a desirable result if APP_DIR contains nested directories, e.g. "foo/bar"
  chgrp www-data "${socketsDir}" || fail

  app-units::write-service "${serviceName}" "bin/puma" || fail

  systemd::write-system-unit "${APP_NAME}-${serviceName}.socket" <<SHELL || fail
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

  systemctl --quiet reenable "${APP_NAME}-${serviceName}.socket" || fail
}

app-units::write-units() {
  app-units::write-resque-service || fail
  app-units::write-rails-service webserver || fail
}

# start/stop
# ==========

app-units::restart-service() {
  local item serviceList=()
  for item in "$@"; do
    serviceList+=("${APP_NAME}-${item}.service") || fail
  done

  systemctl restart "${serviceList[@]}" || fail
}

app-units::restart-service-and-socket() {
  systemctl restart "${APP_NAME}-$1.socket" "${APP_NAME}-$1.service" || fail
}

app-units::stop-service() {
  systemctl stop "${APP_NAME}-$1.service" || fail
}

app-units::stop-service-and-socket() {
  systemctl stop "${APP_NAME}-$1.socket" "${APP_NAME}-$1.service" || fail
}

app-units::disable-service() {
  systemctl --quiet disable "${APP_NAME}-$1.service" || fail
}

app-units::disable-service-and-socket() {
  systemctl --quiet disable "${APP_NAME}-$1.socket" "${APP_NAME}-$1.service" || fail
}

app-units::disable-and-stop-service() {
  systemctl --quiet disable "${APP_NAME}-$1.service" || fail
  systemctl stop "${APP_NAME}-$1.service" || fail
}

app-units::disable-and-stop-service-and-socket() {
  systemctl --quiet disable "${APP_NAME}-$1.socket" "${APP_NAME}-$1.service" || fail
  systemctl stop "${APP_NAME}-$1.socket" "${APP_NAME}-$1.service" || fail
}

app-units::hot-restart() {
  app-units::restart-service \
    resque \
    webserver \
      || fail
}

app-units::full-restart() {
  app-units::restart-service resque || fail
  app-units::restart-service-and-socket webserver || fail
}

app-units::full-stop() {
  app-units::stop-service resque || fail
  app-units::stop-service-and-socket webserver || fail
}

app-units::disable-everything() {
  app-units::disable-service resque || fail
  app-units::disable-service-and-socket webserver || fail
}

app-units::disable-and-stop-everything() {
  app-units::disable-and-stop-service resque || fail
  app-units::disable-and-stop-service-and-socket webserver || fail
}

# status and log
# ==============

app-units::status() {
  systemctl status "${APP_NAME}-$1" || fail
}

app-units::display-statuses() {
  export SYSTEMD_COLORS=1
  app-units::status resque.service || fail
  app-units::status webserver.service || fail
}

app-units::display-logs() {
  export SYSTEMD_COLORS=1
  journalctl \
    --unit "${APP_NAME}-resque.service" \
    \
    --unit "${APP_NAME}-webserver.service" \
    --unit "${APP_NAME}-webserver.socket" \
    \
  --since yesterday --follow || fail
}
