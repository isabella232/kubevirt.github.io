---
layout: post
author: Alberto Losada Grande
description: A use case is exposed where containerized VMs running on top of Kubernetes ease the deployment of standardized VMs required by software developers. In this first part, we focus on creating standard images using different tools and then containerize them so that they can be stored in a container registry.
navbar_active: Blogs
category: news
tags:
  [
    "kubevirt",
    "kubernetes",
    "virtual machine",
    "okd",
    "containerDisk",
    "dockerfile",
    "registry",
    "composer-cli",
    "virt-customize",
    "builder tool",
  ]
comments: true
title: Customizing images for containerized VMs (1/2)
pub-date: March 11
pub-year: 2020
---

**Table of contents**

<!-- TOC depthFrom:2 insertAnchor:false orderedList:false updateOnSave:true withLinks:true -->

- [The vision](#the-vision)
- [Preparation of the environment](#preparation-of-the-environment)
  - [Configuration of the Builder image server](#configuration-of-the-builder-image-server)
- [Building standard CentOS 8 image](#building-standard-centos-8-image)
  - [Image creation with Builder Tool](#image-creation-with-builder-tool)
  - [Verify the custom-built image](#verify-the-custom-built-image)
  - [Image tailoring with virt-customize](#image-tailoring-with-virt-customize)
- [Building standard CentOS 7 image from cloud images](#building-standard-centos-7-image-from-cloud-images)
  - [Image creation with virt-customize](#image-creation-with-virt-customize)
- [Image containerization procedure](#image-containerization-procedure)
  - [Store the image in the container registry](#store-the-image-in-the-container-registry)
- [Summary](#summary)
- [References](#references)

<!-- /TOC -->

> info "Information"
> The content of this article has been divided into two: this one, which is the first part, explains how to create a golden image using different tools such as _Builder Tool_ and _virt-customize_. Once the custom-built image is ready, it is containerized so that it can be uploaded and stored into a container registry. The second part deals with the different ways the developers can deploy, modify and connect to the `VirtualMachineInstance` running in the OKD Kubernetes cluster.

## The vision

If you work for a software factory, some kind of development environment standardization is probably in place. There are a lot of approaches which fit different use cases. In this blog post, our example company has allowed developers to choose their preferred editing tools and debugging environment locally to their workstations. However, before committing their changes to the Git repository, they need to validate them in a specifically tailored environment. This environment, due to legal restrictions, contains exact versions of the libraries, databases, web server or any other software previously agreed with customers.

> note "Note"
> Aside from the pre-commit environments, the company already has an automated continuous integration workflow composed by several shared environments: _development, integration and production_.

This blog post focuses on showing a use case where containerized VMs running on top of Kubernetes ease the deployment and creation of standardized VMs to our developers. These VMs are meant to be ephemeral. However, if necessary, additional non-persistent disk or shared persistent storage can be attached so that important information can be kept safe.

Along the process, different approaches and tools to create custom VM images that will be stored in a corporate registry are detailed. Containerizing VMs means adapting them so that they can be saved in a container registry. Being able to manage VMs as container images leverages the benefits of a container registry, such as:

- The registry becomes a **source of truth** for the VMs you want to run. Everybody can list all VMs available searching on a centralized point.
- The container registry, depending on the storage size, contains historical information of all the VMs, which might have multiple different versions, identified by their tags. Any developer with the proper permissions is able to run any specific version of your standardized VM.
- It is the unique point where all your VMs are stored avoiding having them spread all over your infrastructure.

> info "Information"
> A container image registry is a service that stores container images, and is hosted either by a third-party or as a public/private registry such as Docker Hub, Quay, and so on.

The ambitious goal is to allow the developers to deploy the standardized VMs on the current Kubernetes infrastructure. Then, execute the required tests and if they are good, push the code to the corporate Git repositories and delete the VM.

This goal is divided into three main procedures:

- Create custom standardized VM images, also known as golden images.
- Containerize the resulting golden VM images.
- Deploy the proper VM images from the corporate registry into the OKD Kubernetes cluster.

<br>

## Preparation of the environment

Running containerized VMs in KubeVirt uses the [containerDisk](https://kubevirt.io/user-guide/docs/latest/creating-virtual-machines/disks-and-volumes.html#containerdisk) feature which provides the ability to store and distributed VM disks in the container image registry. The disks are pulled from the container registry and reside on the local node hosting the VMs that consume the disks.

Prior to run VMs in KubeVirt, it first must be running in the Kubernetes cluster. The company already have an [OKD 4 Kubernetes cluster](https://www.okd.io/) installed which provides out of the box a container registry and some required security features such as _Role Based Access Controls (RBAC)_ and _Security Context Constraints (SCC)_.

> info "Information"
> [Here](https://blog.openshift.com/enterprise-kubernetes-with-openshift-part-one/) you can find useful information between the similarities and differences between OKD and Kubernetes.

On top of the OKD cluster, KubeVirt is required so that we can run our virtual machines. The installation process is pretty well detailed in the [KubeVirt's documentation](https://kubevirt.io/pages/cloud.html). Below it is shown how KubeVirt components can be seen from the OKD web console.

> info "Information"
> KubeVirt version deployed is **0.26.1** which is the latest at the moment of writing.

```sh
$ echo $KUBEVIRT_VERSION
v0.26.1

$ kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
$ kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
```

<br>

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/kubevirt_okd.png"
      itemprop="contentUrl"
      data-size="1110x520"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/kubevirt_okd.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description"></figcaption>
  </figure>
</div>

> warning "Warning"
> **oc** is the specific command-line tool for OKD, however, it is based in *kubectl* plus some additional features detailed here. It is probably that along the blog post, you can find executions with *oc* or *kubectl* interchangeably.

`containerDisks` are created from RAW or [QCOW2](https://www.linux-kvm.org/page/Qcow2) virtual machine images. Nevertheless, virtual machine images with all the agreed software and proper configuration files in place must be created previously. The company currently uses CentOS 7 as their approved base operating system to run their applications. However, during the last months, it has been encouraging to move to the recently released version 8 of CentOS.

From a long time they had been using the prebuilt [CentOS cloud images](https://cloud.centos.org/centos/) with [virt-customize](http://libguestfs.org/virt-customize.1.html), which allowed them to modify the prebuilt cloud images. As a trade-off, they had to trust on the cloud image provided by CentOS or verify if new packages were added on each release.

> info "Information"
> **Virt-customize** can customize a virtual machine (disk image) by installing packages, editing configuration files, and so on. Virt-customize modifies the guest or disk image in place.

They are currently investigating a new tool called [Image Builder](https://docs.centos.org/en-US/centos/install-guide/Composer/) that can create deployment-ready customized system images from scratch. Furthermore, there is an integration with Cockpit where you can create custom CentOS images in various formats including QCOW2 for OpenStack, AMI (Amazon Machine Image), VHD (Azure Disk Image) etc. from a friendly user interface.

> note "Note"
> There are a lot of tools that can accomplish the objective of creating custom images. Here we are focusing on two: `virt-customize` and `Image Builder`.

Along this blog post, both tools are used together in the image building process, leveraging their strengths. In the following diagram is depicted the different agents that take part in the process of running our standardized VMs in Kubernetes. This workflow includes the creation and customization of the images, their containerization, storing them into the OKD container registry and finally the creation of the VMs in Kubernetes by the employees.

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/diagram-customizing-images.png"
      itemprop="contentUrl"
      data-size="1110x320"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/diagram-customizing-images.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description">okd imagestream devstation</figcaption>
  </figure>
</div>

### Configuration of the Builder image server

In order to prepare the building environment, it is recommended to install Image Builder in a dedicated machine as it has specific security requirements. Actually, the `lorax-composer` which is one of its components doesn’t work properly with SELinux running, as it installs an entire OS image in an alternate directory.

> warning "Warning"
> As shown in the [lorax-composer documentation](https://weldr.io/Running-Composer-on-RHEL/) SELinux must be disabled. However, I have been able to create custom images successfully with SELinux enabled. During this blog post all image builds are created with SELinux enabled. However, in case you find any problems during your building, check the `lorax-composer` logs in journal in order to get more detailed information.

Here it is a table where the software required to run the builds along with the versions have been used.

> note "Note"
> Operating System is **CentOS 8** since CentOS 7 Image Builder is still an [experimental feature](https://docs.centos.org/en-US/centos/install-guide/Composer/)

| Configuration      | Value                                                                        |
| ------------------ | ---------------------------------------------------------------------------- |
| `Operating System` | `CentOS Linux release 8.1.1911 (Core)`                                       |
| `Libvirt`          | `libvirtd (libvirt) 4.5.0`                                                   |
| `virt-customize`   | `virt-customize 1.38.4rhel=8,release=14.module_el8.1.0+248+298dec18,libvirt` |
| `Image Builder`    | `lorax-composer, composer-cli, (composer-cli-28.14.30-1), cockpit-composer`  |

Once the builder image server is provisioned with latest CentOS 8, the `Virtualization Host` group package is installed. It will be required to test our customized images locally before containerizing and pushing them to the OKD registry.

```sh
$ yum groupinstall "Virtualization Host" -y
$ systemctl enable libvirtd --now
```

Next, `virt-customize` is installed from the `libguestfs-tools` package along with the Image Builder. The latest is composed by lorax-composer, the Cockpit composer plugin and the composer-cli, which will be used in case we want to interact directly with Composer.

```sh
$ dnf install -y libguestfs-tools lorax-composer composer-cli cockpit-composer
$ systemctl enable lorax-composer.socket
$ systemctl enable lorax-composer --now
$ systemctl start cockpit
```

Then, the local firewall is configured so that we can connect to the Cockpit user interface via HTTP from our workstation.

```sh
$ firewall-cmd --add-service=cockpit && firewall-cmd --add-service=cockpit --permanent
```

Finally, verify you can connect to the Cockpit user interface and log in with the builder image server local account.

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/cockpit-gui.png"
      itemprop="contentUrl"
      data-size="1110x484"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/cockpit-gui.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description"></figcaption>
  </figure>
</div>

The following image shows the Image Build plugin web page. Actually, what it is depicted are the different Image Build blueprints that are shipped by default. _The blueprint_ defines what should be included in your image. This includes packages, users, files, server settings ...

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/cockpit-first-page.png"
      itemprop="contentUrl"
      data-size="1110x333"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/cockpit-first-page.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description"></figcaption>
  </figure>
</div>

## Building standard CentOS 8 image

It is time to create our standardized CentOS 8 image or also called golden CentOS 8 image. This image will be built from the ground up using the Image Builder tool.

### Image creation with Builder Tool

The easiest way to start is creating a new blueprint from the Cockpit user interface. This will produce a scaffold file where all the required modifications can be made. Here it is shown the process of creation a new blueprint from Cockpit:

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/create_blueprint.png"
      itemprop="contentUrl"
      data-size="1110x413"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/create_blueprint.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description"></figcaption>
  </figure>
</div>

I would also suggest adding some users and all the packages you want to install from the user interface. In our case, we are going to create the following users. In both cases, the password is known by the respective group of users and also belongs to the wheel group.

| Users     | Note                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------- |
| sysadmin  | Privileged user owned by the Systems Engineering team to troubleshoot and have access to the VM |
| developer | These are the credentials used by the developers to access the VM                               |

Next, specify the packages to include. Add the proper version of the package already agreed with the customer.

| Package        | Version |
| -------------- | ------- |
| httpd          | 2.4.37  |
| mod_ssl        | 2.4.37  |
| php            | 7.2.11  |
| mariadb-server | 10.3.17 |
| openssh-server | latest  |

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/packages_version.png"
      itemprop="contentUrl"
      data-size="1110x454"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/packages_version.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description"></figcaption>
  </figure>
</div>

At this point, you already have a blueprint template to start working. In addition to using the web console, you can also use the **Image Builder CLI** to create images. When using the CLI, you have access to a few more customization options, such as managing firewall rules or download files from Git. Since we already have installed the composer-cli package in the [Image Builder server](#configuration-of-the-builder-image-server), let’s use it to further customize our golden image.

First, access to the Builder Image server and download the custom blueprint called `devstation-centos8`.

```sh
$ composer-cli blueprints list
devstation-centos8
example-atlas
example-development
Example-http-server

$ composer-cli blueprints save devstation-centos8
$ ls
devstation-centos8.toml
```

Now, let’s edit the `devstation-centos8.toml` file which is in charge of building our custom image:

- The timezone has been added to match Europe/Madrid with proper NTP servers.
- The kernel has been modified to allow connection via console.
- Several firewall rules have been added to allow our services being accessed from outside.
- Some services have been configured so that they are enabled and started at boot.
- A Git repository has been configured to be cloned. Actually, it is a Git repository that contains a manual detailing how the custom image is configured and how it must be used.

> warning "Warning"
> It is important to add console as a kernel option since the Builder Image tool disables access to serial console by default. Probably for other use cases it is fine to be disabled, however, in our case of containerized VMs it is almost mandatory to be enabled. It will allow the *virtctl* command to connect to the VM while it is booting in our OKD Kubernetes cluster.

This is the final building configuration file, it can be downloaded from [here](/assets/2020-03-11-Customizing-images-for-containerized-vms/devstation-centos8.toml)

```toml
name = "devstation-centos8"
description = "A developer station"
version = "0.0.1"
modules = []
groups = []

[[packages]]
name = "httpd"
version = "2.4.37"

[[packages]]
name = "mod_ssl"
version = "2.4.37"

[[packages]]
name = "php"
version = "7.2.11"

[[packages]]
name = "mariadb-server"
version = "10.3.17"

[[packages]]
name = "openssh-server"
version = "*"

[customizations]
hostname = "devstation"

[customizations.kernel]
append = "console=tty0 console=ttyS0,19200n81"

[customizations.timezone]
timezone = "Europe/Madrid"
ntpservers = ["0.europe.pool.ntp.org", "1.europe.pool.ntp.org"]

[[customizations.user]]
name = "sysadmin"
description = "Company Systems Admin"
password = "$6$ZGmDxvGu3Q0M4RO/$KkfU0bD32FrLNpUCWEL8sy3dknJVyqExoy.NJMOcSCRjpt1H6sFKFjx8mFWn8H5CWTP7.bibPLBrRSRq3MrDb."
home = "/home/sysadmin/"
shell = "/usr/bin/bash"
groups = ["users", "wheel"]

[[customizations.user]]
name = "developer"
description = "developer"
groups = ["wheel"]
password = "$6$wlIgNacMnqCcXn3o$mPpw0apT4iZ3jDq0q6epXN3xCmNN.oVGFW.Gvu9r0nDVX.FXY3iCwfFkfPEcmhj7Kxw4Ppoes2LsUzPtNRjez0"

[customizations.services]
enabled = ["httpd","mariadb","sshd"]

[customizations.firewall.services]
enabled = ["http","https","mysql","ssh"]

[[repos.git]]
rpmname = "manual"
rpmversion = "1.0"
rpmrelease = "1"
summary = "Manual how to work with devstation"
repo = "https://github.com/alosadagrande/lorax"
ref = "master"
destination = "/var/www/html/manual"
```

> note "Note"
> In this case, we are using a Git repository to download useful information on how to deal with the customized image. However, it is possible to download for instance code or other information that can be stored in Git. And what is most important, it is versioned.

Once edited, push the modified configuration to Image Builder and start the building process by selecting the blueprint and the output format. Builder Image tool can export the same blueprint into multiple output formats. Thus, one blueprint might create the same custom image running on multiple providers (qcow2 in our case).

```sh
$ composer-cli blueprints push devstation-centos8.toml

$ composer-cli compose start devstation-centos8 qcow2
Compose ea8089f6-7e60-4282-a4e8-5c168246c0b6 added to the queue
```

> note "Note"
> It is possible to verify that the modified blueprint has been pushed successfully by executing the show command.
>
> ```sh
> $ composer-cli blueprints show devstation-centos8
> ```

The building process can take tens of minutes. It is possible to see the process by checking the lorax-composer logs in the journal or request the status of the blueprint built from the composer-cli:

```sh
$ composer-cli compose status
ea8089f6-7e60-4282-a4e8-5c168246c0b6 RUNNING  Thu Feb 27 16:00:49 2020 devstation-centos8 0.0.1 qcow2

$ journalctl -u lorax-composer -300f
Mar 02 09:17:41 eko7.cloud.lab.eng.bos.redhat.com lorax-composer[26293]: 2020-03-02 09:17:41,715: Downloading 471 RPMs, 330.8 MiB / 378.27 MiB (87%) done.
Mar 02 09:17:41 eko7.cloud.lab.eng.bos.redhat.com lorax-composer[26293]: 2020-03-02 09:17:41,715: Downloading 471 RPMs, 337.2 MiB / 378.27 MiB (89%) done.
Mar 02 09:17:41 eko7.cloud.lab.eng.bos.redhat.com lorax-composer[26293]: 2020-03-02 09:17:41,715: Preparing transaction from installation source
Mar 02 09:19:09 eko7.cloud.lab.eng.bos.redhat.com lorax-composer[26293]: 2020-03-02 09:19:09,316: Installing libgcc.x86_64 (1/472)
Mar 02 09:19:09 eko7.cloud.lab.eng.bos.redhat.com lorax-composer[26293]: 2020-03-02 09:19:09,316: Installing hwdata.noarch (2/472)
...
```

Once the building image is finished, it is time to download the `qcow2` file. It can be downloaded from Cockpit or from the composer-cli:

```sh
$ composer-cli compose image ea8089f6-7e60-4282-a4e8-5c168246c0b6
ea8089f6-7e60-4282-a4e8-5c168246c0b6-disk.qcow2: 1895.12 MB

$ ls -lhrt
-rw-r--r--. 1 root root 1.3K Mar  2 08:45 devstation-centos8.toml
-rw-r--r--. 1 root root 1.9G Mar  2 09:31 ea8089f6-7e60-4282-a4e8-5c168246c0b6-disk.qcow2
```

Afterwards the image is renamed to something more meaningful and the information given by qemu reviewed as exhibited below:

```sh
$ mv ea8089f6-7e60-4282-a4e8-5c168246c0b6-disk.qcow2 golden-devstation-centos8-disk.qcow2

$ qemu-img info golden-devstation-centos8-disk.qcow2
image: golden-devstation-centos8-disk.qcow2
file format: qcow2
virtual size: 4.4G (4731174912 bytes)
disk size: 1.9G
cluster_size: 65536
Format specific information:
    compat: 1.1
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
```

> warning "Warning"
> Virtual size of the image is 4.4G, since we agreed 10G the disk must be resized and root filesystem expanded before being containerized. Currently, there is no way to specify disk capacity in containerDisk as it can be done with [emptyDisks](https://github.com/kubevirt/kubevirt/blob/master/docs/container-empty-disks.md#implementation). The size of the root filesystem and disk when running in KubeVirt is driven by the image.

```sh
$ qemu-img resize golden-devstation-centos8-disk.qcow2 10G
Image resized.
```

The expansion is executed on the root partition, which in case of our golden image is **/dev/vda2** partition. It must be checked previously. Note that a copy of the golden image has been created and that's the one expanded.

```sh
$ cp golden-devstation-centos8-disk.qcow2 golden-devstation-centos8-disk-10G.qcow2
$ virt-resize --expand /dev/vda2 golden-devstation-centos8-disk.qcow2 golden-devstation-centos8-disk-10G.qcow2
[   0.0] Examining golden-devstation-centos8-disk.qcow2
**********

Summary of changes:

/dev/sda1: This partition will be left alone.

/dev/sda2: This partition will be resized from 2.7G to 9.0G.  The
filesystem xfs on /dev/sda2 will be expanded using the ‘xfs_growfs’
method.

**********
[   2.2] Setting up initial partition table on golden-devstation-centos8-disk-10G.qcow2
[   3.1] Copying /dev/sda1
[   4.0] Copying /dev/sda2
 100%
[   8.5] Expanding /dev/sda2 using the ‘xfs_growfs’ method

Resize operation completed with no errors.  Before deleting the old disk,
carefully check that the resized disk boots and works correctly.
```

Finally, verify that the image meets the expected values:

```sh
$ qemu-img info golden-devstation-centos8-disk-10G.qcow2
image: golden-devstation-centos8-disk-10G.qcow2
file format: qcow2
virtual size: 10G (10737418240 bytes)
disk size: 1.8G
cluster_size: 65536
Format specific information:
    compat: 1.1
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
```

> note "Note"
> If you want to allow the developer choosing between multiple flavours, e.g. different root filesystem sizes, you can end up with multiple containerized VM images. If you just need an additional block device, `emptyDisk` is the proper way to go.

### Verify the custom-built image

Before continuing, it is suggested to verify the golden expanded image. Since the qcow2 image is not yet containerized, it can easily run on KVM/libvirt. In our case, the builder server has already in place the *Virtualization Host* group packages.

> info "Information"
> There are a lot of tools that allow us to run a qcow2 image in libvirt. In this example, `virt-install` is used, however, other tool that makes easy to deploy VM images and worth exploring is [kcli](https://github.com/karmab/kcli)

First, install [virt-install](https://linux.die.net/man/1/virt-install), which is a command-line tool for creating new KVM, Xen, or Linux container guests using the "libvirt" hypervisor management library, and run a new VM from the golden image:

```sh
$ yum install virt-install -y
$ virt-install --version
2.2.1

$ virt-install --memory 2048 --vcpus 2 --name devstation-centos8 --disk /var/lib/libvirt/images/golden-devstation-centos8-disk-10G.qcow2,device=disk --os-type Linux --os-variant rhel8.1 --virt-type kvm --graphics none --network default --import

Starting install...
Connected to domain devstation-centos8
Escape character is ^]

CentOS Linux 8 (Core)
Kernel 4.18.0-147.5.1.el8_1.x86_64 on an x86_64

devstation login:
```

Login as [developer or sysadmin user](#image-creation-with-builder-tool), scale privileges and check that the VM is configured as expected.

```sh
$ firewall-cmd --list-all
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: ens3
  sources:
  services: cockpit dhcpv6-client http https mysql ssh
```

```sh
$ systemctl is-active httpd
active
$ systemctl is-active mariadb
active
$ systemctl is-active sshd
active
```

Verify the disk and partition sizes are correctly configured:

```sh
$ lsblk
NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
vda    252:0    0  10G  0 disk
├─vda1 252:1    0   1G  0 part /boot
└─vda2 252:2    0   9G  0 part /

$ df -h
Filesystem      Size  Used Avail Use% Mounted on
devtmpfs        962M     0  962M   0% /dev
tmpfs           995M     0  995M   0% /dev/shm
tmpfs           995M   17M  979M   2% /run
tmpfs           995M     0  995M   0% /sys/fs/cgroup
/dev/vda2       9.0G  1.9G  7.2G  21% /
```

> note "Note"
> In case you are unsure on which partition you need to expand or contains the root filesystem, just run a VM from the golden qcow2 image and execute the previous commands. Then delete the VM and expand the image accordingly.

Finally, notice how the cloned repository has been copied successfully during the built process. Users can check the custom image information connecting to the local Apache server:

```sh
[root@devstation ~]# curl localhost/manual/
Dear developer,
<br>
<br>
Welcome to the devstation server.

<h2> How to use the devstation server </h2>

Remember that before committing your changes to the corporate source management control server, you need to validate your code here.

<h2> Need help? </h2>

Please contact us at sysadmin@corporate.com
```

<br>

### Image tailoring with virt-customize

In the previous section, we have verified that the golden image has been successfully built. However, there are few things that need to be added so that the golden image can be successfully containerized and run on top of our OKD Kubernetes cluster.

First, a worthy package that is suggested to be included in the golden image is [cloud-init](https://cloud-init.io/). KubeVirt allows you to create VM objects along with [cloud-init](https://kubevirt.io/user-guide/docs/latest/creating-virtual-machines/startup-scripts.html#cloud-init) configurations. Cloud-init will let our developers further adapt the custom image to their application needs. On the other hand, it has been agreed with the Software Engineering team to add a graphical interface to the custom image since there are developers that are not familiar with the terminal.

The result will be **two golden images CentOS 8**, both with cloud-init, but one will include a GUI and the other is terminal-based and therefore much lighter.

> warning "Warning"
> It is important to set the memsize of the building process to 4096m and have expanded the root filesystem otherwise you will face an out of space or/and out of memory error while installing the GNOME GUI.

```sh
$ cp golden-devstation-centos8-disk-10G.qcow2 golden-devstation-centos8-disk-10G-gui.qcow2

$ $ virt-customize --format qcow2 -a /var/lib/libvirt/images/golden-devstation-centos8-disk-10G-gui.qcow2 --install @graphical-server-environment,cloud-init --memsize 4096 --run-command "systemctl set-default graphical.target" --selinux-relabel
[   0.0] Examining the guest ...
[   4.9] Setting a random seed
[   5.0] Setting the machine ID in /etc/machine-id
[   5.0] Installing packages: @graphical-server-environment cloud-init
[ 491.8] Running: systemctl set-default graphical.target
[ 491.8] SELinux relabelling
[ 530.1] Finishing off
```

<br>

At this point it has been built:

- A golden CentOS 8 image which can run on libvirt/KVM virtualization servers (golden-devstation-centos8-disk.qcow2)
- A 10G CentOS 8 image prepared to be executed by KubeVirt which included cloud-init. (golden-devstation-centos8-disk-10G.qcow2)
- A 10G CentOS 8 image prepared to be executed by KubeVirt that includes cloud-init and GNOME GUI (golden-devstation-centos8-disk-10G-gui.qcow2)

## Building a standard CentOS 7 image from cloud images

In the previous section, it was shown how we can build and customize images from scratch using the Builder Image tool. However, there are settings that could not be configured even with the composer-cli. Thus, virt-customize was used to fine-tune the custom image, i.e, add cloud-init and a graphical user interface.

Since the Builder Tool is an [experimental tool in CentOS 7.6](https://docs.centos.org/en-US/centos/install-guide/Composer/), the company continues creating their golden CentOS 7 images based on CentOS cloud images. Comparing with the CentOS 8 workflow, this image is the golden image even it is not built by the Systems Engineering department.

> warning "Warning"
> Note that with CentOS 7 images, the company is trusting a cloud image provided by a third party instead of creating one from scratch.

### Image creation with virt-customize

The process to create the golden CentOS 7 image is quite similar to the CentOS 8 one. However, in this case, the customize procedure is entirely done with virt-customize. The first step is to download the cloud image.

```sh
$ curl -o /var/lib/libvirt/images/CentOS-7-x86_64-GenericCloud.qcow2c https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2c
```

Then, it is required to resize and expand the image to meet the agreed size of 10GB. The details are the same explained in the [previous section](#image-creation-with-builder-tool)

```sh
$ qemu-img info golden-devstation-centos7-disk.qcow2
image: golden-devstation-centos7-disk.qcow2
file format: qcow2
virtual size: 8.0G (8589934592 bytes)
disk size: 398M
cluster_size: 65536
Format specific information:
    compat: 0.10
    refcount bits: 16
```

> warning "Warning"
> In this case, unlike CentOS 8 image, the partition where the root filesystem resides is **/dev/vda1**. That’s the partition that needs to be expanded.

Below it is the `virt-customize` command that modifies the CentOS 7 _expanded_ cloud image by:

- Installing the required packages (however, not the exact versions)
- Changing the root password
- Setting devstation as hostname to the customized image
- Configuring the time zone
- Enabling and starting the installed services
- Including files from the manual.

```sh
$ virt-customize --format qcow2 -a /var/lib/libvirt/images/golden-devstation-centos7-disk-10G.qcow2 --install cloud-init,mod_ssl,httpd,mariadb-server,php,openssh-server --memsize 4096  --hostname devstation  --selinux-relabel --timezone Europe/Madrid --root-password password:toor --password centos:password:developer123 --run-command ‘systemctl enable httpd --now’ --run-command ‘systemctl enable mariadb --now’ --mkdir /var/www/html/manual --upload /root/devstation-code/lorax/index.html:/var/www/html/manual/index.html
[   0.0] Examining the guest ...
[   4.7] Setting a random seed
[   4.7] Installing packages: mod_ssl httpd mariadb-server php openssh-server
[ 102.9] Setting the hostname: devstation
[ 102.9] Setting the timezone: Europe/Madrid
[ 102.9] Making directory: /var/www/html/manual
[ 102.9] Uploading: /root/devstation-code/lorax/index.html to /var/www/html/manual/index.html
[ 103.0] Setting passwords
[ 104.7] SELinux relabelling
[ 116.7] Finishing off
```

> info "Information"
> Instead of executing all parameters in the command-line it is possible to create a file that is used as an input file for virt-customize. See option [commands-from-file](http://libguestfs.org/virt-customize.1.html)

Finally, include the GNOME GUI to the expanded CentOS 7 image.

```sh
$ virt-customize --format qcow2 -a /var/lib/libvirt/images/golden-devstation-centos7-disk-10G-gui.qcow2 --install cloud-init --memsize 4096 --run-command "yum groupinstall 'GNOME Desktop' -y" --run-command "systemctl set-default graphical.target" --selinux-relabel
[   0.0] Examining the guest ...
[   4.7] Setting a random seed
[   4.7] Installing packages: cloud-init
[   5.1] Running: yum groupinstall 'GNOME Desktop' -y
[ 872.7] Running: systemctl set-default graphical.target
[ 872.8] SELinux relabelling
[ 922.1] Finishing off
```

> warning "Warning"
> I have not been successful in installing the *GNOME Desktop* group package by *groupid*, i.e, @gnome-desktop-environment. Ultimately, I make use of the *run-command* from the parameter of *virt-customize* to install the GUI.

At this point it has been built:

- A golden CentOS 7 image which can run on libvirt/KVM virtualization servers (golden-devstation-centos7-disk.qcow2).
- A 10G CentOS 7 image prepared to be executed by KubeVirt which includes cloud-init (golden-devstation-centos7-disk-10G.qcow2).
- A 10G CentOS 7 image prepared to be executed by KubeVirt which includes cloud-init and GNOME GUI (golden-devstation-centos7-disk-10G-gui.qcow2).

## Image containerization procedure

The procedure to inject a *VirtualMachineInstance* disk into a container images is pretty well explained in [containerDisk Workflow example](https://kubevirt.io/user-guide/#/creation/disks-and-volumes?) from the official documentation. Only RAW and QCOW2 formats are supported and the disk it is recommended to be placed into the /disk directory inside the container. Actually, it can be placed in other directories, but then, it must be explicitly configured when creating the *VirtualMachine*

Currently, there are 4 standardized images ready to be containerized. The process is the same for all of them, so in order to keep it short, we are just going to show the process of creating a container image from the CentOS 8 QCOW2 images.

> info "Information"
> These are the four available images: CentOS 8 with GNOME, CentOS 8 terminal only, CentOS 7 with GNOME and CentOS 7 terminal only.

```sh
$ cat Dockerfile
FROM scratch
ADD golden-devstation-centos8-disk-10G.qcow2 /disk/
```

```sh
$ cat Dockerfile
FROM scratch
ADD golden-devstation-centos8-disk-10G-gui.qcow2 /disk/
```

Then, it is time to build the image. In our case, [podman](https://podman.io/) has chosen to execute the task, however, we could have used `docker` or `buildah`.

```sh
$ podman build . -t openshift/devstation-centos8:terminal
STEP 1: FROM scratch
STEP 2: ADD golden-devstation-centos8-disk-10G.qcow2 /disk/
STEP 3: COMMIT openshift/devstation-centos8:terminal
8a9e83db71f08995fa73699c4e5a2d331c61b393daa18aa0b63269dc10078467

$ podman build . -t openshift/devstation-centos8:gui
STEP 1: FROM scratch
STEP 2: ADD golden-devstation-centos8-disk-10G-gui.qcow2 /disk/
STEP 3: COMMIT openshift/devstation-centos8:gui
2a4ecc7bf9da91bcb5847fd1cf46f4cd10726a4ceae88815eb2a9ab38b316be4
```

After the successful build, the images are stored locally to the local server, in our case the Builder Server. Remember that they must be uploaded to the OKD container registry.

```sh
$ podman images
REPOSITORY                               TAG        IMAGE ID       CREATED          SIZE
localhost/openshift/devstation-centos8   gui        2a4ecc7bf9da   3 minutes ago    5.72 GB
localhost/openshift/devstation-centos8   terminal   8a9e83db71f0   13 minutes ago   1.94 GB
```

### Store the image in the container registry

Before pushing the images to the corporate container registry, it must be verified that the OKD registry is available outside the Kubernetes cluster. This allows any authenticated user to gain external access to push images into the OKD Kubernetes cluster. [Exposing the secure registry](https://docs.openshift.com/container-platform/4.3/registry/securing-exposing-registry.html) consists basically on configuring a route and expose that route in the OKD routers. Once done, external **authenticated** access is allowed.

```sh
$ oc get route -n openshift-image-registry
NAME            HOST/PORT                                                     PATH   SERVICES         PORT    TERMINATION   WILDCARD
default-route   default-route-openshift-image-registry.apps.okd.okdlabs.com          image-registry   <all>   reencrypt     None
```

> note "Note"
> In order to upload your containerized images to the OKD registry, the user must be authenticated and [authorized to execute the push action](https://docs.openshift.com/container-platform/4.3/registry/accessing-the-registry.html). The role that must be added to the OKD user is the _registry-editor_

In order to authenticate with the OKD container registry, podman is employed as explained in the [official documentation](https://docs.openshift.com/container-platform/4.3/registry/securing-exposing-registry.html).

```sh
$ oc login https://api.okd.okdlabs.com:6443 -u alosadag
The server uses a certificate signed by an unknown authority.
You can bypass the certificate check, but any data you send to the server could be intercepted by others.
Use insecure connections? (y/n): y

Authentication required for https://api.okd.okdlabs.com:6443 (openshift)
Username: alosadag
Password:
Login successful.

$ HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
$ echo $HOST
default-route-openshift-image-registry.apps.okd.okdlabs.com

$  podman login -u $(oc whoami) -p $(oc whoami -t) --tls-verify=false $HOST
Login Succeeded!
```

Before pushing the images, adapt container images to the proper name so they can be uploaded to private registries. Since it is agreed that all developers must be able to pull the images into their namespaces, the images need to be pushed to the openshift project.

> info "Information"
> [Understanding containers, images and imagestreams](https://docs.openshift.com/container-platform/4.3/openshift_images/images-understand.html) from OpenShift documentation deeply explains container image naming.

```sh
$ podman tag localhost/openshift/devstation-centos8:gui default-route-openshift-image-registry.apps.okd.okdlabs.com/openshift/devstation:v8-terminal
$ podman push default-route-openshift-image-registry.apps.okd.okdlabs.com/openshift/devstation:v8-terminal --tls-verify=false
```

```sh
$ podman tag localhost/openshift/devstation-centos:gui default-route-openshift-image-registry.apps.okd.okdlabs.com/openshift/devstation:v8-gui
$ podman push default-route-openshift-image-registry.apps.okd.okdlabs.com/openshift/devstation:v8-gui --tls-verify=false
Getting image source signatures
Copying blob 6b39f8837d66 [========>-----------------------------] 1.2GiB / 5.3GiB
Copying blob 6b39f8837d66 [========>-----------------------------] 1.2GiB / 5.3GiB
Copying blob 6b39f8837d66 [========>-----------------------------] 1.2GiB / 5.3GiB
Copying blob 6b39f8837d66 [========>-----------------------------] 1.2GiB / 5.3GiB
Copying blob 6b39f8837d66 [=============>------------------------] 1.9GiB / 5.3GiB
Copying blob 6b39f8837d66 [==============>-----------------------] 2.1GiB / 5.3GiB
Copying blob 6b39f8837d66 [===================>------------------] 2.7GiB / 5.3GiB
Copying blob 6b39f8837d66 [===================>------------------] 2.7GiB / 5.3GiB
Copying blob 6b39f8837d66 done
Copying config 2a4ecc7bf9 done
Writing manifest to image destination
Storing signatures
```

Verify that the images are stored correctly in the OKD container registry by checking the [imageStream](https://docs.openshift.com/container-platform/4.3/openshift_images/image-streams-manage.html#working-with-imagestreams). As shown below, both images were uploaded successfully since the `devstation` imagestream contains two images with v8-gui and v8-terminal tags respectively.

```sh
oc describe imagestream devstation -n openshift
Name:			devstation
Namespace:		openshift
Created:		23 hours ago
Labels:			<none>
Annotations:		<none>
Image Repository:	default-route-openshift-image-registry.apps.okd.okdlabs.com/openshift/devstation
Image Lookup:		local=false
Unique Images:		2
Tags:			2

v8-gui
  no spec tag

  * image-registry.openshift-image-registry.svc:5000/openshift/devstation@sha256:e301d935c1cb5a64d41df340d78e6162ddb0ede9b9b5df9c20df10d78f8fde0f
      2 hours ago

v8-terminal
  no spec tag

  * image-registry.openshift-image-registry.svc:5000/openshift/devstation@sha256:47c2ba0c463da84fa1569b7fb8552c07167f3464a9ce3b6e3f607207ba4cee65
```

At this point, the images are stored in a private registry and ready to be consumed by the developers.

> info "Information"
> In case you do not have a corporate private registry available, you can upload images to any free public container registry. Then, consume the container images from the public container registry. Just in case you want to use them or take a look, it has been uploaded to my [public container image repository at quay.io](https://quay.io/repository/alosadag/devstation?tab=tags)

<div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
  <figure
    itemprop="associatedMedia"
    itemscope
    itemtype="http://schema.org/ImageObject"
  >
    <a
      href="/assets/2020-03-11-Customizing-images-for-containerized-vms/okd_is_devstation.png"
      itemprop="contentUrl"
      data-size="1110x467"
    >
      <img
        src="/assets/2020-03-11-Customizing-images-for-containerized-vms/okd_is_devstation.png"
        itemprop="thumbnail"
        width="100%"
        alt="VM to VM"
      />
    </a>
    <figcaption itemprop="caption description"></figcaption>
  </figure>
</div>

In the next article, we will show how our developers can consume the custom-built images to run into the OKD Kubernetes cluster.

## Summary

In this blog post, it was detailed a real use of a company that uses KubeVirt to run standardized environments to run and test the code of their applications. In their use case, VMs are spinned up on-demand in the OKD Kubernetes cluster by the developers. This makes them completely autonomous creating and deleting their environments once the tasks are accomplished.

The article explained how to create a golden image using different tools such as Builder Tool and virt-customize. Once the custom-built image was ready, then it is transformed into a container image so that it can be uploaded and stored into a container registry.

> info "Information"
> In the next blog post of these series, the custom-built containerized VM will be deployed from our corporate registry into our Kubernetes cluster. It will be shown how the developers can fine-tune even more the image deployment, how extra storage can be requested and how to connect to the `VirtualMachineInstance`. Stay tuned!

## References

- [KubeVirt installation](https://kubevirt.io/pages/cloud.html)
- [Image Builder: Building custom system images](https://developers.redhat.com/blog/2019/05/08/red-hat-enterprise-linux-8-image-builder-building-custom-system-images/)
- [Composer-cli information](https://weldr.io/lorax/composer-cli.html)
- [Custom-built images available at quay.io](https://quay.io/repository/alosadag/devstation?tab=tags)
