#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 gen-cert|prep|import-cli|import-packages|post-install"
    exit 1
fi

yq eval '.' ./gorkem/values.yaml
export yaml_check=$?

if [ $yaml_check -eq 0 ]; then
    echo "Valid yaml structure for: values.yaml . Continuing."
else
    echo ""
    echo "Invalid yaml structure for: values.yaml . Check values.yaml"
    exit 1
fi

export INGRESS_DOMAIN=$(yq eval '.ingress_domain' ./gorkem/values.yaml)
export minioURL=minio.$INGRESS_DOMAIN
export HARBOR_URL=$(yq eval '.image_registry' ./gorkem/values.yaml)
export HARBOR_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export HARBOR_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export HARBOR_TAP_REPO=$(yq eval '.image_registry_tap' ./gorkem/values.yaml)
export pivnet_token=$(yq eval '.pivnet_token' ./gorkem/values.yaml)
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
    mkdir -p airgapped-files/git-repos/
    mkdir -p airgapped-files/images
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
    
    echo "Downloading tanzu CLI"
    uname -s| grep Linux && wget -q https://github.com/vmware-tanzu/tanzu-cli/releases/download/v1.0.0/tanzu-cli-linux-amd64.tar.gz && tar -xvf tanzu-cli-linux-amd64.tar.gz && install v1.0.0/tanzu-cli-linux_amd64 /usr/local/bin/tanzu
    wget -q https://github.com/vmware-tanzu/tanzu-cli/releases/download/v1.0.0/tanzu-cli-darwin-amd64.tar.gz
    wget -q https://github.com/vmware-tanzu/tanzu-cli/releases/download/v1.0.0/tanzu-cli-windows-amd64.zip
    tanzu plugin download-bundle --group vmware-tap/default:v1.6.2 --to-tar tanzu-cli-tap-162.tar.gz

    echo "Downloading Tilt CLI"
    wget -q https://github.com/tilt-dev/tilt/releases/download/v0.33.4/tilt.0.33.4.mac.x86_64.tar.gz
    wget -q https://github.com/tilt-dev/tilt/releases/download/v0.33.4/tilt.0.33.4.linux.x86_64.tar.gz
    wget -q https://github.com/tilt-dev/tilt/releases/download/v0.33.4/tilt.0.33.4.windows.x86_64.zip
    
    echo "Downloading GitOps Ref. Implementation"
    pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.6.2' --product-file-id=1565341

    echo "Downloading Cluster-Essentials"
    uname -s| grep Darwin && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.6.0' --product-file-id=1526700
    uname -s| grep Linux && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.6.0' --product-file-id=1526701
    
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
      -b registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:54e516b5d088198558d23cababb3f907cd8073892cacfb2496bb9d66886efe15 \
      --to-tar cluster-essentials-bundle-1.6.0.tar \
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
    export tool_images=$(cat ../gorkem/templates/tools/*.yaml|grep "image: "|awk '{ print $2 }')
    mkdir -p images
    for image in $tool_images
    do
        echo $image
        export tool=$(echo $image | awk -F'/' '{print $(NF)}')
        imgpkg copy -i $image --to-tar=images/$tool.tar
        # do something with the image
    done
    imgpkg copy -b projects.registry.vmware.com/tanzu_meta_pocs/tools/gitea:1.15.3_2 --to-tar=images/gitea-bundle.tar
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/gradle:latest --to-tar=images/gradle.tar
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs_tap/tap/learning-center-image:v1.6.2 --to-tar=images/learning-center-image.tar
    cd git-repos/
    git clone https://github.com/gorkemozlu/weatherforecast-steeltoe-net-tap && rm -rf weatherforecast-steeltoe-net-tap/.git && cp ../../gorkem/sample-workloads/workload-dotnet-core.yaml weatherforecast-steeltoe-net-tap/config/workload.yaml
    git clone https://github.com/gorkemozlu/tanzu-java-web-app && rm -rf tanzu-java-web-app/.git && cp ../../gorkem/sample-workloads/workload-java.yaml tanzu-java-web-app/config/workload.yaml
    git clone https://github.com/gorkemozlu/node-express && rm -rf node-express/.git && cp ../../gorkem/sample-workloads/workload-nodejs.yaml node-express/config/workload.yaml
    git clone https://github.com/spring-projects/spring-petclinic && rm -rf spring-petclinic/.git && mkdir -p spring-petclinic/config/ && ../../gorkem/sample-workloads/workload-java-postgres.yaml spring-petclinic/config/workload.yaml
    git clone https://github.com/MoSehsah/bank-demo && rm -rf bank-demo/.git
    git clone https://github.com/gorkemozlu/learning-center-sample && rm -rf learning-center-sample/.git
    cd ..

    export configserver="projects.registry.vmware.com/tanzu_meta_pocs/banking-demo/configserver:latest"
    export jaeger="projects.registry.vmware.com/tanzu_meta_pocs/banking-demo/jaegertracing/all-in-one:1.42.0"
    export otel="projects.registry.vmware.com/tanzu_meta_pocs/banking-demo/opentelemetry-operator:0.74.0"
    export rbac="projects.registry.vmware.com/tanzu_meta_pocs/banking-demo/kube-rbac-proxy:v0.13.0"
    export wfoperator="projects.registry.vmware.com/tanzu_observability/kubernetes-operator:2.2.0"
    imgpkg copy -i $configserver --to-tar=images/configserver.tar
    imgpkg copy -i $jaeger --to-tar=images/jaeger.tar
    imgpkg copy -i $otel --to-tar=images/otel.tar
    imgpkg copy -i $rbac --to-tar=images/rbac.tar
    imgpkg copy -i $wfoperator --to-tar=images/wfoperator.tar

    echo "Downloading Bitnami Catalog"
cat > 01-bitnami-to-local.yaml <<-EOF
source:
  repo:
    kind: OCI
    url: https://harbor.mgt.mytanzu.org/vac/charts/ubuntu-20
    auth:
      username: change-me
      password: change-me
target:
  intermediateBundlesPath: bitnami-local
charts:
- redis
- mysql
- rabbitmq
- postgresql
- kafka
- mongodb
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

    # tilt
    if ! command -v tilt >/dev/null 2>&1 ; then
      echo "installing tilt"
      tar -xvf tilt.0.33.4.linux.x86_64.tar.gz
      cp tilt /usr/local/bin/tilt
    fi

    # charts-syncer
    if ! command -v charts-syncer >/dev/null 2>&1 ; then
      echo "installing charts-syncer"
      cp charts-syncer /usr/local/bin/charts-syncer
    fi

    echo "installing tanzu cli"
    tar -xvf tanzu-cli-linux-amd64.tar.gz
    install v1.0.0/tanzu-cli-linux_amd64 /usr/local/bin/tanzu

    cd ..

elif [ "$1" = "import-packages" ]; then
    echo "start importing files...."
    cp $REGISTRY_CA_PATH /etc/ssl/certs/tap-ca.crt
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"${HARBOR_TAP_REPO}\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"tap-packages\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"bitnami\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"tools\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"tap-lsp\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/users" -d '{"comment": "push-user", "username": "push-user", "password": "VMware1!", "email": "push-user@vmware.com", "realname": "push-user"}' -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/users" -d '{"comment": "pull-user", "username": "pull-user", "password": "VMware1!", "email": "pull-user@vmware.com", "realname": "pull-user"}' -k
    export push_user_id=$(curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X GET -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/users/search?page=1&page_size=10&username=push-user" -k |jq '.[].user_id')
    export pull_user_id=$(curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X GET -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/users/search?page=1&page_size=10&username=pull-user" -k |jq '.[].user_id')
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects/tap-lsp/members" -d "{\"role_id\": 2, \"member_user\": { \"username\": \"push-user\", \"user_id\": ${push_user_id} }}" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects/tap-lsp/members" -d "{\"role_id\": 3, \"member_user\": { \"username\": \"pull-user\", \"user_id\": ${pull_user_id} }}" -k

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
        #kubectl create secret generic kapp-controller-config \
        #   --namespace $KAPP_NS \
        #   --from-file caCerts=gorkem/ca.crt
        #kubectl delete pod $KAPP_POD -n $KAPP_NS
    else
        echo "kapp is not running, therefore installing."
        kubectl create namespace kapp-controller
        kubectl create secret generic kapp-controller-config \
           --namespace kapp-controller \
           --from-file caCerts=gorkem/ca.crt
        imgpkg copy \
          --tar airgapped-files/cluster-essentials-bundle-1.6.0.tar \
          --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tanzu-cluster-essentials/cluster-essentials-bundle \
          --include-non-distributable-layers \
          --registry-ca-cert-path $REGISTRY_CA_PATH
        export INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:54e516b5d088198558d23cababb3f907cd8073892cacfb2496bb9d66886efe15
        export INSTALL_REGISTRY_HOSTNAME=$(yq eval '.image_registry_tap' ./gorkem/values.yaml)
        export INSTALL_REGISTRY_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
        export INSTALL_REGISTRY_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
        mkdir -p gorkem/tanzu-cluster-essentials
        tar -xvf gorkem/tanzu-cluster-essentials-*.tgz -C gorkem/tanzu-cluster-essentials
        cd gorkem/tanzu-cluster-essentials
        ./install.sh --yes
        cd ../..
    fi

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

    export tool_images=$(cat gorkem/templates/tools/*.yaml|grep "image: "|awk '{ print $2 }')
    echo $tool_images
    for image in $tool_images
    do
        echo $image
        export tool=$(echo $image | awk -F'/' '{print $(NF)}')
        export tool_name=$(echo $tool | cut -d':' -f1)
        imgpkg copy \
          --tar airgapped-files/images/$tool.tar \
          --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/$tool_name \
          --include-non-distributable-layers \
          --registry-ca-cert-path $REGISTRY_CA_PATH
        sed -i -e "s~$image~$IMGPKG_REGISTRY_HOSTNAME_1\/tools\/tools\/${tool}~g" gorkem/templates/tools/*.yaml
        rm -f gorkem/templates/tools/*.yaml-e
    done

    imgpkg copy --tar airgapped-files/images/configserver.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-16/banking-demo/configserver --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH
    imgpkg copy --tar airgapped-files/images/jaeger.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-16/banking-demo/jaeger --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH
    imgpkg copy --tar airgapped-files/images/otel.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-16/banking-demo/otel --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH
    imgpkg copy --tar airgapped-files/images/rbac.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-16/banking-demo/kube-rbac-proxy --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH
    imgpkg copy --tar airgapped-files/images/wfoperator.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-16/banking-demo/wfoperator --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH

    imgpkg copy --tar airgapped-files/images/gitea-bundle.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/gitea --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH
    export gitea_image="projects.registry.vmware.com/tanzu_meta_pocs/tools/gitea:1.15.3_2"
    export gitea_image_harbor="$IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/gitea:1.15.3_2"
    sed -i -e "s~$gitea_image~$gitea_image_harbor~g" gorkem/templates/tools/git.yml

    imgpkg copy --tar airgapped-files/images/learning-center-image.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/learning-center-image --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH

    imgpkg copy --tar airgapped-files/images/gradle.tar --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/gradle --include-non-distributable-layers --registry-ca-cert-path $REGISTRY_CA_PATH
    export gradle_image="projects.registry.vmware.com/tanzu_meta_pocs/tools/gradle:latest"
    export gradle_image_harbor="$IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/gradle:latest"
    sed -i -e "s~$gradle_image~$gradle_image_harbor~g" gorkem/namespace-provisioner/resources/test-pipeline-java.yaml
    sed -i -e "s~$gradle_image~$gradle_image_harbor~g" gorkem/namespace-provisioner/resources/test-pipeline-dotnet.yaml
    sed -i -e "s~$gradle_image~$gradle_image_harbor~g" gorkem/namespace-provisioner/resources/test-pipeline-nodejs.yaml

    tanzu config cert add --host $IMGPKG_REGISTRY_HOSTNAME_1 --skip-cert-verify true
    docker login $IMGPKG_REGISTRY_HOSTNAME_1 --username $HARBOR_USERNAME --password $HARBOR_PASSWORD
    tanzu plugin upload-bundle --tar airgapped-files/tanzu-cli-tap-162.tar.gz --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tools/tanzu-cli/plugin
    tanzu plugin source update default --uri $IMGPKG_REGISTRY_HOSTNAME_1/tools/tanzu-cli/plugin/plugin-inventory:latest
    tanzu plugin install --group vmware-tap/default:v1.6.2

elif [ "$1" = "post-install" ]; then

    export nexus_init_pass=$(kubectl exec -it $(kubectl get pod -n nexus -l app=nexus -o jsonpath='{.items[0].metadata.name}') -n nexus -- cat /nexus-data/admin.password)
    curl -u "admin:${nexus_init_pass}" -X 'PUT' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/security/users/admin/change-password" -H 'accept: application/json' -H 'Content-Type: text/plain' -d ${HARBOR_PASSWORD} -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'PUT' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/security/anonymous" -H 'accept: application/json' -H 'Content-Type: text/plain' -d '{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}' -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'POST' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/repositories/npm/proxy" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"name": "npm","online": true,"storage": {"blobStoreName": "default","strictContentTypeValidation": true,"writePolicy": "ALLOW"},"cleanup": null,"proxy": {"remoteUrl": "https://registry.npmjs.org","contentMaxAge": 1440,"metadataMaxAge": 1440},"negativeCache": {"enabled": true,"timeToLive": 1440},"httpClient": {"blocked": false,"autoBlock": true,"connection": {"retries": null,"userAgentSuffix": null,"timeout": null,"enableCircularRedirects": false,"enableCookies": false,"useTrustStore": false},"authentication": null},"routingRuleName": null,"npm": {"removeNonCataloged": false,"removeQuarantined": false},"format": "npm","type": "proxy"}' -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'POST' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/security/users" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"userId": "tanzu","firstName": "tanzu","lastName": "tanzu","emailAddress": "tanzu@vmware.com","password": "VMware1!","status": "active","roles": ["nx-admin"]}' -k

    mc alias set minio https://$minioURL minio minio123 --insecure
    mc mb minio/grype --insecure
    mc cp airgapped-files/vulnerability*.tar.gz minio/grype/databases/ --insecure
    mc cp airgapped-files/listing.json minio/grype/databases/ --insecure
    mc anonymous set download minio/grype --insecure

    mc mb minio/learning --insecure
    mc cp gorkem/templates/learning-center/archive.tar minio/learning/ --insecure
    mc anonymous set download minio/learning --insecure

    export gitea_user=$(yq eval '.git.gitea.git_user' ./gorkem/values.yaml)
    export gitea_pass=$(yq eval '.git.gitea.git_password' ./gorkem/values.yaml)
    export git_repo=$(yq eval '.git.gitea.git_repo' ./gorkem/values.yaml)
    export gitea_token=$(curl -X POST "https://$gitea_user:$gitea_pass@git.$git_repo/api/v1/users/tanzu/tokens" -H  "accept: application/json" -H "Content-Type: application/json" -d "{\"name\": \"token_name\"}" -k|jq -r .sha1)
    git config --global user.email "$gitea_user@vmware.com"
    git config --global user.name $gitea_user
    cd airgapped-files/git-repos/
    cd bank-demo
    curl -k -X POST "https://git.$git_repo/api/v1/user/repos" -H "content-type: application/json" -H "Authorization: token $gitea_token" --data '{"name":"bank-demo","default_branch":"main"}' -k
    git init
    git checkout -b main
    git add .
    git commit -m "big bang"
    git remote add origin https://git.$git_repo/tanzu/bank-demo.git
    git config http.sslVerify "false"
    echo "git user: $gitea_user / pass: $gitea_pass"
    git push -u origin main
    cd ..
    cd node-express
    curl -k -X POST "https://git.$git_repo/api/v1/user/repos" -H "content-type: application/json" -H "Authorization: token $gitea_token" --data '{"name":"node-express","default_branch":"main"}' -k
    git init
    git checkout -b main
    git add .
    git commit -m "big bang"
    git remote add origin https://git.$git_repo/tanzu/node-express.git
    git config http.sslVerify "false"
    echo "git user: $gitea_user / pass: $gitea_pass"
    git push -u origin main
    cd ..
    cd tanzu-java-web-app
    curl -k -X POST "https://git.$git_repo/api/v1/user/repos" -H "content-type: application/json" -H "Authorization: token $gitea_token" --data '{"name":"java-web-app","default_branch":"main"}' -k
    git init
    git checkout -b main
    git add .
    git commit -m "big bang"
    git remote add origin https://git.$git_repo/tanzu/java-web-app.git
    git config http.sslVerify "false"
    echo "git user: $gitea_user / pass: $gitea_pass"
    git push -u origin main
    cd ..
    cd weatherforecast-steeltoe-net-tap
    curl -k -X POST "https://git.$git_repo/api/v1/user/repos" -H "content-type: application/json" -H "Authorization: token $gitea_token" --data '{"name":"steeltoe-net","default_branch":"main"}' -k
    git init
    git checkout -b main
    git add .
    git commit -m "big bang"
    git remote add origin https://git.$git_repo/tanzu/steeltoe-net.git
    git config http.sslVerify "false"
    echo "git user: $gitea_user / pass: $gitea_pass"
    git push -u origin main
    cd ..

    cd learning-center-sample
    curl -k -X POST "https://git.$git_repo/api/v1/user/repos" -H "content-type: application/json" -H "Authorization: token $gitea_token" --data '{"name":"learning-center-sample","default_branch":"main"}' -k
    git init
    git checkout -b main
    git add .
    git commit -m "big bang"
    git remote add origin https://git.$git_repo/tanzu/learning-center-sample.git
    git config http.sslVerify "false"
    echo "git user: $gitea_user / pass: $gitea_pass"
    git push -u origin main
    cd ..

    cd ../..

    export HARBOR_URL=$(yq eval '.image_registry' ./gorkem/values.yaml)
    export HARBOR_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
    mkdir -p /root/nexus-data/
    iptables -I INPUT -p tcp -s 0.0.0.0/0 --dport 8080 -j ACCEPT
    iptables -I INPUT -p tcp -s 0.0.0.0/0 --dport 8081 -j ACCEPT
    cat > /etc/docker/daemon.json <<-EOF
    {
        "data-root": "/docker_storage",
        "insecure-registries" : ["$HARBOR_URL:443"]
    }
EOF
    systemctl restart docker
    docker-compose -f gorkem/templates/tools/nexus-docker-compose.yaml up -d
    export SIVT_VM_IP=$(ip a|grep inet|grep eth0| grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}')
    while true; do
        response=$(curl -s -o /dev/null -w "%{http_code}" "http://$SIVT_VM_IP:8081/" -k)
        
        if [[ "$response" == "200" ]]; then
            echo "Nexus is accessible! (HTTP response code: $response)."
            break
        else
            echo "Nexus is not accessible yet (HTTP response code: $response), will retry again in 45 seconds"
        fi
        
        sleep 45 # Adjust the sleep duration between attempts as needed
    done
    
    export SIVT_VM_IP=$(ip a|grep inet|grep eth0| grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}')
    while [[ -z "$nexus_init_pass_docker" ]]; do
        export nexus_init_pass_docker=$(cat /root/nexus-data/admin.password)
        if [[ -n "$nexus_init_pass_docker" ]]; then
            echo "nexus_init_pass_docker is now non-empty: $nexus_init_pass_docker"
            break
        fi
        sleep 15
    done
    echo $nexus_init_pass_docker
    curl -u "admin:${nexus_init_pass_docker}" -X 'PUT' "http://$SIVT_VM_IP:8081/service/rest/v1/security/users/admin/change-password" -H 'accept: application/json' -H 'Content-Type: text/plain' -d ${HARBOR_PASSWORD} -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'PUT' "http://$SIVT_VM_IP:8081/service/rest/v1/security/anonymous" -H 'accept: application/json' -H 'Content-Type: text/plain' -d '{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}' -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'POST' "http://$SIVT_VM_IP:8081/service/rest/v1/repositories/npm/proxy" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"name": "npm","online": true,"storage": {"blobStoreName": "default","strictContentTypeValidation": true,"writePolicy": "ALLOW"},"cleanup": null,"proxy": {"remoteUrl": "https://registry.npmjs.org","contentMaxAge": 1440,"metadataMaxAge": 1440},"negativeCache": {"enabled": true,"timeToLive": 1440},"httpClient": {"blocked": false,"autoBlock": true,"connection": {"retries": null,"userAgentSuffix": null,"timeout": null,"enableCircularRedirects": false,"enableCookies": false,"useTrustStore": false},"authentication": null},"routingRuleName": null,"npm": {"removeNonCataloged": false,"removeQuarantined": false},"format": "npm","type": "proxy"}' -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'POST' "http://$SIVT_VM_IP:8081/service/rest/v1/security/users" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"userId": "tanzu","firstName": "tanzu","lastName": "tanzu","emailAddress": "tanzu@vmware.com","password": "VMware1!","status": "active","roles": ["nx-admin"]}' -k


elif [ "$1" = "gen-cert" ]; then
    mkdir -p cert/
    cd cert
    export DOMAIN=*.$INGRESS_DOMAIN
    export SUBJ="/C=TR/ST=Istanbul/L=Istanbul/O=Customer, Inc./OU=IT/CN=${DOMAIN}"
    openssl genrsa -des3 -out ca.key -passout pass:1234 4096
cat > ca.conf <<-EOF
[req]
distinguished_name = req_distinguished_name
[req_distinguished_name]
C = TR
ST = Istanbul
L = Istanbul
O = Customer, Inc.
OU = IT
CN = $DOMAIN
[ca]
basicConstraints=CA:TRUE
keyUsage=critical, digitalSignature, keyCertSign, cRLSign
EOF
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -passin pass:1234 -subj "$SUBJ" -extensions ca -config ca.conf -out ca.crt
    openssl genrsa -out server-app.key 4096
    openssl req -sha512 -new \
          -subj "$SUBJ" \
          -key server-app.key \
          -out server-app.csr
cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1=${DOMAIN}
EOF
    openssl x509 -req -sha512 -days 3650 \
          -passin pass:1234 \
          -extfile v3.ext \
          -CA ca.crt -CAkey ca.key -CAcreateserial \
          -in server-app.csr \
          -out server-app.crt
    openssl rsa -in ca.key -out ca-no-pass.key -passin pass:1234
    md5crt=$(openssl x509 -modulus -noout -in server-app.crt | openssl md5|awk '{print $2}')
    md5key=$(openssl rsa -noout -modulus -in server-app.key | openssl md5|awk '{print $2}')
    echo $md5crt
    echo $md5key
    if [ "$md5crt" == "$md5key" ] ;
        then
            echo "Certificates generated successfully"
            #exit 0
        else
            echo "Certificate md5's mismatch. Error."
            exit 1
    fi


    cd ..
else
    echo "Invalid parameter: $1"
    exit 1
fi

