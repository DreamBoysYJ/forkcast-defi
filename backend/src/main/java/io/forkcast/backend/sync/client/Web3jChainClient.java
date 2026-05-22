package io.forkcast.backend.sync.client;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterNumber;
import org.web3j.protocol.core.methods.request.EthFilter;
import org.web3j.protocol.core.methods.response.EthBlock;
import org.web3j.protocol.core.methods.response.Log;

import java.time.Instant;
import java.util.List;
import java.util.stream.Collectors;

@Component
@Slf4j
public class Web3jChainClient {

  private static final int MAX_RETRY_ATTEMPTS = 3;
  private static final long INITIAL_RETRY_DELAY_MS = 1_000L;

  private final Web3j web3j;

  public Web3jChainClient(Web3j web3j) {
    this.web3j = web3j;
  }

  public long getLatestBlockNumber() {
    return withRetry("ethBlockNumber", () ->
      web3j.ethBlockNumber().send().getBlockNumber().longValue()
    );
  }

  public Instant getBlockTimestamp(long blockNumber) {
    return withRetry("ethGetBlockByNumber(" + blockNumber + ")", () -> {
      EthBlock response = web3j.ethGetBlockByNumber(
        new DefaultBlockParameterNumber(blockNumber), false).send();
      return Instant.ofEpochSecond(response.getBlock().getTimestamp().longValue());
    });
  }

  public List<Log> getLogs(
    String contractAddress,
    List<String> topic0List,
    long fromBlock,
    long toBlock
  ) {
    return withRetry("ethGetLogs(" + fromBlock + "-" + toBlock + ")", () -> {
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
    });
  }

  private <T> T withRetry(String operation, RpcCall<T> call) {
    long delayMs = INITIAL_RETRY_DELAY_MS;
    Exception lastException = null;

    for (int attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++) {
      try {
        return call.execute();
      } catch (Exception e) {
        lastException = e;
        if (attempt < MAX_RETRY_ATTEMPTS) {
          log.warn("RPC call '{}' failed (attempt {}/{}), retrying in {}ms",
            operation, attempt, MAX_RETRY_ATTEMPTS, delayMs, e);
          try {
            Thread.sleep(delayMs);
          } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            break;
          }
          delayMs *= 2;
        }
      }
    }
    throw new IllegalStateException(
      "RPC call '" + operation + "' failed after " + MAX_RETRY_ATTEMPTS + " attempts", lastException);
  }

  @FunctionalInterface
  private interface RpcCall<T> {
    T execute() throws Exception;
  }
}
