#!/bin/bash

# age
if ! command -v age >/dev/null 2>&1 ; then
  echo "age not installed. Use below to install"
  echo "brew install age"
  echo "or"
  echo "wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar -xvf age-v1.1.1-linux-amd64.tar.gz && cp age/age /usr/local/bin/age && cp age/age-keygen /usr/local/bin/age-keygen"
  echo "Exiting...."
  exit 1
fi


# sops
if ! command -v sops >/dev/null 2>&1 ; then
  echo "sops not installed. Use below to install"
  echo "brew install sops"
  echo "or"
  echo "wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux.amd64 && chmod +x sops-v3.7.3.linux.amd64 && mv sops-v3.7.3.linux.amd64 sops && cp sops /usr/local/bin/sops"
  echo "Exiting...."
  exit 1
fi

# pivnet
if ! command -v pivnet >/dev/null 2>&1 ; then
  echo "pivnet not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-darwin-amd64-3.0.1 && chmod +x pivnet-darwin-amd64-3.0.1 && mv pivnet-darwin-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet"
  echo "uname -s| grep Linux && wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1 && chmod +x pivnet-linux-amd64-3.0.1 && mv pivnet-linux-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet"
  echo "pivnet login --api-token xyz"
  echo "Exiting...."
  exit 1
fi

# kapp
if ! command -v kapp >/dev/null 2>&1 ; then
  echo "kapp not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/carvel-dev/kapp/releases/download/v0.55.0/kapp-darwin-amd64 && chmod +x kapp-darwin-amd64 && mv kapp-darwin-amd64 kapp && cp kapp /usr/local/bin/kapp"
  echo "uname -s| grep Linux && wget https://github.com/carvel-dev/kapp/releases/download/v0.55.0/kapp-linux-amd64 && chmod +x kapp-linux-amd64 && mv kapp-linux-amd64 kapp && cp kapp /usr/local/bin/kapp"
  echo "Exiting...."
  exit 1

fi

rm -rf .git
rm -rf .catalog
rm -rf clusters
rm -rf setup-repo.sh

# GitOps Ref. Implementation
pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.5.0' --product-file-id=1467377
tar -xvf tanzu-gitops-ri-*.tgz
./setup-repo.sh full-profile sops

# Download Cluster-Essentials

uname -s| grep Darwin && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.5.0' --product-file-id=1460874 && mv tanzu-cluster-essentials-darwin-amd64-1.5.0.tgz gorkem/
uname -s| grep Linux && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.5.0' --product-file-id=1460876 && mv tanzu-cluster-essentials-linux-amd64-1.5.0.tgz gorkem/

mkdir gorkem/tanzu-cluster-essentials
tar -xvf gorkem/tanzu-cluster-essentials-*.tgz -C gorkem/tanzu-cluster-essentials
#cp ./gorkem/templates/values-template.yaml ./gorkem/values.yaml

kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated

export AIRGAPPED=$(yq eval '.airgapped' gorkem/values.yaml)
if [ "$AIRGAPPED" = "true" ]; then
    export IMGPKG_REGISTRY_HOSTNAME_0=registry.tanzu.vmware.com
    export IMGPKG_REGISTRY_USERNAME_0=$(yq eval '.tanzuNet_username' gorkem/values.yaml)
    export IMGPKG_REGISTRY_PASSWORD_0=$(yq eval '.tanzuNet_password' gorkem/values.yaml)
    export IMGPKG_REGISTRY_HOSTNAME_1=$(yq eval '.image_registry' ./gorkem/values.yaml)
    export IMGPKG_REGISTRY_USERNAME_1=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
    export IMGPKG_REGISTRY_PASSWORD_1=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
    export IMGPKG_REGISTRY_HOSTNAME=$(yq eval '.image_registry' ./gorkem/values.yaml)
    export IMGPKG_REGISTRY_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
    export IMGPKG_REGISTRY_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
    export TAP_VERSION=$(yq eval '.tap_version' ./gorkem/values.yaml)
    export TBS_VERSION=$(yq eval '.tbs_version' ./gorkem/values.yaml)
    yq eval '.ca_cert_data' ./gorkem/values.yaml | sed 's/^[ ]*//' > ./gorkem/ca.crt
    export REGISTRY_CA_PATH="$(pwd)/gorkem/ca.crt"

    imgpkg copy \
      -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
      --to-tar tap-packages-$TAP_VERSION.tar \
      --include-non-distributable-layers \
      --concurrency 30

    imgpkg copy \
      --tar tap-packages-$TAP_VERSION.tar \
      --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap \
      --include-non-distributable-layers \
      --concurrency 30 \
      --registry-ca-cert-path $REGISTRY_CA_PATH

    export TAP_PKGR_REPO=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap

    imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/full-tbs-deps-package-repo:$TBS_VERSION \
      --to-tar=tbs-full-deps.tar --concurrency 30

    imgpkg copy --tar tbs-full-deps.tar \
      --to-repo=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tbs-full-deps --concurrency 30 --registry-ca-cert-path $REGISTRY_CA_PATH

    export KAPP_NS=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.status.phase}{"\n"}{end}'|awk '{print $1}')
    export KAPP_POD=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'|awk '{print $1}')

    if [ -n "$KAPP_NS" ]; then
        echo "kapp is running, adding ca.cert"
        kubectl create secret generic kapp-controller-config \
           --namespace $KAPP_NS \
           --from-file caCerts=gorkem/ca.crt

        kubectl delete pod $KAPP_POD -n $KAPP_NS
    else
        echo "kapp is not running, therefore installing."
        kubectl create namespace kapp-controller
        kubectl create secret generic kapp-controller-config \
           --namespace kapp-controller \
           --from-file caCerts=gorkem/ca.crt
        imgpkg copy \
          -b registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446 \
          --to-tar cluster-essentials-bundle-1.5.0.tar \
          --include-non-distributable-layers
        imgpkg copy \
          --tar cluster-essentials-bundle-1.5.0.tar \
          --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/cluster-essentials-bundle \
          --include-non-distributable-layers \
          --registry-ca-cert-path $REGISTRY_CA_PATH

        export INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446
        export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' gorkem/values.yaml)
        export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' gorkem/values.yaml)

        cd gorkem/tanzu-cluster-essentials
        ./install.sh --yes
        cd ../..
    fi

fi

export KAPP_NS=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.status.phase}{"\n"}{end}'|awk '{print $1}')
export KAPP_POD=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'|awk '{print $1}')

if [ -n "$KAPP_NS" ]; then
    echo "kapp is running"
else
    echo "kapp is not running, therefore installing."
    export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446
    export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
    export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' gorkem/values.yaml)
    export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' gorkem/values.yaml)
    
    cd gorkem/tanzu-cluster-essentials
    ./install.sh --yes
    cd ../..
fi




# setup sops key

sops_age_file="./gorkem/tmp-enc/key.txt"

if [ -e "$sops_age_file" ]; then
  echo "The file '$sops_age_file' exists. Continuing"
else
  echo "The file '$sops_age_file' does not exist."
  mkdir -p ./gorkem/tmp-enc
  chmod 700 ./gorkem/tmp-enc
  age-keygen -o ./gorkem/tmp-enc/key.txt
fi

export SOPS_AGE_RECIPIENTS=$(cat ./gorkem/tmp-enc/key.txt | grep "# public key: " | sed 's/# public key: //')
export HARBOR_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export HARBOR_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export HARBOR_URL=$(yq eval '.image_registry' ./gorkem/values.yaml)

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

ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/custom-schema-template.yaml > ./clusters/full-profile/cluster-config/config/custom-schema.yaml
if [ "$AIRGAPPED" = "true" ]; then
  cp ./gorkem/templates/tbs-full-deps.yaml ./clusters/full-profile/cluster-config/config/tbs-full-deps.yaml
  export multi_line_text="#@data/values-schema\n#@overlay/match-child-defaults missing_ok=True\n---"
  echo -e "$multi_line_text" | cat - ./clusters/full-profile/cluster-config/config/custom-schema.yaml > temp && mv temp ./clusters/full-profile/cluster-config/config/custom-schema.yaml
fi
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tap-non-sensitive-values-template.yaml > ./clusters/full-profile/cluster-config/values/tap-values.yaml

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' ./gorkem/values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' ./gorkem/values.yaml)
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

if [ "$AIRGAPPED" = "true" ]; then
  export GIT_REPO=https://$(yq eval '.git_repo' gorkem/values.yaml)
  export GIT_USER=$(yq eval '.git_user' gorkem/values.yaml)
  export GIT_PASS=$(yq eval '.git_password' gorkem/values.yaml)
  export CA_CERT=$(yq eval '.ca_cert_data' ./gorkem/values.yaml)
  export INGRESS_DOMAIN=$(yq eval '.ingress_domain' ./gorkem/values.yaml)
  
  cat << EOF | kubectl apply -f -
  apiVersion: v1
  kind: Secret
  metadata:
    name: workload-git-auth
    namespace: tap-install
  type: Opaque
  stringData:
    content.yaml: |
      git:
        ingress_domain: $INGRESS_DOMAIN
        host: $GIT_REPO
        username: $GIT_USER
        password: $GIT_PASS
        caFile: |
  $(echo "$CA_CERT" | sed 's/^/        /')
  EOF
  
  echo "Waiting for the clusterissuers.cert-manager.io CRD to become available... So that we will add CA Cert"
  
  while ! kubectl get crd clusterissuers.cert-manager.io > /dev/null 2>&1; do
    sleep 5
  done
  
  echo "The clusterissuers.cert-manager.io CRD is now available."
  
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/local-issuer.yaml|kubectl apply -f-
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/gitea.yaml|kubectl apply -f-
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/nexus.yaml|kubectl apply -f-
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/minio.yaml|kubectl apply -f-
  
  
  # minio mc client
  if ! command -v mc >/dev/null 2>&1 ; then
    echo "mc not installed. Use below to install"
    echo "uname -s| grep Darwin && wget https://dl.min.io/client/mc/release/darwin-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc"
    echo "uname -s| grep Linux && wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc"
    echo "Exiting...."
    exit 1
  fi
  
  export minioURL="minio.tmc.h2o-4-10367.h2o.vmware.com"
  wget https://toolbox-data.anchore.io/grype/databases/listing.json
  jq --arg v1 "$v1" '{ "available": { "1" : [.available."1"[0]] , "2" : [.available."2"[0]], "3" : [.available."3"[0]] , "4" : [.available."4"[0]] , "5" : [.available."5"[0]] } }' listing.json > listing.json.tmp
  mv listing.json.tmp listing.json
  wget $(cat listing.json |jq -r '.available."1"[0].url')
  wget $(cat listing.json |jq -r '.available."2"[0].url')
  wget $(cat listing.json |jq -r '.available."3"[0].url')
  wget $(cat listing.json |jq -r '.available."4"[0].url')
  wget $(cat listing.json |jq -r '.available."5"[0].url')
  sed -i -e "s|toolbox-data.anchore.io|$minioURL|g" listing.json
  #mc alias set minio https://$minioURL:443 minio minio123
  mc cp *.tar.gz minio/grype/databases/
  mc cp listing.json minio/grype/databases/

fi

echo "The clusterissuers.cert-manager.io CRD is now available."
while ! kubectl get crd clusterissuers.cert-manager.io > /dev/null 2>&1; do
  sleep 5
done
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/local-issuer.yaml|kubectl apply -f-