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
  - [Run disconnected registry](#run-disconnected-registry)
  - [Create mirror](#create-mirror)

## Context

At the moment of this writing I'm working in the Telco 5G area at Red Hat, where we works mostly with bare metal  deployments of OpenShift. These deployments are focused on clusters that will be placed in remote locations whith no Internet access due to security constrains and/or infrastructure designs.

Currently the deployment of OpenShift require of access to [Quay.io](https://quay.io/), because all their components are container images. This is a limitaion for the scenario that I just described before. Hence this is the reason why it is required to create a mirror in a disconnedted registry of the needed images to install OpenShift , from where can be installed a bare metal cluster without Internet access.

## oc-mirror plugin

The newest version of OCP (OpenShift Container Platform) at this moment is 4.11. This version comes with a lot of new interested features, and one of this features is the `oc-mirror` plugin.

Until now, to create a mirror of the OCP and OLM (Operator Lifecycle Manager) repositories, you had to use a sub-command of the `oc` CLI. The workflow to create the mirror and maintain it synced was very tedious (you can read the whole procedure in the [OCP official documentation](https://docs.openshift.com/container-platform/4.10/installing/disconnected_install/installing-mirroring-installation-images.html)). This is the reason why Red Hat has made an efort to simplify this procedure creating this plugin for `oc`. 

If you are interested in the source code of `oc-mirror` plugin you can find it [their GitHub repository](https://github.com/openshift/oc-mirror).

### Install

The `oc-mirror` plugin is writen in Golang, hence this is just a binary that you can download to your machine, add execution permissions and copy it to some place in your `$PATH`. It can be downloaded from the [offical OCP release site](https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.11.2/).

```bash
curl https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.11.2/oc-mirror.tar.gz -o oc-mirror.tgz

tar zxvf oc-mirror.tgz

chmod +x oc-mirror

mv oc-mirror /usr/sbin/
```

## Run disconnected registry

## Create mirror
