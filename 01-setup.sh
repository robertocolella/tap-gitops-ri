#!/bin/bash

# age
brew install age
# wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz

# sops
brew install sops
# wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux.amd64

rm -rf .git
rm -rf .catalog
rm -rf clusters
rm -rf setup-repo.sh

# GitOps Ref. Implementation
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.5.0-rc.14' --product-file-id=1459284
tar -xvf tanzu-gitops-ri-0.0.3.tgz
./setup-repo.sh full-profile sops

# Download Cluster-Essentials

uname -s| grep Darwin && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.4.1' --product-file-id=1423996 && mv tanzu-cluster-essentials-darwin-amd64-1.4.1.tgz gorkem/
uname -s| grep Linux && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.4.1' --product-file-id=1423994 && mv tanzu-cluster-essentials-darwin-amd64-1.4.1.tgz gorkem/

mkdir gorkem/tanzu-cluster-essentials
tar -xvf gorkem/tanzu-cluster-essentials-darwin-amd64-1.4.1.tgz -C gorkem/tanzu-cluster-essentials

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:2354688e46d4bb4060f74fca069513c9b42ffa17a0a6d5b0dbb81ed52242ea44
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq '.tanzuNet_username' gorkem/values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq '.tanzuNet_password' gorkem/values.yaml)

kubectl create namespace kapp-controller

# kubectl create secret generic kapp-controller-config \
#    --namespace kapp-controller \
#    --from-file caCerts=ca.crt

cd gorkem/tanzu-cluster-essentials
./install.sh --yes
cd ../..

# setup sops key

mkdir -p ./gorkem/tmp-enc
chmod 700 ./gorkem/tmp-enc
age-keygen -o ./gorkem/tmp-enc/key.txt

export SOPS_AGE_RECIPIENTS=$(cat ./gorkem/tmp-enc/key.txt | grep "# public key: " | sed 's/# public key: //')
export HARBOR_USERNAME=$(yq '.image_registry_user' ./gorkem/values.yaml)
export HARBOR_PASSWORD=$(yq '.image_registry_password' ./gorkem/values.yaml)
export HARBOR_URL=$(yq '.image_registry' ./gorkem/values.yaml)

cat > ./gorkem/tmp-enc/tap-sensitive-values.yaml <<-EOF
---
tap_install:
  sensitive_values:
    shared:
      image_registry:
        username: $HARBOR_USERNAME
        password: $HARBOR_PASSWORD
    buildservice:
      kp_default_repository_password: $HARBOR_PASSWORD
EOF

sops --encrypt ./gorkem/tmp-enc/tap-sensitive-values.yaml > ./gorkem/tmp-enc/tap-sensitive-values.sops.yaml
mv ./gorkem/tmp-enc/tap-sensitive-values.sops.yaml ./clusters/full-profile/cluster-config/values


ytt --ignore-unknown-comments -f ./gorkem/templates/values.yaml -f ./gorkem/templates/tap-non-sensitive-values-template.yaml > ./clusters/full-profile/cluster-config/values/tap-values.yaml

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq '.tanzuNet_username' ./gorkem/values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq '.tanzuNet_password' ./gorkem/values.yaml)
export GIT_SSH_PRIVATE_KEY=$(cat $HOME/.ssh/id_rsa)
export GIT_KNOWN_HOSTS=$(ssh-keyscan github.com)
export SOPS_AGE_KEY=$(cat ./gorkem/tmp-enc/key.txt)


git init && git add . && git commit -m "Big Bang" && git branch -M main
git remote add origin https://github.com/gorkemozlu/tap-gitops-2.git
git push -u origin main

cd ./clusters/full-profile
./tanzu-sync/scripts/configure.sh

git add ./cluster-config/ ./tanzu-sync/
git commit -m "Configure install of TAP 1.5.0"
git push

kubectl create ns my-apps
kubectl label ns my-apps apps.tanzu.vmware.com/tap-ns=""
tanzu secret registry add registry-credentials --username $HARBOR_USERNAME --password $HARBOR_PASSWORD --server $HARBOR_URL --namespace my-apps --export-to-all-namespaces

./tanzu-sync/scripts/deploy.sh