#!/bin/bash


KUBE_VERSION=$(aptitude versions kubectl | grep ^i | cut -d ' ' -f3 | cut -d '-' -f1)
MASTER_IP=$(ip -j -p a | jq  '.[].addr_info | .[] | select(.label == "ens192") | .local' | cut -d '"' -f2)

kubeadm init  --image-repository registry.aliyuncs.com/google_containers  --kubernetes-version ${KUBE_VERSION}  --pod-network-cidr=10.10.0.0/16  --apiserver-advertise-address=${MASTER_IP}
# kubeadm init --kubernetes-version ${KUBE_VERSION}  --pod-network-cidr=10.10.0.0/16  --apiserver-advertise-address=${MASTER_IP}

mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml

# kubectl create -f http://192.168.110.138/tftp/bash/custom-resources.yaml

cat <<EOF | tee /root/custom-resources.yaml
# This section includes base Calico installation configuration.
# For more information, see: https://projectcalico.docs.tigera.io/v3.22/reference/installation/api#operator.tigera.io/v1.Installation
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # Configures Calico networking.
  calicoNetwork:
    # Note: The ipPools section cannot be modified post-install.
    ipPools:
    - blockSize: 26
      cidr: 10.10.0.0/16
      encapsulation: None
      natOutgoing: Enabled
      nodeSelector: all()

---

# This section configures the Calico API server.
# For more information, see: https://projectcalico.docs.tigera.io/v3.22/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}

EOF

kubectl apply -f /root/custom-resources.yaml

kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
