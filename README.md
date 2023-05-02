# Tanzu GitOps Reference Implementation (WIP)

## Getting Started Quick

Create the ```values.yaml``` from the ```values-template.yaml``` file.

```
$ cp ./gorkem/templates/values-template.yaml ./gorkem/values.yaml
```

Then, update the ```./gorkem/values.yaml``` file for TAP values.

For airgapped environments, run the ```00-airgapped-prep.sh``` script.

Downloading required all packages.
```
$ ./00-airgapped-prep.sh prep
```

Importing required all CLIs
```
$ ./00-airgapped-prep.sh import-cli
```

Importing required all packages.
```
$ ./00-airgapped-prep.sh import-packages
```

Then run the ```01-setup.sh``` for installation
```
$ ./01-setup.sh
```
