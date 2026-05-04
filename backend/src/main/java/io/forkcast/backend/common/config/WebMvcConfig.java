package io.forkcast.backend.common.config;


import io.forkcast.backend.job.auth.SchedulerAuthInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

  private final SchedulerAuthInterceptor schedulerAuthInterceptor;
  private final CorsProperties corsProperties;


  public WebMvcConfig(SchedulerAuthInterceptor schedulerAuthInterceptor, CorsProperties corsProperties) {
    this.schedulerAuthInterceptor = schedulerAuthInterceptor;
    this.corsProperties = corsProperties;
  }

  @Override
  public void addCorsMappings(CorsRegistry registry) {
    registry.addMapping("/api/**")
      .allowedOrigins(parseAllowedOrigins())
      .allowedMethods("GET", "POST", "OPTIONS")
      .allowedHeaders("*");
  }

  private String[] parseAllowedOrigins() {
    return corsProperties.getAllowedOrigins().split(",");
  }



  @Override
  public void addInterceptors(InterceptorRegistry registry) {
    registry.addInterceptor(schedulerAuthInterceptor)
      .addPathPatterns("/internal/jobs/**");
  }
}
