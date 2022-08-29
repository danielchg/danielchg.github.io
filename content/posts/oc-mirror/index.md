---
title: "Create an OCP and OLM mirror with oc-mirror plugin"
toc: true
date: 2022-08-29T17:44:18+02:00
tags: [devops,openshift]
draft: true
---

## Context

At the moment of this writing I'm working in the Telco 5G area at Red Hat, where we works mostly with bare metal  deployments of OpenShift. These deployments are focused on clusters that will be placed in remote locations whith no Internet access due to security constrains and/or infrastructure designs.

Currently the deployment of OpenShift require of access to [Quay.io](https://quay.io/), because all their components are container images. This is a limitaion for the scenario that I just described before. Hence this is the reason why it is required to create a mirror in a disconnedted registry of the needed images to install OpenShift , from where can be installed a bare metal cluster without Internet access.

## OC Mirror plugin

The newest version of OCP (OpenShift Container Platform) is 4.11, with this version some new features are included, and one of this features is the `oc-mirror` plugin.

On previous versions of OCP there was some sub-commands with the `oc` tool to create a mirror to a disconnected registry, but these tools had some limitations compared with the new approach of `oc-mirror`.


