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

load(
    "@io_bazel_rules_docker//docker:layers.bzl",
    _get_layers = "get_from_target",
    _layer_tools = "tools",
)
load(
    "@io_bazel_rules_docker//docker:label.bzl",
    _string_to_label = "string_to_label",
)

def _instantiate(ctx, f, stamps, output):
  stamp_args = " ".join([
    "--stamp-info-file=%s" % sf.path
    for sf in stamps
  ])
  ctx.action(
    command = ("%s " + stamp_args + " < %s > %s") % (
      ctx.executable._stamper.path,
      f.path, output.path),
    inputs = [ctx.executable._stamper, f] + stamps,
    outputs = [output],
    mnemonic = "InstantiateStamps"
  )

def _runfile_path(ctx, f):
  """Return the runfiles relative path of f."""
  if ctx.workspace_name:
    return ctx.workspace_name + "/" + f.short_path
  else:
    return f.short_path

def _impl(ctx):
  """Core implementation of k8s_deploy."""

  # Option using Bazel for substitutions.
  # ctx.template_action(
  #     template = ctx.file.template,
  #     substitutions = ctx.attr.substitutions,
  #     output = ctx.outputs.yaml,
  # )

  # Set up the user's stamp file.
  user_stamps = ctx.new_file(ctx.label.name + ".stamps")
  ctx.file_action(
    output = user_stamps,
    content = "\n".join([
      "%s %s" % (key, ctx.attr.substitutions[key])
      for key in ctx.attr.substitutions
    ])
  )

  # Resolve the RHS of the user's stamp file before stamping stuff with it.
  resolved_stamps = ctx.new_file(user_stamps.basename + ".instantiated")
  stamps = [ctx.info_file, ctx.version_file]
  _instantiate(ctx, user_stamps, stamps, resolved_stamps)
  stamps += [resolved_stamps]

  # Resolve the template into our final location.
  # It is notable that we do not resolve tag references to digests
  # here because that is non-hermetic.
  _instantiate(ctx, ctx.file.template, stamps, ctx.outputs.yaml)

  push_scripts = []
  if ctx.attr.images:
    # Compute the set of layers from the image_targets.
    image_target_dict = _string_to_label(
        ctx.attr.image_targets, ctx.attr.image_target_strings)
    image_files_dict = _string_to_label(
        ctx.files.image_targets, ctx.attr.image_target_strings)

    stamp_arg = " ".join(["--stamp-info-file=%s" % f.path for f in stamps])

    # Walk the images attribute producing:
    # 1) a set of push commands for each entry of our images attribute,
    #    the output files should be aggregated as inputs to our resolve
    #    script.
    # 2) a set of override arguments of the form: --override {tag}={digest}
    #    given that the output of push_and_resolve.py is {tag}={digest}
    #    these will likely be: --override $(script from #1)
    index = 0
    for unresolved_tag in ctx.attr.images:
      # Allow users to put make variables into the tag name.
      tag = ctx.expand_make_variables("images", unresolved_tag, {})
      target = ctx.attr.images[unresolved_tag]

      image = _get_layers(ctx, image_target_dict[target], image_files_dict[target])

      inputs = [ctx.executable._pusher] + stamps
      legacy_base_arg = ""
      if image.get("legacy"):
        legacy_base_arg = "--tarball=%s" % image["legacy"].path
        inputs += [image["legacy"]]

      blobsums = image.get("blobsum", [])
      digest_arg = " ".join(["--digest=%s" % f.path for f in blobsums])
      blobs = image.get("zipped_layer", [])
      layer_arg = " ".join(["--layer=%s" % f.path for f in blobs])
      config_arg = "--config=%s" % image["config"].path
      inputs += [image["config"]] + blobsums + blobs

      out = ctx.new_file("%s.%d.push" % (ctx.label.name, index))
      ctx.action(
        command = """cat > {script} <<"EOF"
#!/bin/bash -e
{pusher} --name={tag} {stamp} {image}
EOF""".format(
  script = out.path,
  pusher = ctx.executable._pusher.path,
  tag = tag,
  stamp = stamp_arg,
  image = "%s %s %s %s" % (
    legacy_base_arg, config_arg, digest_arg, layer_arg)),
        inputs = inputs,
        outputs = [out],
        mnemonic = "PushImage"
      )
      push_scripts += [out]
      index += 1

  ctx.action(
      command = """cat > {resolve_script} <<"EOF"
#!/bin/bash -e
set -o pipefail
# TODO(mattmoor): Consider evaluating the pushes here in parallel.
{resolver} {overrides} < {yaml}
EOF""".format(
        resolver = ctx.executable._resolver.path,
        overrides = " ".join([
          "--override $(%s)" % script.path
          for script in push_scripts
        ]),
        yaml = ctx.outputs.yaml.path,
        resolve_script = ctx.outputs.resolve.path,
      ),
      inputs = [ctx.outputs.yaml, ctx.executable._resolver] + push_scripts,
      outputs = [ctx.outputs.resolve],
      mnemonic = "ResolveScript"
  )


  # TODO(mattmoor): Make these use the .resolve output.
  ctx.action(
      command = """cat > {create_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

TMPFILE=$(mktemp -t)
trap "rm -f $TMPFILE" EXIT
{resolve_script} > $TMPFILE

echo Created "$(kubectl create -f "$TMPFILE" | cut -d'"' -f 2)"
EOF""".format(
        create_script = ctx.outputs.create.path,
        resolve_script = ctx.outputs.resolve.path,
      ),
      outputs = [ctx.outputs.create],
      inputs = [ctx.outputs.resolve],
      mnemonic = "CreateScript"
  )

  ctx.action(
      command = """cat > {replace_script} <<"EOF"
#!/bin/bash -e

TMPFILE=$(mktemp -t)
trap "rm -f $TMPFILE" EXIT
{resolve_script} > $TMPFILE

# TODO(mattmoor): Capture and rewrite output?
kubectl replace -f "$TMPFILE"
EOF""".format(
        replace_script = ctx.outputs.replace.path,
        resolve_script = ctx.outputs.resolve.path,
      ),
      outputs = [ctx.outputs.replace],
      inputs = [ctx.outputs.resolve],
      mnemonic = "ReplaceScript"
  )

  ctx.action(
      command = """cat > {expose_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

kubectl expose "deployment/$(kubectl create --dry-run -f "{yaml}" | cut -d'"' -f 2)" \
  --type LoadBalancer
EOF""".format(
        expose_script = ctx.outputs.expose.path,
        yaml = ctx.outputs.yaml.path,
      ),
      outputs = [ctx.outputs.expose],
      inputs = [ctx.outputs.yaml],
      mnemonic = "ExposeScript"
  )

  ctx.action(
      command = """cat > {describe_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

kubectl describe deployment "$(kubectl create --dry-run -f "{yaml}" | cut -d'"' -f 2)"
EOF""".format(
        describe_script = ctx.outputs.describe.path,
        yaml = ctx.outputs.yaml.path,
      ),
      outputs = [ctx.outputs.describe],
      inputs = [ctx.outputs.yaml],
      mnemonic = "DescribeScript"
  )

  ctx.action(
      command = """cat > {delete_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

kubectl delete deployment "$(kubectl create --dry-run -f "{yaml}" | cut -d'"' -f 2)"
EOF""".format(
        delete_script = ctx.outputs.delete.path,
        yaml = ctx.outputs.yaml.path,
      ),
      outputs = [ctx.outputs.delete],
      inputs = [ctx.outputs.yaml],
      mnemonic = "DeleteScript"
  )

  return struct(runfiles = ctx.runfiles(files = [
    ctx.executable._pusher,
    ctx.executable._resolver,
    ctx.outputs.yaml,
  ] + stamps))

_k8s_deploy = rule(
    attrs = {
        "template": attr.label(
            allow_files = [".yaml", ".yaml.tpl"],
            single_file = True,
            mandatory = True,
        ),
        "substitutions": attr.string_dict(),
        "images": attr.string_dict(),
        # Implicit dependencies.
        "image_targets": attr.label_list(allow_files = True),
        "image_target_strings": attr.string_list(),
        "_stamper": attr.label(
            default = Label("//k8s:stamper.par"),
            cfg = "host",
            executable = True,
            allow_files = True,
        ),
        "_pusher": attr.label(
            default = Label("//k8s:push_and_resolve.par"),
            cfg = "host",
            executable = True,
            allow_files = True,
        ),
        "_resolver": attr.label(
            default = Label("//k8s:resolver.par"),
            cfg = "host",
            executable = True,
            allow_files = True,
        ),
    } + _layer_tools,
    outputs = {
        "yaml": "%{name}.yaml",
        "create": "%{name}.create",
        "expose": "%{name}.expose",
        "describe": "%{name}.describe",
        "replace": "%{name}.replace",
        "resolve": "%{name}.resolve",
        "delete": "%{name}.delete",
    },
    implementation = _impl,
)

def k8s_deploy(**kwargs):
  """Resolve a K8s deployment object.

  Args:
    name: name of the rule
    template: the yaml template to instantiate.
    substitutions: the set of substitutions to perform.
  """
  for reserved in ["image_targets", "image_target_strings"]:
    if reserved in kwargs:
      fail("reserved for internal use by docker_bundle macro", attr=reserved)

  kwargs["image_targets"] = list(set(kwargs.get("images", {}).values()))
  kwargs["image_target_strings"] = list(set(kwargs.get("images", {}).values()))

  _k8s_deploy(**kwargs)
