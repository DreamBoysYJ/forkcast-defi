package io.forkcast.backend.sync.config;


import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "sync")
public class SyncProperties {

  private final Rpc rpc = new Rpc();
  private final Contracts contracts = new Contracts();
  private long bootstrapWindowBlocks;


  public Rpc getRpc() {
    return rpc;
  }

  public Contracts getContracts() {
    return contracts;
  }

  public long getBootstrapWindowBlocks() {
    return bootstrapWindowBlocks;
  }

  public void setBootstrapWindowBlocks(long bootstrapWindowBlocks) {
    this.bootstrapWindowBlocks = bootstrapWindowBlocks;
  }

  public static class Rpc {
    private String url;

    public String getUrl() {
      return url;
    }



    public void setUrl(String url) {
      this.url = url;
    }
  }

  public static class Contracts {
    private String strategyRouterAddress;
    private String hookAddress;

    public String getStrategyRouterAddress() {
      return strategyRouterAddress;
    }

    public void setStrategyRouterAddress(String strategyRouterAddress) {
      this.strategyRouterAddress = strategyRouterAddress;
    }

    public String getHookAddress() {
      return hookAddress;
    }

    public void setHookAddress(String hookAddress) {
      this.hookAddress = hookAddress;
    }
  }
}
