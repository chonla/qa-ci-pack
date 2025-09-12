#!/usr/bin/env groovy
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState
import hudson.cli.CLI
import java.nio.file.Files
import java.nio.file.Paths

def instance = Jenkins.getInstance()

println '--> creating local user from environment variable'

def env = System.getenv()
def username = env['JENKINS_USERNAME']
def password = env['JENKINS_PASSWORD']

// Create user with custom pass
def realm = new HudsonPrivateSecurityRealm(false, false, null)
instance.setSecurityRealm(realm)
def user = realm.createAccount(username, password)
user.save()

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

if (!instance.installState.isSetupComplete()) {
  println '--> Neutering SetupWizard'
  InstallState.INITIAL_SETUP_COMPLETED.initializeState()
}
instance.save()
