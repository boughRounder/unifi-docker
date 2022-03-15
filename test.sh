#!/bin/bash

declare -a MONGODB_VERSION_SUPPORTED=("4.2" "4.4" "5.0")
printf -v joined '%s,' "${MONGODB_VERSION_SUPPORTED[@]}"

echo "${joined%,}"