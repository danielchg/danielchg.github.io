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
    - [Configure credentials to pull OCP images](#configure-credentials-to-pull-ocp-images)
    - [Deploy disconnected registry](#deploy-disconnected-registry)
    - [Create mirror to file](#create-mirror-to-file)
    - [Create mirror from file to registry](#create-mirror-from-file-to-registry)
    - [ImageContentSourcePolicies objects](#imagecontentsourcepolicies-objects)
  - [Conclusions](#conclusions)
  - [Links](#links)

## Context

At the moment of this writing I'm working in the Telco 5G area at Red Hat, where we works mostly with bare metal  deployments of OpenShift. These deployments are focused on clusters that will be placed in remote locations with no Internet access due to security constrains and/or infrastructure designs.

Currently the deployment of OpenShift require of access to [Quay.io](https://quay.io/), because all their components are container images. This is a limitaion for the scenario that I just described before. Hence this is the reason why it is required to create a mirror in a disconnedted registry with the needed images to install OpenShift, from where to install a bare metal cluster without Internet access.

All the command line examples are run on a RHEL machine, how to do it with other OS is not the goal of this article.

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
Username: <YOUR_USERNAME>
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
3. The channel to retrieve the OpenShift Container Platform images from.
4. The **OLM** catalog source that we are going to use.
5. Based on the previous catalog, winthin this field is spected an array with all the operators to be mirrored.
6. This is the  name of operator.
7. The channel of the operator.

In the example above it is configured to create a mirror of the whole **OCP 4.11** and only the **serverless-operator** from **OLM**

## Create a mirror

When you are going to create a mirror to deploy a disconnected environment there are different ways to do it. The best way for you depend of the your usecase. 

- **Partially Disconnected:** You can create a mirror directly from the public Quay.io to your disconnected registry, what is faster because you only need one step to create the mirror. 

- **Fully Disconnected:** If you have a very restrict network, and the servers where the cluster is going to be deployed don't have Internet access, you can create in a first step a mirror to a file, and later on copy this file to the place where the disconnected registry is. This last case is what I'm going to descrebe in this article. I think that is the most complex use case and maybe more use full to have a better understanding about how this procedure works.

Below in the diagram are shown the steps needed to create a Fully Disconnected mirror.

![Disconnected registry](/disconnected-registry.png)

1. Create a mirror from Quay.io to a local file in your workstation.
2. Copy the mirror file from your workstation to a server with access to the disconnected registry with Internet connection restrictions
3. Import the mirror from file to the disconnected registry.

### Configure credentials to pull OCP images

In order to allow `oc-mirror` to pull the OCP images from the Red Hat registries, you need to configure your credentials. 

First of all you need to create a **Red Hat** account in [this link](https://www.redhat.com/en/technologies/cloud-computing/openshift/try-it), select **Self-managed** option and follow the required steps to create an account.

Once you have an account you can download your pull secrets from [here](https://console.redhat.com/openshift/downloads#tool-pull-secret). Now you have to add this information to your `podman` auth configuration with the below command.

```bash
cat pull-secrets.txt | jq > $XDG_RUNTIME_DIR/containers/auth.json
```

### Deploy disconnected registry

In order to follow this tutorial it is required a running registry where we are going to push all the mirror images. Just for testing purpose I have deployed it with [this script](https://github.com/danielchg/oc-mirror-procedure/blob/main/deploy_registry.sh). There are multiples ways to deploy a registry, for instance Red Had has a light version of Quay.io for this purpose, that is documented [in here](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-creating-registry.html).

You can follow the below commands if you are running this on RHEL or Fedora. 

```bash
git clone https://github.com/danielchg/oc-mirror-procedure.git
cd oc-mirror-procedure/
./deploy_registry.sh
```

This script will deploy a registry that will listen on port `5000/TCP`, with TLS support and authentication with credentials `dummy/dummy`. In order to check the installation follow the below commands, be aware that an entry is added to the `/etc/hosts` due to the use of TLS. For this tutorial we are going to use the same machine for what is called Workstatin, Installer Machine and Disconnected Registry in the diagram above, but in a real scenario these should be different hosts.

```bash
# Check if the container with the registry is running
$ podman ps
CONTAINER ID  IMAGE                         COMMAND               CREATED        STATUS            PORTS       NAMES
37670395eb29  docker.io/library/registry:2  /etc/docker/regis...  3 seconds ago  Up 4 seconds ago              registry

# Add entry to the /etc/hosts
$ echo "127.0.0.1 registry.local" | sudo tee -a /etc/hosts
127.0.0.1 registry.local

# Login to the registry
$ podman login registry.local:5000
Username: dummy
Password: 
Login Succeeded!
```

### Create mirror to file

At this moment we should have in our Fedora machine the `oc-mirror` installed, and a disconnected registry running. The next step is to create a mirror from Quay.io to a file. We are going to use the file generated by the `oc-mirror init` command that we have run before. Be aware that we required an account with permission to pull the OCP container images from registry.redhat.io, if you don't have already an account, please visit the [Red Hat site](https://sso.redhat.com/auth/realms/redhat-external/login-actions/registration?client_id=rh_product_trials&tab_id=1Ks3qWXNdKY) in order to create it. 

```bash
$ podman login registry.redhat.io
Username: dchavero
Password: 
Login Succeeded!
```
Once you have loged in registry.redhat.io we can run the `oc-mirror` command.

```bash
cd ~/oc-mirror-demo
/usr/sbin/oc-mirror --config imagesetconfig.yaml file:///root/oc-mirror-demo/archives
Creating directory: /root/oc-mirror-demo/archives/oc-mirror-workspace/src/publish
Creating directory: /root/oc-mirror-demo/archives/oc-mirror-workspace/src/v2
Creating directory: /root/oc-mirror-demo/archives/oc-mirror-workspace/src/charts
Creating directory: /root/oc-mirror-demo/archives/oc-mirror-workspace/src/release-signatures
No metadata detected, creating new workspace
wrote mirroring manifests to /root/oc-mirror-demo/archives/oc-mirror-workspace/operators.1662238754/manifests-redhat-operator-index

To upload local images to a registry, run:

	oc adm catalog mirror file://redhat/redhat-operator-index:v4.11 REGISTRY/REPOSITORY

[...]

info: Mirroring completed in 2m25.38s (130.8MB/s)
Creating archive /root/oc-mirror-demo/archives/mirror_seq1_000000.tar
```

The output should be something similar to the above, only the first and last lines are shown, the rest has been ommited due to de ammount of lines.

As you can see in the last line of the log the path to the file with the mirror is `/root/oc-mirror-demo/archives/mirror_seq1_000000.tar`, hence this is the file that we need to copy to the restricted location whith access to the disconnected registry. The that you copy this file to that place depend of your use case and your security requirements, the only important thing is to copy it to that place.

The directory structure after the execution should be something like below.

```bash
$ tree .
.
├── archives
│   ├── mirror_seq1_000000.tar
│   └── oc-mirror-workspace
├── imagesetconfig.yaml
└── publish
```

Also there are log file `.oc-mirror.log` where is saved all the output.

### Create mirror from file to registry



### ImageContentSourcePolicies objects

## Conclusions

## Links

- [OCP official documentation](https://docs.openshift.com/container-platform/4.10/installing/disconnected_install/installing-mirroring-installation-images.html)
- [Mirror Registry](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-creating-registry.html)
- [Get pull secrets](https://console.redhat.com/openshift/downloads#tool-pull-secret)
- 