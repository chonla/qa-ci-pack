# QACI Pack

QACI Pack includes CI tools for testing.

## What is in QACI Pack

* Jenkins
* Sonatype Nexus
* Allure Report

## Service domains

* Jenkins -> https://jenkins.localhost
* Nexus -> https://nexus.localhost
* Allure Report -> https://allure.localhost

## Start Services

```
docker-compose up -d
```

## To check if services are up

Use docker ps to see if all services are up, healthy.

```
docker ps
```

## Initialize Services

Once services are up and running, execute initialization script. This script will install Jenkins plugins, initialize Nexus registries, etc.

```
./data/scripts/init.sh
```

## Using *.localhost

All services are reachable by *.localhost domain name. To use this Caddy must be installed and run with this command.

```
caddy run
```

## Installing Caddy

```
brew install caddy
```