# Kubernetes (k3s) on OCI - Always Free

## resource
https://github.com/tribal2/oci-instance-launch-template
https://itnext.io/how-to-deploy-an-always-free-k3s-cluster-on-the-oracle-cloud-infrastructure-4aed6d6d8604

# Introduction

We are going to setup a website with all infrastructure required to do so. We are going to make use of Oracle Cloud offer 'Always Free' services. 
We will utilize k3s, nginx-ingress, cert-manager and Let's Encrypt to expose the endpoint: 'play.rippel.no'

This repo is a bundle of scripts used for the talk at OUGN23 https://2023.ougn.no/

# Setup

### Configure environment

```
. env.sh
```

### Create oci node

```
./create_instance.sh
```

### Connect to node

```
# The previous script made it easy for us to connect. 
# We do not want to memorize ip addresses and ssh-keys.

./connect.sh
```

### Is k3s installed?
```
# the cloud-init script is working hard so it may take a while

type k3s
k3s is /usr/local/bin/k3s
```

### Are we ready for kubernetes? 
```
k get no -owide
NAME       STATUS   ROLES                  AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                  KERNEL-VERSION                   CONTAINER-RUNTIME
node       Ready    control-plane,master   21h   v1.26.3+k3s1   10.0.1.8      <none>        Oracle Linux Server 9.1   5.15.0-6.80.3.1.el9uek.aarch64   containerd://1.6.19-k3s1
```

### Install ingress controller (baremetal). Note: Already in place via cloud-init

```
# fetch manifests from github directly
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.7.0/deploy/static/provider/baremetal/deploy.yaml

# a way to wait for readiness of a k8s service
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# NodePort 30386
kubectl get svc ingress-nginx-controller -n ingress-nginx
NAME                       TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller   NodePort   10.43.153.116   <none>        80:30386/TCP,443:32652/TCP   21h
```

# Deploy application 'whoami'

### YAML - declarative

```
# upload manifests
scp -i ~/.ssh/id_rsa_oci whoami.deployment.yaml opc@${EXTERNAL_IP}:~
scp -i ~/.ssh/id_rsa_oci whoami.ingress.yaml opc@${EXTERNAL_IP}:~

# apply manifests
kubectl apply -f whoami.deployment.yaml
kubectl apply -f whoami.ingress.yaml
```

### Command - imperative
```
kubectl create deployment whoami --image=docker.io/containous/whoami:v1.5.0
kubectl expose deployment whoami --port=80 --type=NodePort
kubectl create ingress whoami --class=nginx --rule="whoami.127.0.0.1.nip.io/*=whoami:80"
```

# Access to service (there are several ways)
```
kubectl get svc whoami -owide
NAME     TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE     SELECTOR
whoami   NodePort   10.43.146.65   <none>        80:30565/TCP   6m36s   app=whoami

nodeport=$(kubectl get svc whoami -ojson | jq '.spec.ports[0].nodePort')

# hit service directly
curl http://$(hostname):${nodeport}

# hit ingress, no HTTP header Host information
curl -k https://$(hostname):443

# hit ingress, HTTP header info is present 
curl -k -H 'Host: whoami.127.0.0.1.nip.io' https://$(hostname):443

# hit ingress, HTTP header info is present
curl -k https://whoami.127.0.0.1.nip.io:443
```

### External access
```
EXTERNAL_IP=$(oci compute instance list-vnics --instance-id "${INSTANCE_ID}" --query 'data[0]."public-ip"' --raw-output)
curl -k -H 'Host: whoami.127.0.0.1.nip.io' https://${EXTERNAL_IP}:443
```

# The love for certificates in kubernetes

### Install cert-manager

```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.1/cert-manager.yaml
kubectl wait --timeout=300s --for=condition=Available --all -n cert-manager deployments
kubectl get pods --namespace cert-manager
```

### Who is going to issue certs? Yes, it is let's encrypt

```
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: first.last@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

### Do we have contact with the issuer? True or False? 

```
kubectl get clusterissuer -owide
```

### Upload play endpoint manifest, based on the game '2048'

```
scp -i ~/.ssh/id_rsa_oci play.yaml opc@${EXTERNAL_IP}:~
kubectl apply -f play.yaml
```

### Is our play.rippel.no cert issued? (No it isn't)
```
kubectl get certificates -owide -w
```

### Do we have this entry in our DNS? No we don't
```
dig +short play.rippel.no
```

### Suddenly Let's Encrypt can access the public endpoint
```
oci dns record rrset patch \
  --domain "play.rippel.no" \
  --zone-name-or-id "rippel.no" \
  --rtype "A" \
  --items "[{\"domain\":\"play.rippel.no\",\"rtype\":\"A\",\"rdata\":\"${EXTERNAL_IP}\",\"ttl\":30,\"operation\":\"ADD\"}]"
```

### Verify TLS endpoint

```
openssl s_client -connect ${EXTERNAL_IP}:443 -servername play.rippel.no -showcerts 2> /dev/null <<< "Q" | openssl x509 -text -noout | grep -E 'Issuer|Subject|DNS'
```

### Viola! Open in a browser window (Yes, there will be security warnings)
```
./open.sh
```


### Performance test utilizing K6

```
# vus - virtual connections
k6 run --vus 1000 --duration 60s script.js
```

### Cleanup
```
./terminate_instance.sh
```




# troubleshoot [a section for additional tools and ideas]

## Additional tools to install (htop,iotop, etc) install Fedora EPEL 
```
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
```

[opc@ougn_amp ~]$ ss | grep 30386
u_str ESTAB      0      0                                                                                       * 30386                         * 0
# enable port 80 and 443

k edit deployment -n ingress-nginx

template:
  spec:
    hostNetwork: true

sudo netstat -tulpn | grep -E ':80|:443' | grep -v tcp6
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      8781/nginx: master
tcp        0      0 0.0.0.0:443             0.0.0.0:*               LISTEN      8781/nginx: master
tcp6       0      0 :::80                   :::*                    LISTEN      8781/nginx: master
tcp6       0      0 :::443                  :::*                    LISTEN      8781/nginx: master




# let's encrypt

1. create certificate cluster issuer
```
kubectl apply -f cluster-issuer.yaml
kubectl get clusterissuer -owide
```
2. create certificate for ingress
```
./ingress-staging.sh
```
3. status
```
kubectl get certificate -o wide
```
4. verify
```
openssl s_client -connect ${EXTERNAL_IP}.nip.io:443 -servername ${EXTERNAL_IP}.nip.io -showcerts 2> /dev/null <<< "Q" | openssl x509 -text -noout | grep -E 'Issuer|Subject|DNS'
```
5. open in browser
```
open http://${EXTERNAL_IP}.nip.io
```

### We need to build an image for ARM arhitecture.
```
git clone https://github.com/alexwhen/docker-2048.git
cd docker-2048

cat > Dockerfile <<EOF
FROM docker.io/arm64v8/nginx:1.23.4-alpine
COPY 2048 /usr/share/nginx/html/
EXPOSE 80
CMD ["-g", "daemon off;"]
ENTRYPOINT ["/usr/sbin/nginx"]
EOF

sudo yum install -y podman
podman build -t "docker-2048" .
podman tag docker-2048:latest docker.io/bjarteb/2048:arm-v3
scp -i ~/.ssh/id_rsa_oci ~/.config/token opc@${EXTERNAL_IP}:~
cat ~/token | podman login docker.io --username <your-username> --password-stdin
podman push docker.io/bjarteb/2048:arm-v3
```


```
docker compose up -d
open http://localhost:8080

podman run -d --rm --name game -p 8080:80 docker.io/bjarteb/2048:arm
```