VM ?= lamp
VM_CONF ?= lamp.ovf
VM_DISK ?= lamp_disk0.vmdk
VM_DISK_FORMAT ?= vmdk

NFS_HOST_SHARE ?= server.nfs.local # change to your own
NFS_HOST_SSH ?= ssh.nfs.local # change to your own
NFS_HOST_SSH_USERNAME ?= ssh # change to your own
NFS_HOST_SSH_PASSWORD ?= ssh # change to your own

TMP_SC ?= local-hostpath
ROOT_SC ?= nfs-zfs
PVC_ACCESS_MODE=ReadWriteOnce # or ReadWriteOnce for k8s >= 1.22

GET_VM_FILES_IMAGE ?= docker.m.daocloud.io/vmware/powerclicore 
GET_VM_FILES_SCRIPT ?= ./sh/get-vm-files_vmware.ps1

LOAD_ROOT_VOLUME_SCRIPT ?= ./sh/load-root-volume.sh
PREPARE_CONTAINER_SCRIPT ?= ./sh/prepare-container.sh
START_CONTAINER_SCRIPT ?= ./sh/start-container.sh

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
nfs:
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

local:
	helm install local-hostpath storage/democratic-csi/ \
	--values storage/democratic-csi/local-hostpath.yaml \
	--set node.kubeletHostPath=$(KUBELET_ROOT) \
	--namespace democratic-csi \
	--create-namespace
un-local:
	helm delete local-hostpath -n democratic-csi

snapctrl:
	helm install snapshot-controller storage/snapshot-controller \
	--namespace kube-system

# Prepare scripts and login
prep:
	kubectl delete configmap v2c-$(VM) || true
	kubectl create configmap v2c-$(VM) \
		--from-file=get-vm-files=$(GET_VM_FILES_SCRIPT) \
		--from-file=load-root-volume=$(LOAD_ROOT_VOLUME_SCRIPT) \
		--from-file=prepare-container=$(PREPARE_CONTAINER_SCRIPT) \
		--from-file=start-container=$(START_CONTAINER_SCRIPT)
	kubectl delete secret v2c-$(VM) || true
	kubectl create secret generic v2c-$(VM) \
		--from-literal=vcsa_host='$(VCSA_HOST)' \
		--from-literal=vcsa_username='$(VCSA_USERNAME)' \
		--from-literal=vcsa_password='$(VCSA_PASSWORD)'

# Run stages
run1:
	helm install 1-get-vm-files-$(VM) ./stages/get-vm-files/ \
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
	helm install 2-load-root-volume-$(VM) ./stages/load-root-volume/ \
		--set vm.name=$(VM) \
		--set vm.disk=$(VM_DISK) \
		--set vm.diskFormat=$(VM_DISK_FORMAT) \
		--set pvc.storageClass=$(ROOT_SC) \
		--set pvc.accessMode=$(PVC_ACCESS_MODE)	
	kubectl wait --for=condition=complete --timeout=1200s job/2-load-root-volume-$(VM)
unrun2:
	helm uninstall 2-load-root-volume-$(VM)
urun2: unrun2
log2:
	kubectl logs -f job/2-load-root-volume-$(VM)

run3:
	helm install 3-prepare-container-$(VM) ./stages/prepare-container/ \
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
	helm install 4-start-container-$(VM) ./stages/start-container/ \
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
	kubectl apply -f clone.yaml
unclone:
	kubectl delete -f clone.yaml

snap:
	kubectl apply -f snapshot.yaml
unsnap:
	kubectl delete -f snapshot.yaml





