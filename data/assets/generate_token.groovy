import jenkins.model.Jenkins
import jenkins.security.ApiTokenProperty
import hudson.model.User

def env = System.getenv()
def username = env['JENKINS_USERNAME']
def user = User.getById(username, true)
def tokenProperty = user.getProperty(ApiTokenProperty.class)
def tokenStore = tokenProperty.getTokenStore()
def result = tokenStore.generateNewToken("automation-token")

user.save()
println("Token: " + result.plainValue)

def filePath = Jenkins.instance.root.getAbsolutePath()
def file = new File(filePath, "api_token.txt")
file.text = result.plainValue