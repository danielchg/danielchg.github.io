---
title: "Troubleshooting Isolated CPUs for low latency workloads on OpenShift"
date: 2026-03-24T12:46:06+01:00
tags: [Telco,OpenShift,Networking,Linux]
draft: false
---

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [PerformanceProfile](#performanceprofile)
    - [Configuring reserved/isolated CPUs](#configuring-reservedisolated-cpus)
  - [Deploy testpmd workload](#deploy-testpmd-workload)
  - [Troubleshooting isolated CPUs](#troubleshooting-isolated-cpus)
  - [Conclusions](#conclusions)
  - [Resources](#resources)

## Introduction

When we talk about low latency workloads, there are some requirements at Linux Kernel settings and how we place those workloads to run on the hardware. It is important that the workloads run as close as possible to the hardware they are going to interact with, like a network interface. Hence we will need to ensure that these workloads run in CPUs within the same NUMA node to which the network interface is connected, to avoid cross NUMA connections. 

In OpenShift there is a Cluster Operator (it comes by default with OpenShift) that allows configuring the cluster nodes in an opinionated way based on Kubernetes CR. This CR is called `PerformanceProfile` and it is described in the next section. 

Even though we have our OpenShift cluster configured with a `PerformanceProfile`, we need to deploy our application accordingly with those settings, and we are going to describe in this article how to review that our application is running on isolated CPUs in the desired NUMA node, and that there are no task switches or undesired IRQ interruptions.

In this article we will explain how to configure the reserved CPUs for the OpenShift control plane and the isolated CPUs to run the workload. Later on we are going to deploy a DPDK application based on [testpmd](https://doc.dpdk.org/guides/testpmd_app_ug/), and we are going to go through some steps to validate that the workloads are running as expected in the OpenShift cluster.

## PerformanceProfile

The PerformanceProfile is a Custom Resource (CR) provided by the Performance Addon Operator (now part of the Node Tuning Operator) in OpenShift. It allows cluster administrators to configure nodes for low-latency workloads by applying a set of performance-focused kernel and system configurations.

Key features of the PerformanceProfile include:

- **CPU Isolation**: Segregates CPUs into reserved (for system/control plane tasks) and isolated (dedicated for workload execution) sets
- **NUMA Awareness**: Ensures workloads run on CPUs that share the same NUMA node as their hardware resources
- **Kernel Tuning**: Applies kernel parameters like `isolcpus`, `nohz_full`, and `rcu_nocbs` to minimize interruptions on isolated CPUs
- **IRQ Affinity**: Routes hardware interrupts away from isolated CPUs to prevent latency spikes
- **Huge Pages**: Configures huge pages for memory-intensive applications like DPDK

By defining a PerformanceProfile, OpenShift automatically configures the underlying nodes with the necessary optimizations for deterministic, low-latency application performance.

### Configuring reserved/isolated CPUs

As described above, different aspects can be configured from the `PerformanceProfile`, but in this article we are going to describe how to set the right values for the reserved and isolated CPUs.

The reserved CPUs are the ones used by the system and the OpenShift control plane. This is important to ensure that in case the user workloads start consuming extra resources, they do not affect the cluster itself. Also the other way around, if the Control Plane needs more resources, we need to ensure the workloads have room to keep working. 

Depending on the use case, we are going to configure more or less reserved and isolated CPUs, and also depending on whether we are configuring only a group of workers or also the control plane nodes. For this article we are going to discuss only the creation of a `PerformanceProfile` for workers, for which we are going to reserve 4 vCPUs (hyperthreading is enabled) on both NUMA nodes. It is important to highlight that we are working on bare metal.

The first thing we have to do is check the distribution of the cores and the siblings between NUMA nodes, to ensure we reserve the first core with its sibling plus an additional core. The below command shows the distribution of the cores (this command is run within the node):

```bash
sh-5.1# lscpu --extended
CPU NODE SOCKET CORE L1d:L1i:L2:L3 ONLINE    MAXMHZ   MINMHZ       MHZ
  0    0      0    0 0:0:0:0          yes 3800.0000 800.0000 1800.0000
  1    1      1    1 64:64:64:1       yes 3800.0000 800.0000 2165.7891
  2    0      0    2 19:19:19:0       yes 3800.0000 800.0000 1800.0000
  3    1      1    3 83:83:83:1       yes 3800.0000 800.0000 1800.0000
  4    0      0    4 8:8:8:0          yes 3800.0000 800.0000 2260.8970
  5    1      1    5 72:72:72:1       yes 3800.0000 800.0000 1800.0000
  6    0      0    6 27:27:27:0       yes 3800.0000 800.0000 1800.0000

# output omitted ...

 64    0      0    0 0:0:0:0          yes 3800.0000 800.0000 3800.0000
 65    1      1    1 64:64:64:1       yes 3800.0000 800.0000 2058.6201
 66    0      0    2 19:19:19:0       yes 3800.0000 800.0000 3800.0000
 67    1      1    3 83:83:83:1       yes 3800.0000 800.0000 2275.6350
 68    0      0    4 8:8:8:0          yes 3800.0000 800.0000 3800.0000
 69    1      1    5 76:76:76:1       yes 3800.0000 800.0000 3800.0000
 70    0      0    6 27:27:27:0       yes 3800.0000 800.0000 3800.0000

# output omitted ...

123    1      1   59 84:84:84:1       yes 3800.0000 800.0000 3800.0000
124    0      0   60 15:15:15:0       yes 3800.0000 800.0000 3800.0000
125    1      1   61 72:72:72:1       yes 3800.0000 800.0000 3800.0000
126    0      0   62 22:22:22:0       yes 3800.0000 800.0000 3800.0000
127    1      1   63 80:80:80:1       yes 3800.0000 800.0000 3800.0000
```

In the output above we can see in the first column the vCPU id, in the second column the NUMA node, and in the fourth column the Core id. We must use the first vCPU and its sibling, which is vCPU 64. We add three more vCPUs for the reservation, then we are going to reserve `0-1` and `64-65`. The rest will be configured within the `isolated` CPUs, and the sum of both must match the total amount of CPUs, otherwise it will fail.

Below is the `PerformanceProfile` used for this article. Even though there are other parameters, we are going to cover only the part of the reserved/isolated CPUs configuration here.

```yaml
apiVersion: performance.openshift.io/v2
kind: PerformanceProfile
metadata:
  annotations:
    kubeletconfig.experimental: |
      {"systemReserved": {"memory": "8Gi"}, "topologyManagerScope": "pod"}
  name: lowlatency
spec:
  additionalKernelArgs:
  - nohz_full='4-63,69-127'
  - nohz_full='2-63,66-127'
  cpu:
    isolated: 2-63,66-127
    reserved: 0-1,64-65
  globallyDisableIrqLoadBalancing: false
  hugepages:
    defaultHugepagesSize: 1G
    pages:
    - count: 6
      node: 0
      size: 1G
    - count: 6
      node: 1
      size: 1G
  kernelPageSize: 4k
  machineConfigPoolSelector:
    pools.operator.machineconfiguration.openshift.io/lowlatency: ""
  net:
    devices:
    - interfaceName: eno12399
    - interfaceName: eno12419
    userLevelNetworking: true
  nodeSelector:
    node-role.kubernetes.io/lowlatency: ""
  numa:
    topologyPolicy: single-numa-node
  realTimeKernel:
    enabled: false
  workloadHints:
    highPowerConsumption: false
    perPodPowerManagement: true
    realTime: false
```

It is not covered in this article, but we must create a `MachineConfigPool` called `lowlatency` in our cluster where this `PerformanceProfile` will be applied. Once applied, we can check as shown in the command below that the status of the `MachineConfigPool` of all the nodes belonging to it is `UPDATED True`. 

```bash
$oc get mcp lowlatency
NAME      CONFIG                                              UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
lowlatency   rendered-lowlatency-0c3b91cfa6eaa7b559a2eb994cd2c4f1   True      False      False      3              3                   3                     0                      18d

```

## Deploy testpmd workload 

Now that we have the workers configured with the `PerformanceProfile`, we can deploy a pod to run a DPDK application with CPU pinning. The below pod manifest is an example that deploys a `testpmd` container.

It is important to highlight some aspects of the below Pod manifests:

* In order to allow the scheduler to use the QoS, we have to set the same amount of `limits` and `resources` within the `.spec.containers.resources` .
* The field `runtimeClassName` must be set with `performance-` plus the name of the `PerformanceProfile`. In this case the value is `performance-lowlatency`.
* The annotations regarding the irq load balancing is important to ensure the pined CPUs will not run interruptions. 

```yaml
apiVersion: v1
kind: Pod
metadata:
 annotations:
   k8s.v1.cni.cncf.io/networks: '[
     {
      "name": "net1",
      "namespace": "testpmd"
     }
   ]'
   cpu-load-balancing.crio.io: disable
   cpu-quota.crio.io: disable
   irq-load-balancing.crio.io: "disable"
 labels:
   app: testpmd
 name: testpmd
 namespace: testpmd
spec:
  tolerations:
   - key: "high-throughput"
     value: "true"
     effect: "NoSchedule"
  containers:
    - command:
        - /bin/bash
        - -c
        - sleep infinity
      image: quay.io/javierpena/dpdk:21.11.2_c9s
      imagePullPolicy: Always
      name: pktgen
      resources:
        limits:
          cpu: "10"
          hugepages-1Gi: 4Gi
          memory: 2Gi
        requests:
          cpu: "10"
          hugepages-1Gi: 4Gi
          memory: 2Gi
      securityContext:
        privileged: true
        capabilities:
          add:
            - IPC_LOCK
            - SYS_RESOURCE
            - NET_RAW
            - NET_ADMIN
        runAsUser: 0
      volumeMounts:
        - mountPath: /mnt/huge
          name: hugepages
        - name: modules
          mountPath: /lib/modules
  terminationGracePeriodSeconds: 5
  volumes:
    - name: modules
      hostPath:
        path: /lib/modules
    - emptyDir:
        medium: HugePages
      name: hugepages
  runtimeClassName: performance-lowlatency
```

We apply the manifests above to run our workload in the `testpmd` Namespace.

> **NOTE**
>
> In this example, SR-IOV is already configured to attach the VFs to the pod. That is not included in this article to focus only on the troubleshooting of the CPU resources.

## Troubleshooting isolated CPUs

1. Find worker where the workload is running

```bash
$oc -n testpmd get pods testpmd -o wide
NAME      READY   STATUS    RESTARTS   AGE     IP            NODE                           NOMINATED NODE   READINESS GATES
testpmd   1/1     Running   0          5d14h   10.129.2.12   worker3.ocp1.e5gc.bos2.lab     <none>           <none>
```

2. Get the ContainerId of pod

```bash
$oc debug node/htworker3.ocp1.e5gc.bos2.lab
Starting pod/worker3ocp1e5gcbos2lab-debug-vb2t4 ...
To use host binaries, run `chroot /host`. Instead, if you need to access host namespaces, run `nsenter -a -t 1`.
Pod IP: 192.168.82.73
If you don't see a command prompt, try pressing enter.
sh-5.1# chroot /host
sh-5.1# 
sh-5.1# crictl ps | grep testpmd
3c0e19d3e6964       quay.io/javierpena/dpdk@sha256:bc647e696a16332d7c129d33ccccf40a157f88acd644eff7f6ce148e206b1d43                                                 5 days ago          Running             pktgen                               0                   dc474cfee8a7e       testpmd        
```

3. Get PID of the container

```bash
[root@htworker3 ~]# crictl inspect 3c0e19d3e6964 | jq .info.pid
2138345
```

4. Get CPU pinned

```bash
[root@htworker3 ~]# crictl inspect 3c0e19d3e6964 | jq .status.resources.linux.cpusetCpus
"4,6,8,10,12,68,70,72,74,76"
```

5. Check if there are task switches associated with given PID. The important thing is to ensure there are no changes in the switches. Only the processes from the pod should be in there and no new task must be scheduled in this core if the pinning is working properly.

```bash
watch grep switches /proc/2138345/task/2138345/sched
nr_switches                                  :                    6
nr_voluntary_switches                        :                    6
nr_involuntary_switches                      :                    0
```

In case we see new switches we can check which processes are being scheduled in the pinned CPU beside the ones from the pod with the below command. For this it is required to exit from the `chroot /host` or run toolbox to have the perf tool installed in an OpenShift node.

```bash
perf top --sort comm,dso -C <CPU> -z
```

6. Review the instructions in the pined cores

```bash
CPUMAX=`cat /proc/cpuinfo | grep processor | tail -n 1 | egrep -o [0-9]*$`
$ echo === NAME of IRQs for every CPU ===
$ for C in `seq 0 $CPUMAX` ; do
  echo -n CPU${C}:
  IRQS=`grep -H ${C}  /proc/irq/*/effective_affinity_list | grep :${C}$ | cut -f 4  -d '/'`
  for I in $IRQS ; do
    IRQNAME=`cat /proc/interrupts | grep \ ${I}\: | awk '{print $(NF)}'`
    echo -n " "${IRQNAME}
  done
  echo
done
=== NAME of IRQs for every CPU ===                                                                                                                            
CPU0: timer                                                                                                                                                   
CPU1:                                                                                                                                                         
CPU2: AMD-Vi                                                                                                                                                  
CPU3: AMD-Vi                                                                                                                                                 
CPU4: AMD-Vi                                                                                                                                                  
CPU5: AMD-Vi  
...
CPU71:
CPU72: megasas0-msix80                                                                                                                                        
CPU73: megasas0-msix81                                                                                                                                        
CPU74: megasas0-msix82                                                                                                                                        
CPU75: megasas0-msix83               
```

## Conclusions

In this article we have explored the essential steps for configuring and troubleshooting CPU isolation for low-latency workloads on OpenShift using the PerformanceProfile custom resource. Proper CPU isolation is critical for achieving deterministic performance in telco and high-performance computing workloads, where even minimal jitter and latency can significantly impact application behavior.

We demonstrated how to configure reserved and isolated CPUs by analyzing the NUMA topology and core distribution, ensuring that system tasks and user workloads are properly segregated. The PerformanceProfile provides a declarative way to apply complex kernel tuning and resource isolation automatically across the cluster nodes, simplifying what would otherwise be a complex manual configuration process.

Through the testpmd deployment example, we showed how to properly configure a DPDK application with CPU pinning and NUMA awareness. The troubleshooting steps outlined - from identifying the worker node and container PID, to monitoring task switches and IRQ affinity - provide a systematic approach to validate that CPU isolation is working as expected.

Key takeaways:
- Reserve adequate CPUs (including siblings) on both NUMA nodes for system and control plane operations
- Ensure the sum of reserved and isolated CPUs matches the total CPU count
- Use CPU pinning annotations and appropriate runtime class for workload pods
- Monitor task switches to detect unwanted scheduling on isolated cores
- Verify IRQ affinity to prevent hardware interrupts on isolated CPUs

Mastering these techniques enables you to deploy and maintain high-performance, low-latency workloads on OpenShift with confidence that your CPU isolation configuration is functioning correctly.

## Resources

* [CPU isolation: troubleshooting 201, with DPDK testpmd
](https://www.youtube.com/watch?v=94QPP1lvl_g)

* [Tuning nodes for low latency with the performance profile](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/scalability_and_performance/cnf-tuning-low-latency-nodes-with-perf-profile)

