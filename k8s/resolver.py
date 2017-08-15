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
"""Walks a yaml object and resolves all docker_name.Tag to docker_name.Digest.
"""

import argparse
import sys

from containerregistry.client import docker_creds
from containerregistry.client import docker_name
from containerregistry.client.v2 import util as v2_util
from containerregistry.client.v2_2 import docker_image as v2_2_image
from containerregistry.client.v2_2 import util
from containerregistry.tools import patched
from containerregistry.transport import transport_pool

import httplib2
import yaml


parser = argparse.ArgumentParser(
    description='Resolve image references to digests.')

parser.add_argument(
  '--override', action='append',
  help='The set of tag to digest overrides.')


_THREADS = 8
_DOCUMENT_DELIMITER = '---\n'

def main():
  args = parser.parse_args()

  transport = transport_pool.Http(httplib2.Http, size=_THREADS)

  overrides = {}
  for o in args.override or []:
    (tag, digest) = o.split('=')
    overrides[docker_name.Tag(tag)] = docker_name.Digest(digest)

  def walk_dict(d):
    return {
      walk(k): walk(v)
      for (k, v) in d.iteritems()
    }

  def walk_list(l):
    return [walk(e) for e in l]

  def walk_string(s):
    try:
      as_tag = docker_name.Tag(s)
      if as_tag in overrides:
        return str(overrides[as_tag])

      # Resolve the tag to digest using the standard
      # Docker keychain logic.
      creds = docker_creds.DefaultKeychain.Resolve(as_tag)
      with v2_2_image.FromRegistry(as_tag, creds, transport) as img:
        if img.exists():
          digest = str(docker_name.Digest('{repository}@{digest}'.format(
            repository=as_tag.as_repository(),
            digest=util.Digest(img.manifest()))))
        else:
          # If the tag doesn't exists as v2.2, then try as v2.
          with v2_image.FromRegistry(as_tag, creds, transport) as img:
            digest = str(docker_name.Digest('{repository}@{digest}'.format(
              repository=as_tag.as_repository(),
              digest=v2_util.Digest(img.manifest()))))

      # Make sure we consistently resolve all instances of a tag,
      # since it is technically possible to have a race here.
      overrides[as_tag] = digest
      return digest
    except:
      return s

  def walk(o):
    if isinstance(o, dict):
      return walk_dict(o)
    if isinstance(o, list):
      return walk_list(o)
    if isinstance(o, str):
      return walk_string(o)
    return o


  inputs = sys.stdin.read()
  outputs = _DOCUMENT_DELIMITER.join([
    yaml.dump(walk(yaml.load(input)))
    for input in inputs.split(_DOCUMENT_DELIMITER)
  ])
  print outputs


if __name__ == '__main__':
  with patched.Httplib2():
    main()
