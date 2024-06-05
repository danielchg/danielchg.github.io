---
title: "SR-IOV on Openshift"
date: 2024-06-05T15:59:54+02:00
tags: [Telco,OpenShift,Networking]
draft: true
---

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
    - [What is SR-IOV](#what-is-sr-iov)
    - [Second interface on pods with Multus](#second-interface-on-pods-with-multus)
    - [Get network low latency using DPDK](#get-network-low-latency-using-dpdk)
    - [Describe environment used for this article](#describe-environment-used-for-this-article)
  - [How to use it on OpenShift](#how-to-use-it-on-openshift)
    - [Install SR-IOV operator](#install-sr-iov-operator)
    - [Configure VFs](#configure-vfs)
    - [Deploy workloads that use VFs](#deploy-workloads-that-use-vfs)
  - [Troubleshooting](#troubleshooting)
  - [Conclusions](#conclusions)
  - [Resources](#resources)

## Introduction

At the moment of this writing, the big actors on 5G, are making a huge effort to transform their workloads to be deployed as cloud native apps. Part of this effort is to run those workloads as containers on top of a platform based on Kubernetes. 

Other important challenge from Telco actors, is to interact as close as possible with the networking hardware, in order to reduce the latency during runtime. One of the industry standards used for that, implemented from the hardware manufactures, and also from the software perspective of the products involved, is SR-IOV. 

So, during this article let's try to explain what is SR-IOV, how it works on OpenShift and how to deploy workloads that use the advantage of it. Also explain the related technologies involved on this.

This article is not going to explain any Telco workloads, or walk you through the details on how the SR-IOV is implemented at hardware level, or even the software. The goal of this article is to introduce the use of SR-IOV on OpenShift, mainly focus to SRE or technical roles involved on use OpenShift for Telco deployments. A lot of interesting articles already exist about this topic, but I like to share my experience on this and share some tips I found during my path.

### What is SR-IOV

Single Root input/output Virtualization (SR-IOV) is a specification that allows the isolation in PCIe network devices, in subsets of virtual interfaces called Virtual Functions (VF). This way in single physical devices (called Physical Function), it is possible to create at hardware level VFs.

### Second interface on pods with Multus

Other 

### Get network low latency using DPDK

### Describe environment used for this article



## How to use it on OpenShift

### Install SR-IOV operator

### Configure VFs

### Deploy workloads that use VFs

## Troubleshooting

## Conclusions

## Resources

* SR-IOV from [official OpenShift documentation](https://docs.openshift.com/container-platform/4.15/networking/hardware_networks/about-sriov.html)

* Definition of SR-IOV from [Wikipedia](https://en.wikipedia.org/wiki/Single-root_input/output_virtualization)

* Some articles from different manufactures:
  * [Juniper](https://www.juniper.net/documentation/us/en/software/nce/nce-189-vsrx-sr-iov-ha-10g-deployment/topics/concept/disaggregated-junos-sr-iov.html)
  * [VMWare](https://docs.vmware.com/en/VMware-Telco-Cloud-Platform/3.0/telco-cloud-platform-5g-edition-data-plane-performance-tuning-guide/GUID-4B328085-63C1-402E-803F-6D710C5C3AAE.html)
  * [Broadcom](https://techdocs.broadcom.com/us/en/storage-and-ethernet-connectivity/ethernet-nic-controllers/bcm957xxx/adapters/introduction/features/sr-iov.html)
  * [Intel](https://www.intel.com/content/www/us/en/developer/articles/technical/configure-sr-iov-network-virtual-functions-in-linux-kvm.html)


* Other blog's articles realted to SR-IOV:
  * 

