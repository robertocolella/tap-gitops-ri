#!/bin/bash

# Get the Kubernetes server version
SERVER_VERSION=$(kubectl version --short | awk -Fv '/Server Version: /{print substr($3,0,4)}')

#check if kubernetes version is retrieved.
if [ -z "$SERVER_VERSION" ]; then
  echo "Error: Failed to retrieve Kubernetes server version"
  exit 1
fi

# Check if the server version is less than 1.24
if (( $(echo "$SERVER_VERSION < 1.25" | bc -l) )); then
  echo "Kubernetes server version is less than 1.25"
  echo "For TAP1.6, you must have minimum k8s 1.25"
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


# kapp
if ! command -v kapp >/dev/null 2>&1 ; then
  echo "kapp not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/carvel-dev/kapp/releases/download/v0.55.0/kapp-darwin-amd64 && chmod +x kapp-darwin-amd64 && mv kapp-darwin-amd64 kapp && cp kapp /usr/local/bin/kapp"
  echo "uname -s| grep Linux && wget https://github.com/carvel-dev/kapp/releases/download/v0.55.0/kapp-linux-amd64 && chmod +x kapp-linux-amd64 && mv kapp-linux-amd64 kapp && cp kapp /usr/local/bin/kapp"
  echo "Exiting...."
  exit 1

fi

# imgpkg
if ! command -v imgpkg >/dev/null 2>&1 ; then
  echo "imgpkg not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/carvel-dev/imgpkg/releases/download/v0.31.3/imgpkg-darwin-amd64 && chmod +x imgpkg-darwin-amd64 && cp imgpkg-darwin-amd64 /usr/local/bin/imgpkg"
  echo "uname -s| grep Linux && wget https://github.com/carvel-dev/imgpkg/releases/download/v0.31.3/imgpkg-linux-amd64 && chmod +x imgpkg-linux-amd64 && cp imgpkg-linux-amd64 /usr/local/bin/imgpkg"
  echo "Exiting...."
  exit 1
fi

# minio mc client
if ! command -v mc >/dev/null 2>&1 ; then
  echo "mc not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://dl.min.io/client/mc/release/darwin-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc"
  echo "uname -s| grep Linux && wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc"
  echo "Exiting...."
  exit 1
fi

if [ -f tanzu-gitops-ri-*.tgz ] && [ -f gorkem/values.yaml ]; then
    echo "required files exist, continuing."
else
    echo "check tanzu-gitops-ri-*.tgz and/or gorkem/values.yaml do not exist."
    exit 1
fi


rm -rf .git
rm -rf .catalog
rm -rf clusters
rm -rf setup-repo.sh

# GitOps Ref. Implementation
tar -xvf tanzu-gitops-ri-*.tgz
./setup-repo.sh full-profile sops

#cp ./gorkem/templates/values-template.yaml ./gorkem/values.yaml

kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated

export AIRGAPPED=$(yq eval '.airgapped' gorkem/values.yaml)

export KAPP_NS=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.status.phase}{"\n"}{end}'|awk '{print $1}')
export KAPP_POD=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'|awk '{print $1}')

if [ -n "$KAPP_NS" ]; then
    echo "kapp is running"
else
    echo "kapp is not running, therefore installing."
    export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:54e516b5d088198558d23cababb3f907cd8073892cacfb2496bb9d66886efe15
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
export TAP_VERSION=$(yq eval '.tap_version' ./gorkem/values.yaml)

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' ./gorkem/values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' ./gorkem/values.yaml)
export GIT_SSH_PRIVATE_KEY=$(cat $HOME/.ssh/id_rsa &>/dev/null || ssh-keygen -b 2048 -t rsa -f /$HOME/.ssh/id_rsa -q -N "" && cat $HOME/.ssh/id_rsa)
export SOPS_AGE_KEY=$(cat ./gorkem/tmp-enc/key.txt)
export SOPS_AGE_SECRET_KEY=$(cat ./gorkem/tmp-enc/key.txt|grep AGE-SECRET-KEY)
export GIT_USER=$(yq eval '.git.gitea.git_user' gorkem/values.yaml)
export GIT_PASS=$(yq eval '.git.gitea.git_password' gorkem/values.yaml)
export GIT_REPO=$(yq eval '.git.push_repo.fqdn' gorkem/values.yaml)

ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tap-sensitive-values.yaml > ./gorkem/tmp-enc/tap-sensitive-values.yaml
ytt --ignore-unknown-comments -f ./gorkem/values.yaml --data-value age_key=$SOPS_AGE_SECRET_KEY -f ./gorkem/templates/tanzu-sync-values.yaml > ./gorkem/tmp-enc/tanzu-sync-values.yaml

export SOPS_AGE_RECIPIENTS=$(cat ./gorkem/tmp-enc/key.txt | grep "# public key: " | sed 's/# public key: //')
sops --encrypt ./gorkem/tmp-enc/tap-sensitive-values.yaml > ./gorkem/tmp-enc/tap-sensitive-values.sops.yaml
mv ./gorkem/tmp-enc/tap-sensitive-values.sops.yaml ./clusters/full-profile/cluster-config/values

sops --encrypt ./gorkem/tmp-enc/tanzu-sync-values.yaml > ./gorkem/tmp-enc/tanzu-sync-values.sops.yaml
mv ./gorkem/tmp-enc/tanzu-sync-values.sops.yaml ./clusters/full-profile/tanzu-sync/app/sensitive-values/tanzu-sync-values.sops.yaml

ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/custom-schema-template.yaml > ./clusters/full-profile/cluster-config/config/custom-schema.yaml
cp ./gorkem/templates/acs.yaml ./clusters/full-profile/cluster-config/config/acs.yaml
cp ./gorkem/templates/scg.yaml ./clusters/full-profile/cluster-config/config/scg.yaml
if [ "$AIRGAPPED" = "true" ]; then
  export IMGPKG_REGISTRY_HOSTNAME_1=$(yq eval '.image_registry' ./gorkem/values.yaml)
  export TAP_PKGR_REPO=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap
  cp ./gorkem/templates/tbs-full-deps.yaml ./clusters/full-profile/cluster-config/config/tbs-full-deps.yaml
  export multi_line_text="#@data/values-schema\n#@overlay/match-child-defaults missing_ok=True\n---"
  echo -e "$multi_line_text" | cat - ./clusters/full-profile/cluster-config/config/custom-schema.yaml > temp && mv temp ./clusters/full-profile/cluster-config/config/custom-schema.yaml
fi
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tap-non-sensitive-values-template.yaml > ./clusters/full-profile/cluster-config/values/tap-values.yaml


git init && git add . && git commit -m "Big Bang" && git branch -M main
git remote add origin $GIT_REPO
git config http.sslVerify "false"
git push -u origin main

cd ./clusters/full-profile
./tanzu-sync/scripts/configure.sh
cd ../../

tanzu secret registry add registry-credentials --username $HARBOR_USERNAME --password $HARBOR_PASSWORD --server $HARBOR_URL --namespace default --export-to-all-namespaces
tanzu secret registry add lsp-push-credentials --username push-user --password 'VMware1!' --server $HARBOR_URL --namespace default
tanzu secret registry add lsp-pull-credentials --username pull-user --password 'VMware1!' --server $HARBOR_URL --namespace default

mkdir -p ./clusters/full-profile/cluster-config/dependant-resources/tools
mkdir -p ./clusters/full-profile/cluster-config/dependant-resources/others

if [ "$AIRGAPPED" = "true" ]; then
  export GIT_REPO=https://git.$(yq eval '.git.gitea.git_repo' gorkem/values.yaml)
  export GIT_USER=$(yq eval '.git.gitea.git_user' gorkem/values.yaml)
  export GIT_PASS=$(yq eval '.git.gitea.git_password' gorkem/values.yaml)
  export MAVEN_REPO=$(yq eval '.maven_repo' gorkem/values.yaml)
  export NPM_REPO=$(yq eval '.npm_repo' gorkem/values.yaml)
  export NUGET_REPO=$(yq eval '.nuget_repo' gorkem/values.yaml)
  export CA_CERT=$(yq eval '.ca_cert_data' ./gorkem/values.yaml)
  export OTHER_CA_CERT=$(yq eval '.other_ca_cert_data' ./gorkem/values.yaml)
  export ALL_CA_CERT=$(echo -e "$CA_CERT""\n""$OTHER_CA_CERT")
  export INGRESS_DOMAIN=$(yq eval '.ingress_domain' ./gorkem/values.yaml)

cat > ./clusters/full-profile/cluster-config/dependant-resources/tools/workload-git-auth.yaml <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: workload-git-auth
  namespace: tap-install
type: Opaque
stringData:
  content.yaml: |
    repo:
      maven: $MAVEN_REPO
      npm: $NPM_REPO
      nuget: $NUGET_REPO
    git:
      ingress_domain: $INGRESS_DOMAIN
      host: $GIT_REPO
      username: $GIT_USER
      password: $GIT_PASS
      caFile: |
$(echo "$ALL_CA_CERT" | sed 's/^/        /')
EOF
  
  export remote_branch_=$( git status --porcelain=2 --branch | grep "^# branch.upstream" | awk '{ print $3 }' )
  export remote_name_=$( echo $remote_branch_ | awk -F/ '{ print $1 }' )
  export remote_url_=$( git config --get remote.${remote_name_}.url )
  ytt --ignore-unknown-comments --data-value git_push_repo=$remote_url_ -f gorkem/templates/dependant-resources-app.yaml > clusters/full-profile/cluster-config/config/dependant-resources-app.yaml
  
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/local-issuer.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/local-issuer.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/git.yml > clusters/full-profile/cluster-config/dependant-resources/others/gitea.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/nexus.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/nexus.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/minio.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/minio.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/crossplane-ca.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/crossplane-ca.yaml
  mkdir -p ./gorkem/templates/overlays/ && cp -r ./gorkem/templates/overlays/ clusters/full-profile/cluster-config/dependant-resources/overlays
  #cp ./gorkem/templates/tools/external-secrets.yaml clusters/full-profile/cluster-config/dependant-resources/tools/external-secrets.yaml
  #ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/vault.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/vault.yaml
fi
cp ./gorkem/templates/tools/openldap.yaml clusters/full-profile/cluster-config/dependant-resources/tools/openldap.yaml
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/dex.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/dex.yaml
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/efk.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/efk.yaml
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/octant.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/octant.yaml

export TAP_VERSION_ORG="1.6.1"
sed -i "s/$TAP_VERSION_ORG/$TAP_VERSION/g" ./clusters/full-profile/cluster-config/config/tap-install/.tanzu-managed/version.yaml

cd ./clusters/full-profile

git add ./cluster-config/ ./tanzu-sync/
git commit -m "Configure install of TAP $TAP_VERSION"
git config http.sslVerify "false"
git push

./tanzu-sync/scripts/deploy.sh