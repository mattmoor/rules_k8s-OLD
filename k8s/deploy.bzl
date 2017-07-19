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
"""An implementation of k8s_deploy to instantiate a Deployment."""

load(":object.bzl", "k8s_object")

def k8s_deploy(**kwargs):
  """Interact with a K8s deployment object.

  Args:
    name: name of the rule.
    template: the yaml template to instantiate.
    substitutions: the set of substitutions to perform.
    images: the images that are a part of the template.
  """
  if "kind" in kwargs:
    fail("k8s_deploy forces kind=\"deployment\", it should be omitted.",
         attr="kind")

  k8s_object(kind = "deployment", **kwargs)
