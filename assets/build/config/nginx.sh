#!/bin/bash
set -e

sed -i \
  -e "s|access_log /var/log/nginx/access.log;|access_log ${GITLAB_LOG_DIR}/nginx/access.log;|" \
  -e "s|error_log /var/log/nginx/error.log;|error_log ${GITLAB_LOG_DIR}/nginx/error.log;|" \
  /etc/nginx/nginx.conf
