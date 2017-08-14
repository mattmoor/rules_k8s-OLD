#!/bin/bash -e

sed -i "s/DEMO *[a-z0-9_-]* */DEMO$1 /g" examples/hello-grpc/cc/server/main.cc
