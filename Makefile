VM ?= lamp
VM_CONF ?= lamp.ovf
VM_DISK ?= lamp_disk0.vmdk
VM_DISK_FORMAT ?= vmdk

NFS_HOST_SHARE ?= server.nfs.local # change to your own
NFS_HOST_SSH ?= ssh.nfs.local # change to your own
NFS_HOST_SSH_USERNAME ?= ssh # change to your own
NFS_HOST_SSH_PASSWORD ?= ssh # change to your own

ISCSI_HOST_PORTAL ?= "" # change to your own
ISCSI_HOST_INTERFACE ?= "" # change to your own
ISCSI_HOST_SSH ?= ssh.scsi.local # change to your own
ISCSI_HOST_SSH_USERNAME ?= ssh # change to your own
ISCSI_HOST_SSH_PASSWORD ?= ssh # change to your own

TMP_SC ?= local-hostpath
ROOT_SC ?= iscsi-zfs
PVC_ACCESS_MODE=ReadWriteOnce # or ReadWriteOncePod for k8s >= 1.22
PVC_VOLUME_MODE=Filesystem # or Block 

GET_VM_FILES_IMAGE ?= daocloud.io/daocloud/powerclicore:no-cert-check
GET_VM_FILES_SCRIPT ?= ./sh/get-vm-files_vmware.ps1

LOAD_ROOT_VOLUME_SCRIPT ?= ./sh/load-root-volume.sh
PREPARE_CONTAINER_SCRIPT ?= ./sh/prepare-container.sh
START_CONTAINER_SCRIPT ?= ./sh/start-container.sh
SYSTEMCTL_REPLACE ?= ./sh/systemctl.py

VCSA_HOST ?= vcsa # change to your own
VCSA_USERNAME ?= vcsa # change to your own
VCSA_PASSWORD ?= vcsa # change to your own

KUBELET_ROOT=/var/snap/microk8s/common/var/lib/kubelet

# Make container images
docker:
	for i in binless libguestfs-tools kubectl; do \
		docker build . -f Dockerfile.$$i -t $$i; \
	done
push:
	for i in binless libguestfs-tools kubectl; do \
		docker tag $$i daocloud.io/daocloud/$$i; \
		docker push daocloud.io/daocloud/$$i || \
		docker push daocloud.io/daocloud/$$i; \
	done

# Set up NFS and Local-Path storages
nfs: snapctrl
	helm upgrade --install zfs-nfs storage/democratic-csi/ \
	--namespace democratic-csi --create-namespace \
	--values storage/democratic-csi/zfs-generic-nfs.yaml \
	--set node.kubeletHostPath=$(KUBELET_ROOT) \
	--set driver.config.sshConnection.host=$(NFS_HOST_SSH) \
	--set driver.config.sshConnection.username=$(NFS_HOST_SSH_USERNAME) \
	--set driver.config.sshConnection.password=$(NFS_HOST_SSH_PASSWORD) \
	--set driver.config.nfs.shareHost=$(NFS_HOST_SHARE)
un-nfs:
	helm delete zfs-nfs -n democratic-csi

# targetcli host: "pip install rtslib-fb" 
# for error "Not a directory: '/sys/kernel/config/target/iscsi/cpus_allowed_list"
# fix in v2.1.76 https://github.com/open-iscsi/rtslib-fb/commit/8d2543c4da62e962661011fea5b19252b9660822
iscsi:
	helm upgrade --install zfs-iscsi storage/democratic-csi/ \
	--namespace democratic-csi --create-namespace \
	--values storage/democratic-csi/zfs-generic-iscsi.yaml \
	--set node.kubeletHostPath=$(KUBELET_ROOT) \
	--set driver.config.sshConnection.host=$(ISCSI_HOST_SSH) \
	--set driver.config.sshConnection.username=$(ISCSI_HOST_SSH_USERNAME) \
	--set driver.config.sshConnection.password=$(ISCSI_HOST_SSH_PASSWORD) \
	--set driver.config.iscsi.targetPortal=$(ISCSI_HOST_PORTAL)
un-iscsi:
	helm delete zfs-iscsi -n democratic-csi

local: 
	helm install local-hostpath storage/democratic-csi/ \
	--values storage/democratic-csi/local-hostpath.yaml \
	--set node.kubeletHostPath=$(KUBELET_ROOT) \
	--namespace democratic-csi \
	--create-namespace
un-local:
	helm delete local-hostpath -n democratic-csi

snapctrl:
	helm upgrade --install snapshot-controller storage/snapshot-controller \
	--namespace kube-system

# Prepare scripts and login
prep:
	kubectl delete configmap v2c-$(VM) || true
	kubectl create configmap v2c-$(VM) \
		--from-file=get-vm-files=$(GET_VM_FILES_SCRIPT) \
		--from-file=load-root-volume=$(LOAD_ROOT_VOLUME_SCRIPT) \
		--from-file=prepare-container=$(PREPARE_CONTAINER_SCRIPT) \
		--from-file=start-container=$(START_CONTAINER_SCRIPT) \
		--from-file=systemctl=$(SYSTEMCTL_REPLACE)
	kubectl delete secret v2c-$(VM) || true
	kubectl create secret generic v2c-$(VM) \
		--from-literal=vcsa_host='$(VCSA_HOST)' \
		--from-literal=vcsa_username='$(VCSA_USERNAME)' \
		--from-literal=vcsa_password='$(VCSA_PASSWORD)'

# Run steps
run1:
	helm install 1-get-vm-files-$(VM) ./steps/get-vm-files/ \
		--set vm.name=$(VM) \
		--set job.image=$(GET_VM_FILES_IMAGE) \
		--set pvc.storageClass=$(TMP_SC) \
		--set pvc.accessMode=$(PVC_ACCESS_MODE)
	kubectl wait --for=condition=complete --timeout=1200s job/1-get-vm-files-$(VM)
unrun1:
	helm uninstall 1-get-vm-files-$(VM)
urun1: unrun1
log1:
	kubectl logs -f job/1-get-vm-files-$(VM)

run2:
	helm install 2-load-root-volume-$(VM) ./steps/load-root-volume/ \
		--set vm.name=$(VM) \
		--set vm.disk=$(VM_DISK) \
		--set vm.diskFormat=$(VM_DISK_FORMAT) \
		--set pvc.storageClass=$(ROOT_SC) \
		--set pvc.accessMode=$(PVC_ACCESS_MODE) \
		--set pvc.volumeMode=$(PVC_VOLUME_MODE)
	kubectl wait --for=condition=complete --timeout=1200s job/2-load-root-volume-$(VM)
unrun2:
	helm uninstall 2-load-root-volume-$(VM)
urun2: unrun2
log2:
	kubectl logs -f job/2-load-root-volume-$(VM)

run3:
	helm install 3-prepare-container-$(VM) ./steps/prepare-container/ \
		--set vm.name=$(VM) \
		--set vm.config=$(VM_CONF) \
		--set vm.diskFormat=$(VM_DISK_FORMAT)
	kubectl wait --for=condition=complete --timeout=1200s job/3-prepare-container-$(VM)
unrun3:
	helm uninstall 3-prepare-container-$(VM)
urun3: unrun3
log3:
	kubectl logs -f job/3-prepare-container-$(VM)

run4:
	kubectl get cm v2c-$(VM)-conf -o yaml | yq '.data["values.yaml"]' > /tmp/values.yaml
	helm install 4-start-container-$(VM) ./steps/start-container/ \
		--set vm.name=$(VM) \
		-f /tmp/values.yaml
	watch kubectl get po
unrun4:
	helm uninstall 4-start-container-$(VM)
urun4: unrun4
log4:
	kubectl logs -f job/4-start-container-$(VM)

all: prep run1 run2 run3 run4
unall: unrun4 unrun3 unrun2 unrun1
	kubectl delete cm v2c-$(VM) v2c-$(VM)-conf
	kubectl delete secret v2c-$(VM)
uall: unall

# Operate the container
ssh: 
	node=$$(kubectl get po $(VM)-0 -o yaml | yq .spec.nodeName); \
	ip=$$(kubectl get no $$node -o yaml | yq '.status.addresses[] | select (.type=="InternalIP") | .address'); \
	port=$$(kubectl get svc $(VM) -o yaml | yq '.spec.ports[] | select(.name == "ssh") | .nodePort'); \
	ssh root@$$ip -p $$port

curl:
	node=$$(kubectl get po $(VM)-0 -o yaml | yq .spec.nodeName); \
	ip=$$(kubectl get no $$node -o yaml | yq '.status.addresses[] | select (.type=="InternalIP") | .address'); \
	port=$$(kubectl get svc $(VM) -o yaml | yq '.spec.ports[] | select(.name == "http") | .nodePort'); \
	curl http://$$ip:$$port/info.php

stop:
	kubectl scale sts/$(VM) --replicas=0
start:
	kubectl scale sts/$(VM) --replicas=1
restart:
	kubectl rollout restart sts/$(VM)
move:
	node=$$(kubectl get po $(VM)-0 -o yaml | yq .spec.nodeName); \
	kubectl cordon $$node; \
	kubectl rollout restart sts $(M); \
	kubectl wait --for=jsonpath='{.status.phase}'=Pending --timeout=60s pod/$(VM)-0; \
	kubectl uncordon $$node

clone:
	kubectl get cm v2c-$(VM)-conf -o yaml | yq '.data["values.yaml"]' > /tmp/values.yaml
	helm install clone-container-$(VM) ./operations/clone-container/ \
		--set vm.name=$(VM) \
		--set pvc.storageClass=$(ROOT_SC) \
		--set pvc.accessMode=$(PVC_ACCESS_MODE) \
		-f /tmp/values.yaml
	watch kubectl get po
unclone:
	helm uninstall clone-container-$(VM)

snap:
	kubectl get cm v2c-$(VM)-conf -o yaml | yq '.data["values.yaml"]' > /tmp/values.yaml
	helm install snapshot-container-$(VM) ./operations/snapshot-container/ \
		--set vm.name=$(VM) \
		--set pvc.storageClass=$(ROOT_SC) \
		--set pvc.accessMode=$(PVC_ACCESS_MODE) \
		-f /tmp/values.yaml
	watch kubectl get po
unsnap:
	helm uninstall snapshot-container-$(VM)





