---
title: "OpenShift hardening using the Compliance Operator"
date: 2023-01-24T17:45:23+01:00
tags: [SecDevOps,OpenShift,Security]
draft: false
---

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Compliance Operator](#compliance-operator)
    - [Requirements](#requirements)
    - [Installation](#installation)
    - [Configure and run scans](#configure-and-run-scans)
      - [Create ScanSettings](#create-scansettings)
      - [Create ScanSettingBinding](#create-scansettingbinding)
    - [Get results](#get-results)
    - [Remediations](#remediations)
  - [Conclusions](#conclusions)
  - [Links](#links)


## Introduction

When we talk about Cyber Security, there are a lot of aspects to be focused on to keep our services secure, and from the point of view of the platform, during all Internet years, the industry has created some standards in order to keep minimum requirements so that our infrastructure is secure enough to prevent unauthorized access or DoS.

For Kubernetes/OpenShift, there are existing specifications on how the clusters needs to be configured to minimize these security risks. Some of these standards are:

* CIS Benchmarks
* ACSC
* NIST SP-800-53
* NERC CIP
* PCI

All these standards are trying to ensure that the configuration of the platform is secure to run workloads on production environments. Hence, to guarantee that our Kubernetes/OpenShift cluster is secure, we can run one or more of these benchmarks, and apply the remediations recommended. You can choose the profiles that are appropriate for your cluster depending on your use case.

In the case of Kubernetes/OpenShift clusters we must provide two kinds of benchmarks, one for the operating system and another one for the control plane.

In this post, we are going to use a Single Node OpenShift running with version `v4.11.22` where we are going to install the Compliance Operator, and its required dependencies. As part of this article, we will create a basic configuration to run a compliance scan, understand the results and the remediations. We won't cover each part of the Operator or review all the features as this is meant to be an introduction to the value of this operator and how to quickly run a first scan to perform hardening.

## Compliance Operator

This operator tries to make it easy to scan our cluster and check the status of the compliance based on some standards profiles, like the ones described above. It is based on the open-source tool [OpenSCAP](https://www.open-scap.org/tools/openscap-base/). For more information about the Compliance Operator you can visit the [official documentation](https://docs.openshift.com/container-platform/4.12/security/compliance_operator/compliance-operator-understanding.html). 

### Requirements

Before installing the Compliance Operator, we need an OpenShift cluster running with version 4.11+. 

A default `StorageClass` is also required, to allow the creation of PVCs to persist the results of the scans. In the case of our Single Node OpenShift deployment, we are using the LVMO operator, but in a multi nodes cluster, ODF can be used instead. Installation of those operators is outside the scope of this blog post, and left as an exercise to the reader.

### Installation

The **Compliance Operator** can be installed using OLM and is available on the OperatorHub, so the procedure is the same as installing any other operator on OpenShift

We create a `Namespace`, an `OperatorGroup` and a `Subscription` object. Below are the `YAML` files and commands used to create those objects on our cluster:

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
Command to create the `Subscription` object.

```bash
oc apply -f subscription.yaml
```

Once those objects are applied to our cluster, we can check if the operator is installed, for that matter, a couple of things can be checked. The first one is the `ClusterServiceVersion`.

```bash
$ oc -n openshift-compliance get csv
NAME                          DISPLAY               VERSION   REPLACES   PHASE
compliance-operator.v0.1.59   Compliance Operator   0.1.59               Succeeded
```

The second one is listing all the pods running in the `openshift-compliance` Namespace, the output should be something similar as below.

```bash
$ oc -n openshift-compliance get pods
NAME                                              READY   STATUS      RESTARTS       AGE
compliance-operator-6c9f9bcc78-jb6nm              1/1     Running     18 (21h ago)   5d19h
ocp4-openshift-compliance-pp-bf7f56444-mcqd2      1/1     Running     7              7d19h
rhcos4-openshift-compliance-pp-7bf7d6bd96-nw2lf   1/1     Running     6              7d19h
```

If the above checks fail, follow [this troubleshooting guide for OLM](https://access.redhat.com/articles/5434131).

### Configure and run scans

Awesome! At this point, we have our OCP cluster running with the **Compliance Operator** running. Now it is time to see which compliance profiles are available, and how to configure their execution.

First, we check which compliance profiles are available, getting the list of them with the `profiles.compliance.openshift.io` CRD. Run the below command, and you should get an output similar to the following one.

```bash
$ oc get profiles.compliance.openshift.io 
NAME                 AGE
ocp4-cis             7d19h
ocp4-cis-node        7d19h
ocp4-e8              7d19h
ocp4-high            7d19h
ocp4-high-node       7d19h
ocp4-moderate        7d19h
ocp4-moderate-node   7d19h
ocp4-nerc-cip        7d19h
ocp4-nerc-cip-node   7d19h
ocp4-pci-dss         7d19h
ocp4-pci-dss-node    7d19h
rhcos4-e8            7d19h
rhcos4-high          7d19h
rhcos4-moderate      7d19h
rhcos4-nerc-cip      7d19h
```

As you can see, there are profiles available based on the standards listed in the introduction. Here, we will run profiles `ocp4-cis`, `ocp4-cis-node` and `ocp4-moderate` for the control plane scans, and `rhcos4-moderate` for the OS scans. 

How this operator is configured is similar to how **RBAC** is configured, in **RBAC** we define `Users` and `Roles`, and after, we create a `RoleBinding`, in the case of the **Compliance Operator** we are going to define `ScanSettings` and we have the listed above `profiles`, and later on we are going to create a `ScanSettingBinding` where we configure the run of the scan. Let's see how to configure our scan to run the desired `profiles`.

#### Create ScanSettings

The `ScanSettings` describes which kind of node is going to run the pods for the scan, the persistence where the results are going to be saved, the schedule when to scan will be run, and also the two last lines that are commented in this example define whether we want that the results with FAIL status get automatically remediated. Once the scan is run, the failed results have a remediation object with a `MachineConfig` per result to remediate those with auto remediation set.

**scansettings.yaml**
```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSetting
metadata:
  generation: 1
  name: first-scan
  namespace: openshift-compliance
rawResultStorage:
  nodeSelector:
    node-role.kubernetes.io/master: ""
  pvAccessModes:
  - ReadWriteOnce
  rotation: 3
  size: 1Gi
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
    operator: Exists
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
  - effect: NoExecute
    key: node.kubernetes.io/unreachable
    operator: Exists
    tolerationSeconds: 300
  - effect: NoSchedule
    key: node.kubernetes.io/memory-pressure
    operator: Exists
roles:
- master
scanTolerations:
- operator: Exists
schedule: 41 12 * * *
showNotApplicable: false
strictNodeScan: true
# autoApplyRemediations: true
# autoUpdateRemediations: true
```
Create the `ScanSettings` object running the below command.

```bash
oc apply -f scansettings.yaml
```

Verify that our `ScanSettings` have been created properly. The output should be similar to the below capture, be aware that there are two faulty `ScanSettings`, one with auto remediation enabled and another without it. 

```bash
$ oc -n openshift-compliance get scansettings
NAME                 AGE
default              8d
default-auto-apply   8d
first-scan           7d22h
```

#### Create ScanSettingBinding

As mentioned before, the configuration of this operator is pretty similar to how one configures **RBAC**, you create some objects and later on, you create a binding of them. Now we already have the `ScanSettings` and the pre-installed `profiles`, so the next step is to create a `ScanSettingBinding` to describe which `profiles` will be used for the scan, matching with given `ScanSettings`. Be aware that we cannot create a `ScanSettingBinding` for `profiles` that are not of the same kind, so we have to create one `ScanSettingBinding` for the scan of the control plane and another for the OS of the hosts.

**scansettingbinding-ocp4.yaml**
```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: test-scan-ocp4
  namespace: openshift-compliance
profiles:
  - name: ocp4-cis
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
  - name: ocp4-cis-node
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
  - name: ocp4-moderate
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: first-scan
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
```

**scansettingbinding-rhcos4.yaml**
```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: test-scan-rhcos
  namespace: openshift-compliance
profiles:
  - name: rhcos4-moderate
    kind: Profile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: first-scan
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
```

We apply those to `ScanSettingBinding` objects.

```bash
oc apply -f scansettingbinding-ocp4.yaml -f scansettingbinding-rhcos4.yaml
```

Once the `ScanSettingBinding` is applied, the scan will start at the scheduled date and time. To validate that the scan is running, execute the below command, be aware that the capture is done when the scans are finished, if the scans are in progress, the status is **RUNNING** instead of **DONE**.

```bash
$ oc -n openshift-compliance get compliancescans.compliance.openshift.io 
NAME                     PHASE   RESULT
ocp4-cis                 DONE    NON-COMPLIANT
ocp4-cis-node-master     DONE    NON-COMPLIANT
ocp4-moderate            DONE    NON-COMPLIANT
rhcos4-moderate-master   DONE    NON-COMPLIANT
```

The run of the scan are jobs running in the `openshift-compliance` Namespace, you can get the pods list for troubleshooting the scan.

```bash
$ oc -n openshift-compliance get pods
NAME                                              READY   STATUS      RESTARTS         AGE
compliance-operator-6c9f9bcc78-jb6nm              1/1     Running     21 (3h33m ago)   6d
test-scan-ocp4-rerunner-27908349-sql4x            0/1     Completed   0                45h
test-scan-ocp4-rerunner-27909401-2bqvr            0/1     Completed   0                27h
test-scan-ocp4-rerunner-27910841-84jll            0/1     Completed   0                3h40m
test-scan-rhcos-rerunner-27908349-bqmzd           0/1     Completed   0                45h
test-scan-rhcos-rerunner-27909401-bzvpw           0/1     Completed   0                27h
test-scan-rhcos-rerunner-27910841-m44gd           0/1     Completed   0                3h40m
ocp4-openshift-compliance-pp-bf7f56444-mcqd2      1/1     Running     8                8d
rhcos4-openshift-compliance-pp-7bf7d6bd96-nw2lf   1/1     Running     7                8d
```

### Get results

OK! So far so good, we already have run the scans, but the goal of this is to understand the security compliance of our cluster, and remediate the configuration if necessary. Let's get the results of the scans querying the CRD `compliancecheckresults.compliance.openshift.io`, this will provide a list of all the reports generated by the scan.

```bash
$ oc -n openshift-compliance get compliancecheckresults.compliance.openshift.io
NAME                                                                                                STATUS   SEVERITY
ocp4-cis-accounts-restrict-service-account-tokens                                                   MANUAL   medium
ocp4-cis-accounts-unique-service-account                                                            MANUAL   medium
ocp4-cis-api-server-admission-control-plugin-alwaysadmit                                            PASS     medium
ocp4-cis-api-server-admission-control-plugin-alwayspullimages                                       PASS     high
ocp4-cis-api-server-admission-control-plugin-namespacelifecycle                                     PASS     medium
ocp4-cis-api-server-admission-control-plugin-noderestriction                                        PASS     medium
ocp4-cis-api-server-admission-control-plugin-scc                                                    PASS     medium
ocp4-cis-api-server-admission-control-plugin-securitycontextdeny                                    PASS     medium
ocp4-cis-api-server-admission-control-plugin-service-account                                        PASS     medium
ocp4-cis-api-server-anonymous-auth                                                                  PASS     medium
ocp4-cis-api-server-api-priority-flowschema-catch-all                                               PASS     medium
ocp4-cis-api-server-audit-log-maxbackup                                                             PASS     low
ocp4-cis-api-server-audit-log-maxsize                                                               PASS     medium
ocp4-cis-api-server-audit-log-path                                                                  PASS     high
ocp4-cis-api-server-profiling-protected-by-rbac                                                     PASS     medium
ocp4-cis-api-server-request-timeout                                                                 PASS     medium
ocp4-cis-api-server-service-account-lookup                                                          PASS     medium
ocp4-cis-api-server-service-account-public-key                                                      PASS     medium
ocp4-cis-api-server-tls-cert                                                                        PASS     medium
ocp4-cis-api-server-tls-cipher-suites                                                               PASS     medium
ocp4-cis-api-server-tls-private-key                                                                 PASS     medium
ocp4-cis-api-server-token-auth                                                                      PASS     high
ocp4-cis-audit-log-forwarding-enabled                                                               FAIL     medium
ocp4-cis-audit-profile-set                                                                          FAIL     medium
ocp4-cis-configure-network-policies                                                                 PASS     high
ocp4-cis-configure-network-policies-namespaces                                                      FAIL     high

```

Some of the output have been removed for clarity, as there are more than 500 results, but in the capture we can see different kinds of reports, with different statuses and severities.

As we saw in the previous section, the output of the `compliancescans` was that the result of each scan was **NON-COMPLIANT**, which means that we have at least one check that in **FAIL** status. If you take a look to the results capture, you can find multiples results with status **FAIL**. 

Now, what is important for us, are the **FAIL** results, to get only these results we use the below command:

```bash
$ oc -n openshift-compliance get compliancecheckresults -l 'compliance.openshift.io/check-status in (FAIL),compliance.openshift.io/automated-remediation'
NAME                                                     STATUS   SEVERITY
ocp4-cis-audit-profile-set                               FAIL     medium
rhcos4-moderate-master-configure-usbguard-auditbackend   FAIL     medium
rhcos4-moderate-master-service-usbguard-enabled          FAIL     medium
rhcos4-moderate-master-usbguard-allow-hid-and-hub        FAIL     medium
```

That's fine, we can see what is wrong in our configuration, but how do we understand what each scan means. On each standard, all the checks have an explanation about why this misconfiguration is a security risk, and also provide a remediation. In order to see this information, we can get it from the content of each result object, the example below shows how to see those details for one of the failed results.

```bash
$ oc -n openshift-compliance get compliancecheckresults.compliance.openshift.io ocp4-cis-audit-profile-set -oyaml | yq .description
Ensure that the cluster's audit profile is properly set
Logging is an important detective control for all systems, to detect potential
unauthorised access.
```

Also, we can get the remediation information from this object.

```bash
$ oc -n openshift-compliance get compliancecheckresults.compliance.openshift.io ocp4-cis-audit-profile-set -oyaml | yq .instructions
Run the following command to retrieve the current audit profile:
$ oc get apiservers cluster -ojsonpath='{.spec.audit.profile}'
Make sure that the returned profile matches the one that should be used.
```

In the next section, we are going to go more in detail about remediations, but it is important to see how to get this information from the results, because the failed results are recommendations, and these recommendations may be incompatible with our environment because of some other requirements.

Just in case you need to share this report with someone else like I had to, I wrote the next script to export the failed results to a `.csv` file.

```bash
#!/bin/sh

CHECKS=$(oc get compliancecheckresults.compliance.openshift.io  | grep FAIL | cut -f1  -d' ')

echo "NAME; DESCRIPTION; SEVERITY" > results.csv
for i in $CHECKS 
do
	DESCRIPTION=$(oc get compliancecheckresults.compliance.openshift.io $i -o jsonpath='{.description}')
	SEVERITY=$(oc get compliancecheckresults.compliance.openshift.io $i -o jsonpath='{.severity}')
	echo "$i; \"$DESCRIPTION\"; $SEVERITY" >> results.csv
done
```

### Remediations

Eventually, we are installing this operator and running all these scans to try to configure our cluster more securely, and so far we just know that there are some changes to do in our configuration to fit the desired standards. This is where the power of this operator lies, since for each failed result, the operator also creates a CRD called `complianceremediations.compliance.openshift.io` which allows the operator to apply the remediation in our cluster. Those auto remediations are not applicable for results with status **MANUAL**, so those will require manual intervention to be solved.

The next command lists all the `complianceremediations` and the status. In the capture, all the auto remediation have been applied already, which is why the status of all is `Applied`, but if you have run the scan with the `ScanSettings` without enabling the `autoApplyRemediations` option, you will see a different output.

```bash
$ oc get complianceremediations.compliance.openshift.io | more
NAME                                                                                                STATE
ocp4-cis-api-server-encryption-provider-cipher                                                      Applied
ocp4-cis-api-server-encryption-provider-config                                                      Applied
ocp4-cis-audit-profile-set                                                                          Applied
ocp4-cis-kubelet-enable-streaming-connections                                                       Applied
ocp4-cis-kubelet-enable-streaming-connections-1                                                     Applied
ocp4-cis-kubelet-eviction-thresholds-set-hard-imagefs-available                                     Applied
ocp4-cis-kubelet-eviction-thresholds-set-hard-imagefs-available-1                                   Applied
ocp4-cis-kubelet-eviction-thresholds-set-hard-imagefs-available-2                                   Applied
ocp4-cis-kubelet-eviction-thresholds-set-hard-imagefs-available-3                                   Applied
ocp4-cis-kubelet-eviction-thresholds-set-hard-imagefs-inodesfree                                    Applied
ocp4-cis-kubelet-eviction-thresholds-set-hard-imagefs-inodesfree-1                                  Applied
```

Let's take a look at the content of one of the `complianceremediations` CRs:

```bash
$ oc get complianceremediations.compliance.openshift.io rhcos4-moderate-master-audit-rules-dac-modification-chmod -oyaml 
apiVersion: compliance.openshift.io/v1alpha1
kind: ComplianceRemediation
metadata:
  creationTimestamp: "2023-01-18T11:05:06Z"
  generation: 2
  labels:
    compliance.openshift.io/scan-name: rhcos4-moderate-master
    compliance.openshift.io/suite: esmb-rhcos
  name: rhcos4-moderate-master-audit-rules-dac-modification-chmod
  namespace: openshift-compliance
  ownerReferences:
  - apiVersion: compliance.openshift.io/v1alpha1
    blockOwnerDeletion: true
    controller: true
    kind: ComplianceCheckResult
    name: rhcos4-moderate-master-audit-rules-dac-modification-chmod
    uid: 83639492-6c8e-4685-8ec2-4f07a67af700
  resourceVersion: "5574521"
  uid: f8d08dae-6132-460a-85ad-f8ffc8d79042
spec:
  apply: true
  current:
    object:
      apiVersion: machineconfiguration.openshift.io/v1
      kind: MachineConfig
      spec:
        config:
          ignition:
            version: 3.1.0
          storage:
            files:
            - contents:
                source: data:,-a%20always%2Cexit%20-F%20arch%3Db32%20-S%20chmod%20-F%20auid%3E%3D1000%20-F%20auid%21%3Dunset%20-F%20key%3Dperm_mod%0A-a%20always%2Cexit%20-F%20arch%3Db64%20-S%20chmod%20-F%20auid%3E%3D1000%20-F%20auid%21%3Dunset%20-F%20key%3Dperm_mod%0A
              mode: 420
              overwrite: true
              path: /etc/audit/rules.d/75-chmod_dac_modification.rules
  outdated: {}
  type: Configuration
status:
  applicationState: Applied
```

As you can see in the capture, eventually the `ComplianceRemediation` object will apply a `MachineConfig` to configure our cluster with the recommendations. Hence, for each remediation we can get the `MachineConfig` object that solves the problem. If desired, we can get these objects to be applied to another cluster that is not running the Compliance Operator. The command below shows how to get this `MachineConfig` object from the `ComplianceRemediation` object.

```bash
$ oc get complianceremediations.compliance.openshift.io rhcos4-moderate-master-audit-rules-dac-modification-chmod -oyaml | yq .spec.current.object
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
spec:
  config:
    ignition:
      version: 3.1.0
    storage:
      files:
        - contents:
            source: data:,-a%20always%2Cexit%20-F%20arch%3Db32%20-S%20chmod%20-F%20auid%3E%3D1000%20-F%20auid%21%3Dunset%20-F%20key%3Dperm_mod%0A-a%20always%2Cexit%20-F%20arch%3Db64%20-S%20chmod%20-F%20auid%3E%3D1000%20-F%20auid%21%3Dunset%20-F%20key%3Dperm_mod%0A
          mode: 420
          overwrite: true
          path: /etc/audit/rules.d/75-chmod_dac_modification.rules
```

## Conclusions

Security is something very important in production environments. From the platform perspective, the described standards and tools help to keep a better configuration, and a more robust environment where we can run our workloads.

The Compliance Operator helps us getting those misconfigurations and, understand and apply remediations to keep a more secure environment, all of this only through Kubernetes native objects. Additionally, the remediation can be listed and exported as `MachineConfig` objects to be applied to a different cluster without the Compliance Operator running.

## Links

- [Compliance Operator official documentation](https://docs.openshift.com/container-platform/4.12/security/compliance_operator/compliance-operator-understanding.html)
- [OpenSCAP tool](https://www.open-scap.org/tools/openscap-base/)
- [CIS benchmarks](https://www.cisecurity.org/cis-benchmarks/)
