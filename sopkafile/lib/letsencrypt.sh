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

letsencrypt::certonly() {
  if [ -z "$(ls -A /etc/letsencrypt/accounts)" ]; then
    sudo letsencrypt register \
      --agree-tos \
      --register-unsafely-without-email \
      --non-interactive \
        || softfail || $?
  fi

  sudo letsencrypt certonly \
    --cert-name "${LETSENCRYPT_CERT_NAME:-"${APP_NAME:?}"}" \
    --deploy-hook "systemctl reload nginx.service" \
    --domains "${LETSENCRYPT_DOMAINS:-"${APP_DOMAINS:?}"}" \
    --manual \
    --manual-auth-hook "/root/.sopka/bin/sopka leaseweb::domains::set-acme-challenge /root/.keys/leaseweb.key" \
    --manual-cleanup-hook "/root/.sopka/bin/sopka leaseweb::domains::clear-acme-challenge /root/.keys/leaseweb.key" \
    --manual-public-ip-logging-ok \
    --non-interactive \
    --preferred-challenges=dns \
      || softfail || $?
}
