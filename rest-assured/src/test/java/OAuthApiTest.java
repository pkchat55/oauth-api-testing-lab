import io.restassured.response.Response;
import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

public class OAuthApiTest {

    private static final String TOKEN_URL =
            "http://localhost:8080/realms/api-testing/protocol/openid-connect/token";

    private static final String API_URL =
            "http://localhost:8000/users";

    private static Response requestToken(String grantType, String clientId, String clientSecret) {
        return given()
                    .contentType("application/x-www-form-urlencoded")
                    .formParam("grant_type", grantType)
                    .formParam("client_id", clientId)
                    .formParam("client_secret", clientSecret)
                .when()
                    .post(TOKEN_URL);
    }

    public static String getAccessToken() {

        String clientId = System.getenv("CLIENT_ID");
        String clientSecret = System.getenv("CLIENT_SECRET");

        if (clientId == null || clientSecret == null) {
            throw new RuntimeException(
                    "CLIENT_ID and CLIENT_SECRET environment variables are required."
            );
        }

        Response response = requestToken("client_credentials", clientId, clientSecret);
        response.then().statusCode(200);

        return response.jsonPath().getString("access_token");
    }

    private static String getNoRoleAccessToken() {

        String clientId = System.getenv("CLIENT_ID_NOROLE");
        String clientSecret = System.getenv("CLIENT_SECRET_NOROLE");

        if (clientId == null || clientSecret == null) {
            throw new RuntimeException(
                    "CLIENT_ID_NOROLE and CLIENT_SECRET_NOROLE environment variables are required."
            );
        }

        Response response = requestToken("client_credentials", clientId, clientSecret);
        response.then().statusCode(200);

        return response.jsonPath().getString("access_token");
    }

    @Test
    public void apiWithoutToken_returns401() {
        given()
        .when()
            .get(API_URL)
        .then()
            .statusCode(401)
            .body("detail", equalTo("Missing Authorization header"));
    }

    @Test
    public void apiWithMalformedToken_returns401() {
        // Real JWT validation (signature via Keycloak JWKS) now rejects this.
        given()
            .header("Authorization", "Bearer invalid.token.value")
        .when()
            .get(API_URL)
        .then()
            .statusCode(401)
            .body("detail", equalTo("Malformed token"));
    }

    @Test
    public void apiWithValidToken_returns200() {
        String accessToken = getAccessToken();

        given()
            .header("Authorization", "Bearer " + accessToken)
        .when()
            .get(API_URL)
        .then()
            .statusCode(200)
            .body("message", equalTo("Authenticated successfully"));
    }

    @Test
    public void apiWithInsufficientRole_returns403() {
        // This client's service account has no "api-user" realm role assigned.
        String accessToken = getNoRoleAccessToken();

        given()
            .header("Authorization", "Bearer " + accessToken)
        .when()
            .get(API_URL)
        .then()
            .statusCode(403)
            .body("detail", equalTo("Missing required role: api-user"));
    }

    @Test
    public void apiWithExpiredToken_returns401() throws InterruptedException {
        // Client1's access-token lifespan is overridden to 6s in Keycloak so this
        // test observes real token expiry instead of forging a signature.
        String accessToken = getAccessToken();

        Thread.sleep(8000);

        given()
            .header("Authorization", "Bearer " + accessToken)
        .when()
            .get(API_URL)
        .then()
            .statusCode(401)
            .body("detail", equalTo("Token expired"));
    }

    @Test
    public void tokenRequestWithWrongClientSecret_returns401() {
        String clientId = System.getenv("CLIENT_ID");

        requestToken("client_credentials", clientId, "totally-wrong-secret")
            .then()
                .statusCode(401);
    }

    @Test
    public void tokenRequestWithInvalidClientId_returns401() {
        requestToken("client_credentials", "no-such-client", "does-not-matter")
            .then()
                .statusCode(401);
    }

    @Test
    public void tokenRequestWithUnsupportedGrantType_returns400() {
        String clientId = System.getenv("CLIENT_ID");
        String clientSecret = System.getenv("CLIENT_SECRET");

        requestToken("totally_unsupported_grant", clientId, clientSecret)
            .then()
                .statusCode(400)
                .body("error", equalTo("unsupported_grant_type"));
    }
}
