---
title: "Create an OCP and OLM mirror with oc-mirror plugin"
toc: true
date: 2022-08-29T17:44:18+02:00
tags: [devops,openshift]
draft: true
---

# Table of Content

- [Table of Content](#table-of-content)
  - [Context](#context)
  - [oc-mirror plugin](#oc-mirror-plugin)
    - [Install](#install)
    - [Configure](#configure)
  - [Create a mirror](#create-a-mirror)
    - [Red Hat Quay.io credentials](#red-hat-quayio-credentials)
    - [Deploy disconnected registry](#deploy-disconnected-registry)
    - [Create mirror to file](#create-mirror-to-file)
    - [Create mirror from file to registry](#create-mirror-from-file-to-registry)
    - [ImageContentSourcePolicies objects](#imagecontentsourcepolicies-objects)
  - [Conclusions](#conclusions)
  - [Links](#links)

## Context

At the moment of this writing I'm working in the Telco 5G area at Red Hat, where we works mostly with bare metal  deployments of OpenShift. These deployments are focused on clusters that will be placed in remote locations with no Internet access due to security constrains and/or infrastructure designs.

Currently the deployment of OpenShift require of access to [Quay.io](https://quay.io/), because all their components are container images. This is a limitaion for the scenario that I just described before. Hence this is the reason why it is required to create a mirror in a disconnedted registry with the needed images to install OpenShift, from where to install a bare metal cluster without Internet access.

> ---
> **NOTE**
> 
> *All the command line examples are run on a Linux machine, how to do it with other OS is not the goal of this article.*
>

## oc-mirror plugin

The newest version of OCP (OpenShift Container Platform) at this moment is 4.11. This version comes with a lot of new interested features, and one of this features is the `oc-mirror` plugin.

Until now, to create a mirror of the OCP and OLM (Operator Lifecycle Manager) repositories, you had to use a sub-command of the `oc` CLI. The workflow to create the mirror and maintain it synced was very tedious (you can read the whole procedure in the [OCP official documentation](https://docs.openshift.com/container-platform/4.10/installing/disconnected_install/installing-mirroring-installation-images.html)). This is the reason why Red Hat has made an effort to simplify this procedure creating this plugin for `oc`. 

If you are interested in the source code of `oc-mirror` plugin you can find it in [their GitHub repository](https://github.com/openshift/oc-mirror).

### Install

The `oc-mirror` plugin is writen in Golang, hence this is just a binary that you can download to your machine, copy it to some place in your `$PATH` and add execution permissions. It can be downloaded from the [offical OCP release site](https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.11.2/).

```bash
curl https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.11.2/oc-mirror.tar.gz -o oc-mirror.tgz

tar zxvf oc-mirror.tgz

mv oc-mirror /usr/sbin/

chmod +x /usr/sbin/oc-mirror
```

You can check if everything works properly showing the version.

```bash
$ oc-mirror version
Client Version: version.Info{Major:"", Minor:"", GitVersion:"4.11.0-202208031306.p0.g3c1c80c.assembly.stream-3c1c80c", GitCommit:"3c1c80ca6a5a22b5826c88897e7a9e5acd7c1a96", GitTreeState:"clean", BuildDate:"2022-08-03T14:23:35Z", GoVersion:"go1.18.4", Compiler:"gc", Platform:"linux/amd64"}
```

### Configure

One of the improvements of `oc-mirror`, in comparison with the previous procedure using `oc adm` command, is that you can define the caracteristics of your mirror via a config file, and this file can be versioned using `git`, or any other version control system. This helps a lot in the lifecycle maintenance of your mirror. `oc-mirror` understand the contend of a **YAML** file called `imageSetConfiguration`. You can find generate a base file based on a template with the below commands.

```bash
$ podman login registry.redhat.io
Username: dchavero
Password: 
Login Succeeded!
$ mkdir ~/oc-mirror-demo
$ oc-mirror init > ~/oc-mirror-demo/imagesetconfig.yaml
```

Let's review the structure of the `imagesetconfig.yaml` file and the meaning of each field.

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2 # 1 
storageConfig:
  local:
    path: ./ # 2
mirror:
  platform:
    channels:
    - name: stable-4.11 # 3
      type: ocp
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.11 # 4
    packages: # 5
    - name: serverless-operator # 6
      channels:
      - name: stable # 7
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  helm: {}
```

1. Each version of `oc-mirror` required an specific `apiVersion`.
2. This is the path where the metadata of each mirror run is saved.
3. Which channel of **OCP** we are going to create the mirror.
4. The **OLM** catalog source that we are going to use.
5. Based on the previous catalog, winthin this field is spected an array with all the operators to be mirrored.
6. This is the  name of operator.
7. The channel of the operator.

In the example above it is configured to create a mirror of the whole **OCP 4.11** and only the **serverless-operator** from **OLM**

## Create a mirror

When you are going to create a mirror to deploy a disconnected environment there are different ways to do it. The best way for you depend of the your usecase. 

- You can create a mirror directly from the public Quay.io to your disconnected registry, what is faster because you only need one step to create the mirror. 

- If you have a very restrict network, and the servers where the cluster is going to be deployed don't have Internet access, you can create in a first step a mirror to a file, and later on copy this file to the place where the disconnected registry is. This last case is what I'm going to descrebe in this article. I think that is the most complex use case and maybe more use full to have a better understanding about how this procedure works.

Below in the diagram are shown the steps needed to create this mirror.

![Disconnected registry](/disconnected-registry.png)

1. Create a mirror from Quay.io to a local file in your workstation.
2. Copy the mirror file from your workstation to a server with access to the disconnected registry with Internet connection restrictions
3. Import the mirror from file to the disconnected registry.

### Red Hat Quay.io credentials

### Deploy disconnected registry



### Create mirror to file

### Create mirror from file to registry

### ImageContentSourcePolicies objects

## Conclusions

## Links
