#!/bin/bash -e

sed -i "s/DEMO [0-9]* */DEMO $RANDOM /g" examples/hello-grpc/cc/server/main.cc
