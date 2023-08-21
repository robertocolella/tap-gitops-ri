# Tanzu GitOps Reference Implementation (WIP)

## Getting Started Quick

Fork the repo.

Create the ```values.yaml``` from the ```values-template.yaml``` file.

```
cp ./gorkem/templates/values-template.yaml ./gorkem/values.yaml
```

Then, update the ```./gorkem/values.yaml``` file for TAP values.

If you need to create required certificates:
```
./00-airgapped-prep.sh gen-cert
```

To update ```./gorkem/values.yaml``` file with CA Certs:
```
export TAP_CA_CERT=$(cat ./cert/ca.crt)
yq e -i ".ca_cert_data = strenv(TAP_CA_CERT)" ./gorkem/values.yaml

export TAP_CA_KEY=$(cat ./cert/ca-no-pass.key)
yq e -i ".ca_cert_key = strenv(TAP_CA_KEY)" ./gorkem/values.yaml
```

Downloading required all packages.
```
./00-airgapped-prep.sh prep
```

Importing required all CLIs
```
./00-airgapped-prep.sh import-cli
```

Importing required all packages.
```
./00-airgapped-prep.sh import-packages
```

Then run the ```01-setup.sh``` for installation
```
./01-setup.sh
```

Finally, run the post install command.
```
./00-airgapped-prep.sh post-install
```