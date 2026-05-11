package io.forkcast.backend.sync.config;


import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.http.HttpService;

@Configuration
public class Web3jConfig {


  @Bean
  Web3j web3j(SyncProperties syncProperties) {
    return Web3j.build(new HttpService(syncProperties.getRpc().getUrl()));
  }
}
