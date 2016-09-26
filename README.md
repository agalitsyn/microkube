# Microkube

Smaller than minikube.

Kubernetes quickstart was [docker](https://github.com/kubernetes/kubernetes.github.io/blob/ab612c6bd6f783fb79d2d876e3ab2ed7cc47d429/docs/getting-started-guides/docker.md).
But it was supressed by [minikube](https://github.com/kubernetes/minikube).

Use of local docker have several advantages, like:
* It uses the same docker as you use, so all builded images are available without need to create private docker registry.
* Same PID and network space, easy to strace and dump traffic.
* Easy to test services without need of expose them.
* Also, on linux using VM looks like overhead.

Originally was created in need as part of experimental project [yagoda](https://github.com/agalitsyn/yagoda).
