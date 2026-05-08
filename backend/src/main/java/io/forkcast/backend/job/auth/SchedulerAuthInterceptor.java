package io.forkcast.backend.job.auth;


import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

@Component
public class SchedulerAuthInterceptor implements HandlerInterceptor {

  private final SchedulerAuthProperties properties;
  private final SchedulerTokenVerifier tokenVerifier;

  public SchedulerAuthInterceptor(SchedulerAuthProperties properties, SchedulerTokenVerifier tokenVerifier) {
    this.properties = properties;
    this.tokenVerifier = tokenVerifier;
  }

  @Override
  public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws IOException {

    if (!properties.isEnabled()) {
      return true;
    }
    String authorization = request.getHeader(HttpHeaders.AUTHORIZATION);
    if (authorization == null || !authorization.startsWith("Bearer ")) {
      writeError(response, HttpServletResponse.SC_UNAUTHORIZED, "UNAUTHORIZED", "Missing bearer token");
      return false;
    }

    String rawToken = authorization.substring("Bearer ".length()).trim();

    if (rawToken.isEmpty()) {
      writeError(response, HttpServletResponse.SC_UNAUTHORIZED, "UNAUTHORIZED",
        "Missing bearer token");
      return false;
    }

    try {
      tokenVerifier.verify(rawToken);
      return true;
    } catch (IllegalArgumentException e) {
      writeError(response, HttpServletResponse.SC_FORBIDDEN, "FORBIDDEN",
        "Invalid scheduler token");
      return false;
    }
  }

  private void writeError(HttpServletResponse response, int status, String code, String message) throws IOException {
    response.setStatus(status);
    response.setCharacterEncoding(StandardCharsets.UTF_8.name());
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    response.getWriter().write("""
      {"code":"%s","message":"%s"}
      """.formatted(code, message));
  }
}
