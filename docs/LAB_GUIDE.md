# OAuth 2.0 API Testing Lab --- Keycloak + FastAPI + Postman + Rest Assured

A hands-on local lab for learning Client ID, Client Secret, OAuth 2.0
Access Tokens, protected APIs, 401/200 responses, Postman, and Rest
Assured.

## Architecture

``` text
Postman / Rest Assured
        |
        | Client ID + Client Secret
        v
     Keycloak
 Authorization Server
        |
        | Access Token
        v
   Protected API
        |
   Bearer <token>
        |
        v
      200 OK

No token -> 401 Unauthorized
```

## Prerequisites

Install:

-   Visual Studio Code
-   Docker Desktop
-   Python 3.10+
-   Postman
-   Java 17+
-   Maven

Verify:

``` bash
docker --version
python3 --version
java -version
mvn -version
```

## 1. Start Keycloak

Open the VS Code Terminal:

``` bash
docker run --name keycloak -p 127.0.0.1:8080:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin quay.io/keycloak/keycloak:26.7.3 start-dev
```

Open:

``` text
http://localhost:8080
```

Login:

``` text
Username: admin
Password: admin
```

For an existing container:

``` bash
docker start keycloak
```

Check:

``` bash
docker ps
```

`start-dev` is for local development/testing, not production.

## 2. Create a Realm

In Keycloak:

1.  Open the realm selector.
2.  Create a new realm.
3.  Name it:

``` text
api-testing
```

## 3. Register the OAuth Client

Go to:

``` text
Clients -> Create client
```

Use:

``` text
Client type: OpenID Connect
Client ID: api-automation-client
```

Enable client authentication and configure the client as confidential.

Save.

## 4. Get the Client Secret

Open:

``` text
Clients -> api-automation-client -> Credentials
```

You should see:

``` text
Client ID: api-automation-client
Client Secret: <generated secret>
```

The Client ID identifies the application. The Client Secret
authenticates a confidential application.

Never commit the secret to Git.

## 5. Enable Service Account / Client Credentials

Configure the client for service-account/client-credentials
authentication.

This gives the following flow:

``` text
Automation Client
      |
      | Client ID + Client Secret
      v
Keycloak
      |
      | Access Token
      v
Protected API
```

No human login is required for this application-to-application flow.

## 6. Create the FastAPI Project

Create this structure:

``` text
oauth-api-testing-lab/
├── README.md
├── api/
│   ├── app.py
│   └── requirements.txt
└── rest-assured/
    ├── pom.xml
    └── src/test/java/OAuthApiTest.java
```

Create `api/requirements.txt`:

``` text
fastapi
uvicorn
```

Install:

``` bash
cd api
python3 -m pip install -r requirements.txt
```

Create `api/app.py`:

``` python
from fastapi import FastAPI, Header, HTTPException

app = FastAPI()


@app.get("/users")
def get_users(authorization: str | None = Header(default=None)):

    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Missing Authorization header"
        )

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Invalid Authorization header"
        )

    token = authorization.replace("Bearer ", "")

    if not token:
        raise HTTPException(
            status_code=401,
            detail="Missing token"
        )

    return {
        "message": "Authenticated successfully",
        "users": [
            {
                "id": 1,
                "name": "Test User"
            }
        ]
    }
```

This demo only checks that a Bearer token exists. It intentionally does
not validate the JWT cryptographically. A production API must validate
signature, issuer, audience, expiry, scopes/roles, etc.

## 7. Start the API

From the `api` directory:

``` bash
uvicorn app:app --reload --port 8000
```

API:

``` text
http://localhost:8000/users
```

Swagger:

``` text
http://localhost:8000/docs
```

## 8. Test Without a Token

In Postman:

``` http
GET http://localhost:8000/users
```

Do not add Authorization.

Expected:

``` text
401 Unauthorized
```

Response:

``` json
{
  "detail": "Missing Authorization header"
}
```

## 9. Get an Access Token

Token endpoint:

``` text
http://localhost:8080/realms/api-testing/protocol/openid-connect/token
```

Postman:

``` text
POST <token endpoint>
```

Body:

``` text
x-www-form-urlencoded
```

Parameters:

``` text
grant_type=client_credentials
client_id=api-automation-client
client_secret=<YOUR_CLIENT_SECRET>
```

Expected response:

``` json
{
  "access_token": "eyJ...",
  "expires_in": 300,
  "token_type": "Bearer"
}
```

Copy the `access_token`.

## 10. Call the Protected API

In Postman:

``` http
GET http://localhost:8000/users
```

Authorization:

``` text
Type: Bearer Token
Token: <ACCESS_TOKEN>
```

Expected:

``` text
200 OK
```

Response:

``` json
{
  "message": "Authenticated successfully",
  "users": [
    {
      "id": 1,
      "name": "Test User"
    }
  ]
}
```

## 11. Environment Variables

Do not hardcode credentials.

Mac/Linux:

``` bash
export CLIENT_ID="api-automation-client"
export CLIENT_SECRET="<YOUR_SECRET>"
```

Windows PowerShell:

``` powershell
$env:CLIENT_ID="api-automation-client"
$env:CLIENT_SECRET="<YOUR_SECRET>"
```

Java can read them with:

``` java
System.getenv("CLIENT_ID");
System.getenv("CLIENT_SECRET");
```

For CI/CD, use encrypted secret storage such as Jenkins Credentials,
GitHub Actions Secrets, GitLab CI/CD Variables, Azure Key Vault, or AWS
Secrets Manager.

## 12. Rest Assured

Create `rest-assured/pom.xml`:

``` xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">

    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>oauth-api-testing</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>io.rest-assured</groupId>
            <artifactId>rest-assured</artifactId>
            <version>5.5.6</version>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.13.4</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
```

Create `rest-assured/src/test/java/OAuthApiTest.java`:

``` java
import io.restassured.response.Response;

import static io.restassured.RestAssured.given;

public class OAuthApiTest {

    private static final String TOKEN_URL =
            "http://localhost:8080/realms/api-testing/protocol/openid-connect/token";

    private static final String API_URL =
            "http://localhost:8000/users";

    public static String getAccessToken() {

        String clientId = System.getenv("CLIENT_ID");
        String clientSecret = System.getenv("CLIENT_SECRET");

        if (clientId == null || clientSecret == null) {
            throw new RuntimeException(
                    "CLIENT_ID and CLIENT_SECRET environment variables are required."
            );
        }

        Response response =
                given()
                    .contentType("application/x-www-form-urlencoded")
                    .formParam("grant_type", "client_credentials")
                    .formParam("client_id", clientId)
                    .formParam("client_secret", clientSecret)
                .when()
                    .post(TOKEN_URL);

        response.then().statusCode(200);

        return response.jsonPath().getString("access_token");
    }
}
```

## 13. Key Test Scenarios

  Test                        Expected
  ------------------------- ----------
  API without token                401
  API with invalid token           401
  API with expired token           401
  API with valid token             200
  Insufficient scope/role          403
  Wrong Client Secret          401/400
  Invalid Client ID            401/400
  Unsupported grant type           400

## 14. 401 vs 403

`401 Unauthorized` generally means authentication is missing or invalid:

-   No token
-   Invalid token
-   Expired token
-   Malformed token

`403 Forbidden` generally means authentication succeeded but the caller
lacks permission:

``` text
Token role = user
API requires role = admin
```

## 15. Client Credentials vs Refresh Token

For this lab we use:

``` text
client_credentials
```

The normal flow is:

``` text
Client ID + Client Secret
        |
        v
Keycloak
        |
        v
Access Token
        |
        v
API
```

When the access token expires, the application normally requests another
access token.

Do not expect a refresh token in the normal client-credentials flow.
Refresh tokens are more commonly used in user-delegated OAuth flows such
as Authorization Code.

## 16. Production Considerations

A production API should validate:

``` text
JWT signature
Issuer (iss)
Audience (aud)
Expiration (exp)
Scopes
Roles
```

It should also:

-   Use HTTPS.
-   Keep Client Secrets in a secret manager.
-   Never commit credentials to Git.
-   Rotate secrets.
-   Apply least-privilege scopes/roles.
-   Avoid printing tokens/secrets in CI logs.
-   Validate token audience and issuer.
-   Handle token expiry safely.

## 17. Interview Explanation

A strong explanation is:

> Client ID and Client Secret are credentials associated with an
> application registered with an OAuth 2.0/OpenID Connect Identity
> Provider. The Client ID identifies the application, while the Client
> Secret authenticates a confidential client. In the client-credentials
> flow, the automation framework sends these credentials to the token
> endpoint and receives an access token. The access token is then
> supplied as a Bearer token to protected APIs. In automation,
> credentials should be stored in a secure CI/CD secret store rather
> than source control.

## 18. Final Flow

``` text
Application Registration
        |
        v
Client ID + Client Secret
        |
        v
Token Request
        |
        v
Keycloak Authorization Server
        |
        v
Access Token
        |
        v
Authorization: Bearer <token>
        |
        v
Protected API
     /       No Token    Valid Token
   |            |
  401          200
```

## 19. Next Advanced Exercise

After this basic lab works, implement real JWT validation in FastAPI
using Keycloak's JWKS/public keys.

Then add:

-   JWT signature validation
-   Issuer validation
-   Audience validation
-   Token expiry tests
-   Scope validation
-   Role-based authorization
-   401/403 negative tests
-   Rest Assured TokenManager
-   Token caching
-   Automatic token renewal
-   Jenkins/GitLab CI integration

This will turn the lab into a realistic enterprise API security
automation project.
