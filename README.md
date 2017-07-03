# EXPERIMENTAL Kubernetes Docker Rules

## Rules

* [k8s_deploy](#k8s_deploy)

## Overview

This repository contains rules for interacting with Kubernetes configurations.

## Setup

Add the following to your `WORKSPACE` file to add the external repositories:

```python
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

# This requires rules_docker to be fully instantiated before
# it is pulled in.
git_repository(
    name = "io_bazel_rules_k8s",
    remote = "https://github.com/mattmoor/rules_k8s.git",
    # TODO(mattmoor): Update when we release, for now use the
    # commit at HEAD.
    tag = "TODO",
)
load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_repositories")
k8s_repositories()
```

## Authorization

TODO: this section

## Examples

### k8s_deploy (Dev setup)

```python
k8s_deploy(
  name = "dev",
  # A template of a Kubernetes Deployment object yaml.
  template = ":deployment.yaml.tpl",
  # Format strings within the above template of the form:
  #   {environment} and {replicas}
  # These can be embedded in other strings, e.g.
  #   image: gcr.io/my-project/my-image:{environment}
  # You can think of these as augmenting the stamp variables
  # supported by docker_{push,bundle}, but they also support
  # stamp variables in their own values, see below.
  substitutions = {
      "environment": "{BUILD_USER}",
      "replicas": "1",
  },
  # When the `:dev.resolve`, `:dev.create` or `:dev.replace`
  # targets are `bazel run` these images are published and
  # their digest is substituted into the template in place of
  # what is currently published.
  images = {
    "gcr.io/convoy-adapter/bazel-grpc:{environment}": "//server:image"
  },
)
```


### k8s_deploy (Prod setup)

TODO: this

## Usage (k8s_deploy)

This single target exposes a rich set of actions that empower developers
to effectively deploy applications to Kubernetes.  We will follow the `:dev`
target from the example above.

### Instantiate the Template

Users can instantiate their `deployment.sh.tpl` by simply running:

```shell
bazel build :dev
```

This will create a single-replica deployment namespaced in various ways to
my developer identity.  You can examine it by:

```shell
cat bazel-bin/dev.yaml
```

### Instantiate *and Resolve* the Template

Deploying with tags, especially in production, is a bad idea because they are
mutable.  If a tag changes, it can lead to inconsistent versions of your app
running after auto-scaling or auto-healing events.  Thankfully in v2 of the
Docker Registry, digests were introduced.  Deploying by digest provides
cryptographic guarantees of consistency across the replicas of a deployment.

You can "resolve" the instantiated template by running:

```shell
bazel run :dev.resolve
```

This command will publish any `images = {}` present in your rule, substituting
those exact digests into the yaml template, and for other images resolving the
tags to digests by fetching their manifests.

### Creating an Environment

Users can create an environment by running:
```shell
bazel run :dev.create
```

This deploys the **resolved** template, including publishing images.

### Exposing an Environment

Users can "expose" their environment by running:

```shell
bazel run :dev.expose
```

### Describe the Environment

Users can "describe" their environment by running:

```shell
bazel run :dev.describe
```

### Updating/Replacing an Environment

Users can update (replace) their environment by running:
```shell
bazel run :dev.replace
```

Like `.create` this deploys the **resolved** template, including
republishing images.  This action is intended to be the workhorse
of fast-iteration development (rebuilding / republishing / redeploying).

### Tearing down an Environment

Users can tear down their environment by running:
```shell
bazel run :dev.delete
```

It is notable that despite deleting the deployment, this won't delete
any services currently load balancing over the deployment (e.g. `.expose`).
This is intentional as load balancers from cloud providers can be slow
to create.


<a name="k8s_deploy"></a>
## k8s_deploy

```python
k8s_deploy(name, template, substitutions, images)
```

A rule that instantiates templated Kubernetes Deployment yaml and enables
a variety of interactions with that object.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>name</code></td>
      <td>
        <p><code>Name, required</code></p>
        <p>Unique name for this rule.</p>
      </td>
    </tr>
    <tr>
      <td><code>template</code></td>
      <td>
        <p><code>Templatized yaml file; required</code></p>
        <p>A templatized form of the Kubernetes Deployment yaml.</p>
        <p>The yaml is allowed to container <code>{param}</code>
           references, for which stamp variables and substitutions
           will replace.</p>
      </td>
    </tr>
    <tr>
      <td><code>substitutions</code></td>
      <td>
        <p><code>Map of string to string; required</code></p>
        <p>A set of replacements to make across the template.</p>
        <p>Instances of each key surrounded by <code>{}</code> are
           replaced with the right-hand side, after stamp variables
           have been replaced (e.g. <code>{BUILD_USER}</code>).</p>
      </td>
    </tr>
    <tr>
      <td><code>images</code></td>
      <td>
        <p><code>Map of tag to Label; required</code></p>
        <p>Identical to the <code>images</code> attribute of
           <code>docker_bundle</code>, this set of images is published
           and tag references replaced with the published digest whenever
           the template is resolved (<code>.resolve, .create, .update</code>)</p>
      </td>
    </tr>
  </tbody>
</table>
