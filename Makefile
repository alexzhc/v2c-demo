VM ?= lamp
VM_CONF ?= lamp.ovf
VM_DISK ?= lamp_disk0.vmdk
VM_DISK_FORMAT ?= vmdk
TMP_SC ?= local-path
ROOT_SC ?= local-path
GET_VM_FILES_IMAGE ?= docker.m.daocloud.io/vmware/powerclicore 
GET_VM_FILES_SCRIPT ?= ./sh/get-vm-files_vmware.ps1
LOAD_ROOT_VOLUME_SCRIPT ?= ./sh/load-root-volume.sh
PREPARE_CONTAINER_SCRIPT ?= ./sh/prepare-container.sh
START_CONTAINER_SCRIPT ?= ./sh/start-container.sh
VCSA_USERNAME ?= vcsa
VCSA_PASSWORD ?= vcsa

docker:
	for i in binless libguestfs-tools kubectl; do \
		docker build . -f Dockerfile.$$i -t $$i; \
	done

kc:
	docker build . -f Dockerfile.kubectl -t kubectl 

push:
	for i in binless libguestfs-tools kubectl; do \
		docker tag $$i daocloud.io/daocloud/$$i; \
		docker push daocloud.io/daocloud/$$i || \
		docker push daocloud.io/daocloud/$$i; \
	done 

prep:
	kubectl delete configmap v2c-$(VM) || true
	kubectl create configmap v2c-$(VM) \
		--from-file=get-vm-files=$(GET_VM_FILES_SCRIPT) \
		--from-file=load-root-volume=$(LOAD_ROOT_VOLUME_SCRIPT) \
		--from-file=prepare-container=$(PREPARE_CONTAINER_SCRIPT) \
		--from-file=start-container=$(START_CONTAINER_SCRIPT)
	kubectl delete secret v2c-$(VM) || true
	kubectl create secret generic v2c-$(VM) \
		--from-literal=vcsa_username='$(VCSA_USERNAME)' \
		--from-literal=vcsa_password='$(VCSA_PASSWORD)'

run1:
	helm install get-vm-files-$(VM) ./Charts/get-vm-files/ \
		--set vm.name=$(VM) \
		--set job.image=$(GET_VM_FILES_IMAGE) \
		--set pvc.storageClass=$(TMP_SC)
	kubectl wait --for=condition=complete --timeout=1200s job/get-vm-files-$(VM)
unrun1:
	helm uninstall get-vm-files-$(VM)
urun1: unrun1
log1:
	kubectl logs -f job/get-vm-files-$(VM)

run2:
	helm install load-root-volume-$(VM) ./Charts/load-root-volume/ \
		--set vm.name=$(VM) \
		--set vm.disk=$(VM_DISK) \
		--set vm.diskFormat=$(VM_DISK_FORMAT) \
		--set pvc.storageClass=$(ROOT_SC)
	kubectl wait --for=condition=complete --timeout=1200s job/load-root-volume-$(VM)
unrun2:
	helm uninstall load-root-volume-$(VM)
urun2: unrun2
log2:
	kubectl logs -f job/load-root-volume-$(VM)

run3:
	helm install prepare-container-$(VM) ./Charts/prepare-container/ \
		--set vm.name=$(VM) \
		--set vm.config=$(VM_CONF) \
		--set vm.diskFormat=$(VM_DISK_FORMAT)
	kubectl wait --for=condition=complete --timeout=1200s job/prepare-container-$(VM)
unrun3:
	helm uninstall prepare-container-$(VM)
urun3: unrun3
log3:
	kubectl logs -f job/prepare-container-$(VM)

run4:
	kubectl get cm v2c-$(VM)-conf -o yaml | yq '.data["values.yaml"]' > /tmp/values.yaml
	helm install start-container-$(VM) ./Charts/start-container/ \
		--set vm.name=$(VM) \
		-f /tmp/values.yaml
	watch kubectl get po
unrun4:
	helm uninstall start-container-$(VM)
urun4: unrun4
log4:
	kubectl logs -f job/start-container-$(VM)

all: run1 run2 run3 run4
unall: unrun4 unrun3 unrun2 unrun1
	kubectl delete cm v2c-$(VM) v2c-$(VM)-conf
	kubectl delete secret v2c-$(VM)
uall: unall

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



