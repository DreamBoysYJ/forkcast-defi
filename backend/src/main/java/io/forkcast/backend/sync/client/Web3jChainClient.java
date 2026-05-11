package io.forkcast.backend.sync.client;

import org.springframework.stereotype.Component;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterNumber;
import org.web3j.protocol.core.methods.request.EthFilter;
import org.web3j.protocol.core.methods.response.Log;

import java.io.IOException;
import java.util.List;
import java.util.stream.Collectors;

@Component
public class Web3jChainClient {

  private final Web3j web3j;

  public Web3jChainClient(Web3j web3j) {
    this.web3j = web3j;
  }

  public long getLatestBlockNumber() {
    try {
      return web3j.ethBlockNumber()
        .send()
        .getBlockNumber()
        .longValue();
    } catch (IOException e) {
      throw new IllegalStateException("failed to fetch latest block number", e);
    }
  }

  public List<Log> getLogs(
    String contractAddress,
    List<String> topic0List,
    long fromBlock,
    long toBlock
  ) {
    try {
      EthFilter filter = new EthFilter(
        new DefaultBlockParameterNumber(fromBlock),
        new DefaultBlockParameterNumber(toBlock),
        contractAddress
      );

      if (topic0List != null && !topic0List.isEmpty()) {
        filter.addOptionalTopics(topic0List.toArray(String[]::new));
      }

      return web3j.ethGetLogs(filter)
        .send()
        .getLogs()
        .stream()
        .map(logResult -> (Log) logResult.get())
        .collect(Collectors.toList());
    } catch (IOException e) {
      throw new IllegalStateException("failed to fetch logs", e);
    }
  }
}
