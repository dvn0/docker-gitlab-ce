#!/bin/bash

if [[ -x ./bin/compile ]]; then
  echo "Compiling gitlab-shell golang executables..."
  exec_as_git PATH=/tmp/go/bin:$PATH GOROOT=/tmp/go ./bin/compile
fi
