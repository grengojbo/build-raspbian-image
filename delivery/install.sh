#!/bin/bash

machine=`uname -m`
if [ "${machine}" != "armv7l" ]; then
  echo "This script will be executed at mounted raspbian enviroment (armv7l). Current environment is ${machine}."
  exit 1
fi

echo "Now preparing the Poppy environment"
echo ""

chmod +x poppy-installer
su pi -c "./poppy-installer $@"
