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
export INSTALL_REGISTRY_USERNAME=$(yq '.tanzuNet_username' values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq '.tanzuNet_password' values.yaml)
cd ./tanzu-cluster-essentials
./install.sh --yes

#########
mkdir -p ./gorkem/tmp-enc
chmod 700 ./gorkem/tmp-enc
cd ./gorkem/tmp-enc
age-keygen -o key.txt

export SOPS_AGE_RECIPIENTS=$(cat key.txt | grep "# public key: " | sed 's/# public key: //')

export HARBOR_USERNAME=$(yq '.image_registry_user' values.yaml)
export HARBOR_PASSWORD=$(yq '.image_registry_password' values.yaml)
cat > tap-sensitive-values.yaml <<-EOF
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

sops --encrypt tap-sensitive-values.yaml > tap-sensitive-values.sops.yaml
mv tap-sensitive-values.sops.yaml ../../clusters/full-profile/cluster-config/values
cd ../../

ytt --ignore-unknown-comments -f values.yaml -f ./gorkem/tap-non-sensitive-values.yaml > clusters/full-profile/cluster-config/values/tap-values.yaml

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq '.tanzuNet_username' values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq '.tanzuNet_password' values.yaml)
export GIT_SSH_PRIVATE_KEY=$(cat $HOME/.ssh/id_rsa)
export GIT_KNOWN_HOSTS=$(ssh-keyscan github.com)
export AGE_KEY=$(cat ./tmp-enc/key.txt)

./tanzu-sync/scripts/configure.sh

git add cluster-config/ tanzu-sync/
git commit -m "Configure install of TAP 1.5.0"
git push

./tanzu-sync/scripts/deploy.sh