#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 prep|import-cli|import-packages"
    exit 1
fi

export INGRESS_DOMAIN=$(yq eval '.ingress_domain' ./gorkem/values.yaml)
export minioURL=minio.$INGRESS_DOMAIN
export HARBOR_URL=$(yq eval '.image_registry' ./gorkem/values.yaml)
export HARBOR_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export HARBOR_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export pivnet_token=6fd8a9a30d004521a05e9260dfca688c-r
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
export TAP_PKGR_REPO=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap
pivnet login --api-token $pivnet_token
mkdir -p $HOME/tmp/
export TMPDIR="$HOME/tmp/"

# check the first parameter
if [ "$1" = "prep" ]; then
    echo "start prepping files...."

    mkdir -p airgapped-files/
    cd airgapped-files/
    
    echo "Downloading age"
    wget -q https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar -xvf age-v1.1.1-linux-amd64.tar.gz
    
    echo "Downloading sops"
    wget -q https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux.amd64 && chmod +x sops-v3.7.3.linux.amd64
    
    echo "Downloading pivnet"
    uname -s| grep Linux && wget -q https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1 && chmod +x pivnet-linux-amd64-3.0.1 && mv pivnet-linux-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet
    uname -s| grep Darwin && wget -q https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-darwin-amd64-3.0.1 && chmod +x pivnet-darwin-amd64-3.0.1 && mv pivnet-darwin-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet
    
    echo "Downloading charts-syncer"
    uname -s| grep Linux && wget -q https://github.com/bitnami-labs/charts-syncer/releases/download/v0.20.1/charts-syncer_0.20.1_linux_x86_64.tar.gz && tar -xvf charts-syncer_0.20.1_linux_x86_64.tar.gz && cp charts-syncer /usr/local/bin/charts-syncer
    uname -s| grep Darwin && wget -q https://github.com/bitnami-labs/charts-syncer/releases/download/v0.20.1/charts-syncer_0.20.1_darwin_x86_64.tar.gz && tar -xvf charts-syncer_0.20.1_darwin_x86_64.tar.gz && cp charts-syncer /usr/local/bin/charts-syncer
    
    echo "Downloading minio client"
    uname -s| grep Linux && wget -q https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc
    uname -s| grep Darwin && brew install minio/stable/mc
    
    echo "Downloading GitOps Ref. Implementation"
    pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.5.0' --product-file-id=1467377
    
    echo "Downloading Cluster-Essentials"
    uname -s| grep Darwin && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.5.0' --product-file-id=1460874
    uname -s| grep Linux && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.5.0' --product-file-id=1460876
    
    # imgpkg binary check
    if ! command -v imgpkg >/dev/null 2>&1 ; then
      echo "installing imgpkg"
      tar -xvf tanzu-cluster-essentials*.tgz
      cp imgpkg /usr/local/bin/imgpkg
    fi
    
    echo "Downloading TAP Packages"
    imgpkg copy \
      -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
      --to-tar tap-packages-$TAP_VERSION.tar \
      --include-non-distributable-layers \
      --concurrency 30
    
    echo "Downloading TBS Full Dependencies"
    imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/full-tbs-deps-package-repo:$TBS_VERSION \
      --to-tar=tbs-full-deps.tar --concurrency 30
    
    echo "Downloading Cluster Essentials"
    imgpkg copy \
      -b registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446 \
      --to-tar cluster-essentials-bundle-1.5.0.tar \
      --include-non-distributable-layers
    
    echo "Downloading Grype Vulnerability Definitions"
    wget -q https://toolbox-data.anchore.io/grype/databases/listing.json
    jq --arg v1 "$v1" '{ "available": { "1" : [.available."1"[0]] , "2" : [.available."2"[0]], "3" : [.available."3"[0]] , "4" : [.available."4"[0]] , "5" : [.available."5"[0]] } }' listing.json > listing.json.tmp
    mv listing.json.tmp listing.json
    wget -q $(cat listing.json |jq -r '.available."1"[0].url')
    wget -q $(cat listing.json |jq -r '.available."2"[0].url')
    wget -q $(cat listing.json |jq -r '.available."3"[0].url')
    wget -q $(cat listing.json |jq -r '.available."4"[0].url')
    wget -q $(cat listing.json |jq -r '.available."5"[0].url')
    sed -i -e "s|toolbox-data.anchore.io|$minioURL|g" listing.json
    
    echo "Downloading tool images"
    export tool_images=$(cat ../gorkem/templates/tools/*.yaml|grep "image:"|awk '{ print $2 }')
    for image in $tool_images
    do
        echo $image
        export tool=$(echo $image | awk -F'/' '{print $(NF)}')
        imgpkg copy -i $image --to-tar=$tool.tar
        # do something with the image
    done
    
    echo "Downloading Bitnami Catalog"
cat > 01-bitnami-to-local.yaml <<-EOF
source:
  repo:
    kind: HELM
    url: https://charts.app-catalog.vmware.com/demo
target:
  intermediateBundlesPath: bitnami-local
charts:
- redis
- mysql
- rabbitmq
- postgresql
EOF
    charts-syncer sync --config 01-bitnami-to-local.yaml --latest-version-only
    
    cd ..

elif [ "$1" = "import-cli" ]; then
    echo "start importing clis...."

    cd airgapped-files/
    # age
    if ! command -v age >/dev/null 2>&1 ; then
      echo "installing age"
      cp age/age /usr/local/bin/age && cp age/age-keygen /usr/local/bin/age-keygen
    fi
    
    # sops
    if ! command -v sops >/dev/null 2>&1 ; then
      echo "installing sops"
      cp sops-v3.7.3.linux.amd64 /usr/local/bin/sops
    fi
    
    # pivnet
    if ! command -v pivnet >/dev/null 2>&1 ; then
      echo "installing pivnet"
      cp pivnet-linux-amd64-3.0.1 /usr/local/bin/pivnet
    fi
    
    # kapp
    if ! command -v kapp >/dev/null 2>&1 ; then
      echo "installing kapp"
      tar -xvf tanzu-cluster-essentials*.tgz
      cp kapp /usr/local/bin/kapp
    fi
    
    # imgpkg
    if ! command -v imgpkg >/dev/null 2>&1 ; then
      echo "installing imgpkg"
      tar -xvf tanzu-cluster-essentials*.tgz
      cp imgpkg /usr/local/bin/imgpkg
    fi
    
    # mc
    if ! command -v mc >/dev/null 2>&1 ; then
      echo "installing mc"
      cp mc /usr/local/bin/mc
    fi
    
    cd ..

elif [ "$1" = "import-packages" ]; then
    echo "start importing files...."
    cp $REGISTRY_CA_PATH /etc/ssl/certs/tap-ca.crt
    cp airgapped-files/tanzu-gitops-ri-*.tgz .
    cp airgapped-files/tanzu-cluster-essentials*.tgz gorkem/
    
    imgpkg copy \
      --tar airgapped-files/tap-packages-$TAP_VERSION.tar \
      --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap \
      --include-non-distributable-layers \
      --concurrency 30 \
      --registry-ca-cert-path $REGISTRY_CA_PATH
    
    imgpkg copy --tar airgapped-files/tbs-full-deps.tar \
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
          --tar airgapped-files/cluster-essentials-bundle-1.5.0.tar \
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
    
    
    mc alias set minio https://$minioURL minio minio123 --insecure
    mc mb minio/grype --insecure
    mc cp airgapped-files/vulnerability*.tar.gz minio/grype/databases/ --insecure
    mc cp airgapped-files/listing.json minio/grype/databases/ --insecure
    cd airgapped-files/
cat > 02-bitnami-from-local.yaml <<-EOF
source:
  intermediateBundlesPath: bitnami-local
target:
  containerRegistry: $HARBOR_URL
  containerRepository: bitnami/containers
  containers:
    auth:
      username: admin
      password: VMware1!
  repo:
    kind: OCI
    url: https://$HARBOR_URL/bitnami/charts
    auth:
      username: $HARBOR_USERNAME
      password: $HARBOR_PASSWORD
EOF
    charts-syncer sync --config 02-bitnami-from-local.yaml
    cd ..

else
    echo "Invalid parameter: $1"
    exit 1
fi

