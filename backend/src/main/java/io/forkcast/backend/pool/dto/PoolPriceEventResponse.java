package io.forkcast.backend.pool.dto;

import io.forkcast.backend.pool.domain.PoolPriceEvent;

import java.time.Instant;

public record PoolPriceEventResponse(
  String poolId,
  int tick,
  String sqrtPriceX96,
  Instant eventTimestamp,
  String txHash,
  long blockNumber
) {
  public static PoolPriceEventResponse from(PoolPriceEvent event) {
    return new PoolPriceEventResponse(
      event.getPoolId(),
      event.getTick(),
      event.getSqrtPriceX96().toString(),
      event.getEventTimestamp(),
      event.getTxHash(),
      event.getBlockNumber()
    );
  }

}
