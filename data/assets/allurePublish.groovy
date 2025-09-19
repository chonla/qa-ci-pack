// vars/allurePublish.groovy
import groovy.json.JsonOutput

def call(Map a = [:]) {
  String pattern       = a.pattern       ?: error('pattern is required')
  String projectId     = a.projectId     ?: error('projectId is required')
  String server        = a.server        ?: (env.ALLURE_API      ?: error('server/ALLURE_API is required'))
  String user          = a.user          ?: (env.ALLURE_USER     ?: error('user/ALLURE_USER is required'))
  String password      = a.password      ?: (env.ALLURE_PASSWORD ?: error('password/ALLURE_PASSWORD is required'))
  String executionName = a.executionName ?: "Build #${env.BUILD_NUMBER}"
  String executionFrom = a.executionFrom ?: 'jenkins'
  String executionType = a.executionType ?: 'ci'

  // 1) pack allure-results as JSON
  def results = []
  findFiles(glob: pattern).each { f ->
    def b64 = readFile(file: f.path, encoding: 'Base64')
    if (b64?.trim()) results << [file_name: f.name, content_base64: b64]
  }
  String resultsJson = JsonOutput.toJson([results: results])

  // 2) login
  def loginResp = httpRequest(
    url: "${server}/allure-docker-service/login",
    httpMode: 'POST',
    contentType: 'APPLICATION_JSON',
    requestBody: JsonOutput.toJson([username: user, password: password]),
    validResponseCodes: '200'
  )

  // 3) cookies + csrf (super simple)
  List<String> setCookies = []
  def sc = loginResp?.headers?."Set-Cookie"
  if (sc instanceof String) setCookies = [sc]
  else if (sc instanceof Collection) setCookies = sc as List<String>

  def findCookie = { name -> setCookies.find { it.startsWith("${name}=") } ?: '' }
  def cookieVal  = { line -> line ? line.split(';')[0].split('=')[1] : '' }

  String accessLine = findCookie('access_token_cookie')
  String csrf       = cookieVal(findCookie('csrf_access_token'))
  String accessHdr  = accessLine ?: ''

  // 4) send results
  httpRequest(
    url: "${server}/allure-docker-service/send-results?project_id=${projectId}",
    httpMode: 'POST',
    contentType: 'APPLICATION_JSON',
    customHeaders: [
      [name: 'Cookie', value: accessHdr],
      [name: 'X-CSRF-TOKEN', value: csrf]
    ],
    requestBody: resultsJson,
    validResponseCodes: '200'
  )

  // 5) generate report
  def enc = { URLEncoder.encode(it ?: '', 'UTF-8') }
  def genUrl = "${server}/allure-docker-service/generate-report" +
               "?project_id=${projectId}&execution_name=${enc(executionName)}&execution_from=${enc(executionFrom)}&execution_type=${enc(executionType)}"

  def genResp = httpRequest(
    url: genUrl,
    httpMode: 'GET',
    contentType: 'APPLICATION_JSON',
    customHeaders: [
      [name: 'Cookie', value: accessHdr],
      [name: 'X-CSRF-TOKEN', value: csrf]
    ],
    validResponseCodes: '200'
  )

  return genResp // pipeline can echo genResp.content if needed
}