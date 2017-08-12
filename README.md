# EXPERIMENTAL Kubernetes Docker Rules

## Rules

* [k8s_defaults](#k8s_defaults)
* [k8s_object](#k8s_object)

## Overview

This repository contains rules for interacting with Kubernetes configurations / clusters.

## Setup

Add the following to your `WORKSPACE` file to add the external repositories:

```python
git_repository(
    name = "io_bazel_rules_docker",
    remote = "https://github.com/bazelbuild/rules_docker.git",
    commit = "{HEAD}",
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
    commit = "{HEAD}",
)
load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_repositories")
k8s_repositories()
```

## Authorization

As is somewhat standard for Bazel, the expectation is that the
kubectl toolchain is configured to authenticate with any clusters
you might interact with.

TODO: Add a link to configuring auth in kubectl.

## Examples

### Basic "deployment" objects

```python
load("@io_bazel_rules_k8s//k8s:object.bzl", "k8s_object")

k8s_object(
  name = "dev",
  kind = "deployment",
  cluster = "my-gke-cluster",
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
  # When the `:dev`, `:dev.create` or `:dev.replace`
  # targets are `bazel run` these images are published and
  # their digest is substituted into the template in place of
  # what is currently published.
  images = {
    "gcr.io/convoy-adapter/bazel-grpc:{environment}": "//server:image"
  },
)
```


### Configuring aliases with defaults

In your `WORKSPACE` you can set up aliases for a more readable short-hand:
```python
load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_defaults")

k8s_defaults(
  # This becomes the name of the @repository and the rule
  # you will import in your BUILD files.
  name = "k8s_deploy",
  kind = "deployment",
  cluster = "my-gke-cluster",
)
```

Then in place of the above, you can use the following in your `BUILD` file:

```python
load("@k8s_deploy//:defaults.bzl", "k8s_deploy")

k8s_deploy(
  name = "dev",
  template = ":deployment.yaml.tpl",
  substitutions = {
      "environment": "{BUILD_USER}",
      "replicas": "1",
  },
  images = {
    "gcr.io/convoy-adapter/bazel-grpc:{environment}": "//server:image"
  },
)
```

### Configuring more advanced aliases

Suppose my team uses different clusters for development and production,
instead of a simple `k8s_deploy`, you might use:
```python
load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_defaults")

k8s_defaults(
  name = "k8s_dev_deploy",
  kind = "deployment",
  cluster = "my-dev-cluster",
)

k8s_defaults(
  name = "k8s_prod_deploy",
  kind = "deployment",
  cluster = "my-prod-cluster",
)
```

## Usage

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
bazel run :dev
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


<a name="k8s_object"></a>
## k8s_object

```python
k8s_object(name, kind, cluster, template, substitutions, images)
```

A rule that instantiates templated Kubernetes yaml and enables
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
      <td><code>kind</code></td>
      <td>
        <p><code>Kind, required</code></p>
        <p>The kind of the Kubernetes object in the yaml.</p>
      </td>
    </tr>
    <tr>
      <td><code>cluster</code></td>
      <td>
        <p><code>Cluster, required</code></p>
        <p>The name of the K8s cluster with which
	   <code>bazel run :foo.xxx</code> actions interact.</p>
      </td>
    </tr>
    <tr>
      <td><code>template</code></td>
      <td>
        <p><code>Templatized yaml file; required</code></p>
        <p>A templatized form of the Kubernetes yaml.</p>
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

<a name="k8s_defaults"></a>
## k8s_defaults

```python
k8s_defaults(name, kind, cluster)
```

A repository rule that allows users to alias `k8s_object` with default values
for `kind` and/or `cluster`.

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
        <p>The name of the repository that this rule will create.</p>
        <p>Also the name of rule imported from
	   <code>@name//:defaults.bzl</code></p>
      </td>
    </tr>
    <tr>
      <td><code>kind</code></td>
      <td>
        <p><code>Kind, optional</code></p>
        <p>The kind of objects the alias of <code>k8s_object</code> handles.</p>
      </td>
    </tr>
    <tr>
      <td><code>cluster</code></td>
      <td>
        <p><code>Cluster, optional</code></p>
        <p>The name of the K8s cluster with which
	   <code>bazel run :foo.xxx</code> actions interact.</p>
      </td>
    </tr>
  </tbody>
</table>
