#!/bin/bash -e

function create() {
   bazel run examples/hello-grpc/cc/server:staging.create
}

function check_msg() {
   bazel build examples/hello-grpc/cc/client

   OUTPUT=$(./bazel-bin/examples/hello-grpc/cc/client/client)
   echo Checking response from service: "${OUTPUT}" matches: "DEMO$1<space>"
   echo "${OUTPUT}" | grep "DEMO$1[ ]"
}

function edit() {
   ./examples/hello-grpc/cc/server/edit.sh "$1"
}

function update() {
   bazel run examples/hello-grpc/cc/server:staging.replace
}

function delete() {
   bazel run examples/hello-grpc/cc/server:staging.delete
}


create
trap "delete" EXIT
sleep 3
check_msg

for i in $RANDOM $RANDOM $RANDOM; do
  edit "$i"
  update
  sleep 3
  check_msg "$i"
done
