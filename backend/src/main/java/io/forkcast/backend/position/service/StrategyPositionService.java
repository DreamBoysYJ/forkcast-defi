package io.forkcast.backend.position.service;

import io.forkcast.backend.chain.client.EventLogDecoder;
import io.forkcast.backend.position.domain.StrategyPosition;
import io.forkcast.backend.position.repository.StrategyPositionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class StrategyPositionService {

  private final StrategyPositionRepository strategyPositionRepository;

  public StrategyPositionService(StrategyPositionRepository strategyPositionRepository) {
    this.strategyPositionRepository = strategyPositionRepository;
  }


  public void applyOpened(EventLogDecoder.DecodedEvent event) {
    if (!"PositionOpened".equals(event.eventName())) {
      throw new IllegalArgumentException("only PositionOpened is supproted");
    }

    long tokenId = event.uint256(4).longValueExact();

    if (strategyPositionRepository.existsById(tokenId)) {
      return ;
    }

    StrategyPosition strategyPosition = new StrategyPosition(
      tokenId,
      event.userAddress(),
      event.vaultAddress(),
      event.address(0),
      event.address(2),
      true,
      event.blockNumber(),
      null,
      event.txHash(),
      null
    );

    strategyPositionRepository.save(strategyPosition);
  }

  public void applyClosed(EventLogDecoder.DecodedEvent event) {
    if (!"PositionClosed".equals(event.eventName())) {
      throw new IllegalArgumentException("only PositionClosed is supported");
    }

    long tokenId = event.indexedUint256(2).longValueExact();
    StrategyPosition strategyPosition = strategyPositionRepository.findById(tokenId)
      .orElseThrow(() -> new IllegalArgumentException(
        "strategy_position not found: tokenId = " + tokenId
      ));

    if (!strategyPosition.isOpen()) {
      return;
    }

    strategyPosition.close(event.blockNumber(), event.txHash());
  }
}
