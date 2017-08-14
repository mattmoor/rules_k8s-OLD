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
"""An implementation of k8s_object for interacting with an object of kind."""

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
  """Core implementation of k8s_object."""

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
  all_stamps = stamps + [resolved_stamps]

  # Resolve the template into our final location.
  # It is notable that we do not resolve tag references to digests
  # here because that is non-hermetic.
  _instantiate(ctx, ctx.file.template, all_stamps, ctx.outputs.yaml)

  push_commands = []
  all_inputs = []
  if ctx.attr.images:
    # Compute the set of layers from the image_targets.
    image_target_dict = _string_to_label(
        ctx.attr.image_targets, ctx.attr.image_target_strings)
    image_files_dict = _string_to_label(
        ctx.files.image_targets, ctx.attr.image_target_strings)

    stamp_arg = " ".join(["--stamp-info-file=%s" % f.short_path for f in stamps])

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
        legacy_base_arg = "--tarball=%s" % image["legacy"]
        inputs += [image["legacy"]]

      blobsums = image.get("blobsum", [])
      digest_arg = " ".join(["--digest=%s" % f.short_path for f in blobsums])
      blobs = image.get("zipped_layer", [])
      layer_arg = " ".join(["--layer=%s" % f.short_path for f in blobs])
      config_arg = "--config=%s" % image["config"].short_path
      inputs += [image["config"]] + blobsums + blobs

      push_commands += ["{pusher} --name={tag} {stamp} {image}".format(
        pusher = ctx.executable._pusher.short_path,
        tag = tag,
        stamp = stamp_arg,
        image = " ".join([legacy_base_arg, config_arg, digest_arg, layer_arg]))]
      index += 1
      all_inputs += inputs

  ctx.action(
      command = """cat > {resolve_script} <<"EOF"
#!/bin/bash -e
set -o pipefail
# TODO(mattmoor): Consider evaluating the pushes here in parallel.
{resolver} {overrides} < {yaml}
EOF""".format(
        resolver = ctx.executable._resolver.short_path,
        overrides = " ".join([
          "--override $(%s)" % script
          for script in push_commands
        ]),
        yaml = ctx.outputs.yaml.short_path,
        resolve_script = ctx.outputs.executable.path,
      ),
      inputs = [],
      outputs = [ctx.outputs.executable],
      mnemonic = "ResolveScript"
  )

  return struct(runfiles = ctx.runfiles(files = [
    ctx.executable._pusher,
    ctx.executable._resolver,
    ctx.outputs.yaml,
  ] + all_stamps + all_inputs))

def _create_impl(ctx):
  """Core implementation of k8s_object."""

  ctx.action(
      command = """cat > {create_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

TMPFILE=$(mktemp -t)
trap "rm -f $TMPFILE" EXIT
./{resolve_script} > $TMPFILE

echo Created "$(kubectl --cluster="{cluster}" create -f "$TMPFILE" | cut -d'"' -f 2)"
EOF""".format(
        cluster = ctx.attr.cluster,
        create_script = ctx.outputs.executable.path,
        resolve_script = ctx.executable.resolved.short_path,
      ),
      outputs = [ctx.outputs.executable],
      inputs = [],
      mnemonic = "CreateScript"
  )

  return struct(runfiles = ctx.runfiles(files = [
    ctx.executable._pusher,
    ctx.executable._resolver,
    ctx.executable.resolved,
    # Stamps
    ctx.info_file,
    ctx.version_file
  ] + list(ctx.attr.resolved.default_runfiles.files)))

def _replace_impl(ctx):
  """Core implementation of k8s_object."""

  ctx.action(
      command = """cat > {replace_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

TMPFILE=$(mktemp -t)
trap "rm -f $TMPFILE" EXIT
./{resolve_script} > $TMPFILE

echo Replaced "$(kubectl --cluster="{cluster}" replace -f "$TMPFILE" | cut -d'"' -f 2)"
EOF""".format( 
        cluster = ctx.attr.cluster,
        replace_script = ctx.outputs.executable.path,
        resolve_script = ctx.executable.resolved.short_path,
      ),
      outputs = [ctx.outputs.executable],
      inputs = [],
      mnemonic = "ReplaceScript"
  )

  return struct(runfiles = ctx.runfiles(files = [
    ctx.executable._pusher,
    ctx.executable._resolver,
    ctx.executable.resolved,
    # Stamps
    ctx.info_file,
    ctx.version_file
  ] + list(ctx.attr.resolved.default_runfiles.files)))

def _expose_impl(ctx):
  """Core implementation of k8s_object."""

  # TODO(mattmoor): We should check whether kind is one of
  # the resources for which expose works, and if not generate
  # an action that fails if run with a suitable diagnostic message.
  ctx.action(
      command = """cat > {expose_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

kubectl --cluster="{cluster}" expose "{kind}/$(kubectl create --dry-run -f "{yaml}" | cut -d'"' -f 2)" \
  --type LoadBalancer
EOF""".format(expose_script = ctx.outputs.executable.path,
              cluster = ctx.attr.cluster,
              kind = ctx.attr.kind,
              yaml = ctx.files.yaml[0].short_path,
      ),
      outputs = [ctx.outputs.executable],
      inputs = [],
      mnemonic = "ExposeScript"
  )

  return struct(runfiles = ctx.runfiles(files = ctx.files.yaml))

def _describe_impl(ctx):
  """Core implementation of k8s_object."""

  ctx.action(
      command = """cat > {describe_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

kubectl --cluster="{cluster}" describe {kind} "$(kubectl create --dry-run -f "{yaml}" | cut -d'"' -f 2)"
EOF""".format(describe_script = ctx.outputs.executable.path,
              cluster = ctx.attr.cluster,
              kind = ctx.attr.kind,
              yaml = ctx.files.yaml[0].short_path,
      ),
      outputs = [ctx.outputs.executable],
      inputs = [],
      mnemonic = "DescribeScript"
  )

  return struct(runfiles = ctx.runfiles(files = ctx.files.yaml))

def _delete_impl(ctx):
  """Core implementation of k8s_object."""

  ctx.action(
      command = """cat > {delete_script} <<"EOF"
#!/bin/bash -e
set -o pipefail

kubectl --cluster="{cluster}" delete {kind} "$(kubectl create --dry-run -f "{yaml}" | cut -d'"' -f 2)"
EOF""".format(delete_script = ctx.outputs.executable.path,
              cluster = ctx.attr.cluster,
              kind = ctx.attr.kind,
              yaml = ctx.files.yaml[0].short_path,
      ),
      outputs = [ctx.outputs.executable],
      inputs = [],
      mnemonic = "DeleteScript"
  )

  return struct(runfiles = ctx.runfiles(files = ctx.files.yaml))

_common_attrs = {
  "cluster": attr.string(mandatory = True),
  "kind": attr.string(mandatory = True,
                      # TODO(mattmoor): Support additional objects
                      values = ["deployment"]),
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
}

# TODO(mattmoor): Consider exposing something like docker.build, but for:
# k8s.object.create, k8s.deployment.create, etc...
_k8s_object = rule(
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
    } + _common_attrs + _layer_tools,
    outputs = {
        "yaml": "%{name}.yaml",
    },
    implementation = _impl,
    executable = True,
)

_k8s_object_create = rule(
    attrs = {
      "resolved": attr.label(
        cfg = "host",
        executable = True,
        allow_files = True,
      ),
    } + _common_attrs,
    implementation = _create_impl,
    executable = True,
)

_k8s_object_replace = rule(
    attrs = {
      "resolved": attr.label(
        cfg = "host",
        executable = True,
        allow_files = True,
      ),
    } + _common_attrs,
    implementation = _replace_impl,
    executable = True,
)

_k8s_object_expose = rule(
    attrs = {
      "yaml": attr.label(
        allow_files = [".yaml"],
        single_file = True,
        mandatory = True,
      ),
    } + _common_attrs,
    implementation = _expose_impl,
    executable = True,
)

_k8s_object_describe = rule(
    attrs = {
      "yaml": attr.label(
        allow_files = [".yaml"],
        single_file = True,
        mandatory = True,
      ),
    } + _common_attrs,
    implementation = _describe_impl,
    executable = True,
)

_k8s_object_delete = rule(
    attrs = {
      "yaml": attr.label(
        allow_files = [".yaml"],
        single_file = True,
        mandatory = True,
      ),
    } + _common_attrs,
    implementation = _delete_impl,
    executable = True,
)

def k8s_object(name, **kwargs):
  """Interact with a K8s object.

  Args:
    name: name of the rule.
    kind: the object kind.
    template: the yaml template to instantiate.
    substitutions: the set of substitutions to perform.
    images: the images that are a part of the template.
  """
  for reserved in ["image_targets", "image_target_strings", "resolved"]:
    if reserved in kwargs:
      fail("reserved for internal use by docker_bundle macro", attr=reserved)

  kwargs["image_targets"] = list(set(kwargs.get("images", {}).values()))
  kwargs["image_target_strings"] = list(set(kwargs.get("images", {}).values()))

  _k8s_object(name=name, **kwargs)
  _k8s_object_create(name=name + '.create', resolved=name,
                     kind=kwargs.get("kind"), cluster=kwargs.get("cluster"))
  _k8s_object_replace(name=name + '.replace', resolved=name,
                      kind=kwargs.get("kind"), cluster=kwargs.get("cluster"))
  _k8s_object_expose(name=name + '.expose', yaml=name + '.yaml',
                     kind=kwargs.get("kind"), cluster=kwargs.get("cluster"))
  _k8s_object_describe(name=name + '.describe', yaml=name + '.yaml',
                       kind=kwargs.get("kind"), cluster=kwargs.get("cluster"))
  _k8s_object_delete(name=name + '.delete', yaml=name + '.yaml',
                     kind=kwargs.get("kind"), cluster=kwargs.get("cluster"))
