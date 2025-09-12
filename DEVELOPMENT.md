# Note for QA CI Pack development

## Listing plugins installed in Jenkins using Jenkins Script Console

```groovy
Jenkins.instance.pluginManager.plugins.each { plugin -> println plugin.getShortName() }
```