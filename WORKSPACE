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
    remote = "https://github.com/mattmoor/rules_docker.git",
    commit = "5ee8f1b66309d6c59762900cf0b8b1b88224ecaf",
)

load(
  "@io_bazel_rules_docker//docker:docker.bzl",
  "docker_repositories",
)
docker_repositories()

load("//k8s:k8s.bzl", "k8s_repositories")
k8s_repositories()