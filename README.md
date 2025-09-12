# QACI Pack

QACI Pack includes CI tools for testing.

## What is in QACI Pack

* Jenkins
* Sonatype Nexus
* Allure Report

## Installation

```
docker-compose up -d
```

## Initialize Services

Once services are up and running, execute initializing script.

```
./init.sh
```

## Using *.localhost

Caddy must be installed.

```
caddy run
```

* Jenkins -> jenkins.localhost
* Nexus -> nexus.localhost
* Allure Report -> allure.localhost
