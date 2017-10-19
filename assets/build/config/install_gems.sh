#!/bin/bash

if [[ -d ${GEM_CACHE_DIR} ]]; then
  mv ${GEM_CACHE_DIR} ${GITLAB_INSTALL_DIR}/vendor/cache
  chown -R ${GITLAB_USER}: ${GITLAB_INSTALL_DIR}/vendor/cache
fi
