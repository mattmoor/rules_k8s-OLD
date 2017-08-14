# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
workspace(name = "io_bazel_rules_k8s")

git_repository(
    name = "io_bazel_rules_docker",
    commit = "27b494ceefedd35b0ae72100860997f7ab1bf714",
    remote = "https://github.com/bazelbuild/rules_docker.git",
)

load(
    "@io_bazel_rules_docker//docker:docker.bzl",
    "docker_repositories",
)

docker_repositories()

load("//k8s:k8s.bzl", "k8s_repositories", "k8s_defaults")

k8s_repositories()

# ================================================================
# Imports for examples/
# ================================================================

git_repository(
    name = "org_pubref_rules_protobuf",
    commit = "be63ed9cb3140ec23e4df5118fca9a3f98640cf6",
    remote = "https://github.com/pubref/rules_protobuf.git",
)

load("@org_pubref_rules_protobuf//protobuf:rules.bzl", "proto_repositories")

proto_repositories()

load("@org_pubref_rules_protobuf//cpp:rules.bzl", "cpp_proto_repositories")

cpp_proto_repositories()

# We use cc_image to build our sample service
load(
    "@io_bazel_rules_docker//docker/contrib/cc:image.bzl",
    _cc_image_repos = "repositories",
)

_cc_image_repos()

# Generate a k8s_deploy alias that takes deployment objects and
# deploys them to the named cluster.
k8s_defaults(
    name = "k8s_deploy",
    # TODO(mattmoor): Move to a cluster in rules_k8s.
    cluster = "gke_convoy-adapter_us-central1-f_bazel-grpc",
    kind = "deployment",
)
