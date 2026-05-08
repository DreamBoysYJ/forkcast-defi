package io.forkcast.backend.position.dto;

import io.forkcast.backend.position.domain.PositionTimeline;

import java.time.Instant;

public record PositionTimelineResponse(
  Long tokenId,
  String eventType,
  String txHash,
  long blockNumber,
  Instant eventTimestamp,
  String userAddress,
  String vaultAddress,
  String metadata
) {
  public static PositionTimelineResponse from(PositionTimeline timeline) {
    return new PositionTimelineResponse(
      timeline.getTokenId(),
      timeline.getEventType(),
      timeline.getTxHash(),
      timeline.getBlockNumber(),
      timeline.getEventTimestamp(),
      timeline.getUserAddress(),
      timeline.getVaultAddress(),
      timeline.getMetadataJson()
    );
  }
}
