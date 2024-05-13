# Wasm-k8s-workshop

This workshop is divided into the following sections:
- [Wasm-k8s-workshop](#wasm-k8s-workshop)
  - [1. Pre-requisites](#1-pre-requisites)
  - [2. Build and test the app](#2-build-and-test-the-app)
  - [3. Package as OCI container and run it](#3-package-as-oci-container-and-run-it)
  - [4. Push to ttl.sh](#4-push-to-ttlsh)
  - [5. Build a Kind Kubernetes cluster](#5-build-a-kind-kubernetes-cluster)
  - [6. Configure Kubernetes for Wasm](#6-configure-kubernetes-for-wasm)
  - [7. Deploy Wasm app to Kubernetes](#7-deploy-wasm-app-to-kubernetes)
  - [Clean-up](#clean-up)

## 1. Pre-requisites

To complete the workshop, you'll need the following:

- Docker with Wasm features enabled.
  - If you use `colima`, check my `colima` template in the `setup` folder
- Rust with the `wasm32-wasi` target added (run `rustup target add wasm32-wasi` before)
  - rustup 1.27.0
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/) v0.22.0
- [Wasmedge](https://wasmedge.org/docs/start/overview) version 0.13.5

Note: if you want to use the rust app already provided go to step 2.3.

## 2. Build and test the app

2.1 Create a new simple hello world rust app.

```
➜ cargo new wasm-test
```



2.2 Enter the new directory and execute `cargo run` to make sure that your new rust app runs OK:

```
➜ cargo run
   Compiling wasm-test v0.1.0 (/Users/gs/projects/temp/wasm-test)
    Finished dev [unoptimized + debuginfo] target(s) in 0.76s
     Running `target/debug/wasm-test`
Hello, world!
```

2.3 Build the app as a Wasm Module using the `--target wasm32-wasi`:

```
➜ cargo build --target wasm32-wasi --release
   Compiling wasm-test v0.1.0 (/Users/gs/projects/temp/wasm-test)
    Finished release [optimized] target(s) in 0.75s
```

2.4 Run the new Wasm Module using WasmEdge runtime:

```
➜ wasmedge target/wasm32-wasi/release/wasm-test.wasm
Hello, world!
```

Let's now use Docker to understand how today's tool can also work together with Wasm.


## 3. Package as OCI container and run it

You should be in the `root` directory.

3.1 If you have been following the workshop you can use the `Dockerfile` provided:

```
FROM scratch
COPY target/wasm32-wasi/release/wasm-test.wasm /test.wasm
ENTRYPOINT [ "/test.wasm" ]
```

3.2 Run the following command to build the app into an OCI image. The last line will use an anonymous and temporary OCI registry called [ttl.sh](https://ttl.sh) (use it only for testing!):

```
➜ docker buildx build \
  --platform wasi/wasm \
  --provenance=false \
  -t ttl.sh/wasmtest:1d .
```

3.3 Verify the image was built:

```
➜ docker images
REPOSITORY                       TAG       IMAGE ID       CREATED          SIZE
ttl.sh/wasmtest                  1d        de4b93827021   29 seconds ago   2.14MB
```

3.4 Run it on your local Docker environment specifying a Wasm Runtime :

```
➜ docker run --rm \
  --runtime=io.containerd.wasmedge.v1 \
  --platform=wasi/wasm \
  ttl.sh/wasmtest:1d
Hello, world!
```

It works! The app is now packaged as a container and ready to be pushed.

## 4. Push to ttl.sh

4.1 Run the following command to push the image to [ttl.sh](https://ttl.sh). The image tag will say for how long will the image be saved in the registry.

```
docker push ttl.sh/wasmtest:1d
```

With the app built, containerized, and uploaded to a registry, it's time to build a Kubernetes cluster and deploy the app to it.

## 5. Build a Kind Kubernetes cluster

Run the following command to create a Kubernetes cluster with one control plane node, two workers. Give a name to it if you want (in this case was `cnl`).

5.1 Create the cluster and test it.

```
➜ kind create cluster --config setup/kind.yaml --name cnl
...
➜ kubectl get nodes
NAME                STATUS   ROLES           AGE   VERSION
cnl-control-plane   Ready    control-plane   41h   v1.29.2
cnl-worker          Ready    <none>          41h   v1.29.2
cnl-worker2         Ready    <none>          41h   v1.29.2
```

## 6. Configure Kubernetes for Wasm

6.1 To add Wasm capabilities to our cluster we will need [Kwasm Operator](https://kwasm.sh/).
>"Kwasm is a Kubernetes Operator that adds WebAssembly support to your Kubernetes nodes. It does so by using a container image that contains binaries and configuration variables needed to run pure WebAssembly images."

```
# Add helm repo
helm repo add kwasm http://kwasm.sh/kwasm-operator/
# Install operator
helm install -n kwasm --create-namespace kwasm-operator kwasm/kwasm-operator
# Annotate the nodes
kubectl annotate node --all kwasm.sh/kwasm-node=true
```

6.2 Kwasm Operator will create jobs to add the wasm features to each node:

```
➜ kubectl get pods -n kwasm
NAME                                      READY   STATUS      RESTARTS   AGE
cnl-control-plane-provision-kwasm-phq49   0/1     Completed   0          41h
cnl-worker-provision-kwasm-6rlpj          0/1     Completed   0          41h
cnl-worker2-provision-kwasm-nmxq8         0/1     Completed   0          41h
kwasm-operator-69848c8c9c-mcsq9           1/1     Running     0          41h
```

## 7. Deploy Wasm app to Kubernetes

7.1 Check for existing RuntimeClasses.

```
➜ kubectl get runtimeclass
NAME       HANDLER    AGE
```
In this step, we will use wasmedge runtime. You can learn about it here: https://wasmedge.org/

7.2 Run the following command to create a new RuntimeClass called `wasmedge` that calls the `wasmedge` handler or use the already provided file **RuntimeClass.yaml** inside de `k8s`folder.

```
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: wasmedge
handler: wasmedge
EOF
```

7.3 Check it installed correctly.

```
➜ kubectl get runtimeclass
NAME      HANDLER   AGE
wasmedge   wasmedge      1m
```

7.4 Create a new file (or use the already provided inside `k8s` folder) called **Deployment.yaml** and copy in the following content:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-wasm
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-wasm
  template:
    metadata:
      labels:
        app: test-wasm
    spec:
      runtimeClassName: wasmedge
      containers:
        - name: wasmtest
          image: ttl.sh/wasmtest:1d
```

7.5 Deploy it and check it with the following commands.

```
➜ kubectl apply -f k8s/Deployment.yaml
deployment.apps/test-wasm created

➜ kubectl get deploy
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
test-wasm   0/2     2            0           3m42s
```

7.6 Check that the 2 replicas are all scheduled to the nodes with the Wasm runtimes.

```
➜ kubectl get pods
NAME                         READY   STATUS             RESTARTS     AGE
test-wasm-6b64d64647-djc2d   0/1     Completed          1 (4s ago)   53s
test-wasm-6b64d64647-g22nm   0/1     Completed          1 (3s ago)   53s
```

7.7 Check the logs:

```
➜ kubectl logs test-wasm-6b64d64647-djc2d
Hello, world!
```

**Note**: The pods will restart continuously within the Kubernetes deployment because we receive an `ExitCode 0` which indicates the process is finished with success. This happens because the app that we created is not a continuous process.


## Clean-up

If you don't plan on keeping the kind cluster, you can delete it with the following command. This will delete all cluster resources including the Deployment. Be sure to use your cluster name.

```
$ kind delete clusters cnl
```
