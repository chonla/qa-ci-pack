# Note for QA CI Pack development

## Listing plugins installed in Jenkins using Jenkins Script Console

```groovy
Jenkins.instance.pluginManager.plugins.each { plugin -> println plugin.getShortName() }
```

## Adding host public key to known-hosts file

```bash
ssh-keyscan hostname.example.com >> ~/.ssh/known_hosts
```
