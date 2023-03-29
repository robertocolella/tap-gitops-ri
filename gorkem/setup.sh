#!/bin/bash

# age
brew install age
# sops
brew install sops

# GitOps Ref. Implementation
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.5.0-rc.11' --product-file-id=1431307

#mac
pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.4.1' --product-file-id=1423996
#linux
pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.4.1' --product-file-id=1423994
mkdir tanzu-cluster-essentials
tar -xvf tanzu-cluster-essentials-darwin-amd64-1.4.1.tgz -C tanzu-cluster-essentials

kubectl create namespace kapp-controller

# kubectl create secret generic kapp-controller-config \
#    --namespace kapp-controller \
#    --from-file caCerts=ca.crt

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:2354688e46d4bb4060f74fca069513c9b42ffa17a0a6d5b0dbb81ed52242ea44
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME='user@corp.com'
export INSTALL_REGISTRY_PASSWORD='xx'
cd ./tanzu-cluster-essentials
./install.sh --yes