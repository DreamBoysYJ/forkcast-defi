package io.forkcast.backend.job.auth;


import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "scheduler.auth")
public class SchedulerAuthProperties {

  private boolean enabled;
  private String allowedServiceAccount;
  private String audience;

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public String getAllowedServiceAccount() {
    return allowedServiceAccount;
  }

  public void setAllowedServiceAccount(String allowedServiceAccount) {
    this.allowedServiceAccount = allowedServiceAccount;
  }

  public String getAudience() {
    return audience;
  }

  public void setAudience(String audience) {
    this.audience = audience;
  }

}
