---
title: "OpenShift hardening using the Compliance Operator"
date: 2023-01-24T17:45:23+01:00
tags: [SecDevOps,OpenShift,Security]
draft: true
---

# Table of Content

- [Table of Content](#table-of-content)
  - [Introduction](#introduction)
  - [Compliance Operator](#compliance-operator)
    - [Requirements](#requirements)
    - [Installation](#installation)
    - [Configure](#configure)
    - [Run scan](#run-scan)
    - [Get results](#get-results)
    - [Remediations](#remediations)
  - [Conclusions](#conclusions)
  - [Links](#links)


## Introduction

When we talk about Cyber Security there are a lot of aspect to be focused on to keep our services secure, and from the point of view of the platform, during all these years of Internet, the industry has created some standards in order to keep minimum requirement to think that our infrstructure is secure enough to avoid unauthorized access or DoS.

For Kubernetes, and also for OpenShift, exists some specification on how the clusters must be configured to minimize these security risks. Some of these standards that have specification for Kubernetes and OpenShift are:

* CIS Benchmarks
* ACSC
* NIST SP-800-53
* NERC CIP
* PCI

All these standards trying to ensure that the configuration of the platform is secure to run workloads on production environments. Hence, when we want to ensure that our Kubernetes or OpenShift cluster is secure, we can run one or more of these bencharmark, and apply the remediations recomended to keep the configuration of our cluster according to these standards. Depend where your cluster is based will be convinient one or another.

In the case of a Kubernetes or OpenShift clusters we must pass two kind of benchmarks, one for the operation system and other for the control plain of our cluster.


For this post we are going to use a Single Node OpenShift `v4.11.22` where we are going to install the Compliance Operator, and the required dependencies. During this article we are going to create a basic configuration to run a compliance scan, understand the results and the remediations. We are not going to see in detail each part of the Operator or review all the features, this is an introduction to understand the value of this operator, and how to run quickly a first scan to perform a hardening of our cluster.

## Compliance Operator

This operator try to make easy to scan our cluster to check the status of the compliance based on some standards profiles, like the described above. This operator is based on the open-source tool [OpenSCAP](https://www.open-scap.org/tools/openscap-base/). For more information about the Compliance Operator you can visit the [official documentation](https://docs.openshift.com/container-platform/4.12/security/compliance_operator/compliance-operator-understanding.html). 

### Requirements

Before installing the Compliance Operator we need a SNO OCP cluster running with a version 4.11+. 

It also required a default StorageClass configured, to allow the creation of PVCs to persist the results of the scans, hence we are going to install the LVMO operator. We are not going describe how to install it in this article, this is not the goal of this writing.

### Installation

The Compliance Operator is available on OperatorHub to be installed using OLM, hence the procedure is the same as install any other operator on OpenShift, just need to create a `Namespace`, an `OperatorGroup` and a `Subscription` objects. Below are the `YAML` files and commands used to created these object on our cluster.

**namespace.yaml**
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-compliance
```
Command to create the `Namespace` object.

```bash
oc apply -f namespace.yaml
```

**operator-group.yaml**
```yaml
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: compliance-operator
  namespace: openshift-compliance
spec:
  targetNamespaces:
  - openshift-compliance

```
Command to create the `OperatorGroup` object.

```bash
oc apply -f operator-group.yaml
```

**subscription.yaml**
```yaml
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: compliance-operator-sub
  namespace: openshift-compliance
spec:
  channel: "release-0.1"
  installPlanApproval: Automatic
  name: compliance-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace

```
Command to create the `OperatorGroup` object.

```bash
oc apply -f subscription.yaml
```

### Configure

### Run scan

### Get results

### Remediations

## Conclusions

## Links

- [Compliance Operator official documentation](https://docs.openshift.com/container-platform/4.12/security/compliance_operator/compliance-operator-understanding.html)
- [OpenSCAP tool](https://www.open-scap.org/tools/openscap-base/)
- [CIS benchmarks](https://www.cisecurity.org/cis-benchmarks/)
