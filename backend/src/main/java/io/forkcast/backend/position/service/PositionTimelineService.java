package io.forkcast.backend.position.service;

import io.forkcast.backend.chain.client.EventLogDecoder;
import io.forkcast.backend.position.domain.PositionTimeline;
import io.forkcast.backend.position.domain.StrategyPosition;
import io.forkcast.backend.position.repository.PositionTimelineRepository;
import io.forkcast.backend.position.repository.StrategyPositionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
@Transactional
public class PositionTimelineService {

  private final PositionTimelineRepository positionTimelineRepository;
  private final StrategyPositionRepository strategyPositionRepository;
  private final ObjectMapper objectMapper;

  public PositionTimelineService(
    PositionTimelineRepository positionTimelineRepository,
    StrategyPositionRepository strategyPositionRepository,
    ObjectMapper objectMapper
  ) {
    this.positionTimelineRepository = positionTimelineRepository;
    this.strategyPositionRepository = strategyPositionRepository;
    this.objectMapper = objectMapper;
  }

  public void appendOpened(EventLogDecoder.DecodedEvent event) {
    long tokenId = event.uint256(4).longValueExact();

    positionTimelineRepository.save(
      new PositionTimeline(
        tokenId,
        "OPENED",
        event.txHash(),
        event.blockNumber(),
        Instant.now(),
        event.userAddress(),
        event.vaultAddress(),
        toJson(Map.of(
          "supplyAsset", event.address(0),
          "supplyAmount", event.uint256(1).toString(),
          "borrowAsset", event.address(2),
          "borrowedAmount", event.uint256(3).toString(),
          "amount0ForLp", event.uint256(5).toString(),
          "amount1ForLp", event.uint256(6).toString(),
          "spent0", event.uint256(7).toString(),
          "spent1", event.uint256(8).toString()
        ))
      )
    );
  }

  public void appendClosed(EventLogDecoder.DecodedEvent event) {
    long tokenId = event.indexedUint256(2).longValueExact();

    positionTimelineRepository.save(
      new PositionTimeline(
        tokenId,
        "CLOSED",
        event.txHash(),
        event.blockNumber(),
        Instant.now(),
        event.userAddress(),
        event.vaultAddress(),
        toJson(Map.of(
          "supplyAsset", event.address(0),
          "borrowAsset", event.address(1),
          "amountSupplyReturned", event.uint256(2).toString(),
          "amountBorrowReturned", event.uint256(3).toString()
        ))
      )
    );
  }

  public void appendFeesCollected(EventLogDecoder.DecodedEvent event) {
    long tokenId = event.indexedUint256(1).longValueExact();

    StrategyPosition strategyPosition = strategyPositionRepository.findById(tokenId)
      .orElseThrow(() -> new IllegalArgumentException(
        "strategy_position not found: tokenId=" + tokenId
      ));

    positionTimelineRepository.save(
      new PositionTimeline(
        tokenId,
        "FEES_COLLECTED",
        event.txHash(),
        event.blockNumber(),
        Instant.now(),
        event.userAddress(),
        strategyPosition.getVaultAddress(),
        toJson(Map.of(
          "token0", event.address(0),
          "token1", event.address(1),
          "amount0", event.uint256(2).toString(),
          "amount1", event.uint256(3).toString()
        ))
      )
    );
  }

  private String toJson(Map<String, Object> metadata) {
    try {
      return objectMapper.writeValueAsString(new LinkedHashMap<>(metadata));
    } catch (JacksonException e) {
      throw new IllegalStateException("failed to serialize metadata_json", e);
    }
  }
}
