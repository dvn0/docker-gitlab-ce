#!/bin/bash

if [[ -x ./bin/compile ]]; then
  echo "Compiling gitlab-shell golang executables..."
  $EXEC_AS_GIT PATH=/tmp/go/bin:$PATH GOROOT=/tmp/go ./bin/compile
  $EXEC_AS_GIT ./bin/install
fi
