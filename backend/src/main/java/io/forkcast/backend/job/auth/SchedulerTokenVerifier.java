package io.forkcast.backend.job.auth;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.gson.GsonFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.Collections;

@Component
public class SchedulerTokenVerifier {

  private final SchedulerAuthProperties properties;

  public SchedulerTokenVerifier(SchedulerAuthProperties properties) {
    this.properties = properties;
  }

  public void verify(String rawToken) {
    GoogleIdTokenVerifier verifier = new GoogleIdTokenVerifier.Builder(
      new NetHttpTransport(),
      GsonFactory.getDefaultInstance()
    )
      .setAudience(Collections.singletonList(properties.getAudience())).build();

    GoogleIdToken idToken = verifyingGoogleToken(verifier, rawToken);
    GoogleIdToken.Payload payload = idToken.getPayload();

    String email = payload.getEmail();
    boolean emailVerified = Boolean.TRUE.equals(payload.getEmailVerified());
    if (!emailVerified) {
      throw new IllegalArgumentException("Scheduler token email is not verified");
    }
    if (email == null || !email.equalsIgnoreCase(properties.getAllowedServiceAccount())) {
      throw new IllegalArgumentException("Scheduler service account is not allowed");
    }
  }

  private GoogleIdToken verifyingGoogleToken(GoogleIdTokenVerifier verifier, String rawToken) {
    try {
      GoogleIdToken idToken = verifier.verify(rawToken);
      if (idToken == null) {
        throw new IllegalArgumentException("Invalid Google Id token");
      }

      return idToken;
    } catch (GeneralSecurityException | IOException exception) {
      throw new IllegalArgumentException("failed to verify Google ID token", exception);
    }
  }
}
