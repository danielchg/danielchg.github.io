---
title: "Create an OCP and OLM mirror with oc-mirror plugin"
toc: true
date: 2022-08-29T17:44:18+02:00
tags: [devops,openshift]
draft: false
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

At the moment of this writing, I'm working in the Telco 5G area at Red Hat, where we work mostly deploying OCP (OpenShift Container Platform) on bare metal. These deployments are focused on clusters that will be placed in remote locations with no Internet access due to security constraints and/or network designs.

To install an OCP cluster needs Internet access to pull container images from registries managed by Red Hat, because all the OCP components are container images. This is a limitation of the scenario described before. And this is the reason why it is required to create a mirror in a disconnected registry with the needed images to install OpenShift, from where to install a bare metal cluster without Internet access.

All the command line examples are run on a RHEL machine, how to do it with other OS is not the goal of this article.

The procedure refers to a possible production solution with multiple hosts in different networks with access restrictions, but for learning purposes, it is described how to do it in a single host.

## oc-mirror plugin

The newest version of OCP at this moment is **4.11**. This version comes with a lot of new interested features, and one of this features is the `oc-mirror` plugin.

Until now, to create a mirror of the OCP and OLM (Operator Lifecycle Manager) repositories, you had to use a sub-command of the `oc` CLI. The workflow to create the mirror and maintain it synced was very tedious (you can read the whole procedure in the [OCP official documentation](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-installation-images.html)). This is the reason why Red Hat has made an effort to simplify this procedure creating this plugin for `oc`. 

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

Also there are a log file `.oc-mirror.log` where is saved all the output.

### Create mirror from file to registry

In my lab I'm going to run this part of the procedure in the same machine, but in a real production environment you should copy the generated file `mirror_seq1_000000.tar` to the Installer Machine, from where the below command should be run to import the images in the Disconnected Registry. I know that I already told about this, but it is important that these aspects of the lab vs production are clear for a better understanding.

In order to import the images from the mirror file to our Disconnected Registry we just need to run the below command from the same folder as the before step, but actually you only need access to the `mirror_seq1_000000.tar` for this step, the rest of the content of the folder are important for future runs to create the mirror to file.

```bash
$ /usr/sbin/oc-mirror --from ./archives/mirror_seq1_000000.tar docker://registry.local:5000/oc-mirror --dest-skip-tls
Checking push permissions for registry.local:5000
Publishing image set from archive "./archives/mirror_seq1_000000.tar" to registry "registry.local:5000"
registry.local:5000/
  oc-mirror/openshift/release
    blobs:
      file://openshift/release sha256:545277d800059b32cf03377a9301094e9ac8aa4bb42d809766d7355ca9aa8652 1.753KiB
      file://openshift/release sha256:c052f5b9bb68f5cf7676f99f56a53f673d0c25ce2109d596148a5eea4c8e68e4 5.885KiB
      file://openshift/release sha256:8471560c450b0951780fd61a8df6c1b98154fde18036f7c091de2316da33bf6a 11.47MiB
      file://openshift/release sha256:e46a55fccddefc1d37574b70cd4e5c54fc3d795c51543b729d6c93051e1be9e3 35.43MiB
      file://openshift/release sha256:630499beaeb04bcb68b94f4a413a3626b152e3c211d5fbab3a2813047baaf079 57.83MiB
      file://openshift/release sha256:f70d60810c69edad990aaf0977a87c6d2bcc9cd52904fa6825f08507a9b6e7bc 74.8MiB
    manifests:
      sha256:b4023de0e31fc7d448254794512f6b1e0c01226953063d253238aa051761a683 -> 4.11.1-x86_64-cloud-credential-operator
  stats: shared=0 unique=6 size=179.5MiB ratio=1.00

phase 0:
  registry.local:5000 oc-mirror/openshift/release blobs=6 mounts=0 manifests=1 shared=0

info: Planning completed in 20ms
uploading: registry.local:5000/oc-mirror/openshift/release sha256:630499beaeb04bcb68b94f4a413a3626b152e3c211d5fbab3a2813047baaf079 57.83MiB

[...]

phase 0:
  registry.local:5000 oc-mirror/openshift/release blobs=5 mounts=0 manifests=1 shared=0

info: Planning completed in 10ms
uploading: registry.local:5000/oc-mirror/openshift/release sha256:646ce49c160e0610d41b7b0b59936938df136232dd7efe91796a0d9497682994 26.53MiB
sha256:4e0b8de27a9295163d397b1c7b9fd77a18276df6fb36076fb4423ce89877aa59 registry.local:5000/oc-mirror/openshift/release:4.11.1-x86_64-cluster-autoscaler
info: Mirroring completed in 360ms (76.25MB/s)
Wrote release signatures to oc-mirror-workspace/results-1662308847
Rendering catalog image "registry.local:5000/oc-mirror/redhat/redhat-operator-index:v4.11" with file-based catalog 
Writing image mapping to oc-mirror-workspace/results-1662308847/mapping.txt
Writing CatalogSource manifests to oc-mirror-workspace/results-1662308847
Writing ICSP manifests to oc-mirror-workspace/results-1662308847
```

As the previous run I have caputured only part of the output of the command, the first part just to show what is expected to see at the  beggining, and the end of the log, because in here there are important information that we have to use for the next steps.

At this point should see something like below in our folder.

```bash
$ tree .
.
├── archives
│   ├── mirror_seq1_000000.tar
│   └── oc-mirror-workspace
├── imagesetconfig.yaml
├── oc-mirror-workspace
│   ├── publish
│   └── results-1662308847
│       ├── catalogSource-redhat-operator-index.yaml
│       ├── charts
│       ├── imageContentSourcePolicy.yaml
│       ├── mapping.txt
│       └── release-signatures
│           └── signature-sha256-97410a5db655a9d3.json
└── publish

8 directories, 6 files
```

As you can see there are new files within `oc-mirror-workspace/results-1662308847`. These files are described in the next section.

### ImageContentSourcePolicies objects

That's awesome! We already have our **Disconnected Registry** with all the images to required to deploy our cluster in a restricted network. But how I install my cluster using these images instead of the public images that the `openshift-installer` normally use? That's a great question, and this is the reason why exist the objects **ImageContentSourcePolicies**. These object create a mapping between the public registries and our disconnected registry, in order to modify the CRI-O configuration to pull all the needed images from our Disconnected Registry instead of the Internet registry. Let's take a look to the content of one of this files for better understanding.

```bash
$ cat oc-mirror-workspace/results-1662308847/imageContentSourcePolicy.yaml 
---
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: generic-0
spec:
  repositoryDigestMirrors:
  - mirrors:
    - registry.local:5000/oc-mirror/ubi8
    source: registry.redhat.io/ubi8

[...]
```
In this part of the file we can see that a `ImageConteSourcePolicy` object with name `generic-0` will update the CRI-O configuration to pull all the images from the registry `registry.redhat.io/ubi8` from the Disconnected Registry `registry.local"5000/oc-mirror/ubi8`. We can just try to pull this image from our Disconnected Registry in order to validate that actually this image is in there.

```bash
$ podman pull registry.local:5000/oc-mirror/ubi8/ubi:latest
Trying to pull registry.local:5000/oc-mirror/ubi8/ubi:latest...
Getting image source signatures
Copying blob 0d51f270409c done  
Copying blob 480a8b2c25e9 done  
Copying config 343496049f done  
Writing manifest to image destination
Storing signatures
343496049fae3aadfc5c63064bbae33bce2e1511fa7b1a9522dca3cd9c318f6b
```

It is important to be aware that the content of the `ImageContentSourcePolicy` make reference only to the registry repository no to the container image. As you can see in the command above the image that we try to pull is `registry.local:5000/oc-mirror/ubi8/ubi:latest` not just `registry.local:5000/oc-mirror/ubi8`.

How to use these ICSPs objects depend of the status of your cluster, if you are going to start an OCP installation from scratch, there are a section in the `install-config.yaml` to add these configs, and if you have a cluster already running and you just need to update the ICSPs objects just apply this YAML files with `oc apply -f`.

## Conclusions

Currently there are a lot of use cases where a disconnected installation of an OCP cluster is required, and it is important that the procedure to create and maintain a disconnected registry should be as easier as posible. With this new `oc-mirror` plugin the whole procedure has been simplify and also there are multimple improvements like the inrcremental download on each run vs the full download with the previous approach. Moreover, nowadays with DevOps culture and GitOps methodology, it is good to have a way to keep tracking in a Git reposotory of all the changes and track with a CI/CD tool the runs to create and/or maintain the Disconnected Registry. I think it is a worthy tool that helps a lot for production environments.

## Links

- [Disconnected mirror](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-installation-images.html)
- [oc-mirror GitHub repository](https://github.com/openshift/oc-mirror)
- [Mirror Registry](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-creating-registry.html)
- [Get pull secrets](https://console.redhat.com/openshift/downloads#tool-pull-secret)
