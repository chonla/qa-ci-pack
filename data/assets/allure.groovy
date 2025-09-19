// ===== Helper Imports =====
import groovy.json.JsonOutput

// ===== Custom class
class Result { String file_name; String content_base64 }

// ===== Helper Methods =====
String build_allure_results_json(pattern) {
    def results = []
    def files = findFiles(glob: pattern)
    files.each {
        def b64_content = readFile file: "${it.path}", encoding: 'Base64'
        if (!b64_content.trim().isEmpty()) {
            results.add(new Result(file_name: "${it.name}", content_base64: b64_content))
        } else {
            print("Empty File skipped: ${it.path}")
        }
    }
    JsonOutput.toJson(results: results)
}

Object login_to_allure_docker_service() {
    def body = JsonOutput.toJson([username: env.ALLURE_USER, password: env.ALLURE_PASSWORD])
    httpRequest url: "${env.ALLURE_API}/allure-docker-service/login",
                httpMode: 'POST',
                contentType: 'APPLICATION_JSON',
                requestBody: body,
                consoleLogResponseBody: true,
                validResponseCodes: '200'
}

Object get_cookies(response) {
    def cookies_map = [:]
    def cookies = response.headers.get('Set-Cookie')
    cookies.each {
        def cookie = it.substring(0, it.indexOf(';'))
        def cookie_key = cookie.substring(0, cookie.indexOf('='))
        cookies_map[cookie_key] = it
    }
    cookies_map
}

Object get_cookie_value(cookie) {
    def simple_cookie = cookie.substring(0, cookie.indexOf(';'))
    return simple_cookie.substring(simple_cookie.indexOf('=') + 1, simple_cookie.length())
}

def get_csrf_from(jar) {
    return jar['csrf_access_token'] ?: ''
}

Object send_results_to_allure_docker_service(allure_server_url, cookies, csrf_access_token, project_id, results_json) {
    httpRequest url: "${allure_server_url}/allure-docker-service/send-results?project_id=${project_id}",
                httpMode: 'POST',
                contentType: 'APPLICATION_JSON',
                customHeaders: [
                    [ name: 'Cookie', value: cookies['access_token_cookie'] ],
                    [ name: 'X-CSRF-TOKEN', value: csrf_access_token ]
                ],
                requestBody: results_json,
                consoleLogResponseBody: true,
                validResponseCodes: '200'
}

Object generate_allure_report(allure_server_url, cookies, csrf_access_token, project_id, execution_name, execution_from, execution_type) {
    execution_name = URLEncoder.encode(execution_name, 'UTF-8')
    execution_from = URLEncoder.encode(execution_from, 'UTF-8')
    execution_type = URLEncoder.encode(execution_type, 'UTF-8')

    httpRequest url: "${allure_server_url}/allure-docker-service/generate-report?project_id=${project_id}&execution_name=${execution_name}&execution_from=${execution_from}&execution_type=${execution_type}",
                httpMode: 'GET',
                contentType: 'APPLICATION_JSON',
                customHeaders: [
                    [ name: 'Cookie', value: cookies['access_token_cookie'] ],
                    [ name: 'X-CSRF-TOKEN', value: csrf_access_token ]
                ],
                consoleLogResponseBody: true,
                validResponseCodes: '200'
}
