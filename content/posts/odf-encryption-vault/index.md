---
title: "ODF Storage Encryption using HashiCorp Vault as KMS"
date: 2026-10-06T09:00:00+02:00
tags: [OpenShift,Storage,Security,SecDevOps]
draft: false
---

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Architecture Overview](#architecture-overview)
  - [Install and Configure Vault in the HUB Cluster](#install-and-configure-vault-in-the-hub-cluster)
    - [Install Vault with Helm](#install-vault-with-helm)
    - [Initialize Vault](#initialize-vault)
    - [Expose Vault to the Outside](#expose-vault-to-the-outside)
    - [Create the Vault Secret Backend for ODF](#create-the-vault-secret-backend-for-odf)
    - [Configure Vault Policy](#configure-vault-policy)
  - [Configure ODF on the Spoke Cluster](#configure-odf-on-the-spoke-cluster)
    - [Create ServiceAccount in the Tenant Namespace](#create-serviceaccount-in-the-tenant-namespace)
    - [Create ServiceAccount and RBAC for ODF](#create-serviceaccount-and-rbac-for-odf)
    - [Configure KMS Connectivity for ODF](#configure-kms-connectivity-for-odf)
    - [Configure Vault Kubernetes Authentication](#configure-vault-kubernetes-authentication)
    - [Create the Encrypted StorageClass](#create-the-encrypted-storageclass)
  - [Test the Encryption](#test-the-encryption)
  - [Conclusions](#conclusions)
  - [References](#references)

## Introduction

Data security is a critical concern in any production environment, especially when sensitive workloads run on shared infrastructure. OpenShift Data Foundation (ODF) supports Persistent Volume (PV) encryption at rest using an external Key Management System (KMS). One of the most common and powerful options for this is HashiCorp Vault.

In this post we will walk through the configuration required to enable PV encryption on an ODF-based Spoke cluster, using HashiCorp Vault deployed on a remote HUB cluster running Red Hat Advanced Cluster Management (ACM). This setup is common in hub-and-spoke architectures where you want centralised key management across multiple managed clusters.

## Architecture Overview

The setup involves two OpenShift clusters:

- **HUB cluster**: runs ACM and hosts a HashiCorp Vault instance in HA mode using the Raft storage backend. This cluster acts as the central KMS.
- **Spoke cluster**: runs ODF and is configured to use the Vault instance on the HUB as its KMS for encrypting PVs.

The Ceph CSI driver on the Spoke cluster authenticates to Vault using Kubernetes service account token review, allowing Vault to validate identities from the Spoke cluster's API server.

## Install and Configure Vault in the HUB Cluster

### Install Vault with Helm

All the steps in this section must be run against the **HUB cluster**.

First, add the HashiCorp Helm repository:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Create the namespace where Vault will be installed:

```bash
oc new-project vault
```

Then install Vault in HA mode with the Raft storage backend. The `global.openshift=true` flag adjusts the deployment to comply with OpenShift security constraints.

Note that the `server.image.repository` and `injector.image.repository` parameters must explicitly reference the Docker Hub registry (`docker.io`). Without this, Helm defaults to pulling images from the Red Hat Quay registry, which does not host the HashiCorp Vault images and will cause the pods to fail to start.

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --set "global.openshift=true" \
  --set "server.image.repository=docker.io/hashicorp/vault" \
  --set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
  --set "server.ha.enabled=true" \
  --set "server.ha.raft.enabled=true"
```

### Initialize Vault

Once the pods are running, initialize Vault. This generates the unseal keys and the initial root token. Store them securely — you will need them every time Vault restarts.

```bash
oc exec -it vault-0 -n vault -- vault operator init
```

Unseal `vault-0` using three different unseal keys from the output above:

```bash
oc exec -it vault-0 -n vault -- vault operator unseal
oc exec -it vault-0 -n vault -- vault operator unseal
oc exec -it vault-0 -n vault -- vault operator unseal
```

In some cases the other Raft members do not join the cluster automatically. If that happens, join them manually and unseal each one:

```bash
oc exec -it vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
oc exec -it vault-1 -n vault -- vault operator unseal
oc exec -it vault-1 -n vault -- vault operator unseal
oc exec -it vault-1 -n vault -- vault operator unseal

oc exec -it vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
oc exec -it vault-2 -n vault -- vault operator unseal
oc exec -it vault-2 -n vault -- vault operator unseal
oc exec -it vault-2 -n vault -- vault operator unseal
```

Verify that all pods are running and healthy:

```bash
$ oc -n vault get pods
NAME                                   READY   STATUS    RESTARTS   AGE
vault-0                                1/1     Running   0          34m
vault-1                                1/1     Running   0          34m
vault-2                                1/1     Running   0          34m
vault-agent-injector-94fc75565-qv6sc   1/1     Running   0          34m
```

### Expose Vault to the Outside

The Spoke cluster needs to reach the Vault API over HTTPS. Create an edge-terminated OpenShift Route to expose the Vault service:

```bash
oc create route edge vault-route --service=vault --port=http -n vault
```

Get the resulting URL:

```bash
$ oc get route vault-route -n vault -o jsonpath='{"https://"}{.spec.host}{"\n"}'
https://vault-route-vault.apps.acm.mycluster.mylab.lab
```

Note this URL — it will be used later when configuring the KMS connection details on the Spoke cluster.

### Create the Vault Secret Backend for ODF

The remaining Vault CLI commands in this section must be run from inside the `vault-0` pod. Open a shell into it first:

```bash
oc -n vault rsh vault-0
```

Enable a KV v2 secrets engine at the path `odf`. This is where Ceph CSI will store the per-volume encryption keys:

```bash
vault secrets enable -path=odf kv-v2
```

### Configure Vault Policy

Create a Vault policy that grants the CSI driver the necessary permissions to manage encryption keys under the `odf` path:

```bash
vault policy write ocp1-encrypt - <<EOF
path "sys/mounts" {
  capabilities = ["read"]
}

path "odf/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "odf/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
EOF
```

## Configure ODF on the Spoke Cluster

### Create ServiceAccount in the Tenant Namespace

On the Spoke cluster, create a dedicated ServiceAccount in the namespace where the encrypted PVCs will be consumed. Ceph CSI uses this ServiceAccount to authenticate to Vault:

```bash
$ cat <<EOF | oc create -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ceph-csi-vault-sa
EOF
```

### Create ServiceAccount and RBAC for ODF

ODF also needs a ServiceAccount in the `openshift-storage` namespace with permissions to perform token reviews. Vault will use this to validate Kubernetes service account tokens from the Spoke cluster:

```bash
$ cat <<EOF | oc create -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rbd-csi-vault-token-review
  namespace: openshift-storage
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rbd-csi-vault-token-review
rules:
  - apiGroups: ["authentication.k8s.io"]
    resources: ["tokenreviews"]
    verbs: ["create", "get", "list"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rbd-csi-vault-token-review
subjects:
  - kind: ServiceAccount
    name: rbd-csi-vault-token-review
    namespace: openshift-storage
roleRef:
  kind: ClusterRole
  name: rbd-csi-vault-token-review
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Configure KMS Connectivity for ODF

Edit the `csi-kms-connection-details` ConfigMap in the `openshift-storage` namespace to point the CSI driver at the Vault instance on the HUB cluster. The key `vault-tenant-sa` is the KMS identifier that will be referenced later by the StorageClass:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: csi-kms-connection-details
  namespace: openshift-storage
data:
  vault-tenant-sa: |-
    {
      "encryptionKMSType": "vaulttenantsa",
      "vaultAddress": "https://vault-route-vault.apps.acm.mycluster.mylab.lab:443",
      "vaultTLSServerName": "vault-route-vault.apps.acm.mycluster.mylab.lab",
      "vaultBackendPath": "odf",
      "vaultCAFromSecret": "vault-cacert",
      "tenantSAName": "ceph-csi-vault-sa"
    }
```

The `vaultCAFromSecret` field references a Secret named `vault-cacert` in `openshift-storage` that must contain the CA certificate used to sign the Vault Route TLS certificate. To obtain it, run the following command against the Vault Route hostname to download the full certificate chain:

```bash
openssl s_client -showcerts -connect vault-route-vault.apps.acm.mycluster.mylab.lab:443 \
  </dev/null 2>/dev/null > vault_chain.pem
```

Open `vault_chain.pem` and extract the last certificate block (the CA certificate) into a separate file named `ingress-cacert.crt`. Then create the Secret in the `openshift-storage` namespace on the Spoke cluster:

```bash
oc create secret generic vault-cacert \
  --from-file=ingress-cacert.crt \
  -n openshift-storage
```

### Configure Vault Kubernetes Authentication

This step links the Spoke cluster's Kubernetes API to Vault, enabling token-based authentication. Run the following commands from the Spoke cluster context to extract the required values:

```bash
# From the Spoke (ODF) cluster
SA_JWT_TOKEN=$(oc -n openshift-storage get secret rbd-csi-vault-token-review-token \
  -o jsonpath="{.data['token']}" | base64 --decode; echo)

SA_CA_CRT=$(oc -n openshift-storage get secret rbd-csi-vault-token-review-token \
  -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

OCP_HOST=$(oc config view --minify --flatten \
  -o jsonpath="{.clusters[0].cluster.server}")
```

Then open a shell into the `vault-0` pod on the HUB cluster and run the following commands. If the environment variables set in the previous step are not available inside the pod, replace them with the literal values obtained earlier:

```bash
oc -n vault rsh vault-0
```

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="$OCP_HOST" \
  kubernetes_ca_cert="$SA_CA_CRT"
```

Create a Vault Kubernetes auth role that maps the `ceph-csi-vault-sa` ServiceAccount to the `ocp1-encrypt` policy:

```bash
vault write "auth/kubernetes/role/csi-kubernetes" \
  bound_service_account_names="ceph-csi-vault-sa" \
  bound_service_account_namespaces=default \
  policies=ocp1-encrypt
```

### Create the Encrypted StorageClass

Create a StorageClass that instructs the Ceph RBD CSI driver to encrypt volumes using the KMS configuration defined above. The key parameters are `encrypted: "true"` and `encryptionKMSID: vault-tenant-sa`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ocs-storagecluster-ceph-rbd-encrypted
  annotations:
    description: "Provides RWO Filesystem volumes, and RWO and RWX Block volumes encrypted"
parameters:
  clusterID: openshift-storage
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: openshift-storage
  csi.storage.k8s.io/fstype: ext4
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: openshift-storage
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: openshift-storage
  encrypted: "true"
  encryptionKMSID: vault-tenant-sa
  imageFeatures: layering,deep-flatten,exclusive-lock,object-map,fast-diff
  imageFormat: "2"
  pool: ocs-storagecluster-cephblockpool
provisioner: openshift-storage.rbd.csi.ceph.com
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
```

## Test the Encryption

Deploy a PVC using the new encrypted StorageClass and a test pod to confirm the end-to-end flow works correctly:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: encrypted-rbd-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ocs-storagecluster-ceph-rbd-encrypted
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: app-using-encrypted-pvc
spec:
  containers:
    - name: app-container
      image: registry.access.redhat.com/ubi8/ubi:latest
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: secure-storage
          mountPath: /data
  volumes:
    - name: secure-storage
      persistentVolumeClaim:
        claimName: encrypted-rbd-pvc
```

Apply the manifest and verify the PVC is bound and the pod is running:

```bash
oc apply -f pod-pvc-example.yaml

$ oc get pvc encrypted-rbd-pvc
NAME                STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS                               AGE
encrypted-rbd-pvc   Bound    ...      5Gi        RWO            ocs-storagecluster-ceph-rbd-encrypted      ...

$ oc get pod app-using-encrypted-pvc
NAME                      READY   STATUS    RESTARTS   AGE
app-using-encrypted-pvc   1/1     Running   0          ...
```

If the PVC binds successfully and the pod reaches `Running` state, the encryption setup is working correctly. You can also verify in Vault that a new key has been created under the `odf` secrets engine path.

## Conclusions

This configuration allows centralising encryption key management for ODF PVs across multiple Spoke clusters using a single Vault instance running on the HUB cluster. The Kubernetes auth method in Vault provides a clean, token-based authentication flow without needing to distribute static credentials to each Spoke cluster.

Key takeaways:

- Vault runs in HA mode with Raft storage on the HUB cluster, exposed via an OpenShift Route.
- The Ceph CSI driver on the Spoke uses the `vaulttenantsa` KMS type, authenticating via a dedicated ServiceAccount.
- Vault's Kubernetes auth backend is configured with the Spoke cluster's API server details to validate tokens.
- Each new encrypted PV results in a corresponding encryption key stored in Vault under the `odf` path.

## References

- [Red Hat ODF official documentation — Storage class for PV encryption](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/managing_and_allocating_storage_resources/storage-class-for-persistent-volume-encryption_rhodf)
- [Red Hat Developers — OpenShift Data Foundation and HashiCorp Vault: Securing Data](https://developers.redhat.com/articles/2025/06/18/openshift-data-foundation-and-hashicorp-vault-securing-data#5_steps_to_deploy_vault_on_openshift)
