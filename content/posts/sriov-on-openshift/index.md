---
title: "SR-IOV on OpenShift"
date: 2024-06-05T15:59:54+02:00
tags: [Telco,OpenShift,Networking]
draft: true
---

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
    - [What is SR-IOV](#what-is-sr-iov)
    - [Describe environment used for this article](#describe-environment-used-for-this-article)
  - [How to use it on OpenShift](#how-to-use-it-on-openshift)
    - [Install SR-IOV operator](#install-sr-iov-operator)
    - [NIC BIOS settings](#nic-bios-settings)
    - [Configure VFs](#configure-vfs)
    - [Deploy workloads that use VFs](#deploy-workloads-that-use-vfs)
  - [Troubleshooting](#troubleshooting)
  - [Conclusions](#conclusions)
  - [Resources](#resources)

## Introduction

At the moment of this writing, the big actors on 5G, are making a huge effort to transform their workloads to be deployed as cloud native apps. Part of this effort is to run those workloads as containers on top of a platform based on Kubernetes. 

Other important challenge from Telco actors, is to interact as close as possible with the networking hardware, in order to reduce the latency during runtime. One of the industry standards involved to get this is SR-IOV.

During this article let's try to explain what is SR-IOV, how it works on OpenShift and how to deploy workloads that use the advantage of it.

This article is not going to explain anything related with the Telco workloads, or walk you through the details on how the SR-IOV is implemented at hardware level, or even the software. The goal of this article is to introduce the use of SR-IOV on OpenShift, mainly focus for SRE or other technical roles involved on use OpenShift for Telco deployments, as architects, DevOps, platform engineers, etc. A lot of interesting articles already exist about this topic, but I like to share my experience on this and share some tips I found during my path.

### What is SR-IOV

**Single Root input/output Virtualization (SR-IOV)** is a specification that allows the isolation in PCIe network devices, to create subsets of virtual interfaces called Virtual Functions (VF). This way in single physical devices (called Physical Function), it is possible to create at hardware level VFs.

Using SR-IOV devices, it is possible to have direct access to the Direct Memory Access (DMA) from the workload, which allow to get a low latency and better performance. In the case of virtualization allow the VM to interact directly with hardware via the PCI bus, and in the case of containers can be used DPDK for that, to interact directly with the hardware from the user space, instead of from the kernel space. The explanation of what is DPDK libraries and how works is not part of this article, but for sure that it is a very important topic that need to be understood by the reader. Some resource about DPDK are included at the end of the article if you are more interested on that.

### Describe environment used for this article

The environment used for this article is a baremetal laboratory, compound by five **Dell PowerEdge R450** nodes. Three of these nodes are the control plane nodes of the cluster, and the other two are worker nodes. The installation of the cluster is out of the scope of this article. You can refer to the [OpenShift official documentation](https://docs.openshift.com/container-platform/4.15/installing/index.html) for that.

```bash
$oc get nodes,clusterversion
NAME                         STATUS   ROLES                  AGE     VERSION
node/master0.ocp1.r450.org   Ready    control-plane,master   7d22h   v1.27.10+c79e5e2
node/master1.ocp1.r450.org   Ready    control-plane,master   7d22h   v1.27.10+c79e5e2
node/master2.ocp1.r450.org   Ready    control-plane,master   7d22h   v1.27.10+c79e5e2
node/worker0.ocp1.r450.org   Ready    worker                 7d22h   v1.27.10+c79e5e2
node/worker1.ocp1.r450.org   Ready    worker                 7d22h   v1.27.10+c79e5e2

NAME                                         VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
clusterversion.config.openshift.io/version   4.14.16   True        False         7d22h   Cluster version is 4.14.16
```

The worker nodes have connected  an **Intel E810-XXV** NIC on each one, which support SR-IOV.

## How to use it on OpenShift

Now that we understand how SR-IOV works and why it is important for Telco deployments, let's walk through how to use it on OpenShift.

As most of the implementations on Kubernetes or OpenShift, the main way to extend features of our cluster is via an operator. This is not an exception, there is a SR-IOV operator that allow us to configure everything via the Kubernetes API applying YAML manifest.

### Install SR-IOV operator

The installation of the SR-IOV operator is straight forward using OLM. It is very well documented in the [OpenShift official documentation](https://docs.openshift.com/container-platform/4.14/networking/hardware_networks/installing-sriov-operator.html), but let's summarize in here how to do it using the `oc` CLI.

* Create the **openshift-sriov-network-operator** namespace:

```bash
$ cat << EOF| oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-sriov-network-operator
  annotations:
    workload.openshift.io/allowed: management
EOF
```
* Create the OperatorGroup for the SR-IOV operator:

```bash
$ cat << EOF| oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: sriov-network-operators
  namespace: openshift-sriov-network-operator
spec:
  targetNamespaces:
  - openshift-sriov-network-operator
EOF
```

* Create the Subscription:

```bash
$ cat << EOF| oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: sriov-network-operator-subscription
  namespace: openshift-sriov-network-operator
spec:
  channel: stable
  name: sriov-network-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

* Verify the installation:

```bash
$oc get csv -n openshift-sriov-network-operator \
  -o custom-columns=Name:.metadata.name,Phase:.status.phase
Name                                          Phase
sriov-network-operator.v4.14.0-202405161337   Succeeded
```

### NIC BIOS settings 

As we already mentioned above, it is mandatory for using SR-IOV to have support at hardware level. In our case the **Intel E810** NICs support SR-IOV. But even the NIC support it, we need to configure it from the BIOS settings.

To ensure that the required configurations for the NIC are enabled, we need to connect to the server BMC, in our case iDRAC because is a DELL machine. From there, we have to open the Virtual Console, reboot our system from the Power options, and follow the next workflow:

1. Press ***F2*** (Enter System Setup)
2. Clikc on ***Device Settings***
3. Select your devices from the list, in our case ***NIC in Slot 3 Port 1: Intel(R) Ethernet 25G 2P E810-XXV Adapter***
4. From this view enable ***SR-IOV*** within the ***Virtualization Mode***, as show below in the pic

![Enable SR-IOV](/sriov-bios-enable.png)

5. Click on ***Finish*** until get the ***System Setup*** menu
6. Click on ***System BIOS***
7. Click on ***Integrated Devices***
8. Ensure that ***SR-IOV Global Enable*** is ***Enabled*** as show below


![Enable SR-IOV 2](/sriov-bios-enable-2.png)

9. Click on ***Back*** and ***Finish*** until a window ask for confirmation and then click on ***Yes***

At this point we are sure that SR-IOV is enabled in our NIC. Now let’s see from the OS that the driver support it. In the below capture the output of the `lspci` command show the capabilities of the devices, and there we can see that the card support SR-IOV.

```bash
sh-5.1# lspci | grep E810
98:00.0 Ethernet controller: Intel Corporation Ethernet Controller E810-XXV for SFP (rev 02)
98:00.1 Ethernet controller: Intel Corporation Ethernet Controller E810-XXV for SFP (rev 02)
sh-5.1# lspci -s 98:00.0 -v
98:00.0 Ethernet controller: Intel Corporation Ethernet Controller E810-XXV for SFP (rev 02)
        Subsystem: Intel Corporation Ethernet 25G 2P E810-XXV Adapter
        Flags: bus master, fast devsel, latency 0, IRQ 18, NUMA node 1
        Memory at d4000000 (64-bit, prefetchable) [size=32M]
        Memory at d8010000 (64-bit, prefetchable) [size=64K]
        Expansion ROM at d1000000 [disabled] [size=1M]
        Capabilities: [40] Power Management version 3
        Capabilities: [50] MSI: Enable- Count=1/1 Maskable+ 64bit+
        Capabilities: [70] MSI-X: Enable+ Count=1024 Masked-
        Capabilities: [a0] Express Endpoint, MSI 00
        Capabilities: [e0] Vital Product Data
        Capabilities: [100] Advanced Error Reporting
        Capabilities: [148] Alternative Routing-ID Interpretation (ARI)
        Capabilities: [150] Device Serial Number b4-83-51-ff-ff-00-66-a6
        Capabilities: [160] Single Root I/O Virtualization (SR-IOV)
        Capabilities: [1a0] Transaction Processing Hints
        Capabilities: [1b0] Access Control Services
        Capabilities: [1d0] Secondary PCI Express
        Capabilities: [200] Data Link Feature <?>
        Capabilities: [210] Physical Layer 16.0 GT/s <?>
        Capabilities: [250] Lane Margining at the Receiver <?>
        Kernel driver in use: ice
        Kernel modules: ice

```

### Configure VFs

```bash
$oc debug node/worker1.ocp1.r450.org
Starting pod/worker1ocp1r450org-debug-j5mvd ...
To use host binaries, run `chroot /host`
Pod IP: 10.6.115.24
If you don't see a command prompt, try pressing enter.
sh-4.4# chroot /host
sh-5.1# ip link show ens3f1
7: ens3f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether b4:83:51:00:66:a7 brd ff:ff:ff:ff:ff:ff
    vf 0     link/ether aa:94:1c:3b:6c:79 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 1     link/ether 9e:60:c6:85:dc:7b brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 2     link/ether 36:28:fe:31:0a:72 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 3     link/ether f2:1b:59:70:3b:f3 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 4     link/ether f6:42:ee:0f:73:79 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 5     link/ether da:0e:29:9e:9c:bb brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 6     link/ether 56:f5:4d:b3:0e:0e brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    vf 7     link/ether ae:6b:93:a1:ee:b8 brd ff:ff:ff:ff:ff:ff, spoof checking on, link-state auto, trust off
    altname enp152s0f1
sh-5.1# 

```

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

* [DPDK site](https://www.dpdk.org/about/)
  
* [Use DPDK library to work with SR-IOV hardware](https://docs.openshift.com/container-platform/4.15/networking/hardware_networks/using-dpdk-and-rdma.html).
